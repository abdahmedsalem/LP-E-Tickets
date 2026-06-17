import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;

import '../../core/config/app_environment.dart';
import '../../core/config/diagnostic_config.dart';
import '../../core/config/odoo_fueltoken_rpc_config.dart';
import '../models/carnet_type.dart';
import 'acpec_carnet_types_mapper.dart';
import 'odoo_fueltoken_facade.dart';
import 'odoo_jsonrpc_client.dart';

/// Résultat d’un chargement faces, wallet et achats (diagnostic UI / logs).
///
/// Si [facesOnlyQuery] est vrai (écran admin « Types »), enchaîne les routes
/// types carnets puis faces disponibles.
class AcpecCarnetCatalogLoadResult {
  const AcpecCarnetCatalogLoadResult({
    required this.types,
    this.facesOnlyQuery = false,
    this.carnetTypesFromAdminList = false,
    this.carnetTypesError,
    this.carnetTypesResponsePreview,
    this.facesError,
    this.facesResponsePreview,
    this.walletError,
    this.walletResponsePreview,
    this.purchasesError,
    this.purchasesResponsePreview,
  });

  final List<CarnetType> types;

  /// Vrai si la liste des types provient de la route admin dédiée.
  final bool carnetTypesFromAdminList;

  /// Erreur réseau ou métier sur le chargement des types ; null si succès.
  final String? carnetTypesError;

  /// Aperçu JSON du `result` carnet-types (diagnostic).
  final String? carnetTypesResponsePreview;

  /// Chargement admin « types » : pas d’appels wallet / liste achats.
  final bool facesOnlyQuery;

  /// Erreur sur le chargement des faces ; null si succès.
  final String? facesError;
  final String? facesResponsePreview;

  /// Erreur réseau ou métier sur le portefeuille ; null si succès.
  final String? walletError;

  /// Aperçu JSON du portefeuille (diagnostic).
  final String? walletResponsePreview;

  final String? purchasesError;
  final String? purchasesResponsePreview;

  /// Aucun type affichable et la ou les sources utilisées ont échoué.
  bool get bothRpcFailed {
    if (facesOnlyQuery) {
      return types.isEmpty && facesError != null && carnetTypesError != null;
    }
    return types.isEmpty &&
        facesError != null &&
        walletError != null &&
        purchasesError != null;
  }

  bool get hasAnyRpcSuccess {
    if (facesOnlyQuery) {
      return facesError == null || carnetTypesError == null;
    }
    return facesError == null ||
        walletError == null ||
        purchasesError == null ||
        carnetTypesError == null;
  }

  String _sanitize(String msg) => msg.replaceAll('Exception: ', '').trim();

  String _shortForClient(String message) {
    var s = message
        .replaceAll('OdooJsonRpcException', '')
        .replaceAll('(', '')
        .replaceAll(')', '')
        .trim();
    if (s.length > 220) {
      return '${s.substring(0, 220)}…';
    }
    return s;
  }

