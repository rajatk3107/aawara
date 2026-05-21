import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class OpenFoodFactsClient {
  static const _baseUrl = 'https://world.openfoodfacts.org/api/v2/product';
  static const _userAgent = 'Aawara-FitnessApp/1.0 (aawara-fitness)';
  static const _fields =
      'product_name,product_name_en,brands,nutriments,serving_size';
  static const _timeout = Duration(seconds: 10);
  static const _maxRetries = 2;

  // Returns the OFF product JSON object, or null if not found / invalid.
  Future<Map<String, dynamic>?> lookupBarcode(String barcode) async {
    final uri = Uri.parse('$_baseUrl/$barcode.json?fields=$_fields');

    for (int attempt = 0; attempt <= _maxRetries; attempt++) {
      try {
        final resp = await http.get(
          uri,
          headers: {'User-Agent': _userAgent},
        ).timeout(_timeout);

        if (resp.statusCode == 429) {
          if (attempt < _maxRetries) {
            await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
            continue;
          }
          throw Exception('Rate limited by Open Food Facts');
        }

        if (resp.statusCode != 200) return null;

        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        if (data['status'] != 1) return null;

        return data['product'] as Map<String, dynamic>?;
      } on TimeoutException {
        if (attempt < _maxRetries) {
          await Future.delayed(Duration(seconds: attempt + 1));
          continue;
        }
        rethrow;
      }
    }
    return null;
  }
}
