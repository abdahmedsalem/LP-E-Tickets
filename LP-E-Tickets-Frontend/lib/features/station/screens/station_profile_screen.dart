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
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/api_required_view.dart';
import '../../../shared/widgets/app_status_lottie.dart';
import '../../../shared/widgets/single_line_card_title.dart';
import '../../auth/bloc/auth_bloc.dart';

/// Profil station / opérateur (données retirées de l’accueil).
class StationProfileScreen extends StatefulWidget {
  const StationProfileScreen({super.key});

  @override
  State<StationProfileScreen> createState() => _StationProfileScreenState();
}

class _StationProfileScreenState extends State<StationProfileScreen> {
  AcpecStationProfileData? _acpecProfile;
  String? _profileError;
  String _localeCode = AppPreferences.defaultLocaleCode;

  @override
  void initState() {
    super.initState();
    _loadLocale();
    if (AppEnvironment.useAcpecLiveData) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadAcpecProfile());
    }
  }

  Future<void> _loadLocale() async {
    final locale = await AppPreferences.localeCode();
    if (mounted) {
      setState(() => _localeCode = locale);
    }
  }

  Future<void> _pickLanguage() async {
    final l10n = AppLocalizations.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.ink.withValues(alpha: 0.58),
      isScrollControlled: true,
      builder: (sheetContext) => _StationLanguageSheet(
        selectedCode: _localeCode,
        title: l10n.settingsLanguage,
        frenchLabel: l10n.settingsFrench,
        arabicLabel: l10n.settingsArabic,
        onSelected: (code) => Navigator.pop(sheetContext, code),
      ),
    );
    if (choice == null || choice == _localeCode) return;
    await AppPreferences.setLocaleCode(choice);
    if (!mounted) return;
    setState(() => _localeCode = choice);
    await context
        .findAncestorStateOfType<FuelTokenAppState>()
        ?.reloadPreferences();
  }

  String _briefError(Object e) {
    if (e is OdooJsonRpcException && e.isOdooSessionExpired) {
      return AppLocalizations.of(context).stationSessionExpired;
    }
    return ErrorPresenter.localizedMessage(context, e).trim();
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
      _profileError = null;
    });

    try {
      final raw = await OdooFueltokenFacade().stationProfile(const {});
      final p = AcpecStationProfileData.fromRpc(raw);
      if (!mounted) return;
      setState(() {
        _acpecProfile = p;
      });
    } catch (e) {
      if (!mounted) return;

      final fallback = sessionUser == null
          ? null
          : AcpecStationProfileData.fromSessionUser(sessionUser);

      setState(() {
        _acpecProfile = fallback;
        _profileError = fallback == null ? _briefError(e) : null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
              : l10n.station);
    final inService = !useAcpec || ap == null || ap.stationActive;

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        backgroundColor: pageBg,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: false,
        toolbarHeight: 72,
        title: Text(
          l10n.stationProfileTitle,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 26,
            color: scheme.onSurface,
            letterSpacing: -0.7,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          _ProfileHeroCard(
            stationTitle: stationTitle,
            inService: inService,
          ),
          const SizedBox(height: 14),
          if (useAcpec) ...[
            if (_profileError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _AcpecProfileErrorCard(
                  message: _profileError!,
                  onRetry: () => _loadAcpecProfile(forceRefresh: true),
                ),
              ),
          ] else ...[
            ApiRequiredView(message: l10n.stationProfileServerRequired),
          ],
          const SizedBox(height: 20),
          _SectionLabel(l10n.stationPreferences),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Theme.of(context).brightness == Brightness.dark
                    ? scheme.outline.withValues(alpha: 0.28)
                    : AppColors.line,
              ),
              boxShadow: Theme.of(context).brightness == Brightness.dark
                  ? null
                  : AppColors.softShadow,
            ),
            child: Column(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                  leading: const _ProfileSettingIcon(
                    icon: Icons.language_rounded,
                  ),
                  title: Text(
                    l10n.settingsLanguage,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                  trailing: Icon(
                    Directionality.of(context) == TextDirection.rtl
                        ? Icons.chevron_left_rounded
                        : Icons.chevron_right_rounded,
                    color: AppColors.muted,
                  ),
                  onTap: _pickLanguage,
                ),
              ],
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
              label: Text(l10n.stationLogout),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
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
    required this.inService,
  });

  final String stationTitle;
  final bool inService;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.validGradient,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.leaderGreen.withValues(alpha: 0.22),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.local_gas_station_rounded,
              color: Colors.white,
              size: 29,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SingleLineCardTitle(
                  text: stationTitle,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    height: 1.05,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: inService
                                  ? const Color(0xFFB7F7C4)
                                  : Colors.white70,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            inService
                                ? l10n.stationInService
                                : l10n.stationOutOfService,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.75,
        color: AppColors.leaderGreenDark,
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
    final l10n = AppLocalizations.of(context);
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
            label: Text(l10n.commonRetry),
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
    final l10n = AppLocalizations.of(context);
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
            l10n.stationLinkedOperator,
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
          title: l10n.station,
          icon: Icons.local_gas_station_outlined,
          rows: [
            _ProfileRow(l10n.stationNameLabel, profile.stationName),
            _ProfileRow(l10n.stationCodeLabel, profile.stationCode, mono: true),
            _ProfileRow(l10n.stationAddressLabel, profile.stationAddress),
            _ProfileRow(
              l10n.stationStatusLabel,
              profile.stationActive
                  ? l10n.stationInService
                  : l10n.stationOutOfService,
            ),
          ],
        ),
        const SizedBox(height: 10),
        _ProfileSubCard(
          title: l10n.stationMobileOperator,
          icon: Icons.badge_outlined,
          rows: [
            _ProfileRow(l10n.stationNameLabel, profile.operatorName),
            _ProfileRow(l10n.stationEmailLabel, profile.operatorEmail),
            _ProfileRow(
              l10n.stationPhoneLabel,
              profile.operatorPhone.isEmpty ? '—' : profile.operatorPhone,
            ),
            _ProfileRow(
              l10n.stationOperatorIdentifier,
              profile.operatorId,
              mono: true,
            ),
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
  });

  final String title;
  final IconData icon;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? scheme.outline.withValues(alpha: 0.24)
              : AppColors.lineSoft,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.successSurface,
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 18, color: AppColors.leaderGreen),
              ),
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

