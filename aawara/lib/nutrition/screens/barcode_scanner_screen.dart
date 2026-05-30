import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/nutrition_models.dart';
import '../services/barcode_nutrition_service.dart';
import '../widgets/manual_nutrition_form.dart';
import '../../workout/database/workout_database.dart';
import '../../utils/safe_navigation.dart';

class BarcodeScannerScreen extends StatefulWidget {
  final String date;
  final String meal;

  const BarcodeScannerScreen({
    super.key,
    required this.date,
    required this.meal,
  });

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  final _controller = MobileScannerController();
  final _service = BarcodeNutritionService.instance;

  bool _scanning = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (!_scanning || _loading) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;

    setState(() {
      _scanning = false;
      _loading = true;
      _error = null;
    });

    final result = await _service.lookup(raw);

    if (!mounted) return;
    setState(() => _loading = false);

    switch (result) {
      case BarcodeFound(:final food, :final isFromLocal, :final isNutritionComplete):
        if (isNutritionComplete) {
          _showFoundSheet(food, isFromLocal: isFromLocal);
        } else {
          _showIncompleteSheet(food);
        }
      case BarcodeNotFound(:final barcode):
        _showNotFoundSheet(barcode);
      case BarcodeLookupError(:final message):
        setState(() => _error = message);
    }
  }

  void _resetScanner() {
    setState(() {
      _scanning = true;
      _loading = false;
      _error = null;
    });
  }

  void _closeResultSheet(BuildContext sheetContext, bool added) {
    popAfterFocusSettles(sheetContext, added);
  }

  void _handleResultSheetClosed(bool? added) {
    if (!mounted) return;
    if (added == true) {
      popAfterFocusSettles(context, true);
    } else if (!_scanning && !_loading && _error == null) {
      _resetScanner();
    }
  }

  void _showFoundSheet(Food food, {required bool isFromLocal}) {
    showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isDismissible: false,
      builder: (sheetContext) => _FoundSheet(
        food: food,
        isFromLocal: isFromLocal,
        date: widget.date,
        meal: widget.meal,
        onAdded: () => _closeResultSheet(sheetContext, true),
        onRescan: () => _closeResultSheet(sheetContext, false),
      ),
    ).then(_handleResultSheetClosed);
  }

  void _showIncompleteSheet(Food partialFood) {
    showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      isDismissible: false,
      builder: (sheetContext) => _IncompleteSheet(
        partialFood: partialFood,
        date: widget.date,
        meal: widget.meal,
        onAdded: () => _closeResultSheet(sheetContext, true),
        onRescan: () => _closeResultSheet(sheetContext, false),
      ),
    ).then(_handleResultSheetClosed);
  }

  void _showNotFoundSheet(String barcode) {
    showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      isDismissible: false,
      builder: (sheetContext) => _NotFoundSheet(
        barcode: barcode,
        date: widget.date,
        meal: widget.meal,
        onAdded: () => _closeResultSheet(sheetContext, true),
        onRescan: () => _closeResultSheet(sheetContext, false),
      ),
    ).then(_handleResultSheetClosed);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          _ScanOverlay(),
          // Top bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white),
                    onPressed: () => popAfterFocusSettles(context),
                  ),
                  const Expanded(
                    child: Text('Scan Barcode',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.flash_on_rounded, color: Colors.white),
                    onPressed: () => _controller.toggleTorch(),
                  ),
                ],
              ),
            ),
          ),
          // Loading overlay
          if (_loading)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                        color: Color(0xFFFFD700), strokeWidth: 2),
                    SizedBox(height: 16),
                    Text('Looking up product…',
                        style: TextStyle(color: Colors.white70, fontSize: 14)),
                  ],
                ),
              ),
            ),
          // Error card
          if (_error != null)
            Positioned(
              bottom: 80,
              left: 24,
              right: 24,
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A2E),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF2A2A3E)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_off_rounded,
                        color: Color(0xFF555577), size: 32),
                    const SizedBox(height: 10),
                    Text(_error!,
                        style: const TextStyle(
                            color: Color(0xFFCCCCDD), fontSize: 13),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(
                          onPressed: _resetScanner,
                          child: const Text('Try Again',
                              style: TextStyle(color: Color(0xFFFFD700))),
                        ),
                        const SizedBox(width: 12),
                        TextButton(
                          onPressed: () => popAfterFocusSettles(context),
                          child: const Text('Go Back',
                              style: TextStyle(color: Color(0xFF888899))),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          // Hint
          if (!_loading && _error == null)
            const Positioned(
              bottom: 60,
              left: 0,
              right: 0,
              child: Text('Point camera at a product barcode',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white60, fontSize: 13)),
            ),
        ],
      ),
    );
  }
}

