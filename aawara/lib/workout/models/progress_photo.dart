class ProgressPhoto {
  final int? id;
  final String date;
  final String filePath;
  final String? note;
  final String? createdAt;

  const ProgressPhoto({
    this.id,
    required this.date,
    required this.filePath,
    this.note,
    this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'date': date,
        'file_path': filePath,
        'note': note,
      };

  factory ProgressPhoto.fromMap(Map<String, dynamic> map) => ProgressPhoto(
        id: map['id'] as int?,
        date: map['date'] as String,
        filePath: map['file_path'] as String,
        note: map['note'] as String?,
        createdAt: map['created_at'] as String?,
      );
}
