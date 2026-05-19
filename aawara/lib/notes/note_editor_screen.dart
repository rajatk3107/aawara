import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'note_model.dart';
import 'notes_database.dart';

class NoteEditorScreen extends StatefulWidget {
  final Note? note;
  final String? defaultFolderId;
  final List<NoteFolder> folders;
  final List<NoteTag> tags;

  const NoteEditorScreen({
    super.key,
    this.note,
    this.defaultFolderId,
    required this.folders,
    required this.tags,
  });

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late final QuillController _quillController;
  late final TextEditingController _titleController;
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();

  late String? _folderId;
  late List<String> _selectedTagIds;
  bool _saving = false;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();

    final note = widget.note;
    _titleController = TextEditingController(text: note?.title ?? '');
    _folderId = note?.folderId ?? widget.defaultFolderId;
    _selectedTagIds = note?.tagIds.toList() ?? [];

    if (note != null && note.content.isNotEmpty) {
      try {
        final json = jsonDecode(note.content) as List;
        _quillController = QuillController(
          document: Document.fromJson(json),
          selection: const TextSelection.collapsed(offset: 0),
        );
      } catch (_) {
        _quillController = QuillController.basic();
      }
    } else {
      _quillController = QuillController.basic();
    }

    _titleController.addListener(_markChanged);
    _quillController.addListener(_markChanged);
  }

  void _markChanged() => _hasChanges = true;

  @override
  void dispose() {
    _quillController.dispose();
    _titleController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final title = _titleController.text.trim();
    final delta = _quillController.document.toDelta();
    // Skip saving if truly empty new note (single empty newline op)
    final isBodyEmpty = delta.length == 1 &&
        delta.first.data is String &&
        (delta.first.data as String) == '\n';
    if (widget.note == null && title.isEmpty && isBodyEmpty) return;

    setState(() => _saving = true);
    final content = jsonEncode(delta.toJson());
    final db = NotesDatabase.instance;

    if (widget.note == null) {
      await db.createNote(
        title: title.isEmpty ? 'Untitled' : title,
        content: content,
        folderId: _folderId,
        tagIds: _selectedTagIds,
      );
    } else {
      await db.updateNote(widget.note!.copyWith(
        title: title.isEmpty ? 'Untitled' : title,
        content: content,
        folderId: _folderId,
        tagIds: _selectedTagIds,
        updatedAt: DateTime.now(),
      ));
    }

    if (mounted) setState(() => _saving = false);
    _hasChanges = false;
  }

  Future<void> _insertImage() async {
    final picker = ImagePicker();
    final picked =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;

    final dir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory('${dir.path}/notes_images');
    if (!imagesDir.existsSync()) imagesDir.createSync(recursive: true);

    final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    final dest = '${imagesDir.path}/$fileName';
    await File(picked.path).copy(dest);

    final index = _quillController.selection.baseOffset;
    final length =
        _quillController.selection.extentOffset - index;
    _quillController.replaceText(
        index, length, BlockEmbed.image(dest), null);
  }

  void _showFolderPicker() {
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
            _sheetHandle(),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Move to Folder',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ),
            ListTile(
              leading: Icon(Icons.folder_off_outlined,
                  color: _folderId == null
                      ? const Color(0xFFFFD700)
                      : Colors.white54),
              title: const Text('No Folder',
                  style: TextStyle(color: Colors.white)),
              trailing: _folderId == null
                  ? const Icon(Icons.check, color: Color(0xFFFFD700))
                  : null,
              onTap: () {
                setState(() => _folderId = null);
                _hasChanges = true;
                Navigator.pop(ctx);
              },
            ),
            ...widget.folders.map((f) => ListTile(
                  leading: Icon(Icons.folder_rounded,
                      color: _folderId == f.id
                          ? Color(f.colorValue)
                          : Colors.white54),
                  title: Text(f.name,
                      style: const TextStyle(color: Colors.white)),
                  trailing: _folderId == f.id
                      ? Icon(Icons.check, color: Color(f.colorValue))
                      : null,
                  onTap: () {
                    setState(() => _folderId = f.id);
                    _hasChanges = true;
                    Navigator.pop(ctx);
                  },
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showTagPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              _sheetHandle(),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Select Tags',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
              ),
              if (widget.tags.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('No tags created yet',
                      style: TextStyle(color: Color(0xFF888899))),
                )
              else
                ...widget.tags.map((tag) {
                  final selected = _selectedTagIds.contains(tag.id);
                  return ListTile(
                    leading: CircleAvatar(
                        radius: 10,
                        backgroundColor: Color(tag.colorValue)),
                    title: Text(tag.name,
                        style: const TextStyle(color: Colors.white)),
                    trailing: selected
                        ? Icon(Icons.check, color: Color(tag.colorValue))
                        : null,
                    onTap: () {
                      setS(() {
                        if (selected) {
                          _selectedTagIds.remove(tag.id);
                        } else {
                          _selectedTagIds.add(tag.id);
                        }
                      });
                      setState(() {});
                      _hasChanges = true;
                    },
                  );
                }),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetHandle() => Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
            color: Colors.white24, borderRadius: BorderRadius.circular(2)),
      );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_hasChanges) await _save();
        if (mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0D1A),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0D0D1A),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white70),
            onPressed: () async {
              if (_hasChanges) await _save();
              if (mounted) Navigator.pop(context);
            },
          ),
          actions: [
            IconButton(
              tooltip: 'Insert image',
              icon: const Icon(Icons.image_outlined, color: Colors.white54),
              onPressed: _insertImage,
            ),
            IconButton(
              tooltip: 'Folder',
              icon: Icon(
                Icons.folder_outlined,
                color: _folderId != null
                    ? const Color(0xFFFFD700)
                    : Colors.white54,
              ),
              onPressed: _showFolderPicker,
            ),
            IconButton(
              tooltip: 'Tags',
              icon: Icon(
                Icons.label_outline_rounded,
                color: _selectedTagIds.isNotEmpty
                    ? const Color(0xFFFFD700)
                    : Colors.white54,
              ),
              onPressed: _showTagPicker,
            ),
            if (_saving)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFFFFD700)),
                ),
              )
            else
              IconButton(
                tooltip: 'Done',
                icon: const Icon(Icons.check_rounded,
                    color: Color(0xFFFFD700)),
                onPressed: () async {
                  await _save();
                  if (mounted) Navigator.pop(context);
                },
              ),
          ],
        ),
        body: Column(
          children: [
            // Title
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: TextField(
                controller: _titleController,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
                decoration: const InputDecoration(
                  hintText: 'Title',
                  hintStyle: TextStyle(
                      color: Color(0xFF444455), fontSize: 22),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                textCapitalization: TextCapitalization.sentences,
                maxLines: 2,
                minLines: 1,
                onSubmitted: (_) => _focusNode.requestFocus(),
              ),
            ),
            const Divider(color: Color(0xFF222235), height: 1),
            // Toolbar
            QuillSimpleToolbar(
                controller: _quillController,
                configurations: QuillSimpleToolbarConfigurations(
                  color: const Color(0xFF111120),
                  multiRowsDisplay: false,
                  showBoldButton: true,
                  showItalicButton: true,
                  showUnderLineButton: true,
                  showStrikeThrough: true,
                  showHeaderStyle: true,
                  showListBullets: true,
                  showListNumbers: true,
                  showQuote: true,
                  showLink: true,
                  showUndo: true,
                  showRedo: true,
                  showAlignmentButtons: true,
                  showIndent: true,
                  showCodeBlock: false,
                  showInlineCode: false,
                  showSearchButton: false,
                  showSubscript: false,
                  showSuperscript: false,
                  showSmallButton: false,
                  showFontSize: false,
                  showFontFamily: false,
                  showDividers: true,
                  showClipboardCut: false,
                  showClipboardCopy: false,
                  showClipboardPaste: false,
                  buttonOptions: QuillSimpleToolbarButtonOptions(
                    base: QuillToolbarBaseButtonOptions(
                      iconSize: 18,
                      iconTheme: QuillIconTheme(
                        iconButtonSelectedData: IconButtonData(
                          color: const Color(0xFF0D0D1A),
                          style: ButtonStyle(
                            backgroundColor: WidgetStateProperty.all(
                                const Color(0xFFFFD700)),
                          ),
                        ),
                        iconButtonUnselectedData: const IconButtonData(
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ),
                ),
            ),
            const Divider(color: Color(0xFF222235), height: 1),
            // Editor body
            Expanded(
              child: QuillEditor(
                controller: _quillController,
                focusNode: _focusNode,
                scrollController: _scrollController,
                configurations: QuillEditorConfigurations(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                  placeholder: 'Start writing…',
                  expands: false,
                  scrollable: true,
                  embedBuilders: [_LocalImageEmbedBuilder()],
                  customStyles: DefaultStyles(
                    color: Colors.white,
                    placeHolder: DefaultTextBlockStyle(
                      const TextStyle(
                          color: Color(0xFF444455), fontSize: 16),
                      HorizontalSpacing.zero,
                      VerticalSpacing.zero,
                      VerticalSpacing.zero,
                      null,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Renders local file-path images inserted via BlockEmbed.image
class _LocalImageEmbedBuilder extends EmbedBuilder {
  @override
  String get key => BlockEmbed.imageType;

  @override
  bool get expanded => true;

  @override
  Widget build(
    BuildContext context,
    QuillController controller,
    Embed node,
    bool readOnly,
    bool inline,
    TextStyle textStyle,
  ) {
    final path = node.value.data as String;
    final file = File(path);
    if (!file.existsSync()) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(
          height: 80,
          child: Center(
              child: Icon(Icons.broken_image_outlined,
                  color: Color(0xFF444455), size: 40)),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(file, fit: BoxFit.fitWidth),
      ),
    );
  }
}
