import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../database/workout_database.dart';
import '../models/progress_photo.dart';

class ProgressPhotosScreen extends StatefulWidget {
  const ProgressPhotosScreen({super.key});

  @override
  State<ProgressPhotosScreen> createState() => _ProgressPhotosScreenState();
}

class _ProgressPhotosScreenState extends State<ProgressPhotosScreen> {
  final _db = WorkoutDatabase.instance;
  final _picker = ImagePicker();

  List<ProgressPhoto> _photos = [];
  bool _loading = true;
  bool _compareMode = false;
  final Set<int> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final photos = await _db.getProgressPhotos();
    if (mounted) setState(() { _photos = photos; _loading = false; });
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _addPhoto() async {
    final source = await _pickSource();
    if (source == null) return;

    final picked = await _picker.pickImage(source: source, imageQuality: 90);
    if (picked == null) return;

    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      aspectRatio: const CropAspectRatio(ratioX: 3, ratioY: 4),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Photo',
          toolbarColor: const Color(0xFF0D0D1A),
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: const Color(0xFFFFD700),
          lockAspectRatio: true,
          hideBottomControls: false,
        ),
        IOSUiSettings(
          title: 'Crop Photo',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
        ),
      ],
    );
    if (cropped == null) return;

    // Save to app documents
    final dir = await getApplicationDocumentsDirectory();
    final filename = 'progress_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final dest = '${dir.path}/$filename';
    await File(cropped.path).copy(dest);

    // Optional note
    final note = await _askNote();

    final photo = ProgressPhoto(
      date: _fmt(DateTime.now()),
      filePath: dest,
      note: note?.isNotEmpty == true ? note : null,
    );
    await _db.addProgressPhoto(photo);
    _load();
  }

  Future<ImageSource?> _pickSource() async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 16),
              _SourceTile(
                icon: Icons.camera_alt_rounded,
                label: 'Camera',
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              const SizedBox(height: 8),
              _SourceTile(
                icon: Icons.photo_library_rounded,
                label: 'Photo Library',
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _askNote() async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Add a note',
            style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          autofocus: false,
          maxLines: 2,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Add a note... (optional)',
            hintStyle: TextStyle(color: Color(0xFF555577)),
            border: InputBorder.none,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Skip',
                style: TextStyle(color: Color(0xFF888899))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.black,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Save',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _deletePhoto(ProgressPhoto photo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete photo?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text('This cannot be undone.',
            style: TextStyle(color: Color(0xFF888899))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF888899))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE74C3C),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Delete',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _db.deleteProgressPhoto(photo.id!);
      _load();
    }
  }

  void _toggleSelect(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else if (_selectedIds.length < 2) {
        _selectedIds.add(id);
      }
    });
  }

  void _openCompare() {
    final selected = _photos.where((p) => _selectedIds.contains(p.id)).toList();
    if (selected.length != 2) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _CompareViewScreen(
          left: selected[0],
          right: selected[1],
        ),
      ),
    );
  }

  String _fmtDate(String date) {
    try {
      final d = DateTime.parse(date);
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${months[d.month - 1]} ${d.day}, ${d.year}';
    } catch (_) {
      return date;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D1A),
        surfaceTintColor: Colors.transparent,
        title: const Text('Progress Photos',
            style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_photos.length >= 2)
            TextButton(
              onPressed: () {
                setState(() {
                  _compareMode = !_compareMode;
                  _selectedIds.clear();
                });
              },
              child: Text(
                _compareMode ? 'Cancel' : 'Compare',
                style: TextStyle(
                  color: _compareMode
                      ? const Color(0xFF888899)
                      : const Color(0xFFFFD700),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.add_rounded, color: Color(0xFFFFD700)),
            onPressed: _addPhoto,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFFD700)))
          : _photos.isEmpty
              ? _buildEmpty()
              : Stack(
                  children: [
                    GridView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 3 / 4,
                      ),
                      itemCount: _photos.length,
                      itemBuilder: (_, i) => _buildPhotoCell(_photos[i]),
                    ),
                    if (_compareMode && _selectedIds.length == 2)
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 24,
                        child: ElevatedButton.icon(
                          onPressed: _openCompare,
                          icon: const Icon(Icons.compare_rounded),
                          label: const Text('View Side-by-Side',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFD700),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }

  Widget _buildEmpty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.camera_alt_outlined,
                color: Color(0xFF333355), size: 56),
            const SizedBox(height: 16),
            const Text('No photos yet',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
            const SizedBox(height: 6),
            const Text('Tap + to add your first progress photo',
                style: TextStyle(color: Color(0xFF555577), fontSize: 13)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _addPhoto,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Photo',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD700),
                foregroundColor: Colors.black,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      );

  Widget _buildPhotoCell(ProgressPhoto photo) {
    final isSelected = _selectedIds.contains(photo.id);
    return GestureDetector(
      onTap: () {
        if (_compareMode) {
          _toggleSelect(photo.id!);
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => _PhotoDetailScreen(
                photo: photo,
                onDelete: () {
                  Navigator.pop(context);
                  _deletePhoto(photo);
                },
              ),
            ),
          );
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFFFD700)
                : Colors.transparent,
            width: isSelected ? 2.5 : 0,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(isSelected ? 10 : 12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _PhotoImage(path: photo.filePath),
              // Date + note overlay
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Color(0xCC000000), Colors.transparent],
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_fmtDate(photo.date),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                      if (photo.note != null && photo.note!.isNotEmpty)
                        Text(photo.note!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white60, fontSize: 10)),
                    ],
                  ),
                ),
              ),
              if (_compareMode)
                Positioned(
                  top: 8,
                  right: 8,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected
                          ? const Color(0xFFFFD700)
                          : Colors.black45,
                      border: Border.all(color: Colors.white54, width: 1.5),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check_rounded,
                            color: Colors.black, size: 14)
                        : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Photo Detail ─────────────────────────────────────────────────────────────

