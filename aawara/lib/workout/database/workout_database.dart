import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../models/exercise.dart';
import '../models/plateau_alert.dart';
import '../models/progress_photo.dart';
import '../models/supplement.dart';
import '../models/sleep_session.dart';
import '../models/lab_value.dart';
import '../../services/samsung_health_models.dart';
import '../utils/samsung_link.dart';
import '../utils/heart_rate_zones.dart';
import '../models/workout_log.dart';
import '../models/workout_plan_day.dart';
import '../../nutrition/models/nutrition_models.dart';

class WorkoutDatabase {
  static final WorkoutDatabase instance = WorkoutDatabase._init();
  static Database? _database;
  // Caches the in-flight open so concurrent callers (e.g. Future.wait of many
  // queries on cold start) all await the same init instead of each kicking off
  // their own open + migrations, which used to race and throw.
  static Future<Database>? _opening;

  WorkoutDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _opening ??= _initDB('workout.db');
    try {
      _database = await _opening!;
      return _database!;
    } catch (_) {
      _opening = null; // let a later call retry a failed open
      rethrow;
    }
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(
      path,
      version: 24,
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
    if (oldVersion < 8) await _migrateV8(db);
    if (oldVersion < 9) await _migrateV9(db);
    if (oldVersion < 10) await _migrateV10(db);
    if (oldVersion < 11) await _migrateV11(db);
    if (oldVersion < 12) await _migrateV12(db);
    if (oldVersion < 13) await _migrateV13(db);
    if (oldVersion < 14) await _migrateV14(db);
    if (oldVersion < 15) await _migrateV15(db);
    if (oldVersion < 16) await _migrateV16(db);
    if (oldVersion < 17) await _migrateV17(db);
    if (oldVersion < 18) await _migrateV18(db);
    if (oldVersion < 19) await _migrateV19(db);
    if (oldVersion < 20) await _migrateV20(db);
    if (oldVersion < 21) await _migrateV21(db);
    if (oldVersion < 22) await _migrateV22(db);
    if (oldVersion < 23) await _migrateV23(db);
    if (oldVersion < 24) await _migrateV24(db);
  }

  Future<void> _migrateV23(Database db) async {
    for (final sql in _createSamsungHealthSql) {
      await db.execute(sql);
    }
    // Link gym workouts to watch-recorded exercise sessions + capture start time.
    for (final col in ['started_at TEXT', 'samsung_exercise_uid TEXT']) {
      try {
        await db.execute('ALTER TABLE workout_logs ADD COLUMN $col');
      } catch (_) {}
    }
  }

  /// v24: track which watch sessions have had their dense HEART_RATE series
  /// pulled (the in-session exercise log is unreliable for some workout types,
  /// so we backfill from the HR series and remember we tried).
  Future<void> _migrateV24(Database db) async {
    try {
      await db.execute(
          'ALTER TABLE sh_exercise_sessions ADD COLUMN hr_series_checked INTEGER DEFAULT 0');
    } catch (_) {}
  }

