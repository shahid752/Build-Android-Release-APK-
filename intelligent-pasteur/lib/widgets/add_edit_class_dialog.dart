import 'package:flutter/material.dart';
import '../models/class_session.dart';
import 'lecture_card.dart';

/// Modal dialog for manually creating or editing a ClassSession subject.
class AddEditClassDialog extends StatefulWidget {
  final ClassSession? initialSession;
  final int? initialWeekday;

  const AddEditClassDialog({
    super.key,
    this.initialSession,
    this.initialWeekday,
  });

  /// Shows the dialog and returns the updated or newly created [ClassSession].
  static Future<ClassSession?> show(
    BuildContext context, {
    ClassSession? session,
    int? defaultWeekday,
  }) {
    return showDialog<ClassSession>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AddEditClassDialog(
        initialSession: session,
        initialWeekday: defaultWeekday,
      ),
    );
  }

  @override
  State<AddEditClassDialog> createState() => _AddEditClassDialogState();
}

class _AddEditClassDialogState extends State<AddEditClassDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _codeController;
  late TextEditingController _nameController;
  late TextEditingController _buildingController;
  late TextEditingController _roomController;
  late TextEditingController _instructorController;

  late int _dayOfWeek;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late int _colorIndex;

  final List<String> _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  void initState() {
    super.initState();
    final s = widget.initialSession;
    _codeController = TextEditingController(text: s?.courseCode ?? '');
    _nameController = TextEditingController(text: s?.courseName ?? '');
    _buildingController = TextEditingController(text: s?.building ?? '');
    _roomController = TextEditingController(text: s?.room ?? '');
    _instructorController = TextEditingController(text: s?.instructor ?? '');

    _dayOfWeek = s?.dayOfWeek ?? widget.initialWeekday ?? 1;
    _colorIndex = s?.colorIndex ?? 0;

    if (s != null) {
      _startTime = _parseTimeOfDay(s.startTime);
      _endTime = _parseTimeOfDay(s.endTime);
    } else {
      _startTime = const TimeOfDay(hour: 9, minute: 0);
      _endTime = const TimeOfDay(hour: 10, minute: 30);
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _buildingController.dispose();
    _roomController.dispose();
    _instructorController.dispose();
    super.dispose();
  }

  TimeOfDay _parseTimeOfDay(String timeStr) {
    try {
      final parts = timeStr.split(':');
      return TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      );
    } catch (_) {
      return const TimeOfDay(hour: 9, minute: 0);
    }
  }

  String _formatTimeOfDay(TimeOfDay tod) {
    final h = tod.hour.toString().padLeft(2, '0');
    final m = tod.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );
    if (picked != null) {
      setState(() {
        _startTime = picked;
        // If end time is before start time, set end time to 1 hour after
        final startMinutes = picked.hour * 60 + picked.minute;
        final endMinutes = _endTime.hour * 60 + _endTime.minute;
        if (endMinutes <= startMinutes) {
          final newEndMinutes = (startMinutes + 60) % (24 * 60);
          _endTime = TimeOfDay(
            hour: newEndMinutes ~/ 60,
            minute: newEndMinutes % 60,
          );
        }
      });
    }
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime,
    );
    if (picked != null) {
      setState(() => _endTime = picked);
    }
  }

  void _save() {
    if (_formKey.currentState?.validate() ?? false) {
      final session = ClassSession(
        id: widget.initialSession?.id,
        courseCode: _codeController.text.trim().toUpperCase(),
        courseName: _nameController.text.trim(),
        dayOfWeek: _dayOfWeek,
        startTime: _formatTimeOfDay(_startTime),
        endTime: _formatTimeOfDay(_endTime),
        building: _buildingController.text.trim(),
        room: _roomController.text.trim(),
        instructor: _instructorController.text.trim(),
        colorIndex: _colorIndex,
      );
      Navigator.pop(context, session);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialSession != null;
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            isEditing ? Icons.edit_calendar_rounded : Icons.add_circle_outline_rounded,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Text(isEditing ? 'Edit Subject' : 'Add Subject Manually'),
        ],
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Course Code & Name
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 4,
                      child: TextFormField(
                        controller: _codeController,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Code *',
                          hintText: 'CS101',
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 6,
                      child: TextFormField(
                        controller: _nameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Subject Name *',
                          hintText: 'Data Structures',
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Day of Week Dropdown
                DropdownButtonFormField<int>(
                  value: _dayOfWeek,
                  decoration: const InputDecoration(
                    labelText: 'Day of Week',
                    prefixIcon: Icon(Icons.today_rounded, size: 20),
                  ),
                  items: List.generate(7, (i) {
                    final dayNum = i + 1;
                    return DropdownMenuItem(
                      value: dayNum,
                      child: Text(_weekdays[i]),
                    );
                  }),
                  onChanged: (val) {
                    if (val != null) setState(() => _dayOfWeek = val);
                  },
                ),
                const SizedBox(height: 12),

                // Time Pickers (Start & End)
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: _pickStartTime,
                        borderRadius: BorderRadius.circular(12),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Start Time',
                            prefixIcon: Icon(Icons.schedule_rounded, size: 20),
                          ),
                          child: Text(
                            _formatTimeOfDay(_startTime),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: _pickEndTime,
                        borderRadius: BorderRadius.circular(12),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'End Time',
                            prefixIcon: Icon(Icons.timer_off_outlined, size: 20),
                          ),
                          child: Text(
                            _formatTimeOfDay(_endTime),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Location: Building and Room
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _buildingController,
                        decoration: const InputDecoration(
                          labelText: 'Building / Block',
                          hintText: 'Block A',
                          prefixIcon: Icon(Icons.business_rounded, size: 20),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _roomController,
                        decoration: const InputDecoration(
                          labelText: 'Room / Hall *',
                          hintText: 'Room 204',
                          prefixIcon: Icon(Icons.room_rounded, size: 20),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Instructor
                TextFormField(
                  controller: _instructorController,
                  decoration: const InputDecoration(
                    labelText: 'Instructor / Professor',
                    hintText: 'Dr. John Smith',
                    prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
                  ),
                ),
                const SizedBox(height: 16),

                // Card Color Choice
                const Text(
                  'Card Color Accent',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: List.generate(courseColors.length, (idx) {
                    final color = courseColors[idx];
                    final isSelected = _colorIndex == idx;
                    return GestureDetector(
                      onTap: () => setState(() => _colorIndex = idx),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: isSelected
                              ? Border.all(color: Colors.white, width: 3)
                              : null,
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: color.withOpacity(0.6),
                                    blurRadius: 8,
                                    spreadRadius: 2,
                                  ),
                                ]
                              : null,
                        ),
                        child: isSelected
                            ? const Icon(Icons.check, size: 18, color: Colors.white)
                            : null,
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(isEditing ? 'Save Changes' : 'Add Subject'),
        ),
      ],
    );
  }
}
