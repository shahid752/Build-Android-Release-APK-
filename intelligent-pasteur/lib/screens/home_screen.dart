import 'package:flutter/material.dart';
import '../models/class_session.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../widgets/add_edit_class_dialog.dart';
import '../widgets/day_schedule_view.dart';
import 'import_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<String> _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];
  
  Map<int, List<ClassSession>> _classesByDay = {};
  bool _isLoading = true;
  ClassSession? _nextClass;
  int _totalClassCount = 0;

  @override
  void initState() {
    super.initState();
    final todayWeekday = DateTime.now().weekday;
    final initialIndex = (todayWeekday >= 1 && todayWeekday <= 5) ? todayWeekday - 1 : 0;
    _tabController = TabController(length: _days.length, vsync: this, initialIndex: initialIndex);
    
    _loadScheduleData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadScheduleData() async {
    setState(() => _isLoading = true);

    final all = await DatabaseService.instance.getAllClasses();
    final Map<int, List<ClassSession>> grouped = {1: [], 2: [], 3: [], 4: [], 5: []};
    
    for (var session in all) {
      if (grouped.containsKey(session.dayOfWeek)) {
        grouped[session.dayOfWeek]!.add(session);
      }
    }

    final next = _findNextUpcomingClass(all);

    setState(() {
      _classesByDay = grouped;
      _totalClassCount = all.length;
      _nextClass = next;
      _isLoading = false;
    });
  }

  ClassSession? _findNextUpcomingClass(List<ClassSession> classes) {
    if (classes.isEmpty) return null;
    final now = DateTime.now();
    final currentDay = now.weekday;
    final currentMinuteOfDay = now.hour * 60 + now.minute;

    // Search today first
    final todayClasses = classes.where((c) => c.dayOfWeek == currentDay).toList();
    for (var session in todayClasses) {
      final sessionStart = session.startHour * 60 + session.startMinute;
      if (sessionStart > currentMinuteOfDay) {
        return session;
      }
    }

    // Otherwise search subsequent days in the week
    for (int d = 1; d <= 7; d++) {
      final targetDay = ((currentDay + d - 1) % 7) + 1;
      final dayMatches = classes.where((c) => c.dayOfWeek == targetDay).toList();
      if (dayMatches.isNotEmpty) {
        return dayMatches.first;
      }
    }
    return classes.first;
  }

  /// Manually add a subject to the timetable
  Future<void> _addSubjectManually() async {
    final currentDay = _tabController.index + 1;
    final newSession = await AddEditClassDialog.show(context, defaultWeekday: currentDay);
    if (newSession != null) {
      final id = await DatabaseService.instance.insertClass(newSession);
      final sessionWithId = newSession.copyWith(id: id);
      await NotificationService.instance.scheduleClassReminder(sessionWithId, 10);
      await _loadScheduleData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green.shade700,
            content: Text('Added "${newSession.courseCode}: ${newSession.courseName}" on ${newSession.dayName}'),
          ),
        );
      }
    }
  }

  /// Edit an existing subject on tap
  Future<void> _editSession(ClassSession session) async {
    final updated = await AddEditClassDialog.show(context, session: session);
    if (updated != null) {
      await DatabaseService.instance.updateClass(updated);
      await NotificationService.instance.rescheduleAllReminders();
      await _loadScheduleData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Updated "${updated.courseCode}"')),
        );
      }
    }
  }

  void _navigateToImport() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ImportScreen()),
    );
    if (result == true) {
      await _loadScheduleData();
    }
  }

  void _navigateToSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsScreen()),
    );
    await _loadScheduleData();
  }

  void _confirmDeleteSession(ClassSession session) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Class Session?'),
        content: Text('Remove "${session.courseCode} - ${session.courseName}" on ${session.dayName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () async {
              Navigator.pop(ctx);
              if (session.id != null) {
                await DatabaseService.instance.deleteClass(session.id!);
                await NotificationService.instance.cancelReminder(session.id!);
                _loadScheduleData();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Removed ${session.courseCode}')),
                  );
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.school_rounded,
                color: theme.colorScheme.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CampusSchedule',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19),
                ),
                Text(
                  'Weekly Timetable & Reminders',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Add Subject Manually',
            icon: const Icon(Icons.add_box_outlined),
            onPressed: _addSubjectManually,
          ),
          IconButton(
            tooltip: 'Import Timetable',
            icon: const Icon(Icons.file_upload_outlined),
            onPressed: _navigateToImport,
          ),
          IconButton(
            tooltip: 'Settings & Notifications',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _navigateToSettings,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: theme.colorScheme.surface,
            child: TabBar(
              controller: _tabController,
              isScrollable: false,
              labelColor: theme.colorScheme.primary,
              indicatorColor: theme.colorScheme.primary,
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 13.5),
              tabs: const [
                Tab(text: 'Mon'),
                Tab(text: 'Tue'),
                Tab(text: 'Wed'),
                Tab(text: 'Thu'),
                Tab(text: 'Fri'),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Next Upcoming Class Announcement Banner (if available)
          if (_nextClass != null && _totalClassCount > 0)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primaryContainer.withOpacity(0.7),
                    theme.colorScheme.secondaryContainer.withOpacity(0.5),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.colorScheme.primary.withOpacity(0.15)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.alarm_on_rounded, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'NEXT LECTURE • ${_nextClass!.dayName.toUpperCase()}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_nextClass!.courseCode}: ${_nextClass!.courseName}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${_nextClass!.formattedTimeSpan} @ ${_nextClass!.locationString}',
                          style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // Main TabBar View for Daily Lectures
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: List.generate(5, (index) {
                final weekday = index + 1;
                return RefreshIndicator(
                  onRefresh: _loadScheduleData,
                  child: DayScheduleView(
                    weekday: weekday,
                    dayName: _days[index],
                    classes: _classesByDay[weekday] ?? [],
                    isLoading: _isLoading,
                    onClassSelected: _editSession,
                    onImportPressed: _navigateToImport,
                    onDeleteClass: _confirmDeleteSession,
                  ),
                );
              }),
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'fab_import',
            tooltip: 'Import PDF Timetable',
            onPressed: _navigateToImport,
            child: const Icon(Icons.file_upload_outlined),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'fab_add',
            onPressed: _addSubjectManually,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add Subject'),
          ),
        ],
      ),
    );
  }
}
