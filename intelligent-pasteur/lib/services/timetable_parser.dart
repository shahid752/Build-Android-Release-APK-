import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../models/class_session.dart';

/// Service responsible for extracting text from PDF timetable files and parsing
/// unstructured or tabular course data into strongly-typed [ClassSession] objects.
class TimetableParser {
  /// Extracts text from a PDF file located at [filePath] and parses it.
  static Future<List<ClassSession>> parsePdfFile(String filePath) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    return parsePdfBytes(bytes);
  }

  /// Extracts raw text from PDF document byte stream using Syncfusion PDF engine.
  static Future<List<ClassSession>> parsePdfBytes(List<int> bytes) async {
    try {
      final PdfDocument document = PdfDocument(inputBytes: bytes);
      final PdfTextExtractor extractor = PdfTextExtractor(document);
      final String extractedText = extractor.extractText();
      document.dispose();

      debugPrint('--- RAW EXTRACTED PDF TEXT ---');
      debugPrint(extractedText);
      debugPrint('------------------------------');

      return parseRawText(extractedText);
    } catch (e) {
      debugPrint('Error reading PDF document: $e');
      return [];
    }
  }

  /// Core parsing logic that recognizes tabular lines, pipe/tab/comma delimited rows,
  /// and regex-based timetable formats.
  static List<ClassSession> parseRawText(String rawText) {
    final List<ClassSession> results = [];
    final lines = rawText.split(RegExp(r'[\r\n]+'));

    int colorCounter = 0;

    for (String rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#') || line.toLowerCase().startsWith('course code')) {
        continue; // Skip headers or empty lines
      }

      final session = _parseLine(line, colorCounter);
      if (session != null) {
        results.add(session);
        colorCounter = (colorCounter + 1) % 6;
      }
    }

    // If standard line-by-line parsing yielded nothing, try global block regex matching
    if (results.isEmpty) {
      results.addAll(_parseByGlobalRegex(rawText));
    }

    return results;
  }

  /// Attempts to parse a single line into a ClassSession
  static ClassSession? _parseLine(String line, int colorIndex) {
    // 1. Check for Delimited formats (Pipe '|', Tab '\t', or Semicolon ';')
    if (line.contains('|') || line.contains('\t') || line.contains(';')) {
      final delimiter = line.contains('|')
          ? '|'
          : line.contains('\t')
              ? '\t'
              : ';';
      final parts = line.split(delimiter).map((e) => e.trim()).toList();
      if (parts.length >= 4) {
        return _buildFromTokens(parts, colorIndex);
      }
    }

    // 2. Regular Expression matching standard schedule pattern:
    // e.g., "CS101 Intro to Programming Mon 09:00 - 10:30 Block A Room 204 Dr. Smith"
    final regex = RegExp(
      r'([A-Z]{2,4}[-\s]?\d{3,4}[A-Z]?)\s+(.*?)\s+(Mon(?:day)?|Tue(?:sday)?|Wed(?:nesday)?|Thu(?:rsday)?|Fri(?:day)?|Sat(?:urday)?|Sun(?:day)?)\s+(\d{1,2}:\d{2}(?:\s*[AaPp][Mm])?)\s*[-–to]+\s*(\d{1,2}:\d{2}(?:\s*[AaPp][Mm])?)\s+(.*?)(?:Room|Rm|Lab|Hall|Auditorium|\#)?\s*([A-Za-z0-9\-\.\s]+?)(?:\s+(Dr\..*|Prof\..*|Mr\..*|Ms\..*))?$',
      caseSensitive: false,
    );

    final match = regex.firstMatch(line);
    if (match != null) {
      final courseCode = match.group(1) ?? 'CLASS';
      final courseName = match.group(2) ?? 'Lecture';
      final dayStr = match.group(3) ?? 'Mon';
      final startStr = _normalizeTime(match.group(4) ?? '08:00');
      final endStr = _normalizeTime(match.group(5) ?? '09:00');
      final building = (match.group(6) ?? 'Main Campus').trim();
      final room = (match.group(7) ?? 'TBA').trim();
      final instructor = (match.group(8) ?? 'Faculty').trim();

      return ClassSession(
        courseCode: courseCode,
        courseName: courseName,
        dayOfWeek: _parseDayOfWeek(dayStr),
        startTime: startStr,
        endTime: endStr,
        building: building.isEmpty ? 'Main Campus' : building,
        room: room.isEmpty ? 'Hall A' : room,
        instructor: instructor.isEmpty ? 'Faculty Staff' : instructor,
        colorIndex: colorIndex,
      );
    }

    // 3. Fallback heuristic: Detect time range + Day + Code
    return _parseFallbackHeuristic(line, colorIndex);
  }

  static ClassSession? _buildFromTokens(List<String> tokens, int colorIndex) {
    try {
      // Expected typical layout:
      // [0] CourseCode, [1] CourseName, [2] Day, [3] Time (e.g. 09:00 - 10:30), [4] Building, [5] Room, [6] Instructor
      final courseCode = tokens[0];
      final courseName = tokens.length > 1 ? tokens[1] : 'Lecture';
      final dayStr = tokens.length > 2 ? tokens[2] : 'Mon';
      final timeStr = tokens.length > 3 ? tokens[3] : '09:00 - 10:00';
      
      final timeParts = timeStr.split(RegExp(r'[-–to]+'));
      final startTime = timeParts.isNotEmpty ? _normalizeTime(timeParts[0].trim()) : '08:00';
      final endTime = timeParts.length > 1 ? _normalizeTime(timeParts[1].trim()) : '09:00';

      final building = tokens.length > 4 ? tokens[4] : 'Campus';
      final room = tokens.length > 5 ? tokens[5] : 'Room 101';
      final instructor = tokens.length > 6 ? tokens[6] : 'Faculty';

      return ClassSession(
        courseCode: courseCode,
        courseName: courseName,
        dayOfWeek: _parseDayOfWeek(dayStr),
        startTime: startTime,
        endTime: endTime,
        building: building,
        room: room,
        instructor: instructor,
        colorIndex: colorIndex,
      );
    } catch (e) {
      return null;
    }
  }

  static ClassSession? _parseFallbackHeuristic(String line, int colorIndex) {
    final timeMatch = RegExp(r'(\d{1,2}:\d{2})\s*[-–to]+\s*(\d{1,2}:\d{2})').firstMatch(line);
    final dayMatch = RegExp(r'\b(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday|Mon|Tue|Wed|Thu|Fri|Sat|Sun)\b', caseSensitive: false).firstMatch(line);
    final codeMatch = RegExp(r'\b([A-Z]{2,5}[-\s]?\d{3,4})\b').firstMatch(line);

    if (timeMatch != null && dayMatch != null) {
      final courseCode = codeMatch != null ? codeMatch.group(1)! : 'LEC-${(line.hashCode % 900 + 100).abs()}';
      final startTime = _normalizeTime(timeMatch.group(1)!);
      final endTime = _normalizeTime(timeMatch.group(2)!);
      final dayOfWeek = _parseDayOfWeek(dayMatch.group(1)!);

      // Clean remaining text for name/location
      String remaining = line
          .replaceAll(timeMatch.group(0)!, '')
          .replaceAll(dayMatch.group(0)!, '');
      if (codeMatch != null) {
        remaining = remaining.replaceAll(codeMatch.group(0)!, '');
      }

      final parts = remaining.split(RegExp(r'[,\|;]')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

      final courseName = parts.isNotEmpty ? parts[0] : 'University Lecture';
      final location = parts.length > 1 ? parts[1] : 'Main Hall';
      final instructor = parts.length > 2 ? parts[2] : 'Academic Staff';

      return ClassSession(
        courseCode: courseCode,
        courseName: courseName,
        dayOfWeek: dayOfWeek,
        startTime: startTime,
        endTime: endTime,
        building: 'Campus',
        room: location,
        instructor: instructor,
        colorIndex: colorIndex,
      );
    }
    return null;
  }

  static List<ClassSession> _parseByGlobalRegex(String text) {
    final List<ClassSession> sessions = [];
    final regex = RegExp(
      r'([A-Z]{2,5}\s?\d{3,4})[\s\S]*?(Monday|Tuesday|Wednesday|Thursday|Friday|Mon|Tue|Wed|Thu|Fri)[\s\S]*?(\d{1,2}:\d{2})\s*[-–]\s*(\d{1,2}:\d{2})',
      caseSensitive: false,
    );

    int idx = 0;
    for (final match in regex.allMatches(text)) {
      final code = match.group(1) ?? 'CS101';
      final day = match.group(2) ?? 'Mon';
      final start = _normalizeTime(match.group(3) ?? '09:00');
      final end = _normalizeTime(match.group(4) ?? '10:30');

      sessions.add(
        ClassSession(
          courseCode: code,
          courseName: 'Course $code',
          dayOfWeek: _parseDayOfWeek(day),
          startTime: start,
          endTime: end,
          building: 'Academic Block',
          room: 'Hall ${idx + 1}',
          instructor: 'Faculty Member',
          colorIndex: idx % 6,
        ),
      );
      idx++;
    }
    return sessions;
  }

  static int _parseDayOfWeek(String dayStr) {
    final lower = dayStr.toLowerCase().trim();
    if (lower.startsWith('mon')) return 1;
    if (lower.startsWith('tue')) return 2;
    if (lower.startsWith('wed')) return 3;
    if (lower.startsWith('thu')) return 4;
    if (lower.startsWith('fri')) return 5;
    if (lower.startsWith('sat')) return 6;
    if (lower.startsWith('sun')) return 7;
    return 1;
  }

  /// Normalizes times like "9:00", "09:00 AM", "2:30 PM" to standard 24-hour "HH:mm"
  static String _normalizeTime(String raw) {
    String str = raw.trim().toUpperCase();
    bool isPM = str.contains('PM');
    bool isAM = str.contains('AM');
    str = str.replaceAll(RegExp(r'[A-Z\s]'), '');

    final parts = str.split(':');
    if (parts.length >= 2) {
      int hour = int.tryParse(parts[0]) ?? 8;
      int minute = int.tryParse(parts[1]) ?? 0;

      if (isPM && hour < 12) hour += 12;
      if (isAM && hour == 12) hour = 0;

      final hourStr = hour.toString().padLeft(2, '0');
      final minStr = minute.toString().padLeft(2, '0');
      return '$hourStr:$minStr';
    }
    return '08:00';
  }

  /// Generates sample timetable dataset for quick testing and demonstrations.
  static List<ClassSession> getSampleTimetable() {
    return [
      ClassSession(
        courseCode: 'CS301',
        courseName: 'Algorithms & Complexity',
        dayOfWeek: 1, // Monday
        startTime: '09:00',
        endTime: '10:30',
        building: 'Turing Hall',
        room: 'Room 204',
        instructor: 'Dr. Evelyn Reed',
        colorIndex: 0,
      ),
      ClassSession(
        courseCode: 'MATH240',
        courseName: 'Linear Algebra & Matrices',
        dayOfWeek: 1, // Monday
        startTime: '11:00',
        endTime: '12:30',
        building: 'Euler Building',
        room: 'Auditorium B',
        instructor: 'Prof. Marcus Vance',
        colorIndex: 1,
      ),
      ClassSession(
        courseCode: 'CS350',
        courseName: 'Database Systems Architecture',
        dayOfWeek: 2, // Tuesday
        startTime: '10:00',
        endTime: '11:45',
        building: 'Engineering Block C',
        room: 'Lab 4',
        instructor: 'Dr. Sarah Connor',
        colorIndex: 2,
      ),
      ClassSession(
        courseCode: 'PHYS120',
        courseName: 'University Physics II',
        dayOfWeek: 2, // Tuesday
        startTime: '13:30',
        endTime: '15:00',
        building: 'Science Complex',
        room: 'Lecture Hall 1',
        instructor: 'Prof. Richard Feynman',
        colorIndex: 3,
      ),
      ClassSession(
        courseCode: 'CS301',
        courseName: 'Algorithms Lab Practice',
        dayOfWeek: 3, // Wednesday
        startTime: '09:00',
        endTime: '11:00',
        building: 'Turing Hall',
        room: 'Computing Lab 2',
        instructor: 'Dr. Evelyn Reed',
        colorIndex: 0,
      ),
      ClassSession(
        courseCode: 'ENG210',
        courseName: 'Technical Communications',
        dayOfWeek: 3, // Wednesday
        startTime: '14:00',
        endTime: '15:30',
        building: 'Humanities Wing',
        room: 'Room 108',
        instructor: 'Ms. Clara Oswald',
        colorIndex: 4,
      ),
      ClassSession(
        courseCode: 'CS410',
        courseName: 'Mobile Application Architecture',
        dayOfWeek: 4, // Thursday
        startTime: '09:30',
        endTime: '11:00',
        building: 'Innovation Hub',
        room: 'Studio 3',
        instructor: 'Prof. David Clark',
        colorIndex: 5,
      ),
      ClassSession(
        courseCode: 'MATH240',
        courseName: 'Linear Algebra Problem Session',
        dayOfWeek: 4, // Thursday
        startTime: '11:30',
        endTime: '13:00',
        building: 'Euler Building',
        room: 'Seminar Room 12',
        instructor: 'Prof. Marcus Vance',
        colorIndex: 1,
      ),
      ClassSession(
        courseCode: 'CS350',
        courseName: 'Database Systems Lab',
        dayOfWeek: 5, // Friday
        startTime: '10:00',
        endTime: '12:00',
        building: 'Engineering Block C',
        room: 'Lab 4',
        instructor: 'Dr. Sarah Connor',
        colorIndex: 2,
      ),
      ClassSession(
        courseCode: 'CS490',
        courseName: 'Senior Capstone Seminar',
        dayOfWeek: 5, // Friday
        startTime: '14:00',
        endTime: '16:00',
        building: 'Innovation Hub',
        room: 'Executive Boardroom',
        instructor: 'Dean Katherine Johnson',
        colorIndex: 0,
      ),
    ];
  }
}