  // Samsung Health (watch) data, kept separate from the manual logs. Every row
  // keeps raw_json so later analytics can use fields we don't model yet.
  static const _createSamsungHealthSql = <String>[
    '''
    CREATE TABLE IF NOT EXISTS sh_exercise_sessions (
      uid TEXT PRIMARY KEY,
      exercise_type TEXT,
      custom_title TEXT,
      start_iso TEXT NOT NULL,
      end_iso TEXT NOT NULL,
      duration_seconds INTEGER,
      calories REAL,
      distance REAL,
      count INTEGER,
      mean_hr REAL, max_hr REAL, min_hr REAL,
      mean_speed REAL, max_speed REAL,
      vo2max REAL,
      hr_series_checked INTEGER DEFAULT 0,
      raw_json TEXT
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_sh_ex_start ON sh_exercise_sessions(start_iso)',
    '''
    CREATE TABLE IF NOT EXISTS sh_exercise_samples (
      uid TEXT NOT NULL, t_iso TEXT NOT NULL,
      hr REAL, cadence REAL, power REAL, speed REAL
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_sh_ex_samples ON sh_exercise_samples(uid)',
    '''
    CREATE TABLE IF NOT EXISTS sh_exercise_route (
      uid TEXT NOT NULL, t_iso TEXT NOT NULL, lat REAL, lng REAL, alt REAL
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_sh_ex_route ON sh_exercise_route(uid)',
    '''
    CREATE TABLE IF NOT EXISTS sh_sleep_sessions (
      uid TEXT PRIMARY KEY, date TEXT, score INTEGER,
      start_iso TEXT, end_iso TEXT, duration_seconds INTEGER, raw_json TEXT
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS sh_sleep_stages (
      uid TEXT NOT NULL, stage TEXT, start_iso TEXT, end_iso TEXT
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_sh_sleep_stages ON sh_sleep_stages(uid)',
    '''
    CREATE TABLE IF NOT EXISTS sh_sync_state (
      key TEXT PRIMARY KEY, value TEXT
    )
    ''',
  ];

  Future<void> _migrateV21(Database db) async {
    await db.execute(_createSleepSessionsSql);
  }

  Future<void> _migrateV22(Database db) async {
    // Per-timestamp HR / SpO₂ samples for the overnight charts.
    for (final col in ['hr_series_json', 'spo2_series_json']) {
      try {
        await db.execute('ALTER TABLE sleep_sessions ADD COLUMN $col TEXT');
      } catch (_) {}
    }
  }

  static const _createSleepSessionsSql = '''
    CREATE TABLE IF NOT EXISTS sleep_sessions (
      date TEXT PRIMARY KEY,
      start_iso TEXT,
      end_iso TEXT,
      total_minutes INTEGER NOT NULL DEFAULT 0,
      asleep_minutes INTEGER NOT NULL DEFAULT 0,
      awake_minutes INTEGER NOT NULL DEFAULT 0,
      light_minutes INTEGER NOT NULL DEFAULT 0,
      deep_minutes INTEGER NOT NULL DEFAULT 0,
      rem_minutes INTEGER NOT NULL DEFAULT 0,
      score INTEGER NOT NULL DEFAULT 0,
      hr_avg REAL,
      hr_min REAL,
      spo2_avg REAL,
      spo2_min REAL,
      resp_avg REAL,
      source TEXT NOT NULL DEFAULT 'health_connect',
      stages_json TEXT,
      hr_series_json TEXT,
      spo2_series_json TEXT
    )
  ''';

  Future<void> _migrateV20(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS supplements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        dose TEXT,
        time_hhmm TEXT NOT NULL,
        notes TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT DEFAULT (datetime('now'))
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS supplement_logs (
        supplement_id INTEGER NOT NULL,
        date TEXT NOT NULL,
        taken_at TEXT NOT NULL,
        PRIMARY KEY (supplement_id, date)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS lab_values (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        name TEXT NOT NULL,
        value REAL NOT NULL,
        unit TEXT,
        ref_low REAL,
        ref_high REAL,
        notes TEXT,
        created_at TEXT DEFAULT (datetime('now'))
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_lab_values_name_date ON lab_values(name, date)');
    // Add optional category to progress_photos (front / side / back)
    try {
      await db.execute('ALTER TABLE progress_photos ADD COLUMN category TEXT');
    } catch (_) {}
  }

  Future<void> _migrateV19(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS meal_slots (
        meal_key TEXT PRIMARY KEY,
        display_order INTEGER NOT NULL
      )
    ''');
    // Seed the 5 default slots for existing users
    for (int i = 1; i <= 5; i++) {
      await db.insert(
        'meal_slots',
        {'meal_key': 'meal_$i', 'display_order': i},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future<void> _migrateV18(Database db) async {
    // Correct nuts/seeds from IFCT → USDA values (per 100g)
    // All values verified against USDA FoodData Central
    final corrections = <String, Map<String, double>>{
      'Almonds': {
        'calories': 577, 'protein_g': 20.0, 'carbs_g': 20.0,
        'fat_g': 50.0, 'fiber_g': 11.7, 'sugar_g': 4.0,
        'saturated_fat_g': 3.7,
      },
      'Cashews': {
        'calories': 553, 'protein_g': 18.2, 'carbs_g': 30.2,
        'fat_g': 43.9, 'fiber_g': 3.3, 'sugar_g': 5.9,
        'saturated_fat_g': 7.8,
      },
      'Walnuts': {
        'calories': 654, 'protein_g': 15.2, 'carbs_g': 13.7,
        'fat_g': 65.2, 'fiber_g': 6.7, 'sugar_g': 2.6,
        'saturated_fat_g': 6.1,
      },
      'Pistachios': {
        'calories': 560, 'protein_g': 20.2, 'carbs_g': 27.2,
        'fat_g': 45.3, 'fiber_g': 10.6, 'sugar_g': 7.7,
        'saturated_fat_g': 5.9,
      },
    };
    for (final entry in corrections.entries) {
      await db.update(
        'foods',
        entry.value,
        where: 'name = ? AND is_custom = 0',
        whereArgs: [entry.key],
      );
    }

    // Add new milk variants
    const uuid = Uuid();
    final newFoods = [
      {
        'id': uuid.v4(),
        'name': 'Indian Cow milk without malai',
        'calories': 34.6,
        'protein_g': 3.46,
        'carbs_g': 5.0,
        'fat_g': 0.08,
        'fiber_g': 0.0,
        'sugar_g': 5.0,
        'sodium_mg': 43.0,
        'saturated_fat_g': 0.04,
        'trans_fat_g': 0.0,
        'cholesterol_mg': 2.0,
        'serving_size': 240.0,
        'serving_unit': 'ml',
        'is_custom': 0,
        'source': 'seeded',
      },
      {
        'id': uuid.v4(),
        'name': 'Indian Buffalo milk without malai',
        'calories': 39.6,
        'protein_g': 3.96,
        'carbs_g': 5.42,
        'fat_g': 0.21,
        'fiber_g': 0.0,
        'sugar_g': 5.42,
        'sodium_mg': 52.0,
        'saturated_fat_g': 0.08,
        'trans_fat_g': 0.0,
        'cholesterol_mg': 3.0,
        'serving_size': 240.0,
        'serving_unit': 'ml',
        'is_custom': 0,
        'source': 'seeded',
      },
    ];
    for (final food in newFoods) {
      await db.insert('foods', food, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<void> _migrateV17(Database db) async {
    // Create configurable meal names table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS meal_templates (
        meal_key TEXT PRIMARY KEY,
        name TEXT NOT NULL
      )
    ''');
    // Migrate fixed meal names → numbered keys
    await db.rawUpdate("UPDATE nutrition_entries SET meal_type = 'meal_1' WHERE meal_type = 'Breakfast'");
    await db.rawUpdate("UPDATE nutrition_entries SET meal_type = 'meal_2' WHERE meal_type = 'Lunch'");
    await db.rawUpdate("UPDATE nutrition_entries SET meal_type = 'meal_3' WHERE meal_type = 'Dinner'");
    await db.rawUpdate("UPDATE nutrition_entries SET meal_type = 'meal_4' WHERE meal_type = 'Snack'");
    // Also fix any meal_presets_items that stored meal_type (for logMealPreset)
    try {
      await db.rawUpdate("UPDATE meal_preset_items SET meal_type = 'meal_1' WHERE meal_type = 'Breakfast'");
      await db.rawUpdate("UPDATE meal_preset_items SET meal_type = 'meal_2' WHERE meal_type = 'Lunch'");
      await db.rawUpdate("UPDATE meal_preset_items SET meal_type = 'meal_3' WHERE meal_type = 'Dinner'");
      await db.rawUpdate("UPDATE meal_preset_items SET meal_type = 'meal_4' WHERE meal_type = 'Snack'");
    } catch (_) {}
  }

  Future<void> _migrateV16(Database db) async {
    await db.execute('ALTER TABLE foods ADD COLUMN saturated_fat_g REAL DEFAULT 0');
    await db.execute('ALTER TABLE foods ADD COLUMN trans_fat_g REAL DEFAULT 0');
    await db.execute('ALTER TABLE foods ADD COLUMN cholesterol_mg REAL DEFAULT 0');

    // Backfill sugar, sodium, saturated_fat, trans_fat, cholesterol for all seeded foods.
    for (final (name, _, _, _, _, _, _, _, sugar, sodium, satFat, transFat, chol) in _kFoodSeed) {
      await db.update(
        'foods',
        {
          'sugar_g': sugar,
          'sodium_mg': sodium,
          'saturated_fat_g': satFat,
          'trans_fat_g': transFat,
          'cholesterol_mg': chol,
        },
        where: 'name = ? AND is_custom = 0',
        whereArgs: [name],
      );
    }

    const uuid = Uuid();
    final foods = [
      {
        'id': uuid.v4(),
        'name': 'BeastLife Creatine Unflavoured',
        'calories': 0.0,
        'protein_g': 0.0,
        'carbs_g': 0.0,
        'fat_g': 0.0,
        'fiber_g': 0.0,
        'sugar_g': 0.0,
        'sodium_mg': 0.0,
        'saturated_fat_g': 0.0,
        'trans_fat_g': 0.0,
        'cholesterol_mg': 0.0,
        'serving_size': 3.0,
        'serving_unit': 'scoop (3g)',
        'brand': 'BeastLife',
        'is_custom': 0,
        'source': 'seeded',
      },
      {
        'id': uuid.v4(),
        'name': 'BeastLife Isorich Whey Protein Isolate',
        'calories': 377.70,
        'protein_g': 74.24,
        'carbs_g': 10.09,
        'fat_g': 4.48,
        'fiber_g': 0.0,
        'sugar_g': 1.88,
        'sodium_mg': 185.09,
        'saturated_fat_g': 1.32,
        'trans_fat_g': 0.09,
        'cholesterol_mg': 94.06,
        'serving_size': 33.0,
        'serving_unit': 'scoop (33g)',
        'brand': 'BeastLife',
        'is_custom': 0,
        'source': 'seeded',
      },
      {
        'id': uuid.v4(),
        'name': 'NATURALTEIN Natural Whey Protein Isolate Chocolate',
        'calories': 397.0,
        'protein_g': 80.2,
        'carbs_g': 5.3,
        'fat_g': 6.1,
        'fiber_g': 0.0,
        'sugar_g': 1.5,
        'sodium_mg': 109.0,
        'saturated_fat_g': 3.6,
        'trans_fat_g': 0.0,
        'cholesterol_mg': 1.3,
        'serving_size': 30.0,
        'serving_unit': 'scoop (30g)',
        'brand': 'NATURALTEIN',
        'is_custom': 0,
        'source': 'seeded',
      },
      {
        'id': uuid.v4(),
        'name': 'True Elements Steel Cut Oats',
        'calories': 419.2,
        'protein_g': 11.5,
        'carbs_g': 65.7,
        'fat_g': 12.2,
        'fiber_g': 10.7,
        'sugar_g': 0.0,
        'sodium_mg': 4.0,
        'saturated_fat_g': 2.8,
        'trans_fat_g': 0.0,
        'cholesterol_mg': 0.0,
        'serving_size': 40.0,
        'serving_unit': 'g',
        'brand': 'True Elements',
        'is_custom': 0,
        'source': 'seeded',
      },
      {
        'id': uuid.v4(),
        'name': 'BeastLife Pre-Workout Orange Flavour',
        'calories': 10.84,
        'protein_g': 0.0,
        'carbs_g': 2.71,
        'fat_g': 0.0,
        'fiber_g': 0.0,
        'sugar_g': 0.0,
        'sodium_mg': 726.43,
        'saturated_fat_g': 0.0,
        'trans_fat_g': 0.0,
        'cholesterol_mg': 0.0,
        'serving_size': 7.0,
        'serving_unit': 'scoop (7g)',
        'brand': 'BeastLife',
        'is_custom': 0,
        'source': 'seeded',
      },
      {
        'id': uuid.v4(),
        'name': 'BeastLife Multivitamin tablets',
        'calories': 159.3,
        'protein_g': 0.0,
        'carbs_g': 38.7,
        'fat_g': 0.55,
        'fiber_g': 0.16,
        'sugar_g': 0.93,
        'sodium_mg': 140.1,
        'saturated_fat_g': 0.0,
        'trans_fat_g': 0.0,
        'cholesterol_mg': 0.0,
        'serving_size': 1.82,
        'serving_unit': 'tablet (1.82g)',
        'brand': 'BeastLife',
        'is_custom': 0,
        'source': 'seeded',
      },
      {
        'id': uuid.v4(),
        'name': 'NATURALTEIN Omega-3 Fish Oil 1250mg Triple Strength Softgel Capsules | 450mg EPA & 300mg DHA in Triglyceride Form',
        'calories': 875.3,
        'protein_g': 21.33,
        'carbs_g': 10.0,
        'fat_g': 83.33,
        'fiber_g': 0.0,
        'sugar_g': 0.0,
        'sodium_mg': 3333.33,
        'saturated_fat_g': 0.0,
        'trans_fat_g': 0.0,
        'cholesterol_mg': 0.0,
        'serving_size': 1.5,
        'serving_unit': 'softgel (1.5g)',
        'brand': 'NATURALTEIN',
        'is_custom': 0,
        'source': 'seeded',
      },
    ];
    for (final food in foods) {
      await db.insert('foods', food, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<void> _migrateV15(Database db) async {
    await db.execute('ALTER TABLE exercise_logs ADD COLUMN notes TEXT');
  }

  Future<void> _migrateV14(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS body_measurements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        type TEXT NOT NULL,
        value_cm REAL NOT NULL,
        created_at TEXT DEFAULT (datetime('now')),
        UNIQUE(date, type)
      )
    ''');
  }

  Future<void> _migrateV11(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS progress_photos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        file_path TEXT NOT NULL,
        note TEXT,
        created_at TEXT DEFAULT (datetime('now'))
      )
    ''');
  }

  Future<void> _migrateV13(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS step_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL UNIQUE,
        steps INTEGER NOT NULL DEFAULT 0,
        goal INTEGER NOT NULL,
        updated_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');
  }

  Future<void> _migrateV12(Database db) async {
    await db.execute('ALTER TABLE foods ADD COLUMN barcode TEXT');
    await db.execute('ALTER TABLE foods ADD COLUMN brand TEXT');
    await db.execute('ALTER TABLE foods ADD COLUMN sugar_g REAL DEFAULT 0');
    await db.execute('ALTER TABLE foods ADD COLUMN sodium_mg REAL DEFAULT 0');
    await db.execute("ALTER TABLE foods ADD COLUMN source TEXT DEFAULT 'manual'");
    await db.execute('ALTER TABLE foods ADD COLUMN last_updated TEXT');
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_foods_barcode
      ON foods(barcode) WHERE barcode IS NOT NULL
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS scan_cache (
        barcode TEXT PRIMARY KEY,
        food_id TEXT,
        status TEXT NOT NULL DEFAULT 'found',
        scan_count INTEGER NOT NULL DEFAULT 1,
        last_scanned_at TEXT NOT NULL,
        raw_json TEXT
      )
    ''');
  }

  Future<void> _migrateV8(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS foods (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        calories REAL NOT NULL,
        protein_g REAL NOT NULL,
        carbs_g REAL NOT NULL,
        fat_g REAL NOT NULL,
        fiber_g REAL,
        serving_size REAL NOT NULL DEFAULT 100,
        serving_unit TEXT NOT NULL DEFAULT 'g',
        is_custom INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS nutrition_logs (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL UNIQUE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS nutrition_entries (
        id TEXT PRIMARY KEY,
        log_id TEXT NOT NULL,
        food_id TEXT NOT NULL,
        meal_type TEXT NOT NULL,
        quantity REAL NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS nutrition_goals (
        id INTEGER PRIMARY KEY,
        calories REAL NOT NULL,
        protein_g REAL NOT NULL,
        carbs_g REAL NOT NULL,
        fat_g REAL NOT NULL
      )
    ''');
    await _seedFoodsIfEmpty(db);
  }

  Future<void> _migrateV10(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS meal_presets (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS meal_preset_items (
        id TEXT PRIMARY KEY,
        preset_id TEXT NOT NULL,
        food_id TEXT NOT NULL,
        quantity REAL NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS meal_templates (
        meal_key TEXT PRIMARY KEY,
        name TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS meal_slots (
        meal_key TEXT PRIMARY KEY,
        display_order INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS supplements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        dose TEXT,
        time_hhmm TEXT NOT NULL,
        notes TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT DEFAULT (datetime('now'))
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS supplement_logs (
        supplement_id INTEGER NOT NULL,
        date TEXT NOT NULL,
        taken_at TEXT NOT NULL,
        PRIMARY KEY (supplement_id, date)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS lab_values (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        name TEXT NOT NULL,
        value REAL NOT NULL,
        unit TEXT,
        ref_low REAL,
        ref_high REAL,
        notes TEXT,
        created_at TEXT DEFAULT (datetime('now'))
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_lab_values_name_date ON lab_values(name, date)');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS water_logs (
        date TEXT PRIMARY KEY,
        glasses_drunk INTEGER NOT NULL DEFAULT 0,
        target_glasses INTEGER NOT NULL DEFAULT 8
      )
    ''');
  }

  Future<void> _migrateV9(Database db) async {
    // Delete only seeded (non-custom) foods; user-created foods (is_custom=1) are preserved.
    await db.delete('foods', where: 'is_custom = ?', whereArgs: [0]);
    await _seedFoodsIfEmpty(db);
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
        duration_seconds INTEGER,
        started_at TEXT,
        samsung_exercise_uid TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE exercise_logs (
        id TEXT PRIMARY KEY,
        workout_log_id TEXT NOT NULL,
        exercise_id TEXT NOT NULL,
        order_index INTEGER NOT NULL,
        notes TEXT
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

    await db.execute('''
      CREATE TABLE foods (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        calories REAL NOT NULL,
        protein_g REAL NOT NULL,
        carbs_g REAL NOT NULL,
        fat_g REAL NOT NULL,
        fiber_g REAL,
        serving_size REAL NOT NULL DEFAULT 100,
        serving_unit TEXT NOT NULL DEFAULT 'g',
        is_custom INTEGER NOT NULL DEFAULT 0,
        barcode TEXT,
        brand TEXT,
        sugar_g REAL DEFAULT 0,
        sodium_mg REAL DEFAULT 0,
        saturated_fat_g REAL DEFAULT 0,
        trans_fat_g REAL DEFAULT 0,
        cholesterol_mg REAL DEFAULT 0,
        source TEXT DEFAULT 'manual',
        last_updated TEXT
      )
    ''');

    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_foods_barcode
      ON foods(barcode) WHERE barcode IS NOT NULL
    ''');

    await db.execute('''
      CREATE TABLE scan_cache (
        barcode TEXT PRIMARY KEY,
        food_id TEXT,
        status TEXT NOT NULL DEFAULT 'found',
        scan_count INTEGER NOT NULL DEFAULT 1,
        last_scanned_at TEXT NOT NULL,
        raw_json TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE nutrition_logs (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL UNIQUE
      )
    ''');

    await db.execute('''
      CREATE TABLE nutrition_entries (
        id TEXT PRIMARY KEY,
        log_id TEXT NOT NULL,
        food_id TEXT NOT NULL,
        meal_type TEXT NOT NULL,
        quantity REAL NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE nutrition_goals (
        id INTEGER PRIMARY KEY,
        calories REAL NOT NULL,
        protein_g REAL NOT NULL,
        carbs_g REAL NOT NULL,
        fat_g REAL NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE meal_presets (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE meal_preset_items (
        id TEXT PRIMARY KEY,
        preset_id TEXT NOT NULL,
        food_id TEXT NOT NULL,
        quantity REAL NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE water_logs (
        date TEXT PRIMARY KEY,
        glasses_drunk INTEGER NOT NULL DEFAULT 0,
        target_glasses INTEGER NOT NULL DEFAULT 8
      )
    ''');

    await db.execute('''
      CREATE TABLE progress_photos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        file_path TEXT NOT NULL,
        note TEXT,
        created_at TEXT DEFAULT (datetime('now'))
      )
    ''');

    await db.execute('''
      CREATE TABLE step_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL UNIQUE,
        steps INTEGER NOT NULL DEFAULT 0,
        goal INTEGER NOT NULL,
        updated_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');

    await db.execute('''
      CREATE TABLE body_measurements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        type TEXT NOT NULL,
        value_cm REAL NOT NULL,
        created_at TEXT DEFAULT (datetime('now')),
        UNIQUE(date, type)
      )
    ''');

    await db.execute(_createSleepSessionsSql);
    for (final sql in _createSamsungHealthSql) {
      await db.execute(sql);
    }

    await _seedDefaultExercises(db);
    await _seedPplWeeklyPlan(db);
    await _seedFoodsIfEmpty(db);
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

  // (name, cal, protein, carbs, fat, fiber, servingSize, servingUnit, sugar, sodium, saturatedFat, transFat, cholesterol)
  // Values based on IFCT 2017 (Indian Food Composition Tables, NIN) and USDA per 100g unless noted.
  static const _kFoodSeed = <(String, double, double, double, double, double, double, String, double, double, double, double, double)>[
    // ── Cereals & Millets ──────────────────────────────────────────────────────
    //                             cal    pro    carb   fat    fib    srv  unit    sug    sod    sat    tra    cho
    ('Rice (raw)',                 346,   6.8,   78.2,  0.5,   0.2,   100, 'g',   0.1,   5.0,   0.1,   0.0,   0.0),
    ('Rice (cooked)',              130,   2.7,   28.2,  0.3,   0.2,   100, 'g',   0.1,   1.0,   0.1,   0.0,   0.0),
    ('Basmati Rice (cooked)',      121,   2.5,   26.6,  0.3,   0.3,   100, 'g',   0.1,   1.0,   0.1,   0.0,   0.0),
    ('Wheat Atta (whole)',         341,   12.1,  69.4,  1.7,   11.2,  100, 'g',   0.4,   2.0,   0.3,   0.0,   0.0),
    ('Maida (refined flour)',      348,   10.3,  73.9,  0.9,   2.7,   100, 'g',   0.3,   2.0,   0.2,   0.0,   0.0),
    ('Sooji / Semolina',           348,   10.4,  73.6,  0.8,   3.9,   100, 'g',   0.4,   1.0,   0.1,   0.0,   0.0),
    ('Poha (flat rice)',           333,   6.7,   74.0,  1.0,   1.0,   100, 'g',   0.1,   5.0,   0.2,   0.0,   0.0),
    ('Poha (cooked)',              130,   2.4,   27.0,  0.5,   0.4,   100, 'g',   0.1,   2.0,   0.1,   0.0,   0.0),
    ('Jowar (sorghum)',            349,   10.4,  72.6,  1.9,   6.7,   100, 'g',   1.0,   6.0,   0.3,   0.0,   0.0),
    ('Bajra (pearl millet)',       361,   11.6,  67.5,  5.0,   1.2,   100, 'g',   1.0,   10.0,  0.9,   0.0,   0.0),
    ('Ragi / Finger Millet',       328,   7.3,   72.0,  1.3,   3.6,   100, 'g',   1.7,   11.0,  0.2,   0.0,   0.0),
    ('Oats (dry)',                 389,   13.2,  66.3,  6.9,   10.6,  50,  'g',   1.1,   6.0,   1.2,   0.0,   0.0),
    ('Oats (cooked)',              71,    2.5,   12.0,  1.5,   1.7,   100, 'g',   0.4,   49.0,  0.2,   0.0,   0.0),
    ('Cornflakes',                 357,   7.5,   84.2,  0.5,   1.2,   30,  'g',   8.0,   543.0, 0.1,   0.0,   0.0),
    ('Muesli',                     363,   9.5,   66.0,  5.5,   7.0,   45,  'g',   12.0,  80.0,  0.8,   0.0,   0.0),
    ('Bread (whole wheat)',        243,   8.9,   46.0,  3.4,   7.0,   30,  'g',   3.5,   400.0, 0.5,   0.1,   0.0),
    ('Bread (white)',              265,   7.6,   49.0,  3.3,   2.7,   30,  'g',   4.0,   490.0, 0.6,   0.1,   0.0),
    // ── Pulses & Legumes ───────────────────────────────────────────────────────
    ('Moong Dal (cooked)',         105,   7.0,   18.0,  0.4,   7.6,   100, 'g',   1.3,   4.0,   0.1,   0.0,   0.0),
    ('Moong Dal (raw)',            348,   24.5,  59.9,  1.2,   10.8,  100, 'g',   1.8,   15.0,  0.2,   0.0,   0.0),
    ('Toor Dal (cooked)',          116,   7.2,   20.0,  0.4,   6.7,   100, 'g',   2.0,   6.0,   0.1,   0.0,   0.0),
    ('Toor Dal (raw)',             335,   22.3,  57.6,  1.7,   15.0,  100, 'g',   5.0,   20.0,  0.3,   0.0,   0.0),
    ('Chana Dal (cooked)',         164,   8.9,   29.0,  2.7,   7.6,   100, 'g',   5.6,   7.0,   0.3,   0.0,   0.0),
    ('Masoor Dal (cooked)',        116,   9.0,   20.0,  0.4,   8.0,   100, 'g',   1.8,   7.0,   0.1,   0.0,   0.0),
    ('Urad Dal (cooked)',          105,   7.0,   18.0,  0.4,   7.5,   100, 'g',   0.5,   4.0,   0.1,   0.0,   0.0),
    ('Rajma (cooked)',             127,   8.7,   22.8,  0.5,   7.4,   100, 'g',   0.6,   2.0,   0.1,   0.0,   0.0),
    ('Rajma (raw)',                333,   22.9,  60.6,  1.3,   22.9,  100, 'g',   2.0,   5.0,   0.2,   0.0,   0.0),
    ('Chickpeas / Kabuli Chana (cooked)', 164, 8.9, 27.4, 2.6, 7.6, 100, 'g', 7.9, 7.0, 0.3, 0.0, 0.0),
    ('Bhuna Chana',                360,   24.0,  55.0,  6.0,   16.0,  30,  'g',   2.0,   24.0,  0.7,   0.0,   0.0),
    ('Moong Dal Sprouts',          30,    3.3,   5.6,   0.1,   1.8,   100, 'g',   0.6,   2.0,   0.0,   0.0,   0.0),
    ('Soya Chunks (dry)',          345,   52.0,  33.0,  0.5,   13.0,  30,  'g',   0.0,   100.0, 0.1,   0.0,   0.0),
    ('Soya Chunks (cooked)',       152,   17.0,  15.0,  2.0,   4.5,   100, 'g',   0.0,   50.0,  0.3,   0.0,   0.0),
    ('Lobia / Black Eyed Peas (cooked)', 116, 7.7, 21.0, 0.5, 6.0, 100, 'g', 0.3, 4.0, 0.1, 0.0, 0.0),
    // ── Vegetables ─────────────────────────────────────────────────────────────
    ('Spinach (palak)',            26,    2.0,   3.6,   0.7,   2.2,   100, 'g',   0.4,   79.0,  0.1,   0.0,   0.0),
    ('Fenugreek Leaves (methi)',   49,    4.4,   6.0,   0.9,   1.1,   100, 'g',   0.0,   67.0,  0.1,   0.0,   0.0),
    ('Tomato',                     20,    0.9,   3.9,   0.2,   1.2,   100, 'g',   2.6,   5.0,   0.0,   0.0,   0.0),
    ('Onion',                      50,    1.2,   11.1,  0.1,   1.7,   100, 'g',   4.2,   4.0,   0.0,   0.0,   0.0),
    ('Garlic',                     149,   6.4,   33.1,  0.5,   2.1,   10,  'g',   1.0,   17.0,  0.1,   0.0,   0.0),
    ('Ginger',                     80,    1.8,   17.8,  0.8,   2.0,   10,  'g',   1.7,   13.0,  0.2,   0.0,   0.0),
    ('Potato',                     97,    1.6,   22.6,  0.1,   2.5,   100, 'g',   0.8,   6.0,   0.0,   0.0,   0.0),
    ('Potato (boiled)',            86,    1.9,   19.8,  0.1,   1.8,   100, 'g',   0.9,   4.0,   0.0,   0.0,   0.0),
    ('Sweet Potato',               99,    1.6,   23.0,  0.1,   3.0,   100, 'g',   4.2,   55.0,  0.0,   0.0,   0.0),
    ('Cauliflower',                30,    2.6,   4.9,   0.3,   2.0,   100, 'g',   1.9,   30.0,  0.1,   0.0,   0.0),
    ('Cabbage',                    27,    1.8,   5.8,   0.1,   0.6,   100, 'g',   3.2,   18.0,  0.0,   0.0,   0.0),
    ('Capsicum (green)',           40,    0.9,   9.0,   0.3,   1.8,   100, 'g',   2.4,   4.0,   0.0,   0.0,   0.0),
    ('Brinjal / Eggplant',        24,    1.4,   5.1,   0.3,   2.5,   100, 'g',   3.5,   2.0,   0.0,   0.0,   0.0),
    ('Bhindi / Okra',             36,    2.2,   7.6,   0.2,   3.2,   100, 'g',   1.5,   7.0,   0.0,   0.0,   0.0),
    ('Karela / Bitter Gourd',     25,    1.6,   4.6,   0.2,   2.8,   100, 'g',   1.7,   5.0,   0.0,   0.0,   0.0),
    ('Lauki / Bottle Gourd',      15,    0.5,   3.4,   0.0,   0.5,   100, 'g',   1.6,   2.0,   0.0,   0.0,   0.0),
    ('Tinda / Apple Gourd',       22,    1.1,   4.7,   0.1,   1.5,   100, 'g',   1.0,   2.0,   0.0,   0.0,   0.0),
    ('Carrot',                     48,    0.9,   10.6,  0.2,   2.8,   100, 'g',   4.7,   69.0,  0.0,   0.0,   0.0),
    ('Peas (green)',               81,    5.4,   14.5,  0.4,   5.1,   100, 'g',   5.7,   5.0,   0.1,   0.0,   0.0),
    ('Mushroom',                   26,    3.1,   4.6,   0.3,   1.8,   100, 'g',   2.0,   5.0,   0.0,   0.0,   0.0),
    ('Broccoli',                   34,    2.8,   6.6,   0.4,   2.6,   100, 'g',   1.7,   33.0,  0.1,   0.0,   0.0),
    ('Cucumber',                   16,    0.7,   3.6,   0.1,   0.5,   100, 'g',   1.7,   2.0,   0.0,   0.0,   0.0),
    ('Pumpkin',                    26,    1.0,   6.5,   0.1,   0.5,   100, 'g',   2.8,   1.0,   0.1,   0.0,   0.0),
    ('Beetroot',                   43,    1.7,   9.6,   0.1,   2.8,   100, 'g',   6.8,   78.0,  0.0,   0.0,   0.0),
    // ── Fruits ─────────────────────────────────────────────────────────────────
    ('Mango',                      65,    0.6,   17.0,  0.4,   1.8,   100, 'g',   14.8,  1.0,   0.1,   0.0,   0.0),
    ('Banana',                     89,    1.1,   23.0,  0.3,   2.6,   120, 'g',   12.2,  1.0,   0.1,   0.0,   0.0),
    ('Apple',                      59,    0.3,   15.7,  0.2,   2.4,   150, 'g',   10.4,  1.0,   0.0,   0.0,   0.0),
    ('Orange',                     53,    0.8,   13.3,  0.2,   2.4,   130, 'g',   9.4,   0.0,   0.0,   0.0,   0.0),
    ('Guava',                      68,    2.6,   14.3,  1.0,   5.4,   100, 'g',   8.9,   2.0,   0.3,   0.0,   0.0),
    ('Papaya',                     43,    0.6,   10.8,  0.1,   1.8,   150, 'g',   7.8,   8.0,   0.0,   0.0,   0.0),
    ('Watermelon',                 30,    0.6,   7.6,   0.2,   0.4,   200, 'g',   6.2,   1.0,   0.0,   0.0,   0.0),
    ('Grapes',                     71,    0.7,   18.1,  0.2,   0.9,   100, 'g',   15.5,  2.0,   0.1,   0.0,   0.0),
    ('Pomegranate',                83,    1.7,   18.7,  1.2,   4.0,   100, 'g',   13.7,  3.0,   0.1,   0.0,   0.0),
    ('Pineapple',                  50,    0.5,   13.1,  0.1,   1.4,   100, 'g',   9.9,   1.0,   0.0,   0.0,   0.0),
    ('Coconut (fresh)',            354,   3.3,   15.2,  33.5,  9.0,   50,  'g',   6.2,   20.0,  29.7,  0.0,   0.0),
    ('Litchi',                     66,    0.8,   16.5,  0.4,   1.3,   100, 'g',   15.2,  1.0,   0.0,   0.0,   0.0),
    ('Chickoo / Sapota',           94,    0.7,   23.9,  1.1,   5.3,   100, 'g',   16.0,  12.0,  0.3,   0.0,   0.0),
    ('Pear',                       57,    0.4,   15.5,  0.1,   3.1,   150, 'g',   9.8,   1.0,   0.0,   0.0,   0.0),
    ('Strawberry',                 33,    0.7,   7.7,   0.3,   2.0,   100, 'g',   4.9,   1.0,   0.0,   0.0,   0.0),
    // ── Dairy ──────────────────────────────────────────────────────────────────
    ('Indian Cow milk without malai',     34.6,  3.46,  5.0,   0.08,  0.0,   240, 'ml',  5.0,   43.0,  0.04,  0.0,   2.0),
    ('Indian Buffalo milk without malai', 39.6,  3.96,  5.42,  0.21,  0.0,   240, 'ml',  5.42,  52.0,  0.08,  0.0,   3.0),
    ('Milk (full fat)',            67,    3.2,   4.4,   4.1,   0.0,   250, 'ml',  4.7,   43.0,  2.4,   0.1,   14.0),
    ('Milk (toned)',               58,    3.5,   4.8,   3.0,   0.0,   250, 'ml',  4.8,   44.0,  1.8,   0.1,   10.0),
    ('Milk (skimmed)',             35,    3.6,   5.0,   0.1,   0.0,   250, 'ml',  5.0,   45.0,  0.1,   0.0,   2.0),
    ('Curd / Dahi (full fat)',     98,    3.1,   4.7,   6.0,   0.0,   100, 'g',   3.2,   46.0,  3.7,   0.1,   18.0),
    ('Curd (low fat)',             62,    3.5,   7.5,   1.6,   0.0,   100, 'g',   4.0,   50.0,  1.0,   0.0,   6.0),
    ('Paneer (full fat)',          265,   18.3,  3.4,   20.8,  0.0,   100, 'g',   1.2,   50.0,  13.2,  0.5,   65.0),
    ('Paneer (low fat)',           173,   18.0,  5.0,   8.3,   0.0,   100, 'g',   2.0,   45.0,  5.2,   0.1,   30.0),
    ('Ghee',                       900,   0.3,   0.0,   99.8,  0.0,   10,  'g',   0.0,   2.0,   61.9,  2.8,   256.0),
    ('Butter',                     729,   0.6,   0.6,   81.0,  0.0,   10,  'g',   0.1,   684.0, 51.4,  3.3,   215.0),
    ('Khoa / Mawa',               421,   14.6,  25.3,  31.2,  0.0,   100, 'g',   19.0,  90.0,  19.8,  0.5,   95.0),
    ('Lassi (sweet)',              90,    3.6,   15.0,  1.8,   0.0,   200, 'ml',  10.0,  50.0,  1.1,   0.0,   8.0),
    ('Chaas / Buttermilk',        30,    1.8,   3.6,   0.9,   0.0,   200, 'ml',  2.0,   105.0, 0.6,   0.0,   4.0),
    ('Raita',                      64,    3.8,   5.6,   2.8,   0.4,   100, 'g',   2.5,   50.0,  1.8,   0.0,   10.0),
    ('Ice Cream (vanilla)',        207,   3.5,   23.6,  11.0,  0.0,   100, 'g',   20.0,  70.0,  6.5,   0.1,   35.0),
    // ── Eggs ───────────────────────────────────────────────────────────────────
    ('Egg (whole)',                173,   13.3,  0.0,   13.3,  0.0,   50,  'g',   0.4,   70.0,  3.3,   0.0,   372.0),
    ('Egg White',                  52,    10.9,  0.7,   0.2,   0.0,   100, 'g',   0.6,   166.0, 0.0,   0.0,   0.0),
    ('Egg Yolk',                   322,   15.9,  0.6,   26.5,  0.0,   20,  'g',   0.6,   48.0,  9.6,   0.0,   1234.0),
    ('Boiled Egg',                 155,   12.6,  1.1,   10.6,  0.0,   50,  'g',   1.1,   124.0, 3.3,   0.0,   373.0),
    ('Omelette (plain)',           180,   11.0,  1.5,   14.5,  0.0,   60,  'g',   0.5,   210.0, 4.5,   0.0,   298.0),
    // ── Poultry & Meat ─────────────────────────────────────────────────────────
    ('Chicken Breast (cooked)',    165,   31.0,  0.0,   3.6,   0.0,   100, 'g',   0.0,   74.0,  1.0,   0.0,   85.0),
    ('Chicken Thigh (cooked)',     209,   26.0,  0.0,   11.0,  0.0,   100, 'g',   0.0,   85.0,  3.0,   0.0,   105.0),
    ('Chicken Curry (home)',       155,   19.5,  3.0,   7.0,   0.5,   100, 'g',   1.0,   250.0, 2.0,   0.0,   55.0),
    ('Tandoori Chicken',           150,   22.0,  4.5,   5.5,   0.3,   100, 'g',   2.5,   350.0, 1.5,   0.0,   75.0),
    ('Mutton (cooked)',            194,   26.5,  0.0,   9.5,   0.0,   100, 'g',   0.0,   72.0,  3.7,   0.0,   97.0),
    ('Mutton Curry',               200,   21.0,  3.0,   12.0,  0.3,   100, 'g',   2.0,   300.0, 4.5,   0.0,   75.0),
    ('Keema (minced mutton)',      220,   23.0,  4.0,   13.0,  0.5,   100, 'g',   2.0,   350.0, 5.0,   0.0,   85.0),
    // ── Fish & Seafood ─────────────────────────────────────────────────────────
    ('Rohu Fish (cooked)',         97,    16.6,  0.0,   3.4,   0.0,   100, 'g',   0.0,   50.0,  0.7,   0.0,   55.0),
    ('Pomfret (cooked)',           105,   18.8,  0.0,   3.5,   0.0,   100, 'g',   0.0,   67.0,  0.8,   0.0,   62.0),
    ('Catla Fish (cooked)',        111,   17.5,  0.0,   4.5,   0.0,   100, 'g',   0.0,   48.0,  1.0,   0.0,   60.0),
    ('Prawn (cooked)',             99,    19.0,  0.9,   1.8,   0.0,   100, 'g',   0.0,   148.0, 0.3,   0.0,   152.0),
    ('Tuna (canned in water)',     116,   25.5,  0.0,   0.8,   0.0,   100, 'g',   0.0,   350.0, 0.2,   0.0,   47.0),
    ('Fish Curry',                 130,   17.0,  2.5,   6.0,   0.2,   100, 'g',   1.5,   280.0, 1.5,   0.0,   45.0),
    // ── Nuts & Seeds ───────────────────────────────────────────────────────────
    ('Almonds',                    577,   20.0,  20.0,  50.0,  11.7,  30,  'g',   4.0,   1.0,   3.7,   0.0,   0.0),
    ('Cashews',                    553,   18.2,  30.2,  43.9,  3.3,   30,  'g',   5.9,   12.0,  7.8,   0.0,   0.0),
    ('Walnuts',                    654,   15.2,  13.7,  65.2,  6.7,   30,  'g',   2.6,   2.0,   6.1,   0.0,   0.0),
    ('Peanuts (raw)',              567,   25.8,  16.1,  49.2,  8.5,   30,  'g',   4.7,   18.0,  6.9,   0.0,   0.0),
    ('Peanuts (roasted)',          585,   26.0,  19.0,  49.5,  8.0,   30,  'g',   4.0,   11.0,  7.0,   0.0,   0.0),
    ('Pistachios',                 560,   20.2,  27.2,  45.3,  10.6,  30,  'g',   7.7,   1.0,   5.9,   0.0,   0.0),
    ('Sesame Seeds',               573,   17.7,  23.5,  49.7,  11.8,  15,  'g',   0.3,   11.0,  7.0,   0.0,   0.0),
    ('Flaxseed',                   534,   18.3,  28.9,  42.2,  27.3,  15,  'g',   1.6,   30.0,  3.7,   0.0,   0.0),
    ('Sunflower Seeds',            584,   20.8,  20.0,  51.5,  8.6,   20,  'g',   2.6,   9.0,   4.5,   0.0,   0.0),
    ('Chia Seeds',                 486,   16.5,  42.1,  30.7,  34.4,  15,  'g',   0.0,   16.0,  3.3,   0.0,   0.0),
    ('Peanut Butter',              588,   25.1,  19.6,  50.4,  6.0,   32,  'g',   6.7,   469.0, 9.8,   0.0,   0.0),
    ('Chikki (peanut)',            490,   14.0,  55.0,  24.0,  4.0,   50,  'g',   25.0,  50.0,  4.0,   0.0,   0.0),
    // ── Indian Breads ──────────────────────────────────────────────────────────
    ('Roti / Chapati',             264,   9.6,   51.0,  3.7,   11.0,  40,  'g',   0.5,   3.0,   0.5,   0.0,   0.0),
    ('Plain Paratha',              287,   6.3,   40.0,  10.0,  3.2,   70,  'g',   1.0,   250.0, 2.5,   0.2,   5.0),
    ('Aloo Paratha',               310,   7.0,   44.0,  11.5,  3.5,   100, 'g',   1.5,   280.0, 2.8,   0.2,   8.0),
    ('Puri',                       340,   6.5,   43.0,  17.0,  3.0,   50,  'g',   0.5,   280.0, 4.0,   0.2,   0.0),
    ('Naan',                       263,   8.7,   44.8,  5.1,   2.2,   90,  'g',   2.0,   400.0, 1.0,   0.1,   5.0),
    ('Kulcha',                     272,   7.5,   46.0,  6.5,   2.5,   90,  'g',   2.0,   380.0, 1.2,   0.1,   3.0),
    ('Bhatura',                    380,   8.0,   50.0,  17.0,  2.5,   80,  'g',   1.5,   350.0, 3.8,   0.2,   5.0),
    ('Thepla',                     278,   8.5,   38.0,  10.0,  4.5,   60,  'g',   1.5,   200.0, 1.5,   0.0,   5.0),
    // ── South Indian ───────────────────────────────────────────────────────────
    ('Idli',                       58,    2.0,   11.5,  0.4,   0.5,   40,  'g',   0.2,   130.0, 0.1,   0.0,   0.0),
    ('Plain Dosa',                 165,   3.9,   29.0,  4.1,   1.4,   85,  'g',   0.5,   280.0, 0.8,   0.0,   0.0),
    ('Masala Dosa',                215,   5.5,   36.0,  6.5,   2.0,   120, 'g',   1.0,   350.0, 1.5,   0.0,   5.0),
    ('Uttapam',                    190,   5.5,   32.0,  5.0,   2.5,   100, 'g',   0.8,   300.0, 1.0,   0.0,   0.0),
    ('Upma',                       145,   3.0,   26.0,  3.2,   1.5,   100, 'g',   0.5,   350.0, 0.8,   0.0,   0.0),
    ('Sambar',                     50,    2.5,   8.7,   0.7,   2.1,   100, 'g',   2.0,   350.0, 0.2,   0.0,   0.0),
    ('Coconut Chutney',            180,   2.5,   8.0,   16.0,  4.0,   50,  'g',   2.5,   150.0, 14.0,  0.0,   0.0),
    ('Medu Vada',                  230,   7.5,   28.0,  11.0,  3.0,   60,  'g',   0.5,   400.0, 1.5,   0.0,   0.0),
    ('Pongal (ven)',               160,   4.5,   27.0,  4.5,   1.5,   100, 'g',   0.5,   300.0, 1.5,   0.0,   0.0),
    // ── Rice Dishes ────────────────────────────────────────────────────────────
    ('Chicken Biryani',            200,   10.0,  25.0,  7.0,   1.5,   100, 'g',   2.0,   500.0, 2.0,   0.0,   30.0),
    ('Veg Biryani',                170,   4.5,   30.0,  4.5,   2.0,   100, 'g',   2.0,   400.0, 1.0,   0.0,   0.0),
    ('Mutton Biryani',             225,   12.0,  25.0,  9.0,   1.5,   100, 'g',   2.0,   520.0, 3.0,   0.0,   40.0),
    ('Khichdi',                    135,   5.0,   25.0,  2.5,   2.5,   100, 'g',   1.0,   200.0, 0.5,   0.0,   0.0),
    ('Pulao (veg)',                155,   3.5,   28.0,  3.8,   1.5,   100, 'g',   1.5,   300.0, 0.8,   0.0,   0.0),
    ('Curd Rice',                  120,   3.5,   22.0,  2.5,   0.5,   100, 'g',   2.0,   150.0, 0.8,   0.0,   5.0),
    ('Lemon Rice',                 155,   2.8,   29.0,  4.0,   1.0,   100, 'g',   0.5,   250.0, 0.8,   0.0,   0.0),
    // ── Dal & Curry ────────────────────────────────────────────────────────────
    ('Dal Makhani',                150,   8.0,   21.0,  4.5,   5.6,   100, 'g',   2.0,   350.0, 2.0,   0.0,   10.0),
    ('Dal Tadka',                  120,   7.0,   18.0,  3.5,   5.0,   100, 'g',   1.5,   300.0, 0.8,   0.0,   0.0),
    ('Toor Dal Fry',               140,   7.5,   22.0,  3.0,   5.0,   100, 'g',   1.5,   280.0, 0.5,   0.0,   0.0),
    ('Palak Paneer',               132,   7.8,   7.5,   8.0,   2.6,   100, 'g',   2.0,   300.0, 4.5,   0.0,   25.0),
    ('Paneer Butter Masala',       225,   11.5,  9.0,   17.0,  1.5,   100, 'g',   4.0,   380.0, 8.5,   0.3,   40.0),
    ('Shahi Paneer',               240,   10.0,  8.0,   19.0,  1.0,   100, 'g',   3.5,   350.0, 10.0,  0.3,   45.0),
    ('Rajma Masala',               140,   8.5,   22.5,  3.0,   7.0,   100, 'g',   2.0,   350.0, 0.5,   0.0,   0.0),
    ('Chole Masala',               165,   8.5,   25.0,  4.5,   7.0,   100, 'g',   3.0,   380.0, 0.7,   0.0,   0.0),
    ('Mix Veg Sabzi',              80,    3.0,   11.0,  2.5,   3.0,   100, 'g',   2.0,   250.0, 0.5,   0.0,   0.0),
    ('Aloo Sabzi',                 100,   2.0,   15.0,  4.0,   1.5,   100, 'g',   1.5,   250.0, 1.0,   0.0,   0.0),
    ('Matar Paneer',               185,   9.5,   12.0,  11.5,  2.5,   100, 'g',   2.5,   320.0, 5.0,   0.0,   25.0),
    ('Kadai Paneer',               210,   10.5,  8.0,   16.0,  2.0,   100, 'g',   3.0,   350.0, 7.0,   0.0,   35.0),
    ('Bhindi Masala',              95,    2.8,   11.0,  4.5,   3.2,   100, 'g',   1.5,   280.0, 0.8,   0.0,   0.0),
    ('Baingan Bharta',             90,    2.5,   10.0,  4.5,   3.5,   100, 'g',   2.0,   280.0, 1.0,   0.0,   0.0),
    ('Kadhi (plain, no pakora)',   85,    3.5,   8.0,   4.5,   0.5,   100, 'g',   1.5,   300.0, 1.5,   0.0,   8.0),
    ('Kadhi Pakora',               145,   5.5,   14.0,  8.0,   1.0,   100, 'g',   1.5,   350.0, 1.8,   0.0,   15.0),
    ('Paneer Bhurji',              220,   13.0,  5.5,   16.5,  1.0,   100, 'g',   2.0,   380.0, 9.0,   0.3,   45.0),
    ('Egg Bhurji',                 185,   12.5,  3.0,   14.0,  0.5,   100, 'g',   1.5,   350.0, 4.0,   0.0,   280.0),
    ('Egg Bhurji (1 egg serving)', 148,   10.0,  2.4,   11.2,  0.4,   80,  'g',   1.2,   280.0, 3.2,   0.0,   224.0),
    ('Aloo Gobi',                  110,   2.5,   16.0,  4.0,   2.5,   100, 'g',   2.5,   260.0, 0.8,   0.0,   0.0),
    ('Saag (mustard greens)',      105,   4.5,   10.0,  5.5,   4.0,   100, 'g',   1.5,   280.0, 1.5,   0.0,   0.0),
    // ── Snacks ─────────────────────────────────────────────────────────────────
    ('Samosa (potato)',            265,   4.5,   35.0,  12.0,  2.5,   70,  'g',   1.5,   350.0, 3.0,   0.3,   0.0),
    ('Pakora (veg)',               280,   6.5,   32.0,  14.5,  2.5,   80,  'g',   1.0,   300.0, 2.5,   0.2,   0.0),
    ('Pani Puri',                  55,    1.0,   9.0,   1.8,   0.5,   20,  'g',   0.5,   100.0, 0.3,   0.0,   0.0),
    ('Bhel Puri',                  195,   5.0,   34.0,  5.5,   3.5,   100, 'g',   3.0,   350.0, 0.8,   0.0,   0.0),
    ('Pav Bhaji',                  250,   6.0,   37.0,  9.0,   4.0,   150, 'g',   5.0,   450.0, 2.5,   0.2,   10.0),
    ('Vada Pav',                   290,   7.5,   44.0,  10.0,  3.5,   130, 'g',   3.0,   450.0, 2.0,   0.2,   0.0),
    ('Dhokla',                     160,   5.5,   27.0,  3.8,   2.0,   100, 'g',   5.0,   380.0, 0.5,   0.0,   0.0),
    ('Khandvi',                    175,   6.5,   22.0,  6.5,   2.5,   100, 'g',   2.0,   280.0, 1.0,   0.0,   0.0),
    ('Mathri',                     450,   7.5,   58.0,  22.0,  2.0,   50,  'g',   0.5,   480.0, 5.5,   0.5,   0.0),
    ('Chakli',                     490,   8.5,   60.0,  25.0,  3.0,   50,  'g',   0.5,   450.0, 5.0,   0.3,   0.0),
    ('Khakhra',                    345,   11.0,  60.0,  7.5,   7.5,   40,  'g',   1.0,   300.0, 1.5,   0.1,   0.0),
    ('Namkeen Mixture',            490,   9.0,   58.0,  25.0,  3.5,   30,  'g',   1.5,   800.0, 5.0,   0.3,   0.0),
    ('Popcorn (plain)',            375,   9.0,   74.0,  4.3,   14.5,  25,  'g',   0.9,   2.0,   0.5,   0.0,   0.0),
    ('Murukku',                    490,   7.0,   63.0,  23.0,  2.5,   50,  'g',   0.5,   400.0, 5.5,   0.3,   0.0),
    // ── Indian Sweets ──────────────────────────────────────────────────────────
    ('Gulab Jamun',                380,   6.5,   55.0,  16.0,  0.3,   50,  'g',   38.0,  80.0,  9.0,   0.3,   25.0),
    ('Rasgulla',                   186,   3.8,   40.0,  2.2,   0.0,   80,  'g',   25.0,  40.0,  1.0,   0.0,   5.0),
    ('Kheer / Rice Pudding',       158,   3.5,   25.0,  5.5,   0.2,   100, 'g',   15.0,  60.0,  3.0,   0.1,   15.0),
    ('Halwa (suji)',               340,   5.0,   52.0,  12.0,  0.5,   100, 'g',   25.0,  80.0,  7.0,   0.3,   20.0),
    ('Laddoo (besan)',             450,   9.5,   60.0,  20.0,  3.0,   50,  'g',   28.0,  60.0,  6.0,   0.2,   0.0),
    ('Laddoo (coconut)',           420,   4.5,   52.0,  22.0,  5.0,   50,  'g',   25.0,  50.0,  12.0,  0.0,   0.0),
    ('Jalebi',                     375,   2.5,   61.0,  14.5,  0.5,   60,  'g',   35.0,  60.0,  3.5,   0.5,   0.0),
    ('Barfi (milk)',               370,   8.0,   48.0,  17.0,  0.0,   50,  'g',   32.0,  70.0,  9.0,   0.3,   35.0),
    ('Kaju Katli',                 465,   11.5,  54.0,  24.0,  1.5,   40,  'g',   30.0,  50.0,  5.5,   0.0,   0.0),
    ('Pedha',                      415,   7.0,   60.0,  16.0,  0.0,   50,  'g',   40.0,  80.0,  9.5,   0.2,   40.0),
    ('Payasam / Kheer',            152,   3.5,   24.0,  5.0,   0.3,   100, 'g',   18.0,  55.0,  2.8,   0.1,   12.0),
    ('Chikki (sesame)',            510,   13.5,  54.0,  28.0,  4.5,   40,  'g',   28.0,  30.0,  4.0,   0.0,   0.0),
    // ── Beverages ──────────────────────────────────────────────────────────────
    ('Chai (milk tea with sugar)', 60,    1.5,   9.5,   2.0,   0.0,   150, 'ml',  7.0,   30.0,  1.2,   0.0,   5.0),
    ('Black Tea (no sugar)',       2,     0.0,   0.4,   0.0,   0.0,   200, 'ml',  0.0,   2.0,   0.0,   0.0,   0.0),
    ('Filter Coffee (with milk)',  55,    1.2,   7.5,   2.5,   0.0,   150, 'ml',  5.0,   25.0,  1.5,   0.0,   8.0),
    ('Nimbu Pani (lemon water)',   30,    0.3,   7.8,   0.1,   0.3,   250, 'ml',  6.5,   5.0,   0.0,   0.0,   0.0),
    ('Coconut Water',              19,    0.7,   3.7,   0.2,   1.1,   250, 'ml',  2.6,   105.0, 0.1,   0.0,   0.0),
    ('Mango Lassi',                135,   3.5,   22.0,  3.5,   0.8,   250, 'ml',  16.0,  55.0,  2.0,   0.0,   10.0),
    ('Sugarcane Juice',            75,    0.2,   19.0,  0.0,   0.6,   250, 'ml',  17.0,  2.0,   0.0,   0.0,   0.0),
    ('Aam Panna (raw mango)',      70,    0.5,   18.0,  0.1,   0.5,   200, 'ml',  15.0,  5.0,   0.0,   0.0,   0.0),
    ('Jaljeera',                   25,    0.5,   6.0,   0.1,   0.3,   200, 'ml',  4.5,   380.0, 0.0,   0.0,   0.0),
    ('Turmeric Milk (haldi doodh)',75,    3.0,   8.0,   3.2,   0.5,   200, 'ml',  6.0,   55.0,  2.0,   0.1,   10.0),
    // ── Oils & Fats ────────────────────────────────────────────────────────────
    ('Mustard Oil',                884,   0.0,   0.0,   100.0, 0.0,   10,  'ml',  0.0,   0.0,   11.6,  0.4,   0.0),
    ('Coconut Oil',                884,   0.0,   0.0,   100.0, 0.0,   10,  'ml',  0.0,   0.0,   86.5,  0.0,   0.0),
    ('Groundnut / Peanut Oil',     900,   0.0,   0.0,   100.0, 0.0,   10,  'ml',  0.0,   0.0,   16.9,  0.0,   0.0),
    ('Sunflower Oil',              884,   0.0,   0.0,   100.0, 0.0,   10,  'ml',  0.0,   0.0,   10.1,  0.0,   0.0),
    ('Olive Oil',                  884,   0.0,   0.0,   100.0, 0.0,   10,  'ml',  0.0,   2.0,   13.8,  0.0,   0.0),
    // ── International / Gym Foods ──────────────────────────────────────────────
    ('Whey Protein Powder',        120,   24.0,  3.0,   1.5,   0.0,   30,  'g',   2.0,   100.0, 0.5,   0.0,   10.0),
    ('Casein Protein Powder',      120,   24.0,  4.0,   1.0,   0.0,   30,  'g',   1.5,   90.0,  0.4,   0.0,   8.0),
    ('Greek Yogurt (low fat)',     59,    10.0,  3.6,   0.4,   0.0,   150, 'g',   3.2,   50.0,  0.1,   0.0,   5.0),
    ('Oats (cooked, salted)',      71,    2.5,   12.0,  1.5,   1.7,   100, 'g',   0.4,   300.0, 0.2,   0.0,   0.0),
    ('Brown Rice (cooked)',        112,   2.3,   23.0,  0.9,   1.8,   100, 'g',   0.3,   5.0,   0.2,   0.0,   0.0),
    ('Quinoa (cooked)',            120,   4.4,   21.3,  1.9,   2.8,   100, 'g',   0.9,   7.0,   0.3,   0.0,   0.0),
    ('Salmon',                     208,   20.0,  0.0,   13.0,  0.0,   100, 'g',   0.0,   59.0,  3.0,   0.0,   63.0),
    ('Tuna (fresh, cooked)',       132,   28.0,  0.0,   1.4,   0.0,   100, 'g',   0.0,   45.0,  0.4,   0.0,   49.0),
    ('Avocado',                    160,   2.0,   8.5,   14.7,  6.7,   100, 'g',   0.7,   7.0,   2.1,   0.0,   0.0),
    ('Broccoli (cooked)',          34,    2.8,   6.6,   0.4,   2.6,   100, 'g',   1.2,   41.0,  0.1,   0.0,   0.0),
    ('Honey',                      304,   0.3,   82.4,  0.0,   0.2,   20,  'g',   82.1,  4.0,   0.0,   0.0,   0.0),
    ('Protein Bar',                380,   28.0,  40.0,  12.0,  4.0,   60,  'g',   12.0,  200.0, 3.5,   0.2,   5.0),
    ('Dark Chocolate (70%+)',      600,   7.8,   46.0,  43.0,  10.9,  30,  'g',   23.0,  20.0,  12.5,  0.0,   3.0),
    ('Cottage Cheese',             98,    11.0,  3.4,   4.3,   0.0,   100, 'g',   3.4,   364.0, 1.4,   0.0,   17.0),
    // ── Supplements ────────────────────────────────────────────────────────────
    ('BeastLife Creatine Unflavoured',                  0,   0.0,  0.0,   0.0,  0.0, 3,  'scoop (3g)',   0.0, 0.0,   0.0,  0.0,  0.0),
    ('BeastLife Isorich Whey Protein Isolate',          378, 74.24,10.09, 4.48, 0.0, 33, 'scoop (33g)', 1.88, 185.09, 1.32, 0.09, 94.06),
    ('NATURALTEIN Natural Whey Protein Isolate Chocolate', 397, 80.2, 5.3, 6.1, 0.0, 30, 'scoop (30g)', 1.5, 109.0, 3.6, 0.0, 1.3),
    ('True Elements Steel Cut Oats',                   419.2, 11.5, 65.7, 12.2, 10.7, 40, 'g',          0.0, 4.0,   2.8,  0.0,  0.0),
    ('BeastLife Pre-Workout Orange Flavour',            10.84, 0.0,  2.71, 0.0,  0.0,  7,    'scoop (7g)',   0.0,  726.43, 0.0, 0.0, 0.0),
    ('BeastLife Multivitamin tablets',                 159.3, 0.0,   38.7,  0.55, 0.16, 1.82, 'tablet (1.82g)',  0.93,    140.1,   0.0, 0.0, 0.0),
    ('NATURALTEIN Omega-3 Fish Oil 1250mg Triple Strength Softgel Capsules | 450mg EPA & 300mg DHA in Triglyceride Form',
                                                       875.3, 21.33, 10.0,  83.33, 0.0, 1.5,  'softgel (1.5g)', 0.0,     3333.33, 0.0, 0.0, 0.0),
  ];

  Future<void> _seedFoodsIfEmpty(Database db) async {
    final count = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM foods'),
        ) ??
        0;
    if (count > 0) return;
    const uuid = Uuid();
    final batch = db.batch();
    for (final (name, cal, prot, carbs, fat, fiber, size, unit, sugar, sodium, satFat, transFat, chol) in _kFoodSeed) {
      batch.insert('foods', {
        'id': uuid.v4(),
        'name': name,
        'calories': cal,
        'protein_g': prot,
        'carbs_g': carbs,
        'fat_g': fat,
        'fiber_g': fiber,
        'serving_size': size,
        'serving_unit': unit,
        'sugar_g': sugar,
        'sodium_mg': sodium,
        'saturated_fat_g': satFat,
        'trans_fat_g': transFat,
        'cholesterol_mg': chol,
        'is_custom': 0,
      });
    }
    await batch.commit(noResult: true);
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

  Future<List<WorkoutLog>> getWorkoutLogsForDate(String date) async {
    final db = await database;
    final maps = await db.query(
      'workout_logs',
      where: 'date = ?',
      whereArgs: [date],
      orderBy: 'rowid ASC',
    );
    final logs = <WorkoutLog>[];
    for (final map in maps) {
      final log = WorkoutLog.fromMap(map);
      log.exercises.addAll(await _getExerciseLogs(db, log.id));
      logs.add(log);
    }
    return logs;
  }

  Future<WorkoutLog?> getWorkoutLogById(String id) async {
    final db = await database;
    final maps = await db.query('workout_logs', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    final log = WorkoutLog.fromMap(maps.first);
    log.exercises.addAll(await _getExerciseLogs(db, log.id));
    return log;
  }

  Future<WorkoutLog> createWorkoutLog(WorkoutLog log) async {
    final db = await database;
    // Stamp the wall-clock start so watch (Samsung) sessions can be matched to
    // this workout by time overlap.
    await db.insert('workout_logs', {
      ...log.toMap(),
      'started_at': DateTime.now().toUtc().toIso8601String(),
    });
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

  // Returns the most-recent completed sets for [exerciseId] from a session
  // before [beforeDate]. Used to power progressive-overload suggestions.
  // Returns null if there's no prior data.
  Future<({String date, List<SetLog> sets})?> getLastCompletedSetsForExercise(
    String exerciseId,
    String beforeDate,
  ) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT wl.date, el.id AS exercise_log_id
      FROM workout_logs wl
      INNER JOIN exercise_logs el ON el.workout_log_id = wl.id
      WHERE el.exercise_id = ?
        AND wl.date < ?
        AND wl.completed = 1
      ORDER BY wl.date DESC
      LIMIT 1
    ''', [exerciseId, beforeDate]);
    if (rows.isEmpty) return null;
    final exerciseLogId = rows.first['exercise_log_id'] as String;
    final date = rows.first['date'] as String;
    final setRows = await db.query(
      'set_logs',
      where: 'exercise_log_id = ? AND is_completed = 1',
      whereArgs: [exerciseLogId],
      orderBy: 'set_number ASC',
    );
    if (setRows.isEmpty) return null;
    final sets = setRows.map(SetLog.fromMap).toList();
    return (date: date, sets: sets);
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

  Future<void> updateExerciseLogNote(String id, String? note) async {
    final db = await database;
    await db.update(
      'exercise_logs',
      {'notes': note},
      where: 'id = ?',
      whereArgs: [id],
    );
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

  /// Returns exercises where the peak estimated 1RM has not improved for 3+
  /// consecutive calendar weeks across the last 6 logged sessions.
  Future<List<PlateauAlert>> getPlateauedExercises() async {
    final db = await database;

    // Exercises logged in at least 3 completed sessions
    final exRows = await db.rawQuery('''
      SELECT el.exercise_id
      FROM exercise_logs el
      INNER JOIN workout_logs wl ON el.workout_log_id = wl.id
      WHERE wl.completed = 1
      GROUP BY el.exercise_id
      HAVING COUNT(DISTINCT wl.id) >= 3
    ''');

    final alerts = <PlateauAlert>[];

    for (final exRow in exRows) {
      final exerciseId = exRow['exercise_id'] as String;

      // Best estimated 1RM (Epley: w*(1+r/30)) per session — last 6 sessions
      final sessions = await db.rawQuery('''
        SELECT wl.date,
               MAX(sl.weight * (1.0 + COALESCE(sl.reps, 1) / 30.0)) AS best_1rm
        FROM set_logs sl
        INNER JOIN exercise_logs el ON sl.exercise_log_id = el.id
        INNER JOIN workout_logs wl  ON el.workout_log_id  = wl.id
        WHERE el.exercise_id = ?
          AND sl.weight IS NOT NULL
          AND sl.weight > 0
          AND sl.is_completed = 1
          AND wl.completed = 1
        GROUP BY wl.id
        ORDER BY wl.date DESC
        LIMIT 6
      ''', [exerciseId]);

      if (sessions.length < 3) continue;

      // Group by calendar week (keyed by Monday's date string)
      final weekBest = <String, double>{};
      for (final s in sessions) {
        final date = DateTime.parse(s['date'] as String);
        final key = _weekKey(date);
        final orm = (s['best_1rm'] as num).toDouble();
        if (orm > (weekBest[key] ?? 0)) weekBest[key] = orm;
      }

      if (weekBest.length < 3) continue;

      final weeks = weekBest.keys.toList()..sort();
      final vals = weeks.map((w) => weekBest[w]!).toList();

      // Find the last week where a meaningful new peak (+0.5%) was achieved
      double runMax = 0;
      int lastImprovementIdx = 0;
      for (int i = 0; i < vals.length; i++) {
        if (vals[i] > runMax * 1.005) {
          runMax = vals[i];
          lastImprovementIdx = i;
        }
      }

      final stagnantWeeks = vals.length - lastImprovementIdx;
      if (stagnantWeeks < 3) continue;

      final exMeta = await db.query('exercises',
          where: 'id = ?', whereArgs: [exerciseId], limit: 1);
      if (exMeta.isEmpty) continue;

      final exName = exMeta.first['name'] as String;
      final muscleGroup = exMeta.first['muscle_group'] as String;

      alerts.add(PlateauAlert(
        exerciseId: exerciseId,
        exerciseName: exName,
        muscleGroup: muscleGroup,
        current1RM: runMax,
        weeksStagnant: stagnantWeeks,
        suggestion: _plateauSuggestion(exName, muscleGroup),
      ));
    }

    alerts.sort((a, b) => b.weeksStagnant.compareTo(a.weeksStagnant));
    return alerts;
  }

  // Monday-keyed week string, e.g. "2025-04-14"
  String _weekKey(DateTime date) {
    final monday = date.subtract(Duration(days: date.weekday - 1));
    return '${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';
  }

  String _plateauSuggestion(String name, String muscleGroup) {
    final n = name.toLowerCase();
    // Compound lifts
    if (n.contains('bench') ||
        n.contains('squat') ||
        n.contains('deadlift') ||
        n.contains('overhead press') ||
        n.contains('ohp') ||
        (n.contains('row') && muscleGroup == 'Back') ||
        n.contains('pull-up') ||
        n.contains('pullup')) {
      return 'Try a deload week at 60% weight, then reset';
    }
    // Isolation lifts
    if (n.contains('curl') ||
        n.contains('extension') ||
        n.contains('lateral') ||
        n.contains('raise') ||
        n.contains('fly') ||
        n.contains('flye') ||
        n.contains('kickback') ||
        n.contains('pulldown')) {
      return 'Try increasing reps before adding weight, or swap variation';
    }
    return 'Consider changing rep range or taking a rest day before next session';
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

  Future<Map<String, int>> getWorkoutCountsByDate(
      String fromDate, String toDate) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT date, COUNT(*) as cnt
      FROM workout_logs
      WHERE completed = 1 AND date >= ? AND date <= ?
      GROUP BY date
    ''', [fromDate, toDate]);
    return {for (final r in rows) r['date'] as String: r['cnt'] as int};
  }

  Future<List<Map<String, dynamic>>> getWorkoutSummaryForDate(
      String date) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT wl.workout_name,
             COALESCE(SUM(CASE WHEN sl.is_completed = 1
               THEN sl.weight * sl.reps ELSE 0 END), 0) AS total_volume
      FROM workout_logs wl
      LEFT JOIN exercise_logs el ON el.workout_log_id = wl.id
      LEFT JOIN set_logs sl ON sl.exercise_log_id = el.id
      WHERE wl.date = ? AND wl.completed = 1
      GROUP BY wl.id, wl.workout_name
    ''', [date]);
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
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

  // Returns the body weight as of [date]: the entry for that exact date if
  // it exists, otherwise the most recent entry from any earlier date.
  Future<double?> getBodyWeightAsOf(String date) async {
    final db = await database;
    final rows = await db.query(
      'body_weight_logs',
      where: 'date <= ?',
      whereArgs: [date],
      orderBy: 'date DESC',
      limit: 1,
      columns: ['weight_kg'],
    );
    if (rows.isEmpty) return null;
    return (rows.first['weight_kg'] as num).toDouble();
  }

  // ─── BODY MEASUREMENTS ──────────────────────────────────────────────────────

  Future<void> logMeasurement(String date, String type, double valueCm) async {
    final db = await database;
    await db.insert(
      'body_measurements',
      {'date': date, 'type': type, 'value_cm': valueCm},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteMeasurement(String date, String type) async {
    final db = await database;
    await db.delete('body_measurements',
        where: 'date = ? AND type = ?', whereArgs: [date, type]);
  }

  Future<Map<String, double>> getMeasurementsForDate(String date) async {
    final db = await database;
    final rows = await db.query('body_measurements',
        where: 'date = ?', whereArgs: [date]);
    return {
      for (final r in rows) r['type'] as String: (r['value_cm'] as num).toDouble()
    };
  }

  /// Latest value per measurement type.
  Future<Map<String, double>> getLatestMeasurements() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT type, value_cm
      FROM body_measurements
      WHERE rowid IN (
        SELECT MAX(rowid) FROM body_measurements GROUP BY type
      )
    ''');
    return {
      for (final r in rows) r['type'] as String: (r['value_cm'] as num).toDouble()
    };
  }

  /// Latest logged date per measurement type.
  Future<Map<String, String>> getLatestMeasurementDates() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT type, MAX(date) AS latest_date FROM body_measurements GROUP BY type
    ''');
    return {
      for (final r in rows) r['type'] as String: r['latest_date'] as String
    };
  }

  Future<List<Map<String, dynamic>>> getMeasurementHistory(String type,
      {String? fromDate}) async {
    final db = await database;
    final where = StringBuffer('type = ?');
    final args = <dynamic>[type];
    if (fromDate != null) {
      where.write(' AND date >= ?');
      args.add(fromDate);
    }
    return db.query('body_measurements',
        where: where.toString(), whereArgs: args, orderBy: 'date ASC');
  }

  /// All distinct dates that have at least one measurement, newest first.
  Future<List<String>> getMeasurementDates() async {
    final db = await database;
    final rows = await db.rawQuery(
        'SELECT DISTINCT date FROM body_measurements ORDER BY date DESC');
    return rows.map((r) => r['date'] as String).toList();
  }

  // ─── PROGRESS PHOTOS ────────────────────────────────────────────────────────

  Future<List<ProgressPhoto>> getProgressPhotos() async {
    final db = await database;
    final rows = await db.query('progress_photos',
        orderBy: 'date DESC, id DESC');
    return rows.map(ProgressPhoto.fromMap).toList();
  }

  Future<int> addProgressPhoto(ProgressPhoto photo) async {
    final db = await database;
    return await db.insert('progress_photos', photo.toMap());
  }

  Future<void> deleteProgressPhoto(int id) async {
    final db = await database;
    final rows = await db.query('progress_photos',
        where: 'id = ?', whereArgs: [id], columns: ['file_path']);
    if (rows.isNotEmpty) {
      final path = rows.first['file_path'] as String;
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    await db.delete('progress_photos', where: 'id = ?', whereArgs: [id]);
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
          'notes': e['note'] as String?,
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

  // ─── AI EXPORT ──────────────────────────────────────────────────────────────

  /// Generates a human-readable Markdown document containing all user data,
  /// formatted for pasting into any AI chatbot for personalised analysis.
  Future<String> exportForAI({
    Set<String>? categories,
    String? fromDate,
    String? toDate,
  }) async {
    // null categories = include everything
    bool hasCat(String key) => categories == null || categories.contains(key);
    final db = await database;
    final today = _fmt(DateTime.now());
    final from = fromDate ?? '2000-01-01';
    final to = toDate ?? today;
    final isFiltered = from != '2000-01-01' || to != today;
    final sb = StringBuffer();

    // ── Header ────────────────────────────────────────────────────────────────
    sb.writeln('# Aawara Fitness & Nutrition Data');
    sb.writeln('> Generated: $today');
    if (isFiltered) sb.writeln('> Date range: $from → $to');
    sb.writeln('> Paste this into any AI assistant to get personalised analysis of your fitness, nutrition, and wellness trends.');
    sb.writeln();

    // ── Overview ──────────────────────────────────────────────────────────────
    sb.writeln('## Overview');
    sb.writeln('| Metric | Value |');
    sb.writeln('|--------|-------|');
    if (hasCat('workouts')) {
      final totalWorkouts = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM workout_logs WHERE completed = 1 AND date >= ? AND date <= ?',
            [from, to],
          )) ?? 0;
      final totalWorkoutMins = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT SUM(duration_seconds) FROM workout_logs WHERE completed = 1 AND date >= ? AND date <= ?',
            [from, to],
          )) ?? 0;
      final totalVolume = (await db.rawQuery('''
        SELECT SUM(sl.weight * sl.reps) as v
        FROM set_logs sl
        JOIN exercise_logs el ON el.id = sl.exercise_log_id
        JOIN workout_logs wl ON wl.id = el.workout_log_id
        WHERE sl.weight IS NOT NULL AND sl.reps IS NOT NULL
          AND wl.date >= ? AND wl.date <= ?
      ''', [from, to])).first['v'];
      sb.writeln('| Completed workouts | $totalWorkouts |');
      sb.writeln('| Total training time | ${(totalWorkoutMins / 60).toStringAsFixed(0)} hours |');
      if (totalVolume != null) {
        sb.writeln('| Total volume lifted | ${((totalVolume as num).toDouble() / 1000).toStringAsFixed(1)} tonnes |');
      }
    }
    if (hasCat('bodyWeight')) {
      final bwCount = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM body_weight_logs WHERE date >= ? AND date <= ?',
            [from, to],
          )) ?? 0;
      sb.writeln('| Body weight entries | $bwCount |');
    }
    if (hasCat('nutrition')) {
      final nutritionDays = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM nutrition_logs WHERE date >= ? AND date <= ?',
            [from, to],
          )) ?? 0;
      sb.writeln('| Nutrition days logged | $nutritionDays |');
    }
    if (hasCat('stepLogs')) {
      final stepDays = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM step_logs WHERE date >= ? AND date <= ?',
            [from, to],
          )) ?? 0;
      sb.writeln('| Step days logged | $stepDays |');
    }
    sb.writeln();

    // ── Nutrition Goals ───────────────────────────────────────────────────────
    if (hasCat('nutritionGoals')) {
      final goals = await db.query('nutrition_goals', limit: 1);
      if (goals.isNotEmpty) {
        final g = goals.first;
        sb.writeln('## Nutrition Goals');
        sb.writeln('| Calories | Protein | Carbs | Fat |');
        sb.writeln('|----------|---------|-------|-----|');
        sb.writeln('| ${(g['calories'] as num).round()} kcal | ${(g['protein_g'] as num).round()} g | ${(g['carbs_g'] as num).round()} g | ${(g['fat_g'] as num).round()} g |');
        sb.writeln();
      }
    }

    // ── Body Weight ───────────────────────────────────────────────────────────
    if (hasCat('bodyWeight')) {
      final bwLogs = await db.query('body_weight_logs',
          where: 'date >= ? AND date <= ?',
          whereArgs: [from, to],
          orderBy: 'date ASC');
      if (bwLogs.isNotEmpty) {
        sb.writeln('## Body Weight Log');
        final first = bwLogs.first;
        final last = bwLogs.last;
        final firstW = (first['weight_kg'] as num).toDouble();
        final lastW = (last['weight_kg'] as num).toDouble();
        final diff = lastW - firstW;
        sb.writeln('**Start:** ${firstW.toStringAsFixed(1)} kg (${first['date']}) → '
            '**Current:** ${lastW.toStringAsFixed(1)} kg (${last['date']}) | '
            '**Change:** ${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)} kg');
        sb.writeln();
        sb.writeln('| Date | Weight (kg) |');
        sb.writeln('|------|------------|');
        for (final row in bwLogs) {
          sb.writeln('| ${row['date']} | ${(row['weight_kg'] as num).toStringAsFixed(1)} |');
        }
        sb.writeln();
      }
    }

    // ── Exercise Personal Records ─────────────────────────────────────────────
    if (hasCat('personalRecords')) {
      final prs = await db.rawQuery('''
        SELECT ep.best_1rm, ep.date, e.name
        FROM exercise_prs ep
        JOIN exercises e ON e.id = ep.exercise_id
        WHERE ep.date >= ? AND ep.date <= ?
        ORDER BY ep.best_1rm DESC
      ''', [from, to]);
      if (prs.isNotEmpty) {
        sb.writeln('## Personal Records (Best Estimated 1RM)');
        sb.writeln('| Exercise | Best 1RM (kg) | Date |');
        sb.writeln('|----------|--------------|------|');
        for (final pr in prs) {
          sb.writeln('| ${pr['name']} | ${(pr['best_1rm'] as num).toStringAsFixed(1)} | ${pr['date']} |');
        }
        sb.writeln();
      }
    }

    // ── Workout History ───────────────────────────────────────────────────────
    if (hasCat('workouts')) {
      final wLogs = await db.query('workout_logs',
          where: 'date >= ? AND date <= ?',
          whereArgs: [from, to],
          orderBy: 'date DESC');
      if (wLogs.isNotEmpty) {
        sb.writeln('## Workout History');
        for (final wRow in wLogs) {
          final wId = wRow['id'] as String;
          final durationMin = wRow['duration_seconds'] != null
              ? ' · ${((wRow['duration_seconds'] as int) / 60).round()} min'
              : '';
          final completed = (wRow['completed'] as int) == 1;
          sb.writeln('### ${wRow['date']} — ${wRow['workout_name']}$durationMin${completed ? '' : ' (incomplete)'}');

          // Watch (Samsung Health) sessions for this workout — one line each,
          // named (Weight machine, Treadmill, …).
          final watchSessions = await getWatchSummariesForWorkout(wId);
          for (final watch in watchSessions) {
            final parts = <String>[
              if (watch['hr_avg'] != null) 'avg ${watch['hr_avg']} bpm',
              if (watch['hr_max'] != null) 'max ${watch['hr_max']}',
              if (watch['calories'] != null)
                '${(watch['calories'] as num).round()} kcal',
            ];
            final zones = watch['hr_zone_seconds'] as Map?;
            if (zones != null) {
              String m(String k) => '${((zones[k] as int? ?? 0) / 60).round()}m';
              parts.add(
                  'zones: peak ${m('peak')}, cardio ${m('cardio')}, fat-burn ${m('fat_burn')}, warm-up ${m('warm_up')}');
            }
            sb.writeln('_Watch — ${watch['name']}: ${parts.join(' · ')}_');
          }

          final exLogs = await db.query('exercise_logs',
              where: 'workout_log_id = ?', whereArgs: [wId], orderBy: 'order_index ASC');
          for (final exRow in exLogs) {
            final exId = exRow['exercise_id'] as String;
            final exData = await db.query('exercises', where: 'id = ?', whereArgs: [exId], limit: 1);
            final exName = exData.isNotEmpty ? exData.first['name'] as String : exId;
            final sets = await db.query('set_logs',
                where: 'exercise_log_id = ?', whereArgs: [exRow['id']], orderBy: 'set_number ASC');

            if (sets.isEmpty) {
              sb.writeln('- **$exName** — no sets logged');
              continue;
            }

            final isCardio = sets.first['weight'] == null && sets.first['duration_seconds'] != null;
            sb.writeln('- **$exName**');
            if (isCardio) {
              for (final s in sets) {
                final dur = s['duration_seconds'] != null
                    ? '${((s['duration_seconds'] as int) / 60).round()} min' : '';
                final dist = s['distance_km'] != null ? ' · ${s['distance_km']} km' : '';
                final speed = s['speed'] != null ? ' · ${s['speed']} km/h' : '';
                sb.writeln('  - Set ${s['set_number']}: $dur$dist$speed');
              }
            } else {
              for (final s in sets) {
                final w = s['weight'] != null ? '${s['weight']} kg' : '—';
                final r = s['reps'] != null ? '${s['reps']} reps' : '—';
                final done = (s['is_completed'] as int? ?? 0) == 1 ? ' ✓' : '';
                sb.writeln('  - Set ${s['set_number']}: $w × $r$done');
              }
            }
            final exNote = exRow['notes'] as String?;
            if (exNote != null && exNote.isNotEmpty) {
              sb.writeln('  - _Note: $exNote');
            }
          }
          sb.writeln();
        }
      }
    }

    // ── Nutrition ─────────────────────────────────────────────────────────────
    if (hasCat('nutrition')) {
      final nutLogs = await db.query('nutrition_logs',
          where: 'date >= ? AND date <= ?',
          whereArgs: [from, to],
          orderBy: 'date DESC');
      if (nutLogs.isNotEmpty) {
        sb.writeln('## Nutrition — Daily Summaries');
        double sumCal = 0, sumPro = 0, sumCarb = 0, sumFat = 0;
        final summaryRows = <Map<String, dynamic>>[];

        for (final nl in nutLogs) {
          final entries = await db.rawQuery('''
            SELECT ne.quantity, ne.meal_type,
                   f.name, f.calories, f.protein_g, f.carbs_g, f.fat_g, f.serving_size
            FROM nutrition_entries ne
            JOIN foods f ON f.id = ne.food_id
            WHERE ne.log_id = ?
          ''', [nl['id']]);

          double cal = 0, pro = 0, carb = 0, fat = 0;
          for (final e in entries) {
            final q = (e['quantity'] as num).toDouble();
            final s = (e['serving_size'] as num).toDouble();
            final mult = (q * s) / 100.0;
            cal += (e['calories'] as num).toDouble() * mult;
            pro += (e['protein_g'] as num).toDouble() * mult;
            carb += (e['carbs_g'] as num).toDouble() * mult;
            fat += (e['fat_g'] as num).toDouble() * mult;
          }
          sumCal += cal; sumPro += pro; sumCarb += carb; sumFat += fat;
          summaryRows.add({
            'date': nl['date'],
            'cal': cal, 'pro': pro, 'carb': carb, 'fat': fat,
            'entries': entries,
          });
        }

        final n = nutLogs.length;
        sb.writeln('**Daily averages over $n days:** '
            '${(sumCal / n).round()} kcal | Protein ${(sumPro / n).round()} g | '
            'Carbs ${(sumCarb / n).round()} g | Fat ${(sumFat / n).round()} g');
        sb.writeln();
        sb.writeln('| Date | Calories | Protein (g) | Carbs (g) | Fat (g) |');
        sb.writeln('|------|----------|-------------|-----------|---------|');
        for (final row in summaryRows) {
          sb.writeln('| ${row['date']} | ${(row['cal'] as double).round()} | '
              '${(row['pro'] as double).toStringAsFixed(1)} | '
              '${(row['carb'] as double).toStringAsFixed(1)} | '
              '${(row['fat'] as double).toStringAsFixed(1)} |');
        }
        sb.writeln();

        sb.writeln('## Nutrition — Detailed Food Log');
        const mealOrder = ['Breakfast', 'Lunch', 'Dinner', 'Snack'];
        for (final row in summaryRows) {
          sb.writeln('### ${row['date']}');
          final entries = row['entries'] as List<Map<String, dynamic>>;
          final byMeal = <String, List<Map<String, dynamic>>>{};
          for (final e in entries) {
            (byMeal[e['meal_type'] as String] ??= []).add(e);
          }
          for (final meal in mealOrder) {
            if (!byMeal.containsKey(meal)) continue;
            sb.writeln('**$meal**');
            for (final e in byMeal[meal]!) {
              final q = (e['quantity'] as num).toDouble();
              final s = (e['serving_size'] as num).toDouble();
              final grams = (q * s).round();
              final cal = ((e['calories'] as num).toDouble() * q * s / 100).round();
              final pro = ((e['protein_g'] as num).toDouble() * q * s / 100).toStringAsFixed(1);
              sb.writeln('- ${e['name']} — ${grams}g · $cal kcal · ${pro}g protein');
            }
          }
          sb.writeln();
        }
      }
    }

    // ── Water Intake ──────────────────────────────────────────────────────────
    if (hasCat('water')) {
      final water = await db.query('water_logs',
          where: 'date >= ? AND date <= ?',
          whereArgs: [from, to],
          orderBy: 'date ASC');
      if (water.isNotEmpty) {
        sb.writeln('## Water Intake');
        final avgGlasses = water.fold(0, (s, r) => s + (r['glasses_drunk'] as int)) / water.length;
        sb.writeln('**Average:** ${avgGlasses.toStringAsFixed(1)} glasses/day '
            '(${(avgGlasses * 0.25).toStringAsFixed(2)} L/day)');
        sb.writeln();
        sb.writeln('| Date | Glasses | Target | Litres |');
        sb.writeln('|------|---------|--------|--------|');
        for (final w in water) {
          final g = w['glasses_drunk'] as int;
          final t = w['target_glasses'] as int;
          sb.writeln('| ${w['date']} | $g | $t | ${(g * 0.25).toStringAsFixed(2)} |');
        }
        sb.writeln();
      }
    }

    // ── Wellness Log ──────────────────────────────────────────────────────────
    if (hasCat('wellness')) {
      final wellness = await db.query('wellness_logs',
          where: 'date >= ? AND date <= ?',
          whereArgs: [from, to],
          orderBy: 'date DESC');
      if (wellness.isNotEmpty) {
        sb.writeln('## Wellness Log');
        final avgSleep = wellness.fold(0.0, (s, r) => s + (r['sleep_hours'] as num).toDouble()) / wellness.length;
        final avgEnergy = wellness.fold(0.0, (s, r) => s + (r['energy'] as int)) / wellness.length;
        final avgSore = wellness.fold(0.0, (s, r) => s + (r['soreness'] as int)) / wellness.length;
        sb.writeln('**Averages:** Sleep ${avgSleep.toStringAsFixed(1)} hrs | '
            'Energy ${avgEnergy.toStringAsFixed(1)}/5 | Soreness ${avgSore.toStringAsFixed(1)}/5');
        sb.writeln();
        sb.writeln('| Date | Sleep (hrs) | Energy (1–5) | Soreness (1–5) | Notes |');
        sb.writeln('|------|-------------|--------------|----------------|-------|');
        for (final w in wellness) {
          final notes = (w['notes'] as String? ?? '').replaceAll('|', '/');
          sb.writeln('| ${w['date']} | ${(w['sleep_hours'] as num).toStringAsFixed(1)} | '
              '${w['energy']} | ${w['soreness']} | $notes |');
        }
        sb.writeln();
      }
    }

    // ── Sleep ─────────────────────────────────────────────────────────────────
    if (hasCat('sleep')) {
      final sleep = await db.query('sleep_sessions',
          where: 'date >= ? AND date <= ?',
          whereArgs: [from, to],
          orderBy: 'date DESC');
      if (sleep.isNotEmpty) {
        sb.writeln('## Sleep');
        final avgScore = sleep.fold(0, (s, r) => s + (r['score'] as int)) / sleep.length;
        final avgAsleep = sleep.fold(0, (s, r) => s + (r['asleep_minutes'] as int)) / sleep.length;
        sb.writeln('**Averages over ${sleep.length} nights:** '
            'Score ${avgScore.round()}/100 | '
            'Time asleep ${(avgAsleep / 60).toStringAsFixed(1)} hrs');
        sb.writeln();
        sb.writeln('| Date | Score | Asleep | Deep | REM | Light | Awake | HR avg | SpO₂ avg |');
        sb.writeln('|------|-------|--------|------|-----|-------|-------|--------|----------|');
        String hm(int m) => '${m ~/ 60}h ${m % 60}m';
        String opt(Object? v, String unit) =>
            v == null ? '—' : '${(v as num).toStringAsFixed(0)}$unit';
        for (final r in sleep) {
          sb.writeln('| ${r['date']} | ${r['score']} | '
              '${hm(r['asleep_minutes'] as int)} | ${hm(r['deep_minutes'] as int)} | '
              '${hm(r['rem_minutes'] as int)} | ${hm(r['light_minutes'] as int)} | '
              '${hm(r['awake_minutes'] as int)} | ${opt(r['hr_avg'], ' bpm')} | '
              '${opt(r['spo2_avg'], '%')} |');
        }
        sb.writeln();
      }
    }

    // ── Step Logs ─────────────────────────────────────────────────────────────
    if (hasCat('stepLogs')) {
      final steps = await db.query('step_logs',
          where: 'date >= ? AND date <= ?',
          whereArgs: [from, to],
          orderBy: 'date DESC');
      if (steps.isNotEmpty) {
        sb.writeln('## Step Logs');
        final avgSteps = steps.fold(0, (s, r) => s + (r['steps'] as int)) / steps.length;
        sb.writeln('**Average:** ${avgSteps.round()} steps/day');
        sb.writeln();
        sb.writeln('| Date | Steps | Goal | % of Goal |');
        sb.writeln('|------|-------|------|-----------|');
        for (final s in steps) {
          final stepped = s['steps'] as int;
          final goal = s['goal'] as int;
          final pct = goal > 0 ? (stepped * 100 / goal).round() : 0;
          sb.writeln('| ${s['date']} | $stepped | $goal | $pct% |');
        }
        sb.writeln();
      }
    }

    // ── Body Measurements ─────────────────────────────────────────────────────
    if (hasCat('bodyMeasurements')) {
      final rows = await db.query('body_measurements',
          where: 'date >= ? AND date <= ?',
          whereArgs: [from, to],
          orderBy: 'date ASC, type ASC');
      if (rows.isNotEmpty) {
        sb.writeln('## Body Measurements (cm)');
        final byType = <String, List<Map<String, dynamic>>>{};
        for (final r in rows) {
          final t = r['type'] as String;
          byType.putIfAbsent(t, () => []).add(r);
        }
        for (final entry in byType.entries) {
          final type = entry.key;
          final history = entry.value;
          final first = (history.first['value_cm'] as num).toDouble();
          final last = (history.last['value_cm'] as num).toDouble();
          final diff = last - first;
          sb.writeln('### ${type[0].toUpperCase()}${type.substring(1)}');
          sb.writeln('**First:** ${first.toStringAsFixed(1)} cm (${history.first['date']}) → '
              '**Latest:** ${last.toStringAsFixed(1)} cm (${history.last['date']}) | '
              '**Change:** ${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)} cm');
          sb.writeln('| Date | Value (cm) |');
          sb.writeln('|------|-----------|');
          for (final r in history) {
            sb.writeln('| ${r['date']} | ${(r['value_cm'] as num).toStringAsFixed(1)} |');
          }
          sb.writeln();
        }
      }
    }

    // ── Achievements ──────────────────────────────────────────────────────────
    if (hasCat('achievements')) {
      final ach = await db.query('achievements_unlocked', orderBy: 'unlocked_at ASC');
      if (ach.isNotEmpty) {
        sb.writeln('## Achievements Unlocked');
        for (final a in ach) {
          sb.writeln('- ${a['achievement_id']} (${(a['unlocked_at'] as String).split('T').first})');
        }
        sb.writeln();
      }
    }

    // ── Suggested prompts ─────────────────────────────────────────────────────
    sb.writeln('---');
    sb.writeln('## Suggested Questions to Ask');
    sb.writeln('- What are my strength progress trends over the last few months?');
    sb.writeln('- Am I eating enough protein relative to my training volume?');
    sb.writeln('- Are there any patterns between my sleep/energy and workout performance?');
    sb.writeln('- Which muscle groups am I training most and least frequently?');
    sb.writeln('- What does my calorie intake look like on training vs. rest days?');
    sb.writeln('- How is my body weight trending relative to my nutrition?');
    sb.writeln('- Where should I focus to improve my overall fitness?');

    return sb.toString();
  }

  // ─── FULL BACKUP EXPORT ─────────────────────────────────────────────────────

  /// Exports user-created data as a single JSON string (schema_version: 3).
  /// Pass [categories] to limit which data types are included; null = all.
  Future<String> exportFullBackup({Set<String>? categories}) async {
    bool hasCat(String key) => categories == null || categories.contains(key);
    final db = await database;

    // Custom foods
    final customFoods = hasCat('customFoods')
        ? await db.query('foods', where: 'is_custom = ?', whereArgs: [1])
        : <Map<String, dynamic>>[];

    // Custom exercises
    final customExercises = hasCat('customExercises')
        ? await db.query('exercises', where: 'is_custom = ?', whereArgs: [1])
        : <Map<String, dynamic>>[];

    // Workout logs with full exercise/set data
    final workoutsJson = <Map<String, dynamic>>[];
    if (hasCat('workouts')) {
      final allLogs = await getWorkoutLogsForExport();
      final exerciseMap = <String, Exercise>{};
      for (final log in allLogs) {
        for (final exLog in log.exercises) {
          if (!exerciseMap.containsKey(exLog.exerciseId)) {
            final ex = await getExerciseById(exLog.exerciseId);
            if (ex != null) exerciseMap[exLog.exerciseId] = ex;
          }
        }
      }
      workoutsJson.addAll(allLogs.map((log) => {
      'date': log.date,
      'workout_name': log.workoutName,
      'completed': log.completed,
      if (log.durationSeconds != null) 'duration_seconds': log.durationSeconds,
      'exercises': log.exercises.map((exLog) {
        final ex = exerciseMap[exLog.exerciseId];
        return {
          'name': ex?.name ?? exLog.exerciseId,
          'muscle_group': ex?.muscleGroup ?? '',
          'equipment': ex?.equipment ?? '',
          'exercise_type': ex?.exerciseType ?? 'strength',
          if (exLog.notes != null && exLog.notes!.isNotEmpty) 'note': exLog.notes,
          'sets': exLog.sets.map((s) => {
            'set_number': s.setNumber,
            'is_completed': s.isCompleted,
            if (s.weight != null) 'weight_kg': s.weight,
            if (s.reps != null) 'reps': s.reps,
            if (s.durationSeconds != null) 'duration_seconds': s.durationSeconds,
            if (s.speed != null) 'speed': s.speed,
            if (s.incline != null) 'incline': s.incline,
            if (s.resistance != null) 'resistance': s.resistance,
            if (s.distanceKm != null) 'distance_km': s.distanceKm,
          }).toList(),
        };
      }).toList(),
      }).toList());
    }

    // Nutrition logs + entries (per-meal detail)
    final nutritionEntriesList = <Map<String, dynamic>>[];
    if (hasCat('nutrition')) {
      final nutritionLogRows = await db.query('nutrition_logs');
      for (final nlRow in nutritionLogRows) {
        final entries = await db.query('nutrition_entries',
            where: 'log_id = ?', whereArgs: [nlRow['id']]);
        for (final entry in entries) {
          nutritionEntriesList.add({...entry, 'date': nlRow['date']});
        }
      }
    }

    // Water logs
    final waterLogs = hasCat('water')
        ? await db.query('water_logs')
        : <Map<String, dynamic>>[];

    // Meal presets + items
    final presetsJson = <Map<String, dynamic>>[];
    if (hasCat('mealPresets')) {
      final presetRows = await db.query('meal_presets');
      for (final p in presetRows) {
        final items = await db.query('meal_preset_items',
            where: 'preset_id = ?', whereArgs: [p['id']]);
        presetsJson.add({...p, 'items': items.toList()});
      }
    }

    // Body weight logs
    final bodyWeightLogs = hasCat('bodyWeight')
        ? await db.query('body_weight_logs')
        : <Map<String, dynamic>>[];

    // Wellness logs
    final wellnessLogs = hasCat('wellness')
        ? await db.query('wellness_logs')
        : <Map<String, dynamic>>[];

    // Achievements
    final achievements = hasCat('achievements')
        ? await db.query('achievements_unlocked')
        : <Map<String, dynamic>>[];

    // Exercise PRs (include exercise name for portability)
    final prs = hasCat('personalRecords')
        ? await db.rawQuery('''
            SELECT ep.exercise_id, ep.best_1rm, ep.date, e.name AS exercise_name
            FROM exercise_prs ep
            LEFT JOIN exercises e ON e.id = ep.exercise_id
          ''')
        : <Map<String, dynamic>>[];

    // Nutrition goals
    final nutritionGoals = hasCat('nutritionGoals')
        ? await db.query('nutrition_goals')
        : <Map<String, dynamic>>[];

    // Day overrides
    final dayOverrides = hasCat('dayOverrides')
        ? await db.query('day_overrides')
        : <Map<String, dynamic>>[];

    // Quick start templates
    final quickStartTemplates = hasCat('quickStart')
        ? await db.query('quick_start_templates')
        : <Map<String, dynamic>>[];

    // Step logs
    final stepLogs = hasCat('stepLogs')
        ? await db.query('step_logs', orderBy: 'date ASC')
        : <Map<String, dynamic>>[];

    // Body measurements
    final bodyMeasurements = hasCat('bodyMeasurements')
        ? await db.query('body_measurements', orderBy: 'date ASC, type ASC')
        : <Map<String, dynamic>>[];

    // Sleep sessions (full rows, incl. stage/HR/SpO₂ series for a true restore)
    final sleepSessions = hasCat('sleep')
        ? await db.query('sleep_sessions', orderBy: 'date ASC')
        : <Map<String, dynamic>>[];

    // Samsung Health (watch) data — exported with workouts so the watch stats
    // travel with a backup.
    final shExercise = hasCat('workouts')
        ? await db.query('sh_exercise_sessions', orderBy: 'start_iso ASC')
        : <Map<String, dynamic>>[];
    final shExSamples = hasCat('workouts')
        ? await db.query('sh_exercise_samples')
        : <Map<String, dynamic>>[];
    final shExRoute = hasCat('workouts')
        ? await db.query('sh_exercise_route')
        : <Map<String, dynamic>>[];
    final shSleep = hasCat('sleep')
        ? await db.query('sh_sleep_sessions', orderBy: 'start_iso ASC')
        : <Map<String, dynamic>>[];
    final shSleepStages =
        hasCat('sleep') ? await db.query('sh_sleep_stages') : <Map<String, dynamic>>[];

    final payload = <String, dynamic>{
      'app': 'aawara',
      'schema_version': 3,
      'exported_at': DateTime.now().toIso8601String(),
      if (customFoods.isNotEmpty) 'custom_foods': customFoods.toList(),
      if (customExercises.isNotEmpty) 'custom_exercises': customExercises.toList(),
      if (workoutsJson.isNotEmpty) 'workout_logs': workoutsJson,
      if (bodyWeightLogs.isNotEmpty) 'body_weight_logs': bodyWeightLogs.toList(),
      if (nutritionEntriesList.isNotEmpty) 'nutrition_logs': nutritionEntriesList,
      if (waterLogs.isNotEmpty) 'water_logs': waterLogs.toList(),
      if (presetsJson.isNotEmpty) 'meal_presets': presetsJson,
      if (wellnessLogs.isNotEmpty) 'wellness_logs': wellnessLogs.toList(),
      if (achievements.isNotEmpty) 'achievements': achievements.toList(),
      if (prs.isNotEmpty) 'exercise_prs': prs.toList(),
      if (nutritionGoals.isNotEmpty) 'nutrition_goals': nutritionGoals.toList(),
      if (dayOverrides.isNotEmpty) 'day_overrides': dayOverrides.toList(),
      if (quickStartTemplates.isNotEmpty) 'quick_start_templates': quickStartTemplates.toList(),
      if (stepLogs.isNotEmpty) 'step_logs': stepLogs.toList(),
      if (bodyMeasurements.isNotEmpty) 'body_measurements': bodyMeasurements.toList(),
      if (sleepSessions.isNotEmpty) 'sleep_sessions': sleepSessions.toList(),
      if (shExercise.isNotEmpty) 'sh_exercise_sessions': shExercise.toList(),
      if (shExSamples.isNotEmpty) 'sh_exercise_samples': shExSamples.toList(),
      if (shExRoute.isNotEmpty) 'sh_exercise_route': shExRoute.toList(),
      if (shSleep.isNotEmpty) 'sh_sleep_sessions': shSleep.toList(),
      if (shSleepStages.isNotEmpty) 'sh_sleep_stages': shSleepStages.toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  // ─── FULL BACKUP IMPORT ─────────────────────────────────────────────────────

  /// Imports a full backup (schema_version: 3). Merges safely — existing rows
  /// are never overwritten. Returns counts per data type.
  Future<Map<String, ({int imported, int skipped})>> importFullBackup(String jsonStr) async {
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    final db = await database;
    const uuid = Uuid();

    final counts = <String, ({int imported, int skipped})>{};

    int imp = 0, skip = 0;

    // ── Custom exercises ──────────────────────────────────────────────────────
    imp = 0; skip = 0;
    final nameCache = <String, String>{};
    for (final ex in await getAllExercises()) {
      nameCache[ex.name.toLowerCase()] = ex.id;
    }
    final customExercises = (data['custom_exercises'] as List? ?? []).cast<Map<String, dynamic>>();
    for (final e in customExercises) {
      final name = (e['name'] as String? ?? '').trim();
      if (name.isEmpty) { skip++; continue; }
      if (nameCache.containsKey(name.toLowerCase())) { skip++; continue; }
      final newId = uuid.v4();
      await db.insert('exercises', {
        'id': newId,
        'name': name,
        'muscle_group': e['muscle_group'] as String? ?? 'Full Body',
        'equipment': e['equipment'] as String? ?? 'Other',
        'is_custom': 1,
        'exercise_type': e['exercise_type'] as String? ?? 'strength',
      });
      nameCache[name.toLowerCase()] = newId;
      imp++;
    }
    counts['custom_exercises'] = (imported: imp, skipped: skip);

    // ── Custom foods ─────────────────────────────────────────────────────────
    imp = 0; skip = 0;
    final customFoods = (data['custom_foods'] as List? ?? []).cast<Map<String, dynamic>>();
    for (final f in customFoods) {
      final id = f['id'] as String? ?? '';
      if (id.isEmpty) { skip++; continue; }
      final existing = await db.query('foods', where: 'id = ?', whereArgs: [id], limit: 1);
      if (existing.isNotEmpty) { skip++; continue; }
      // Also check by name to avoid name duplicates
      final byName = await db.query('foods',
          where: 'LOWER(name) = LOWER(?)', whereArgs: [f['name'] ?? ''], limit: 1);
      if (byName.isNotEmpty) { skip++; continue; }
      await db.insert('foods', {
        'id': id,
        'name': f['name'] as String? ?? '',
        'calories': (f['calories'] as num?)?.toDouble() ?? 0.0,
        'protein_g': (f['protein_g'] as num?)?.toDouble() ?? 0.0,
        'carbs_g': (f['carbs_g'] as num?)?.toDouble() ?? 0.0,
        'fat_g': (f['fat_g'] as num?)?.toDouble() ?? 0.0,
        'fiber_g': (f['fiber_g'] as num?)?.toDouble(),
        'serving_size': (f['serving_size'] as num?)?.toDouble() ?? 100.0,
        'serving_unit': f['serving_unit'] as String? ?? 'g',
        'is_custom': 1,
      });
      imp++;
    }
    counts['custom_foods'] = (imported: imp, skipped: skip);

    // ── Workout logs ─────────────────────────────────────────────────────────
    // Rebuild name cache after custom exercise import
    for (final ex in await getAllExercises()) {
      nameCache[ex.name.toLowerCase()] = ex.id;
    }
    final workouts = (data['workout_logs'] as List? ?? []).cast<Map<String, dynamic>>();
    imp = 0; skip = 0;
    for (final w in workouts) {
      final date = w['date'] as String? ?? '';
      if (date.isEmpty) { skip++; continue; }
      final existing = await db.query('workout_logs', where: 'date = ?', whereArgs: [date], limit: 1);
      if (existing.isNotEmpty) { skip++; continue; }
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
      final exercises = (w['exercises'] as List? ?? []).cast<Map<String, dynamic>>();
      for (int i = 0; i < exercises.length; i++) {
        final e = exercises[i];
        final name = (e['name'] as String? ?? '').trim();
        if (name.isEmpty) continue;
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
          'notes': e['note'] as String?,
        });
        final sets = (e['sets'] as List? ?? []).cast<Map<String, dynamic>>();
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
      imp++;
    }
    counts['workout_logs'] = (imported: imp, skipped: skip);

    // ── Body weight logs ─────────────────────────────────────────────────────
    imp = 0; skip = 0;
    final bwLogs = (data['body_weight_logs'] as List? ?? []).cast<Map<String, dynamic>>();
    for (final bw in bwLogs) {
      final date = bw['date'] as String? ?? '';
      final wkg = (bw['weight_kg'] as num?)?.toDouble();
      if (date.isEmpty || wkg == null) { skip++; continue; }
      final existing = await db.query('body_weight_logs',
          where: 'date = ?', whereArgs: [date], limit: 1);
      if (existing.isNotEmpty) { skip++; continue; }
      await db.insert('body_weight_logs', {
        'id': uuid.v4(),
        'date': date,
        'weight_kg': wkg,
        'notes': bw['notes'] as String?,
      });
      imp++;
    }
    counts['body_weight_logs'] = (imported: imp, skipped: skip);

    // ── Nutrition entries ────────────────────────────────────────────────────
    imp = 0; skip = 0;
    final nutritionEntries = (data['nutrition_logs'] as List? ?? []).cast<Map<String, dynamic>>();
    // Group by date
    final byDate = <String, List<Map<String, dynamic>>>{};
    for (final e in nutritionEntries) {
      final d = e['date'] as String? ?? '';
      if (d.isNotEmpty) (byDate[d] ??= []).add(e);
    }
    // Build food id lookup (existing + imported custom foods)
    final foodCache = <String, String>{}; // id → id (for existence check)
    final existingFoods = await db.query('foods', columns: ['id']);
    for (final f in existingFoods) {
      foodCache[f['id'] as String] = f['id'] as String;
    }
    for (final date in byDate.keys) {
      final logRows = await db.query('nutrition_logs',
          where: 'date = ?', whereArgs: [date], limit: 1);
      String logId;
      if (logRows.isNotEmpty) {
        logId = logRows.first['id'] as String;
        // Date already has a log — skip all entries for it to avoid duplicates
        skip += byDate[date]!.length;
        continue;
      }
      logId = uuid.v4();
      await db.insert('nutrition_logs', {'id': logId, 'date': date});
      for (final entry in byDate[date]!) {
        final foodId = entry['food_id'] as String? ?? '';
        if (foodId.isEmpty || !foodCache.containsKey(foodId)) { skip++; continue; }
        await db.insert('nutrition_entries', {
          'id': uuid.v4(),
          'log_id': logId,
          'food_id': foodId,
          'meal_type': entry['meal_type'] as String? ?? 'Snack',
          'quantity': (entry['quantity'] as num?)?.toDouble() ?? 1.0,
          'created_at': entry['created_at'] as String? ?? DateTime.now().toIso8601String(),
        });
        imp++;
      }
    }
    counts['nutrition_logs'] = (imported: imp, skipped: skip);

    // ── Water logs ───────────────────────────────────────────────────────────
    imp = 0; skip = 0;
    final waterLogs = (data['water_logs'] as List? ?? []).cast<Map<String, dynamic>>();
    for (final w in waterLogs) {
      final date = w['date'] as String? ?? '';
      if (date.isEmpty) { skip++; continue; }
      final existing = await db.query('water_logs', where: 'date = ?', whereArgs: [date], limit: 1);
      if (existing.isNotEmpty) { skip++; continue; }
      await db.insert('water_logs', {
        'date': date,
        'glasses_drunk': w['glasses_drunk'] as int? ?? 0,
        'target_glasses': w['target_glasses'] as int? ?? 8,
      });
      imp++;
    }
    counts['water_logs'] = (imported: imp, skipped: skip);

    // ── Meal presets ─────────────────────────────────────────────────────────
    imp = 0; skip = 0;
    final mealPresets = (data['meal_presets'] as List? ?? []).cast<Map<String, dynamic>>();
    for (final p in mealPresets) {
      final id = p['id'] as String? ?? '';
      if (id.isEmpty) { skip++; continue; }
      final existing = await db.query('meal_presets', where: 'id = ?', whereArgs: [id], limit: 1);
      if (existing.isNotEmpty) { skip++; continue; }
      await db.insert('meal_presets', {
        'id': id,
        'name': p['name'] as String? ?? 'Imported Preset',
        'created_at': p['created_at'] as String? ?? DateTime.now().toIso8601String(),
      });
      final items = (p['items'] as List? ?? []).cast<Map<String, dynamic>>();
      for (final item in items) {
        final foodId = item['food_id'] as String? ?? '';
        if (foodId.isEmpty || !foodCache.containsKey(foodId)) continue;
        await db.insert('meal_preset_items', {
          'id': item['id'] as String? ?? uuid.v4(),
          'preset_id': id,
          'food_id': foodId,
          'quantity': (item['quantity'] as num?)?.toDouble() ?? 1.0,
        });
      }
      imp++;
    }
    counts['meal_presets'] = (imported: imp, skipped: skip);

    // ── Wellness logs ────────────────────────────────────────────────────────
    imp = 0; skip = 0;
    final wellnessLogs = (data['wellness_logs'] as List? ?? []).cast<Map<String, dynamic>>();
    for (final w in wellnessLogs) {
      final date = w['date'] as String? ?? '';
      if (date.isEmpty) { skip++; continue; }
      final existing = await db.query('wellness_logs',
          where: 'date = ?', whereArgs: [date], limit: 1);
      if (existing.isNotEmpty) { skip++; continue; }
      await db.insert('wellness_logs', {
        'id': w['id'] as String? ?? uuid.v4(),
        'date': date,
        'sleep_hours': (w['sleep_hours'] as num?)?.toDouble() ?? 0.0,
        'energy': w['energy'] as int? ?? 3,
        'soreness': w['soreness'] as int? ?? 3,
        'notes': w['notes'] as String?,
      });
      imp++;
    }
    counts['wellness_logs'] = (imported: imp, skipped: skip);

    // ── Achievements ─────────────────────────────────────────────────────────
    imp = 0; skip = 0;
    final achievements = (data['achievements'] as List? ?? []).cast<Map<String, dynamic>>();
    for (final a in achievements) {
      final aid = a['achievement_id'] as String? ?? '';
      if (aid.isEmpty) { skip++; continue; }
      final existing = await db.query('achievements_unlocked',
          where: 'achievement_id = ?', whereArgs: [aid], limit: 1);
      if (existing.isNotEmpty) { skip++; continue; }
      await db.insert('achievements_unlocked', {
        'achievement_id': aid,
        'unlocked_at': a['unlocked_at'] as String? ?? DateTime.now().toIso8601String(),
      });
      imp++;
    }
    counts['achievements'] = (imported: imp, skipped: skip);

    // ── Exercise PRs ─────────────────────────────────────────────────────────
    imp = 0; skip = 0;
    final prs = (data['exercise_prs'] as List? ?? []).cast<Map<String, dynamic>>();
    for (final pr in prs) {
      final exName = (pr['exercise_name'] as String? ?? '').trim();
      if (exName.isEmpty) { skip++; continue; }
      final exId = nameCache[exName.toLowerCase()];
      if (exId == null) { skip++; continue; }
      final existing = await db.query('exercise_prs',
          where: 'exercise_id = ?', whereArgs: [exId], limit: 1);
      if (existing.isNotEmpty) { skip++; continue; }
      await db.insert('exercise_prs', {
        'exercise_id': exId,
        'best_1rm': (pr['best_1rm'] as num?)?.toDouble() ?? 0.0,
        'date': pr['date'] as String? ?? _fmt(DateTime.now()),
      });
      imp++;
    }
    counts['exercise_prs'] = (imported: imp, skipped: skip);

    // ── Nutrition goals ──────────────────────────────────────────────────────
    imp = 0; skip = 0;
    final existingGoals = await db.query('nutrition_goals', limit: 1);
    if (existingGoals.isEmpty) {
      final goals = (data['nutrition_goals'] as List? ?? []).cast<Map<String, dynamic>>();
      for (final g in goals) {
        await db.insert('nutrition_goals', {
          'calories': (g['calories'] as num?)?.toDouble() ?? 2000.0,
          'protein_g': (g['protein_g'] as num?)?.toDouble() ?? 150.0,
          'carbs_g': (g['carbs_g'] as num?)?.toDouble() ?? 200.0,
          'fat_g': (g['fat_g'] as num?)?.toDouble() ?? 65.0,
        });
        imp++;
      }
    } else {
      skip = (data['nutrition_goals'] as List? ?? []).length;
    }
    counts['nutrition_goals'] = (imported: imp, skipped: skip);

    // ── Day overrides ────────────────────────────────────────────────────────
    imp = 0; skip = 0;
    final dayOverrides = (data['day_overrides'] as List? ?? []).cast<Map<String, dynamic>>();
    for (final d in dayOverrides) {
      final date = d['date'] as String? ?? '';
      if (date.isEmpty) { skip++; continue; }
      final existing = await db.query('day_overrides', where: 'date = ?', whereArgs: [date], limit: 1);
      if (existing.isNotEmpty) { skip++; continue; }
      await db.insert('day_overrides', {
        'date': date,
        'exercise_ids_json': d['exercise_ids_json'] as String? ?? '[]',
      });
      imp++;
    }
    counts['day_overrides'] = (imported: imp, skipped: skip);

    // ── Quick start templates ────────────────────────────────────────────────
    imp = 0; skip = 0;
    final templates = (data['quick_start_templates'] as List? ?? []).cast<Map<String, dynamic>>();
    for (final t in templates) {
      final name = (t['name'] as String? ?? '').trim();
      if (name.isEmpty) { skip++; continue; }
      final existing = await db.query('quick_start_templates',
          where: 'name = ?', whereArgs: [name], limit: 1);
      if (existing.isNotEmpty) { skip++; continue; }
      await db.insert('quick_start_templates', {
        'name': name,
        'exercise_ids_json': t['exercise_ids_json'] as String? ?? '[]',
      });
      imp++;
    }
    counts['quick_start_templates'] = (imported: imp, skipped: skip);

    // ── Sleep sessions ───────────────────────────────────────────────────────
    imp = 0; skip = 0;
    final sleepSessions = (data['sleep_sessions'] as List? ?? []).cast<Map<String, dynamic>>();
    for (final s in sleepSessions) {
      final date = s['date'] as String? ?? '';
      if (date.isEmpty) { skip++; continue; }
      final existing = await db.query('sleep_sessions',
          where: 'date = ?', whereArgs: [date], limit: 1);
      if (existing.isNotEmpty) { skip++; continue; }
      // Round-trip via the model so only known columns are written.
      await db.insert('sleep_sessions', SleepSession.fromMap(s).toMap());
      imp++;
    }
    counts['sleep_sessions'] = (imported: imp, skipped: skip);

    // Samsung Health (watch) data. Parents dedupe by uid; children are cleared
    // for the imported uids then re-inserted, so re-importing is idempotent.
    Future<void> importSamsung(String parentTable, String parentList,
        List<({String childTable, String childList})> children) async {
      var pi = 0, ps = 0;
      final parents =
          (data[parentList] as List? ?? []).cast<Map<String, dynamic>>();
      final uids = <String>{};
      for (final row in parents) {
        final uid = row['uid'] as String?;
        if (uid == null) {
          ps++;
          continue;
        }
        uids.add(uid);
        final n = await db.insert(parentTable, Map<String, dynamic>.from(row),
            conflictAlgorithm: ConflictAlgorithm.ignore);
        if (n > 0) {
          pi++;
        } else {
          ps++;
        }
      }
      for (final c in children) {
        for (final uid in uids) {
          await db.delete(c.childTable, where: 'uid = ?', whereArgs: [uid]);
        }
        for (final row in (data[c.childList] as List? ?? [])
            .cast<Map<String, dynamic>>()) {
          if (uids.contains(row['uid'])) {
            await db.insert(c.childTable, Map<String, dynamic>.from(row));
          }
        }
      }
      counts[parentTable] = (imported: pi, skipped: ps);
    }

    await importSamsung('sh_exercise_sessions', 'sh_exercise_sessions', [
      (childTable: 'sh_exercise_samples', childList: 'sh_exercise_samples'),
      (childTable: 'sh_exercise_route', childList: 'sh_exercise_route'),
    ]);
    await importSamsung('sh_sleep_sessions', 'sh_sleep_sessions', [
      (childTable: 'sh_sleep_stages', childList: 'sh_sleep_stages'),
    ]);

    return counts;
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

  /// Sets only the sleep hours for [date], preserving energy/soreness/notes if a
  /// row exists (used to auto-fill from Health Connect). Creates a row with
  /// neutral energy/soreness defaults otherwise.
  Future<void> setWellnessSleepHours(String date, double sleepHours) async {
    final db = await database;
    final existing = await db.query('wellness_logs',
        where: 'date = ?', whereArgs: [date], limit: 1);
    if (existing.isNotEmpty) {
      await db.update('wellness_logs', {'sleep_hours': sleepHours},
          where: 'date = ?', whereArgs: [date]);
    } else {
      await db.insert('wellness_logs', {
        'id': const Uuid().v4(),
        'date': date,
        'sleep_hours': sleepHours,
        'energy': 3,
        'soreness': 2,
        'notes': null,
      });
    }
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

  // ─── NUTRITION ───────────────────────────────────────────────────────────────

  Future<String> _getOrCreateNutritionLog(String date) async {
    final db = await database;
    final existing = await db.query('nutrition_logs',
        where: 'date = ?', whereArgs: [date], limit: 1);
    if (existing.isNotEmpty) return existing.first['id'] as String;
    const uuid = Uuid();
    final id = uuid.v4();
    await db.insert('nutrition_logs', {'id': id, 'date': date});
    return id;
  }

  // Returns aggregated weekly training and nutrition metrics for the
  // [fromDate, toDate] inclusive range (both 'YYYY-MM-DD').
  Future<WeeklyInsights> getWeeklyInsights({
    required String fromDate,
    required String toDate,
  }) async {
    final db = await database;

    // Sets per muscle group from completed sessions in range
    final muscleRows = await db.rawQuery('''
      SELECT e.muscle_group AS muscle_group, COUNT(sl.id) AS set_count
      FROM set_logs sl
      INNER JOIN exercise_logs el ON el.id = sl.exercise_log_id
      INNER JOIN workout_logs wl ON wl.id = el.workout_log_id
      INNER JOIN exercises e ON e.id = el.exercise_id
      WHERE wl.date >= ? AND wl.date <= ?
        AND wl.completed = 1 AND sl.is_completed = 1
      GROUP BY e.muscle_group
    ''', [fromDate, toDate]);
    final setsPerMuscleGroup = <String, int>{};
    for (final r in muscleRows) {
      final g = r['muscle_group'] as String?;
      if (g == null || g.isEmpty) continue;
      setsPerMuscleGroup[g] = (r['set_count'] as int);
    }

    final trainingDays = Sqflite.firstIntValue(await db.rawQuery('''
      SELECT COUNT(DISTINCT date) FROM workout_logs
      WHERE date >= ? AND date <= ? AND completed = 1
    ''', [fromDate, toDate])) ?? 0;

    // Average daily nutrition. Calculated using per-100g formula consistent
    // with NutritionEntry: kcal_total = (food.calories × ne.quantity × food.serving_size / 100)
    final nutRows = await db.rawQuery('''
      SELECT nl.date,
             SUM(f.calories * ne.quantity * f.serving_size / 100.0) AS cal,
             SUM(f.protein_g * ne.quantity * f.serving_size / 100.0) AS prot
      FROM nutrition_logs nl
      INNER JOIN nutrition_entries ne ON ne.log_id = nl.id
      INNER JOIN foods f ON f.id = ne.food_id
      WHERE nl.date >= ? AND nl.date <= ?
      GROUP BY nl.date
    ''', [fromDate, toDate]);
    double totalCal = 0, totalPro = 0;
    for (final r in nutRows) {
      totalCal += (r['cal'] as num?)?.toDouble() ?? 0;
      totalPro += (r['prot'] as num?)?.toDouble() ?? 0;
    }
    final nutDays = nutRows.length;

    // Average daily water across days that had any entry
    final waterRows = await db.query(
      'water_logs',
      where: 'date >= ? AND date <= ?',
      whereArgs: [fromDate, toDate],
    );
    double totalGlasses = 0;
    for (final r in waterRows) {
      totalGlasses += (r['glasses_drunk'] as num?)?.toDouble() ?? 0;
    }
    final waterDays = waterRows.length;

    // Most recent body weight within the range
    final bwRows = await db.query(
      'body_weight_logs',
      where: 'date >= ? AND date <= ?',
      whereArgs: [fromDate, toDate],
      orderBy: 'date DESC',
      limit: 1,
    );
    final avgWeightKg = bwRows.isEmpty
        ? null
        : (bwRows.first['weight_kg'] as num).toDouble();

    final daysInRange = DateTime.parse(toDate)
            .difference(DateTime.parse(fromDate))
            .inDays +
        1;

    return WeeklyInsights(
      setsPerMuscleGroup: setsPerMuscleGroup,
      trainingDays: trainingDays,
      avgProteinG: nutDays > 0 ? totalPro / nutDays : 0,
      avgCalories: nutDays > 0 ? totalCal / nutDays : 0,
      avgGlassesWater: waterDays > 0 ? totalGlasses / waterDays : 0,
      avgWeightKg: avgWeightKg,
      daysInRange: daysInRange,
    );
  }

  Future<List<Food>> searchFoods(String query) async {
    final db = await database;
    final maps = await db.query(
      'foods',
      where: 'name LIKE ?',
      whereArgs: ['%$query%'],
      orderBy: 'is_custom DESC, name ASC',
      limit: 50,
    );
    return maps.map(Food.fromMap).toList();
  }

  // Returns the most recently logged foods (unique), most-recent first.
  // Used to power the "Recent" chips row in the food search sheet.
  Future<List<Food>> getRecentlyLoggedFoods({int limit = 15}) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT f.* FROM foods f
      INNER JOIN (
        SELECT food_id, MAX(created_at) AS latest_at
        FROM nutrition_entries
        GROUP BY food_id
      ) recent ON recent.food_id = f.id
      ORDER BY recent.latest_at DESC
      LIMIT ?
    ''', [limit]);
    return rows.map(Food.fromMap).toList();
  }

  // Copies all food entries from one date+meal into another date+meal.
  // Used by the "Copy from yesterday" action. Returns the number of entries copied.
  Future<int> copyMealEntries({
    required String fromDate,
    required String toDate,
    required String mealType,
  }) async {
    final db = await database;
    final fromLogId = await _getOrCreateNutritionLog(fromDate);
    final toLogId = await _getOrCreateNutritionLog(toDate);
    final source = await db.query(
      'nutrition_entries',
      where: 'log_id = ? AND meal_type = ?',
      whereArgs: [fromLogId, mealType],
    );
    if (source.isEmpty) return 0;
    final uuid = const Uuid();
    final now = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (final row in source) {
      batch.insert('nutrition_entries', {
        'id': uuid.v4(),
        'log_id': toLogId,
        'food_id': row['food_id'],
        'meal_type': mealType,
        'quantity': row['quantity'],
        'created_at': now,
      });
    }
    await batch.commit(noResult: true);
    return source.length;
  }

  Future<NutritionTotals> getFoodsForDate(String date) async {
    final logId = await _getOrCreateNutritionLog(date);
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT ne.id as entry_id, ne.log_id, ne.meal_type, ne.quantity, ne.created_at,
             f.id as food_id, f.name, f.calories, f.protein_g, f.carbs_g,
             f.fat_g, f.fiber_g, f.serving_size, f.serving_unit, f.is_custom
      FROM nutrition_entries ne
      INNER JOIN foods f ON ne.food_id = f.id
      WHERE ne.log_id = ?
      ORDER BY ne.created_at ASC
    ''', [logId]);

    final entries = rows.map((r) {
      final food = Food.fromMap({
        'id': r['food_id'],
        'name': r['name'],
        'calories': r['calories'],
        'protein_g': r['protein_g'],
        'carbs_g': r['carbs_g'],
        'fat_g': r['fat_g'],
        'fiber_g': r['fiber_g'],
        'serving_size': r['serving_size'],
        'serving_unit': r['serving_unit'],
        'is_custom': r['is_custom'],
      });
      return NutritionEntry(
        id: r['entry_id'] as String,
        logId: r['log_id'] as String,
        food: food,
        mealType: r['meal_type'] as String,
        quantity: (r['quantity'] as num).toDouble(),
        createdAt: r['created_at'] as String,
      );
    }).toList();

    double cal = 0, prot = 0, carbs = 0, fat = 0, fiber = 0;
    for (final e in entries) {
      cal += e.calories;
      prot += e.proteinG;
      carbs += e.carbsG;
      fat += e.fatG;
      fiber += e.fiberG;
    }
    return NutritionTotals(
      calories: cal,
      proteinG: prot,
      carbsG: carbs,
      fatG: fat,
      fiberG: fiber,
      entries: entries,
    );
  }

  Future<NutritionEntry> addNutritionEntry(
    String date,
    String foodId,
    String mealType,
    double quantity,
  ) async {
    final logId = await _getOrCreateNutritionLog(date);
    const uuid = Uuid();
    final id = uuid.v4();
    final now = DateTime.now().toIso8601String();
    final db = await database;
    await db.insert('nutrition_entries', {
      'id': id,
      'log_id': logId,
      'food_id': foodId,
      'meal_type': mealType,
      'quantity': quantity,
      'created_at': now,
    });
    final foodRows =
        await db.query('foods', where: 'id = ?', whereArgs: [foodId], limit: 1);
    final food = Food.fromMap(foodRows.first);
    return NutritionEntry(
      id: id,
      logId: logId,
      food: food,
      mealType: mealType,
      quantity: quantity,
      createdAt: now,
    );
  }

  Future<void> deleteNutritionEntry(String entryId) async {
    final db = await database;
    await db.delete('nutrition_entries', where: 'id = ?', whereArgs: [entryId]);
  }

  Future<void> deleteMealEntries(String date, String mealType) async {
    final db = await database;
    final logId = await _getOrCreateNutritionLog(date);
    await db.delete(
      'nutrition_entries',
      where: 'log_id = ? AND meal_type = ?',
      whereArgs: [logId, mealType],
    );
  }

  Future<void> updateNutritionEntry(
    String entryId, {
    double? quantity,
    String? mealType,
  }) async {
    final db = await database;
    final updates = <String, dynamic>{};
    if (quantity != null) updates['quantity'] = quantity;
    if (mealType != null) updates['meal_type'] = mealType;
    if (updates.isEmpty) return;
    await db.update('nutrition_entries', updates,
        where: 'id = ?', whereArgs: [entryId]);
  }

  Future<Map<String, String>> getMealTemplates() async {
    final db = await database;
    try {
      final rows = await db.query('meal_templates');
      return {for (final r in rows) r['meal_key'] as String: r['name'] as String};
    } catch (_) {
      return {};
    }
  }

  Future<void> saveMealTemplate(String mealKey, String name) async {
    final db = await database;
    await db.insert(
      'meal_templates',
      {'meal_key': mealKey, 'name': name},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<String>> getMealSlotKeys() async {
    final db = await database;
    try {
      final rows = await db.query('meal_slots', orderBy: 'display_order ASC');
      if (rows.isEmpty) return ['meal_1', 'meal_2', 'meal_3', 'meal_4', 'meal_5'];
      return rows.map((r) => r['meal_key'] as String).toList();
    } catch (_) {
      return ['meal_1', 'meal_2', 'meal_3', 'meal_4', 'meal_5'];
    }
  }

  // Creates a new meal slot with an auto-generated key and saves its name.
  // Returns the new meal key.
  Future<String> createMealSlot(String name) async {
    final db = await database;
    final maxRow = await db.rawQuery('SELECT MAX(display_order) as m FROM meal_slots');
    final maxOrder = (maxRow.first['m'] as int?) ?? 5;
    final newOrder = maxOrder + 1;
    final mealKey = 'meal_$newOrder';
    await db.insert('meal_slots', {'meal_key': mealKey, 'display_order': newOrder},
        conflictAlgorithm: ConflictAlgorithm.replace);
    await saveMealTemplate(mealKey, name);
    return mealKey;
  }

  // Deletes a meal slot and all its food log entries across all dates.
  Future<void> deleteMealSlot(String mealKey) async {
    final db = await database;
    await db.rawDelete('DELETE FROM nutrition_entries WHERE meal_type = ?', [mealKey]);
    await db.delete('meal_templates', where: 'meal_key = ?', whereArgs: [mealKey]);
    await db.delete('meal_slots', where: 'meal_key = ?', whereArgs: [mealKey]);
  }

  Future<NutritionTotals> getTodayTotals(String date) => getFoodsForDate(date);

  Future<NutritionGoals?> getNutritionGoals() async {
    final db = await database;
    final rows = await db.query('nutrition_goals', limit: 1);
    if (rows.isEmpty) return null;
    return NutritionGoals.fromMap(rows.first);
  }

  Future<void> saveNutritionGoals(NutritionGoals goals) async {
    final db = await database;
    await db.insert(
      'nutrition_goals',
      {...goals.toMap(), 'id': 1},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Food> createCustomFood(Food food) async {
    final db = await database;
    await db.insert('foods', food.toMap());
    return food;
  }

  // Update a custom food. Only foods with is_custom = 1 can be updated.
  Future<void> updateCustomFood(Food food) async {
    final db = await database;
    await db.update(
      'foods',
      food.toMap(),
      where: 'id = ? AND is_custom = 1',
      whereArgs: [food.id],
    );
  }

  // Delete a custom food. Only foods with is_custom = 1 can be deleted.
  // Also removes any logged nutrition entries that reference this food.
  Future<void> deleteCustomFood(String foodId) async {
    final db = await database;
    await db.delete(
      'nutrition_entries',
      where: 'food_id = ?',
      whereArgs: [foodId],
    );
    await db.delete(
      'foods',
      where: 'id = ? AND is_custom = 1',
      whereArgs: [foodId],
    );
  }

  Future<Food?> getFoodByExactName(String name) async {
    final db = await database;
    final rows = await db.query(
      'foods',
      where: 'LOWER(name) = LOWER(?)',
      whereArgs: [name.trim()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Food.fromMap(rows.first);
  }

  Future<Food?> getFoodById(String id) async {
    final db = await database;
    final rows = await db.query('foods', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Food.fromMap(rows.first);
  }

  Future<Food?> getFoodByBarcode(String barcode) async {
    final db = await database;
    final rows = await db.query('foods', where: 'barcode = ?', whereArgs: [barcode], limit: 1);
    if (rows.isEmpty) return null;
    return Food.fromMap(rows.first);
  }

  Future<Food> upsertFoodFromApi(Food food) async {
    final db = await database;
    if (food.barcode != null) {
      final existing = await getFoodByBarcode(food.barcode!);
      if (existing != null) {
        final updated = food.copyWith(id: existing.id);
        await db.update('foods', updated.toMap(), where: 'id = ?', whereArgs: [existing.id]);
        return updated;
      }
    }
    await db.insert('foods', food.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    return food;
  }

  Future<ScanCacheEntry?> getScanCache(String barcode) async {
    final db = await database;
    final rows = await db.query('scan_cache', where: 'barcode = ?', whereArgs: [barcode], limit: 1);
    if (rows.isEmpty) return null;
    return ScanCacheEntry.fromMap(rows.first);
  }

  Future<void> upsertScanCache(ScanCacheEntry entry) async {
    final db = await database;
    await db.insert('scan_cache', entry.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> incrementScanCount(String barcode) async {
    final db = await database;
    await db.execute(
      'UPDATE scan_cache SET scan_count = scan_count + 1, last_scanned_at = ? WHERE barcode = ?',
      [DateTime.now().toIso8601String(), barcode],
    );
  }

  Future<List<String>> getFailedBarcodes() async {
    final db = await database;
    final rows = await db.query('scan_cache', columns: ['barcode'], where: "status != 'found'");
    return rows.map((r) => r['barcode'] as String).toList();
  }

  // ── Water Logs ────────────────────────────────────────────────────────────────

  Future<WaterLog> getWaterLog(String date) async {
    final db = await database;
    final rows = await db.query('water_logs',
        where: 'date = ?', whereArgs: [date], limit: 1);
    if (rows.isNotEmpty) return WaterLog.fromMap(rows.first);
    return WaterLog(date: date, glassesDrunk: 0, targetGlasses: 8);
  }

  Future<void> setWaterGlasses(String date, int glasses,
      {int targetGlasses = 8}) async {
    final db = await database;
    await db.insert(
      'water_logs',
      {'date': date, 'glasses_drunk': glasses, 'target_glasses': targetGlasses},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateWaterTarget(String date, int target) async {
    final db = await database;
    final existing = await db.query('water_logs',
        where: 'date = ?', whereArgs: [date], limit: 1);
    final glasses =
        existing.isNotEmpty ? existing.first['glasses_drunk'] as int : 0;
    await db.insert(
      'water_logs',
      {'date': date, 'glasses_drunk': glasses, 'target_glasses': target},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ── Meal Presets ──────────────────────────────────────────────────────────────

  Future<List<MealPreset>> getMealPresets() async {
    final db = await database;
    final presets = await db.query('meal_presets', orderBy: 'created_at DESC');
    final result = <MealPreset>[];
    for (final p in presets) {
      final id = p['id'] as String;
      final itemRows = await db.rawQuery('''
        SELECT mpi.id, mpi.preset_id, mpi.quantity,
               f.id as food_id, f.name, f.calories, f.protein_g, f.carbs_g,
               f.fat_g, f.fiber_g, f.serving_size, f.serving_unit, f.is_custom
        FROM meal_preset_items mpi
        INNER JOIN foods f ON mpi.food_id = f.id
        WHERE mpi.preset_id = ?
      ''', [id]);
      final items = itemRows.map((r) {
        final food = Food.fromMap({
          'id': r['food_id'],
          'name': r['name'],
          'calories': r['calories'],
          'protein_g': r['protein_g'],
          'carbs_g': r['carbs_g'],
          'fat_g': r['fat_g'],
          'fiber_g': r['fiber_g'],
          'serving_size': r['serving_size'],
          'serving_unit': r['serving_unit'],
          'is_custom': r['is_custom'],
        });
        return MealPresetItem(
          id: r['id'] as String,
          presetId: id,
          food: food,
          quantity: (r['quantity'] as num).toDouble(),
        );
      }).toList();
      result.add(MealPreset(
        id: id,
        name: p['name'] as String,
        createdAt: p['created_at'] as String,
        items: items,
      ));
    }
    return result;
  }

  Future<MealPreset> createMealPreset(
      String name, List<NutritionEntry> entries) async {
    final db = await database;
    const uuid = Uuid();
    final id = uuid.v4();
    final now = DateTime.now().toIso8601String();
    await db.insert('meal_presets', {'id': id, 'name': name, 'created_at': now});
    for (final e in entries) {
      await db.insert('meal_preset_items', {
        'id': uuid.v4(),
        'preset_id': id,
        'food_id': e.food.id,
        'quantity': e.quantity,
      });
    }
    return (await getMealPresets()).firstWhere((p) => p.id == id);
  }

  Future<void> logMealPreset(
      String presetId, String date, String mealType) async {
    final db = await database;
    final itemRows = await db.query('meal_preset_items',
        where: 'preset_id = ?', whereArgs: [presetId]);
    for (final row in itemRows) {
      await addNutritionEntry(
        date,
        row['food_id'] as String,
        mealType,
        (row['quantity'] as num).toDouble(),
      );
    }
  }

  Future<void> deleteMealPreset(String id) async {
    final db = await database;
    await db.delete('meal_preset_items',
        where: 'preset_id = ?', whereArgs: [id]);
    await db.delete('meal_presets', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<DailyNutritionSummary>> getNutritionHistory(
      String fromDate, String toDate) async {
    final db = await database;
    // Macros scale by (quantity × serving_size / 100) — same as the per-entry
    // NutritionEntry getters. Omitting serving_size here used to inflate the
    // Progress > Nutrition totals vs. the Nutrition screen.
    final rows = await db.rawQuery('''
      SELECT nl.date,
             SUM(ne.quantity * f.serving_size / 100.0 * f.calories) as calories,
             SUM(ne.quantity * f.serving_size / 100.0 * f.protein_g) as protein_g,
             SUM(ne.quantity * f.serving_size / 100.0 * f.carbs_g) as carbs_g,
             SUM(ne.quantity * f.serving_size / 100.0 * f.fat_g) as fat_g
      FROM nutrition_logs nl
      INNER JOIN nutrition_entries ne ON ne.log_id = nl.id
      INNER JOIN foods f ON ne.food_id = f.id
      WHERE nl.date >= ? AND nl.date <= ?
      GROUP BY nl.date
      ORDER BY nl.date ASC
    ''', [fromDate, toDate]);
    return rows
        .map((r) => DailyNutritionSummary.fromMap(Map<String, dynamic>.from(r)))
        .toList();
  }

  Future<void> upsertStepLog(String date, int steps, int goal) async {
    final db = await database;
    await db.rawInsert('''
      INSERT INTO step_logs (date, steps, goal, updated_at)
      VALUES (?, ?, ?, datetime('now'))
      ON CONFLICT(date) DO UPDATE SET
        steps = excluded.steps,
        goal = excluded.goal,
        updated_at = excluded.updated_at
    ''', [date, steps, goal]);
  }

  Future<Map<String, dynamic>?> getStepLog(String date) async {
    final db = await database;
    final rows =
        await db.query('step_logs', where: 'date = ?', whereArgs: [date]);
    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
  }

  Future<List<Map<String, dynamic>>> getStepHistory(int days) async {
    final db = await database;
    final from = DateTime.now().subtract(Duration(days: days - 1));
    final fromStr =
        '${from.year}-${from.month.toString().padLeft(2, '0')}-${from.day.toString().padLeft(2, '0')}';
    final rows = await db.query('step_logs',
        where: 'date >= ?',
        whereArgs: [fromStr],
        orderBy: 'date ASC');
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  // ─── SAMSUNG HEALTH (watch) ─────────────────────────────────────────────────

  Future<void> upsertSamsungExercise(SamsungExercise e) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert(
        'sh_exercise_sessions',
        {
          'uid': e.uid,
          'exercise_type': e.exerciseType,
          'custom_title': e.customTitle,
          'start_iso': e.start.toUtc().toIso8601String(),
          'end_iso': e.end.toUtc().toIso8601String(),
          'duration_seconds': e.durationSeconds,
          'calories': e.calories,
          'distance': e.distance,
          'count': e.count,
          'mean_hr': e.meanHeartRate,
          'max_hr': e.maxHeartRate,
          'min_hr': e.minHeartRate,
          'mean_speed': e.meanSpeed,
          'max_speed': e.maxSpeed,
          'vo2max': e.vo2Max,
          'raw_json': e.rawJson,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.delete('sh_exercise_samples',
          where: 'uid = ?', whereArgs: [e.uid]);
      await txn.delete('sh_exercise_route', where: 'uid = ?', whereArgs: [e.uid]);
      final batch = txn.batch();
      for (final s in e.samples) {
        batch.insert('sh_exercise_samples', {
          'uid': e.uid,
          't_iso': s.t.toUtc().toIso8601String(),
          'hr': s.hr,
          'cadence': s.cadence,
          'power': s.power,
          'speed': s.speed,
        });
      }
      for (final r in e.route) {
        batch.insert('sh_exercise_route', {
          'uid': e.uid,
          't_iso': r.t.toUtc().toIso8601String(),
          'lat': r.lat,
          'lng': r.lng,
          'alt': r.alt,
        });
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> upsertSamsungSleep(SamsungSleep s) async {
    final db = await database;
    final date = s.end.toLocal();
    await db.transaction((txn) async {
      await txn.insert(
        'sh_sleep_sessions',
        {
          'uid': s.uid,
          'date':
              '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
          'score': s.score,
          'start_iso': s.start.toUtc().toIso8601String(),
          'end_iso': s.end.toUtc().toIso8601String(),
          'duration_seconds': s.durationSeconds,
          'raw_json': s.rawJson,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.delete('sh_sleep_stages', where: 'uid = ?', whereArgs: [s.uid]);
      final batch = txn.batch();
      for (final st in s.stages) {
        batch.insert('sh_sleep_stages', {
          'uid': s.uid,
          'stage': st.stage,
          'start_iso': st.start.toUtc().toIso8601String(),
          'end_iso': st.end.toUtc().toIso8601String(),
        });
      }
      await batch.commit(noResult: true);
    });
  }

  /// The watch exercise session linked to a logged workout (for the detail view).
  Future<Map<String, dynamic>?> getSamsungExerciseForWorkout(
      String workoutId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT s.* FROM sh_exercise_sessions s
      JOIN workout_logs w ON w.samsung_exercise_uid = s.uid
      WHERE w.id = ? LIMIT 1
    ''', [workoutId]);
    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
  }

  /// ALL watch sessions that belong to a logged workout (for the carousel) —
  /// every session overlapping the workout window (with a buffer to catch
  /// back-to-back sessions like weights → treadmill), or, for a historical
  /// workout with no start time, all sessions on the same day.
  Future<List<Map<String, dynamic>>> getWatchSessionsForWorkout(
      String workoutId) async {
    final db = await database;
    final wr = await db.query('workout_logs',
        columns: ['started_at', 'date', 'duration_seconds'],
        where: 'id = ?',
        whereArgs: [workoutId],
        limit: 1);
    if (wr.isEmpty) return [];
    final w = wr.first;
    final startedAt = w['started_at'] as String?;
    if (startedAt != null) {
      final wStart = DateTime.parse(startedAt).toUtc();
      final wEnd =
          wStart.add(Duration(seconds: (w['duration_seconds'] as int?) ?? 0));
      final from = wStart.subtract(const Duration(minutes: 30));
      final to = wEnd.add(const Duration(minutes: 120));
      return db.query('sh_exercise_sessions',
          where: 'start_iso < ? AND end_iso > ?',
          whereArgs: [to.toIso8601String(), from.toIso8601String()],
          orderBy: 'start_iso ASC');
    }
    // Historical fallback: same local date.
    final wd = w['date'] as String;
    final key = wd.length >= 10 ? wd.substring(0, 10) : wd;
    final all =
        await db.query('sh_exercise_sessions', orderBy: 'start_iso ASC');
    return all.where((s) {
      final d = DateTime.parse(s['start_iso'] as String).toLocal();
      final sd =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      return sd == key;
    }).toList();
  }

  /// HR samples (t, hr) for a watch session, ordered by time.
  Future<List<({DateTime t, double hr})>> getSamsungExerciseSamples(
      String uid) async {
    final db = await database;
    final rows = await db.query('sh_exercise_samples',
        columns: ['t_iso', 'hr'],
        where: 'uid = ? AND hr IS NOT NULL',
        whereArgs: [uid],
        orderBy: 't_iso ASC');
    return [
      for (final r in rows)
        (t: DateTime.parse(r['t_iso'] as String), hr: (r['hr'] as num).toDouble())
    ];
  }

  /// Watch sessions whose dense HEART_RATE series hasn't been pulled yet, with
  /// their time window so the sync can fetch HR for exactly that span.
  Future<List<({String uid, DateTime start, DateTime end})>>
      sessionsNeedingHrSeries() async {
    final db = await database;
    final rows = await db.query('sh_exercise_sessions',
        columns: ['uid', 'start_iso', 'end_iso'],
        where: 'hr_series_checked = 0');
    return [
      for (final r in rows)
        (
          uid: r['uid'] as String,
          start: DateTime.parse(r['start_iso'] as String),
          end: DateTime.parse(r['end_iso'] as String),
        )
    ];
  }

  /// Stores a session's HEART_RATE series as its samples when it's denser than
  /// whatever the in-session exercise log gave us, then marks the session
  /// checked (so we never re-pull, even if it genuinely had no HR).
  Future<void> applyHrSeries(
      String uid, List<({DateTime t, double hr})> series) async {
    final db = await database;
    final points = [for (final s in series) if (s.hr > 0) s];
    await db.transaction((txn) async {
      final existing = Sqflite.firstIntValue(await txn.rawQuery(
              'SELECT COUNT(*) FROM sh_exercise_samples WHERE uid = ? AND hr IS NOT NULL',
              [uid])) ??
          0;
      if (points.length > existing) {
        await txn.delete('sh_exercise_samples', where: 'uid = ?', whereArgs: [uid]);
        final batch = txn.batch();
        for (final p in points) {
          batch.insert('sh_exercise_samples',
              {'uid': uid, 't_iso': p.t.toUtc().toIso8601String(), 'hr': p.hr});
        }
        await batch.commit(noResult: true);
      }
      await txn.update('sh_exercise_sessions', {'hr_series_checked': 1},
          where: 'uid = ?', whereArgs: [uid]);
    });
  }

  static String _watchSessionName(Map<String, dynamic> ex) {
    final t = (ex['custom_title'] as String?) ?? (ex['exercise_type'] as String?);
    if (t == null || t.isEmpty) return 'Watch workout';
    return t
        .split('_')
        .map((w) => w.isEmpty ? w : w[0] + w.substring(1).toLowerCase())
        .join(' ');
  }

  /// All watch sessions for a logged workout (weights, treadmill, …), each with
  /// its name + HR + zones — exported inline so every session's HR travels with
  /// the workout data. Empty when none belong to the workout.
  Future<List<Map<String, dynamic>>> getWatchSummariesForWorkout(
      String workoutId) async {
    final sessions = await getWatchSessionsForWorkout(workoutId);
    final out = <Map<String, dynamic>>[];
    for (final ex in sessions) {
      final samples = await getSamsungExerciseSamples(ex['uid'] as String);
      final z = samples.isEmpty
          ? null
          : heartRateZones([for (final s in samples) HrSample(s.t, s.hr)]);
      out.add({
        'source': 'samsung_health',
        'name': _watchSessionName(ex),
        if (ex['exercise_type'] != null) 'exercise_type': ex['exercise_type'],
        if (ex['duration_seconds'] != null)
          'duration_seconds': ex['duration_seconds'],
        if (ex['calories'] != null) 'calories': ex['calories'],
        if (ex['distance'] != null) 'distance_m': ex['distance'],
        if (ex['mean_hr'] != null) 'hr_avg': (ex['mean_hr'] as num).round(),
        if (ex['max_hr'] != null) 'hr_max': (ex['max_hr'] as num).round(),
        if (ex['min_hr'] != null) 'hr_min': (ex['min_hr'] as num).round(),
        if (ex['vo2max'] != null) 'vo2max': ex['vo2max'],
        if (z != null)
          'hr_zone_seconds': {
            'warm_up': z.warmUpSeconds,
            'fat_burn': z.fatBurnSeconds,
            'cardio': z.cardioSeconds,
            'peak': z.peakSeconds,
          },
      });
    }
    return out;
  }

  Future<void> setWorkoutStartedAt(String workoutId, DateTime startedAt) async {
    final db = await database;
    await db.update('workout_logs',
        {'started_at': startedAt.toUtc().toIso8601String()},
        where: 'id = ?', whereArgs: [workoutId]);
  }

  /// Links logged workouts to overlapping watch sessions. Returns # newly linked.
  Future<int> linkSamsungToWorkouts() async {
    final db = await database;
    final workouts = await db.query('workout_logs',
        where:
            "started_at IS NOT NULL AND (samsung_exercise_uid IS NULL OR samsung_exercise_uid = '')");
    var linked = 0;
    for (final w in workouts) {
      final startedAt = DateTime.tryParse(w['started_at'] as String);
      if (startedAt == null) continue;
      final wStart = startedAt.toUtc();
      final wEnd =
          wStart.add(Duration(seconds: (w['duration_seconds'] as int?) ?? 0));
      // Overlap: session.start <= workout.end AND session.end >= workout.start.
      final ex = await db.rawQuery('''
        SELECT uid FROM sh_exercise_sessions
        WHERE start_iso <= ? AND end_iso >= ?
        ORDER BY start_iso DESC LIMIT 1
      ''', [wEnd.toIso8601String(), wStart.toIso8601String()]);
      if (ex.isNotEmpty) {
        await db.update(
            'workout_logs', {'samsung_exercise_uid': ex.first['uid']},
            where: 'id = ?', whereArgs: [w['id']]);
        linked++;
      }
    }

    // Fallback for workouts WITHOUT a start time (history): same calendar day,
    // and only when there's exactly one gym-type watch session that day (never
    // an evening walk, never a guess between two candidates).
    final undated = await db.query('workout_logs',
        columns: ['id', 'date'],
        where:
            "started_at IS NULL AND (samsung_exercise_uid IS NULL OR samsung_exercise_uid = '')");
    if (undated.isNotEmpty) {
      final sessions = await db.query('sh_exercise_sessions',
          columns: ['uid', 'exercise_type', 'start_iso']);
      // Group gym-type sessions by their local date.
      final byDate = <String, List<String>>{};
      for (final s in sessions) {
        if (!isGymType(s['exercise_type'] as String?)) continue;
        final start = DateTime.parse(s['start_iso'] as String).toLocal();
        final d =
            '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
        (byDate[d] ??= []).add(s['uid'] as String);
      }
      for (final w in undated) {
        final wd = (w['date'] as String);
        final key = wd.length >= 10 ? wd.substring(0, 10) : wd; // YYYY-MM-DD
        final candidates = byDate[key];
        if (candidates != null && candidates.length == 1) {
          await db.update(
              'workout_logs', {'samsung_exercise_uid': candidates.first},
              where: 'id = ?', whereArgs: [w['id']]);
          linked++;
        }
      }
    }
    return linked;
  }

  Future<String?> getSyncState(String key) async {
    final db = await database;
    final rows = await db.query('sh_sync_state',
        where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setSyncState(String key, String value) async {
    final db = await database;
    await db.insert('sh_sync_state', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ─── SUPPLEMENTS ────────────────────────────────────────────────────────────

  Future<List<Supplement>> getSupplements() async {
    final db = await database;
    final rows = await db.query('supplements',
        orderBy: 'time_hhmm ASC, sort_order ASC, id ASC');
    return rows.map(Supplement.fromMap).toList();
  }

  Future<int> upsertSupplement(Supplement s) async {
    final db = await database;
    if (s.id == null) {
      return db.insert('supplements', s.toMap());
    }
    await db.update('supplements', s.toMap(),
        where: 'id = ?', whereArgs: [s.id]);
    return s.id!;
  }

  Future<void> deleteSupplement(int id) async {
    final db = await database;
    await db.delete('supplement_logs',
        where: 'supplement_id = ?', whereArgs: [id]);
    await db.delete('supplements', where: 'id = ?', whereArgs: [id]);
  }

  // Returns the set of supplement IDs that were marked taken on [date].
  Future<Set<int>> getSupplementsTakenOn(String date) async {
    final db = await database;
    final rows = await db.query('supplement_logs',
        where: 'date = ?',
        whereArgs: [date],
        columns: ['supplement_id']);
    return rows.map((r) => r['supplement_id'] as int).toSet();
  }

  Future<void> markSupplementTaken(int supplementId, String date) async {
    final db = await database;
    await db.insert(
      'supplement_logs',
      {
        'supplement_id': supplementId,
        'date': date,
        'taken_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> unmarkSupplementTaken(int supplementId, String date) async {
    final db = await database;
    await db.delete('supplement_logs',
        where: 'supplement_id = ? AND date = ?',
        whereArgs: [supplementId, date]);
  }

  // Returns adherence for the last [days] days as a map
  // {supplementId: takenDayCount}. Use to show weekly adherence.
  Future<Map<int, int>> getSupplementAdherence({int days = 7}) async {
    final db = await database;
    final from = DateTime.now().subtract(Duration(days: days - 1));
    final fromStr =
        '${from.year}-${from.month.toString().padLeft(2, '0')}-${from.day.toString().padLeft(2, '0')}';
    final rows = await db.rawQuery('''
      SELECT supplement_id, COUNT(*) AS taken_days
      FROM supplement_logs
      WHERE date >= ?
      GROUP BY supplement_id
    ''', [fromStr]);
    return {
      for (final r in rows)
        (r['supplement_id'] as int): (r['taken_days'] as int),
    };
  }

  // ─── SLEEP ──────────────────────────────────────────────────────────────────

  Future<void> upsertSleepSession(SleepSession s) async {
    final db = await database;
    await db.insert('sleep_sessions', s.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<SleepSession?> getSleepSession(String date) async {
    final db = await database;
    final rows = await db.query('sleep_sessions',
        where: 'date = ?', whereArgs: [date], limit: 1);
    if (rows.isEmpty) return null;
    return SleepSession.fromMap(rows.first);
  }

  /// Sessions in [fromDate, toDate] (inclusive), oldest first.
  Future<List<SleepSession>> getSleepSessions(
      String fromDate, String toDate) async {
    final db = await database;
    final rows = await db.query('sleep_sessions',
        where: 'date >= ? AND date <= ?',
        whereArgs: [fromDate, toDate],
        orderBy: 'date ASC');
    return rows.map(SleepSession.fromMap).toList();
  }

  // ─── LAB VALUES ─────────────────────────────────────────────────────────────

  Future<List<LabValue>> getLabValues({String? name}) async {
    final db = await database;
    final rows = name == null
        ? await db.query('lab_values', orderBy: 'date DESC, id DESC')
        : await db.query('lab_values',
            where: 'name = ?', whereArgs: [name], orderBy: 'date DESC');
    return rows.map(LabValue.fromMap).toList();
  }

  Future<List<String>> getLabValueNames() async {
    final db = await database;
    final rows = await db.rawQuery(
        'SELECT name, MAX(date) AS latest_date FROM lab_values GROUP BY name ORDER BY latest_date DESC');
    return rows.map((r) => r['name'] as String).toList();
  }

  Future<int> upsertLabValue(LabValue v) async {
    final db = await database;
    if (v.id == null) {
      return db.insert('lab_values', v.toMap());
    }
    await db.update('lab_values', v.toMap(),
        where: 'id = ?', whereArgs: [v.id]);
    return v.id!;
  }

  Future<void> deleteLabValue(int id) async {
    final db = await database;
    await db.delete('lab_values', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}
