import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../l10n/app_localizations.dart';
import '../bloc/auth_bloc.dart';

class ActivationPendingScreen extends StatelessWidget {
  const ActivationPendingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(l10n.authDeviceStateTitle),
        ),
        body: SafeArea(
          child: BlocBuilder<AuthBloc, AuthState>(
            builder: (context, state) {
              final user = state.user;
              final refreshing = state.status == AuthStatus.authenticating;
              final trustState = user?.deviceTrustState?.trim();
              final stateLabel = trustState == null || trustState.isEmpty
                  ? l10n.authDevicePendingState
                  : trustState;
              final deviceBlocked = user?.isDeviceBlocked == true;
              final headline = deviceBlocked
                  ? l10n.authDeviceBlocked
                  : l10n.authActivationPending;
              final body = deviceBlocked
                  ? l10n.authDeviceBlockedMessage
                  : l10n.authActivationPendingMessage;
              final icon = deviceBlocked
                  ? Icons.block_outlined
                  : Icons.verified_user_outlined;
              final refreshLabel = deviceBlocked
                  ? l10n.authCheckAgain
                  : l10n.commonRefresh;

              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(icon, size: 72),
                        const SizedBox(height: 24),
                        Text(
                          headline,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          body,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 20),
                        if (user != null) ...[
                          Text(
                            user.name,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            l10n.authDeviceState(stateLabel),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 24),
                        ],
                        FilledButton.icon(
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
                                  ),
                                )
                              : const Icon(Icons.refresh),
                          label: Text(refreshLabel),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => context.read<AuthBloc>().add(
                            const AuthLogoutRequested(),
                          ),
                          icon: const Icon(Icons.logout),
                          label: Text(l10n.authLogout),
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
