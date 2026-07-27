import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/settings/app_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../main.dart';
import '../../../shared/widgets/fuel_mark.dart';
import '../../../shared/widgets/single_line_card_title.dart';

class LanguageSelectionScreen extends StatefulWidget {
  const LanguageSelectionScreen({super.key});

  @override
  State<LanguageSelectionScreen> createState() =>
      _LanguageSelectionScreenState();
}

class _LanguageSelectionScreenState extends State<LanguageSelectionScreen> {
  String? _selectedCode;
  bool _applying = false;

  Future<void> _selectLanguage(String code) async {
    if (_applying) return;
    setState(() {
      _selectedCode = code;
      _applying = true;
    });
    await AppPreferences.setLocaleCode(code);
    if (!mounted) return;
    final app = context.findAncestorStateOfType<FuelTokenAppState>();
    await app?.reloadPreferences();
    if (!mounted) return;
    setState(() => _applying = false);
  }

  void _continue() {
    if (_selectedCode == null || _applying) return;
    context.go('/onboarding');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 430,
                    minHeight: constraints.maxHeight - 48,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: FuelLogo(size: 34, showOrgWordmark: true),
                      ),
                      const SizedBox(height: 28),
                      _LanguageHero(
                        title: l10n.languageSelectionTitle,
                        message: l10n.languageSelectionMessage,
                      ),
                      const SizedBox(height: 24),
                      _LanguageCard(
                        code: 'fr',
                        nativeName: 'Français',
                        secondaryName: 'الفرنسية',
                        selected: _selectedCode == 'fr',
                        enabled: !_applying,
                        onTap: _selectLanguage,
                      ),
                      const SizedBox(height: 12),
                      _LanguageCard(
                        code: 'ar',
                        nativeName: 'العربية',
                        secondaryName: 'Arabe',
                        selected: _selectedCode == 'ar',
                        enabled: !_applying,
                        onTap: _selectLanguage,
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        height: 56,
                        child: FilledButton(
                          onPressed: _selectedCode == null || _applying
                              ? null
                              : _continue,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.leaderGreen,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: AppColors.line,
                            disabledForegroundColor: AppColors.muted,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _applying
                              ? const SizedBox.square(
                                  dimension: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  l10n.languageSelectionContinue,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LanguageHero extends StatelessWidget {
  const _LanguageHero({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppColors.loginHeroGradient,
        borderRadius: const BorderRadius.all(Radius.circular(28)),
        boxShadow: AppColors.elevatedShadow,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.translate_rounded,
                color: Colors.white,
                size: 27,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 27,
                height: 1.08,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.2,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: const TextStyle(
                color: Color(0xFFE0F2FE),
                fontSize: 15.5,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageCard extends StatelessWidget {
  const _LanguageCard({
    required this.code,
    required this.nativeName,
    required this.secondaryName,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String code;
  final String nativeName;
  final String secondaryName;
  final bool selected;
  final bool enabled;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      child: Material(
        color: selected ? AppColors.successSurface : Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: enabled ? () => onTap(code) : null,
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? AppColors.leaderGreen : AppColors.line,
                width: selected ? 1.8 : 1,
              ),
              boxShadow: selected ? AppColors.softShadow : null,
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.leaderGreen
                        : AppColors.lineSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    code.toUpperCase(),
                    style: TextStyle(
                      color: selected ? Colors.white : AppColors.leaderGreen,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SingleLineCardTitle(
                        text: nativeName,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        secondaryName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: selected
                      ? const Icon(
                          Icons.check_circle_rounded,
                          key: ValueKey('selected'),
                          color: AppColors.leaderGreen,
                          size: 26,
                        )
                      : const Icon(
                          Icons.radio_button_unchecked_rounded,
                          key: ValueKey('unselected'),
                          color: AppColors.hint,
                          size: 24,
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
