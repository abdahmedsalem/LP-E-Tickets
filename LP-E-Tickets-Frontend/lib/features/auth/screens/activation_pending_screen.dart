import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/auth_brand_image.dart';
import '../bloc/auth_bloc.dart';

class ActivationPendingScreen extends StatelessWidget {
  const ActivationPendingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: BlocBuilder<AuthBloc, AuthState>(
            builder: (context, state) {
              final user = state.user;
              final refreshing = state.status == AuthStatus.authenticating;
              final deviceBlocked = user?.isDeviceBlocked == true;
              final headline = deviceBlocked
                  ? l10n.authDeviceBlocked
                  : l10n.authActivationPending;
              final body = deviceBlocked
                  ? l10n.authDeviceBlockedMessage
                  : l10n.authActivationPendingMessage;
              final icon = deviceBlocked
                  ? Icons.block_outlined
                  : Icons.gpp_maybe_outlined;
              final refreshLabel = deviceBlocked
                  ? l10n.authCheckAgain
                  : l10n.commonRefresh;

              return Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const AuthBrandImage(),
                        const SizedBox(height: 32),
                        Icon(
                          icon,
                          size: 68,
                          color: deviceBlocked
                              ? AppColors.danger
                              : AppColors.brandBlue,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          headline,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 19.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          body,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13.5,
                            height: 1.45,
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (user != null) ...[
                          Text(
                            user.name,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ],
                        const SizedBox(height: 32),
                        SizedBox(
                          height: 50,
                          child: FilledButton.icon(
                            onPressed: refreshing
                                ? null
                                : () => context.read<AuthBloc>().add(
                                      const AuthActivationRefreshRequested(),
                                    ),
                            icon: refreshing
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.refresh, size: 19),
                            label: Text(
                              refreshLabel,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 50,
                          child: OutlinedButton.icon(
                            onPressed: () => context.read<AuthBloc>().add(
                                  const AuthLogoutRequested(),
                                ),
                            icon: const Icon(Icons.logout, size: 19),
                            label: Text(
                              l10n.authLogout,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
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
      ),
    );
  }
}
