import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../models/class_session.dart';
import 'database_service.dart';

/// Service responsible for initializing notification channels, requesting permissions,
/// and scheduling exact weekly recurring push notifications before lecture times.
class NotificationService {
  static final NotificationService instance = NotificationService._internal();
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  NotificationService._internal();

  static const String channelId = 'campus_schedule_channel';
  static const String channelName = 'Class Reminders';
  static const String channelDescription = 'Exact notifications scheduled 10-15 minutes prior to lectures';

  static const String prefNotificationsEnabled = 'pref_notifications_enabled';
  static const String prefLeadMinutes = 'pref_lead_minutes';

  bool _isInitialized = false;

  /// Initialize local notifications, configure timezones and notification channels.
  Future<void> initialize() async {
    if (_isInitialized) return;

    // 1. Initialize timezone database
    tz.initializeTimeZones();
    try {
      final String timeZoneName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timeZoneName));
    } catch (e) {
      debugPrint('Fallback to UTC timezone due to error: $e');
      tz.setLocalLocation(tz.getLocation('UTC'));
    }

    // 2. Android Initialization Settings
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // 3. iOS / Darwin Initialization Settings
    const DarwinInitializationSettings darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
    );

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // 4. Create High Importance Android Notification Channel
    if (Platform.isAndroid) {
      final AndroidNotificationChannel channel = const AndroidNotificationChannel(
        channelId,
        channelName,
        description: channelDescription,
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      );

      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }

    _isInitialized = true;
  }

  void _onNotificationTapped(NotificationResponse response) {
    debugPrint('Notification tapped with payload: ${response.payload}');
  }

  /// Explicitly requests POST_NOTIFICATIONS and Exact Alarm permissions on Android 13+ & iOS.
  Future<bool> requestPermissions() async {
    bool? granted = false;

    if (Platform.isAndroid) {
      final androidImplementation = _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

      // Request push notification permission (Android 13+)
      granted = await androidImplementation?.requestNotificationsPermission();

      // Request exact alarm permission (Android 12+)
      await androidImplementation?.requestExactAlarmsPermission();
    } else if (Platform.isIOS) {
      final iosImplementation = _notificationsPlugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();

      granted = await iosImplementation?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    return granted ?? true;
  }

  /// Calculates the next TZDateTime for a weekly recurring class matching dayOfWeek and start time minus lead minutes.
  tz.TZDateTime _nextInstanceOfClass(int dayOfWeek, int hour, int minute, int minutesBefore) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    
    // Convert target class time to raw DateTime on today's date
    tz.TZDateTime scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    ).subtract(Duration(minutes: minutesBefore));

    // Adjust day of week (ISO 8601: 1=Mon, ..., 7=Sun)
    while (scheduledDate.weekday != dayOfWeek || scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    return scheduledDate;
  }

  /// Schedules a weekly exact local push notification for a single lecture session.
  Future<void> scheduleClassReminder(ClassSession session, int minutesBefore) async {
    if (session.id == null) return;

    final tz.TZDateTime scheduledDate = _nextInstanceOfClass(
      session.dayOfWeek,
      session.startHour,
      session.startMinute,
      minutesBefore,
    );

    final notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.max,
        priority: Priority.high,
        ticker: 'Class Starting Soon',
        styleInformation: BigTextStyleInformation(
          'Your lecture "${session.courseName}" is starting at ${session.startTime} in ${session.locationString}.\nInstructor: ${session.instructor}',
          contentTitle: '🔔 Upcoming Class: ${session.courseCode}',
          summaryText: '${session.locationString} • in $minutesBefore mins',
        ),
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    );

    await _notificationsPlugin.zonedSchedule(
      session.id!, // Unique notification ID mapped to class ID
      '🔔 Class in $minutesBefore mins: ${session.courseCode}',
      '${session.courseName} starting at ${session.startTime} @ ${session.locationString}',
      scheduledDate,
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime, // Repeats weekly
      payload: 'class_id_${session.id}',
    );

    debugPrint('Scheduled notification for [${session.courseCode}] at $scheduledDate (Day ${session.dayOfWeek})');
  }

  /// Reschedules all notifications for all stored classes based on user preferences.
  Future<void> rescheduleAllReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final bool isEnabled = prefs.getBool(prefNotificationsEnabled) ?? true;
    final int leadMinutes = prefs.getInt(prefLeadMinutes) ?? 10;

    // Clear existing scheduled notifications first
    await cancelAllReminders();

    if (!isEnabled) {
      debugPrint('Notifications disabled by user setting. All cleared.');
      return;
    }

    final classes = await DatabaseService.instance.getAllClasses();
    for (final session in classes) {
      await scheduleClassReminder(session, leadMinutes);
    }
    debugPrint('Successfully rescheduled ${classes.length} class notifications with $leadMinutes min lead time.');
  }

  /// Cancels a specific reminder by session ID.
  Future<void> cancelReminder(int sessionId) async {
    await _notificationsPlugin.cancel(sessionId);
  }

  /// Cancels all scheduled local notifications.
  Future<void> cancelAllReminders() async {
    await _notificationsPlugin.cancelAll();
  }

  /// Sends an immediate test notification to verify audio, vibration, and channels.
  Future<void> sendTestNotification() async {
    const notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.max,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );

    await _notificationsPlugin.show(
      99999,
      '🎓 CampusSchedule Notifications Active',
      'Exact alarms and weekly lecture reminders are properly configured!',
      notificationDetails,
    );
  }
}