// ── Scan overlay ──────────────────────────────────────────────────────────────

class _ScanOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    const boxW = 280.0;
    const boxH = 180.0;
    final left = (size.width - boxW) / 2;
    final top = size.height / 2 - boxH / 2 - 40;

    return Stack(
      children: [
        ColorFiltered(
          colorFilter: ColorFilter.mode(
              Colors.black.withValues(alpha: 0.6), BlendMode.srcOut),
          child: Stack(
            children: [
              Container(
                decoration: const BoxDecoration(
                  color: Colors.black,
                  backgroundBlendMode: BlendMode.dstOut,
                ),
              ),
              Positioned(
                top: top,
                left: left,
                child: Container(
                  width: boxW,
                  height: boxH,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.red,
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          top: top,
          left: left,
          child: _Corners(width: boxW, height: boxH),
        ),
      ],
    );
  }
}

class _Corners extends StatelessWidget {
  final double width;
  final double height;
  const _Corners({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    const len = 24.0;
    const t = 3.0;
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          Positioned(top: 0, left: 0, child: _Corner(len, t, true, true)),
          Positioned(top: 0, right: 0, child: _Corner(len, t, false, true)),
          Positioned(bottom: 0, left: 0, child: _Corner(len, t, true, false)),
          Positioned(bottom: 0, right: 0, child: _Corner(len, t, false, false)),
        ],
      ),
    );
  }
}

class _Corner extends StatelessWidget {
  final double len, thickness;
  final bool left, top;
  const _Corner(this.len, this.thickness, this.left, this.top);

  @override
  Widget build(BuildContext context) => SizedBox(
        width: len,
        height: len,
        child: CustomPaint(painter: _CornerPainter(thickness, left, top)),
      );
}

class _CornerPainter extends CustomPainter {
  final double thickness;
  final bool left, top;
  const _CornerPainter(this.thickness, this.left, this.top);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFFD700)
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final x = left ? 0.0 : size.width;
    final y = top ? 0.0 : size.height;
    final dx = left ? size.width : -size.width;
    final dy = top ? size.height : -size.height;
    canvas.drawLine(Offset(x, y), Offset(x + dx, y), paint);
    canvas.drawLine(Offset(x, y), Offset(x, y + dy), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ── Found sheet ───────────────────────────────────────────────────────────────

class _FoundSheet extends StatefulWidget {
  final Food food;
  final bool isFromLocal;
  final String date;
  final String meal;
  final VoidCallback onAdded;
  final VoidCallback onRescan;

  const _FoundSheet({
    required this.food,
    required this.isFromLocal,
    required this.date,
    required this.meal,
    required this.onAdded,
    required this.onRescan,
  });

  @override
  State<_FoundSheet> createState() => _FoundSheetState();
}

class _FoundSheetState extends State<_FoundSheet> {
  bool _saving = false;

  Future<void> _addToLog() async {
    setState(() => _saving = true);
    await WorkoutDatabase.instance
        .addNutritionEntry(widget.date, widget.food.id, widget.meal, 1.0);
    if (mounted) widget.onAdded();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.food;
    final isOff = f.source == 'off';
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status row
          Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: Color(0xFF2ECC71), size: 18),
              const SizedBox(width: 6),
              Text(
                widget.isFromLocal ? 'Found in your library' : 'Product Found',
                style: const TextStyle(
                    color: Color(0xFF2ECC71),
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Product name
          Text(f.name,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          if (f.brand != null && f.brand!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(f.brand!,
                style: const TextStyle(
                    color: Color(0xFF888899), fontSize: 13)),
          ],
          const SizedBox(height: 2),
          Text('per ${f.servingSize.round()}${f.servingUnit}',
              style:
                  const TextStyle(color: Color(0xFF555577), fontSize: 12)),
          const SizedBox(height: 14),
          // Main macros
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF0D0D1A),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _macro('Calories', '${f.calories.round()}',
                    const Color(0xFFFFD700)),
                _macro('Protein', '${f.proteinG.toStringAsFixed(1)}g',
                    const Color(0xFF5DCAA5)),
                _macro('Carbs', '${f.carbsG.toStringAsFixed(1)}g',
                    const Color(0xFFEF9F27)),
                _macro('Fat', '${f.fatG.toStringAsFixed(1)}g',
                    const Color(0xFFF0997B)),
              ],
            ),
          ),
          // Extended detail for OFF-sourced foods (Step 8)
          if (isOff && (f.sugarG != null || f.sodiumMg != null || f.fiberG != null)) ...[
            const SizedBox(height: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D1A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  if (f.fiberG != null)
                    _miniMacro('Fiber', '${f.fiberG!.toStringAsFixed(1)}g'),
                  if (f.sugarG != null) ...[
                    if (f.fiberG != null) _dot(),
                    _miniMacro('Sugar', '${f.sugarG!.toStringAsFixed(1)}g'),
                  ],
                  if (f.sodiumMg != null) ...[
                    if (f.fiberG != null || f.sugarG != null) _dot(),
                    _miniMacro('Sodium',
                        '${f.sodiumMg!.round()}mg'),
                  ],
                ],
              ),
            ),
          ],
          // OFF attribution (mandatory when showing OFF data)
          if (isOff) ...[
            const SizedBox(height: 6),
            const Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    color: Color(0xFF444466), size: 12),
                SizedBox(width: 4),
                Text('via Open Food Facts',
                    style: TextStyle(
                        color: Color(0xFF444466), fontSize: 11)),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onRescan,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF888899),
                    side: const BorderSide(color: Color(0xFF333355)),
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Rescan'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _saving ? null : _addToLog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD700),
                    foregroundColor: Colors.black,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black))
                      : Text('Add to ${widget.meal}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _macro(String label, String value, Color color) => Column(
        children: [
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  color: Color(0xFF555577), fontSize: 11)),
        ],
      );

  Widget _miniMacro(String label, String value) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(
                  color: Color(0xFF555577), fontSize: 11)),
          const SizedBox(width: 3),
          Text(value,
              style: const TextStyle(
                  color: Color(0xFF888899),
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ],
      );

  Widget _dot() => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: Text('·',
            style: TextStyle(color: Color(0xFF333355), fontSize: 11)),
      );
}

