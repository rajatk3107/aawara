import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:uuid/uuid.dart';
import '../models/nutrition_models.dart';
import '../../workout/database/workout_database.dart';

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
    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue == null) return;

    setState(() {
      _scanning = false;
      _loading = true;
      _error = null;
    });

    final code = barcode!.rawValue!;
    try {
      final food = await _lookupBarcode(code);
      if (!mounted) return;
      if (food != null) {
        _showFoundSheet(food);
      } else {
        setState(() {
          _error = 'Product not found for barcode $code.\nTry another product or create it manually.';
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Network error. Check your connection and try again.';
          _loading = false;
        });
      }
    }
  }

  Future<Food?> _lookupBarcode(String barcode) async {
    final url = Uri.parse(
        'https://world.openfoodfacts.org/api/v0/product/$barcode.json');
    final resp = await http
        .get(url, headers: {'User-Agent': 'Aawara-FitnessApp/1.0'}).timeout(
      const Duration(seconds: 12),
    );
    if (resp.statusCode != 200) return null;

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    if (data['status'] != 1) return null;

    final product = data['product'] as Map<String, dynamic>;
    final nutriments =
        (product['nutriments'] as Map<String, dynamic>?) ?? {};

    final name = ((product['product_name'] as String?) ??
            (product['product_name_en'] as String?) ??
            '')
        .trim();
    if (name.isEmpty) return null;

    double cal = _nutrient(nutriments, 'energy-kcal_100g') ??
        ((_nutrient(nutriments, 'energy_100g') ?? 0) / 4.184);
    final protein = _nutrient(nutriments, 'proteins_100g') ?? 0;
    final carbs = _nutrient(nutriments, 'carbohydrates_100g') ?? 0;
    final fat = _nutrient(nutriments, 'fat_100g') ?? 0;
    final fiber = _nutrient(nutriments, 'fiber_100g');

    return Food(
      id: const Uuid().v4(),
      name: name,
      calories: cal,
      proteinG: protein,
      carbsG: carbs,
      fatG: fat,
      fiberG: fiber,
      servingSize: 100,
      servingUnit: 'g',
      isCustom: true,
    );
  }

  double? _nutrient(Map<String, dynamic> n, String key) {
    final v = n[key];
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  void _showFoundSheet(Food food) {
    setState(() => _loading = false);
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isDismissible: false,
      builder: (_) => _FoundSheet(
        food: food,
        date: widget.date,
        meal: widget.meal,
        onAdded: () => Navigator.pop(context, true),
        onRescan: () {
          setState(() {
            _scanning = true;
            _loading = false;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
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
                    onPressed: () => Navigator.pop(context),
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
                    icon: const Icon(Icons.flash_on_rounded,
                        color: Colors.white),
                    onPressed: () => _controller.toggleTorch(),
                  ),
                ],
              ),
            ),
          ),
          // Loading
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
          // Error
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
                    const Icon(Icons.qr_code_scanner_rounded,
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
                          onPressed: () => setState(() {
                            _error = null;
                            _scanning = true;
                          }),
                          child: const Text('Try Again',
                              style: TextStyle(color: Color(0xFFFFD700))),
                        ),
                        const SizedBox(width: 12),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
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
        child: CustomPaint(
          painter: _CornerPainter(thickness, left, top),
        ),
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

// ── Found sheet ────────────────────────────────────────────────────────────────

class _FoundSheet extends StatefulWidget {
  final Food food;
  final String date;
  final String meal;
  final VoidCallback onAdded;
  final VoidCallback onRescan;

  const _FoundSheet({
    required this.food,
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
    final db = WorkoutDatabase.instance;

    // Reuse existing food if it's already in the DB, otherwise create it.
    Food? existing = await db.getFoodByExactName(widget.food.name);
    existing ??= await db.createCustomFood(widget.food);

    await db.addNutritionEntry(widget.date, existing.id, widget.meal, 1.0);
    if (mounted) widget.onAdded();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.food;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: Color(0xFF2ECC71), size: 18),
              const SizedBox(width: 6),
              const Text('Product Found',
                  style: TextStyle(
                      color: Color(0xFF2ECC71),
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 10),
          Text(f.name,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          const Text('per 100g',
              style: TextStyle(color: Color(0xFF555577), fontSize: 12)),
          const SizedBox(height: 16),
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
                    const Color(0xFF3498DB)),
                _macro('Carbs', '${f.carbsG.toStringAsFixed(1)}g',
                    const Color(0xFF2ECC71)),
                _macro('Fat', '${f.fatG.toStringAsFixed(1)}g',
                    const Color(0xFFE67E22)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onRescan();
                  },
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
                          style: const TextStyle(fontWeight: FontWeight.bold)),
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
}
