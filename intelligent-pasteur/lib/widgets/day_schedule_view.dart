import 'package:flutter/material.dart';
import '../models/class_session.dart';
import 'lecture_card.dart';

/// Renders the list of scheduled lectures for a particular day of the week,
/// with empty states and interactive options.
class DayScheduleView extends StatelessWidget {
  final int weekday;
  final String dayName;
  final List<ClassSession> classes;
  final bool isLoading;
  final Function(ClassSession session)? onClassSelected;
  final Function(ClassSession session)? onDeleteClass;
  final VoidCallback onImportPressed;

  const DayScheduleView({
    super.key,
    required this.weekday,
    required this.dayName,
    required this.classes,
    this.isLoading = false,
    this.onClassSelected,
    this.onDeleteClass,
    required this.onImportPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (classes.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withOpacity(0.4),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.event_available_rounded,
                  size: 48,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'No Classes on $dayName',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'You have free time or haven\'t imported your timetable yet.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onImportPressed,
                icon: const Icon(Icons.upload_file_rounded),
                label: const Text('Import Timetable PDF'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: classes.length,
      itemBuilder: (context, index) {
        final session = classes[index];
        return LectureCard(
          session: session,
          onTap: () => onClassSelected?.call(session),
          onDelete: onDeleteClass != null ? () => onDeleteClass?.call(session) : null,
        );
      },
    );
  }
}
