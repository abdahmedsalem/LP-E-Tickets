import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:local_auth/local_auth.dart';

import '../../../core/auth/login_session_cache.dart';
import '../../../core/config/app_environment.dart';
import '../../../core/config/odoo_api_config.dart';
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
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/single_line_card_title.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../../shared/widgets/app_message.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _bioPref = false;
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
    final loc = await AppPreferences.localeCode();
    if (mounted) {
      setState(() {
        _bioPref = bio;
        _localeCode = loc;
      });
    }
  }

  Future<void> _pickLanguage() async {
    final l10n = AppLocalizations.of(context);
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
                title: Text(l10n.settingsFrench),
                trailing: _localeCode == 'fr'
                    ? const Icon(Icons.check_rounded, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, 'fr'),
              ),
              ListTile(
                title: Text(l10n.settingsArabic),
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

  Future<void> _showDeleteAccountInfo() async {
    final l10n = AppLocalizations.of(context);
    final baseUrl = OdooApiConfig.baseUrlTrimmed;
    final deletionUrl = baseUrl.isEmpty
        ? 'https://acpec2.odoo.com/account-deletion'
        : '$baseUrl/account-deletion';
    final copyLink = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(l10n.settingsDeleteAccountTitle),
        content: Text(l10n.settingsDeleteAccountMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.link_rounded),
            label: Text(l10n.settingsDeletionGuide),
          ),
        ],
      ),
    );
    if (copyLink != true) return;
    await Clipboard.setData(ClipboardData(text: deletionUrl));
    if (!mounted) return;
    AppMessage.info(context, l10n.settingsDeletionLinkCopied);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final user = context.watch<AuthBloc>().state.user;
    final scheme = Theme.of(context).colorScheme;
    const pageBg = Color(0xFFF7F9FC);
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
              Expanded(
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 120),
                  children: [
                    if (context.canPop())
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: IconButton(
                          onPressed: () => popOrGoClientHome(context),
                          icon: const Icon(Icons.arrow_back_ios_new_rounded),
                        ),
                      ),
                    if (user != null) ...[
                      _CompanyHeaderCard(
                        name: user.name,
                        initials: _initials(user.name),
                        verified: true,
                        verifiedLabel: l10n.homeVerifiedAccount,
                        identifier: user.phone.isNotEmpty
                            ? user.phone
                            : user.id,
                        memberSince: l10n.settingsMemberSince(
                          DateFormat.yMMMM(
                            Localizations.localeOf(context).toLanguageTag(),
                          ).format(user.createdAt),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _StatsRow(
                        lotsText: lotsText,
                        qrsText: qrsText,
                        consumedText: consText,
                        cardBg: cardBg,
                        borderColor: borderColor,
                        labelColor: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 24),
                    ],
                    _sectionTitle(
                      l10n.settingsQuickAccess.toUpperCase(),
                      scheme,
                    ),
                    _ProfileMenuCard(
                      cardBg: cardBg,
                      borderColor: borderColor,
                      children: [
                        _prefTile(
                          context,
                          icon: Icons.payments_outlined,
                          title: l10n.settingsPaymentHistory,
                          onTap: () => context.push('/payment-history'),
                        ),
                        _prefTile(
                          context,
                          icon: Icons.language_rounded,
                          title: l10n.settingsLanguage,
                          onTap: _pickLanguage,
                        ),
                      ],
                    ),
                    const SizedBox(height: 26),
                    _sectionTitle(
                      l10n.settingsAccountSecurity.toUpperCase(),
                      scheme,
                    ),
                    _ProfileMenuCard(
                      cardBg: cardBg,
                      borderColor: borderColor,
                      children: [
                        _prefTile(
                          context,
                          icon: Icons.fingerprint_rounded,
                          title: l10n.settingsQuickUnlock,
                          trailing: Switch.adaptive(
                            value: _bioPref,
                            activeTrackColor: scheme.primary,
                            activeThumbColor: scheme.onPrimary,
                            onChanged: (v) async {
                              if (v) {
                                try {
                                  final deviceOk = await _localAuth
                                      .isDeviceSupported();
                                  final bioOk =
                                      await _localAuth.canCheckBiometrics;
                                  if (!deviceOk && !bioOk) {
                                    if (!context.mounted) return;
                                    AppMessage.warning(
                                      context,
                                      l10n.settingsBiometricUnavailable,
                                    );
                                    return;
                                  }
                                  final ok = await _localAuth.authenticate(
                                    localizedReason:
                                        l10n.settingsBiometricReason,
                                    options: const AuthenticationOptions(
                                      biometricOnly: true,
                                      stickyAuth: true,
                                      useErrorDialogs: true,
                                    ),
                                  );
                                  if (!ok) return;
                                } on PlatformException {
                                  if (!context.mounted) return;
                                  AppMessage.info(
                                    context,
                                    l10n.settingsActivationCancelled,
                                  );
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
                          icon: Icons.person_remove_outlined,
                          title: l10n.settingsDeleteAccount,
                          onTap: _showDeleteAccountInfo,
                          iconColor: AppColors.muted,
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                    _LogoutTile(
                      onLogout: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            title: Text(l10n.settingsLogoutTitle),
                            content: Text(l10n.settingsLogoutQuestion),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: Text(l10n.commonCancel),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.danger,
                                ),
                                child: Text(l10n.authLogout),
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
                    const SizedBox(height: 28),
                    const Text(
                      'Version 1.0.0 • ACPEC',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.hint,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
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
      padding: const EdgeInsetsDirectional.only(start: 4, bottom: 10, top: 4),
      child: Text(
        text,
        style: TextStyle(
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
    VoidCallback? onTap,
    Widget? trailing,
    Color? iconColor,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: iconColor ?? AppColors.ink2, size: 25),
            const SizedBox(width: 16),
            Expanded(
              child: SingleLineCardTitle(
                text: title,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15.5,
                  color: scheme.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 8),
            trailing ??
                (onTap != null
                    ? Icon(Icons.chevron_right_rounded, color: AppColors.hint)
                    : const SizedBox.shrink()),
          ],
        ),
      ),
    );
  }
}

class _ProfileMenuCard extends StatelessWidget {
  const _ProfileMenuCard({
    required this.cardBg,
    required this.borderColor,
    required this.children,
  });

  final Color cardBg;
  final Color borderColor;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: borderColor.withValues(alpha: 0.75)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              const Divider(
                height: 1,
                thickness: 1,
                indent: 58,
                endIndent: 18,
                color: AppColors.lineSoft,
              ),
          ],
        ],
      ),
    );
  }
}

class _CompanyHeaderCard extends StatelessWidget {
  const _CompanyHeaderCard({
    required this.name,
    required this.initials,
    required this.verified,
    required this.verifiedLabel,
    required this.identifier,
    required this.memberSince,
  });

  final String name;
  final String initials;
  final bool verified;
  final String verifiedLabel;
  final String identifier;
  final String memberSince;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 26),
      decoration: BoxDecoration(
        gradient: AppColors.clientHomeWalletGradient,
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(
            color: Color(0x332EA043),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 82,
            height: 82,
            decoration: BoxDecoration(
              color: AppColors.brandBlue,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 4),
            ),
            alignment: Alignment.center,
            child: Text(
              initials,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
                fontSize: 28,
              ),
            ),
          ),
          const SizedBox(height: 13),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                verified ? Icons.verified_rounded : Icons.info_outline,
                size: 15,
                color: Colors.white,
              ),
              const SizedBox(width: 6),
              Text(
                verifiedLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Text(
            '$identifier  •  $memberSince',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
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
    final l10n = AppLocalizations.of(context);
    final valueColor = Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: borderColor.withValues(alpha: 0.9)),
      ),
      child: Row(
        children: [
          _statCell(l10n.settingsCarnets, lotsText, labelColor, valueColor),
          _divider(labelColor),
          _statCell(l10n.settingsQr, qrsText, labelColor, valueColor),
          _divider(labelColor),
          _statCell(
            l10n.settingsConsumptions,
            consumedText,
            labelColor,
            valueColor,
          ),
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
            style: TextStyle(
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
            style: TextStyle(
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
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Material(
        color: AppColors.dangerSurface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onLogout,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.logout_rounded,
                  color: AppColors.danger,
                  size: 21,
                ),
                const SizedBox(width: 10),
                Text(
                  l10n.authLogout,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: AppColors.danger,
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