class _ProfileSettingIcon extends StatelessWidget {
  const _ProfileSettingIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.successSurface,
        borderRadius: BorderRadius.circular(13),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: AppColors.leaderGreen, size: 21),
    );
  }
}

class _StationLanguageSheet extends StatelessWidget {
  const _StationLanguageSheet({
    required this.selectedCode,
    required this.title,
    required this.frenchLabel,
    required this.arabicLabel,
    required this.onSelected,
  });

  final String selectedCode;
  final String title;
  final String frenchLabel;
  final String arabicLabel;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: AppColors.line),
            boxShadow: [
              BoxShadow(
                color: AppColors.ink.withValues(alpha: 0.16),
                blurRadius: 34,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(27),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 7,
                  decoration: const BoxDecoration(
                    gradient: AppColors.validGradient,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.line,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: const BoxDecoration(
                              color: AppColors.successSurface,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.language_rounded,
                              color: AppColors.leaderGreen,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                                color: AppColors.ink,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _StationLanguageOption(
                        label: frenchLabel,
                        selected: selectedCode == 'fr',
                        onTap: () => onSelected('fr'),
                      ),
                      const SizedBox(height: 10),
                      _StationLanguageOption(
                        label: arabicLabel,
                        selected: selectedCode == 'ar',
                        onTap: () => onSelected('ar'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StationLanguageOption extends StatelessWidget {
  const _StationLanguageOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.successSurface : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppColors.leaderGreen : AppColors.line,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: selected ? AppColors.leaderGreenDark : AppColors.ink,
                  ),
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.leaderGreen,
                  size: 23,
                ),
            ],
          ),
        ),
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
