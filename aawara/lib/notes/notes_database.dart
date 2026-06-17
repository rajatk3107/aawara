import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';
import 'note_model.dart';

class NotesDatabase {
  static final NotesDatabase instance = NotesDatabase._init();
  static Database? _db;
  // See WorkoutDatabase: cache the in-flight open so concurrent first-callers
  // share one init instead of racing to open the DB multiple times.
  static Future<Database>? _opening;

  NotesDatabase._init();

  Future<Database> get database async {
    if (_db != null) return _db!;
    _opening ??= _initDB('richie_rich_notes.db');
    try {
      _db = await _opening!;
      return _db!;
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  Future<Database> _initDB(String fileName) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, fileName);
    return openDatabase(path, version: 1, onCreate: _onCreate);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE folders (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        color_value INTEGER NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE tags (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        color_value INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE notes (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        folder_id TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE note_tags (
        note_id TEXT NOT NULL,
        tag_id TEXT NOT NULL,
        PRIMARY KEY (note_id, tag_id)
      )
    ''');
  }

  // ─── Notes ───────────────────────────────────────────────────────────────

  Future<Note> createNote({
    required String title,
    required String content,
    String? folderId,
    List<String> tagIds = const [],
  }) async {
    final db = await database;
    final id = const Uuid().v4();
    final now = DateTime.now();
    final note = Note(
      id: id,
      title: title,
      content: content,
      folderId: folderId,
      tagIds: tagIds,
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('notes', note.toMap());
    for (final tagId in tagIds) {
      await db.insert('note_tags', {'note_id': id, 'tag_id': tagId},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    return note;
  }

  Future<void> updateNote(Note note) async {
    final db = await database;
    await db.update('notes', note.toMap(),
        where: 'id = ?', whereArgs: [note.id]);
    await db.delete('note_tags', where: 'note_id = ?', whereArgs: [note.id]);
    for (final tagId in note.tagIds) {
      await db.insert('note_tags', {'note_id': note.id, 'tag_id': tagId},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<void> deleteNote(String id) async {
    final db = await database;
    await db.delete('note_tags', where: 'note_id = ?', whereArgs: [id]);
    await db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Note>> getNotes({
    String? folderId,
    String? tagId,
    String? searchQuery,
  }) async {
    final db = await database;
    final conditions = <String>[];
    final args = <dynamic>[];

    if (folderId != null) {
      conditions.add('n.folder_id = ?');
      args.add(folderId);
    }
    if (searchQuery != null && searchQuery.isNotEmpty) {
      conditions.add('(n.title LIKE ? OR n.content LIKE ?)');
      args.addAll(['%$searchQuery%', '%$searchQuery%']);
    }

    String query = 'SELECT DISTINCT n.* FROM notes n';
    if (tagId != null) {
      query += ' INNER JOIN note_tags nt ON n.id = nt.note_id AND nt.tag_id = ?';
      args.insert(0, tagId);
    }
    if (conditions.isNotEmpty) {
      query += ' WHERE ${conditions.join(' AND ')}';
    }
    query += ' ORDER BY n.updated_at DESC';

    final maps = await db.rawQuery(query, args);
    return Future.wait(maps.map((map) async {
      final tagIds = await _tagIdsForNote(db, map['id'] as String);
      return Note.fromMap(map, tagIds);
    }));
  }

  Future<List<String>> _tagIdsForNote(Database db, String noteId) async {
    final rows = await db
        .query('note_tags', where: 'note_id = ?', whereArgs: [noteId]);
    return rows.map((r) => r['tag_id'] as String).toList();
  }

  // ─── Folders ─────────────────────────────────────────────────────────────

  Future<NoteFolder> createFolder(String name, int colorValue) async {
    final db = await database;
    final folder = NoteFolder(
      id: const Uuid().v4(),
      name: name,
      colorValue: colorValue,
      createdAt: DateTime.now(),
    );
    await db.insert('folders', folder.toMap());
    return folder;
  }

  Future<List<NoteFolder>> getFolders() async {
    final db = await database;
    final maps = await db.query('folders', orderBy: 'created_at ASC');
    return maps.map(NoteFolder.fromMap).toList();
  }

  Future<void> updateFolder(NoteFolder folder) async {
    final db = await database;
    await db.update('folders', folder.toMap(),
        where: 'id = ?', whereArgs: [folder.id]);
  }

  Future<void> deleteFolder(String id) async {
    final db = await database;
    await db.update('notes', {'folder_id': null},
        where: 'folder_id = ?', whereArgs: [id]);
    await db.delete('folders', where: 'id = ?', whereArgs: [id]);
  }

  // ─── Tags ─────────────────────────────────────────────────────────────────

  Future<NoteTag> createTag(String name, int colorValue) async {
    final db = await database;
    final tag = NoteTag(
      id: const Uuid().v4(),
      name: name,
      colorValue: colorValue,
    );
    await db.insert('tags', tag.toMap());
    return tag;
  }

  Future<List<NoteTag>> getTags() async {
    final db = await database;
    final maps = await db.query('tags');
    return maps.map(NoteTag.fromMap).toList();
  }

  Future<void> updateTag(NoteTag tag) async {
    final db = await database;
    await db.update('tags', tag.toMap(),
        where: 'id = ?', whereArgs: [tag.id]);
  }

  Future<void> deleteTag(String id) async {
    final db = await database;
    await db.delete('note_tags', where: 'tag_id = ?', whereArgs: [id]);
    await db.delete('tags', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> close() async => (await database).close();
}
