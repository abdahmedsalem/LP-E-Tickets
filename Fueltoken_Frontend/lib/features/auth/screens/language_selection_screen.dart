import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/settings/app_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../main.dart';
import '../../../shared/widgets/fuel_mark.dart';

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
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: FuelLogo(size: 48)),
                  const SizedBox(height: 38),
                  Text(
                    l10n.languageSelectionTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 27,
                      height: 1.15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    l10n.languageSelectionMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.body,
                      fontSize: 14.5,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 32),
                  _LanguageCard(
                    code: 'fr',
                    nativeName: 'Français',
                    secondaryName: 'الفرنسية',
                    selected: _selectedCode == 'fr',
                    enabled: !_applying,
                    onTap: _selectLanguage,
                  ),
                  const SizedBox(height: 14),
                  _LanguageCard(
                    code: 'ar',
                    nativeName: 'العربية',
                    secondaryName: 'Arabe',
                    selected: _selectedCode == 'ar',
                    enabled: !_applying,
                    onTap: _selectLanguage,
                  ),
                  const SizedBox(height: 30),
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
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
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
    return Material(
      color: selected ? AppColors.primarySoft : Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: enabled ? () => onTap(code) : null,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.line,
              width: selected ? 1.8 : 1,
            ),
            boxShadow: selected ? AppColors.softShadow : null,
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : AppColors.background,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  code.toUpperCase(),
                  style: TextStyle(
                    color: selected ? Colors.white : AppColors.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nativeName,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      secondaryName,
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
                        color: AppColors.primary,
                        size: 26,
                      )
                    : const Icon(
                        Icons.radio_button_unchecked_rounded,
                        key: ValueKey('unselected'),
                        color: AppColors.muted,
                        size: 24,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
