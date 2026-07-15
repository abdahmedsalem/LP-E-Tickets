import 'package:flutter/foundation.dart'
    show kDebugMode, kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/config/odoo_api_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_presenter.dart';
import '../../../data/models/acpec_mobile_auth_bootstrap.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/odoo_jsonrpc_client.dart';
import '../../../shared/widgets/loading_skeleton.dart';
import '../../../shared/widgets/empty_state.dart';

/// Checks ACPEC `version-check` + `signup-companies`; presents a minimal,
/// role-agnostic summary (no hosts, IDs, or RPC jargon).
class AcpecConnectionStep1Screen extends StatefulWidget {
  const AcpecConnectionStep1Screen({super.key});

  @override
  State<AcpecConnectionStep1Screen> createState() =>
      _AcpecConnectionStep1ScreenState();
}

class _AcpecConnectionStep1ScreenState
    extends State<AcpecConnectionStep1Screen> {
  final _facade = OdooFueltokenFacade();

  bool _loading = true;
  String? _error;
  String? _debugErrorDetail;
  AcpecVersionCheckData? _version;
  List<AcpecSignupCompany> _companies = [];
  String _installedVersion = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _debugErrorDetail = null;
    });
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      final platform = _acpecPlatformParam();
      final buildNum = int.tryParse(info.buildNumber) ?? 1;
      final versionParams = <String, dynamic>{
        'platform': platform,
        'app_version': info.version,
        'build_number': buildNum,
      };
      _installedVersion = info.version;

      if (!OdooApiConfig.isConfigured) {
        const userMsg =
            'Le service ne peut pas être vérifié sur cet appareil pour le moment.';
        _debugErrorDetail =
            'ODOO_JSONRPC_BASE_URL manquant (build / dart-define).';
        throw AcpecBootstrapException(userMsg);
      }

      final verRaw = await _facade.versionCheck(versionParams);
      final verData = acpecParseEnvelope(verRaw);
      final version = AcpecVersionCheckData.fromDataMap(verData);

      final coRaw = await _facade.signupCompanies({});
      final coData = acpecParseEnvelope(coRaw);
      final companies = AcpecSignupCompany.listFromDataMap(coData);

      if (!mounted) return;
      setState(() {
        _version = version;
        _companies = companies;
        _loading = false;
      });
    } on AcpecBootstrapException catch (e) {
      if (mounted) {
        setState(() {
          _error = ErrorPresenter.message(e);
          _loading = false;
        });
      }
    } on OdooJsonRpcException catch (e) {
      if (mounted) {
        setState(() {
          _error =
              'Connexion au service impossible. Vérifiez votre réseau et réessayez.';
          _debugErrorDetail = ErrorPresenter.message(e);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Une erreur inattendue s?est produite. Réessayez plus tard.';
          _debugErrorDetail = ErrorPresenter.message(e);
          _loading = false;
        });
      }
    }
  }

  static String _acpecPlatformParam() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pageBg = Colors.white;
    final borderColor = scheme.outline.withValues(
      alpha: scheme.brightness == Brightness.dark ? 0.5 : 0.35,
    );

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        backgroundColor: pageBg,
        title: Text(
          'État du service',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (_loading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: AppLoadingSkeleton(
                    style: AppLoadingSkeletonStyle.historyRows,
                    itemCount: 3,
                  ),
                ),
              )
            else if (_error != null) ...[
              _errorState(context, scheme, borderColor),
            ] else ...[
              if (_version != null)
                _versionUserSummary(context, scheme, borderColor),
              if (_installedVersion.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Version installée : $_installedVersion',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 28),
              _organizationsBlock(context, scheme, borderColor),
            ],
            if (kDebugMode &&
                _debugErrorDetail != null &&
                _debugErrorDetail!.isNotEmpty) ...[
              const SizedBox(height: 24),
              _debugPanel(context, borderColor),
            ],
          ],
        ),
      ),
    );
  }

  Widget _errorState(
    BuildContext context,
    ColorScheme scheme,
    Color borderColor,
  ) {
    return Column(
      children: [
        const SizedBox(height: 24),
        Icon(Icons.cloud_off_rounded, size: 56, color: scheme.onSurfaceVariant),
        const SizedBox(height: 16),
        Text(
          _error!,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            height: 1.45,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _load,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          ),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Réessayer'),
        ),
      ],
    );
  }

  /// Maps server flags to a single friendly card (no raw field names).
  Widget _versionUserSummary(
    BuildContext context,
    ColorScheme scheme,
    Color borderColor,
  ) {
    final v = _version!;
    final statusOk = v.status.toLowerCase() == 'ok';

    if (v.forceUpdate) {
      return _statusCard(
        context,
        borderColor,
        icon: Icons.system_update_alt_rounded,
        iconColor: AppColors.warning,
        surfaceTint: AppColors.warningSurface,
        title: 'Mise à jour requise',
        body:
            'Installez la dernière version de FuelToken pour continuer à utiliser le service.',
      );
    }

    if (!statusOk) {
      return _statusCard(
        context,
        borderColor,
        icon: Icons.error_outline_rounded,
        iconColor: AppColors.danger,
        surfaceTint: AppColors.dangerSurface.withValues(alpha: 0.4),
        title: 'Service indisponible',
        body:
            'Le service ne répond pas correctement. Réessayez dans quelques instants.',
      );
    }

    if (!v.latestVersion &&
        v.messageRaw != null &&
        v.messageRaw!.trim().isNotEmpty) {
      return _statusCard(
        context,
        borderColor,
        icon: Icons.info_outline_rounded,
        iconColor: AppColors.primary,
        surfaceTint: AppColors.primarySoft.withValues(alpha: 0.5),
        title: 'Mise à jour disponible',
        body: v.messageRaw!,
      );
    }

    if (!v.latestVersion) {
      return _statusCard(
        context,
        borderColor,
        icon: Icons.new_releases_outlined,
        iconColor: AppColors.primary,
        surfaceTint: AppColors.primarySoft.withValues(alpha: 0.35),
        title: 'Mise à jour disponible',
        body:
            'Une version plus récente existe. Nous vous recommandons de mettre à jour l?application lorsque vous le pourrez.',
      );
    }

    return _statusCard(
      context,
      borderColor,
      icon: Icons.verified_rounded,
      iconColor: AppColors.success,
      surfaceTint: AppColors.successSurface.withValues(alpha: 0.45),
      title: 'Tout est en ordre',
      body: 'Votre application est à jour et le service répond normalement.',
    );
  }

  Widget _statusCard(
    BuildContext context,
    Color borderColor, {
    required IconData icon,
    required Color iconColor,
    required Color surfaceTint,
    required String title,
    required String body,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: surfaceTint,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  shape: BoxShape.circle,
                  boxShadow: AppColors.softShadow,
                ),
                child: Icon(icon, color: iconColor, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      body,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _organizationsBlock(
    BuildContext context,
    ColorScheme scheme,
    Color borderColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Organisations disponibles',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        if (_companies.isEmpty)
          const EmptyState(
            icon: Icons.business_outlined,
            title: 'Aucune organisation',
            message: 'Aucune organisation à afficher pour le moment.',
          )
        else
          ..._companies.map((c) => _orgTile(context, scheme, borderColor, c)),
      ],
    );
  }

  Widget _orgTile(
    BuildContext context,
    ColorScheme scheme,
    Color borderColor,
    AcpecSignupCompany c,
  ) {
    final initial = _orgInitial(c.name);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: scheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: borderColor),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.primarySoft,
                foregroundColor: AppColors.primary,
                child: Text(
                  initial,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  c.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              Icon(
                Icons.business_rounded,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _orgInitial(String name) {
    final t = name.trim();
    if (t.isEmpty) return '?';
    return String.fromCharCode(t.runes.first).toUpperCase();
  }

  Widget _debugPanel(BuildContext context, Color borderColor) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Détail (mode développement)',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            _debugErrorDetail ?? '',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
