import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fueltoken_app/data/services/login_otp_challenge.dart';
import 'package:fueltoken_app/features/auth/bloc/auth_bloc.dart';
import 'package:fueltoken_app/features/auth/screens/login_screen.dart';
import 'package:fueltoken_app/l10n/app_localizations.dart';

class LoginTestBloc extends AuthBloc {
  void showState(AuthState value) => emit(value);
}

void main() {
  testWidgets('unknown account stays on phone entry and shows a clear message', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final bloc = LoginTestBloc();
    addTearDown(bloc.close);
    await tester.pumpWidget(
      BlocProvider<AuthBloc>.value(
        value: bloc,
        child: MaterialApp(
          locale: const Locale('fr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const LoginScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '46999999');

    // Even an accepted response cannot open the OTP field without a challenge.
    bloc.showState(
      const AuthState(
        status: AuthStatus.unauthenticated,
        loginOtpIdentifier: '46999999',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsOneWidget);

    bloc.showState(
      const AuthState(
        status: AuthStatus.failure,
        errorMessage: LoginOtpChallenge.accountUnavailableMessage,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(LoginOtpChallenge.accountUnavailableMessage),
      findsOneWidget,
    );
    expect(find.byType(TextFormField), findsOneWidget);
    await tester.tap(find.text('Fermer'));
    await tester.pumpAndSettle();

    // A real challenge still opens verification for an existing account.
    bloc.showState(
      const AuthState(
        status: AuthStatus.unauthenticated,
        loginOtpIdentifier: '46999999',
        loginOtpChallengeId: 42,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNWidgets(2));

    // A failed resend must also hide the old SMS input.
    bloc.showState(
      const AuthState(
        status: AuthStatus.failure,
        errorMessage: LoginOtpChallenge.accountUnavailableMessage,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsOneWidget);
    expect(
      find.text(LoginOtpChallenge.accountUnavailableMessage),
      findsOneWidget,
    );
  });
}