  /// [includeApiBodies] : `true` pour support / debug (corps JSON). Sinon résumé métier uniquement.
  String buildDiagnosticReport({bool includeApiBodies = false}) {
    if (!includeApiBodies) {
      final b = StringBuffer()
        ..writeln('Résumé')
        ..writeln('• Types affichés : ${types.length}')
        ..writeln(
          '• Types carnets (RPC dédié) : ${carnetTypesError == null ? "OK ou inférence" : "erreur"}',
        )
        ..writeln('• Faces (mobile) : ${facesError == null ? "OK" : "erreur"}');
      if (facesOnlyQuery) {
        b.writeln(
          '• Solde / liste achats : non interrogés (écran admin types : faces uniquement).',
        );
        if (carnetTypesFromAdminList) {
          b.writeln('• Source types : API admin carnet-types/list.');
        }
      } else {
        b
          ..writeln('• Solde : ${walletError == null ? "OK" : "erreur"}')
          ..writeln(
            '• Commandes : ${purchasesError == null ? "OK" : "erreur"}',
          );
      }
      if (carnetTypesError != null) {
        b.writeln('  ${_shortForClient(carnetTypesError!)}');
      }
      if (facesError != null) {
        b.writeln('  ${_shortForClient(facesError!)}');
      }
      if (!facesOnlyQuery && walletError != null) {
        b.writeln('  ${_shortForClient(walletError!)}');
      }
      if (!facesOnlyQuery && purchasesError != null) {
        b.writeln('  ${_shortForClient(purchasesError!)}');
      }
      b
        ..writeln()
        ..writeln(
          'En cas de difficulté : vérifiez la connexion, reconnectez-vous, '
          'ou contactez le support.',
        );
      return b.toString();
    }

    final b = StringBuffer()
      ..writeln('— Types de carnets (mobile) —')
      ..writeln(
        carnetTypesError != null
            ? 'Erreur: ${_sanitize(carnetTypesError!)}'
            : 'OK ou non requis (démo)',
      )
      ..writeln(
        carnetTypesResponsePreview != null &&
                carnetTypesResponsePreview!.isNotEmpty
            ? carnetTypesResponsePreview!
            : '(pas de corps enregistré)',
      )
      ..writeln()
      ..writeln('— Faces disponibles (mobile) —')
      ..writeln(facesError != null ? 'Erreur: ${_sanitize(facesError!)}' : 'OK')
      ..writeln(
        facesResponsePreview != null && facesResponsePreview!.isNotEmpty
            ? facesResponsePreview!
            : '(pas de corps enregistré)',
      )
      ..writeln();
    if (!facesOnlyQuery) {
      b
        ..writeln('— Solde (mobile) —')
        ..writeln(
          walletError != null ? 'Erreur: ${_sanitize(walletError!)}' : 'OK',
        )
        ..writeln(
          walletResponsePreview != null && walletResponsePreview!.isNotEmpty
              ? walletResponsePreview!
              : '(pas de corps enregistré)',
        )
        ..writeln()
        ..writeln('— Commandes (mobile) —')
        ..writeln(
          purchasesError != null
              ? 'Erreur: ${_sanitize(purchasesError!)}'
              : 'OK',
        )
        ..writeln(
          purchasesResponsePreview != null &&
                  purchasesResponsePreview!.isNotEmpty
              ? purchasesResponsePreview!
              : '(pas de corps enregistré)',
        )
        ..writeln();
    }
    b.writeln('Types détectés : ${types.length}');
    return b.toString();
  }
}

/// Infère les types de carnets visibles côté mobile à partir des APIs ACPEC
/// (`/api/acpec/fueltoken/v1/...`) : d’abord **`/mobile/carnet-types`** (`params: {}`,
/// en-tête Bearer si présent), puis complément par **`/mobile/faces`**, wallet et achats
/// si la route catalogue n’est pas exploitable.
class AcpecCarnetCatalogService {
  AcpecCarnetCatalogService._();

  static final AcpecCarnetCatalogService instance =
      AcpecCarnetCatalogService._();

  /// Dernier chargement (écrans admin / debug).
  static AcpecCarnetCatalogLoadResult? lastLoadResult;

  /// Toujours faux : le catalogue types/faces provient d’Odoo (pas de JWT catalogue séparé).
  static bool lastCatalogTypesFromAdminList = false;

  static const int _kLogPreviewMaxChars = 12000;

  int _int(dynamic v, [int d = 0]) {
    if (v == null) return d;
    if (v is int) return v;
    if (v is num) return v.round();
    final s = v.toString().trim();
    if (s.isEmpty) return d;
    final x = double.tryParse(s.replaceAll(',', '.'));
    if (x != null) return x.round();
    return int.tryParse(s.split('.').first) ?? d;
  }

