import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:local_auth/local_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/auth/login_session_cache.dart';
import '../../../core/config/odoo_api_config.dart';
import '../../../core/navigation/client_tab_navigation.dart';
import '../../../core/settings/app_preferences.dart';
import '../../../core/theme/app_colors.dart';
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
  String _appVersion = '—';
  String _buildNumber = '—';
  final _localAuth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait<dynamic>([
      LoginSessionCache.biometricPreferred(),
      AppPreferences.localeCode(),
      PackageInfo.fromPlatform(),
    ]);
    final bio = results[0] as bool;
    final loc = results[1] as String;
    final packageInfo = results[2] as PackageInfo;
    if (mounted) {
      setState(() {
        _bioPref = bio;
        _localeCode = loc;
        _appVersion = packageInfo.version;
        _buildNumber = packageInfo.buildNumber;
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

  Future<void> _showPrivacyPolicyInfo() async {
    const privacyUrl = 'https://lpft.odoorim.com/privacy';
    final copyLink = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Politique de confidentialité'),
        content: const Text(
          'Leader Petroleum E-Tickets s’engage à protéger vos données personnelles. '
          'La géolocalisation et l’appareil mobile servent uniquement à la sécurité et à la validation des opérations de carburant.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Fermer'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.link_rounded),
            label: const Text('Copier le lien'),
          ),
        ],
      ),
    );
    if (copyLink != true) return;
    await Clipboard.setData(const ClipboardData(text: privacyUrl));
    if (!mounted) return;
    AppMessage.info(context, 'Lien de la politique de confidentialité copié.');
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

    Future<void> onPullRefresh() async {
      await _load();
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
                          icon: Icons.privacy_tip_outlined,
                          title: 'Politique de confidentialité',
                          onTap: _showPrivacyPolicyInfo,
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
                    Text(
                      l10n.settingsDevelopedBy,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.settingsVersionBuild(_appVersion, _buildNumber),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
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
