import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/settings/app_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_context.dart';
import '../../../data/models/user_role.dart';
import '../../../data/models/app_user.dart';
import '../../../main.dart';
import '../../../shared/widgets/app_status_lottie.dart';
import '../../auth/bloc/auth_bloc.dart';

/// Profil administrateur : identité, affichage, déconnexion.
class AdminProfileScreen extends StatefulWidget {
  const AdminProfileScreen({super.key});

  @override
  State<AdminProfileScreen> createState() => _AdminProfileScreenState();
}

class _AdminProfileScreenState extends State<AdminProfileScreen> {
  bool _darkPref = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
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

  List<Widget> _identityRows(AppUser user) {
    final rows = <Widget>[
      if (user.email.trim().isNotEmpty)
        _InfoTile(
          icon: Icons.mail_outline_rounded,
          label: 'E-mail',
          value: user.email,
        ),
      if (user.phone.trim().isNotEmpty)
        _InfoTile(
          icon: Icons.phone_outlined,
          label: 'Téléphone',
          value: user.phone,
        ),
      _InfoTile(
        icon: Icons.badge_outlined,
        label: 'Rôle',
        value: user.role.label,
      ),
      if ((user.companyId ?? '').trim().isNotEmpty)
        _InfoTile(
          icon: Icons.business_outlined,
          label: 'Société',
          value: user.companyId!,
          mono: true,
        ),
      if ((user.stationId ?? '').trim().isNotEmpty)
        _InfoTile(
          icon: Icons.local_gas_station_outlined,
          label: 'Station',
          value: user.stationId!,
          mono: true,
        ),
    ];
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthBloc>().state.user;
    if (user == null) {
      return const Scaffold(body: AppPageLoading());
    }
    final scheme = Theme.of(context).colorScheme;
    final pageBg = context.fuelPageBackground;
    final rows = _identityRows(user);

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        backgroundColor: pageBg,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        title: Text(
          'Profil',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: scheme.onSurface,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 120),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.accentViolet,
                  AppColors.accentViolet.withValues(alpha: 0.78),
                  const Color(0xFF5B21B6),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: AppColors.accentViolet.withValues(alpha: 0.32),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _initials(user.name),
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          height: 1.12,
                          letterSpacing: -0.25,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          user.role.label,
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'IDENTITÉ',
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.85,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: scheme.outline.withValues(alpha: 0.18)),
              boxShadow: AppColors.softShadow,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
              child: Column(children: rows),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'AFFICHAGE',
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.85,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: scheme.outline.withValues(alpha: 0.18)),
              boxShadow: AppColors.softShadow,
            ),
            child: SwitchListTile.adaptive(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              tileColor: Colors.white,
              title: Text(
                'Mode sombre',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
              subtitle: Text(
                'Appliqué à toute l’app sur cet appareil.',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              value: _darkPref,
              activeTrackColor: scheme.primary,
              activeThumbColor: scheme.onPrimary,
              onChanged: _persistTheme,
            ),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Déconnexion'),
                  content: const Text(
                    'Quitter la session administrateur sur cet appareil ?',
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
                context.read<AuthBloc>().add(const AuthLogoutRequested());
                context.go('/login');
              }
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
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          height: 78,
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(
              top: BorderSide(color: scheme.outline.withValues(alpha: 0.14)),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: () => context.go('/admin'),
                  icon: const Icon(Icons.home_rounded),
                  label: const Text('Accueil'),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  onPressed: () => context.go('/admin/profile'),
                  icon: const Icon(Icons.person_rounded),
                  label: const Text('Profil'),
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
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    this.mono = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: scheme.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                    height: 1.25,
                    letterSpacing: mono ? 0.1 : -0.1,
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
