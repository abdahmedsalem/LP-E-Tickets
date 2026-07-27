import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/auth/payment_proof_http_headers.dart';
import '../../core/config/odoo_api_config.dart';

/// Télécharge le binaire d’une preuve (pièce jointe Odoo, URL absolue ou relative).
class PaymentProofLoader {
  PaymentProofLoader._();

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 45),
      responseType: ResponseType.bytes,
      validateStatus: (s) => s != null && s < 600,
    ),
  );

  static String? resolveProofUrl(String? url) {
    final raw = url?.trim();
    if (raw == null || raw.isEmpty || raw == 'false') return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    final base = OdooApiConfig.baseUrlTrimmed;
    if (base.isEmpty) return raw;
    return raw.startsWith('/') ? '$base$raw' : '$base/$raw';
  }

  static Future<Uint8List?> fetchBytes(String? url) async {
    final resolved = resolveProofUrl(url);
    if (resolved == null) return null;
    try {
      final headers = await paymentProofHttpHeaders();
      final response = await _dio.get<List<int>>(
        resolved,
        options: Options(headers: headers),
      );
      if (response.statusCode != 200 || response.data == null) return null;
      final data = response.data!;
      if (data.isEmpty) return null;
      return Uint8List.fromList(data);
    } catch (_) {
      return null;
    }
  }
}
