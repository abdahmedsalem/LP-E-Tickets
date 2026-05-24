import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Affiché lorsque les données doivent provenir du serveur ACPEC.
class ApiRequiredView extends StatelessWidget {
  const ApiRequiredView({
    super.key,
    this.title = 'Connexion serveur requise',
    this.message =
        'Configurez l’URL Odoo et activez l’authentification ACPEC pour afficher les données.',
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 56,
              color: scheme.primary.withValues(alpha: 0.65),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.muted,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
