import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/settings/app_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_context.dart';
import '../../../main.dart';
import '../../../shared/widgets/app_status_lottie.dart';
import 'admin_shell_scaffold.dart';
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

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthBloc>().state.user;
    if (user == null) {
      return const Scaffold(body: AppPageLoading());
    }
    final scheme = Theme.of(context).colorScheme;
    final pageBg = context.fuelPageBackground;

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        backgroundColor: pageBg,
        foregroundColor: scheme.onSurface,
        automaticallyImplyLeading: false,
        title: Text(
          'Profil',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: scheme.onSurface,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.accentViolet,
                  AppColors.accentViolet.withValues(alpha: 0.75),
                  const Color(0xFF5B21B6),
                ],
              ),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: AppColors.accentViolet.withValues(alpha: 0.35),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _initials(user.name),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
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
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'Rôle · Administrateur',
                          style: TextStyle(
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
          const SizedBox(height: 24),
          Text(
            'AFFICHAGE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.85,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          SwitchListTile.adaptive(
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
            onChanged: (v) => _persistTheme(v),
          ),
          const SizedBox(height: 28),
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
            ),
          ),
        ],
      ),
      bottomNavigationBar: AdminBottomTabsBar(
        selectedIndex: 2,
        onTap: (index) {
          switch (index) {
            case 0:
              context.go('/admin');
              return;
            case 1:
              context.go('/admin/achats');
              return;
            case 2:
              context.go('/admin/profile');
              return;
          }
        },
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