  Map<String, dynamic> _unwrapAcpec(dynamic result) {
    if (result is! Map) return {};
    var m = Map<String, dynamic>.from(result);
    if (m['ok'] == false) {
      throw Exception(m['message']?.toString() ?? 'Réponse ACPEC invalide.');
    }
    final data = m['data'];
    if (data is Map) {
      m = Map<String, dynamic>.from(data);
    }
    if (m['ok'] == false) {
      throw Exception(m['message']?.toString() ?? 'Réponse ACPEC invalide.');
    }
    return m;
  }

  void _absorbRow(Map<String, dynamic> row, Map<String, _CarnetAgg> acc) {
    final rawId = row['carnet_type_id'] ?? row['type_id'];
    var idStr = rawId?.toString().trim() ?? '';
    if (idStr.isEmpty) {
      final ct = row['carnet_type']?.toString().trim();
      if (ct != null && ct.isNotEmpty) idStr = ct;
    }
    if (idStr.isEmpty || idStr == '0') return;

    final code = row['carnet_type_code']?.toString().trim().isNotEmpty == true
        ? row['carnet_type_code'].toString()
        : (row['code']?.toString().trim().isNotEmpty == true
              ? row['code'].toString()
              : 'T$idStr');
    final faceValue = _int(
      row['face_value'] ??
          row['nominal'] ??
          row['ticket_value'] ??
          row['unit_value'],
    );
    if (faceValue <= 0) return;

    final size = math.max(
      1,
      _int(
        row['carnet_size'] ??
            row['size'] ??
            row['face_count'] ??
            row['tickets_per_carnet'] ??
            row['ticket_count'] ??
            row['qty_per_carnet'],
        1,
      ),
    );
    final validityDays = math.max(
      1,
      _int(row['validity_days'] ?? row['validity_after_validation_days'], 365),
    );
    final name =
        row['carnet_type_name']?.toString() ?? row['name']?.toString() ?? '';

    final prev = acc[idStr];
    if (prev == null) {
      acc[idStr] = _CarnetAgg(
        idStr: idStr,
        code: code,
        name: name,
        faceValue: faceValue,
        size: size,
        validityDays: validityDays,
      );
      return;
    }
    acc[idStr] = _CarnetAgg(
      idStr: idStr,
      code: code.isNotEmpty && !code.startsWith('T') ? code : prev.code,
      name: name.isNotEmpty ? name : prev.name,
      faceValue: faceValue,
      size: size > 1 ? size : prev.size,
      validityDays: validityDays != 365 ? validityDays : prev.validityDays,
    );
  }

  void _walk(dynamic node, Map<String, _CarnetAgg> acc) {
    if (node is Map) {
      final m = Map<String, dynamic>.from(node);
      if (m.containsKey('carnet_type_id') || m.containsKey('type_id')) {
        _absorbRow(m, acc);
      }
      for (final v in m.values) {
        _walk(v, acc);
      }
    } else if (node is List) {
      for (final e in node) {
        _walk(e, acc);
      }
    }
  }

  List<CarnetType> _toTypes(Map<String, _CarnetAgg> acc, String companyId) {
    final out =
        acc.values
            .map(
              (a) => CarnetType(
                id: a.idStr,
                code: a.code,
                name: a.displayName,
                size: a.size,
                faceValue: a.faceValue,
                companyId: companyId,
                active: true,
                validityDays: a.validityDays,
              ),
            )
            .toList()
          ..sort((x, y) => x.faceValue.compareTo(y.faceValue));
    return out;
  }

  String _jsonPreview(dynamic value) {
    if (value == null) return '';
    try {
      final s = const JsonEncoder.withIndent('  ').convert(value);
      if (s.length <= _kLogPreviewMaxChars) return s;
      return '${s.substring(0, _kLogPreviewMaxChars)}…\n[tronqué $_kLogPreviewMaxChars car.]';
    } catch (_) {
      return value.toString();
    }
  }

