class Note {
  final String id;
  final String title;
  final String content; // Quill Delta JSON
  final String? folderId;
  final List<String> tagIds;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Note({
    required this.id,
    required this.title,
    required this.content,
    this.folderId,
    required this.tagIds,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'content': content,
        'folder_id': folderId,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory Note.fromMap(Map<String, dynamic> map, List<String> tagIds) => Note(
        id: map['id'] as String,
        title: map['title'] as String,
        content: map['content'] as String,
        folderId: map['folder_id'] as String?,
        tagIds: tagIds,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
      );

  Note copyWith({
    String? title,
    String? content,
    Object? folderId = _sentinel,
    List<String>? tagIds,
    DateTime? updatedAt,
  }) =>
      Note(
        id: id,
        title: title ?? this.title,
        content: content ?? this.content,
        folderId: folderId == _sentinel ? this.folderId : folderId as String?,
        tagIds: tagIds ?? this.tagIds,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

// Sentinel so copyWith can distinguish null from "not provided"
const _sentinel = Object();

class NoteFolder {
  final String id;
  final String name;
  final int colorValue;
  final DateTime createdAt;

  const NoteFolder({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'color_value': colorValue,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory NoteFolder.fromMap(Map<String, dynamic> map) => NoteFolder(
        id: map['id'] as String,
        name: map['name'] as String,
        colorValue: map['color_value'] as int,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      );

  NoteFolder copyWith({String? name, int? colorValue}) => NoteFolder(
        id: id,
        name: name ?? this.name,
        colorValue: colorValue ?? this.colorValue,
        createdAt: createdAt,
      );
}

class NoteTag {
  final String id;
  final String name;
  final int colorValue;

  const NoteTag({
    required this.id,
    required this.name,
    required this.colorValue,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'color_value': colorValue,
      };

  factory NoteTag.fromMap(Map<String, dynamic> map) => NoteTag(
        id: map['id'] as String,
        name: map['name'] as String,
        colorValue: map['color_value'] as int,
      );

  NoteTag copyWith({String? name, int? colorValue}) => NoteTag(
        id: id,
        name: name ?? this.name,
        colorValue: colorValue ?? this.colorValue,
      );
}
