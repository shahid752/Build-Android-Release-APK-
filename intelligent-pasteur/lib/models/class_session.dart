/// Data model representing a recurring university class or lecture session.
class ClassSession {
  final int? id;
  final String courseCode;
  final String courseName;
  final int dayOfWeek; // 1 = Monday, 2 = Tuesday, ..., 7 = Sunday
  final String startTime; // "HH:mm" (24-hour format, e.g. "09:30")
  final String endTime; // "HH:mm" (24-hour format, e.g. "11:00")
  final String building;
  final String room;
  final String instructor;
  final int colorIndex;

  ClassSession({
    this.id,
    required this.courseCode,
    required this.courseName,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    required this.building,
    required this.room,
    required this.instructor,
    this.colorIndex = 0,
  });

  /// Convert ClassSession object to Map for SQLite database operations.
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'course_code': courseCode.trim(),
      'course_name': courseName.trim(),
      'day_of_week': dayOfWeek,
      'start_time': startTime.trim(),
      'end_time': endTime.trim(),
      'building': building.trim(),
      'room': room.trim(),
      'instructor': instructor.trim(),
      'color_index': colorIndex,
    };
  }

  /// Create a ClassSession object from a database Map.
  factory ClassSession.fromMap(Map<String, dynamic> map) {
    return ClassSession(
      id: map['id'] as int?,
      courseCode: (map['course_code'] as String?) ?? '',
      courseName: (map['course_name'] as String?) ?? '',
      dayOfWeek: (map['day_of_week'] as int?) ?? 1,
      startTime: (map['start_time'] as String?) ?? '08:00',
      endTime: (map['end_time'] as String?) ?? '09:00',
      building: (map['building'] as String?) ?? '',
      room: (map['room'] as String?) ?? '',
      instructor: (map['instructor'] as String?) ?? 'Staff',
      colorIndex: (map['color_index'] as int?) ?? 0,
    );
  }

  ClassSession copyWith({
    int? id,
    String? courseCode,
    String? courseName,
    int? dayOfWeek,
    String? startTime,
    String? endTime,
    String? building,
    String? room,
    String? instructor,
    int? colorIndex,
  }) {
    return ClassSession(
      id: id ?? this.id,
      courseCode: courseCode ?? this.courseCode,
      courseName: courseName ?? this.courseName,
      dayOfWeek: dayOfWeek ?? this.dayOfWeek,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      building: building ?? this.building,
      room: room ?? this.room,
      instructor: instructor ?? this.instructor,
      colorIndex: colorIndex ?? this.colorIndex,
    );
  }

  /// Returns English day name based on ISO weekday number (1..7).
  String get dayName {
    switch (dayOfWeek) {
      case 1:
        return 'Monday';
      case 2:
        return 'Tuesday';
      case 3:
        return 'Wednesday';
      case 4:
        return 'Thursday';
      case 5:
        return 'Friday';
      case 6:
        return 'Saturday';
      case 7:
        return 'Sunday';
      default:
        return 'Unknown';
    }
  }

  /// Returns 3-letter day abbreviation.
  String get shortDayName {
    switch (dayOfWeek) {
      case 1:
        return 'Mon';
      case 2:
        return 'Tue';
      case 3:
        return 'Wed';
      case 4:
        return 'Thu';
      case 5:
        return 'Fri';
      case 6:
        return 'Sat';
      case 7:
        return 'Sun';
      default:
        return '???';
    }
  }

  /// Full location string combining building and room.
  String get locationString {
    if (building.isNotEmpty && room.isNotEmpty) {
      return '$building, $room';
    } else if (room.isNotEmpty) {
      return room;
    } else if (building.isNotEmpty) {
      return building;
    }
    return 'TBA';
  }

  /// Formatted time interval string (e.g. "09:00 - 10:30").
  String get formattedTimeSpan => '$startTime - $endTime';

  /// Parsed integer hour of start time.
  int get startHour {
    try {
      final parts = startTime.split(':');
      return int.parse(parts[0]);
    } catch (_) {
      return 8;
    }
  }

  /// Parsed integer minute of start time.
  int get startMinute {
    try {
      final parts = startTime.split(':');
      return int.parse(parts[1]);
    } catch (_) {
      return 0;
    }
  }

  @override
  String toString() {
    return 'ClassSession($courseCode - $courseName, $dayName $startTime-$endTime @ $locationString)';
  }
}