class _PhotoDetailScreen extends StatelessWidget {
  final ProgressPhoto photo;
  final VoidCallback onDelete;

  const _PhotoDetailScreen({required this.photo, required this.onDelete});

  String _fmtDate(String date) {
    try {
      final d = DateTime.parse(date);
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${months[d.month - 1]} ${d.day}, ${d.year}';
    } catch (_) {
      return date;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(_fmtDate(photo.date),
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded,
                color: Color(0xFFE74C3C)),
            onPressed: onDelete,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 5.0,
              child: Center(child: _PhotoImage(path: photo.filePath)),
            ),
          ),
          if (photo.note != null && photo.note!.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
              color: const Color(0xFF0D0D1A),
              child: Text(
                photo.note!,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Compare View ─────────────────────────────────────────────────────────────

class _CompareViewScreen extends StatefulWidget {
  final ProgressPhoto left;
  final ProgressPhoto right;

  const _CompareViewScreen({required this.left, required this.right});

  @override
  State<_CompareViewScreen> createState() => _CompareViewScreenState();
}

class _CompareViewScreenState extends State<_CompareViewScreen> {
  final _repaintKey = GlobalKey();
  bool _sharing = false;

  String _fmtDate(String date) {
    try {
      final d = DateTime.parse(date);
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${months[d.month - 1]} ${d.day}, ${d.year}';
    } catch (_) {
      return date;
    }
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final boundary =
          _repaintKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();
      final tmp = await getTemporaryDirectory();
      final file = File(
          '${tmp.path}/compare_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)],
          text: 'Progress comparison');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Share failed: $e'),
            backgroundColor: const Color(0xFF2A2A45),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Compare',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        actions: [
          _sharing
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFFFFD700)),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.share_rounded,
                      color: Color(0xFFFFD700)),
                  onPressed: _share,
                ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: RepaintBoundary(
              key: _repaintKey,
              child: Row(
                children: [
                  Expanded(
                    child: _CompareSide(
                      photo: widget.left,
                      label: _fmtDate(widget.left.date),
                    ),
                  ),
                  Container(width: 2, color: const Color(0xFF1A1A2E)),
                  Expanded(
                    child: _CompareSide(
                      photo: widget.right,
                      label: _fmtDate(widget.right.date),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompareSide extends StatelessWidget {
  final ProgressPhoto photo;
  final String label;

  const _CompareSide({required this.photo, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: InteractiveViewer(
            minScale: 0.8,
            maxScale: 5.0,
            child: _PhotoImage(path: photo.filePath, fit: BoxFit.cover),
          ),
        ),
        Container(
          width: double.infinity,
          color: const Color(0xFF0D0D1A),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

// ─── Shared helpers ───────────────────────────────────────────────────────────

class _PhotoImage extends StatelessWidget {
  final String path;
  final BoxFit fit;

  const _PhotoImage({required this.path, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    return file.existsSync()
        ? Image.file(file, fit: fit)
        : Container(
            color: const Color(0xFF1A1A2E),
            child: const Icon(Icons.broken_image_outlined,
                color: Color(0xFF333355), size: 32),
          );
  }
}

class _SourceTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SourceTile(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0D1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF1E1E35)),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFFFFD700), size: 22),
            const SizedBox(width: 14),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