  void _logRpc(String tag, dynamic payload) {
    if (!DiagnosticConfig.showTechnicalDiagnostics) {
      return;
    }
    developer.log(_jsonPreview(payload), name: 'AcpecCarnetCatalog.$tag');
  }

  /// Types carnets : route admin list en priorité si [preferAdminList], sinon mobile.
  Future<
    ({
      List<CarnetType>? list,
      String? err,
      String? preview,
      bool usedAdminRoute,
    })
  >
  _tryFetchCarnetTypesRpc(
    String companyId, {
    bool preferAdminList = false,
  }) async {
    String? preview;

    if (preferAdminList) {
      try {
        final raw = await OdooFueltokenFacade().adminCarnetTypesList(
          const <String, dynamic>{},
        );
        _logRpc('adminCarnetTypesList.response', raw);
        preview = _jsonPreview(raw);
        final list = AcpecCarnetTypesMapper.tryListFromRpc(
          raw,
          companyId: companyId,
          includeInactiveRows: true,
        );
        if (list != null) {
          return (
            list: list,
            err: null,
            preview: preview,
            usedAdminRoute: true,
          );
        }
      } on OdooJsonRpcException catch (e, st) {
        if (DiagnosticConfig.showTechnicalDiagnostics) {
          developer.log(
            '$e\n$st',
            name: 'AcpecCarnetCatalog.adminCarnetTypesList',
          );
        }
      } catch (e, st) {
        if (DiagnosticConfig.showTechnicalDiagnostics) {
          developer.log(
            '$e\n$st',
            name: 'AcpecCarnetCatalog.adminCarnetTypesList',
          );
        }
      }
    }

    try {
      final raw = await OdooFueltokenFacade().carnetTypes(
        const <String, dynamic>{},
      );
      _logRpc('carnetTypes.response', raw);
      preview = _jsonPreview(raw);
      final list = AcpecCarnetTypesMapper.tryListFromRpc(
        raw,
        companyId: companyId,
      );
      return (list: list, err: null, preview: preview, usedAdminRoute: false);
    } on OdooJsonRpcException catch (e, st) {
      if (DiagnosticConfig.showTechnicalDiagnostics) {
        developer.log('$e\n$st', name: 'AcpecCarnetCatalog.carnetTypes');
      }
      return (
        list: null,
        err: e.toString(),
        preview: preview,
        usedAdminRoute: false,
      );
    } catch (e, st) {
      if (DiagnosticConfig.showTechnicalDiagnostics) {
        developer.log('$e\n$st', name: 'AcpecCarnetCatalog.carnetTypes');
      }
      return (
        list: null,
        err: e.toString(),
        preview: preview,
        usedAdminRoute: false,
      );
    }
  }

