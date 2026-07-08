import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/config/odoo_fueltoken_rpc_config.dart';
import '../../../core/network/acpec_fueltoken_rpc_coordinator.dart';
import '../../../core/settings/app_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_context.dart';
import '../../../core/utils/error_presenter.dart';
import '../../../main.dart';
import '../../../data/models/acpec_station_profile.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/odoo_jsonrpc_client.dart'
    show OdooJsonRpcException;
import '../../../shared/widgets/api_required_view.dart';
import '../../../shared/widgets/app_status_lottie.dart';
import '../../auth/bloc/auth_bloc.dart';

/// Profil station / opérateur (données retirées de l’accueil).
class StationProfileScreen extends StatefulWidget {
  const StationProfileScreen({super.key});

  @override
  State<StationProfileScreen> createState() => _StationProfileScreenState();
}

class _StationProfileScreenState extends State<StationProfileScreen> {
  AcpecStationProfileData? _acpecProfile;
  bool _profileLoading = false;
  String? _profileError;
  bool _darkPref = false;

  @override
  void initState() {
    super.initState();
    _loadDark();
    if (AppEnvironment.useAcpecLiveData) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadAcpecProfile());
    }
  }

  Future<void> _loadDark() async {
    final d = await AppPreferences.darkMode();
    if (mounted) setState(() => _darkPref = d);
  }

  Future<void> _persistTheme(bool dark) async {
    await AppPreferences.setDarkMode(dark);
    if (!mounted) return;
    setState(() => _darkPref = dark);
    final app = context.findAncestorStateOfType<FuelTokenAppState>();
    await app?.reloadPreferences();
  }

  String _briefError(Object e) {
    if (e is OdooJsonRpcException && e.isOdooSessionExpired) {
      return 'Session expirée. Reconnectez-vous.';
    }
    return ErrorPresenter.message(e).trim();
  }

  Future<void> _loadAcpecProfile({bool forceRefresh = false}) async {
    if (!AppEnvironment.useAcpecLiveData) return;

    final sessionUser = context.read<AuthBloc>().state.user;
    if (forceRefresh) {
      AcpecFueltokenRpcCoordinator.shared.invalidate(
        OdooFueltokenRpcConfig.stationProfile,
        const {},
      );
    }

    setState(() {
      _profileLoading = true;
      _profileError = null;
    });

    try {
      final raw = await OdooFueltokenFacade().stationProfile(const {});
      final p = AcpecStationProfileData.fromRpc(raw);
      if (!mounted) return;
      setState(() {
        _acpecProfile = p;
        _profileLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      final fallback = sessionUser == null
          ? null
          : AcpecStationProfileData.fromSessionUser(sessionUser);

      setState(() {
        _acpecProfile = fallback;
        _profileError = fallback == null ? _briefError(e) : null;
        _profileLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthBloc>().state.user;
    if (user == null) {
      return const Scaffold(body: AppPageLoading());
    }
    final scheme = Theme.of(context).colorScheme;
    final pageBg = context.fuelPageBackground;
    final useAcpec = AppEnvironment.useAcpecLiveData;
    final ap = _acpecProfile;
    final stationTitle = useAcpec && ap != null
        ? ap.stationName
        : (user.stationName?.trim().isNotEmpty == true
              ? user.stationName!.trim()
              : 'Station');
    final operatorSubtitle = useAcpec && ap != null
        ? ap.operatorName
        : user.name;
    final inService = !useAcpec || ap == null || ap.stationActive;

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        backgroundColor: pageBg,
        foregroundColor: scheme.onSurface,
        automaticallyImplyLeading: false,
        centerTitle: false,
        toolbarHeight: 66,
        title: Text(
          'Profil',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 24,
            color: scheme.onSurface,
            letterSpacing: -0.8,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          _ProfileHeroCard(
            stationTitle: stationTitle,
            operatorSubtitle: operatorSubtitle,
            inService: inService,
            iconColor: scheme.primary,
          ),
          const SizedBox(height: 16),
          if (ap != null) ...[
            _SectionLabel('Informations'),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: scheme.outline.withValues(alpha: 0.24),
                ),
                boxShadow: Theme.of(context).brightness == Brightness.dark
                    ? null
                    : AppColors.softShadow,
              ),
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  _ProfileSubCard(
                    title: 'Station',
                    icon: Icons.local_gas_station_outlined,
                    compact: true,
                    rows: [
                      _ProfileRow('Nom', ap.stationName),
                      _ProfileRow('Code', ap.stationCode, mono: true),
                      _ProfileRow('Adresse', ap.stationAddress),
                      _ProfileRow(
                        'Statut',
                        ap.stationActive ? 'En service' : 'Hors service',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (useAcpec) ...[
            if (_profileLoading && ap == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: AppLoadingLottie(size: 100)),
              ),
            if (_profileError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _AcpecProfileErrorCard(
                  message: _profileError!,
                  onRetry: () => _loadAcpecProfile(forceRefresh: true),
                ),
              ),
          ] else ...[
            const ApiRequiredView(
              message:
                  'Connectez-vous au serveur ACPEC pour afficher le profil station.',
            ),
          ],
          const SizedBox(height: 20),
          _SectionLabel('Préférences'),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: scheme.outline.withValues(alpha: 0.24)),
              boxShadow: Theme.of(context).brightness == Brightness.dark
                  ? null
                  : AppColors.softShadow,
            ),
            child: SwitchListTile.adaptive(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: scheme.outline.withValues(alpha: 0.35)),
              ),
              tileColor: scheme.surface,
              title: Text(
                'Mode sombre',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
              subtitle: Text(
                'Appliqué à toute l’app sur cet appareil.',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              value: _darkPref,
              activeTrackColor: scheme.primary,
              activeThumbColor: scheme.onPrimary,
              onChanged: _persistTheme,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: () {
                context.read<AuthBloc>().add(const AuthLogoutRequested());
                context.go('/login');
              },
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Se déconnecter'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeroCard extends StatelessWidget {
  const _ProfileHeroCard({
    required this.stationTitle,
    required this.operatorSubtitle,
    required this.inService,
    required this.iconColor,
  });

  final String stationTitle;
  final String operatorSubtitle;
  final bool inService;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.22)),
        boxShadow: Theme.of(context).brightness == Brightness.dark
            ? null
            : AppColors.softShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.local_gas_station_rounded,
              color: iconColor,
              size: 27,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stationTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: scheme.onSurface,
                    height: 1.05,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: inService ? AppColors.success : scheme.outline,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      inService ? 'En service' : 'Hors service',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: inService
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  operatorSubtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.9,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _AcpecProfileErrorCard extends StatelessWidget {
  const _AcpecProfileErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.error.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const AppErrorLottie(size: 56),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    height: 1.35,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _AcpecStationProfilePanel extends StatelessWidget {
  const _AcpecStationProfilePanel({required this.profile});

  final AcpecStationProfileData profile;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.22)),
          ),
          child: Text(
            'Station liée et opérateur mobile (ACPEC).',
            style: TextStyle(
              fontSize: 11,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: scheme.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _ProfileSubCard(
          title: 'Station',
          icon: Icons.local_gas_station_outlined,
          rows: [
            _ProfileRow('Nom', profile.stationName),
            _ProfileRow('Code', profile.stationCode, mono: true),
            _ProfileRow('Adresse', profile.stationAddress),
            _ProfileRow(
              'Statut',
              profile.stationActive ? 'En service' : 'Hors service',
            ),
          ],
        ),
        const SizedBox(height: 10),
        _ProfileSubCard(
          title: 'Opérateur (mobile)',
          icon: Icons.badge_outlined,
          rows: [
            _ProfileRow('Nom', profile.operatorName),
            _ProfileRow('E-mail', profile.operatorEmail),
            _ProfileRow(
              'Téléphone',
              profile.operatorPhone.isEmpty ? '—' : profile.operatorPhone,
            ),
            _ProfileRow('ID', profile.operatorId, mono: true),
          ],
        ),
      ],
    );
  }
}

class _ProfileSubCard extends StatelessWidget {
  const _ProfileSubCard({
    required this.title,
    required this.icon,
    required this.rows,
    this.compact = false,
  });

  final String title;
  final IconData icon;
  final List<Widget> rows;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.all(compact ? 12 : 14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.24)),
        boxShadow: Theme.of(context).brightness == Brightness.dark
            ? null
            : AppColors.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
          Divider(height: 22, color: scheme.outline.withValues(alpha: 0.25)),
          ...rows,
        ],
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow(this.label, this.value, {this.mono = false});

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized == '�' || normalized == '—') {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              normalized,
              style: mono
                  ? TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    )
                  : TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
