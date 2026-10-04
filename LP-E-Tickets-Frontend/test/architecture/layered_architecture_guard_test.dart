import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('core does not import data or feature modules', () {
    final coreFiles = Directory('lib/core')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    final violations = <String>[];
    for (final file in coreFiles) {
      final source = file.readAsStringSync();
      if (RegExp(
        r'''(?:import|export)\s+['"][^'"]*(?:data|features)/''',
      ).hasMatch(source)) {
        violations.add(file.path);
      }
    }

    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('domain does not depend on framework, data or presentation layers', () {
    final domainFiles = Directory('lib/domain')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    final forbidden = RegExp(
      r'''(?:import|export)\s+['"][^'"]*(?:core|data|features|shared)/''',
    );
    final violations = domainFiles
        .where((file) => forbidden.hasMatch(file.readAsStringSync()))
        .map((file) => file.path)
        .toList();
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('application code does not import legacy data model paths', () {
    final appFiles = <File>[
      ...Directory('lib/features').listSync(recursive: true).whereType<File>(),
      ...Directory('lib/shared').listSync(recursive: true).whereType<File>(),
      ...Directory('lib/app').listSync(recursive: true).whereType<File>(),
    ].where((file) => file.path.endsWith('.dart'));
    final violations = appFiles
        .where(
          (file) => RegExp(
            r'''(?:import|export)\s+['"][^'"]*data/models/''',
          ).hasMatch(file.readAsStringSync()),
        )
        .map((file) => file.path)
        .toList();
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('domain models remain free of API and persistence serialization', () {
    final modelFiles = Directory('lib/domain/models')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    final forbidden = RegExp(
      r'''(?:import|export)\s+['"][^'"]*(?:core|data|features)/|(?:fromJson|toJson|jsonDecode|jsonEncode|fromWalletPayload)\s*\(''',
    );
    final violations = modelFiles
        .where((file) => forbidden.hasMatch(file.readAsStringSync()))
        .map((file) => file.path)
        .toList();
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('data layer does not import feature modules', () {
    final dataFiles = Directory('lib/data')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    final violations = <String>[];
    for (final file in dataFiles) {
      final source = file.readAsStringSync();
      if (RegExp(r'''import\s+['"][^'"]*features/''').hasMatch(source) ||
          RegExp(r'''export\s+['"][^'"]*features/''').hasMatch(source)) {
        violations.add(file.path);
      }
    }

    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('feature presentation layers do not import data services', () {
    final uiLayers = Directory('lib/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (file) =>
              file.path.contains('/screens/') ||
              file.path.contains('/controllers/') ||
              file.path.contains('/bloc/'),
        );

    final violations = <String>[];
    for (final file in uiLayers) {
      if (file.readAsStringSync().contains('data/services/')) {
        violations.add(file.path);
      }
    }

    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test(
    'feature controllers and blocs do not depend on concrete data repositories',
    () {
      final files = Directory('lib/features')
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (file) =>
                file.path.endsWith('.dart') &&
                (file.path.contains('/controllers/') ||
                    file.path.contains('/bloc/')),
          );
      final violations = files
          .where(
            (file) => file.readAsStringSync().contains('data/repositories/'),
          )
          .map((file) => file.path)
          .toList();
      expect(violations, isEmpty, reason: violations.join('\n'));
    },
  );

  test('transfer controllers depend on domain repository contracts', () {
    final controllers = Directory(
      'lib/features/transfer/controllers',
    ).listSync().whereType<File>().where((file) => file.path.endsWith('.dart'));
    final violations = <String>[];
    for (final file in controllers) {
      final source = file.readAsStringSync();
      if (source.contains('data/repositories/')) violations.add(file.path);
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test(
    'migrated purchase, history and portfolio controllers use domain contracts',
    () {
      final controllers = <File>[
        File('lib/features/purchases/controllers/purchase_controller.dart'),
        File('lib/features/history/controllers/history_controller.dart'),
        File('lib/features/portfolio/controllers/portfolio_controller.dart'),
      ];
      final violations = controllers
          .where(
            (file) => file.readAsStringSync().contains('data/repositories/'),
          )
          .map((file) => file.path)
          .toList();
      expect(violations, isEmpty, reason: violations.join('\n'));
    },
  );

  test('feature screens do not create Odoo clients or invoke API services', () {
    final screens = Directory('lib/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.contains('/screens/'));
    final directApiUse = RegExp(
      r'OdooFueltokenFacade\s*\(|OdooJsonRpcClient\s*\(|'
      r'AcpecFueltokenJsonRpcApi\s*\(|OdooAuthService\.instance|'
      r'AcpecCarnetCatalogService\.instance|\.callRoute\s*\(|'
      r'\.postJsonRpc\s*\(',
    );

    final violations = <String>[];
    for (final screen in screens) {
      final content = screen.readAsStringSync();
      if (directApiUse.hasMatch(content)) violations.add(screen.path);
    }

    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('feature presentation does not decode backend response envelopes', () {
    final files = Directory('lib/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where(
          (file) =>
              file.path.contains('/screens/') ||
              file.path.contains('/bloc/') ||
              file.path.contains('/controllers/'),
        );
    final transportAccess = RegExp(
      r'''\[['"](?:data|result|records|items|access_token|refresh_token|qr_max_amount|transaction_reference)['"]\]''',
    );
    final violations = files
        .where((file) => transportAccess.hasMatch(file.readAsStringSync()))
        .map((file) => file.path)
        .toList();
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('auth and QR screens consume typed repository results', () {
    final screens = [
      File('lib/features/auth/screens/register_screen.dart'),
      File('lib/features/auth/screens/register_verify_otp_screen.dart'),
      File('lib/features/qr/generation/screens/emit_qr_screen.dart'),
    ];
    final violations = <String>[];
    for (final screen in screens) {
      final source = screen.readAsStringSync();
      if (source.contains("['data']") ||
          source.contains("['access_token']") ||
          source.contains("['qr_max_amount']") ||
          source.contains("['transaction_reference']") ||
          source.contains('_extractTokens')) {
        violations.add(screen.path);
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('QR, transfer and purchase screens do not depend on data services', () {
    const migratedFeatures = {'qr', 'transfer', 'purchases'};
    final screens = Directory('lib/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.contains('/screens/'))
        .where((file) {
          final segments = file.uri.pathSegments;
          final featureIndex = segments.indexOf('features');
          return featureIndex >= 0 &&
              featureIndex + 1 < segments.length &&
              migratedFeatures.contains(segments[featureIndex + 1]);
        });

    final violations = <String>[];
    for (final screen in screens) {
      final content = screen.readAsStringSync();
      if (content.contains('data/services/') ||
          content.contains('data/repositories/')) {
        violations.add(screen.path);
      }
    }

    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