  /// Charge les types (démo locale ou inférence Odoo) et remplit [lastLoadResult].
  Future<AcpecCarnetCatalogLoadResult> loadCatalog({
    required String companyId,
  }) async {
    lastCatalogTypesFromAdminList = false;
    if (!AppEnvironment.useAcpecLiveData) {
      const r = AcpecCarnetCatalogLoadResult(types: []);
      lastLoadResult = r;
      return r;
    }

    final agg = <String, _CarnetAgg>{};
    String? ctErr;
    String? ctPreview;
    final ctRpc = await _tryFetchCarnetTypesRpc(companyId);
    ctPreview = ctRpc.preview;
    ctErr = ctRpc.err;
    final apiTypes = ctRpc.list;
    final ctFromAdmin = ctRpc.usedAdminRoute;
    String? fErr;
    String? fPreview;
    String? wErr;
    String? wPreview;
    String? pErr;
    String? pPreview;

    try {
      final fRaw = await OdooFueltokenFacade().faces(const <String, dynamic>{});
      _logRpc('faces.response', fRaw);
      fPreview = _jsonPreview(fRaw);
      _walk(_unwrapAcpec(fRaw), agg);
    } on OdooJsonRpcException catch (e, st) {
      fErr = e.toString();
      if (DiagnosticConfig.showTechnicalDiagnostics) {
        developer.log('$e\n$st', name: 'AcpecCarnetCatalog.faces');
      }
    } catch (e, st) {
      fErr = e.toString();
      if (DiagnosticConfig.showTechnicalDiagnostics) {
        developer.log('$e\n$st', name: 'AcpecCarnetCatalog.faces');
      }
    }

    try {
      final wRaw = await OdooFueltokenFacade().walletCurrent(
        Map<String, dynamic>.from(
          OdooFueltokenRpcConfig.walletCurrentDefaultParams,
        ),
      );
      _logRpc('walletCurrent.response', wRaw);
      wPreview = _jsonPreview(wRaw);
      _walk(_unwrapAcpec(wRaw), agg);
    } on OdooJsonRpcException catch (e, st) {
      wErr = e.toString();
      if (DiagnosticConfig.showTechnicalDiagnostics) {
        developer.log('$e\n$st', name: 'AcpecCarnetCatalog.walletCurrent');
      }
    } catch (e, st) {
      wErr = e.toString();
      if (DiagnosticConfig.showTechnicalDiagnostics) {
        developer.log('$e\n$st', name: 'AcpecCarnetCatalog.walletCurrent');
      }
    }

    try {
      final pRaw = await OdooFueltokenFacade().purchasesList(
        const <String, dynamic>{},
      );
      _logRpc('purchasesList.response', pRaw);
      pPreview = _jsonPreview(pRaw);
      _walk(_unwrapAcpec(pRaw), agg);
    } on OdooJsonRpcException catch (e, st) {
      pErr = e.toString();
      if (DiagnosticConfig.showTechnicalDiagnostics) {
        developer.log('$e\n$st', name: 'AcpecCarnetCatalog.purchasesList');
      }
    } catch (e, st) {
      pErr = e.toString();
      if (DiagnosticConfig.showTechnicalDiagnostics) {
        developer.log('$e\n$st', name: 'AcpecCarnetCatalog.purchasesList');
      }
    }

    final inferred = _toTypes(agg, companyId);
    final types = apiTypes != null
        ? (List<CarnetType>.from(apiTypes)
            ..sort((a, b) => a.faceValue.compareTo(b.faceValue)))
        : inferred;
    final result = AcpecCarnetCatalogLoadResult(
      types: types,
      facesError: fErr,
      facesResponsePreview: fPreview,
      walletError: wErr,
      walletResponsePreview: wPreview,
      purchasesError: pErr,
      purchasesResponsePreview: pPreview,
      carnetTypesError: ctErr,
      carnetTypesResponsePreview: ctPreview,
      carnetTypesFromAdminList: ctFromAdmin,
    );
    lastLoadResult = result;
    if (DiagnosticConfig.showTechnicalDiagnostics) {
      developer.log(
        'Résumé: carnetTypesErr=${ctErr != null}, facesErr=${fErr != null}, walletErr=${wErr != null}, purchErr=${pErr != null}, '
        'types=${types.length}',
        name: 'AcpecCarnetCatalog',
      );
    }
    return result;
  }

