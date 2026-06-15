import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Raison d’affichage de l’écran de blocage en build release mal configuré.
enum ProductionConfigGateReason { missingApi, insecureApi }

/// Affichée si un build **release** est lancé sans config valide pour les stores.
class ProductionConfigGateApp extends StatelessWidget {
  const ProductionConfigGateApp({
    super.key,
    this.reason = ProductionConfigGateReason.missingApi,
  });

  final ProductionConfigGateReason reason;

  @override
  Widget build(BuildContext context) {
    final (title, body) = switch (reason) {
      ProductionConfigGateReason.missingApi => (
        'Configuration API requise',
        'En release, l’URL Odoo ACPEC doit être fournie au moment du build '
            '(compile-time), sinon l’app ne peut pas joindre le serveur.\n\n'
            'Même source que le développement : copiez '
            '`scripts/env/flutter.mobile.example.env` → '
            '`scripts/env/flutter.mobile.env`, renseignez '
            '`ODOO_JSONRPC_BASE_URL`, puis :\n\n'
            './scripts/run.sh build apk --release\n\n'
            'Windows : .\\scripts\\run.ps1 build apk --release\n\n'
            'Sans fichier .env (CI, etc.) :\n\n'
            'flutter build apk --release \\\n'
            '  --dart-define=ODOO_JSONRPC_BASE_URL=https://votre-hôte \\\n'
            '  --dart-define=ODOO_USE_ACPEC_AUTH=true \\\n'
            '  --dart-define=ODOO_FUEL_ENABLED=true\n\n'
            'REST OTP / inscription externe : '
            '`--dart-define=API_BASE_URL=https://…` si nécessaire.\n\n'
            'Build interne sans serveur : '
            '--dart-define=ALLOW_OFFLINE_DEMO=true',
      ),
      ProductionConfigGateReason.insecureApi => (
        'HTTPS requis (stores)',
        'Les builds release destinés à l’App Store et Google Play '
            'n’acceptent pas les URL API en **http://**.\n\n'
            'Corrigez `ODOO_JSONRPC_BASE_URL` (et `API_BASE_URL` si défini) '
            'dans `scripts/env/flutter.mobile.env` ou vos `--dart-define`, '
            'puis reconstruisez :\n\n'
            'ODOO_JSONRPC_BASE_URL=https://votre-odoo.example\n\n'
            './scripts/run.sh build appbundle --release\n\n'
            'Développement local HTTP : utilisez un build **debug** '
            '(cleartext autorisé sur Android debug uniquement).',
      ),
    };

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      reason == ProductionConfigGateReason.insecureApi
                          ? Icons.lock_outline
                          : Icons.settings_applications_outlined,
                      size: 48,
                      color: AppColors.primary,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      body,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.body,
                        height: 1.45,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
