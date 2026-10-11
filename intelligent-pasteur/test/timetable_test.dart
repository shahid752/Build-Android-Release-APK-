import 'package:campus_schedule/models/class_session.dart';
import 'package:campus_schedule/services/timetable_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ClassSession Model Tests', () {
    test('toMap and fromMap should correctly serialize and deserialize', () {
      final session = ClassSession(
        id: 42,
        courseCode: 'CS301',
        courseName: 'Algorithms & Complexity',
        dayOfWeek: 1,
        startTime: '09:00',
        endTime: '10:30',
        building: 'Turing Hall',
        room: 'Room 204',
        instructor: 'Dr. Evelyn Reed',
        colorIndex: 2,
      );

      final map = session.toMap();
      final fromMap = ClassSession.fromMap(map);

      expect(fromMap.id, 42);
      expect(fromMap.courseCode, 'CS301');
      expect(fromMap.courseName, 'Algorithms & Complexity');
      expect(fromMap.dayOfWeek, 1);
      expect(fromMap.dayName, 'Monday');
      expect(fromMap.shortDayName, 'Mon');
      expect(fromMap.startTime, '09:00');
      expect(fromMap.endTime, '10:30');
      expect(fromMap.locationString, 'Turing Hall, Room 204');
      expect(fromMap.startHour, 9);
      expect(fromMap.startMinute, 0);
    });
  });

  group('TimetableParser Tests', () {
    test('parseRawText correctly parses pipe-delimited rows', () {
      const sampleText = '''
# Timetable Export
CS101 | Intro to Programming | Monday | 09:00 - 10:30 | Block A | Room 204 | Dr. Smith
MATH201 | Calculus III | Wednesday | 11:00 - 12:30 | Science Hall | Rm 102 | Prof. Johnson
PHYS101 | General Physics | Friday | 14:00 - 15:30 | West Wing | Lab 3 | Dr. Brown
''';

      final sessions = TimetableParser.parseRawText(sampleText);
      expect(sessions.length, 3);

      expect(sessions[0].courseCode, 'CS101');
      expect(sessions[0].dayOfWeek, 1);
      expect(sessions[0].startTime, '09:00');
      expect(sessions[0].endTime, '10:30');
      expect(sessions[0].room, 'Room 204');

      expect(sessions[1].courseCode, 'MATH201');
      expect(sessions[1].dayOfWeek, 3);
      expect(sessions[1].startTime, '11:00');
      expect(sessions[1].endTime, '12:30');

      expect(sessions[2].courseCode, 'PHYS101');
      expect(sessions[2].dayOfWeek, 5);
    });

    test('getSampleTimetable returns populated demo sessions across weekdays', () {
      final samples = TimetableParser.getSampleTimetable();
      expect(samples.isNotEmpty, true);
      expect(samples.any((s) => s.dayOfWeek == 1), true); // Monday
      expect(samples.any((s) => s.dayOfWeek == 5), true); // Friday
    });
  });
}
