import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import 'package:fueltoken_app/core/theme/app_theme.dart';
import 'package:fueltoken_app/domain/models/app_user.dart';
import 'package:fueltoken_app/domain/models/user_role.dart';
import 'package:fueltoken_app/data/repositories/auth_repository.dart';
import 'package:fueltoken_app/data/services/immediate_account_deletion_service.dart';
import 'package:fueltoken_app/data/services/shared_services/odoo_jsonrpc_client.dart';
import 'package:fueltoken_app/features/auth/bloc/auth_bloc.dart';
import 'package:fueltoken_app/features/settings/widgets/account_deletion_flow.dart';
import 'package:fueltoken_app/l10n/app_localizations.dart';

class DeletionFlowBloc extends AuthBloc {
  DeletionFlowBloc() : super(repo: AuthRepository.instance) {
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
  bool hasValue = true;
  Object? failure;
  String? pin;
  @override
  Future<bool> recover() async => false;
  @override
  Future<DeletionWalletReport> preview() async =>
      DeletionWalletReport.fromJson({
        'snapshot': List.filled(64, 'b').join(),
        'has_value': hasValue,
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
        'carnets': [
          {
            'reference': 'Carnet-test',
            'value': 100,
            'available': 27,
            'expires_at': '2027-12-31 23:59:00',
          },
        ],
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
    if (failure != null) throw failure!;
    if (hasValue && !waiveValue) throw StateError('Missing consent');
    this.pin = pin;
    deleted = true;
  }

  @override
  Future<void> clearLocalSession() async => cleared = true;
  @override
  Future<void> acknowledge() async => acknowledged = true;
}

Future<void> openReport(
  WidgetTester tester,
  FlowService service, {
  String locale = 'fr',
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) async {
  final bloc = DeletionFlowBloc();
  addTearDown(bloc.close);
  await tester.pumpWidget(
    BlocProvider<AuthBloc>.value(
      value: bloc,
      child: MaterialApp(
        locale: Locale(locale),
        theme: brightness == Brightness.dark
            ? AppTheme.dark()
            : AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
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
  final l10n = AppLocalizations.of(tester.element(find.text('Start')));
  await tester.tap(find.text(l10n.authContinue));
  await tester.pumpAndSettle();
}

void main() {
  for (final locale in ['fr', 'ar']) {
    testWidgets('report fits a narrow screen with large $locale text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = FlowService();
      await openReport(
        tester,
        service,
        locale: locale,
        textScale: 1.6,
        brightness: locale == 'ar' ? Brightness.dark : Brightness.light,
      );
      final l10n = AppLocalizations.of(tester.element(find.text('Start')));
      final title = find.text(l10n.deletionReportTitle);
      expect(
        Directionality.of(tester.element(title)),
        locale == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      );
      expect(find.text(l10n.deletionActive), findsOneWidget);
      expect(find.text(l10n.deletionCopiesNotice), findsOneWidget);
      expect(
        find.text(
          DateFormat.yMMMd(
            locale,
          ).add_Hm().format(DateTime(2027, 12, 31, 23, 59)),
        ),
        findsOneWidget,
      );
      final confirm = find.widgetWithText(FilledButton, l10n.deletionConfirm);
      await tester.ensureVisible(confirm);
      expect(tester.getRect(confirm).bottom, lessThanOrEqualTo(568));
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      final checkbox = find.byType(CheckboxListTile);
      await tester.ensureVisible(checkbox);
      await tester.tap(checkbox);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byTooltip(l10n.commonCloseTooltip));
      await tester.tap(find.byTooltip(l10n.commonCloseTooltip));
      await tester.pumpAndSettle();
      expect(service.deleted, isFalse);
      expect(service.cleared, isFalse);
    });
  }

  testWidgets(
    'Arabic success stays localized and automatically completes logout',
    (tester) async {
      final service = FlowService()..hasValue = false;
      await openReport(tester, service, locale: 'ar');
      final l10n = AppLocalizations.of(tester.element(find.text('Start')));
      expect(find.byType(CheckboxListTile), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, l10n.deletionConfirm));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.text(l10n.authConfirm));
      await tester.pumpAndSettle();
      final success = find.text(l10n.deletionSuccess);
      expect(success, findsOneWidget);
      expect(Directionality.of(tester.element(success)), TextDirection.rtl);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(service.cleared, isTrue);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(service.acknowledged, isTrue);
      expect(success, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final code in [
    'INVALID_ACTION_CODE',
    'RATE_LIMITED',
    'UNEXPECTED_FAILURE',
  ]) {
    testWidgets('Arabic $code failure never exposes the raw server message', (
      tester,
    ) async {
      final service = FlowService()
        ..hasValue = false
        ..failure = OdooJsonRpcException(
          'Raw technical server error',
          publicCode: code,
        );
      await openReport(tester, service, locale: 'ar');
      final l10n = AppLocalizations.of(tester.element(find.text('Start')));
      await tester.tap(find.widgetWithText(FilledButton, l10n.deletionConfirm));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.text(l10n.authConfirm));
      await tester.pumpAndSettle();
      final message = switch (code) {
        'INVALID_ACTION_CODE' => l10n.commonPinIncorrect,
        'RATE_LIMITED' => l10n.commonTooManyAttempts,
        _ => l10n.deletionFailure,
      };
      expect(find.text(message), findsOneWidget);
      expect(find.textContaining('Raw technical'), findsNothing);
      expect(find.text(l10n.deletionSuccess), findsNothing);
      expect(service.cleared, isFalse);
      await tester.pump(const Duration(seconds: 5));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'report requires voluntary waiver before PIN and server deletion',
    (tester) async {
      final service = FlowService();
      await openReport(tester, service);
      expect(
        find.text(NumberFormat.decimalPattern('fr').format(2700)),
        findsOneWidget,
      );
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
