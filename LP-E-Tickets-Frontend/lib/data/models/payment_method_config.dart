import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

class PaymentMethodConfig {
  const PaymentMethodConfig({
    this.id,
    required this.code,
    required this.name,
    required this.merchantCode,
    this.instructions,
    this.colorHex,
    this.logoData,
  });

  final int? id;
  final String code;
  final String name;
  final String merchantCode;
  final String? instructions;
  final String? colorHex;
  final String? logoData;

  static const fallbackMethods = [
    PaymentMethodConfig(
      code: 'bankily',
      name: 'Bankily',
      merchantCode: '123456',
      colorHex: '#43A047',
    ),
    PaymentMethodConfig(
      code: 'sedad',
      name: 'Sedad',
      merchantCode: '222222',
      colorHex: '#0284C7',
    ),
    PaymentMethodConfig(
      code: 'masrivi',
      name: 'Masrivi',
      merchantCode: '333333',
      colorHex: '#D97706',
    ),
  ];

  factory PaymentMethodConfig.fromJson(Map<String, dynamic> json) {
    final code = _clean(json['code']);
    final name = _clean(json['display_name']) ?? _clean(json['name']);
    final merchantCode = _clean(json['merchant_code']);
    if (code == null || name == null || merchantCode == null) {
      throw const FormatException('Moyen de paiement incomplet.');
    }
    return PaymentMethodConfig(
      id: _intOrNull(json['id']),
      code: code.toLowerCase(),
      name: name,
      merchantCode: merchantCode,
      instructions: _clean(json['instructions']),
      colorHex: _clean(json['color_hex']),
      logoData: _clean(json['logo_data']) ?? _clean(json['image_128']),
    );
  }

  Uint8List? get logoBytes {
    final raw = logoData?.trim();
    if (raw == null || raw.isEmpty) return null;
    final normalized = raw.contains(',') ? raw.split(',').last : raw;
    try {
      return base64Decode(normalized);
    } catch (_) {
      return null;
    }
  }

  Color get color {
    final raw = colorHex?.trim();
    if (raw == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(raw)) {
      return const Color(0xFF43A047);
    }
    return Color(int.parse('FF${raw.substring(1)}', radix: 16));
  }

  String get initial {
    final cleanName = name.trim();
    if (cleanName.isEmpty) return '?';
    return String.fromCharCode(cleanName.runes.first).toUpperCase();
  }

  static String? _clean(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty || text == 'false' ? null : text;
  }

  static int? _intOrNull(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString().trim() ?? '');
  }
}
