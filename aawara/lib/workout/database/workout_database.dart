import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../models/exercise.dart';
import '../models/workout_log.dart';
import '../models/workout_plan_day.dart';

class WorkoutDatabase {
  static final WorkoutDatabase instance = WorkoutDatabase._init();
  static Database? _database;

  WorkoutDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('workout.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(
      path,
      version: 7,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) await _addMissingExercises(db);
    if (oldVersion < 3) await _addBodyWeightTable(db);
    if (oldVersion < 4) await _addQuickStartTemplatesTable(db);
    if (oldVersion < 5) await _migrateV5(db);
    if (oldVersion < 6) await _migrateV6(db);
    if (oldVersion < 7) await _migrateV7(db);
  }

  Future<void> _migrateV7(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS wellness_logs (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL UNIQUE,
        sleep_hours REAL NOT NULL,
        energy INTEGER NOT NULL,
        soreness INTEGER NOT NULL,
        notes TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS achievements_unlocked (
        achievement_id TEXT PRIMARY KEY,
        unlocked_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _migrateV6(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS exercise_prs (
        exercise_id TEXT PRIMARY KEY,
        best_1rm REAL NOT NULL,
        date TEXT NOT NULL
      )
    ''');
  }

  Future<void> _migrateV5(Database db) async {
    await db.execute('ALTER TABLE exercises ADD COLUMN exercise_type TEXT DEFAULT "strength"');
    await db.execute('ALTER TABLE set_logs ADD COLUMN is_completed INTEGER DEFAULT 0');
    await db.execute('ALTER TABLE set_logs ADD COLUMN duration_seconds INTEGER');
    await db.execute('ALTER TABLE set_logs ADD COLUMN speed REAL');
    await db.execute('ALTER TABLE set_logs ADD COLUMN incline REAL');
    await db.execute('ALTER TABLE set_logs ADD COLUMN resistance REAL');
    await db.execute('ALTER TABLE set_logs ADD COLUMN distance_km REAL');
    await db.execute('ALTER TABLE workout_logs ADD COLUMN duration_seconds INTEGER');
  }

  Future<void> _addQuickStartTemplatesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS quick_start_templates (
        name TEXT PRIMARY KEY,
        exercise_ids_json TEXT NOT NULL
      )
    ''');
  }

  Future<void> _addBodyWeightTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS body_weight_logs (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL,
        weight_kg REAL NOT NULL,
        notes TEXT
      )
    ''');
  }

  Future<void> _addMissingExercises(Database db) async {
    const uuid = Uuid();
    final toAdd = [
      {'name': 'Goblet Squat', 'group': 'Legs', 'equip': 'Kettlebell'},
      {'name': 'Hip Thrust', 'group': 'Legs', 'equip': 'Barbell'},
      {'name': 'Walking Lunges', 'group': 'Legs', 'equip': 'Dumbbell'},
      {'name': 'Standing Calf Raise', 'group': 'Legs', 'equip': 'Machine'},
      {'name': 'Smith Machine Bench Press', 'group': 'Chest', 'equip': 'Machine'},
      {'name': 'Cable Crossover', 'group': 'Chest', 'equip': 'Cable'},
      {'name': 'Incline Push-ups', 'group': 'Chest', 'equip': 'Bodyweight'},
      {'name': 'Diamond Push-ups', 'group': 'Chest', 'equip': 'Bodyweight'},
      {'name': 'EZ Bar Curl', 'group': 'Arms', 'equip': 'Barbell'},
      {'name': 'Concentration Curl', 'group': 'Arms', 'equip': 'Dumbbell'},
      {'name': 'Incline DB Curl', 'group': 'Arms', 'equip': 'Dumbbell'},
      {'name': 'Bench Dips', 'group': 'Arms', 'equip': 'Bodyweight'},
      {'name': 'Assisted Pull-up', 'group': 'Back', 'equip': 'Machine'},
      {'name': 'Chest Supported Row', 'group': 'Back', 'equip': 'Machine'},
      {'name': 'Single Arm DB Row', 'group': 'Back', 'equip': 'Dumbbell'},
      {'name': 'Arnold Press', 'group': 'Shoulders', 'equip': 'Dumbbell'},
      {'name': 'Face Pulls', 'group': 'Shoulders', 'equip': 'Cable'},
    ];
    for (final e in toAdd) {
      final existing = await db.query(
        'exercises',
        where: 'LOWER(name) = LOWER(?)',
        whereArgs: [e['name']],
        limit: 1,
      );
      if (existing.isEmpty) {
        await db.insert('exercises', {
          'id': uuid.v4(),
          'name': e['name'],
          'muscle_group': e['group'],
          'equipment': e['equip'],
          'is_custom': 0,
        });
      }
    }
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE exercises (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        muscle_group TEXT NOT NULL,
        equipment TEXT NOT NULL,
        is_custom INTEGER NOT NULL DEFAULT 0,
        exercise_type TEXT NOT NULL DEFAULT 'strength'
      )
    ''');

    await db.execute('''
      CREATE TABLE workout_plan_days (
        id TEXT PRIMARY KEY,
        day_of_week INTEGER NOT NULL UNIQUE,
        workout_name TEXT NOT NULL,
        is_rest_day INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE plan_day_exercises (
        id TEXT PRIMARY KEY,
        plan_day_id TEXT NOT NULL,
        exercise_id TEXT NOT NULL,
        order_index INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE day_overrides (
        date TEXT PRIMARY KEY,
        exercise_ids_json TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE workout_logs (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL,
        plan_day_id TEXT,
        workout_name TEXT NOT NULL,
        notes TEXT,
        completed INTEGER NOT NULL DEFAULT 0,
        duration_seconds INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE exercise_logs (
        id TEXT PRIMARY KEY,
        workout_log_id TEXT NOT NULL,
        exercise_id TEXT NOT NULL,
        order_index INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE set_logs (
        id TEXT PRIMARY KEY,
        exercise_log_id TEXT NOT NULL,
        set_number INTEGER NOT NULL,
        weight REAL,
        reps INTEGER,
        notes TEXT,
        is_completed INTEGER DEFAULT 0,
        duration_seconds INTEGER,
        speed REAL,
        incline REAL,
        resistance REAL,
        distance_km REAL
      )
    ''');

    await db.execute('''
      CREATE TABLE body_weight_logs (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL,
        weight_kg REAL NOT NULL,
        notes TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE quick_start_templates (
        name TEXT PRIMARY KEY,
        exercise_ids_json TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE exercise_prs (
        exercise_id TEXT PRIMARY KEY,
        best_1rm REAL NOT NULL,
        date TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE wellness_logs (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL UNIQUE,
        sleep_hours REAL NOT NULL,
        energy INTEGER NOT NULL,
        soreness INTEGER NOT NULL,
        notes TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE achievements_unlocked (
        achievement_id TEXT PRIMARY KEY,
        unlocked_at TEXT NOT NULL
      )
    ''');

    await _seedDefaultExercises(db);
    await _seedPplWeeklyPlan(db);
  }

  static const _kPplSchedule = [
    (1, 'Push A', false, ['Bench Press', 'Incline Dumbbell Press', 'Cable Flyes', 'Dumbbell Shoulder Press', 'Lateral Raises', 'Tricep Pushdown', 'Overhead Tricep Extension']),
    (2, 'Pull A', false, ['Assisted Pull-up', 'Barbell Row', 'Seated Cable Row', 'Lat Pulldown', 'Hammer Curl', 'EZ Bar Curl', 'Face Pulls']),
    (3, 'Legs A', false, ['Squat', 'Leg Press', 'Leg Extension', 'Walking Lunges', 'Romanian Deadlift', 'Seated Calf Raises']),
    (4, 'Push B', false, ['Smith Machine Bench Press', 'Cable Crossover', 'Incline Push-ups', 'Arnold Press', 'Rear Delt Flyes', 'Tricep Dips', 'Skull Crushers']),
    (5, 'Pull B', false, ['Deadlift', 'Single Arm DB Row', 'Chest Supported Row', 'Lat Pulldown', 'Incline DB Curl', 'Concentration Curl', 'Face Pulls']),
    (6, 'Legs B', false, ['Romanian Deadlift', 'Leg Curl', 'Goblet Squat', 'Leg Press', 'Hip Thrust', 'Standing Calf Raise', 'Plank']),
    (7, 'Rest', true, <String>[]),
  ];

  static const _kStrengthSchedule = [
    (1, 'Upper A', false, ['Bench Press', 'Barbell Row', 'Overhead Press', 'Pull-ups', 'Tricep Pushdown', 'Barbell Curl']),
    (2, 'Lower A', false, ['Squat', 'Romanian Deadlift', 'Leg Press', 'Leg Curl', 'Calf Raises']),
    (3, 'Rest', true, <String>[]),
    (4, 'Upper B', false, ['Incline Bench Press', 'Seated Cable Row', 'Lateral Raises', 'Hammer Curl', 'Skull Crushers']),
    (5, 'Lower B', false, ['Deadlift', 'Hack Squat', 'Walking Lunges', 'Leg Extension', 'Seated Calf Raises']),
    (6, 'Rest', true, <String>[]),
    (7, 'Rest', true, <String>[]),
  ];

  static const _kWeightLossSchedule = [
    (1, 'Full Body A', false, ['Squat', 'Bench Press', 'Barbell Row', 'Overhead Press', 'Plank']),
    (2, 'Rest', true, <String>[]),
    (3, 'Full Body B', false, ['Deadlift', 'Incline Bench Press', 'Pull-ups', 'Lateral Raises', 'Mountain Climbers']),
    (4, 'Rest', true, <String>[]),
    (5, 'Full Body C', false, ['Leg Press', 'Incline Dumbbell Press', 'Seated Cable Row', 'Tricep Pushdown', 'Barbell Curl']),
    (6, 'Rest', true, <String>[]),
    (7, 'Rest', true, <String>[]),
  ];

  static const _kGeneralFitnessSchedule = [
    (1, 'Workout A', false, ['Squat', 'Bench Press', 'Barbell Row']),
    (2, 'Rest', true, <String>[]),
    (3, 'Workout B', false, ['Overhead Press', 'Deadlift', 'Pull-ups']),
    (4, 'Rest', true, <String>[]),
    (5, 'Workout A', false, ['Squat', 'Bench Press', 'Barbell Row']),
    (6, 'Rest', true, <String>[]),
    (7, 'Rest', true, <String>[]),
  ];

  Future<void> _seedSchedule(
      Database db, List<(int, String, bool, List<String>)> schedule) async {
    const uuid = Uuid();
    for (final (dow, name, isRest, exNames) in schedule) {
      final dayId = uuid.v4();
      await db.insert('workout_plan_days', {
        'id': dayId,
        'day_of_week': dow,
        'workout_name': name,
        'is_rest_day': isRest ? 1 : 0,
      });
      for (int i = 0; i < exNames.length; i++) {
        final rows = await db.query('exercises',
            where: 'LOWER(name) = LOWER(?)', whereArgs: [exNames[i]], limit: 1);
        if (rows.isEmpty) continue;
        await db.insert('plan_day_exercises', {
          'id': uuid.v4(),
          'plan_day_id': dayId,
          'exercise_id': rows.first['id'],
          'order_index': i,
        });
      }
    }
  }

  Future<void> _ensureExercise(
      Database db, String name, String group, String equip) async {
    final existing = await db.query('exercises',
        where: 'LOWER(name) = LOWER(?)', whereArgs: [name], limit: 1);
    if (existing.isEmpty) {
      await db.insert('exercises', {
        'id': const Uuid().v4(),
        'name': name,
        'muscle_group': group,
        'equipment': equip,
        'is_custom': 0,
        'exercise_type': 'strength',
      });
    }
  }

  Future<void> _seedPplWeeklyPlan(Database db) async =>
      _seedSchedule(db, _kPplSchedule);

  /// Replaces the entire weekly plan with the 6-day PPL schedule.
  Future<void> loadPplWeeklyPlan() async {
    final db = await database;
    for (final (dow, _, _, _) in _kPplSchedule) {
      await deletePlanDay(dow);
    }
    await _seedPplWeeklyPlan(db);
  }

  /// Seeds a full weekly plan matching the given goal key.
  /// Clears all existing plan days first.
  Future<void> seedGoalPlan(String goal) async {
    final db = await database;
    for (int i = 1; i <= 7; i++) {
      await deletePlanDay(i);
    }
    switch (goal) {
      case 'muscle_gain':
        await _seedSchedule(db, _kPplSchedule);
      case 'strength':
        await _seedSchedule(db, _kStrengthSchedule);
      case 'weight_loss':
        await _ensureExercise(db, 'Mountain Climbers', 'Core', 'Bodyweight');
        await _seedSchedule(db, _kWeightLossSchedule);
      case 'general_fitness':
        await _seedSchedule(db, _kGeneralFitnessSchedule);
    }
  }

  Future<void> _seedDefaultExercises(Database db) async {
    const uuid = Uuid();
    final exercises = [
      // Chest
      {'name': 'Bench Press', 'group': 'Chest', 'equip': 'Barbell'},
      {'name': 'Incline Bench Press', 'group': 'Chest', 'equip': 'Barbell'},
      {'name': 'Decline Bench Press', 'group': 'Chest', 'equip': 'Barbell'},
      {'name': 'Dumbbell Flyes', 'group': 'Chest', 'equip': 'Dumbbell'},
      {'name': 'Incline Dumbbell Press', 'group': 'Chest', 'equip': 'Dumbbell'},
      {'name': 'Cable Flyes', 'group': 'Chest', 'equip': 'Cable'},
      {'name': 'Push-ups', 'group': 'Chest', 'equip': 'Bodyweight'},
      {'name': 'Chest Dips', 'group': 'Chest', 'equip': 'Bodyweight'},
      {'name': 'Smith Machine Bench Press', 'group': 'Chest', 'equip': 'Machine'},
      {'name': 'Cable Crossover', 'group': 'Chest', 'equip': 'Cable'},
      {'name': 'Incline Push-ups', 'group': 'Chest', 'equip': 'Bodyweight'},
      {'name': 'Diamond Push-ups', 'group': 'Chest', 'equip': 'Bodyweight'},
      // Back
      {'name': 'Deadlift', 'group': 'Back', 'equip': 'Barbell'},
      {'name': 'Barbell Row', 'group': 'Back', 'equip': 'Barbell'},
      {'name': 'Pull-ups', 'group': 'Back', 'equip': 'Bodyweight'},
      {'name': 'Chin-ups', 'group': 'Back', 'equip': 'Bodyweight'},
      {'name': 'Lat Pulldown', 'group': 'Back', 'equip': 'Cable'},
      {'name': 'Seated Cable Row', 'group': 'Back', 'equip': 'Cable'},
      {'name': 'Dumbbell Row', 'group': 'Back', 'equip': 'Dumbbell'},
      {'name': 'T-Bar Row', 'group': 'Back', 'equip': 'Barbell'},
      {'name': 'Hyperextensions', 'group': 'Back', 'equip': 'Machine'},
      {'name': 'Assisted Pull-up', 'group': 'Back', 'equip': 'Machine'},
      {'name': 'Chest Supported Row', 'group': 'Back', 'equip': 'Machine'},
      {'name': 'Single Arm DB Row', 'group': 'Back', 'equip': 'Dumbbell'},
      // Shoulders
      {'name': 'Overhead Press', 'group': 'Shoulders', 'equip': 'Barbell'},
      {'name': 'Dumbbell Shoulder Press', 'group': 'Shoulders', 'equip': 'Dumbbell'},
      {'name': 'Lateral Raises', 'group': 'Shoulders', 'equip': 'Dumbbell'},
      {'name': 'Front Raises', 'group': 'Shoulders', 'equip': 'Dumbbell'},
      {'name': 'Rear Delt Flyes', 'group': 'Shoulders', 'equip': 'Dumbbell'},
      {'name': 'Arnold Press', 'group': 'Shoulders', 'equip': 'Dumbbell'},
      {'name': 'Face Pulls', 'group': 'Shoulders', 'equip': 'Cable'},
      {'name': 'Upright Row', 'group': 'Shoulders', 'equip': 'Barbell'},
      // Arms
      {'name': 'Barbell Curl', 'group': 'Arms', 'equip': 'Barbell'},
      {'name': 'Dumbbell Curl', 'group': 'Arms', 'equip': 'Dumbbell'},
      {'name': 'Hammer Curl', 'group': 'Arms', 'equip': 'Dumbbell'},
      {'name': 'Preacher Curl', 'group': 'Arms', 'equip': 'Machine'},
      {'name': 'Cable Curl', 'group': 'Arms', 'equip': 'Cable'},
      {'name': 'Tricep Pushdown', 'group': 'Arms', 'equip': 'Cable'},
      {'name': 'Skull Crushers', 'group': 'Arms', 'equip': 'Barbell'},
      {'name': 'Overhead Tricep Extension', 'group': 'Arms', 'equip': 'Dumbbell'},
      {'name': 'Tricep Dips', 'group': 'Arms', 'equip': 'Bodyweight'},
      {'name': 'Close-Grip Bench Press', 'group': 'Arms', 'equip': 'Barbell'},
      {'name': 'EZ Bar Curl', 'group': 'Arms', 'equip': 'Barbell'},
      {'name': 'Concentration Curl', 'group': 'Arms', 'equip': 'Dumbbell'},
      {'name': 'Incline DB Curl', 'group': 'Arms', 'equip': 'Dumbbell'},
      {'name': 'Bench Dips', 'group': 'Arms', 'equip': 'Bodyweight'},
      // Legs
      {'name': 'Squat', 'group': 'Legs', 'equip': 'Barbell'},
      {'name': 'Front Squat', 'group': 'Legs', 'equip': 'Barbell'},
      {'name': 'Leg Press', 'group': 'Legs', 'equip': 'Machine'},
      {'name': 'Romanian Deadlift', 'group': 'Legs', 'equip': 'Barbell'},
      {'name': 'Leg Curl', 'group': 'Legs', 'equip': 'Machine'},
      {'name': 'Leg Extension', 'group': 'Legs', 'equip': 'Machine'},
      {'name': 'Lunges', 'group': 'Legs', 'equip': 'Dumbbell'},
      {'name': 'Bulgarian Split Squat', 'group': 'Legs', 'equip': 'Dumbbell'},
      {'name': 'Hack Squat', 'group': 'Legs', 'equip': 'Machine'},
      {'name': 'Calf Raises', 'group': 'Legs', 'equip': 'Machine'},
      {'name': 'Seated Calf Raises', 'group': 'Legs', 'equip': 'Machine'},
      {'name': 'Goblet Squat', 'group': 'Legs', 'equip': 'Kettlebell'},
      {'name': 'Hip Thrust', 'group': 'Legs', 'equip': 'Barbell'},
      {'name': 'Walking Lunges', 'group': 'Legs', 'equip': 'Dumbbell'},
      {'name': 'Standing Calf Raise', 'group': 'Legs', 'equip': 'Machine'},
      // Core
      {'name': 'Plank', 'group': 'Core', 'equip': 'Bodyweight'},
      {'name': 'Crunches', 'group': 'Core', 'equip': 'Bodyweight'},
      {'name': 'Russian Twists', 'group': 'Core', 'equip': 'Bodyweight'},
      {'name': 'Leg Raises', 'group': 'Core', 'equip': 'Bodyweight'},
      {'name': 'Mountain Climbers', 'group': 'Core', 'equip': 'Bodyweight'},
      {'name': 'Cable Crunches', 'group': 'Core', 'equip': 'Cable'},
      {'name': 'Ab Wheel Rollout', 'group': 'Core', 'equip': 'Other'},
      {'name': 'Hanging Leg Raises', 'group': 'Core', 'equip': 'Bodyweight'},
      // Cardio
      {'name': 'Treadmill Run', 'group': 'Cardio', 'equip': 'Machine'},
      {'name': 'Cycling', 'group': 'Cardio', 'equip': 'Machine'},
      {'name': 'Jump Rope', 'group': 'Cardio', 'equip': 'Other'},
      {'name': 'Rowing Machine', 'group': 'Cardio', 'equip': 'Machine'},
      {'name': 'Stair Climber', 'group': 'Cardio', 'equip': 'Machine'},
    ];

    final batch = db.batch();
    for (final e in exercises) {
      batch.insert('exercises', {
        'id': uuid.v4(),
        'name': e['name'],
        'muscle_group': e['group'],
        'equipment': e['equip'],
        'is_custom': 0,
      });
    }
    await batch.commit(noResult: true);
  }

  // ─── EXERCISES ──────────────────────────────────────────────────────────────

  Future<List<Exercise>> getAllExercises({String? muscleGroup}) async {
    final db = await database;
    if (muscleGroup != null && muscleGroup.isNotEmpty) {
      final maps = await db.query(
        'exercises',
        where: 'muscle_group = ?',
        whereArgs: [muscleGroup],
        orderBy: 'name ASC',
      );
      return maps.map(Exercise.fromMap).toList();
    }
    final maps = await db.query('exercises', orderBy: 'muscle_group ASC, name ASC');
    return maps.map(Exercise.fromMap).toList();
  }

  Future<Exercise?> getExerciseById(String id) async {
    final db = await database;
    final maps = await db.query('exercises', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Exercise.fromMap(maps.first);
  }

  Future<List<Exercise>> searchExercises(String query, {String? muscleGroup}) async {
    final db = await database;
    final where = StringBuffer('name LIKE ?');
    final args = <Object>['%$query%'];
    if (muscleGroup != null && muscleGroup.isNotEmpty) {
      where.write(' AND muscle_group = ?');
      args.add(muscleGroup);
    }
    final maps = await db.query(
      'exercises',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'name ASC',
    );
    return maps.map(Exercise.fromMap).toList();
  }

  Future<Exercise> createExercise(Exercise exercise) async {
    final db = await database;
    await db.insert('exercises', exercise.toMap());
    return exercise;
  }

  Future<void> updateExercise(Exercise exercise) async {
    final db = await database;
    await db.update('exercises', exercise.toMap(),
        where: 'id = ?', whereArgs: [exercise.id]);
  }

  Future<void> deleteExercise(String id) async {
    final db = await database;
    await db.delete('exercises', where: 'id = ?', whereArgs: [id]);
  }

  // ─── WORKOUT PLAN ────────────────────────────────────────────────────────────

  Future<List<WorkoutPlanDay>> getWorkoutPlan() async {
    final db = await database;
    final dayMaps = await db.query('workout_plan_days', orderBy: 'day_of_week ASC');
    final days = <WorkoutPlanDay>[];
    for (final dayMap in dayMaps) {
      final day = WorkoutPlanDay.fromMap(dayMap);
      final exMaps = await db.query(
        'plan_day_exercises',
        where: 'plan_day_id = ?',
        whereArgs: [day.id],
        orderBy: 'order_index ASC',
      );
      days.add(day.copyWith(
        exerciseIds: exMaps.map((m) => m['exercise_id'] as String).toList(),
      ));
    }
    return days;
  }

  Future<WorkoutPlanDay?> getPlanDayForWeekday(int dayOfWeek) async {
    final db = await database;
    final maps = await db.query(
      'workout_plan_days',
      where: 'day_of_week = ?',
      whereArgs: [dayOfWeek],
    );
    if (maps.isEmpty) return null;
    final day = WorkoutPlanDay.fromMap(maps.first);
    final exMaps = await db.query(
      'plan_day_exercises',
      where: 'plan_day_id = ?',
      whereArgs: [day.id],
      orderBy: 'order_index ASC',
    );
    return day.copyWith(
      exerciseIds: exMaps.map((m) => m['exercise_id'] as String).toList(),
    );
  }

  Future<void> savePlanDay(WorkoutPlanDay day) async {
    final db = await database;
    await db.insert(
      'workout_plan_days',
      day.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await db.delete('plan_day_exercises',
        where: 'plan_day_id = ?', whereArgs: [day.id]);
    const uuid = Uuid();
    final batch = db.batch();
    for (int i = 0; i < day.exerciseIds.length; i++) {
      batch.insert('plan_day_exercises', {
        'id': uuid.v4(),
        'plan_day_id': day.id,
        'exercise_id': day.exerciseIds[i],
        'order_index': i,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<void> deletePlanDay(int dayOfWeek) async {
    final db = await database;
    final maps = await db.query(
      'workout_plan_days',
      where: 'day_of_week = ?',
      whereArgs: [dayOfWeek],
    );
    if (maps.isEmpty) return;
    final id = maps.first['id'] as String;
    await db.delete('plan_day_exercises', where: 'plan_day_id = ?', whereArgs: [id]);
    await db.delete('workout_plan_days', where: 'id = ?', whereArgs: [id]);
  }

  // ─── DAY OVERRIDES ──────────────────────────────────────────────────────────

  Future<List<String>?> getDayOverride(String date) async {
    final db = await database;
    final maps = await db.query('day_overrides', where: 'date = ?', whereArgs: [date]);
    if (maps.isEmpty) return null;
    final json = maps.first['exercise_ids_json'] as String;
    return List<String>.from(jsonDecode(json) as List);
  }

  Future<void> saveDayOverride(String date, List<String> exerciseIds) async {
    final db = await database;
    await db.insert(
      'day_overrides',
      {'date': date, 'exercise_ids_json': jsonEncode(exerciseIds)},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteDayOverride(String date) async {
    final db = await database;
    await db.delete('day_overrides', where: 'date = ?', whereArgs: [date]);
  }

  // ─── WORKOUT LOGS ────────────────────────────────────────────────────────────

  Future<WorkoutLog?> getWorkoutLogForDate(String date) async {
    final db = await database;
    final maps = await db.query('workout_logs', where: 'date = ?', whereArgs: [date]);
    if (maps.isEmpty) return null;
    final log = WorkoutLog.fromMap(maps.first);
    final exerciseLogs = await _getExerciseLogs(db, log.id);
    log.exercises.addAll(exerciseLogs);
    return log;
  }

  Future<List<WorkoutLog>> getAllWorkoutLogs() async {
    final db = await database;
    final maps = await db.query('workout_logs', orderBy: 'date DESC');
    final logs = <WorkoutLog>[];
    for (final map in maps) {
      final log = WorkoutLog.fromMap(map);
      log.exercises.addAll(await _getExerciseLogs(db, log.id));
      logs.add(log);
    }
    return logs;
  }

  Future<List<ExerciseLog>> _getExerciseLogs(
      Database db, String workoutLogId) async {
    final maps = await db.query(
      'exercise_logs',
      where: 'workout_log_id = ?',
      whereArgs: [workoutLogId],
      orderBy: 'order_index ASC',
    );
    final exLogs = <ExerciseLog>[];
    for (final map in maps) {
      final exLog = ExerciseLog.fromMap(map);
      final setMaps = await db.query(
        'set_logs',
        where: 'exercise_log_id = ?',
        whereArgs: [exLog.id],
        orderBy: 'set_number ASC',
      );
      exLog.sets.addAll(setMaps.map(SetLog.fromMap));
      exLogs.add(exLog);
    }
    return exLogs;
  }

  Future<WorkoutLog> createOrGetWorkoutLog(WorkoutLog log) async {
    final existing = await getWorkoutLogForDate(log.date);
    if (existing != null) return existing;
    final db = await database;
    await db.insert('workout_logs', log.toMap());
    return log;
  }

  Future<void> updateWorkoutLog(WorkoutLog log) async {
    final db = await database;
    await db.update('workout_logs', log.toMap(),
        where: 'id = ?', whereArgs: [log.id]);
  }

  Future<void> deleteWorkoutLog(String id) async {
    final db = await database;
    final exLogs = await db.query('exercise_logs',
        where: 'workout_log_id = ?', whereArgs: [id], columns: ['id']);
    for (final e in exLogs) {
      await db.delete('set_logs',
          where: 'exercise_log_id = ?', whereArgs: [e['id']]);
    }
    await db.delete('exercise_logs', where: 'workout_log_id = ?', whereArgs: [id]);
    await db.delete('workout_logs', where: 'id = ?', whereArgs: [id]);
  }

  Future<ExerciseLog> createExerciseLog(ExerciseLog exLog) async {
    final db = await database;
    await db.insert('exercise_logs', exLog.toMap());
    return exLog;
  }

  Future<void> deleteExerciseLog(String id) async {
    final db = await database;
    await db.delete('set_logs', where: 'exercise_log_id = ?', whereArgs: [id]);
    await db.delete('exercise_logs', where: 'id = ?', whereArgs: [id]);
  }

  Future<SetLog> createSetLog(SetLog setLog) async {
    final db = await database;
    await db.insert('set_logs', setLog.toMap());
    return setLog;
  }

  Future<void> updateSetLog(SetLog setLog) async {
    final db = await database;
    await db.update('set_logs', setLog.toMap(),
        where: 'id = ?', whereArgs: [setLog.id]);
  }

  Future<void> deleteSetLog(String id) async {
    final db = await database;
    await db.delete('set_logs', where: 'id = ?', whereArgs: [id]);
  }

  // ─── PROGRESS / ANALYTICS ───────────────────────────────────────────────────

  /// Returns sets grouped by session for the last [n] completed sessions
  /// that included this exercise, newest session first.
  Future<List<List<SetLog>>> getLastNSessionsForExercise(
      String exerciseId, int n) async {
    final db = await database;
    final sessions = await db.rawQuery('''
      SELECT DISTINCT wl.id
      FROM workout_logs wl
      INNER JOIN exercise_logs el ON el.workout_log_id = wl.id
      WHERE el.exercise_id = ? AND wl.completed = 1
      ORDER BY wl.date DESC
      LIMIT ?
    ''', [exerciseId, n]);
    final result = <List<SetLog>>[];
    for (final session in sessions) {
      final setMaps = await db.rawQuery('''
        SELECT sl.* FROM set_logs sl
        INNER JOIN exercise_logs el ON sl.exercise_log_id = el.id
        WHERE el.workout_log_id = ? AND el.exercise_id = ?
        ORDER BY sl.set_number ASC
      ''', [session['id'], exerciseId]);
      result.add(setMaps.map(SetLog.fromMap).toList());
    }
    return result;
  }

  Future<double?> getBest1RM(String exerciseId) async {
    final db = await database;
    final rows = await db.query('exercise_prs',
        where: 'exercise_id = ?', whereArgs: [exerciseId], limit: 1);
    if (rows.isEmpty) return null;
    return (rows.first['best_1rm'] as num).toDouble();
  }

  Future<void> updateBest1RM(
      String exerciseId, double orm, String date) async {
    final db = await database;
    await db.insert(
      'exercise_prs',
      {'exercise_id': exerciseId, 'best_1rm': orm, 'date': date},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Returns the last completed sets for an exercise, most recent first.
  Future<List<SetLog>> getLastSetsForExercise(String exerciseId,
      {int limit = 10}) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT sl.* FROM set_logs sl
      INNER JOIN exercise_logs el ON sl.exercise_log_id = el.id
      INNER JOIN workout_logs wl ON el.workout_log_id = wl.id
      WHERE el.exercise_id = ? AND wl.completed = 1
      ORDER BY wl.date DESC, sl.set_number ASC
      LIMIT ?
    ''', [exerciseId, limit]);
    return maps.map(SetLog.fromMap).toList();
  }

  /// Returns best weight per date for a given exercise (for the progress chart).
  /// Optionally filtered by [fromDate] and [toDate] (inclusive, 'YYYY-MM-DD').
  Future<List<Map<String, dynamic>>> getProgressForExercise(
      String exerciseId, {String? fromDate, String? toDate}) async {
    final db = await database;
    final where = StringBuffer(
        'el.exercise_id = ? AND sl.weight IS NOT NULL AND wl.completed = 1');
    final args = <dynamic>[exerciseId];
    if (fromDate != null) {
      where.write(' AND wl.date >= ?');
      args.add(fromDate);
    }
    if (toDate != null) {
      where.write(' AND wl.date <= ?');
      args.add(toDate);
    }
    return db.rawQuery('''
      SELECT wl.date, MAX(sl.weight) as max_weight, sl.reps
      FROM set_logs sl
      INNER JOIN exercise_logs el ON sl.exercise_log_id = el.id
      INNER JOIN workout_logs wl ON el.workout_log_id = wl.id
      WHERE ${where.toString()}
      GROUP BY wl.date
      ORDER BY wl.date ASC
    ''', args);
  }

  /// Looks up exercises by exact name (case-insensitive). Used by Quick Start.
  Future<List<Exercise>> getExercisesByNames(List<String> names) async {
    final db = await database;
    final results = <Exercise>[];
    for (final name in names) {
      final maps = await db.query('exercises',
          where: 'LOWER(name) = LOWER(?)', whereArgs: [name], limit: 1);
      if (maps.isNotEmpty) results.add(Exercise.fromMap(maps.first));
    }
    return results;
  }

  /// Returns up to [limit] exercises matching any of [groups]. Used by Quick Start.
  Future<List<Exercise>> getExercisesByMuscleGroups(List<String> groups,
      {int limit = 8}) async {
    final db = await database;
    final placeholders = groups.map((_) => '?').join(',');
    final maps = await db.query(
      'exercises',
      where: 'muscle_group IN ($placeholders)',
      whereArgs: groups,
      orderBy: 'is_custom DESC, name ASC',
      limit: limit,
    );
    return maps.map(Exercise.fromMap).toList();
  }

  Future<Map<String, dynamic>?> getPRForExercise(String exerciseId) async {
    final db = await database;
    final results = await db.rawQuery('''
      SELECT sl.weight, sl.reps, wl.date
      FROM set_logs sl
      INNER JOIN exercise_logs el ON sl.exercise_log_id = el.id
      INNER JOIN workout_logs wl ON el.workout_log_id = wl.id
      WHERE el.exercise_id = ? AND sl.weight IS NOT NULL AND wl.completed = 1
      ORDER BY sl.weight DESC
      LIMIT 1
    ''', [exerciseId]);
    return results.isEmpty ? null : Map<String, dynamic>.from(results.first);
  }

  Future<int> getWorkoutStreak() async {
    final db = await database;
    final logs = await db.query(
      'workout_logs',
      where: 'completed = 1',
      orderBy: 'date DESC',
      columns: ['date'],
    );
    if (logs.isEmpty) return 0;
    final dates = logs.map((l) => l['date'] as String).toSet();
    int streak = 0;
    DateTime check = DateTime.now();
    final today = _fmt(check);
    final yesterday = _fmt(check.subtract(const Duration(days: 1)));
    final latest = logs.first['date'] as String;
    if (latest != today && latest != yesterday) return 0;
    if (latest == yesterday) check = check.subtract(const Duration(days: 1));
    while (dates.contains(_fmt(check))) {
      streak++;
      check = check.subtract(const Duration(days: 1));
    }
    return streak;
  }

  Future<int> getWeeklyWorkoutCount() async {
    final db = await database;
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final count = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM workout_logs WHERE completed = 1 AND date >= ?',
      [_fmt(weekStart)],
    ));
    return count ?? 0;
  }

  Future<int> getMonthlyWorkoutCount() async {
    final db = await database;
    final now = DateTime.now();
    final from = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
    final count = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM workout_logs WHERE completed = 1 AND date >= ?',
      [from],
    ));
    return count ?? 0;
  }

  Future<Set<String>> getCompletedWorkoutDatesInRange(String fromDate, String toDate) async {
    final db = await database;
    final rows = await db.query(
      'workout_logs',
      columns: ['date'],
      where: 'completed = 1 AND date >= ? AND date <= ?',
      whereArgs: [fromDate, toDate],
    );
    return rows.map((r) => r['date'] as String).toSet();
  }

  // ─── BODY WEIGHT ────────────────────────────────────────────────────────────

  Future<void> logBodyWeight(String date, double weightKg, {String? notes}) async {
    const uuid = Uuid();
    final db = await database;
    final existing = await db.query('body_weight_logs', where: 'date = ?', whereArgs: [date]);
    if (existing.isNotEmpty) {
      await db.update('body_weight_logs', {'weight_kg': weightKg, 'notes': notes},
          where: 'date = ?', whereArgs: [date]);
    } else {
      await db.insert('body_weight_logs', {
        'id': uuid.v4(),
        'date': date,
        'weight_kg': weightKg,
        'notes': notes,
      });
    }
  }

  Future<List<Map<String, dynamic>>> getBodyWeightLogs(
      {String? fromDate, String? toDate}) async {
    final db = await database;
    final where = StringBuffer('1=1');
    final args = <dynamic>[];
    if (fromDate != null) { where.write(' AND date >= ?'); args.add(fromDate); }
    if (toDate != null) { where.write(' AND date <= ?'); args.add(toDate); }
    return db.rawQuery(
        'SELECT date, weight_kg FROM body_weight_logs WHERE ${where.toString()} ORDER BY date ASC',
        args);
  }

  Future<double?> getLatestBodyWeight() async {
    final db = await database;
    final rows = await db.query('body_weight_logs',
        orderBy: 'date DESC', limit: 1, columns: ['weight_kg']);
    if (rows.isEmpty) return null;
    return (rows.first['weight_kg'] as num).toDouble();
  }

  // ─── QUICK START TEMPLATES ──────────────────────────────────────────────────

  Future<void> saveQuickStartTemplate(String name, List<String> exerciseIds) async {
    final db = await database;
    await db.insert(
      'quick_start_templates',
      {'name': name, 'exercise_ids_json': jsonEncode(exerciseIds)},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<String>?> getQuickStartTemplate(String name) async {
    final db = await database;
    final rows = await db.query('quick_start_templates',
        where: 'name = ?', whereArgs: [name]);
    if (rows.isEmpty) return null;
    return List<String>.from(
        jsonDecode(rows.first['exercise_ids_json'] as String) as List);
  }

  // ─── EXERCISE TRACKER ANALYTICS ─────────────────────────────────────────────

  /// Returns all exercises that have at least one set logged in a completed
  /// workout, with PR, last weight, gain, and sparkline values.
  Future<List<Map<String, dynamic>>> getTrackedExerciseSummaries() async {
    final db = await database;
    // One row per exercise: PR, session count, last session date
    final rows = await db.rawQuery('''
      SELECT el.exercise_id,
             MAX(sl.weight) as pr,
             COUNT(DISTINCT wl.id) as sessions,
             MAX(wl.date) as last_date
      FROM exercise_logs el
      INNER JOIN set_logs sl ON sl.exercise_log_id = el.id
      INNER JOIN workout_logs wl ON el.workout_log_id = wl.id
      WHERE wl.completed = 1 AND sl.weight IS NOT NULL
      GROUP BY el.exercise_id
      ORDER BY sessions DESC, pr DESC
    ''');

    final result = <Map<String, dynamic>>[];
    for (final row in rows) {
      final exId = row['exercise_id'] as String;
      final ex = await getExerciseById(exId);
      if (ex == null) continue;

      // Last 9 sessions' max weight for sparkline (oldest→newest)
      final sparks = await db.rawQuery('''
        SELECT MAX(sl.weight) as w
        FROM exercise_logs el
        INNER JOIN set_logs sl ON sl.exercise_log_id = el.id
        INNER JOIN workout_logs wl ON el.workout_log_id = wl.id
        WHERE el.exercise_id = ? AND wl.completed = 1 AND sl.weight IS NOT NULL
        GROUP BY wl.date
        ORDER BY wl.date DESC
        LIMIT 9
      ''', [exId]);
      final sparkValues = sparks
          .map((r) => (r['w'] as num).toDouble())
          .toList()
          .reversed
          .toList();

      // First ever weight for delta calculation
      final firstRow = await db.rawQuery('''
        SELECT MIN(sl.weight) as fw
        FROM exercise_logs el
        INNER JOIN set_logs sl ON sl.exercise_log_id = el.id
        INNER JOIN workout_logs wl ON el.workout_log_id = wl.id
        WHERE el.exercise_id = ? AND wl.completed = 1 AND sl.weight IS NOT NULL
      ''', [exId]);
      final firstWeight =
          (firstRow.firstOrNull?['fw'] as num?)?.toDouble() ?? 0.0;

      result.add({
        'exercise': ex,
        'pr': (row['pr'] as num).toDouble(),
        'sessions': row['sessions'] as int,
        'last_date': row['last_date'] as String,
        'sparkline': sparkValues,
        'last_weight': sparkValues.isNotEmpty ? sparkValues.last : 0.0,
        'gain': (row['pr'] as num).toDouble() - firstWeight,
      });
    }
    return result;
  }

  /// Time-series data for a specific exercise, grouped by date.
  /// [metric]: 'orm' (Epley 1RM), 'weight' (top set), 'volume' (session total)
  Future<List<Map<String, dynamic>>> getExerciseChartData(
    String exerciseId,
    String metric,
    String fromDate,
  ) async {
    final db = await database;
    String selectExpr;
    switch (metric) {
      case 'orm':
        selectExpr =
            'MAX(sl.weight * (1.0 + COALESCE(sl.reps, 0) / 30.0)) as value';
        break;
      case 'volume':
        selectExpr =
            'SUM(COALESCE(sl.weight, 0) * COALESCE(sl.reps, 0)) as value';
        break;
      default: // weight
        selectExpr = 'MAX(sl.weight) as value';
    }
    final rows = await db.rawQuery('''
      SELECT wl.date, $selectExpr
      FROM exercise_logs el
      INNER JOIN set_logs sl ON sl.exercise_log_id = el.id
      INNER JOIN workout_logs wl ON el.workout_log_id = wl.id
      WHERE el.exercise_id = ? AND wl.completed = 1
            AND sl.weight IS NOT NULL AND wl.date >= ?
      GROUP BY wl.date
      ORDER BY wl.date ASC
    ''', [exerciseId, fromDate]);
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// Last [limit] sessions for an exercise with per-set breakdown.
  Future<List<Map<String, dynamic>>> getRecentSessionsForExercise(
    String exerciseId, {
    int limit = 5,
  }) async {
    final db = await database;
    final sessionRows = await db.rawQuery('''
      SELECT DISTINCT wl.id, wl.date, MAX(sl.weight) as top_weight
      FROM exercise_logs el
      INNER JOIN set_logs sl ON sl.exercise_log_id = el.id
      INNER JOIN workout_logs wl ON el.workout_log_id = wl.id
      WHERE el.exercise_id = ? AND wl.completed = 1 AND sl.weight IS NOT NULL
      GROUP BY wl.id, wl.date
      ORDER BY wl.date DESC
      LIMIT ?
    ''', [exerciseId, limit]);

    final sessions = <Map<String, dynamic>>[];
    double allTimePR = 0;
    for (final row in sessionRows) {
      final w = (row['top_weight'] as num).toDouble();
      if (w > allTimePR) allTimePR = w;
    }

    for (final row in sessionRows) {
      final wlId = row['id'] as String;
      final setRows = await db.rawQuery('''
        SELECT sl.weight, sl.reps
        FROM set_logs sl
        INNER JOIN exercise_logs el ON sl.exercise_log_id = el.id
        WHERE el.workout_log_id = ? AND el.exercise_id = ?
        ORDER BY sl.set_number ASC
      ''', [wlId, exerciseId]);

      final sets = setRows
          .where((s) => s['weight'] != null)
          .map((s) => {
                'weight': (s['weight'] as num).toDouble(),
                'reps': s['reps'] as int? ?? 0,
              })
          .toList();
      if (sets.isEmpty) continue;

      final topW = (row['top_weight'] as num).toDouble();
      final topSet = sets.firstWhere(
        (s) => (s['weight'] as double) == topW,
        orElse: () => sets.last,
      );

      sessions.add({
        'date': row['date'] as String,
        'sets': sets,
        'top_weight': topW,
        'top_reps': topSet['reps'] as int,
        'is_pr': topW >= allTimePR,
      });
    }
    // Only mark the most recent session as PR if it actually is
    if (sessions.isNotEmpty) {
      final first = sessions.first;
      sessions.first['is_pr'] =
          (first['top_weight'] as double) >= allTimePR;
    }
    return sessions;
  }

  /// PR history for an exercise (all-time bests in chronological order,
  /// returned newest-first).
  Future<List<Map<String, dynamic>>> getPRHistoryForExercise(
      String exerciseId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT wl.date, MAX(sl.weight) as max_weight
      FROM exercise_logs el
      INNER JOIN set_logs sl ON sl.exercise_log_id = el.id
      INNER JOIN workout_logs wl ON el.workout_log_id = wl.id
      WHERE el.exercise_id = ? AND wl.completed = 1 AND sl.weight IS NOT NULL
      GROUP BY wl.date
      ORDER BY wl.date ASC
    ''', [exerciseId]);

    double running = 0;
    final prs = <Map<String, dynamic>>[];
    for (final row in rows) {
      final w = (row['max_weight'] as num).toDouble();
      if (w > running) {
        prs.add({'weight': w, 'date': row['date'] as String});
        running = w;
      }
    }
    return prs.reversed.toList(); // newest first
  }

  /// Aggregate totals for an exercise (sessions, sets, reps, volume).
  Future<Map<String, dynamic>> getExerciseTotalStats(
      String exerciseId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT
        COUNT(DISTINCT wl.id) as sessions,
        COUNT(sl.id) as total_sets,
        SUM(COALESCE(sl.reps, 0)) as total_reps,
        SUM(COALESCE(sl.weight, 0) * COALESCE(sl.reps, 0)) as total_volume
      FROM exercise_logs el
      INNER JOIN set_logs sl ON sl.exercise_log_id = el.id
      INNER JOIN workout_logs wl ON el.workout_log_id = wl.id
      WHERE el.exercise_id = ? AND wl.completed = 1
    ''', [exerciseId]);
    if (rows.isEmpty) {
      return {
        'sessions': 0,
        'total_sets': 0,
        'total_reps': 0,
        'total_volume': 0.0,
      };
    }
    return {
      'sessions': rows.first['sessions'] as int? ?? 0,
      'total_sets': rows.first['total_sets'] as int? ?? 0,
      'total_reps': rows.first['total_reps'] as int? ?? 0,
      'total_volume':
          (rows.first['total_volume'] as num?)?.toDouble() ?? 0.0,
    };
  }

  // ─── EXPORT ─────────────────────────────────────────────────────────────────

  /// Returns workout logs filtered by date range and optionally by a single
  /// exercise. When [exerciseId] is set, only workouts that contain that
  /// exercise are returned and each log contains only that exercise's data.
  Future<List<WorkoutLog>> getWorkoutLogsForExport({
    String? fromDate,
    String? toDate,
    String? exerciseId,
  }) async {
    final db = await database;

    List<Map<String, dynamic>> maps;

    if (exerciseId != null) {
      final whereParts = ['el.exercise_id = ?'];
      final whereArgs = <dynamic>[exerciseId];
      if (fromDate != null) {
        whereParts.add('wl.date >= ?');
        whereArgs.add(fromDate);
      }
      if (toDate != null) {
        whereParts.add('wl.date <= ?');
        whereArgs.add(toDate);
      }
      maps = await db.rawQuery('''
        SELECT DISTINCT wl.* FROM workout_logs wl
        INNER JOIN exercise_logs el ON el.workout_log_id = wl.id
        WHERE ${whereParts.join(' AND ')}
        ORDER BY wl.date DESC
      ''', whereArgs);
    } else {
      final whereParts = <String>[];
      final whereArgs = <dynamic>[];
      if (fromDate != null) {
        whereParts.add('date >= ?');
        whereArgs.add(fromDate);
      }
      if (toDate != null) {
        whereParts.add('date <= ?');
        whereArgs.add(toDate);
      }
      final whereStr =
          whereParts.isEmpty ? '' : 'WHERE ${whereParts.join(' AND ')}';
      maps = await db.rawQuery(
          'SELECT * FROM workout_logs $whereStr ORDER BY date DESC',
          whereArgs);
    }

    final logs = <WorkoutLog>[];
    for (final map in maps) {
      final log = WorkoutLog.fromMap(map);
      log.exercises
          .addAll(await _getExerciseLogsFiltered(db, log.id, exerciseId: exerciseId));
      logs.add(log);
    }
    return logs;
  }

  Future<List<ExerciseLog>> _getExerciseLogsFiltered(
    Database db,
    String workoutLogId, {
    String? exerciseId,
  }) async {
    final whereParts = ['workout_log_id = ?'];
    final whereArgs = <dynamic>[workoutLogId];
    if (exerciseId != null) {
      whereParts.add('exercise_id = ?');
      whereArgs.add(exerciseId);
    }
    final maps = await db.query(
      'exercise_logs',
      where: whereParts.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'order_index ASC',
    );
    final exLogs = <ExerciseLog>[];
    for (final map in maps) {
      final exLog = ExerciseLog.fromMap(map);
      final setMaps = await db.query(
        'set_logs',
        where: 'exercise_log_id = ?',
        whereArgs: [exLog.id],
        orderBy: 'set_number ASC',
      );
      exLog.sets.addAll(setMaps.map(SetLog.fromMap));
      exLogs.add(exLog);
    }
    return exLogs;
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ─── IMPORT ─────────────────────────────────────────────────────────────────

  /// Imports workouts from a JSON string produced by the export screen.
  /// Returns a record with the count of imported and skipped workouts.
  /// A workout is skipped if a log for that date already exists in the DB.
  Future<({int imported, int skipped})> importFromJson(String jsonStr) async {
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    final workouts =
        (data['workouts'] as List? ?? []).cast<Map<String, dynamic>>();

    const uuid = Uuid();
    int imported = 0;
    int skipped = 0;

    // Build name → id cache from existing exercises (case-insensitive lookup)
    final nameCache = <String, String>{};
    for (final ex in await getAllExercises()) {
      nameCache[ex.name.toLowerCase()] = ex.id;
    }

    final db = await database;

    for (final w in workouts) {
      final date = w['date'] as String? ?? '';
      if (date.isEmpty) { skipped++; continue; }

      // Skip if any workout already exists on this date
      final existing = await db.query('workout_logs',
          where: 'date = ?', whereArgs: [date], limit: 1);
      if (existing.isNotEmpty) { skipped++; continue; }

      final logId = uuid.v4();
      await db.insert('workout_logs', {
        'id': logId,
        'date': date,
        'workout_name': w['workout_name'] as String? ?? 'Imported Workout',
        'completed': (w['completed'] as bool? ?? false) ? 1 : 0,
        'duration_seconds': w['duration_seconds'] as int?,
        'notes': w['notes'] as String?,
        'plan_day_id': null,
      });

      final exercises =
          (w['exercises'] as List? ?? []).cast<Map<String, dynamic>>();

      for (int i = 0; i < exercises.length; i++) {
        final e = exercises[i];
        final name = (e['name'] as String? ?? '').trim();
        if (name.isEmpty) continue;

        // Find existing exercise by name or create a new custom one
        String exId;
        if (nameCache.containsKey(name.toLowerCase())) {
          exId = nameCache[name.toLowerCase()]!;
        } else {
          exId = uuid.v4();
          await db.insert('exercises', {
            'id': exId,
            'name': name,
            'muscle_group': e['muscle_group'] as String? ?? 'Full Body',
            'equipment': e['equipment'] as String? ?? 'Other',
            'is_custom': 1,
            'exercise_type': e['exercise_type'] as String? ?? 'strength',
          });
          nameCache[name.toLowerCase()] = exId;
        }

        final exLogId = uuid.v4();
        await db.insert('exercise_logs', {
          'id': exLogId,
          'workout_log_id': logId,
          'exercise_id': exId,
          'order_index': i,
        });

        final sets =
            (e['sets'] as List? ?? []).cast<Map<String, dynamic>>();
        for (final s in sets) {
          await db.insert('set_logs', {
            'id': uuid.v4(),
            'exercise_log_id': exLogId,
            'set_number': s['set_number'] as int? ?? 1,
            'weight': (s['weight_kg'] as num?)?.toDouble(),
            'reps': s['reps'] as int?,
            'is_completed': (s['is_completed'] as bool? ?? false) ? 1 : 0,
            'duration_seconds': s['duration_seconds'] as int?,
            'speed': (s['speed'] as num?)?.toDouble(),
            'incline': (s['incline'] as num?)?.toDouble(),
            'resistance': (s['resistance'] as num?)?.toDouble(),
            'distance_km': (s['distance_km'] as num?)?.toDouble(),
          });
        }
      }

      imported++;
    }

    return (imported: imported, skipped: skipped);
  }

  // ─── MONTHLY SUMMARY ────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getMonthlySummary(int year, int month) async {
    final db = await database;
    final monthStart =
        '$year-${month.toString().padLeft(2, '0')}-01';
    final lastDay = DateTime(year, month + 1, 0).day;
    final monthEnd =
        '$year-${month.toString().padLeft(2, '0')}-${lastDay.toString().padLeft(2, '0')}';

    final prevMonth = month == 1 ? 12 : month - 1;
    final prevYear = month == 1 ? year - 1 : year;
    final prevMonthStart =
        '$prevYear-${prevMonth.toString().padLeft(2, '0')}-01';
    final prevLastDay = DateTime(prevYear, prevMonth + 1, 0).day;
    final prevMonthEnd =
        '$prevYear-${prevMonth.toString().padLeft(2, '0')}-${prevLastDay.toString().padLeft(2, '0')}';

    final sessionsResult = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM workout_logs WHERE completed = 1 AND date >= ? AND date <= ?',
      [monthStart, monthEnd],
    );
    final totalSessions = (sessionsResult.first['cnt'] as int?) ?? 0;

    final volumeResult = await db.rawQuery('''
      SELECT SUM(COALESCE(sl.weight, 0) * COALESCE(sl.reps, 0)) as vol
      FROM set_logs sl
      INNER JOIN exercise_logs el ON sl.exercise_log_id = el.id
      INNER JOIN workout_logs wl ON el.workout_log_id = wl.id
      WHERE wl.completed = 1 AND wl.date >= ? AND wl.date <= ?
    ''', [monthStart, monthEnd]);
    final totalVolume = (volumeResult.first['vol'] as num?)?.toDouble() ?? 0.0;

    final prevVolumeResult = await db.rawQuery('''
      SELECT SUM(COALESCE(sl.weight, 0) * COALESCE(sl.reps, 0)) as vol
      FROM set_logs sl
      INNER JOIN exercise_logs el ON sl.exercise_log_id = el.id
      INNER JOIN workout_logs wl ON el.workout_log_id = wl.id
      WHERE wl.completed = 1 AND wl.date >= ? AND wl.date <= ?
    ''', [prevMonthStart, prevMonthEnd]);
    final prevVolume =
        (prevVolumeResult.first['vol'] as num?)?.toDouble() ?? 0.0;

    final prRows = await db.rawQuery('''
      SELECT e.name,
             MAX(CASE WHEN wl.date < ? THEN
               sl.weight * (1.0 + COALESCE(sl.reps, 0) / 30.0) ELSE NULL END) as old_1rm,
             MAX(CASE WHEN wl.date >= ? AND wl.date <= ? THEN
               sl.weight * (1.0 + COALESCE(sl.reps, 0) / 30.0) ELSE NULL END) as new_1rm
      FROM exercise_logs el
      INNER JOIN set_logs sl ON sl.exercise_log_id = el.id
      INNER JOIN workout_logs wl ON el.workout_log_id = wl.id
      INNER JOIN exercises e ON el.exercise_id = e.id
      WHERE wl.completed = 1 AND sl.weight IS NOT NULL AND sl.reps IS NOT NULL AND sl.reps > 0
      GROUP BY el.exercise_id, e.name
      HAVING new_1rm IS NOT NULL AND (old_1rm IS NULL OR new_1rm > old_1rm)
      ORDER BY (new_1rm - COALESCE(old_1rm, 0)) DESC
      LIMIT 3
    ''', [monthStart, monthStart, monthEnd]);

    final topPRs = prRows.map((r) => {
          'name': r['name'] as String,
          'old_1rm': (r['old_1rm'] as num?)?.toDouble(),
          'new_1rm': (r['new_1rm'] as num).toDouble(),
        }).toList();

    final muscleRows = await db.rawQuery('''
      SELECT e.muscle_group, COUNT(sl.id) as set_count
      FROM exercise_logs el
      INNER JOIN set_logs sl ON sl.exercise_log_id = el.id
      INNER JOIN workout_logs wl ON el.workout_log_id = wl.id
      INNER JOIN exercises e ON el.exercise_id = e.id
      WHERE wl.completed = 1 AND wl.date >= ? AND wl.date <= ?
      GROUP BY e.muscle_group
      ORDER BY set_count DESC
      LIMIT 1
    ''', [monthStart, monthEnd]);
    final topMuscleGroup = muscleRows.isEmpty
        ? null
        : muscleRows.first['muscle_group'] as String;

    final bwFirst = await db.rawQuery(
      'SELECT weight_kg FROM body_weight_logs WHERE date >= ? AND date <= ? ORDER BY date ASC LIMIT 1',
      [monthStart, monthEnd],
    );
    final bwLast = await db.rawQuery(
      'SELECT weight_kg FROM body_weight_logs WHERE date >= ? AND date <= ? ORDER BY date DESC LIMIT 1',
      [monthStart, monthEnd],
    );
    final bwFirstVal =
        bwFirst.isEmpty ? null : (bwFirst.first['weight_kg'] as num).toDouble();
    final bwLastVal =
        bwLast.isEmpty ? null : (bwLast.first['weight_kg'] as num).toDouble();

    final dateRows = await db.rawQuery(
      'SELECT date FROM workout_logs WHERE completed = 1 AND date >= ? AND date <= ? ORDER BY date ASC',
      [monthStart, monthEnd],
    );
    final dates = dateRows.map((r) => r['date'] as String).toSet();
    int longestStreak = 0;
    int currentStreak = 0;
    for (int d = 1; d <= lastDay; d++) {
      final ds =
          '$year-${month.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
      if (dates.contains(ds)) {
        currentStreak++;
        if (currentStreak > longestStreak) longestStreak = currentStreak;
      } else {
        currentStreak = 0;
      }
    }

    return {
      'total_sessions': totalSessions,
      'total_volume': totalVolume,
      'prev_volume': prevVolume,
      'top_prs': topPRs,
      'top_muscle_group': topMuscleGroup,
      'bw_first': bwFirstVal,
      'bw_last': bwLastVal,
      'longest_streak': longestStreak,
    };
  }

  // ─── WELLNESS LOGS ──────────────────────────────────────────────────────────

  Future<void> logWellness({
    required String date,
    required double sleepHours,
    required int energy,
    required int soreness,
    String? notes,
  }) async {
    const uuid = Uuid();
    final db = await database;
    final existing = await db.query('wellness_logs',
        where: 'date = ?', whereArgs: [date], limit: 1);
    if (existing.isNotEmpty) {
      await db.update(
        'wellness_logs',
        {
          'sleep_hours': sleepHours,
          'energy': energy,
          'soreness': soreness,
          'notes': notes,
        },
        where: 'date = ?',
        whereArgs: [date],
      );
    } else {
      await db.insert('wellness_logs', {
        'id': uuid.v4(),
        'date': date,
        'sleep_hours': sleepHours,
        'energy': energy,
        'soreness': soreness,
        'notes': notes,
      });
    }
  }

  Future<Map<String, dynamic>?> getWellnessForDate(String date) async {
    final db = await database;
    final rows = await db.query('wellness_logs',
        where: 'date = ?', whereArgs: [date], limit: 1);
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first);
  }

  Future<List<Map<String, dynamic>>> getWellnessLogs(
      {String? fromDate, String? toDate}) async {
    final db = await database;
    final where = StringBuffer('1=1');
    final args = <dynamic>[];
    if (fromDate != null) {
      where.write(' AND date >= ?');
      args.add(fromDate);
    }
    if (toDate != null) {
      where.write(' AND date <= ?');
      args.add(toDate);
    }
    return db.rawQuery(
      'SELECT date, sleep_hours, energy, soreness FROM wellness_logs WHERE ${where.toString()} ORDER BY date ASC',
      args,
    );
  }

  // ─── ACHIEVEMENTS ────────────────────────────────────────────────────────────

  Future<Map<String, String>> getUnlockedAchievements() async {
    final db = await database;
    final rows = await db.query('achievements_unlocked');
    return {
      for (final r in rows)
        r['achievement_id'] as String: r['unlocked_at'] as String
    };
  }

  Future<void> markAchievementUnlocked(String achievementId) async {
    final db = await database;
    await db.insert(
      'achievements_unlocked',
      {
        'achievement_id': achievementId,
        'unlocked_at': _fmt(DateTime.now()),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Computes all achievement-related stats and marks newly unlocked ones.
  /// Returns IDs of achievements that were just unlocked this call.
  Future<List<String>> checkAndUnlockAchievements({int notesCount = 0}) async {
    final db = await database;

    final totalWorkouts = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM workout_logs WHERE completed = 1',
        )) ??
        0;

    final volumeRow = await db.rawQuery('''
      SELECT SUM(COALESCE(sl.weight, 0) * COALESCE(sl.reps, 0)) as vol
      FROM set_logs sl
      INNER JOIN exercise_logs el ON sl.exercise_log_id = el.id
      INNER JOIN workout_logs wl ON el.workout_log_id = wl.id
      WHERE wl.completed = 1
    ''');
    final totalVolume =
        (volumeRow.first['vol'] as num?)?.toDouble() ?? 0.0;

    final prCount = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM exercise_prs',
        )) ??
        0;

    final legWorkouts = Sqflite.firstIntValue(await db.rawQuery('''
      SELECT COUNT(DISTINCT wl.id) FROM workout_logs wl
      INNER JOIN exercise_logs el ON el.workout_log_id = wl.id
      INNER JOIN exercises e ON el.exercise_id = e.id
      WHERE wl.completed = 1 AND e.muscle_group = 'Legs'
    ''')) ??
        0;

    final streak = await getWorkoutStreak();
    final consistent = await _checkConsistentFourWeeks(db);

    final workoutNoteCount = Sqflite.firstIntValue(await db.rawQuery(
          "SELECT COUNT(*) FROM workout_logs WHERE completed = 1 AND notes IS NOT NULL AND notes != ''",
        )) ??
        0;
    final totalNotes = workoutNoteCount + notesCount;

    final conditions = <String, bool>{
      'first_rep': totalWorkouts >= 1,
      'week_warrior': streak >= 7,
      'century_club': totalWorkouts >= 100,
      'ten_k_club': totalVolume >= 10000,
      'pr_machine': prCount >= 10,
      'consistent': consistent,
      'leg_day_hero': legWorkouts >= 20,
      'note_taker': totalNotes >= 10,
    };

    final already = await getUnlockedAchievements();
    final newlyUnlocked = <String>[];

    for (final entry in conditions.entries) {
      if (entry.value && !already.containsKey(entry.key)) {
        await markAchievementUnlocked(entry.key);
        newlyUnlocked.add(entry.key);
      }
    }

    return newlyUnlocked;
  }

  Future<bool> _checkConsistentFourWeeks(Database db) async {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    for (int week = 1; week <= 4; week++) {
      final weekStart = monday.subtract(Duration(days: 7 * week));
      final weekEnd = weekStart.add(const Duration(days: 6));
      final count = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM workout_logs WHERE completed = 1 AND date >= ? AND date <= ?',
            [_fmt(weekStart), _fmt(weekEnd)],
          )) ??
          0;
      if (count < 3) return false;
    }
    return true;
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}
