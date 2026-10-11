import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../models/class_session.dart';

/// Class containing extraction results and raw text for debugging/inspection.
class ParseResult {
  final List<ClassSession> sessions;
  final String rawText;

  ParseResult({required this.sessions, required this.rawText});
}

/// Service responsible for extracting text from PDF timetable files and parsing
/// unstructured, tabular, or day-grouped course data into [ClassSession] objects.
class TimetableParser {
  /// Extracts text from a PDF file located at [filePath] and parses it.
  static Future<ParseResult> parsePdfFile(String filePath) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    return parsePdfBytes(bytes);
  }

  /// Extracts raw text from PDF document byte stream using Syncfusion PDF engine.
  static Future<ParseResult> parsePdfBytes(List<int> bytes) async {
    try {
      final PdfDocument document = PdfDocument(inputBytes: bytes);
      final PdfTextExtractor extractor = PdfTextExtractor(document);
      final String extractedText = extractor.extractText();
      document.dispose();

      debugPrint('--- RAW EXTRACTED PDF TEXT (${extractedText.length} chars) ---');
      debugPrint(extractedText);
      debugPrint('-------------------------------------------------------------');

      final sessions = parseRawText(extractedText);
      return ParseResult(sessions: sessions, rawText: extractedText);
    } catch (e) {
      debugPrint('Error reading PDF document: $e');
      return ParseResult(sessions: [], rawText: 'Error reading PDF: $e');
    }
  }

  /// Multi-strategy parser for extracting timetable sessions from raw text.
  static List<ClassSession> parseRawText(String rawText) {
    if (rawText.trim().isEmpty) return [];

    final List<ClassSession> results = [];
    final lines = rawText.split(RegExp(r'[\r\n]+'));

    int colorCounter = 0;
    int currentDayHeader = 1; // Default Monday

    // Strategy 1: Day-Grouped State Machine
    // Handles timetables where days appear as section headers:
    // e.g.:
    // MONDAY
    // CS101 Intro to CS 09:00 - 10:30 Room 204 Dr. Smith
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      // Check if line is a Day Header (e.g. "MONDAY", "Monday Schedule", "Day: Tue")
      final detectedDay = _detectDayHeader(line);
      if (detectedDay != null) {
        currentDayHeader = detectedDay;
        continue;
      }

      // Try parsing single line with active day context
      final session = _parseLineWithContext(line, currentDayHeader, colorCounter);
      if (session != null) {
        results.add(session);
        colorCounter = (colorCounter + 1) % 6;
        continue;
      }

      // Strategy 2: Multi-line chunking (When PDF text extractor splits cells into consecutive lines)
      // Checks window of next 2-4 lines
      if (i + 2 < lines.length) {
        final multiChunk = _tryParseMultiLineChunk(lines, i, currentDayHeader, colorCounter);
        if (multiChunk != null) {
          results.add(multiChunk.session);
          colorCounter = (colorCounter + 1) % 6;
          i += multiChunk.linesConsumed - 1;
          continue;
        }
      }
    }

    // Strategy 3: Global Regex Scan (if line-by-line found very few or no classes)
    if (results.isEmpty) {
      results.addAll(_parseByGlobalRegex(rawText));
    }

    return results;
  }

  /// Checks if a line represents a day header (e.g., "MONDAY", "Day: Tuesday", "=== WEDNESDAY ===")
  static int? _detectDayHeader(String line) {
    final clean = line.replaceAll(RegExp(r'[^a-zA-Z]'), '').toLowerCase();
    if (clean == 'monday' || clean == 'mon') return 1;
    if (clean == 'tuesday' || clean == 'tue' || clean == 'tues') return 2;
    if (clean == 'wednesday' || clean == 'wed') return 3;
    if (clean == 'thursday' || clean == 'thu' || clean == 'thur' || clean == 'thurs') return 4;
    if (clean == 'friday' || clean == 'fri') return 5;
    if (clean == 'saturday' || clean == 'sat') return 6;
    if (clean == 'sunday' || clean == 'sun') return 7;
    return null;
  }

  /// Parses a line with support for delimiter tokens or contextual active day
  static ClassSession? _parseLineWithContext(String line, int contextualDay, int colorIndex) {
    // 1. Delimited formats (Pipe '|', Tab '\t', Semicolon ';', or Comma ',')
    if (line.contains('|') || line.contains('\t') || line.contains(';')) {
      final delimiter = line.contains('|')
          ? '|'
          : line.contains('\t')
              ? '\t'
              : ';';
      final parts = line.split(delimiter).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      if (parts.length >= 3) {
        return _buildFromTokens(parts, contextualDay, colorIndex);
      }
    }

    // 2. Comprehensive schedule row regex matching course code, name, optional day, time, and room
    // Example: "CS301 Algorithms 09:00-10:30 Room 204 Dr. Reed"
    final regex = RegExp(
      r'([A-Za-z]{2,5}[-\s]?\d{2,4}[A-Za-z]?)\s+(.*?)\s+(?:(Mon(?:day)?|Tue(?:sday)?|Wed(?:nesday)?|Thu(?:rsday)?|Fri(?:day)?|Sat(?:urday)?|Sun(?:day)?)\s+)?(\d{1,2}(?::\d{2})?\s*(?:[AaPp][Mm])?)\s*[-–to]+\s*(\d{1,2}(?::\d{2})?\s*(?:[AaPp][Mm])?)\s+(.*)',
      caseSensitive: false,
    );

    final match = regex.firstMatch(line);
    if (match != null) {
      final courseCode = match.group(1)?.trim() ?? 'CLASS';
      final courseName = match.group(2)?.trim() ?? 'Lecture';
      final dayStr = match.group(3);
      final startStr = _normalizeTime(match.group(4) ?? '09:00');
      final endStr = _normalizeTime(match.group(5) ?? '10:00');
      final remainder = (match.group(6) ?? '').trim();

      // Extract room/building and instructor from remainder
      final locDetails = _extractLocationAndInstructor(remainder);

      return ClassSession(
        courseCode: courseCode,
        courseName: courseName.isEmpty ? courseCode : courseName,
        dayOfWeek: dayStr != null ? _parseDayOfWeek(dayStr) : contextualDay,
        startTime: startStr,
        endTime: endStr,
        building: locDetails.building,
        room: locDetails.room,
        instructor: locDetails.instructor,
        colorIndex: colorIndex,
      );
    }

    // 3. Fallback heuristic for time range in the line
    return _parseFallbackHeuristic(line, contextualDay, colorIndex);
  }

  static _ParsedMultiChunk? _tryParseMultiLineChunk(
    List<String> lines,
    int startIndex,
    int contextualDay,
    int colorIndex,
  ) {
    // Check if within lines[startIndex .. startIndex + 4] we have:
    // a course code line, a title line, a time line, and a room line
    String combined = '';
    for (int k = 0; k < 4 && (startIndex + k) < lines.length; k++) {
      combined += ' ${lines[startIndex + k].trim()}';
      final timeMatch = _extractTimeRange(combined);
      if (timeMatch != null) {
        final session = _parseLineWithContext(combined.trim(), contextualDay, colorIndex);
        if (session != null) {
          return _ParsedMultiChunk(session: session, linesConsumed: k + 1);
        }
      }
    }
    return null;
  }

  static ClassSession? _buildFromTokens(List<String> tokens, int contextualDay, int colorIndex) {
    try {
      // Find which token contains time range
      int timeTokenIndex = -1;
      String startTime = '09:00';
      String endTime = '10:00';

      for (int i = 0; i < tokens.length; i++) {
        final tr = _extractTimeRange(tokens[i]);
        if (tr != null) {
          timeTokenIndex = i;
          startTime = tr.start;
          endTime = tr.end;
          break;
        }
      }

      if (timeTokenIndex == -1) return null;

      final courseCode = tokens[0].trim();
      final courseName = tokens.length > 1 && timeTokenIndex != 1 ? tokens[1].trim() : 'Lecture';

      int dayOfWeek = contextualDay;
      for (var t in tokens) {
        final d = _extractDayName(t);
        if (d != null) {
          dayOfWeek = d;
          break;
        }
      }

      String room = 'Room 101';
      String building = 'Campus';
      String instructor = 'Faculty';

      if (timeTokenIndex + 1 < tokens.length) {
        room = tokens[timeTokenIndex + 1].trim();
      }
      if (timeTokenIndex + 2 < tokens.length) {
        instructor = tokens[timeTokenIndex + 2].trim();
      }

      return ClassSession(
        courseCode: courseCode,
        courseName: courseName,
        dayOfWeek: dayOfWeek,
        startTime: startTime,
        endTime: endTime,
        building: building,
        room: room,
        instructor: instructor,
        colorIndex: colorIndex,
      );
    } catch (_) {
      return null;
    }
  }

  static ClassSession? _parseFallbackHeuristic(String line, int contextualDay, int colorIndex) {
    final tr = _extractTimeRange(line);
    if (tr == null) return null;

    final dayMatch = _extractDayName(line);
    final dayOfWeek = dayMatch ?? contextualDay;

    final codeMatch = RegExp(r'\b([A-Za-z]{2,5}[-\s]?\d{2,4}[A-Za-z]?)\b').firstMatch(line);
    final courseCode = codeMatch != null ? codeMatch.group(1)!.trim() : 'LEC-${(line.hashCode % 900 + 100).abs()}';

    // Clean remaining line text
    String remaining = line
        .replaceAll(tr.rawMatch, '')
        .replaceAll(RegExp(r'\b(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday|Mon|Tue|Wed|Thu|Fri|Sat|Sun)\b', caseSensitive: false), '');
    if (codeMatch != null) {
      remaining = remaining.replaceAll(codeMatch.group(0)!, '');
    }

    final locDetails = _extractLocationAndInstructor(remaining);
    final courseName = locDetails.name.isNotEmpty ? locDetails.name : 'Lecture ($courseCode)';

    return ClassSession(
      courseCode: courseCode,
      courseName: courseName,
      dayOfWeek: dayOfWeek,
      startTime: tr.start,
      endTime: tr.end,
      building: locDetails.building,
      room: locDetails.room,
      instructor: locDetails.instructor,
      colorIndex: colorIndex,
    );
  }

  static _LocationResult _extractLocationAndInstructor(String text) {
    String building = 'Main Campus';
    String room = 'TBA';
    String instructor = 'Faculty';
    String name = '';

    // Search room markers (Room 204, Lab 3, Hall A, LH-2, Audi 1, Block C)
    final roomRegex = RegExp(
      r'(?:(Block|Bldg|Building|Hall|Lab|Room|Rm|LH|LT|Auditorium)\s*[-:]?\s*([A-Za-z0-9\-]+))',
      caseSensitive: false,
    );
    final roomMatch = roomRegex.firstMatch(text);
    if (roomMatch != null) {
      room = '${roomMatch.group(1)} ${roomMatch.group(2)}'.trim();
    }

    // Search instructor prefix (Dr., Prof., Mr., Ms., Engr.)
    final instRegex = RegExp(r'(?:(?:Dr\.|Prof\.|Mr\.|Ms\.|Engr\.)\s+[A-Za-z\.\s]+)', caseSensitive: false);
    final instMatch = instRegex.firstMatch(text);
    if (instMatch != null) {
      instructor = instMatch.group(0)!.trim();
    }

    final cleaned = text
        .replaceAll(roomRegex, '')
        .replaceAll(instRegex, '')
        .replaceAll(RegExp(r'[,\|\-\–]'), ' ')
        .trim();
    if (cleaned.isNotEmpty) {
      name = cleaned;
    }

    return _LocationResult(
      building: building,
      room: room,
      instructor: instructor,
      name: name,
    );
  }

  static _TimeRangeResult? _extractTimeRange(String text) {
    // Matches 09:00 - 10:30, 9:00-10:00, 9:00 AM - 10:30 AM, 9-11 AM, 14:00 to 15:30
    final regex = RegExp(
      r'(\d{1,2}(?::\d{2})?\s*(?:[AaPp][Mm])?)\s*[-–to]+\s*(\d{1,2}(?::\d{2})?\s*(?:[AaPp][Mm])?)',
      caseSensitive: false,
    );
    final match = regex.firstMatch(text);
    if (match != null) {
      return _TimeRangeResult(
        start: _normalizeTime(match.group(1)!),
        end: _normalizeTime(match.group(2)!),
        rawMatch: match.group(0)!,
      );
    }
    return null;
  }

  static int? _extractDayName(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('mon')) return 1;
    if (lower.contains('tue')) return 2;
    if (lower.contains('wed')) return 3;
    if (lower.contains('thu')) return 4;
    if (lower.contains('fri')) return 5;
    if (lower.contains('sat')) return 6;
    if (lower.contains('sun')) return 7;
    return null;
  }

  static int _parseDayOfWeek(String dayStr) {
    return _extractDayName(dayStr) ?? 1;
  }

  static String _normalizeTime(String raw) {
    String str = raw.trim().toUpperCase();
    bool isPM = str.contains('PM');
    bool isAM = str.contains('AM');
    str = str.replaceAll(RegExp(r'[A-Z\s]'), '');

    if (str.contains('.')) {
      str = str.replaceAll('.', ':');
    }

    int hour = 8;
    int minute = 0;

    if (str.contains(':')) {
      final parts = str.split(':');
      hour = int.tryParse(parts[0]) ?? 8;
      minute = int.tryParse(parts[1]) ?? 0;
    } else {
      hour = int.tryParse(str) ?? 8;
    }

    if (isPM && hour < 12) hour += 12;
    if (isAM && hour == 12) hour = 0;

    final hourStr = hour.toString().padLeft(2, '0');
    final minStr = minute.toString().padLeft(2, '0');
    return '$hourStr:$minStr';
  }

  static List<ClassSession> _parseByGlobalRegex(String text) {
    final List<ClassSession> sessions = [];
    final regex = RegExp(
      r'([A-Za-z]{2,5}[-\s]?\d{2,4})[\s\S]*?(Mon(?:day)?|Tue(?:sday)?|Wed(?:nesday)?|Thu(?:rsday)?|Fri(?:day)?|Sat(?:urday)?|Sun(?:day)?)[\s\S]*?(\d{1,2}(?::\d{2})?)\s*[-–]\s*(\d{1,2}(?::\d{2})?)',
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
          courseCode: code.toUpperCase(),
          courseName: 'Subject $code',
          dayOfWeek: _parseDayOfWeek(day),
          startTime: start,
          endTime: end,
          building: 'Campus',
          room: 'Hall ${idx + 1}',
          instructor: 'Faculty Staff',
          colorIndex: idx % 6,
        ),
      );
      idx++;
    }
    return sessions;
  }

  static List<ClassSession> getSampleTimetable() {
    return [
      ClassSession(
        courseCode: 'CS301',
        courseName: 'Algorithms & Complexity',
        dayOfWeek: 1,
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
        dayOfWeek: 1,
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
        dayOfWeek: 2,
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
        dayOfWeek: 2,
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
        dayOfWeek: 3,
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
        dayOfWeek: 3,
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
        dayOfWeek: 4,
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
        dayOfWeek: 4,
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
        dayOfWeek: 5,
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
        dayOfWeek: 5,
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

class _TimeRangeResult {
  final String start;
  final String end;
  final String rawMatch;
  _TimeRangeResult({required this.start, required this.end, required this.rawMatch});
}

class _LocationResult {
  final String building;
  final String room;
  final String instructor;
  final String name;
  _LocationResult({required this.building, required this.room, required this.instructor, required this.name});
}

class _ParsedMultiChunk {
  final ClassSession session;
  final int linesConsumed;
  _ParsedMultiChunk({required this.session, required this.linesConsumed});
}
