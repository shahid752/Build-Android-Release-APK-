import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/class_session.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../services/timetable_parser.dart';
import '../widgets/lecture_card.dart';
import 'web_portal_import_screen.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  bool _isProcessing = false;
  String? _selectedFileName;
  List<ClassSession> _previewSessions = [];
  String? _errorMessage;

  /// Picks a PDF file from device storage, extracts text, and parses timetable sessions.
  Future<void> _pickAndParsePdf() async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        _selectedFileName = file.name;

        List<ClassSession> sessions = [];
        if (file.bytes != null) {
          sessions = await TimetableParser.parsePdfBytes(file.bytes!);
        } else if (file.path != null) {
          sessions = await TimetableParser.parsePdfFile(file.path!);
        }

        if (sessions.isEmpty) {
          setState(() {
            _errorMessage = 'Could not detect structured timetable rows in "${file.name}". You can load sample data or import via the Student Portal.';
          });
        } else {
          setState(() {
            _previewSessions = sessions;
          });
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error reading PDF file: $e';
      });
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  /// Loads preset university sample timetable for immediate demo & verification.
  void _loadSampleData() {
    setState(() {
      _selectedFileName = 'University_Standard_Timetable_Demo.pdf';
      _previewSessions = TimetableParser.getSampleTimetable();
      _errorMessage = null;
    });
  }

  /// Navigates to the webview student portal scraper.
  Future<void> _openWebPortal() async {
    final result = await Navigator.push<List<ClassSession>>(
      context,
      MaterialPageRoute(builder: (context) => const WebPortalImportScreen()),
    );

    if (result != null && result.isNotEmpty) {
      setState(() {
        _selectedFileName = 'Student Portal Web Scraper';
        _previewSessions = result;
      });
    }
  }

  /// Saves the parsed preview sessions to SQLite and schedules exact weekly notifications.
  Future<void> _confirmAndSave() async {
    if (_previewSessions.isEmpty) return;

    setState(() => _isProcessing = true);

    try {
      // 1. Clear previous schedule if overwriting
      await DatabaseService.instance.clearAllClasses();

      // 2. Insert batch into SQLite
      await DatabaseService.instance.insertClassesBatch(_previewSessions);

      // 3. Request permissions & reschedule exact alarms
      await NotificationService.instance.requestPermissions();
      await NotificationService.instance.rescheduleAllReminders();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green.shade700,
            content: Text(
              '🎉 Successfully imported ${_previewSessions.length} classes and scheduled exact lecture alarms!',
            ),
            duration: const Duration(seconds: 4),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade700,
            content: Text('Failed to save schedule: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _removePreviewItem(int index) {
    setState(() {
      _previewSessions.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Import Timetable'),
        actions: [
          IconButton(
            tooltip: 'Web Portal Scraper',
            icon: const Icon(Icons.language_rounded),
            onPressed: _openWebPortal,
          ),
        ],
      ),
      body: Column(
        children: [
          // Top Action Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
              border: Border(
                bottom: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.4)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossCrossConstraints.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isProcessing ? null : _pickAndParsePdf,
                        icon: const Icon(Icons.picture_as_pdf_rounded),
                        label: const Text('Pick Timetable PDF'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _isProcessing ? null : _loadSampleData,
                      icon: const Icon(Icons.auto_awesome_rounded),
                      label: const Text('Demo Sample'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _isProcessing ? null : _openWebPortal,
                  icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                  label: const Text('Or Import via Student Web Portal Session'),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
                if (_selectedFileName != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle_rounded, size: 16, color: theme.colorScheme.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Source: $_selectedFileName',
                            style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          if (_errorMessage != null)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline_rounded, color: theme.colorScheme.error),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(color: theme.colorScheme.onErrorContainer, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

          if (_isProcessing)
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Extracting and parsing timetable sessions...'),
                  ],
                ),
              ),
            )
          else if (_previewSessions.isEmpty)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.cloud_upload_outlined,
                        size: 64,
                        color: theme.colorScheme.primary.withOpacity(0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No Timetable Loaded',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Pick your university PDF timetable file, open your student portal, or click "Demo Sample" to test instantly.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: Column(
                crossAxisAlignment: CrossCrossConstraints.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'PREVIEW (${_previewSessions.length} Classes Found)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        Text(
                          'Swipe or tap to edit',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _previewSessions.length,
                      itemBuilder: (context, index) {
                        final session = _previewSessions[index];
                        return Dismissible(
                          key: Key('preview_${session.courseCode}_${session.dayOfWeek}_$index'),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            color: theme.colorScheme.error,
                            child: const Icon(Icons.delete_rounded, color: Colors.white),
                          ),
                          onDismissed: (_) => _removePreviewItem(index),
                          child: LectureCard(session: session),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      bottomNavigationBar: _previewSessions.isNotEmpty
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: theme.colorScheme.primary,
                  ),
                  onPressed: _isProcessing ? null : _confirmAndSave,
                  icon: const Icon(Icons.notifications_active_rounded),
                  label: Text(
                    'Confirm & Set Exact Reminders (${_previewSessions.length} Classes)',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}
