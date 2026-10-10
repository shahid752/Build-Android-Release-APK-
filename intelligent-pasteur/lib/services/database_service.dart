import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/class_session.dart';

/// Singleton service managing local SQLite database operations for timetable persistence.
class DatabaseService {
  static final DatabaseService instance = DatabaseService._internal();
  static Database? _database;

  DatabaseService._internal();

  static const String tableName = 'class_sessions';
  static const String dbName = 'campus_schedule.db';
  static const int dbVersion = 1;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, dbName);

    return await openDatabase(
      path,
      version: dbVersion,
      onCreate: _onCreate,
    );
  }

  FutureOr<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tableName (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        course_code TEXT NOT NULL,
        course_name TEXT NOT NULL,
        day_of_week INTEGER NOT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT NOT NULL,
        building TEXT NOT NULL,
        room TEXT NOT NULL,
        instructor TEXT NOT NULL,
        color_index INTEGER DEFAULT 0
      )
    ''');

    // Index day_of_week and start_time for rapid query sorting
    await db.execute('''
      CREATE INDEX idx_day_time ON $tableName(day_of_week, start_time)
    ''');
  }

  /// Inserts a single class session and returns the generated row id.
  Future<int> insertClass(ClassSession session) async {
    final db = await database;
    return await db.insert(
      tableName,
      session.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Inserts a batch of class sessions inside a single atomic transaction.
  Future<List<int>> insertClassesBatch(List<ClassSession> classes) async {
    final db = await database;
    final List<int> ids = [];
    await db.transaction((txn) async {
      for (final session in classes) {
        final id = await txn.insert(
          tableName,
          session.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        ids.add(id);
      }
    });
    return ids;
  }

  /// Retrieves all scheduled classes, sorted by weekday and start time.
  Future<List<ClassSession>> getAllClasses() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      tableName,
      orderBy: 'day_of_week ASC, start_time ASC',
    );
    return List.generate(maps.length, (i) => ClassSession.fromMap(maps[i]));
  }

  /// Retrieves all classes for a specific day of the week (1=Mon..7=Sun).
  Future<List<ClassSession>> getClassesForDay(int weekday) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      tableName,
      where: 'day_of_week = ?',
      whereArgs: [weekday],
      orderBy: 'start_time ASC',
    );
    return List.generate(maps.length, (i) => ClassSession.fromMap(maps[i]));
  }

  /// Updates an existing class session.
  Future<int> updateClass(ClassSession session) async {
    final db = await database;
    if (session.id == null) return 0;
    return await db.update(
      tableName,
      session.toMap(),
      where: 'id = ?',
      whereArgs: [session.id],
    );
  }

  /// Deletes a specific class session by ID.
  Future<int> deleteClass(int id) async {
    final db = await database;
    return await db.delete(
      tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Deletes all rows in the timetable table.
  Future<int> clearAllClasses() async {
    final db = await database;
    return await db.delete(tableName);
  }

  /// Gets total number of classes stored.
  Future<int> getClassCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM $tableName');
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