// ── Incomplete-nutrition sheet ────────────────────────────────────────────────
// Shown when OFF found the product but one or more required macros are missing.

class _IncompleteSheet extends StatelessWidget {
  final Food partialFood;
  final String date;
  final String meal;
  final VoidCallback onAdded;
  final VoidCallback onRescan;

  const _IncompleteSheet({
    required this.partialFood,
    required this.date,
    required this.meal,
    required this.onAdded,
    required this.onRescan,
  });

  @override
  Widget build(BuildContext context) {
    final kb = MediaQuery.of(context).viewInsets.bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 20, 20, kb + 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.edit_note_rounded,
                  color: Color(0xFFFFD700), size: 18),
              const SizedBox(width: 6),
              const Text('Complete nutrition info',
                  style: TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${partialFood.name} was found on Open Food Facts but some '
            'nutrition values are missing. Fill them in to log this product.',
            style: const TextStyle(color: Color(0xFF888899), fontSize: 12),
          ),
          const SizedBox(height: 16),
          ManualNutritionForm(
            barcode: partialFood.barcode ?? '',
            date: date,
            meal: meal,
            prefill: partialFood,
            onAdded: onAdded,
            onRescan: onRescan,
          ),
          const SizedBox(height: 8),
          const Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  color: Color(0xFF444466), size: 12),
              SizedBox(width: 4),
              Text('via Open Food Facts',
                  style: TextStyle(color: Color(0xFF444466), fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Not-found sheet ───────────────────────────────────────────────────────────

class _NotFoundSheet extends StatelessWidget {
  final String barcode;
  final String date;
  final String meal;
  final VoidCallback onAdded;
  final VoidCallback onRescan;

  const _NotFoundSheet({
    required this.barcode,
    required this.date,
    required this.meal,
    required this.onAdded,
    required this.onRescan,
  });

  @override
  Widget build(BuildContext context) {
    final kb = MediaQuery.of(context).viewInsets.bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 20, 20, kb + 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.search_off_rounded,
                  color: Color(0xFFE67E22), size: 18),
              const SizedBox(width: 6),
              const Text('Product Not Found',
                  style: TextStyle(
                      color: Color(0xFFE67E22),
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Barcode $barcode wasn\'t found on Open Food Facts.\nEnter the nutrition info below to log it.',
            style: const TextStyle(color: Color(0xFF888899), fontSize: 12),
          ),
          const SizedBox(height: 16),
          ManualNutritionForm(
            barcode: barcode,
            date: date,
            meal: meal,
            onAdded: onAdded,
            onRescan: onRescan,
          ),
        ],
      ),
    );
  }
}
