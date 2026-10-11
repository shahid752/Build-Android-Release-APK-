import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;
  int _leadMinutes = 10;
  int _classCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final count = await DatabaseService.instance.getClassCount();

    setState(() {
      _notificationsEnabled = prefs.getBool(NotificationService.prefNotificationsEnabled) ?? true;
      _leadMinutes = prefs.getInt(NotificationService.prefLeadMinutes) ?? 10;
      _classCount = count;
      _isLoading = false;
    });
  }

  Future<void> _updateNotificationsEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(NotificationService.prefNotificationsEnabled, value);
    setState(() {
      _notificationsEnabled = value;
    });
    await NotificationService.instance.rescheduleAllReminders();
  }

  Future<void> _updateLeadMinutes(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(NotificationService.prefLeadMinutes, minutes);
    setState(() {
      _leadMinutes = minutes;
    });
    await NotificationService.instance.rescheduleAllReminders();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reminders set to $minutes minutes before each class.')),
      );
    }
  }

  Future<void> _testNotification() async {
    await NotificationService.instance.sendTestNotification();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sent test notification! Check your notification tray.')),
      );
    }
  }

  Future<void> _requestPermissions() async {
    final granted = await NotificationService.instance.requestPermissions();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(granted ? 'All notification permissions granted!' : 'Permissions requested.'),
        ),
      );
    }
  }

  Future<void> _clearAllData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Timetable Data?'),
        content: const Text(
          'This will delete all stored classes and cancel all scheduled alarms. You can re-import anytime.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseService.instance.clearAllClasses();
      await NotificationService.instance.cancelAllReminders();
      await _loadSettings();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Database cleared and reminders cancelled.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings & Alerts'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          // Section 1: Push Notifications & Alarms
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'NOTIFICATION ALARMS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          SwitchListTile(
            secondary: Icon(
              _notificationsEnabled ? Icons.notifications_active_rounded : Icons.notifications_off_rounded,
              color: _notificationsEnabled ? theme.colorScheme.primary : theme.colorScheme.outline,
            ),
            title: const Text('Lecture Reminders', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Receive exact push notifications before your classes start'),
            value: _notificationsEnabled,
            onChanged: _updateNotificationsEnabled,
          ),
          const Divider(),

          // Section 2: Warning Lead Time
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              'REMINDER LEAD TIME',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          RadioListTile<int>(
            title: const Text('5 Minutes Before Class'),
            subtitle: const Text('Quick alert right before walking into class'),
            value: 5,
            groupValue: _leadMinutes,
            onChanged: _notificationsEnabled ? (val) => val != null ? _updateLeadMinutes(val) : null : null,
          ),
          RadioListTile<int>(
            title: const Text('10 Minutes Before Class (Recommended)'),
            subtitle: const Text('Gives you sufficient time to reach the room/hall'),
            value: 10,
            groupValue: _leadMinutes,
            onChanged: _notificationsEnabled ? (val) => val != null ? _updateLeadMinutes(val) : null : null,
          ),
          RadioListTile<int>(
            title: const Text('15 Minutes Before Class'),
            subtitle: const Text('Best for large campuses and distant lecture halls'),
            value: 15,
            groupValue: _leadMinutes,
            onChanged: _notificationsEnabled ? (val) => val != null ? _updateLeadMinutes(val) : null : null,
          ),
          const Divider(),

          // Section 3: Diagnostic & System Permissions
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              'DIAGNOSTICS & SYSTEM',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.send_to_mobile_rounded),
            title: const Text('Send Test Notification'),
            subtitle: const Text('Verify that sound, vibration, and banner alerts work properly'),
            onTap: _testNotification,
          ),
          ListTile(
            leading: const Icon(Icons.security_rounded),
            title: const Text('Request System Permissions'),
            subtitle: const Text('Ensure exact alarms & notification rights are granted'),
            onTap: _requestPermissions,
          ),
          const Divider(),

          // Section 4: Data Management & Offline SQLite
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              'OFFLINE DATABASE',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.storage_rounded),
            title: const Text('Stored Lecture Sessions'),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$_classCount Classes',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
          ListTile(
            leading: Icon(Icons.delete_forever_rounded, color: theme.colorScheme.error),
            title: Text(
              'Clear Timetable Database',
              style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.bold),
            ),
            subtitle: const Text('Delete all stored schedule sessions and cancel all alarms'),
            onTap: _clearAllData,
          ),
          const Divider(),

          // App Info
          const Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              children: [
                Text(
                  'CampusSchedule v1.0.0',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
                ),
                SizedBox(height: 4),
                Text(
                  'Offline SQLite & Exact Notification Timetable for Students',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
