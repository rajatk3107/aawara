import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:intl/intl.dart';
import 'note_model.dart';
import 'notes_database.dart';
import 'note_editor_screen.dart';
import '../workout/widgets/empty_state_widget.dart';

class NotesListScreen extends StatefulWidget {
  const NotesListScreen({super.key});

  @override
  State<NotesListScreen> createState() => _NotesListScreenState();
}

class _NotesListScreenState extends State<NotesListScreen> {
  final _db = NotesDatabase.instance;
  final _searchController = TextEditingController();

  List<Note> _notes = [];
  List<NoteFolder> _folders = [];
  List<NoteTag> _tags = [];

  String? _selectedFolderId; // null = All
  String? _selectedTagId;
  bool _isSearching = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final notes = await _db.getNotes(
      folderId: _selectedFolderId,
      tagId: _selectedTagId,
      searchQuery: _searchQuery.isEmpty ? null : _searchQuery,
    );
    final folders = await _db.getFolders();
    final tags = await _db.getTags();
    if (!mounted) return;
    setState(() {
      _notes = notes;
      _folders = folders;
      _tags = tags;
    });
  }

  Future<void> _openEditor({Note? note}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen(
          note: note,
          defaultFolderId: _selectedFolderId,
          folders: _folders,
          tags: _tags,
        ),
      ),
    );
    _load();
  }

  Future<void> _deleteNote(Note note) async {
    await _db.deleteNote(note.id);
    _load();
  }

  void _onSearchChanged(String value) {
    setState(() => _searchQuery = value);
    _load();
  }

  // ── Folder management ───────────────────────────────────────────────────

  void _showCreateFolderDialog() {
    final nameCtrl = TextEditingController();
    int selectedColor = _folderColors[0].value;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          title: const Text('New Folder',
              style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Folder name',
                  hintStyle: TextStyle(color: Color(0xFF888899)),
                  enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF444455))),
                  focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFFFFD700))),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: _folderColors.map((c) {
                  final selected = c.value == selectedColor;
                  return GestureDetector(
                    onTap: () => setS(() => selectedColor = c.value),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: selected
                            ? Border.all(color: Colors.white, width: 2)
                            : null,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(color: Color(0xFF888899))),
            ),
            TextButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                await _db.createFolder(name, selectedColor);
                if (ctx.mounted) Navigator.pop(ctx);
                _load();
              },
              child: const Text('Create',
                  style: TextStyle(color: Color(0xFFFFD700))),
            ),
          ],
        ),
      ),
    );
  }

  void _showFolderOptions(NoteFolder folder) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.edit_rounded,
                  color: Color(0xFFFFD700)),
              title: const Text('Rename',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _showRenameFolderDialog(folder);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              title: const Text('Delete Folder',
                  style: TextStyle(color: Colors.redAccent)),
              onTap: () async {
                Navigator.pop(ctx);
                await _db.deleteFolder(folder.id);
                if (_selectedFolderId == folder.id) {
                  setState(() => _selectedFolderId = null);
                }
                _load();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showRenameFolderDialog(NoteFolder folder) {
    final ctrl = TextEditingController(text: folder.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Rename Folder',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintStyle: TextStyle(color: Color(0xFF888899)),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF444455))),
            focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFFFD700))),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(color: Color(0xFF888899)))),
          TextButton(
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              await _db.updateFolder(folder.copyWith(name: name));
              if (ctx.mounted) Navigator.pop(ctx);
              _load();
            },
            child: const Text('Save',
                style: TextStyle(color: Color(0xFFFFD700))),
          ),
        ],
      ),
    );
  }

  // ── Tag management ──────────────────────────────────────────────────────

  void _showManageTagsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _TagManagerSheet(
        tags: _tags,
        onChanged: _load,
        db: _db,
      ),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  String _preview(String contentJson) {
    try {
      final doc = Document.fromJson(jsonDecode(contentJson) as List);
      return doc.toPlainText().trim().replaceAll('\n', ' ');
    } catch (_) {
      return '';
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      return DateFormat('h:mm a').format(date);
    } else if (date.year == now.year) {
      return DateFormat('MMM d').format(date);
    }
    return DateFormat('MM/dd/yy').format(date);
  }

  static const _folderColors = [
    Color(0xFFFFD700), Color(0xFF4DAAFF), Color(0xFF66DD88),
    Color(0xFFFF6B6B), Color(0xFFCC88FF), Color(0xFFFF9944),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildFolderTabs(),
          if (_tags.isNotEmpty) _buildTagChips(),
          Expanded(child: _buildNotesList()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        backgroundColor: const Color(0xFFFFD700),
        foregroundColor: const Color(0xFF1A1000),
        shape: const CircleBorder(),
        child: const Icon(Icons.add_rounded, size: 28),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF0D0D1A),
      elevation: 0,
      title: _isSearching
          ? TextField(
              controller: _searchController,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Search notes…',
                hintStyle: TextStyle(color: Color(0xFF888899)),
                border: InputBorder.none,
              ),
              onChanged: _onSearchChanged,
            )
          : const Text('Notes',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 22)),
      actions: [
        IconButton(
          icon: Icon(_isSearching ? Icons.close : Icons.search_rounded,
              color: Colors.white70),
          onPressed: () {
            setState(() {
              _isSearching = !_isSearching;
              if (!_isSearching) {
                _searchController.clear();
                _searchQuery = '';
                _load();
              }
            });
          },
        ),
        PopupMenuButton<String>(
          color: const Color(0xFF1A1A2E),
          icon: const Icon(Icons.more_vert, color: Colors.white70),
          onSelected: (v) {
            if (v == 'tags') _showManageTagsSheet();
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'tags',
              child: Row(children: [
                Icon(Icons.label_outline_rounded,
                    color: Color(0xFFFFD700), size: 20),
                SizedBox(width: 10),
                Text('Manage Tags',
                    style: TextStyle(color: Colors.white)),
              ]),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFolderTabs() {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          // All tab
          _FolderTab(
            label: 'All',
            isSelected: _selectedFolderId == null,
            color: const Color(0xFFFFD700),
            onTap: () => setState(() {
              _selectedFolderId = null;
              _load();
            }),
          ),
          ..._folders.map((f) => _FolderTab(
                label: f.name,
                isSelected: _selectedFolderId == f.id,
                color: Color(f.colorValue),
                onTap: () => setState(() {
                  _selectedFolderId =
                      _selectedFolderId == f.id ? null : f.id;
                  _load();
                }),
                onLongPress: () => _showFolderOptions(f),
              )),
          // Add folder button
          GestureDetector(
            onTap: _showCreateFolderDialog,
            child: Container(
              margin: const EdgeInsets.only(left: 8, top: 4, bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF444455)),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.add, color: Color(0xFF888899), size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTagChips() {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: _tags.map((tag) {
          final selected = _selectedTagId == tag.id;
          return GestureDetector(
            onTap: () => setState(() {
              _selectedTagId = selected ? null : tag.id;
              _load();
            }),
            child: Container(
              margin: const EdgeInsets.only(right: 8, top: 2, bottom: 2),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: selected
                    ? Color(tag.colorValue).withValues(alpha: 0.25)
                    : Colors.transparent,
                border: Border.all(
                    color: Color(tag.colorValue).withValues(alpha: 0.6)),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(tag.name,
                  style: TextStyle(
                      color: Color(tag.colorValue),
                      fontSize: 12,
                      fontWeight: FontWeight.w500)),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildNotesList() {
    if (_notes.isEmpty) {
      return EmptyStateWidget(
        icon: Icons.edit_note_rounded,
        title: _searchQuery.isNotEmpty ? 'No matching notes' : 'No notes yet',
        subtitle: _searchQuery.isNotEmpty
            ? 'Try a different search term'
            : 'Tap + to write your first workout note or meal plan',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      itemCount: _notes.length,
      itemBuilder: (_, i) {
        final note = _notes[i];
        final noteTags = _tags
            .where((t) => note.tagIds.contains(t.id))
            .toList();
        final preview = _preview(note.content);

        return Dismissible(
          key: ValueKey(note.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.delete_outline_rounded,
                color: Colors.redAccent),
          ),
          onDismissed: (_) => _deleteNote(note),
          child: GestureDetector(
            onTap: () => _openEditor(note: note),
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          note.title.isEmpty ? 'Untitled' : note.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatDate(note.updatedAt),
                        style: const TextStyle(
                            color: Color(0xFF888899), fontSize: 12),
                      ),
                    ],
                  ),
                  if (preview.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      preview,
                      style: const TextStyle(
                          color: Color(0xFF888899), fontSize: 13, height: 1.4),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (noteTags.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      children: noteTags
                          .map((t) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Color(t.colorValue)
                                      .withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(t.name,
                                    style: TextStyle(
                                        color: Color(t.colorValue),
                                        fontSize: 11)),
                              ))
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Folder tab widget ────────────────────────────────────────────────────────

class _FolderTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _FolderTab({
    required this.label,
    required this.isSelected,
    required this.color,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.2) : Colors.transparent,
          border: Border.all(
              color: isSelected ? color : const Color(0xFF444455)),
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? color : const Color(0xFF888899),
            fontSize: 13,
            fontWeight:
                isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

// ── Tag manager bottom sheet ─────────────────────────────────────────────────

class _TagManagerSheet extends StatefulWidget {
  final List<NoteTag> tags;
  final VoidCallback onChanged;
  final NotesDatabase db;

  const _TagManagerSheet({
    required this.tags,
    required this.onChanged,
    required this.db,
  });

  @override
  State<_TagManagerSheet> createState() => _TagManagerSheetState();
}

class _TagManagerSheetState extends State<_TagManagerSheet> {
  late List<NoteTag> _tags;

  static const _tagColors = [
    Color(0xFFFFD700), Color(0xFF4DAAFF), Color(0xFF66DD88),
    Color(0xFFFF6B6B), Color(0xFFCC88FF), Color(0xFFFF9944),
    Color(0xFF44FFEE), Color(0xFFFF44AA),
  ];

  @override
  void initState() {
    super.initState();
    _tags = List.from(widget.tags);
  }

  void _showCreateTagDialog() {
    final ctrl = TextEditingController();
    int selectedColor = _tagColors[0].value;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          title: const Text('New Tag',
              style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Tag name',
                  hintStyle: TextStyle(color: Color(0xFF888899)),
                  enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF444455))),
                  focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFFFFD700))),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: _tagColors.map((c) {
                  final sel = c.value == selectedColor;
                  return GestureDetector(
                    onTap: () => setS(() => selectedColor = c.value),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: sel
                            ? Border.all(color: Colors.white, width: 2)
                            : null,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel',
                    style: TextStyle(color: Color(0xFF888899)))),
            TextButton(
              onPressed: () async {
                final name = ctrl.text.trim();
                if (name.isEmpty) return;
                final tag = await widget.db.createTag(name, selectedColor);
                setState(() => _tags.add(tag));
                if (ctx.mounted) Navigator.pop(ctx);
                widget.onChanged();
              },
              child: const Text('Create',
                  style: TextStyle(color: Color(0xFFFFD700))),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      maxChildSize: 0.85,
      minChildSize: 0.3,
      expand: false,
      builder: (_, scrollCtrl) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Manage Tags',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18)),
                TextButton.icon(
                  onPressed: _showCreateTagDialog,
                  icon: const Icon(Icons.add, color: Color(0xFFFFD700)),
                  label: const Text('New',
                      style: TextStyle(color: Color(0xFFFFD700))),
                ),
              ],
            ),
          ),
          Expanded(
            child: _tags.isEmpty
                ? const Center(
                    child: Text('No tags yet',
                        style: TextStyle(color: Color(0xFF888899))))
                : ListView.builder(
                    controller: scrollCtrl,
                    itemCount: _tags.length,
                    itemBuilder: (_, i) {
                      final tag = _tags[i];
                      return ListTile(
                        leading: CircleAvatar(
                          radius: 10,
                          backgroundColor: Color(tag.colorValue),
                        ),
                        title: Text(tag.name,
                            style:
                                const TextStyle(color: Colors.white)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline_rounded,
                              color: Colors.redAccent, size: 20),
                          onPressed: () async {
                            await widget.db.deleteTag(tag.id);
                            setState(() => _tags.removeAt(i));
                            widget.onChanged();
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
