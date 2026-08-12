import 'dart:developer' as developer;
import 'dart:math' as math;

import '../../core/config/app_environment.dart';
import '../../core/config/diagnostic_config.dart';
import '../../core/debug/acpec_rpc_debug.dart';
import '../../core/config/odoo_fueltoken_rpc_config.dart';
import '../../core/settings/app_preferences.dart';
import '../../core/utils/error_presenter.dart';
import '../models/business_transaction.dart';
import '../models/carnet_type.dart';
import '../models/face_line.dart';
import '../models/purchase_lot.dart';
import '../models/qr_token.dart';
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

  static int _intValue(dynamic v, [int d = 0]) {
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

  String _localizedRowName(Map<String, dynamic> row, String languageCode) {
    final isArabic = languageCode.trim().toLowerCase().startsWith('ar');
    final candidates = isArabic
        ? [
            row['name_ar'],
            row['name_arabic'],
            row['carnet_type_name_ar'],
            row['carnet_type_name_arabic'],
            row['carnet_type_name'],
            row['name'],
          ]
        : [row['carnet_type_name'], row['name']];
    for (final candidate in candidates) {
      final value = candidate?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  void _absorbRow(
    Map<String, dynamic> row,
    Map<String, _CarnetAgg> acc,
    String languageCode,
  ) {
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
    final name = _localizedRowName(row, languageCode);

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

  void _walk(dynamic node, Map<String, _CarnetAgg> acc, String languageCode) {
    if (node is Map) {
      final m = Map<String, dynamic>.from(node);
      if (m.containsKey('carnet_type_id') || m.containsKey('type_id')) {
        _absorbRow(m, acc, languageCode);
      }
      for (final v in m.values) {
        _walk(v, acc, languageCode);
      }
    } else if (node is List) {
      for (final e in node) {
        _walk(e, acc, languageCode);
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

  static bool _isArabicLanguage(String languageCode) {
    return languageCode.trim().toLowerCase().startsWith('ar');
  }

  static bool _containsArabicText(String value) {
    return RegExp(r'[\u0600-\u06FF]').hasMatch(value);
  }

  List<CarnetType> _preferArabicNamesFromInferredTypes({
    required List<CarnetType> primary,
    required List<CarnetType> inferred,
    required String languageCode,
  }) {
    if (!_isArabicLanguage(languageCode) ||
        primary.isEmpty ||
        inferred.isEmpty) {
      return primary;
    }

    final resolver = _CarnetTypeNameResolver(inferred);
    return primary
        .map((type) {
          final currentName = type.name.trim();
          if (_containsArabicText(currentName)) return type;

          final inferredName = resolver.nameFor(
            id: type.id,
            code: type.code,
            size: type.size,
            faceValue: type.faceValue,
          );
          if (inferredName.isEmpty ||
              !_containsArabicText(inferredName) ||
              inferredName == currentName) {
            return type;
          }

          return CarnetType(
            id: type.id,
            code: type.code,
            name: inferredName,
            size: type.size,
            faceValue: type.faceValue,
            companyId: type.companyId,
            active: type.active,
            validityDays: type.validityDays,
            apiTotalAmount: type.apiTotalAmount,
            currencyName: type.currencyName,
            currencySymbol: type.currencySymbol,
          );
        })
        .toList(growable: false);
  }

  void _logRpc(String tag, dynamic payload) {
    if (!DiagnosticConfig.showTechnicalDiagnostics) {
      return;
    }
    developer.log(AcpecRpcDebug.clip(payload), name: 'AcpecCarnetCatalog.$tag');
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
    String? languageCode,
  }) async {
    String? preview;
    final effectiveLanguageCode =
        languageCode ?? await AppPreferences.localeCode();

    if (preferAdminList) {
      try {
        final raw = await OdooFueltokenFacade().adminCarnetTypesList(
          const <String, dynamic>{},
        );
        _logRpc('adminCarnetTypesList.response', raw);
        preview = AcpecRpcDebug.clip(raw);
        final list = AcpecCarnetTypesMapper.tryListFromRpc(
          raw,
          companyId: companyId,
          includeInactiveRows: true,
          languageCode: effectiveLanguageCode,
        );
        if (list != null) {
          return (
            list: list,
            err: null,
            preview: preview,
            usedAdminRoute: true,
          );
        }
      } on OdooJsonRpcException catch (e) {
        if (DiagnosticConfig.showTechnicalDiagnostics) {
          developer.log(
            'RPC failed: ${e.runtimeType}',
            name: 'AcpecCarnetCatalog.adminCarnetTypesList',
          );
        }
      } catch (e) {
        if (DiagnosticConfig.showTechnicalDiagnostics) {
          developer.log(
            'RPC failed: ${e.runtimeType}',
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
      preview = AcpecRpcDebug.clip(raw);
      final list = AcpecCarnetTypesMapper.tryListFromRpc(
        raw,
        companyId: companyId,
        languageCode: effectiveLanguageCode,
      );
      return (list: list, err: null, preview: preview, usedAdminRoute: false);
    } on OdooJsonRpcException catch (e) {
      if (DiagnosticConfig.showTechnicalDiagnostics) {
        developer.log(
          'RPC failed: ${e.runtimeType}',
          name: 'AcpecCarnetCatalog.carnetTypes',
        );
      }
      return (
        list: null,
        err: ErrorPresenter.message(e),
        preview: preview,
        usedAdminRoute: false,
      );
    } catch (e) {
      if (DiagnosticConfig.showTechnicalDiagnostics) {
        developer.log(
          'RPC failed: ${e.runtimeType}',
          name: 'AcpecCarnetCatalog.carnetTypes',
        );
      }
      return (
        list: null,
        err: ErrorPresenter.message(e),
        preview: preview,
        usedAdminRoute: false,
      );
    }
  }

  /// Charge les types (démo locale ou inférence Odoo) et remplit [lastLoadResult].
  Future<AcpecCarnetCatalogLoadResult> loadCatalog({
    required String companyId,
    String? languageCode,
  }) async {
    lastCatalogTypesFromAdminList = false;
    if (!AppEnvironment.useAcpecLiveData) {
      const r = AcpecCarnetCatalogLoadResult(types: []);
      lastLoadResult = r;
      return r;
    }

    final agg = <String, _CarnetAgg>{};
    final effectiveLanguageCode =
        languageCode ?? await AppPreferences.localeCode();
    String? ctErr;
    String? ctPreview;
    final ctRpc = await _tryFetchCarnetTypesRpc(
      companyId,
      languageCode: effectiveLanguageCode,
    );
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
      fPreview = AcpecRpcDebug.clip(fRaw);
      _walk(_unwrapAcpec(fRaw), agg, effectiveLanguageCode);
    } on OdooJsonRpcException catch (e) {
      fErr = ErrorPresenter.message(e);
      if (DiagnosticConfig.showTechnicalDiagnostics) {
        developer.log(
          'RPC failed: ${e.runtimeType}',
          name: 'AcpecCarnetCatalog.faces',
        );
      }
    } catch (e) {
      fErr = ErrorPresenter.message(e);
      if (DiagnosticConfig.showTechnicalDiagnostics) {
        developer.log(
          'RPC failed: ${e.runtimeType}',
          name: 'AcpecCarnetCatalog.faces',
        );
      }
    }

    try {
      final wRaw = await OdooFueltokenFacade().walletCurrent(
        Map<String, dynamic>.from(
          OdooFueltokenRpcConfig.walletCurrentDefaultParams,
        ),
      );
      _logRpc('walletCurrent.response', wRaw);
      wPreview = AcpecRpcDebug.clip(wRaw);
      _walk(_unwrapAcpec(wRaw), agg, effectiveLanguageCode);
    } on OdooJsonRpcException catch (e) {
      wErr = ErrorPresenter.message(e);
      if (DiagnosticConfig.showTechnicalDiagnostics) {
        developer.log(
          'RPC failed: ${e.runtimeType}',
          name: 'AcpecCarnetCatalog.walletCurrent',
        );
      }
    } catch (e) {
      wErr = ErrorPresenter.message(e);
      if (DiagnosticConfig.showTechnicalDiagnostics) {
        developer.log(
          'RPC failed: ${e.runtimeType}',
          name: 'AcpecCarnetCatalog.walletCurrent',
        );
      }
    }

    try {
      final pRaw = await OdooFueltokenFacade().purchasesList(
        const <String, dynamic>{},
      );
      _logRpc('purchasesList.response', pRaw);
      pPreview = AcpecRpcDebug.clip(pRaw);
      _walk(_unwrapAcpec(pRaw), agg, effectiveLanguageCode);
    } on OdooJsonRpcException catch (e) {
      pErr = ErrorPresenter.message(e);
      if (DiagnosticConfig.showTechnicalDiagnostics) {
        developer.log(
          'RPC failed: ${e.runtimeType}',
          name: 'AcpecCarnetCatalog.purchasesList',
        );
      }
    } catch (e) {
      pErr = ErrorPresenter.message(e);
      if (DiagnosticConfig.showTechnicalDiagnostics) {
        developer.log(
          'RPC failed: ${e.runtimeType}',
          name: 'AcpecCarnetCatalog.purchasesList',
        );
      }
    }

    final inferred = _toTypes(agg, companyId);
    final types = apiTypes != null
        ? _preferArabicNamesFromInferredTypes(
            primary: List<CarnetType>.from(apiTypes)
              ..sort((a, b) => a.faceValue.compareTo(b.faceValue)),
            inferred: inferred,
            languageCode: effectiveLanguageCode,
          )
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

  /// Chargement léger types + faces.
  ///
  /// Par défaut, cette méthode garde le comportement historique admin.
  /// Les écrans mobiles doivent passer [preferAdminList] à false afin de
  /// consommer `/mobile/carnet-types` et jamais `/admin/carnet-types/list`.
  Future<AcpecCarnetCatalogLoadResult> loadCatalogFacesOnly({
    required String companyId,
    bool preferAdminList = true,
    String? languageCode,
  }) async {
    lastCatalogTypesFromAdminList = false;
    if (!AppEnvironment.useAcpecLiveData) {
      const r = AcpecCarnetCatalogLoadResult(types: [], facesOnlyQuery: true);
      lastLoadResult = r;
      return r;
    }

    final agg = <String, _CarnetAgg>{};
    final effectiveLanguageCode =
        languageCode ?? await AppPreferences.localeCode();
    String? ctErr;
    String? ctPreview;
    final ctRpc = await _tryFetchCarnetTypesRpc(
      companyId,
      preferAdminList: preferAdminList,
      languageCode: effectiveLanguageCode,
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
      fPreview = AcpecRpcDebug.clip(fRaw);
      _walk(_unwrapAcpec(fRaw), agg, effectiveLanguageCode);
    } on OdooJsonRpcException catch (e) {
      fErr = ErrorPresenter.message(e);
      if (DiagnosticConfig.showTechnicalDiagnostics) {
        developer.log(
          'RPC failed: ${e.runtimeType}',
          name: 'AcpecCarnetCatalog.faces',
        );
      }
    } catch (e) {
      fErr = ErrorPresenter.message(e);
      if (DiagnosticConfig.showTechnicalDiagnostics) {
        developer.log(
          'RPC failed: ${e.runtimeType}',
          name: 'AcpecCarnetCatalog.faces',
        );
      }
    }

    final inferred = _toTypes(agg, companyId);
    final types = apiTypes != null
        ? _preferArabicNamesFromInferredTypes(
            primary: List<CarnetType>.from(apiTypes)
              ..sort((a, b) => a.faceValue.compareTo(b.faceValue)),
            inferred: inferred,
            languageCode: effectiveLanguageCode,
          )
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
        'Résumé (types/faces): carnetTypesErr=${ctErr != null}, facesErr=${fErr != null}, types=${types.length}',
        name: 'AcpecCarnetCatalog',
      );
    }
    return result;
  }

  /// Types pour l’écran admin : en ACPEC live, utilise la route admin dédiée.
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

  /// Types pour les écrans mobiles nécessitant seulement types + faces.
  ///
  /// Cette méthode ne doit jamais appeler `/admin/carnet-types/list`.
  Future<AcpecCarnetCatalogLoadResult> loadMobileCatalogFacesOnly({
    required String companyId,
    String? languageCode,
  }) async {
    lastCatalogTypesFromAdminList = false;
    if (!AppEnvironment.useAcpecLiveData) {
      const r = AcpecCarnetCatalogLoadResult(types: []);
      lastLoadResult = r;
      return r;
    }

    return loadCatalogFacesOnly(
      companyId: companyId,
      preferAdminList: false,
      languageCode: languageCode,
    );
  }

  /// Types proposés à l’achat : en démo locale, dépôt mémoire ; en ACPEC live,
  /// route **`/mobile/carnet-types`** si disponible, sinon agrégation wallet + lots + faces.
  Future<List<CarnetType>> listPurchaseOfferTypes({
    required String companyId,
    String? languageCode,
  }) async {
    final r = await loadCatalog(
      companyId: companyId,
      languageCode: languageCode,
    );
    return r.types;
  }

  /// Tous les types connus (admin) : inférence Odoo / démo locale selon la configuration.
  Future<List<CarnetType>> listAllInferredTypes({
    required String companyId,
  }) async {
    final r = await loadAdminCatalog(companyId: companyId);
    return r.types;
  }

  static List<FaceLine> localizeFaceLinesByCarnetTypes({
    required List<FaceLine> lines,
    required List<CarnetType> types,
  }) {
    final resolver = _CarnetTypeNameResolver(types);
    if (!resolver.hasTypes || lines.isEmpty) return lines;

    return lines
        .map((line) {
          final name = resolver.nameFor(
            id: line.carnetTypeId,
            code: line.carnetTypeCode,
            size: line.carnetFaceCount,
            faceValue: line.faceValue,
          );
          if (name.isEmpty || name == line.carnetTypeName.trim()) {
            return line;
          }
          return line.copyWith(carnetTypeName: name);
        })
        .toList(growable: false);
  }

  static List<QrLine> localizeQrLinesByCarnetTypes({
    required List<QrLine> lines,
    required List<CarnetType> types,
  }) {
    final resolver = _CarnetTypeNameResolver(types);
    if (!resolver.hasTypes || lines.isEmpty) return lines;

    return lines
        .map((line) {
          final name = resolver.nameFor(
            id: line.carnetTypeId,
            code: line.carnetTypeCode,
            size: line.carnetSize,
            faceValue: line.faceValue,
          );
          if (name.isEmpty || name == line.carnetTypeName.trim()) {
            return line;
          }
          return line.copyWith(carnetTypeName: name);
        })
        .toList(growable: false);
  }

  static QrToken localizeQrTokenByCarnetTypes({
    required QrToken qr,
    required List<CarnetType> types,
  }) {
    final lines = localizeQrLinesByCarnetTypes(lines: qr.lines, types: types);
    return identical(lines, qr.lines) ? qr : qr.copyWith(lines: lines);
  }

  static List<QrToken> localizeQrTokensByCarnetTypes({
    required List<QrToken> qrs,
    required List<CarnetType> types,
  }) {
    if (qrs.isEmpty || types.isEmpty) return qrs;
    return qrs
        .map((qr) => localizeQrTokenByCarnetTypes(qr: qr, types: types))
        .toList(growable: false);
  }

  static List<TransactionLine> localizeTransactionLinesByCarnetTypes({
    required List<TransactionLine> lines,
    required List<CarnetType> types,
  }) {
    final resolver = _CarnetTypeNameResolver(types);
    if (!resolver.hasTypes || lines.isEmpty) return lines;

    return lines
        .map((line) {
          final name = resolver.nameFor(
            id: line.carnetTypeId,
            code: line.carnetTypeCode,
            size: line.carnetSize,
            faceValue: line.faceValue,
          );
          if (name.isEmpty || name == line.carnetTypeName.trim()) {
            return line;
          }
          return line.copyWith(carnetTypeName: name);
        })
        .toList(growable: false);
  }

  static List<PurchaseLine> localizePurchaseLinesByCarnetTypes({
    required List<PurchaseLine> lines,
    required List<CarnetType> types,
  }) {
    final resolver = _CarnetTypeNameResolver(types);
    if (!resolver.hasTypes || lines.isEmpty) return lines;

    return lines
        .map((line) {
          final name = resolver.nameFor(
            id: line.carnetTypeId,
            code: line.carnetTypeCode,
            size: line.carnetSize,
            faceValue: line.faceValue,
          );
          if (name.isEmpty || name == line.carnetTypeName.trim()) {
            return line;
          }
          return line.copyWith(carnetTypeName: name);
        })
        .toList(growable: false);
  }

  static PurchaseLot localizePurchaseLotByCarnetTypes({
    required PurchaseLot lot,
    required List<CarnetType> types,
  }) {
    final lines = localizePurchaseLinesByCarnetTypes(
      lines: lot.lines,
      types: types,
    );
    return identical(lines, lot.lines) ? lot : lot.copyWith(lines: lines);
  }

  static List<PurchaseLot> localizePurchaseLotsByCarnetTypes({
    required List<PurchaseLot> lots,
    required List<CarnetType> types,
  }) {
    if (lots.isEmpty || types.isEmpty) return lots;
    return lots
        .map((lot) => localizePurchaseLotByCarnetTypes(lot: lot, types: types))
        .toList(growable: false);
  }

  static List<BusinessTransaction> localizeTransactionsByCarnetTypes({
    required List<BusinessTransaction> transactions,
    required List<CarnetType> types,
  }) {
    if (transactions.isEmpty || types.isEmpty) return transactions;
    return transactions
        .map((tx) {
          final lines = localizeTransactionLinesByCarnetTypes(
            lines: tx.lines,
            types: types,
          );
          return identical(lines, tx.lines) ? tx : tx.copyWith(lines: lines);
        })
        .toList(growable: false);
  }

  static List<Map<String, dynamic>> localizeCarnetTypeRowsByCarnetTypes({
    required List<Map<String, dynamic>> rows,
    required List<CarnetType> types,
  }) {
    final resolver = _CarnetTypeNameResolver(types);
    if (!resolver.hasTypes || rows.isEmpty) return rows;

    return rows
        .map((row) {
          final name = resolver.nameFor(
            id: row['carnet_type_id']?.toString(),
            code:
                row['carnet_type_code']?.toString() ??
                row['carnet_code']?.toString() ??
                row['code']?.toString(),
            size: _intValue(
              row['carnet_size'] ??
                  row['size'] ??
                  row['face_count'] ??
                  row['carnet_face_count'] ??
                  row['carnet_type_face_count'],
            ),
            faceValue: _intValue(
              row['face_value'] ?? row['nominal'] ?? row['unit_price'],
            ),
          );
          final currentName = row['carnet_type_name']?.toString().trim() ?? '';
          if (name.isEmpty || name == currentName) {
            return row;
          }
          return Map<String, dynamic>.from(row)..['carnet_type_name'] = name;
        })
        .toList(growable: false);
  }

  static Object? localizeCarnetTypeBreakdownByCarnetTypes({
    required Object? value,
    required List<CarnetType> types,
  }) {
    if (value == null || types.isEmpty) return value;

    if (value is List) {
      final localized = List<dynamic>.from(value);
      var changed = false;

      for (var i = 0; i < value.length; i++) {
        final item = value[i];
        if (item is! Map) continue;
        final row = Map<String, dynamic>.from(item);
        if (!_looksLikeCarnetTypeRow(row)) continue;

        final localizedRow = localizeCarnetTypeRowsByCarnetTypes(
          rows: [row],
          types: types,
        ).single;
        if (localizedRow['carnet_type_name'] != row['carnet_type_name']) {
          localized[i] = localizedRow;
          changed = true;
        }
      }

      return changed ? localized : value;
    }

    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      if (_looksLikeCarnetTypeRow(map)) {
        final localized = localizeCarnetTypeRowsByCarnetTypes(
          rows: [map],
          types: types,
        ).single;
        return localized['carnet_type_name'] == map['carnet_type_name']
            ? value
            : localized;
      }

      final keyedRows = Map<dynamic, dynamic>.from(value);
      var hasKeyedRows = false;
      var keyedRowsChanged = false;
      for (final entry in value.entries) {
        final rowValue = entry.value;
        if (rowValue is! Map) continue;
        final row = Map<String, dynamic>.from(rowValue);
        row.putIfAbsent('carnet_type_code', () => entry.key.toString());
        if (!_looksLikeCarnetTypeRow(row)) continue;
        hasKeyedRows = true;

        final localizedRow = localizeCarnetTypeRowsByCarnetTypes(
          rows: [row],
          types: types,
        ).single;
        if (localizedRow['carnet_type_name'] != row['carnet_type_name']) {
          keyedRows[entry.key] = localizedRow;
          keyedRowsChanged = true;
        }
      }
      if (hasKeyedRows) return keyedRowsChanged ? keyedRows : value;

      final localized = Map<String, dynamic>.from(map);
      var changed = false;
      for (final key in const [
        'items',
        'rows',
        'lines',
        'records',
        'types',
        'carnet_types',
      ]) {
        final nested = map[key];
        final localizedNested = localizeCarnetTypeBreakdownByCarnetTypes(
          value: nested,
          types: types,
        );
        if (!identical(localizedNested, nested)) {
          localized[key] = localizedNested;
          changed = true;
        }
      }
      return changed ? localized : value;
    }

    return value;
  }

  static bool _looksLikeCarnetTypeRow(Map<String, dynamic> row) {
    return row.containsKey('carnet_type_id') ||
        row.containsKey('carnet_type_code') ||
        row.containsKey('carnet_type_name') ||
        row.containsKey('carnet_code') ||
        row.containsKey('code');
  }
}

class _CarnetTypeNameResolver {
  _CarnetTypeNameResolver(List<CarnetType> types) {
    for (final type in types) {
      final name = type.name.trim();
      if (name.isEmpty) continue;

      final id = type.id.trim();
      if (id.isNotEmpty) _byId[id] = name;

      final code = type.code.trim().toUpperCase();
      if (code.isNotEmpty) _byCode[code] = name;

      final shapeKey = _shapeKey(size: type.size, faceValue: type.faceValue);
      if (shapeKey.isNotEmpty) _byShape.putIfAbsent(shapeKey, () => name);
    }
  }

  final Map<String, String> _byId = <String, String>{};
  final Map<String, String> _byCode = <String, String>{};
  final Map<String, String> _byShape = <String, String>{};

  bool get hasTypes =>
      _byId.isNotEmpty || _byCode.isNotEmpty || _byShape.isNotEmpty;

  String nameFor({String? id, String? code, int? size, int? faceValue}) {
    final cleanId = id?.trim() ?? '';
    if (cleanId.isNotEmpty) {
      final byId = _byId[cleanId];
      if (byId != null && byId.isNotEmpty) return byId;
    }

    final cleanCode = code?.trim().toUpperCase() ?? '';
    if (cleanCode.isNotEmpty) {
      final byCode = _byCode[cleanCode];
      if (byCode != null && byCode.isNotEmpty) return byCode;
    }

    final shapeKey = _shapeKey(size: size ?? 0, faceValue: faceValue ?? 0);
    if (shapeKey.isNotEmpty) {
      final byShape = _byShape[shapeKey];
      if (byShape != null && byShape.isNotEmpty) return byShape;
    }

    return '';
  }

  static String _shapeKey({required int size, required int faceValue}) {
    if (size <= 0 || faceValue <= 0) return '';
    return '$size:$faceValue';
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
    return code.trim();
  }
}

/// Quantité de **carnets** pour un appel Odoo `purchases/create` (champ `carnet_qty`),
/// à partir d’une quantité **tickets** saisie dans l’UI.
int acpecOdooCarnetQtyFromTicketSelection(CarnetType type, int ticketQty) {
  if (ticketQty <= 0) return 0;
  final s = math.max(1, type.size);
  return (ticketQty + s - 1) ~/ s;
}
