import 'package:flutter/material.dart';

class BackendUnavailableBanner extends StatelessWidget {
  const BackendUnavailableBanner({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.error.withValues(alpha: 0.28)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.cloud_off_rounded, color: scheme.error, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  height: 1.25,
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: scheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 34),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}
