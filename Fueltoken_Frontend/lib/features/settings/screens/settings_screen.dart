import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:local_auth/local_auth.dart';

import '../../../core/auth/login_session_cache.dart';
import '../../../core/config/app_environment.dart';
import '../../../core/navigation/client_tab_navigation.dart';
import '../../../core/settings/app_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/app_user.dart';
import '../../../data/models/business_transaction.dart';
import '../../../data/services/acpec_purchases_mapper.dart';
import '../../../data/services/acpec_qr_mapper.dart';
import '../../../data/services/acpec_transactions_mapper.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/odoo_jsonrpc_client.dart'
    show OdooJsonRpcException;
import '../../../main.dart';
import '../../../shared/widgets/app_bar_header.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../../shared/widgets/app_message.dart';

const _settingsHeaderPadding = EdgeInsets.fromLTRB(24, 0, 24, 0);
const _settingsHeaderGap = 4.0;
const _settingsHeaderTitleSize = 24.0;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _bioPref = false;
  bool _darkPref = false;
  String _localeCode = 'fr';
  final _localAuth = LocalAuthentication();

  int? _acpecStatLots;
  int? _acpecStatQrs;
  int? _acpecStatConsumed;
  bool _acpecStatsRefreshing = false;
  bool _acpecStatsLoaded = false;

  static const int _acpecTxPageSize = 40;
  static const int _acpecTxMaxPages = 80;

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshAcpecAccountStats();
    });
  }

  Future<int> _countAcpecStationConsumptions(AppUser user) async {
    final facade = OdooFueltokenFacade();
    final df = DateFormat('yyyy-MM-dd HH:mm:ss');
    final from = DateTime(2020, 1, 1);
    final to = DateTime.now().add(const Duration(days: 365));
    var offset = 0;
    var count = 0;
    for (var page = 0; page < _acpecTxMaxPages; page++) {
      final raw = await facade.transactions({
        'date_from': df.format(from),
        'date_to': df.format(to),
        'limit': _acpecTxPageSize,
        'offset': offset,
      });
      final parsed = AcpecTransactionsMapper.parsePage(
        raw,
        userId: user.id,
        userName: user.name,
        requestedLimit: _acpecTxPageSize,
        requestedOffset: offset,
      );
      for (final t in parsed.items) {
        if (t.type == TxType.stationConsumption) count++;
      }
      offset += parsed.items.length;
      if (!parsed.hasMore || parsed.items.isEmpty) break;
    }
    return count;
  }

  Future<void> _refreshAcpecAccountStats() async {
    if (!AppEnvironment.useAcpecLiveData) return;
    final user = context.read<AuthBloc>().state.user;
    if (user == null) return;

    setState(() => _acpecStatsRefreshing = true);
    try {
      final facade = OdooFueltokenFacade();
      final lotsRaw = await facade.purchasesList(const <String, dynamic>{});
      final qrsRaw = await facade.qrList(const <String, dynamic>{});
      final lots = AcpecPurchasesMapper.fromRpcResult(
        lotsRaw,
        clientId: user.id,
        clientName: user.name,
        companyId: AppEnvironment.companyIdForUser(user),
      ).length;
      final qrs = AcpecQrMapper.listFromRpc(
        qrsRaw,
        ownerId: user.id,
        ownerName: user.name,
        companyId: AppEnvironment.companyIdForUser(user),
      ).length;
      final consumed = await _countAcpecStationConsumptions(user);
      if (!mounted) return;
      setState(() {
        _acpecStatLots = lots;
        _acpecStatQrs = qrs;
        _acpecStatConsumed = consumed;
        _acpecStatsLoaded = true;
        _acpecStatsRefreshing = false;
      });
    } on OdooJsonRpcException {
      if (!mounted) return;
      setState(() {
        _acpecStatsRefreshing = false;
        if (!_acpecStatsLoaded) {
          _acpecStatLots = 0;
          _acpecStatQrs = 0;
          _acpecStatConsumed = 0;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _acpecStatsRefreshing = false;
        if (!_acpecStatsLoaded) {
          _acpecStatLots = 0;
          _acpecStatQrs = 0;
          _acpecStatConsumed = 0;
        }
      });
    }
  }

  Future<void> _load() async {
    final bio = await LoginSessionCache.biometricPreferred();
    final dark = await AppPreferences.darkMode();
    final loc = await AppPreferences.localeCode();
    if (mounted) {
      setState(() {
        _bioPref = bio;
        _darkPref = dark;
        _localeCode = loc;
      });
    }
  }

  Future<void> _persistTheme(bool dark) async {
    await AppPreferences.setDarkMode(dark);
    if (!mounted) return;
    setState(() => _darkPref = dark);
    final app = context.findAncestorStateOfType<FuelTokenAppState>();
    await app?.reloadPreferences();
  }

  Future<void> _pickLanguage() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final line = Theme.of(ctx).colorScheme.outline.withValues(alpha: 0.4);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: line,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                title: const Text('Français'),
                trailing: _localeCode == 'fr'
                    ? const Icon(Icons.check_rounded, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, 'fr'),
              ),
              ListTile(
                title: const Text('العربية'),
                trailing: _localeCode == 'ar'
                    ? const Icon(Icons.check_rounded, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, 'ar'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (choice != null && choice != _localeCode) {
      await AppPreferences.setLocaleCode(choice);
      if (!mounted) return;
      setState(() => _localeCode = choice);
      final app = context.findAncestorStateOfType<FuelTokenAppState>();
      await app?.reloadPreferences();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthBloc>().state.user;
    final scheme = Theme.of(context).colorScheme;
    final pageBg = Colors.white;
    final cardBg = scheme.surface;
    final borderColor = scheme.outline.withValues(
      alpha: scheme.brightness == Brightness.dark ? 0.5 : 0.35,
    );

    final useLiveStats = user != null && AppEnvironment.useAcpecLiveData;
    final showStatPlaceholder =
        useLiveStats && _acpecStatsRefreshing && !_acpecStatsLoaded;

    String lotsText;
    String qrsText;
    String consText;
    if (!useLiveStats || showStatPlaceholder) {
      lotsText = '—';
      qrsText = '—';
      consText = '—';
    } else {
      lotsText = '${_acpecStatLots ?? 0}';
      qrsText = '${_acpecStatQrs ?? 0}';
      consText = '${_acpecStatConsumed ?? 0}';
    }

    Future<void> onPullRefresh() async {
      await _load();
      await _refreshAcpecAccountStats();
    }

    return Scaffold(
      backgroundColor: pageBg,
      body: RefreshIndicator(
        color: scheme.primary,
        onRefresh: onPullRefresh,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppBarHeader(
                title: 'Mon compte',
                showBack: context.canPop(),
                onBack: () => popOrGoClientHome(context),
                largeTitle: true,
                largeTitlePadding: _settingsHeaderPadding,
                largeTitleGap: _settingsHeaderGap,
                largeTitleFontSize: _settingsHeaderTitleSize,
              ),
              Expanded(
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.fromLTRB(26, 16, 26, 120),
                  children: [
                    if (user != null) ...[
                      _CompanyHeaderCard(
                        name: user.name,
                        initials: _initials(user.name),
                        verified: true,
                        nifLabel: 'Compte vérifié',
                      ),
                      const SizedBox(height: 16),
                      _StatsRow(
                        lotsText: lotsText,
                        qrsText: qrsText,
                        consumedText: consText,
                        cardBg: cardBg,
                        borderColor: borderColor,
                        labelColor: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 22),
                    ],
                    _sectionTitle('PRÉFÉRENCES', scheme),
                    _prefTile(
                      context,
                      icon: Icons.language_rounded,
                      title: 'Langue',
                      subtitle: AppPreferences.labelForCode(_localeCode),
                      cardBg: cardBg,
                      borderColor: borderColor,
                      onTap: _pickLanguage,
                    ),
                    _prefTile(
                      context,
                      icon: Icons.fingerprint_rounded,
                      title: 'Authentification biométrique',
                      subtitle:
                          'Déverrouillage rapide après une connexion réussie.',
                      cardBg: cardBg,
                      borderColor: borderColor,
                      trailing: Switch.adaptive(
                        value: _bioPref,
                        activeTrackColor: scheme.primary,
                        activeThumbColor: scheme.onPrimary,
                        onChanged: (v) async {
                          if (v) {
                            try {
                              final deviceOk = await _localAuth
                                  .isDeviceSupported();
                              final bioOk = await _localAuth.canCheckBiometrics;
                              if (!deviceOk && !bioOk) {
                                if (!context.mounted) return;
                                AppMessage.warning(
                                  context,
                                  'La biométrie n’est pas disponible sur cet appareil.',
                                );
                                return;
                              }
                              final ok = await _localAuth.authenticate(
                                localizedReason:
                                    'Confirmez pour activer Face ID ou l’empreinte.',
                                options: const AuthenticationOptions(
                                  biometricOnly: true,
                                  stickyAuth: true,
                                  useErrorDialogs: true,
                                ),
                              );
                              if (!ok) return;
                            } on PlatformException {
                              if (!context.mounted) return;
                              AppMessage.info(context, 'Activation annulée.');
                              return;
                            }
                          }
                          await LoginSessionCache.setBiometricPreferred(v);
                          if (mounted) setState(() => _bioPref = v);
                        },
                      ),
                    ),
                    _prefTile(
                      context,
                      icon: Icons.dark_mode_outlined,
                      title: 'Mode sombre',
                      subtitle:
                          'Interface adaptée aux environnements peu éclairés.',
                      cardBg: cardBg,
                      borderColor: borderColor,
                      trailing: Switch.adaptive(
                        value: _darkPref,
                        activeTrackColor: scheme.primary,
                        activeThumbColor: scheme.onPrimary,
                        onChanged: (v) => _persistTheme(v),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _sectionTitle('SERVICE', scheme),
                    _prefTile(
                      context,
                      icon: Icons.verified_user_outlined,
                      title: 'Connexion ACPEC',
                      subtitle: 'Vérifier la disponibilité du service.',
                      cardBg: cardBg,
                      borderColor: borderColor,
                      onTap: () => context.push('/settings/acpec-step1'),
                    ),
                    _prefTile(
                      context,
                      icon: Icons.how_to_reg_outlined,
                      title: 'Inscription OTP',
                      subtitle: 'Créer un compte avec OTP SMS.',
                      cardBg: cardBg,
                      borderColor: borderColor,
                      onTap: () => context.push('/register'),
                    ),
                    const SizedBox(height: 18),
                    _LogoutTile(
                      onLogout: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            title: const Text('Déconnexion'),
                            content: const Text(
                              'Voulez-vous quitter FuelToken sur cet appareil ?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Annuler'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.danger,
                                ),
                                child: const Text('Se déconnecter'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true && context.mounted) {
                          context.read<AuthBloc>().add(
                            const AuthLogoutRequested(),
                          );
                          context.go('/login');
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _initials(String name) {
    return name
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .take(2)
        .map((s) => s[0].toUpperCase())
        .join();
  }

  Widget _sectionTitle(String text, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10, top: 4),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.85,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _prefTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color cardBg,
    required Color borderColor,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final iconBg = scheme.brightness == Brightness.dark
        ? scheme.primary.withValues(alpha: 0.24)
        : AppColors.primarySoft;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: borderColor.withValues(alpha: 0.95)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: scheme.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                trailing ??
                    (onTap != null
                        ? Icon(
                            Icons.chevron_right_rounded,
                            color: scheme.onSurfaceVariant,
                          )
                        : const SizedBox.shrink()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompanyHeaderCard extends StatelessWidget {
  const _CompanyHeaderCard({
    required this.name,
    required this.initials,
    required this.verified,
    required this.nifLabel,
  });

  final String name;
  final String initials;
  final bool verified;
  final String nifLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.line.withValues(alpha: 0.9)),
        boxShadow: AppColors.softShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: Text(
              initials,
              style: const TextStyle(
                color: AppColors.primaryDark,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: AppColors.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.successSurface,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        verified ? Icons.verified_rounded : Icons.info_outline,
                        size: 15,
                        color: AppColors.success,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          nifLabel,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.leaderGreenDark,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
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

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.lotsText,
    required this.qrsText,
    required this.consumedText,
    required this.cardBg,
    required this.borderColor,
    required this.labelColor,
  });

  final String lotsText;
  final String qrsText;
  final String consumedText;
  final Color cardBg;
  final Color borderColor;
  final Color labelColor;

  @override
  Widget build(BuildContext context) {
    final valueColor = Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor.withValues(alpha: 0.9)),
      ),
      child: Row(
        children: [
          _statCell('Lots', lotsText, labelColor, valueColor),
          _divider(labelColor),
          _statCell('QR émis', qrsText, labelColor, valueColor),
          _divider(labelColor),
          _statCell('Consommés', consumedText, labelColor, valueColor),
        ],
      ),
    );
  }

  Widget _divider(Color c) {
    return Container(
      width: 1,
      height: 36,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: c.withValues(alpha: 0.2),
    );
  }

  Widget _statCell(
    String label,
    String value,
    Color labelColor,
    Color valueColor,
  ) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w800,
              fontSize: 18,
              letterSpacing: -0.3,
              color: valueColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: labelColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoutTile extends StatelessWidget {
  const _LogoutTile({required this.onLogout});

  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: AppColors.danger.withValues(alpha: 0.22)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onLogout,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.dangerSurface.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.logout_rounded,
                    color: AppColors.danger,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Se déconnecter',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Fin de session sur cet appareil',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
