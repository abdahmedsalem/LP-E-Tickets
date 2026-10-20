import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fueltoken_app/data/models/app_user.dart';
import 'package:fueltoken_app/data/models/user_role.dart';
import 'package:fueltoken_app/data/services/immediate_account_deletion_service.dart';
import 'package:fueltoken_app/features/auth/bloc/auth_bloc.dart';
import 'package:fueltoken_app/features/settings/widgets/account_deletion_flow.dart';
import 'package:fueltoken_app/l10n/app_localizations.dart';

class DeletionFlowBloc extends AuthBloc {
  DeletionFlowBloc() {
    emit(
      AuthState(
        status: AuthStatus.authenticated,
        user: AppUser(
          id: 'fixture',
          email: '',
          name: 'Client test',
          phone: '23451234',
          role: UserRole.user,
          createdAt: DateTime(2026),
        ),
      ),
    );
  }
}

class FlowService extends ImmediateAccountDeletionService {
  bool pendingOperation = false;
  bool fail = false;
  bool deleted = false;
  bool cleared = false;
  bool acknowledged = false;
  String? pin;
  @override
  Future<bool> recover() async => false;
  @override
  Future<DeletionWalletReport> preview() async =>
      DeletionWalletReport.fromJson({
        'snapshot': List.filled(64, 'b').join(),
        'has_value': true,
        'blockers': [if (pendingOperation) 'station_operation'],
        'retention_notice': 'Conservation financière de test.',
        'wallets': [
          {
            'reference': 'Portefeuille test',
            'currency': 'MRU',
            'balance': 2700,
            'available_tickets': 27,
          },
        ],
        'carnets': [],
        'qrs': [
          {'reference': 'QR-test', 'state': 'active', 'tickets': 3},
        ],
      });
  @override
  Future<void> execute({
    required String pin,
    required DeletionWalletReport report,
    required bool waiveValue,
  }) async {
    if (fail) throw Exception('server unavailable');
    if (!waiveValue) throw StateError('Missing consent');
    this.pin = pin;
    deleted = true;
  }

  @override
  Future<void> clearLocalSession() async => cleared = true;
  @override
  Future<void> acknowledge() async => acknowledged = true;
}

Future<void> openReport(WidgetTester tester, FlowService service) async {
  final bloc = DeletionFlowBloc();
  addTearDown(bloc.close);
  await tester.pumpWidget(
    BlocProvider<AuthBloc>.value(
      value: bloc,
      child: MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => runAccountDeletionFlow(context, service),
              child: const Text('Start'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Start'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Continuer'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'report requires voluntary waiver before PIN and server deletion',
    (tester) async {
      final service = FlowService();
      await openReport(tester, service);
      expect(find.textContaining('2700'), findsOneWidget);
      expect(find.text('Enregistrer le rapport'), findsOneWidget);
      final confirm = find.widgetWithText(
        FilledButton,
        'Confirmer la suppression de mon compte',
      );
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      expect(service.deleted, isFalse);
      final checkbox = find.byType(CheckboxListTile);
      await tester.ensureVisible(checkbox);
      await tester.tap(checkbox);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(service.deleted, isFalse);
      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.text('Confirmer'));
      await tester.pumpAndSettle();
      expect(service.deleted, isTrue);
      expect(service.pin, '1234');
      expect(service.cleared, isTrue);
      expect(
        find.text('Votre compte a été supprimé avec succès'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(service.acknowledged, isTrue);
      expect(
        find.text('Votre compte a été supprimé avec succès'),
        findsNothing,
      );
    },
  );

  testWidgets('station operation blocks confirmation even after waiver', (
    tester,
  ) async {
    final service = FlowService()..pendingOperation = true;
    await openReport(tester, service);
    final checkbox = find.byType(CheckboxListTile);
    await tester.ensureVisible(checkbox);
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(
              FilledButton,
              'Confirmer la suppression de mon compte',
            ),
          )
          .onPressed,
      isNull,
    );
    expect(service.deleted, isFalse);
  });

  testWidgets('server refusal never shows success or clears the session', (
    tester,
  ) async {
    final service = FlowService()..fail = true;
    await openReport(tester, service);
    final checkbox = find.byType(CheckboxListTile);
    await tester.ensureVisible(checkbox);
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    final confirm = find.widgetWithText(
      FilledButton,
      'Confirmer la suppression de mon compte',
    );
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('Confirmer'));
    await tester.pumpAndSettle();
    expect(service.deleted, isFalse);
    expect(service.cleared, isFalse);
    expect(service.acknowledged, isFalse);
    expect(find.text('Votre compte a été supprimé avec succès'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });
}
