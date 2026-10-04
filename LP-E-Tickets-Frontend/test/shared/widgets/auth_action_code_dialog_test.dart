import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fueltoken_app/domain/models/app_user.dart';
import 'package:fueltoken_app/domain/models/user_role.dart';
import 'package:fueltoken_app/data/repositories/auth_repository.dart';
import 'package:fueltoken_app/features/auth/bloc/auth_bloc.dart';
import 'package:fueltoken_app/l10n/app_localizations.dart';
import 'package:fueltoken_app/shared/widgets/auth_action_code_dialog.dart';

class SignedInBloc extends AuthBloc {
  SignedInBloc() : super(repo: AuthRepository.instance);

  @override
  AuthState get state => AuthState(
    user: AppUser(id: '1', email: '', name: 'Test', phone: '22000000',
      role: UserRole.user, createdAt: DateTime(2026)),
  );
}

void main() {
  for (final confirm in [false, true]) {
    testWidgets('PIN dialog survives closing animation and reopening: $confirm', (tester) async {
      final bloc = SignedInBloc();
      addTearDown(bloc.close);
      final results = <String?>[];
      await tester.pumpWidget(BlocProvider<AuthBloc>.value(
        value: bloc,
        child: MaterialApp(
          locale: const Locale('fr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(builder: (context) => Scaffold(body: TextButton(
            onPressed: () async {
              results.add(await showSensitiveActionCodeDialog(context,
                title: 'PIN', description: 'Test'));
            },
            child: const Text('Ouvrir'),
          ))),
        ),
      ));
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('Ouvrir'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '1234');
        await tester.pump();
        final context = tester.element(find.byType(TextField));
        final l10n = AppLocalizations.of(context);
        await tester.tap(find.text(confirm ? l10n.authConfirm : l10n.commonCancel));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 130));
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(results, List<String?>.filled(i + 1, confirm ? '1234' : null));
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