  /// Chargement admin « Types de ticket » : types puis faces uniquement.
  Future<AcpecCarnetCatalogLoadResult> loadCatalogFacesOnly({
    required String companyId,
  }) async {
    lastCatalogTypesFromAdminList = false;
    if (!AppEnvironment.useAcpecLiveData) {
      const r = AcpecCarnetCatalogLoadResult(types: [], facesOnlyQuery: true);
      lastLoadResult = r;
      return r;
    }

    final agg = <String, _CarnetAgg>{};
    String? ctErr;
    String? ctPreview;
    final ctRpc = await _tryFetchCarnetTypesRpc(
      companyId,
      preferAdminList: true,
    );
    ctPreview = ctRpc.preview;
    ctErr = ctRpc.err;
    final apiTypes = ctRpc.list;
    final ctFromAdmin = ctRpc.usedAdminRoute;
    String? fErr;
    String? fPreview;

    try {
      final fRaw = await OdooFueltokenFacade().faces(const <String, dynamic>{});
      _logRpc('faces.response', fRaw);
      fPreview = _jsonPreview(fRaw);
      _walk(_unwrapAcpec(fRaw), agg);
    } on OdooJsonRpcException catch (e, st) {
      fErr = e.toString();
      if (DiagnosticConfig.showTechnicalDiagnostics) {
        developer.log('$e\n$st', name: 'AcpecCarnetCatalog.faces');
      }
    } catch (e, st) {
      fErr = e.toString();
      if (DiagnosticConfig.showTechnicalDiagnostics) {
        developer.log('$e\n$st', name: 'AcpecCarnetCatalog.faces');
      }
    }

    final inferred = _toTypes(agg, companyId);
    final types = apiTypes != null
        ? (List<CarnetType>.from(apiTypes)
            ..sort((a, b) => a.faceValue.compareTo(b.faceValue)))
        : inferred;
    final result = AcpecCarnetCatalogLoadResult(
      types: types,
      facesOnlyQuery: true,
      facesError: fErr,
      facesResponsePreview: fPreview,
      carnetTypesError: ctErr,
      carnetTypesResponsePreview: ctPreview,
      carnetTypesFromAdminList: ctFromAdmin,
    );
    lastLoadResult = result;
    if (DiagnosticConfig.showTechnicalDiagnostics) {
      developer.log(
        'Résumé (admin types): carnetTypesErr=${ctErr != null}, facesErr=${fErr != null}, types=${types.length}',
        name: 'AcpecCarnetCatalog',
      );
    }
    return result;
  }

  /// Types pour l’écran admin : en ACPEC live, uniquement [loadCatalogFacesOnly] ;
  /// pour les achats client l’agrégation complète reste [loadCatalog].
  Future<AcpecCarnetCatalogLoadResult> loadAdminCatalog({
    required String companyId,
  }) async {
    lastCatalogTypesFromAdminList = false;
    if (!AppEnvironment.useAcpecLiveData) {
      const r = AcpecCarnetCatalogLoadResult(types: []);
      lastLoadResult = r;
      return r;
    }

    return loadCatalogFacesOnly(companyId: companyId);
  }

  /// Types proposés à l’achat : en démo locale, dépôt mémoire ; en ACPEC live,
  /// route **`/mobile/carnet-types`** si disponible, sinon agrégation wallet + lots + faces.
  Future<List<CarnetType>> listPurchaseOfferTypes({
    required String companyId,
  }) async {
    final r = await loadCatalog(companyId: companyId);
    return r.types;
  }

  /// Tous les types connus (admin) : inférence Odoo / démo locale selon la configuration.
  Future<List<CarnetType>> listAllInferredTypes({
    required String companyId,
  }) async {
    final r = await loadAdminCatalog(companyId: companyId);
    return r.types;
  }
}

class _CarnetAgg {
  _CarnetAgg({
    required this.idStr,
    required this.code,
    required this.name,
    required this.faceValue,
    required this.size,
    required this.validityDays,
  });

  final String idStr;
  final String code;
  final String name;
  final int faceValue;
  final int size;
  final int validityDays;

  String get displayName {
    if (name.trim().isNotEmpty) return name.trim();
    return 'C${size}T-$faceValue';
  }
}

/// Quantité de **carnets** pour un appel Odoo `purchases/create` (champ `carnet_qty`),
/// à partir d’une quantité **tickets** saisie dans l’UI.
int acpecOdooCarnetQtyFromTicketSelection(CarnetType type, int ticketQty) {
  if (ticketQty <= 0) return 0;
  final s = math.max(1, type.size);
  return (ticketQty + s - 1) ~/ s;
}
