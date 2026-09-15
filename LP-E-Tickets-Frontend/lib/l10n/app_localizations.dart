import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('fr'),
  ];

  /// Nom de l'application
  ///
  /// In fr, this message translates to:
  /// **'Leader Petroleum E-Tickets'**
  String get appTitle;

  /// No description provided for @homeVerifiedAccount.
  ///
  /// In fr, this message translates to:
  /// **'Compte vérifié'**
  String get homeVerifiedAccount;

  /// No description provided for @homeQuickActions.
  ///
  /// In fr, this message translates to:
  /// **'Actions rapides'**
  String get homeQuickActions;

  /// No description provided for @homeBuyCarnets.
  ///
  /// In fr, this message translates to:
  /// **'Commander des carnets'**
  String get homeBuyCarnets;

  /// No description provided for @homeWalletTitle.
  ///
  /// In fr, this message translates to:
  /// **'Portefeuille Leader Petroleum'**
  String get homeWalletTitle;

  /// No description provided for @homeGenerateQr.
  ///
  /// In fr, this message translates to:
  /// **'Générer un QR'**
  String get homeGenerateQr;

  /// No description provided for @homeTransferCarnets.
  ///
  /// In fr, this message translates to:
  /// **'Transférer des carnets'**
  String get homeTransferCarnets;

  /// No description provided for @homeTransferTickets.
  ///
  /// In fr, this message translates to:
  /// **'Transférer des tickets'**
  String get homeTransferTickets;

  /// No description provided for @commonRetry.
  ///
  /// In fr, this message translates to:
  /// **'Réessayer'**
  String get commonRetry;

  /// No description provided for @navHome.
  ///
  /// In fr, this message translates to:
  /// **'Accueil'**
  String get navHome;

  /// No description provided for @navCarnets.
  ///
  /// In fr, this message translates to:
  /// **'Carnets'**
  String get navCarnets;

  /// No description provided for @navQr.
  ///
  /// In fr, this message translates to:
  /// **'QR'**
  String get navQr;

  /// No description provided for @navWallet.
  ///
  /// In fr, this message translates to:
  /// **'Opérations'**
  String get navWallet;

  /// No description provided for @navHistory.
  ///
  /// In fr, this message translates to:
  /// **'Historique'**
  String get navHistory;

  /// No description provided for @navPortfolio.
  ///
  /// In fr, this message translates to:
  /// **'Portefeuille'**
  String get navPortfolio;

  /// No description provided for @carnetsTitle.
  ///
  /// In fr, this message translates to:
  /// **'Mes carnets'**
  String get carnetsTitle;

  /// No description provided for @carnet.
  ///
  /// In fr, this message translates to:
  /// **'Carnet'**
  String get carnet;

  /// No description provided for @carnetCodeUnavailable.
  ///
  /// In fr, this message translates to:
  /// **'Code carnet indisponible'**
  String get carnetCodeUnavailable;

  /// No description provided for @carnetStatusExpired.
  ///
  /// In fr, this message translates to:
  /// **'Expiré'**
  String get carnetStatusExpired;

  /// No description provided for @carnetStatusAvailable.
  ///
  /// In fr, this message translates to:
  /// **'Disponible'**
  String get carnetStatusAvailable;

  /// No description provided for @carnetStatusUnavailable.
  ///
  /// In fr, this message translates to:
  /// **'Indisponible'**
  String get carnetStatusUnavailable;

  /// No description provided for @carnetWithCode.
  ///
  /// In fr, this message translates to:
  /// **'Carnet {code}'**
  String carnetWithCode(String code);

  /// No description provided for @carnetTypeFallback.
  ///
  /// In fr, this message translates to:
  /// **'Carnet - {size} tickets x {value} {currency}'**
  String carnetTypeFallback(String size, String value, String currency);

  /// No description provided for @carnetsLoadError.
  ///
  /// In fr, this message translates to:
  /// **'Erreur de chargement'**
  String get carnetsLoadError;

  /// No description provided for @carnetsEmptyTitle.
  ///
  /// In fr, this message translates to:
  /// **'Aucun carnet'**
  String get carnetsEmptyTitle;

  /// No description provided for @carnetsEmptyMessage.
  ///
  /// In fr, this message translates to:
  /// **'Vous n\'avez encore aucun carnet disponible.'**
  String get carnetsEmptyMessage;

  /// No description provided for @filteredEmptyTitle.
  ///
  /// In fr, this message translates to:
  /// **'Aucun résultat pour « {filter} »'**
  String filteredEmptyTitle(String filter);

  /// No description provided for @carnetsFilteredEmptyMessage.
  ///
  /// In fr, this message translates to:
  /// **'Aucun carnet ne correspond au filtre « {filter} » pour le moment.'**
  String carnetsFilteredEmptyMessage(String filter);

  /// No description provided for @carnetsSummaryTitle.
  ///
  /// In fr, this message translates to:
  /// **'Résumé portefeuille'**
  String get carnetsSummaryTitle;

  /// No description provided for @carnetsAvailableTickets.
  ///
  /// In fr, this message translates to:
  /// **'Tickets disponibles'**
  String get carnetsAvailableTickets;

  /// No description provided for @carnetsValue.
  ///
  /// In fr, this message translates to:
  /// **'Valeur'**
  String get carnetsValue;

  /// No description provided for @carnetsActiveQr.
  ///
  /// In fr, this message translates to:
  /// **'QR actifs'**
  String get carnetsActiveQr;

  /// No description provided for @carnetsExpired.
  ///
  /// In fr, this message translates to:
  /// **'Expirés'**
  String get carnetsExpired;

  /// No description provided for @filterAll.
  ///
  /// In fr, this message translates to:
  /// **'Tous'**
  String get filterAll;

  /// No description provided for @filterAvailable.
  ///
  /// In fr, this message translates to:
  /// **'Disponibles'**
  String get filterAvailable;

  /// No description provided for @filterExpired.
  ///
  /// In fr, this message translates to:
  /// **'Expirés'**
  String get filterExpired;

  /// No description provided for @carnetDetailTitle.
  ///
  /// In fr, this message translates to:
  /// **'Détail Carnet'**
  String get carnetDetailTitle;

  /// No description provided for @carnetDetailDescription.
  ///
  /// In fr, this message translates to:
  /// **'Détail des tickets de ce carnet.'**
  String get carnetDetailDescription;

  /// No description provided for @referenceCode.
  ///
  /// In fr, this message translates to:
  /// **'Code de référence'**
  String get referenceCode;

  /// No description provided for @carnetFullNumber.
  ///
  /// In fr, this message translates to:
  /// **'N° complet du carnet'**
  String get carnetFullNumber;

  /// No description provided for @consumedQr.
  ///
  /// In fr, this message translates to:
  /// **'QR consommés'**
  String get consumedQr;

  /// No description provided for @availableAmount.
  ///
  /// In fr, this message translates to:
  /// **'Montant disponible'**
  String get availableAmount;

  /// No description provided for @notAvailable.
  ///
  /// In fr, this message translates to:
  /// **'Non disponible'**
  String get notAvailable;

  /// No description provided for @carnetExpiresOn.
  ///
  /// In fr, this message translates to:
  /// **'Expire le {date}'**
  String carnetExpiresOn(String date);

  /// No description provided for @qrsTitle.
  ///
  /// In fr, this message translates to:
  /// **'Mes QR'**
  String get qrsTitle;

  /// No description provided for @qrFilterActive.
  ///
  /// In fr, this message translates to:
  /// **'Actifs'**
  String get qrFilterActive;

  /// No description provided for @qrFilterBlocked.
  ///
  /// In fr, this message translates to:
  /// **'Bloqués'**
  String get qrFilterBlocked;

  /// No description provided for @qrFilterConsumed.
  ///
  /// In fr, this message translates to:
  /// **'Consommés'**
  String get qrFilterConsumed;

  /// No description provided for @qrStatusActive.
  ///
  /// In fr, this message translates to:
  /// **'Actif'**
  String get qrStatusActive;

  /// No description provided for @qrStatusBlocked.
  ///
  /// In fr, this message translates to:
  /// **'Bloqué'**
  String get qrStatusBlocked;

  /// No description provided for @qrStatusConsumed.
  ///
  /// In fr, this message translates to:
  /// **'Consommé'**
  String get qrStatusConsumed;

  /// No description provided for @qrStatusExpired.
  ///
  /// In fr, this message translates to:
  /// **'Expiré'**
  String get qrStatusExpired;

  /// No description provided for @qrsLoadError.
  ///
  /// In fr, this message translates to:
  /// **'Erreur de chargement'**
  String get qrsLoadError;

  /// No description provided for @qrsEmptyTitle.
  ///
  /// In fr, this message translates to:
  /// **'Aucun QR'**
  String get qrsEmptyTitle;

  /// No description provided for @qrsNoResults.
  ///
  /// In fr, this message translates to:
  /// **'Aucun résultat'**
  String get qrsNoResults;

  /// No description provided for @qrsEmptyMessage.
  ///
  /// In fr, this message translates to:
  /// **'Aucun QR n’est disponible pour le moment.'**
  String get qrsEmptyMessage;

  /// No description provided for @qrsFilterEmptyMessage.
  ///
  /// In fr, this message translates to:
  /// **'Ce filtre ne contient aucun QR. Essayez un autre filtre ou revenez à tous les résultats.'**
  String get qrsFilterEmptyMessage;

  /// No description provided for @qrsFilteredEmptyMessage.
  ///
  /// In fr, this message translates to:
  /// **'Aucun QR ne correspond au filtre « {filter} » pour le moment.'**
  String qrsFilteredEmptyMessage(String filter);

  /// No description provided for @commonRefresh.
  ///
  /// In fr, this message translates to:
  /// **'Actualiser'**
  String get commonRefresh;

  /// No description provided for @sessionExpiredReconnect.
  ///
  /// In fr, this message translates to:
  /// **'Session expirée. Reconnectez-vous.'**
  String get sessionExpiredReconnect;

  /// No description provided for @qrExpirationUndefined.
  ///
  /// In fr, this message translates to:
  /// **'Expiration non définie'**
  String get qrExpirationUndefined;

  /// No description provided for @qrExpiresFrom.
  ///
  /// In fr, this message translates to:
  /// **'Expire dès {date}'**
  String qrExpiresFrom(String date);

  /// No description provided for @qrConsumedOn.
  ///
  /// In fr, this message translates to:
  /// **'Consommé le {date}'**
  String qrConsumedOn(String date);

  /// No description provided for @qrExpiredFrom.
  ///
  /// In fr, this message translates to:
  /// **'Expiré dès {date}'**
  String qrExpiredFrom(String date);

  /// No description provided for @qrPartialExpiration.
  ///
  /// In fr, this message translates to:
  /// **'Expiration partielle détectée'**
  String get qrPartialExpiration;

  /// No description provided for @walletMovementsTitle.
  ///
  /// In fr, this message translates to:
  /// **'Mouvements du portefeuille'**
  String get walletMovementsTitle;

  /// No description provided for @transactionsHistoryTitle.
  ///
  /// In fr, this message translates to:
  /// **'Historique des opérations'**
  String get transactionsHistoryTitle;

  /// No description provided for @stationHistoryTitle.
  ///
  /// In fr, this message translates to:
  /// **'Historique station'**
  String get stationHistoryTitle;

  /// No description provided for @globalHistoryTitle.
  ///
  /// In fr, this message translates to:
  /// **'Historique global'**
  String get globalHistoryTitle;

  /// No description provided for @walletEmptyTitle.
  ///
  /// In fr, this message translates to:
  /// **'Aucun mouvement de portefeuille pour l\'instant'**
  String get walletEmptyTitle;

  /// No description provided for @walletEmptyMessage.
  ///
  /// In fr, this message translates to:
  /// **'Les commandes validées, générations de QR, transferts, réceptions et expirations apparaîtront ici.'**
  String get walletEmptyMessage;

  /// No description provided for @walletFilteredEmptyMessage.
  ///
  /// In fr, this message translates to:
  /// **'Aucun mouvement ne correspond au filtre « {filter} » pour le moment.'**
  String walletFilteredEmptyMessage(String filter);

  /// No description provided for @historyEmptyTitle.
  ///
  /// In fr, this message translates to:
  /// **'Aucun mouvement pour l\'instant'**
  String get historyEmptyTitle;

  /// No description provided for @historyEmptyMessage.
  ///
  /// In fr, this message translates to:
  /// **'Vos commandes, la génération de QR et vos utilisations apparaîtront ici.'**
  String get historyEmptyMessage;

  /// No description provided for @historyFilteredEmptyMessage.
  ///
  /// In fr, this message translates to:
  /// **'Aucune opération ne correspond au filtre « {filter} » pour le moment.'**
  String historyFilteredEmptyMessage(String filter);

  /// No description provided for @stationHistoryEmptyTitle.
  ///
  /// In fr, this message translates to:
  /// **'Aucune consommation'**
  String get stationHistoryEmptyTitle;

  /// No description provided for @stationHistoryEmptyMessage.
  ///
  /// In fr, this message translates to:
  /// **'Aucune consommation enregistrée pour cette période.'**
  String get stationHistoryEmptyMessage;

  /// No description provided for @globalHistoryEmptyTitle.
  ///
  /// In fr, this message translates to:
  /// **'Historique vide'**
  String get globalHistoryEmptyTitle;

  /// No description provided for @globalHistoryEmptyMessage.
  ///
  /// In fr, this message translates to:
  /// **'Synchronisez ou ajoutez des données : l\'historique global se remplira automatiquement.'**
  String get globalHistoryEmptyMessage;

  /// No description provided for @dateFrom.
  ///
  /// In fr, this message translates to:
  /// **'Du'**
  String get dateFrom;

  /// No description provided for @dateTo.
  ///
  /// In fr, this message translates to:
  /// **'Au'**
  String get dateTo;

  /// No description provided for @dateApply.
  ///
  /// In fr, this message translates to:
  /// **'Appliquer la période'**
  String get dateApply;

  /// No description provided for @loadNextPage.
  ///
  /// In fr, this message translates to:
  /// **'Charger la page suivante'**
  String get loadNextPage;

  /// No description provided for @scrollToLoadMore.
  ///
  /// In fr, this message translates to:
  /// **'Faites défiler pour charger plus'**
  String get scrollToLoadMore;

  /// No description provided for @historyPeriodEnd.
  ///
  /// In fr, this message translates to:
  /// **'Fin de l\'historique pour cette période'**
  String get historyPeriodEnd;

  /// No description provided for @today.
  ///
  /// In fr, this message translates to:
  /// **'Aujourd\'hui'**
  String get today;

  /// No description provided for @yesterday.
  ///
  /// In fr, this message translates to:
  /// **'Hier'**
  String get yesterday;

  /// No description provided for @detail.
  ///
  /// In fr, this message translates to:
  /// **'Détail'**
  String get detail;

  /// No description provided for @filterPurchases.
  ///
  /// In fr, this message translates to:
  /// **'Achats'**
  String get filterPurchases;

  /// No description provided for @filterQrGenerations.
  ///
  /// In fr, this message translates to:
  /// **'Générations QR'**
  String get filterQrGenerations;

  /// No description provided for @filterTransfers.
  ///
  /// In fr, this message translates to:
  /// **'Transferts'**
  String get filterTransfers;

  /// No description provided for @filterReceipts.
  ///
  /// In fr, this message translates to:
  /// **'Réceptions'**
  String get filterReceipts;

  /// No description provided for @filterExpirations.
  ///
  /// In fr, this message translates to:
  /// **'Expirations'**
  String get filterExpirations;

  /// No description provided for @filterOrders.
  ///
  /// In fr, this message translates to:
  /// **'Commandes'**
  String get filterOrders;

  /// No description provided for @filterSentReceived.
  ///
  /// In fr, this message translates to:
  /// **'Envoi / reçu'**
  String get filterSentReceived;

  /// No description provided for @filterConsumption.
  ///
  /// In fr, this message translates to:
  /// **'Consommation'**
  String get filterConsumption;

  /// No description provided for @txOrderSubmitted.
  ///
  /// In fr, this message translates to:
  /// **'Commande de carnets'**
  String get txOrderSubmitted;

  /// No description provided for @txOrderValidated.
  ///
  /// In fr, this message translates to:
  /// **'Carnets commandés'**
  String get txOrderValidated;

  /// No description provided for @txOrderRejected.
  ///
  /// In fr, this message translates to:
  /// **'Commande de carnets rejetée'**
  String get txOrderRejected;

  /// No description provided for @txQrGeneration.
  ///
  /// In fr, this message translates to:
  /// **'Génération de QR'**
  String get txQrGeneration;

  /// No description provided for @txQrSplit.
  ///
  /// In fr, this message translates to:
  /// **'Séparation du QR'**
  String get txQrSplit;

  /// No description provided for @txQrWithdrawal.
  ///
  /// In fr, this message translates to:
  /// **'Retrait de tickets'**
  String get txQrWithdrawal;

  /// No description provided for @txTicketTransfer.
  ///
  /// In fr, this message translates to:
  /// **'Transfert de tickets'**
  String get txTicketTransfer;

  /// No description provided for @txTicketReceipt.
  ///
  /// In fr, this message translates to:
  /// **'Réception de tickets'**
  String get txTicketReceipt;

  /// No description provided for @txCarnetTransfer.
  ///
  /// In fr, this message translates to:
  /// **'Transfert de carnets'**
  String get txCarnetTransfer;

  /// No description provided for @txCarnetReceipt.
  ///
  /// In fr, this message translates to:
  /// **'Réception de carnets'**
  String get txCarnetReceipt;

  /// No description provided for @txQrBlocked.
  ///
  /// In fr, this message translates to:
  /// **'QR bloqué'**
  String get txQrBlocked;

  /// No description provided for @txFuelConsumption.
  ///
  /// In fr, this message translates to:
  /// **'Consommation de carburant'**
  String get txFuelConsumption;

  /// No description provided for @txQrExpiration.
  ///
  /// In fr, this message translates to:
  /// **'Expiration QR'**
  String get txQrExpiration;

  /// No description provided for @walletCarnetExpiration.
  ///
  /// In fr, this message translates to:
  /// **'Expiration de carnet'**
  String get walletCarnetExpiration;

  /// No description provided for @txMovement.
  ///
  /// In fr, this message translates to:
  /// **'Mouvement'**
  String get txMovement;

  /// No description provided for @publicReference.
  ///
  /// In fr, this message translates to:
  /// **'Référence publique'**
  String get publicReference;

  /// No description provided for @buyer.
  ///
  /// In fr, this message translates to:
  /// **'Acheteur'**
  String get buyer;

  /// No description provided for @note.
  ///
  /// In fr, this message translates to:
  /// **'Note'**
  String get note;

  /// No description provided for @tickets.
  ///
  /// In fr, this message translates to:
  /// **'Tickets'**
  String get tickets;

  /// No description provided for @withdrawnTickets.
  ///
  /// In fr, this message translates to:
  /// **'Tickets retirés'**
  String get withdrawnTickets;

  /// No description provided for @sender.
  ///
  /// In fr, this message translates to:
  /// **'Expéditeur'**
  String get sender;

  /// No description provided for @beneficiary.
  ///
  /// In fr, this message translates to:
  /// **'Bénéficiaire'**
  String get beneficiary;

  /// No description provided for @station.
  ///
  /// In fr, this message translates to:
  /// **'Station'**
  String get station;

  /// No description provided for @attendant.
  ///
  /// In fr, this message translates to:
  /// **'Pompiste'**
  String get attendant;

  /// No description provided for @message.
  ///
  /// In fr, this message translates to:
  /// **'Message'**
  String get message;

  /// No description provided for @qrBlockedExpiredTicketsMessage.
  ///
  /// In fr, this message translates to:
  /// **'QR bloqué à cause des tickets expirés'**
  String get qrBlockedExpiredTicketsMessage;

  /// No description provided for @orderValidatedNote.
  ///
  /// In fr, this message translates to:
  /// **'Commande validée'**
  String get orderValidatedNote;

  /// No description provided for @orderRejectedNote.
  ///
  /// In fr, this message translates to:
  /// **'Commande refusée'**
  String get orderRejectedNote;

  /// No description provided for @carnetWithValue.
  ///
  /// In fr, this message translates to:
  /// **'Carnet {value}'**
  String carnetWithValue(String value);

  /// No description provided for @ticketCount.
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =0{0 ticket} =1{1 ticket} other{{count} tickets}}'**
  String ticketCount(int count);

  /// No description provided for @ticketsFromCarnet.
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =1{1 ticket de {carnet}} other{{count} tickets de {carnet}}}'**
  String ticketsFromCarnet(int count, String carnet);

  /// No description provided for @expirationDateLabel.
  ///
  /// In fr, this message translates to:
  /// **'Date d\'expiration : {date}'**
  String expirationDateLabel(String date);

  /// No description provided for @commonBack.
  ///
  /// In fr, this message translates to:
  /// **'Retour'**
  String get commonBack;

  /// No description provided for @commonConfirmReview.
  ///
  /// In fr, this message translates to:
  /// **'Vérifiez les éléments avant de confirmer.'**
  String get commonConfirmReview;

  /// No description provided for @commonPinVerification.
  ///
  /// In fr, this message translates to:
  /// **'Vérification du PIN'**
  String get commonPinVerification;

  /// No description provided for @commonPinConfirmationDescription.
  ///
  /// In fr, this message translates to:
  /// **'Saisissez votre PIN pour confirmer cette opération.'**
  String get commonPinConfirmationDescription;

  /// No description provided for @commonGenericError.
  ///
  /// In fr, this message translates to:
  /// **'Une erreur est survenue. Réessayez.'**
  String get commonGenericError;

  /// No description provided for @commonPinIncorrect.
  ///
  /// In fr, this message translates to:
  /// **'Code PIN incorrect.'**
  String get commonPinIncorrect;

  /// No description provided for @commonTooManyAttempts.
  ///
  /// In fr, this message translates to:
  /// **'Trop de tentatives. Réessayez plus tard.'**
  String get commonTooManyAttempts;

  /// No description provided for @commonNetworkError.
  ///
  /// In fr, this message translates to:
  /// **'Impossible de joindre le serveur. Vérifiez votre connexion.'**
  String get commonNetworkError;

  /// No description provided for @commonServerUnavailable.
  ///
  /// In fr, this message translates to:
  /// **'Serveur momentanément indisponible. Vérifiez votre connexion ou réessayez plus tard.'**
  String get commonServerUnavailable;

  /// No description provided for @commonSessionRequired.
  ///
  /// In fr, this message translates to:
  /// **'Session requise.'**
  String get commonSessionRequired;

  /// No description provided for @qrDetailTitle.
  ///
  /// In fr, this message translates to:
  /// **'Détails du QR'**
  String get qrDetailTitle;

  /// No description provided for @qrNotFound.
  ///
  /// In fr, this message translates to:
  /// **'QR introuvable.'**
  String get qrNotFound;

  /// No description provided for @qrServerRequiredForDetail.
  ///
  /// In fr, this message translates to:
  /// **'Connexion serveur requise pour afficher ce QR.'**
  String get qrServerRequiredForDetail;

  /// No description provided for @qrServerRequiredForManualCode.
  ///
  /// In fr, this message translates to:
  /// **'Connexion serveur requise pour révéler le code manuel.'**
  String get qrServerRequiredForManualCode;

  /// No description provided for @qrServerRequiredForSeparation.
  ///
  /// In fr, this message translates to:
  /// **'Connexion serveur requise pour séparer un QR.'**
  String get qrServerRequiredForSeparation;

  /// No description provided for @qrServerRequiredForWithdrawal.
  ///
  /// In fr, this message translates to:
  /// **'Connexion serveur requise pour retirer des tickets.'**
  String get qrServerRequiredForWithdrawal;

  /// No description provided for @qrContent.
  ///
  /// In fr, this message translates to:
  /// **'Contenu'**
  String get qrContent;

  /// No description provided for @qrSeparateUsableHint.
  ///
  /// In fr, this message translates to:
  /// **'Séparez les tickets utilisables des tickets expirés.'**
  String get qrSeparateUsableHint;

  /// No description provided for @qrSeparateActiveButton.
  ///
  /// In fr, this message translates to:
  /// **'Séparer la partie active dans un nouveau QR'**
  String get qrSeparateActiveButton;

  /// No description provided for @qrManualCode.
  ///
  /// In fr, this message translates to:
  /// **'Code manuel'**
  String get qrManualCode;

  /// No description provided for @qrRevealManualCode.
  ///
  /// In fr, this message translates to:
  /// **'Révéler le code manuel'**
  String get qrRevealManualCode;

  /// No description provided for @qrRevealManualCodeDescription.
  ///
  /// In fr, this message translates to:
  /// **'Saisissez votre PIN pour afficher temporairement le code manuel de consommation.'**
  String get qrRevealManualCodeDescription;

  /// No description provided for @qrManualCodeActiveOnly.
  ///
  /// In fr, this message translates to:
  /// **'Le code manuel ne peut être révélé que pour un QR actif.'**
  String get qrManualCodeActiveOnly;

  /// No description provided for @qrManualCodeUsageHint.
  ///
  /// In fr, this message translates to:
  /// **'Présentez ce code uniquement à la station au moment de la consommation.'**
  String get qrManualCodeUsageHint;

  /// No description provided for @qrManualCodeHiddenHint.
  ///
  /// In fr, this message translates to:
  /// **'Code manuel masqué. Touchez l\'œil et saisissez votre PIN pour l\'afficher temporairement.'**
  String get qrManualCodeHiddenHint;

  /// No description provided for @qrManualCodeRevealed.
  ///
  /// In fr, this message translates to:
  /// **'Code manuel révélé temporairement.'**
  String get qrManualCodeRevealed;

  /// No description provided for @qrManualCodeRevealFailed.
  ///
  /// In fr, this message translates to:
  /// **'Le code manuel n\'a pas pu être révélé. Réessayez ou contactez l\'administrateur.'**
  String get qrManualCodeRevealFailed;

  /// No description provided for @expirationDate.
  ///
  /// In fr, this message translates to:
  /// **'Date d\'expiration'**
  String get expirationDate;

  /// No description provided for @amount.
  ///
  /// In fr, this message translates to:
  /// **'Montant'**
  String get amount;

  /// No description provided for @expiresOn.
  ///
  /// In fr, this message translates to:
  /// **'Expire le {date}'**
  String expiresOn(String date);

  /// No description provided for @expiredOn.
  ///
  /// In fr, this message translates to:
  /// **'Expiré le {date}'**
  String expiredOn(String date);

  /// No description provided for @qrWithdrawTitle.
  ///
  /// In fr, this message translates to:
  /// **'Retirer des tickets'**
  String get qrWithdrawTitle;

  /// No description provided for @qrWithdrawInstruction.
  ///
  /// In fr, this message translates to:
  /// **'Sélectionnez les lignes à retirer.'**
  String get qrWithdrawInstruction;

  /// No description provided for @qrSelectAtLeastOneLine.
  ///
  /// In fr, this message translates to:
  /// **'Sélectionnez au moins une ligne à retirer.'**
  String get qrSelectAtLeastOneLine;

  /// No description provided for @qrKeepAtLeastOneLine.
  ///
  /// In fr, this message translates to:
  /// **'Au moins une ligne doit rester dans le QR d’origine.'**
  String get qrKeepAtLeastOneLine;

  /// No description provided for @qrMissingLineIdentifier.
  ///
  /// In fr, this message translates to:
  /// **'Une ligne du QR est indisponible. Rechargez le QR.'**
  String get qrMissingLineIdentifier;

  /// No description provided for @qrOnlyActiveCanWithdraw.
  ///
  /// In fr, this message translates to:
  /// **'Seuls les QR actifs permettent un retrait.'**
  String get qrOnlyActiveCanWithdraw;

  /// No description provided for @qrSingleLineCannotWithdraw.
  ///
  /// In fr, this message translates to:
  /// **'Un QR contenant une seule ligne ne permet pas de retrait.'**
  String get qrSingleLineCannotWithdraw;

  /// No description provided for @qrWithdrawalInProgress.
  ///
  /// In fr, this message translates to:
  /// **'Retrait...'**
  String get qrWithdrawalInProgress;

  /// No description provided for @qrWithdraw.
  ///
  /// In fr, this message translates to:
  /// **'Retirer'**
  String get qrWithdraw;

  /// No description provided for @qrWithdrawSelected.
  ///
  /// In fr, this message translates to:
  /// **'Retirer ({count})'**
  String qrWithdrawSelected(int count);

  /// No description provided for @selection.
  ///
  /// In fr, this message translates to:
  /// **'Sélection'**
  String get selection;

  /// No description provided for @selectedLines.
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =0{Aucune ligne sélectionnée} =1{1 ligne sélectionnée} other{{count} lignes sélectionnées}}'**
  String selectedLines(int count);

  /// No description provided for @qrWithdrawalSuccess.
  ///
  /// In fr, this message translates to:
  /// **'Tickets retirés avec succès.'**
  String get qrWithdrawalSuccess;

  /// No description provided for @qrWithdrawalFailed.
  ///
  /// In fr, this message translates to:
  /// **'Le retrait des tickets a échoué. Réessayez.'**
  String get qrWithdrawalFailed;

  /// No description provided for @qrSeparateTitle.
  ///
  /// In fr, this message translates to:
  /// **'Séparer les tickets valides'**
  String get qrSeparateTitle;

  /// No description provided for @qrSeparateSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Les tickets expirés restent séparés des tickets encore utilisables.'**
  String get qrSeparateSubtitle;

  /// No description provided for @qrOnlyBlockedCanSeparate.
  ///
  /// In fr, this message translates to:
  /// **'Seuls les QR bloqués peuvent être séparés.'**
  String get qrOnlyBlockedCanSeparate;

  /// No description provided for @qrSeparationInProgress.
  ///
  /// In fr, this message translates to:
  /// **'Séparation...'**
  String get qrSeparationInProgress;

  /// No description provided for @qrSeparate.
  ///
  /// In fr, this message translates to:
  /// **'Séparer'**
  String get qrSeparate;

  /// No description provided for @qrSeparationSuccess.
  ///
  /// In fr, this message translates to:
  /// **'QR séparé avec succès.'**
  String get qrSeparationSuccess;

  /// No description provided for @qrSeparationFailed.
  ///
  /// In fr, this message translates to:
  /// **'La séparation du QR a échoué. Réessayez.'**
  String get qrSeparationFailed;

  /// No description provided for @qrSeparationDisclaimer.
  ///
  /// In fr, this message translates to:
  /// **'La séparation générera un nouveau QR pour les lignes non expirées.'**
  String get qrSeparationDisclaimer;

  /// No description provided for @currentDistribution.
  ///
  /// In fr, this message translates to:
  /// **'Répartition actuelle'**
  String get currentDistribution;

  /// No description provided for @ticketDistribution.
  ///
  /// In fr, this message translates to:
  /// **'Répartition des tickets'**
  String get ticketDistribution;

  /// No description provided for @validTickets.
  ///
  /// In fr, this message translates to:
  /// **'Tickets valides'**
  String get validTickets;

  /// No description provided for @expiredTickets.
  ///
  /// In fr, this message translates to:
  /// **'Tickets expirés'**
  String get expiredTickets;

  /// No description provided for @validAmount.
  ///
  /// In fr, this message translates to:
  /// **'Montant valide'**
  String get validAmount;

  /// No description provided for @expiredAmount.
  ///
  /// In fr, this message translates to:
  /// **'Montant expiré'**
  String get expiredAmount;

  /// No description provided for @qrToSeparate.
  ///
  /// In fr, this message translates to:
  /// **'QR à séparer'**
  String get qrToSeparate;

  /// No description provided for @qrValidLinesMoved.
  ///
  /// In fr, this message translates to:
  /// **'Les lignes non expirées seront déplacées dans un nouveau QR.'**
  String get qrValidLinesMoved;

  /// No description provided for @qrLines.
  ///
  /// In fr, this message translates to:
  /// **'Lignes du QR'**
  String get qrLines;

  /// No description provided for @qrValidExpiredSummary.
  ///
  /// In fr, this message translates to:
  /// **'{valid} tickets valides · {expired} tickets expirés'**
  String qrValidExpiredSummary(int valid, int expired);

  /// No description provided for @ticketStatusWithDate.
  ///
  /// In fr, this message translates to:
  /// **'{status} · {date}'**
  String ticketStatusWithDate(String status, String date);

  /// No description provided for @statusActive.
  ///
  /// In fr, this message translates to:
  /// **'Actif'**
  String get statusActive;

  /// No description provided for @statusExpired.
  ///
  /// In fr, this message translates to:
  /// **'Expiré'**
  String get statusExpired;

  /// No description provided for @purchaseOrderTitle.
  ///
  /// In fr, this message translates to:
  /// **'Commande de carnets'**
  String get purchaseOrderTitle;

  /// No description provided for @purchaseSelectInstruction.
  ///
  /// In fr, this message translates to:
  /// **'Sélectionnez les carnets et indiquez la quantité.'**
  String get purchaseSelectInstruction;

  /// No description provided for @purchaseServerRequired.
  ///
  /// In fr, this message translates to:
  /// **'Connexion serveur requise pour afficher les offres.'**
  String get purchaseServerRequired;

  /// No description provided for @purchaseNoOffersTitle.
  ///
  /// In fr, this message translates to:
  /// **'Aucun carnet disponible'**
  String get purchaseNoOffersTitle;

  /// No description provided for @purchaseNoOffersMessage.
  ///
  /// In fr, this message translates to:
  /// **'Aucune offre de carnet n\'est disponible pour le moment.'**
  String get purchaseNoOffersMessage;

  /// No description provided for @purchaseCartTotal.
  ///
  /// In fr, this message translates to:
  /// **'Total du panier'**
  String get purchaseCartTotal;

  /// No description provided for @purchaseContinue.
  ///
  /// In fr, this message translates to:
  /// **'Continuer'**
  String get purchaseContinue;

  /// No description provided for @purchaseQuantity.
  ///
  /// In fr, this message translates to:
  /// **'Quantité'**
  String get purchaseQuantity;

  /// No description provided for @purchaseValidityDays.
  ///
  /// In fr, this message translates to:
  /// **'Validité : {days} jours'**
  String purchaseValidityDays(int days);

  /// No description provided for @purchaseAddProof.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter la preuve de paiement'**
  String get purchaseAddProof;

  /// No description provided for @purchaseProofSelected.
  ///
  /// In fr, this message translates to:
  /// **'Preuve sélectionnée'**
  String get purchaseProofSelected;

  /// No description provided for @purchaseProofFormats.
  ///
  /// In fr, this message translates to:
  /// **'JPG, PNG ou PDF — taille maximale {size}.'**
  String purchaseProofFormats(String size);

  /// No description provided for @purchaseProofTitle.
  ///
  /// In fr, this message translates to:
  /// **'Preuve de paiement'**
  String get purchaseProofTitle;

  /// No description provided for @purchaseProofInstruction.
  ///
  /// In fr, this message translates to:
  /// **'Vérifiez le panier, puis joignez un reçu ou un virement avant de confirmer.'**
  String get purchaseProofInstruction;

  /// No description provided for @purchaseSendOrder.
  ///
  /// In fr, this message translates to:
  /// **'Envoyer la commande'**
  String get purchaseSendOrder;

  /// No description provided for @purchaseConfirmTitle.
  ///
  /// In fr, this message translates to:
  /// **'Confirmer la commande'**
  String get purchaseConfirmTitle;

  /// No description provided for @purchaseConfirmInstruction.
  ///
  /// In fr, this message translates to:
  /// **'Vérifiez la commande de carnets avant de confirmer.'**
  String get purchaseConfirmInstruction;

  /// No description provided for @purchaseCancel.
  ///
  /// In fr, this message translates to:
  /// **'Annuler'**
  String get purchaseCancel;

  /// No description provided for @purchaseApprovalHint.
  ///
  /// In fr, this message translates to:
  /// **'Les carnets seront crédités après approbation.'**
  String get purchaseApprovalHint;

  /// No description provided for @purchaseConfirmationDisclaimer.
  ///
  /// In fr, this message translates to:
  /// **'En confirmant, votre commande sera envoyée à un administrateur pour validation. Les carnets seront crédités après approbation.'**
  String get purchaseConfirmationDisclaimer;

  /// No description provided for @purchaseProofRequired.
  ///
  /// In fr, this message translates to:
  /// **'La preuve de paiement est obligatoire.'**
  String get purchaseProofRequired;

  /// No description provided for @purchaseProofUnreadable.
  ///
  /// In fr, this message translates to:
  /// **'La preuve de paiement est illisible.'**
  String get purchaseProofUnreadable;

  /// No description provided for @purchaseSelectAtLeastOne.
  ///
  /// In fr, this message translates to:
  /// **'Indiquez au moins un ticket.'**
  String get purchaseSelectAtLeastOne;

  /// No description provided for @purchaseMaxTickets.
  ///
  /// In fr, this message translates to:
  /// **'Maximum {count} tickets par commande.'**
  String purchaseMaxTickets(int count);

  /// No description provided for @purchaseSuccessTitle.
  ///
  /// In fr, this message translates to:
  /// **'Commande de carnets enregistrée'**
  String get purchaseSuccessTitle;

  /// No description provided for @purchaseSuccessMessage.
  ///
  /// In fr, this message translates to:
  /// **'Votre commande de carnets est en attente de validation.'**
  String get purchaseSuccessMessage;

  /// No description provided for @purchasedCarnets.
  ///
  /// In fr, this message translates to:
  /// **'Carnets commandés'**
  String get purchasedCarnets;

  /// No description provided for @totalAmount.
  ///
  /// In fr, this message translates to:
  /// **'Montant total'**
  String get totalAmount;

  /// No description provided for @date.
  ///
  /// In fr, this message translates to:
  /// **'Date'**
  String get date;

  /// No description provided for @qrGenerationTitle.
  ///
  /// In fr, this message translates to:
  /// **'Génération de QR'**
  String get qrGenerationTitle;

  /// No description provided for @qrGenerationSelectInstruction.
  ///
  /// In fr, this message translates to:
  /// **'Sélectionnez les carnets à inclure dans le QR.'**
  String get qrGenerationSelectInstruction;

  /// No description provided for @qrGenerationChooseInstruction.
  ///
  /// In fr, this message translates to:
  /// **'Choisissez un carnet et une quantité.'**
  String get qrGenerationChooseInstruction;

  /// No description provided for @qrGenerationEmptyTitle.
  ///
  /// In fr, this message translates to:
  /// **'Aucun ticket disponible'**
  String get qrGenerationEmptyTitle;

  /// No description provided for @qrGenerationEmptyMessage.
  ///
  /// In fr, this message translates to:
  /// **'Commandez des carnets et attendez leur validation pour générer un QR.'**
  String get qrGenerationEmptyMessage;

  /// No description provided for @qrGenerationSelectAtLeastOne.
  ///
  /// In fr, this message translates to:
  /// **'Sélectionnez au moins un carnet.'**
  String get qrGenerationSelectAtLeastOne;

  /// No description provided for @qrGenerationConfirmTitle.
  ///
  /// In fr, this message translates to:
  /// **'Confirmer la génération'**
  String get qrGenerationConfirmTitle;

  /// No description provided for @qrGenerateButton.
  ///
  /// In fr, this message translates to:
  /// **'Générer le QR'**
  String get qrGenerateButton;

  /// No description provided for @qrGenerationDisclaimer.
  ///
  /// In fr, this message translates to:
  /// **'La génération du QR se fera à partir des carnets sélectionnés.'**
  String get qrGenerationDisclaimer;

  /// No description provided for @qrGenerationFailed.
  ///
  /// In fr, this message translates to:
  /// **'La génération du QR a échoué. Réessayez.'**
  String get qrGenerationFailed;

  /// No description provided for @qrGenerationTotal.
  ///
  /// In fr, this message translates to:
  /// **'Montant total du QR'**
  String get qrGenerationTotal;

  /// No description provided for @qrGenerate.
  ///
  /// In fr, this message translates to:
  /// **'Générer'**
  String get qrGenerate;

  /// No description provided for @qrGeneratedTitle.
  ///
  /// In fr, this message translates to:
  /// **'QR généré'**
  String get qrGeneratedTitle;

  /// No description provided for @qrGeneratedMessage.
  ///
  /// In fr, this message translates to:
  /// **'Votre QR est disponible dans la liste des QR.'**
  String get qrGeneratedMessage;

  /// No description provided for @usedCarnets.
  ///
  /// In fr, this message translates to:
  /// **'Carnets utilisés'**
  String get usedCarnets;

  /// No description provided for @purchaseDetailTitle.
  ///
  /// In fr, this message translates to:
  /// **'Détail de la commande'**
  String get purchaseDetailTitle;

  /// No description provided for @purchaseNotFound.
  ///
  /// In fr, this message translates to:
  /// **'Commande introuvable.'**
  String get purchaseNotFound;

  /// No description provided for @purchaseInformation.
  ///
  /// In fr, this message translates to:
  /// **'Informations'**
  String get purchaseInformation;

  /// No description provided for @purchaseOrderLines.
  ///
  /// In fr, this message translates to:
  /// **'Lignes de commande'**
  String get purchaseOrderLines;

  /// No description provided for @purchasePaymentProofs.
  ///
  /// In fr, this message translates to:
  /// **'Preuves de paiement'**
  String get purchasePaymentProofs;

  /// No description provided for @status.
  ///
  /// In fr, this message translates to:
  /// **'Statut'**
  String get status;

  /// No description provided for @paymentReference.
  ///
  /// In fr, this message translates to:
  /// **'Référence de paiement'**
  String get paymentReference;

  /// No description provided for @submittedOn.
  ///
  /// In fr, this message translates to:
  /// **'Soumis le'**
  String get submittedOn;

  /// No description provided for @ticketsExpiration.
  ///
  /// In fr, this message translates to:
  /// **'Expiration des tickets'**
  String get ticketsExpiration;

  /// No description provided for @validatedOn.
  ///
  /// In fr, this message translates to:
  /// **'Validé le'**
  String get validatedOn;

  /// No description provided for @validatedBy.
  ///
  /// In fr, this message translates to:
  /// **'Validé par'**
  String get validatedBy;

  /// No description provided for @rejectionReason.
  ///
  /// In fr, this message translates to:
  /// **'Motif de rejet'**
  String get rejectionReason;

  /// No description provided for @purchaseTotal.
  ///
  /// In fr, this message translates to:
  /// **'Total de la commande'**
  String get purchaseTotal;

  /// No description provided for @purchaseNoLines.
  ///
  /// In fr, this message translates to:
  /// **'Aucune ligne pour cette commande.'**
  String get purchaseNoLines;

  /// No description provided for @purchaseNoProof.
  ///
  /// In fr, this message translates to:
  /// **'Aucune preuve de paiement jointe à cette commande.'**
  String get purchaseNoProof;

  /// No description provided for @commonClose.
  ///
  /// In fr, this message translates to:
  /// **'Fermer'**
  String get commonClose;

  /// No description provided for @commonDownload.
  ///
  /// In fr, this message translates to:
  /// **'Télécharger'**
  String get commonDownload;

  /// No description provided for @commonCancel.
  ///
  /// In fr, this message translates to:
  /// **'Annuler'**
  String get commonCancel;

  /// No description provided for @commonContinue.
  ///
  /// In fr, this message translates to:
  /// **'Continuer'**
  String get commonContinue;

  /// No description provided for @returnHome.
  ///
  /// In fr, this message translates to:
  /// **'Retour à l\'accueil'**
  String get returnHome;

  /// No description provided for @expirationUnknown.
  ///
  /// In fr, this message translates to:
  /// **'Expiration non renseignée'**
  String get expirationUnknown;

  /// No description provided for @transferCarnetsTitle.
  ///
  /// In fr, this message translates to:
  /// **'Transfert de carnets'**
  String get transferCarnetsTitle;

  /// No description provided for @transferTicketsTitle.
  ///
  /// In fr, this message translates to:
  /// **'Transfert de tickets'**
  String get transferTicketsTitle;

  /// No description provided for @transferCarnetsInstruction.
  ///
  /// In fr, this message translates to:
  /// **'Entrez le numéro du bénéficiaire, puis sélectionnez les carnets à transférer.'**
  String get transferCarnetsInstruction;

  /// No description provided for @transferTicketsInstruction.
  ///
  /// In fr, this message translates to:
  /// **'Entrez le numéro du bénéficiaire, puis sélectionnez les tickets à transférer.'**
  String get transferTicketsInstruction;

  /// No description provided for @transferCarnetsEmptyTitle.
  ///
  /// In fr, this message translates to:
  /// **'Aucun carnet disponible'**
  String get transferCarnetsEmptyTitle;

  /// No description provided for @transferCarnetsEmptyMessage.
  ///
  /// In fr, this message translates to:
  /// **'Vos carnets disponibles apparaîtront ici.'**
  String get transferCarnetsEmptyMessage;

  /// No description provided for @transferTicketsEmptyTitle.
  ///
  /// In fr, this message translates to:
  /// **'Aucun ticket disponible'**
  String get transferTicketsEmptyTitle;

  /// No description provided for @transferTicketsEmptyMessage.
  ///
  /// In fr, this message translates to:
  /// **'Vos tickets disponibles apparaîtront ici.'**
  String get transferTicketsEmptyMessage;

  /// No description provided for @recipientPhoneHint.
  ///
  /// In fr, this message translates to:
  /// **'Numéro de téléphone du bénéficiaire'**
  String get recipientPhoneHint;

  /// No description provided for @transferTotal.
  ///
  /// In fr, this message translates to:
  /// **'Total du transfert'**
  String get transferTotal;

  /// No description provided for @transferOwnCarnetsForbidden.
  ///
  /// In fr, this message translates to:
  /// **'Vous ne pouvez pas transférer des carnets vers votre propre compte.'**
  String get transferOwnCarnetsForbidden;

  /// No description provided for @transferOwnTicketsForbidden.
  ///
  /// In fr, this message translates to:
  /// **'Vous ne pouvez pas transférer des tickets vers votre propre compte.'**
  String get transferOwnTicketsForbidden;

  /// No description provided for @recipientPhoneRequired.
  ///
  /// In fr, this message translates to:
  /// **'Saisissez le téléphone du bénéficiaire.'**
  String get recipientPhoneRequired;

  /// No description provided for @recipientPhoneInvalid.
  ///
  /// In fr, this message translates to:
  /// **'Le numéro du bénéficiaire doit contenir 8 chiffres.'**
  String get recipientPhoneInvalid;

  /// No description provided for @transferMissingCarnetLine.
  ///
  /// In fr, this message translates to:
  /// **'Un carnet est indisponible. Rechargez la liste.'**
  String get transferMissingCarnetLine;

  /// No description provided for @transferMissingTicketLine.
  ///
  /// In fr, this message translates to:
  /// **'Un ticket est indisponible. Rechargez la liste.'**
  String get transferMissingTicketLine;

  /// No description provided for @transferTicketQuantityUnavailable.
  ///
  /// In fr, this message translates to:
  /// **'La quantité dépasse le nombre de tickets disponibles.'**
  String get transferTicketQuantityUnavailable;

  /// No description provided for @transferSelectCarnet.
  ///
  /// In fr, this message translates to:
  /// **'Sélectionnez au moins un carnet à transférer.'**
  String get transferSelectCarnet;

  /// No description provided for @transferSelectTicket.
  ///
  /// In fr, this message translates to:
  /// **'Sélectionnez au moins un ticket à transférer.'**
  String get transferSelectTicket;

  /// No description provided for @transferRecipientNotFound.
  ///
  /// In fr, this message translates to:
  /// **'Aucun client ne correspond à ce numéro.'**
  String get transferRecipientNotFound;

  /// No description provided for @transferConfirmTitle.
  ///
  /// In fr, this message translates to:
  /// **'Confirmer le transfert'**
  String get transferConfirmTitle;

  /// No description provided for @transferReviewCarnets.
  ///
  /// In fr, this message translates to:
  /// **'Vérifiez les carnets avant de confirmer.'**
  String get transferReviewCarnets;

  /// No description provided for @transferReviewTickets.
  ///
  /// In fr, this message translates to:
  /// **'Vérifiez les tickets avant de confirmer.'**
  String get transferReviewTickets;

  /// No description provided for @transferredCarnets.
  ///
  /// In fr, this message translates to:
  /// **'Carnets transférés'**
  String get transferredCarnets;

  /// No description provided for @transferredTickets.
  ///
  /// In fr, this message translates to:
  /// **'Tickets transférés'**
  String get transferredTickets;

  /// No description provided for @transferUnconfirmedCarnets.
  ///
  /// In fr, this message translates to:
  /// **'Action non confirmée. Vérifiez l\'état de vos carnets avant de réessayer.'**
  String get transferUnconfirmedCarnets;

  /// No description provided for @transferUnconfirmedTickets.
  ///
  /// In fr, this message translates to:
  /// **'Action non confirmée. Vérifiez l\'état de vos tickets avant de réessayer.'**
  String get transferUnconfirmedTickets;

  /// No description provided for @transferRejected.
  ///
  /// In fr, this message translates to:
  /// **'Le transfert a été refusé par le serveur.'**
  String get transferRejected;

  /// No description provided for @transferFailed.
  ///
  /// In fr, this message translates to:
  /// **'Le transfert a échoué. Réessayez ou contactez l\'administrateur.'**
  String get transferFailed;

  /// No description provided for @transferSuccessTitle.
  ///
  /// In fr, this message translates to:
  /// **'Transfert confirmé'**
  String get transferSuccessTitle;

  /// No description provided for @transferFinalDisclaimer.
  ///
  /// In fr, this message translates to:
  /// **'Le transfert vers {recipient} est définitif et ne peut pas être annulé après confirmation.'**
  String transferFinalDisclaimer(String recipient);

  /// No description provided for @referenceIdentifier.
  ///
  /// In fr, this message translates to:
  /// **'Identifiant de référence'**
  String get referenceIdentifier;

  /// No description provided for @authSplashTagline.
  ///
  /// In fr, this message translates to:
  /// **'Bons carburant traçables'**
  String get authSplashTagline;

  /// No description provided for @authWelcomeTitle.
  ///
  /// In fr, this message translates to:
  /// **'Bienvenue sur Tickets Carburant'**
  String get authWelcomeTitle;

  /// No description provided for @authWelcomeMessage.
  ///
  /// In fr, this message translates to:
  /// **'Commandez, gérez et utilisez vos carnets de tickets carburant en toute sécurité.'**
  String get authWelcomeMessage;

  /// No description provided for @authCreateAccount.
  ///
  /// In fr, this message translates to:
  /// **'Créer mon compte'**
  String get authCreateAccount;

  /// No description provided for @authAlreadyAccount.
  ///
  /// In fr, this message translates to:
  /// **'Vous avez déjà un compte ?'**
  String get authAlreadyAccount;

  /// No description provided for @authSignIn.
  ///
  /// In fr, this message translates to:
  /// **'Se connecter'**
  String get authSignIn;

  /// No description provided for @authContacts.
  ///
  /// In fr, this message translates to:
  /// **'Contacts'**
  String get authContacts;

  /// No description provided for @authContactsHelp.
  ///
  /// In fr, this message translates to:
  /// **'Contactez votre support Tickets Carburant ou votre interlocuteur habituel pour obtenir de l\'aide.'**
  String get authContactsHelp;

  /// No description provided for @authLoginTitle.
  ///
  /// In fr, this message translates to:
  /// **'Connexion'**
  String get authLoginTitle;

  /// No description provided for @authLoginFailed.
  ///
  /// In fr, this message translates to:
  /// **'Connexion impossible. Vérifiez le numéro ou le code SMS.'**
  String get authLoginFailed;

  /// No description provided for @authOtpIncorrect.
  ///
  /// In fr, this message translates to:
  /// **'Code SMS incorrect. Réessayez.'**
  String get authOtpIncorrect;

  /// No description provided for @authPhoneRequired.
  ///
  /// In fr, this message translates to:
  /// **'Saisissez votre numéro de téléphone.'**
  String get authPhoneRequired;

  /// No description provided for @authPhoneInvalid.
  ///
  /// In fr, this message translates to:
  /// **'Saisissez un numéro de téléphone valide à 8 chiffres.'**
  String get authPhoneInvalid;

  /// No description provided for @authOtpLength.
  ///
  /// In fr, this message translates to:
  /// **'Saisissez un code à {count} chiffres.'**
  String authOtpLength(int count);

  /// No description provided for @authDigitsCount.
  ///
  /// In fr, this message translates to:
  /// **'{count} chiffres'**
  String authDigitsCount(int count);

  /// No description provided for @authContinue.
  ///
  /// In fr, this message translates to:
  /// **'Continuer'**
  String get authContinue;

  /// No description provided for @authAccountVerification.
  ///
  /// In fr, this message translates to:
  /// **'Vérification du compte'**
  String get authAccountVerification;

  /// No description provided for @authVerificationCode.
  ///
  /// In fr, this message translates to:
  /// **'Code de vérification'**
  String get authVerificationCode;

  /// No description provided for @authOtpSentTo.
  ///
  /// In fr, this message translates to:
  /// **'Nous avons envoyé un code par SMS au {phone}.'**
  String authOtpSentTo(String phone);

  /// No description provided for @authEnterPhone.
  ///
  /// In fr, this message translates to:
  /// **'Saisissez votre téléphone pour vérifier votre compte.'**
  String get authEnterPhone;

  /// No description provided for @authPhone.
  ///
  /// In fr, this message translates to:
  /// **'Téléphone'**
  String get authPhone;

  /// No description provided for @authSmsCode.
  ///
  /// In fr, this message translates to:
  /// **'Code SMS'**
  String get authSmsCode;

  /// No description provided for @authResendCode.
  ///
  /// In fr, this message translates to:
  /// **'Renvoyer le code'**
  String get authResendCode;

  /// No description provided for @authChangePhone.
  ///
  /// In fr, this message translates to:
  /// **'Changer de numéro'**
  String get authChangePhone;

  /// No description provided for @authForgotPin.
  ///
  /// In fr, this message translates to:
  /// **'PIN oublié ?'**
  String get authForgotPin;

  /// No description provided for @authCreateAnAccount.
  ///
  /// In fr, this message translates to:
  /// **'Créer un compte'**
  String get authCreateAnAccount;

  /// No description provided for @authDeviceStateTitle.
  ///
  /// In fr, this message translates to:
  /// **'État de l\'appareil'**
  String get authDeviceStateTitle;

  /// No description provided for @authDevicePendingState.
  ///
  /// In fr, this message translates to:
  /// **'En attente'**
  String get authDevicePendingState;

  /// No description provided for @authDeviceBlocked.
  ///
  /// In fr, this message translates to:
  /// **'Appareil bloqué'**
  String get authDeviceBlocked;

  /// No description provided for @authActivationPending.
  ///
  /// In fr, this message translates to:
  /// **'Activation en attente'**
  String get authActivationPending;

  /// No description provided for @authDeviceBlockedMessage.
  ///
  /// In fr, this message translates to:
  /// **'Ce téléphone n\'est pas autorisé à utiliser les tickets carburant. Contactez l\'administrateur.'**
  String get authDeviceBlockedMessage;

  /// No description provided for @authActivationPendingMessage.
  ///
  /// In fr, this message translates to:
  /// **'Vous pourrez utiliser les tickets carburant après la validation de cet appareil par l\'administrateur.'**
  String get authActivationPendingMessage;

  /// No description provided for @authDeviceState.
  ///
  /// In fr, this message translates to:
  /// **'État de l\'appareil : {state}'**
  String authDeviceState(String state);

  /// No description provided for @authCheckAgain.
  ///
  /// In fr, this message translates to:
  /// **'Vérifier à nouveau'**
  String get authCheckAgain;

  /// No description provided for @authLogout.
  ///
  /// In fr, this message translates to:
  /// **'Se déconnecter'**
  String get authLogout;

  /// No description provided for @authPinRecovery.
  ///
  /// In fr, this message translates to:
  /// **'Récupération du PIN'**
  String get authPinRecovery;

  /// No description provided for @authPinRecoveryInstruction.
  ///
  /// In fr, this message translates to:
  /// **'Entrez votre numéro pour recevoir le code de vérification.'**
  String get authPinRecoveryInstruction;

  /// No description provided for @authNumber.
  ///
  /// In fr, this message translates to:
  /// **'Numéro'**
  String get authNumber;

  /// No description provided for @authSendCode.
  ///
  /// In fr, this message translates to:
  /// **'Envoyer le code'**
  String get authSendCode;

  /// No description provided for @authCodeSentBySms.
  ///
  /// In fr, this message translates to:
  /// **'Le code est envoyé par SMS à votre numéro de téléphone.'**
  String get authCodeSentBySms;

  /// No description provided for @authVerifyAndNewPin.
  ///
  /// In fr, this message translates to:
  /// **'Vérification et nouveau PIN'**
  String get authVerifyAndNewPin;

  /// No description provided for @authVerifyAndNewPinInstruction.
  ///
  /// In fr, this message translates to:
  /// **'Saisissez le code reçu par SMS puis choisissez votre nouveau PIN.'**
  String get authVerifyAndNewPinInstruction;

  /// No description provided for @authNewPin.
  ///
  /// In fr, this message translates to:
  /// **'Nouveau PIN'**
  String get authNewPin;

  /// No description provided for @authFourDigits.
  ///
  /// In fr, this message translates to:
  /// **'4 chiffres'**
  String get authFourDigits;

  /// No description provided for @authConfirmPin.
  ///
  /// In fr, this message translates to:
  /// **'Confirmer le PIN'**
  String get authConfirmPin;

  /// No description provided for @authReenterPin.
  ///
  /// In fr, this message translates to:
  /// **'Saisissez à nouveau le PIN'**
  String get authReenterPin;

  /// No description provided for @authPinsMismatch.
  ///
  /// In fr, this message translates to:
  /// **'Les PIN ne correspondent pas.'**
  String get authPinsMismatch;

  /// No description provided for @authSavePin.
  ///
  /// In fr, this message translates to:
  /// **'Enregistrer le PIN'**
  String get authSavePin;

  /// No description provided for @authNewPinInstruction.
  ///
  /// In fr, this message translates to:
  /// **'Choisissez un PIN numérique à 4 chiffres.'**
  String get authNewPinInstruction;

  /// No description provided for @authPin.
  ///
  /// In fr, this message translates to:
  /// **'PIN'**
  String get authPin;

  /// No description provided for @authConfirm.
  ///
  /// In fr, this message translates to:
  /// **'Confirmer'**
  String get authConfirm;

  /// No description provided for @authSave.
  ///
  /// In fr, this message translates to:
  /// **'Enregistrer'**
  String get authSave;

  /// No description provided for @authConfirmPinRequired.
  ///
  /// In fr, this message translates to:
  /// **'Confirmez votre PIN.'**
  String get authConfirmPinRequired;

  /// No description provided for @authRegistrationFailed.
  ///
  /// In fr, this message translates to:
  /// **'Inscription impossible avec ce numéro. Si vous avez déjà un compte, connectez-vous.'**
  String get authRegistrationFailed;

  /// No description provided for @authFullName.
  ///
  /// In fr, this message translates to:
  /// **'Nom complet'**
  String get authFullName;

  /// No description provided for @authNameRequired.
  ///
  /// In fr, this message translates to:
  /// **'Le nom est obligatoire.'**
  String get authNameRequired;

  /// No description provided for @authDefinePin.
  ///
  /// In fr, this message translates to:
  /// **'Définir le PIN'**
  String get authDefinePin;

  /// No description provided for @authRegisterTitle.
  ///
  /// In fr, this message translates to:
  /// **'Créer un compte'**
  String get authRegisterTitle;

  /// No description provided for @authRegisterBrand.
  ///
  /// In fr, this message translates to:
  /// **'Leader Petroleum E-Tickets'**
  String get authRegisterBrand;

  /// No description provided for @authRegisterInstruction.
  ///
  /// In fr, this message translates to:
  /// **'Recevez un code SMS pour vérifier votre compte.'**
  String get authRegisterInstruction;

  /// No description provided for @authSmsSent.
  ///
  /// In fr, this message translates to:
  /// **'Code SMS envoyé.'**
  String get authSmsSent;

  /// No description provided for @authOtpMissingExpired.
  ///
  /// In fr, this message translates to:
  /// **'Code SMS introuvable, expiré ou déjà utilisé. Demandez un nouveau code puis réessayez.'**
  String get authOtpMissingExpired;

  /// No description provided for @authVerification.
  ///
  /// In fr, this message translates to:
  /// **'Vérification'**
  String get authVerification;

  /// No description provided for @authCodeSentShort.
  ///
  /// In fr, this message translates to:
  /// **'Code envoyé à {destination}'**
  String authCodeSentShort(String destination);

  /// No description provided for @authVerify.
  ///
  /// In fr, this message translates to:
  /// **'Vérifier'**
  String get authVerify;

  /// No description provided for @authRequestInProgress.
  ///
  /// In fr, this message translates to:
  /// **'Demande en cours...'**
  String get authRequestInProgress;

  /// No description provided for @authOtpMissing.
  ///
  /// In fr, this message translates to:
  /// **'Code SMS introuvable'**
  String get authOtpMissing;

  /// No description provided for @authRestartRegistrationMessage.
  ///
  /// In fr, this message translates to:
  /// **'Recommencez l\'inscription pour recevoir un nouveau code.'**
  String get authRestartRegistrationMessage;

  /// No description provided for @authRestartRegistration.
  ///
  /// In fr, this message translates to:
  /// **'Recommencer l\'inscription'**
  String get authRestartRegistration;

  /// No description provided for @authBackToLogin.
  ///
  /// In fr, this message translates to:
  /// **'Retour à la connexion'**
  String get authBackToLogin;

  /// No description provided for @authConfirmYour.
  ///
  /// In fr, this message translates to:
  /// **'Confirmez votre'**
  String get authConfirmYour;

  /// No description provided for @authMobileNumber.
  ///
  /// In fr, this message translates to:
  /// **'numéro mobile'**
  String get authMobileNumber;

  /// No description provided for @authUnlockApp.
  ///
  /// In fr, this message translates to:
  /// **'Déverrouiller l\'application'**
  String get authUnlockApp;

  /// No description provided for @authSessionRestored.
  ///
  /// In fr, this message translates to:
  /// **'Session restaurée. Saisissez votre PIN serveur pour continuer.'**
  String get authSessionRestored;

  /// No description provided for @authSessionRestoredFor.
  ///
  /// In fr, this message translates to:
  /// **'Session restaurée pour {name}. Saisissez votre PIN serveur pour continuer.'**
  String authSessionRestoredFor(String name);

  /// No description provided for @authPinFourDigits.
  ///
  /// In fr, this message translates to:
  /// **'PIN à 4 chiffres'**
  String get authPinFourDigits;

  /// No description provided for @authUnlock.
  ///
  /// In fr, this message translates to:
  /// **'Déverrouiller'**
  String get authUnlock;

  /// No description provided for @authCodeSent.
  ///
  /// In fr, this message translates to:
  /// **'Code envoyé.'**
  String get authCodeSent;

  /// No description provided for @authCodeResent.
  ///
  /// In fr, this message translates to:
  /// **'Code renvoyé par SMS.'**
  String get authCodeResent;

  /// No description provided for @authEnterSixDigitCode.
  ///
  /// In fr, this message translates to:
  /// **'Saisissez le code SMS à 6 chiffres.'**
  String get authEnterSixDigitCode;

  /// No description provided for @authPinUpdated.
  ///
  /// In fr, this message translates to:
  /// **'PIN mis à jour. Connectez-vous.'**
  String get authPinUpdated;

  /// No description provided for @authEnterPinFourDigits.
  ///
  /// In fr, this message translates to:
  /// **'Saisissez votre PIN à 4 chiffres.'**
  String get authEnterPinFourDigits;

  /// No description provided for @authRestartToRequestCode.
  ///
  /// In fr, this message translates to:
  /// **'Recommencez l\'inscription pour demander un nouveau code.'**
  String get authRestartToRequestCode;

  /// No description provided for @authNewCodeRequested.
  ///
  /// In fr, this message translates to:
  /// **'Un nouveau code a été demandé.'**
  String get authNewCodeRequested;

  /// No description provided for @authRegistrationIncomplete.
  ///
  /// In fr, this message translates to:
  /// **'L\'inscription n\'a pas pu être finalisée. Réessayez ou contactez l\'administrateur.'**
  String get authRegistrationIncomplete;

  /// No description provided for @authRegistrationUnavailable.
  ///
  /// In fr, this message translates to:
  /// **'L\'inscription n\'est pas disponible sur cet appareil.'**
  String get authRegistrationUnavailable;

  /// No description provided for @authSmsNotConfirmed.
  ///
  /// In fr, this message translates to:
  /// **'Le serveur n\'a pas confirmé l\'envoi du code SMS. Réessayez.'**
  String get authSmsNotConfirmed;

  /// No description provided for @settingsTitle.
  ///
  /// In fr, this message translates to:
  /// **'Mon compte'**
  String get settingsTitle;

  /// No description provided for @settingsQuickAccess.
  ///
  /// In fr, this message translates to:
  /// **'Accès rapide'**
  String get settingsQuickAccess;

  /// No description provided for @settingsPaymentHistory.
  ///
  /// In fr, this message translates to:
  /// **'Historique des paiements'**
  String get settingsPaymentHistory;

  /// No description provided for @settingsPaymentHistorySubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Consultez vos opérations et règlements.'**
  String get settingsPaymentHistorySubtitle;

  /// No description provided for @settingsAccountSecurity.
  ///
  /// In fr, this message translates to:
  /// **'Compte & sécurité'**
  String get settingsAccountSecurity;

  /// No description provided for @settingsDeleteAccount.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer mon compte'**
  String get settingsDeleteAccount;

  /// No description provided for @settingsDeleteAccountSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Contactez le support pour la suppression'**
  String get settingsDeleteAccountSubtitle;

  /// No description provided for @settingsDeleteAccountTitle.
  ///
  /// In fr, this message translates to:
  /// **'Demande de suppression du compte'**
  String get settingsDeleteAccountTitle;

  /// No description provided for @settingsDeleteAccountMessage.
  ///
  /// In fr, this message translates to:
  /// **'La suppression est irréversible. Consultez la procédure officielle ACPEC pour envoyer votre demande et vérifier votre identité.'**
  String get settingsDeleteAccountMessage;

  /// No description provided for @settingsDeletionGuide.
  ///
  /// In fr, this message translates to:
  /// **'Copier le lien de la procédure'**
  String get settingsDeletionGuide;

  /// No description provided for @settingsDeletionLinkCopied.
  ///
  /// In fr, this message translates to:
  /// **'Lien de suppression copié.'**
  String get settingsDeletionLinkCopied;

  /// No description provided for @settingsMemberSince.
  ///
  /// In fr, this message translates to:
  /// **'Membre depuis {date}'**
  String settingsMemberSince(String date);

  /// No description provided for @settingsDevelopedBy.
  ///
  /// In fr, this message translates to:
  /// **'Développée par ACPEC Sarl'**
  String get settingsDevelopedBy;

  /// No description provided for @settingsVersionBuild.
  ///
  /// In fr, this message translates to:
  /// **'Version {version} • Build {build}'**
  String settingsVersionBuild(String version, String build);

  /// No description provided for @settingsPreferences.
  ///
  /// In fr, this message translates to:
  /// **'Préférences'**
  String get settingsPreferences;

  /// No description provided for @settingsLanguage.
  ///
  /// In fr, this message translates to:
  /// **'Langue'**
  String get settingsLanguage;

  /// No description provided for @settingsFrench.
  ///
  /// In fr, this message translates to:
  /// **'Français'**
  String get settingsFrench;

  /// No description provided for @settingsArabic.
  ///
  /// In fr, this message translates to:
  /// **'العربية'**
  String get settingsArabic;

  /// No description provided for @settingsQuickUnlock.
  ///
  /// In fr, this message translates to:
  /// **'Déverrouillage rapide'**
  String get settingsQuickUnlock;

  /// No description provided for @settingsQuickUnlockSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Accédez plus rapidement à l\'application sur cet appareil.'**
  String get settingsQuickUnlockSubtitle;

  /// No description provided for @settingsDarkMode.
  ///
  /// In fr, this message translates to:
  /// **'Mode sombre'**
  String get settingsDarkMode;

  /// No description provided for @settingsDarkModeSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Interface adaptée aux environnements peu éclairés.'**
  String get settingsDarkModeSubtitle;

  /// No description provided for @settingsServiceConnection.
  ///
  /// In fr, this message translates to:
  /// **'Connexion au service'**
  String get settingsServiceConnection;

  /// No description provided for @settingsServiceConnectionSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Vérifier si le service est disponible.'**
  String get settingsServiceConnectionSubtitle;

  /// No description provided for @settingsCreateAccountSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Créer un compte avec le code reçu par SMS.'**
  String get settingsCreateAccountSubtitle;

  /// No description provided for @settingsLogoutTitle.
  ///
  /// In fr, this message translates to:
  /// **'Déconnexion'**
  String get settingsLogoutTitle;

  /// No description provided for @settingsLogoutQuestion.
  ///
  /// In fr, this message translates to:
  /// **'Voulez-vous quitter Leader Petroleum E-Tickets sur cet appareil ?'**
  String get settingsLogoutQuestion;

  /// No description provided for @settingsLogoutSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Fin de session sur cet appareil'**
  String get settingsLogoutSubtitle;

  /// No description provided for @settingsCarnets.
  ///
  /// In fr, this message translates to:
  /// **'Carnets'**
  String get settingsCarnets;

  /// No description provided for @settingsQr.
  ///
  /// In fr, this message translates to:
  /// **'QR'**
  String get settingsQr;

  /// No description provided for @settingsConsumptions.
  ///
  /// In fr, this message translates to:
  /// **'Consommations'**
  String get settingsConsumptions;

  /// No description provided for @notificationsTitle.
  ///
  /// In fr, this message translates to:
  /// **'Notifications'**
  String get notificationsTitle;

  /// No description provided for @notificationsMarkAllRead.
  ///
  /// In fr, this message translates to:
  /// **'Tout lu'**
  String get notificationsMarkAllRead;

  /// No description provided for @notificationsEmptyTitle.
  ///
  /// In fr, this message translates to:
  /// **'Aucune notification'**
  String get notificationsEmptyTitle;

  /// No description provided for @notificationsEmptyMessage.
  ///
  /// In fr, this message translates to:
  /// **'Les commandes validées, QR et transferts apparaîtront ici.'**
  String get notificationsEmptyMessage;

  /// No description provided for @notificationsAmountUnavailable.
  ///
  /// In fr, this message translates to:
  /// **'Montant indisponible'**
  String get notificationsAmountUnavailable;

  /// No description provided for @notificationsQrUnavailable.
  ///
  /// In fr, this message translates to:
  /// **'Code QR indisponible'**
  String get notificationsQrUnavailable;

  /// No description provided for @notificationsViewQr.
  ///
  /// In fr, this message translates to:
  /// **'Voir le QR'**
  String get notificationsViewQr;

  /// No description provided for @purchasesListTitle.
  ///
  /// In fr, this message translates to:
  /// **'Mes commandes'**
  String get purchasesListTitle;

  /// No description provided for @purchasesListSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Chaque carte résume la commande de carnets, le montant total et la date de validation.'**
  String get purchasesListSubtitle;

  /// No description provided for @purchasesCount.
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =0{Aucune commande} =1{1 commande} other{{count} commandes}}'**
  String purchasesCount(num count);

  /// No description provided for @purchasesApproved.
  ///
  /// In fr, this message translates to:
  /// **'Carnets commandés'**
  String get purchasesApproved;

  /// No description provided for @purchasesRejected.
  ///
  /// In fr, this message translates to:
  /// **'Commandes rejetées'**
  String get purchasesRejected;

  /// No description provided for @purchasesConnectionRequired.
  ///
  /// In fr, this message translates to:
  /// **'Connexion requise'**
  String get purchasesConnectionRequired;

  /// No description provided for @purchasesEmptyTitle.
  ///
  /// In fr, this message translates to:
  /// **'Aucune commande'**
  String get purchasesEmptyTitle;

  /// No description provided for @purchasesEmptyMessage.
  ///
  /// In fr, this message translates to:
  /// **'Créez une nouvelle commande pour retrouver ici son montant et sa validation.'**
  String get purchasesEmptyMessage;

  /// No description provided for @purchasesNewOrder.
  ///
  /// In fr, this message translates to:
  /// **'Nouvelle commande'**
  String get purchasesNewOrder;

  /// No description provided for @purchasesCarnetType.
  ///
  /// In fr, this message translates to:
  /// **'Type de carnet'**
  String get purchasesCarnetType;

  /// No description provided for @purchasesValidationDate.
  ///
  /// In fr, this message translates to:
  /// **'Date de validation'**
  String get purchasesValidationDate;

  /// No description provided for @purchasesPendingValidation.
  ///
  /// In fr, this message translates to:
  /// **'En attente de validation'**
  String get purchasesPendingValidation;

  /// No description provided for @filtersTitle.
  ///
  /// In fr, this message translates to:
  /// **'Filtres'**
  String get filtersTitle;

  /// No description provided for @filtersClearAll.
  ///
  /// In fr, this message translates to:
  /// **'Tout effacer'**
  String get filtersClearAll;

  /// No description provided for @filtersViewResults.
  ///
  /// In fr, this message translates to:
  /// **'Voir les résultats'**
  String get filtersViewResults;

  /// No description provided for @commonCloseTooltip.
  ///
  /// In fr, this message translates to:
  /// **'Fermer'**
  String get commonCloseTooltip;

  /// No description provided for @authSessionNotFound.
  ///
  /// In fr, this message translates to:
  /// **'Session introuvable'**
  String get authSessionNotFound;

  /// No description provided for @authReconnectToContinue.
  ///
  /// In fr, this message translates to:
  /// **'Reconnectez-vous pour continuer.'**
  String get authReconnectToContinue;

  /// No description provided for @walletBreakdownTitle.
  ///
  /// In fr, this message translates to:
  /// **'Répartition et suivi'**
  String get walletBreakdownTitle;

  /// No description provided for @walletBreakdownEmptyTitle.
  ///
  /// In fr, this message translates to:
  /// **'Pas encore de détail à afficher'**
  String get walletBreakdownEmptyTitle;

  /// No description provided for @walletBreakdownEmptyMessage.
  ///
  /// In fr, this message translates to:
  /// **'Les différentes répartitions de votre portefeuille apparaîtront ici.'**
  String get walletBreakdownEmptyMessage;

  /// No description provided for @walletByFaceValue.
  ///
  /// In fr, this message translates to:
  /// **'Par valeur de face'**
  String get walletByFaceValue;

  /// No description provided for @walletByFaceValueSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Disponible, QR actif, bloqué, consommé et expiré'**
  String get walletByFaceValueSubtitle;

  /// No description provided for @walletByCarnetType.
  ///
  /// In fr, this message translates to:
  /// **'Par type de carnet'**
  String get walletByCarnetType;

  /// No description provided for @walletByCarnetTypeSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Répartition par carnet'**
  String get walletByCarnetTypeSubtitle;

  /// No description provided for @walletNearExpiration.
  ///
  /// In fr, this message translates to:
  /// **'Tickets proches de l\'expiration'**
  String get walletNearExpiration;

  /// No description provided for @walletWatch.
  ///
  /// In fr, this message translates to:
  /// **'À surveiller'**
  String get walletWatch;

  /// No description provided for @walletExpiredTickets.
  ///
  /// In fr, this message translates to:
  /// **'Tickets expirés'**
  String get walletExpiredTickets;

  /// No description provided for @walletUnusable.
  ///
  /// In fr, this message translates to:
  /// **'Non utilisables'**
  String get walletUnusable;

  /// No description provided for @walletOverview.
  ///
  /// In fr, this message translates to:
  /// **'Vue d\'ensemble'**
  String get walletOverview;

  /// No description provided for @walletActiveCarnets.
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =0{Aucun carnet actif} =1{1 carnet actif} other{{count} carnets actifs}}'**
  String walletActiveCarnets(num count);

  /// No description provided for @walletTicketsAtValue.
  ///
  /// In fr, this message translates to:
  /// **'Tickets à {value}'**
  String walletTicketsAtValue(String value);

  /// No description provided for @walletUsableSummary.
  ///
  /// In fr, this message translates to:
  /// **'{count} utilisables · {amount}'**
  String walletUsableSummary(Object amount, Object count);

  /// No description provided for @walletUnits.
  ///
  /// In fr, this message translates to:
  /// **'{count} unités'**
  String walletUnits(Object count);

  /// No description provided for @walletAvailableTicketsCount.
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =0{Aucun ticket disponible} =1{1 ticket disponible} other{{count} tickets disponibles}}'**
  String walletAvailableTicketsCount(num count);

  /// No description provided for @walletFaceValue.
  ///
  /// In fr, this message translates to:
  /// **'Valeur de face {value}'**
  String walletFaceValue(String value);

  /// No description provided for @walletTicketCountShort.
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =0{0 ticket} =1{1 ticket} other{{count} tickets}}'**
  String walletTicketCountShort(num count);

  /// No description provided for @walletDueDate.
  ///
  /// In fr, this message translates to:
  /// **'Échéance : {date}'**
  String walletDueDate(String date);

  /// No description provided for @walletLot.
  ///
  /// In fr, this message translates to:
  /// **'Lot : {lot}'**
  String walletLot(String lot);

  /// No description provided for @settingsService.
  ///
  /// In fr, this message translates to:
  /// **'Service'**
  String get settingsService;

  /// No description provided for @settingsBiometricUnavailable.
  ///
  /// In fr, this message translates to:
  /// **'Le déverrouillage biométrique n\'est pas disponible sur cet appareil.'**
  String get settingsBiometricUnavailable;

  /// No description provided for @settingsBiometricReason.
  ///
  /// In fr, this message translates to:
  /// **'Confirmez pour activer le déverrouillage biométrique.'**
  String get settingsBiometricReason;

  /// No description provided for @settingsActivationCancelled.
  ///
  /// In fr, this message translates to:
  /// **'Activation annulée.'**
  String get settingsActivationCancelled;

  /// No description provided for @notificationsUnread.
  ///
  /// In fr, this message translates to:
  /// **'Non lues'**
  String get notificationsUnread;

  /// No description provided for @notificationsRead.
  ///
  /// In fr, this message translates to:
  /// **'Lues'**
  String get notificationsRead;

  /// No description provided for @notificationsUpdateMessage.
  ///
  /// In fr, this message translates to:
  /// **'Une nouvelle information est disponible dans votre compte.'**
  String get notificationsUpdateMessage;

  /// No description provided for @statusDraft.
  ///
  /// In fr, this message translates to:
  /// **'Brouillon'**
  String get statusDraft;

  /// No description provided for @statusSubmitted.
  ///
  /// In fr, this message translates to:
  /// **'En attente'**
  String get statusSubmitted;

  /// No description provided for @statusApproved.
  ///
  /// In fr, this message translates to:
  /// **'Validée'**
  String get statusApproved;

  /// No description provided for @statusRejected.
  ///
  /// In fr, this message translates to:
  /// **'Refusée'**
  String get statusRejected;

  /// No description provided for @commonNoItem.
  ///
  /// In fr, this message translates to:
  /// **'Aucun élément'**
  String get commonNoItem;

  /// No description provided for @quantity.
  ///
  /// In fr, this message translates to:
  /// **'Quantité'**
  String get quantity;

  /// No description provided for @faceValue.
  ///
  /// In fr, this message translates to:
  /// **'Valeur de face'**
  String get faceValue;

  /// No description provided for @lotReference.
  ///
  /// In fr, this message translates to:
  /// **'Référence du lot'**
  String get lotReference;

  /// No description provided for @purchaseDeviceApprovalRequired.
  ///
  /// In fr, this message translates to:
  /// **'Cet appareil doit être validé avant de pouvoir créer une commande.'**
  String get purchaseDeviceApprovalRequired;

  /// No description provided for @purchaseProofLoadFailed.
  ///
  /// In fr, this message translates to:
  /// **'Impossible de charger la preuve de paiement.'**
  String get purchaseProofLoadFailed;

  /// No description provided for @purchaseActionUnavailable.
  ///
  /// In fr, this message translates to:
  /// **'Cette action n\'est pas disponible pour cette commande.'**
  String get purchaseActionUnavailable;

  /// No description provided for @purchaseDownloadUnavailable.
  ///
  /// In fr, this message translates to:
  /// **'Téléchargement indisponible.'**
  String get purchaseDownloadUnavailable;

  /// No description provided for @purchaseProofDownloadFailed.
  ///
  /// In fr, this message translates to:
  /// **'Impossible de télécharger la preuve.'**
  String get purchaseProofDownloadFailed;

  /// No description provided for @authRestartFromForgotPin.
  ///
  /// In fr, this message translates to:
  /// **'Reprenez depuis l\'écran PIN oublié.'**
  String get authRestartFromForgotPin;

  /// No description provided for @authRestartFromOtp.
  ///
  /// In fr, this message translates to:
  /// **'Reprenez depuis la vérification du code SMS.'**
  String get authRestartFromOtp;

  /// No description provided for @supportReference.
  ///
  /// In fr, this message translates to:
  /// **'Référence support : {reference}'**
  String supportReference(String reference);

  /// No description provided for @apiRequiredTitle.
  ///
  /// In fr, this message translates to:
  /// **'Service indisponible'**
  String get apiRequiredTitle;

  /// No description provided for @apiRequiredMessage.
  ///
  /// In fr, this message translates to:
  /// **'Impossible de charger les données pour le moment. Vérifiez votre connexion et réessayez.'**
  String get apiRequiredMessage;

  /// No description provided for @serviceStatusTitle.
  ///
  /// In fr, this message translates to:
  /// **'État du service'**
  String get serviceStatusTitle;

  /// No description provided for @serviceCheckUnavailable.
  ///
  /// In fr, this message translates to:
  /// **'Le service ne peut pas être vérifié sur cet appareil pour le moment.'**
  String get serviceCheckUnavailable;

  /// No description provided for @serviceConnectionFailed.
  ///
  /// In fr, this message translates to:
  /// **'Connexion au service impossible. Vérifiez votre réseau et réessayez.'**
  String get serviceConnectionFailed;

  /// No description provided for @commonUnexpectedError.
  ///
  /// In fr, this message translates to:
  /// **'Une erreur inattendue s\'est produite. Réessayez plus tard.'**
  String get commonUnexpectedError;

  /// No description provided for @installedVersion.
  ///
  /// In fr, this message translates to:
  /// **'Version installée : {version}'**
  String installedVersion(String version);

  /// No description provided for @updateRequiredTitle.
  ///
  /// In fr, this message translates to:
  /// **'Mise à jour requise'**
  String get updateRequiredTitle;

  /// No description provided for @updateRequiredMessage.
  ///
  /// In fr, this message translates to:
  /// **'Installez la dernière version de Leader Petroleum E-Tickets pour continuer à utiliser le service.'**
  String get updateRequiredMessage;

  /// No description provided for @serviceUnavailableTitle.
  ///
  /// In fr, this message translates to:
  /// **'Service indisponible'**
  String get serviceUnavailableTitle;

  /// No description provided for @serviceUnavailableMessage.
  ///
  /// In fr, this message translates to:
  /// **'Le service ne répond pas correctement. Réessayez dans quelques instants.'**
  String get serviceUnavailableMessage;

  /// No description provided for @updateAvailableTitle.
  ///
  /// In fr, this message translates to:
  /// **'Mise à jour disponible'**
  String get updateAvailableTitle;

  /// No description provided for @updateAvailableMessage.
  ///
  /// In fr, this message translates to:
  /// **'Une version plus récente est disponible. Mettez l\'application à jour dès que possible.'**
  String get updateAvailableMessage;

  /// No description provided for @serviceReadyTitle.
  ///
  /// In fr, this message translates to:
  /// **'Tout est en ordre'**
  String get serviceReadyTitle;

  /// No description provided for @serviceReadyMessage.
  ///
  /// In fr, this message translates to:
  /// **'Votre application est à jour et le service répond normalement.'**
  String get serviceReadyMessage;

  /// No description provided for @organizationsAvailable.
  ///
  /// In fr, this message translates to:
  /// **'Organisations disponibles'**
  String get organizationsAvailable;

  /// No description provided for @organizationsEmptyTitle.
  ///
  /// In fr, this message translates to:
  /// **'Aucune organisation'**
  String get organizationsEmptyTitle;

  /// No description provided for @organizationsEmptyMessage.
  ///
  /// In fr, this message translates to:
  /// **'Aucune organisation à afficher pour le moment.'**
  String get organizationsEmptyMessage;

  /// No description provided for @developmentDetails.
  ///
  /// In fr, this message translates to:
  /// **'Détail (mode développement)'**
  String get developmentDetails;

  /// No description provided for @signupSmsIntro.
  ///
  /// In fr, this message translates to:
  /// **'L\'inscription se fait avec le code reçu par SMS.'**
  String get signupSmsIntro;

  /// No description provided for @signupSmsInstructions.
  ///
  /// In fr, this message translates to:
  /// **'Renseignez vos informations sur l\'écran d\'inscription, puis validez le code reçu pour créer votre compte.'**
  String get signupSmsInstructions;

  /// No description provided for @openRegistration.
  ///
  /// In fr, this message translates to:
  /// **'Ouvrir l\'inscription'**
  String get openRegistration;

  /// No description provided for @walletStatusAvailable.
  ///
  /// In fr, this message translates to:
  /// **'Disponible'**
  String get walletStatusAvailable;

  /// No description provided for @walletStatusActiveQr.
  ///
  /// In fr, this message translates to:
  /// **'En QR actif'**
  String get walletStatusActiveQr;

  /// No description provided for @walletStatusBlocked.
  ///
  /// In fr, this message translates to:
  /// **'Bloqué'**
  String get walletStatusBlocked;

  /// No description provided for @walletStatusConsumed.
  ///
  /// In fr, this message translates to:
  /// **'Consommé'**
  String get walletStatusConsumed;

  /// No description provided for @walletStatusExpired.
  ///
  /// In fr, this message translates to:
  /// **'Expiré'**
  String get walletStatusExpired;

  /// No description provided for @commonNotProvided.
  ///
  /// In fr, this message translates to:
  /// **'Non renseigné'**
  String get commonNotProvided;

  /// No description provided for @purchaseUnconfirmed.
  ///
  /// In fr, this message translates to:
  /// **'Action non confirmée. Vérifiez l\'état de la commande avant de réessayer.'**
  String get purchaseUnconfirmed;

  /// No description provided for @purchaseCannotOpen.
  ///
  /// In fr, this message translates to:
  /// **'Cette commande ne peut pas être ouverte. Vérifiez le lien ou réessayez.'**
  String get purchaseCannotOpen;

  /// No description provided for @purchaseOperationFailed.
  ///
  /// In fr, this message translates to:
  /// **'L\'opération n\'a pas abouti. Réessayez ou reconnectez-vous.'**
  String get purchaseOperationFailed;

  /// No description provided for @qrUnconfirmed.
  ///
  /// In fr, this message translates to:
  /// **'Action non confirmée. Vérifiez la liste de vos QR avant de réessayer.'**
  String get qrUnconfirmed;

  /// No description provided for @languageSelectionTitle.
  ///
  /// In fr, this message translates to:
  /// **'Choisissez votre langue'**
  String get languageSelectionTitle;

  /// No description provided for @languageSelectionMessage.
  ///
  /// In fr, this message translates to:
  /// **'Vous pourrez modifier ce choix plus tard dans les réglages.'**
  String get languageSelectionMessage;

  /// No description provided for @languageSelectionContinue.
  ///
  /// In fr, this message translates to:
  /// **'Continuer'**
  String get languageSelectionContinue;

  /// No description provided for @stationNavHome.
  ///
  /// In fr, this message translates to:
  /// **'Accueil'**
  String get stationNavHome;

  /// No description provided for @stationNavScan.
  ///
  /// In fr, this message translates to:
  /// **'Scanner'**
  String get stationNavScan;

  /// No description provided for @stationAgentFallback.
  ///
  /// In fr, this message translates to:
  /// **'Agent station'**
  String get stationAgentFallback;

  /// No description provided for @stationAgentAtStation.
  ///
  /// In fr, this message translates to:
  /// **'Agent station · {stationName}'**
  String stationAgentAtStation(String stationName);

  /// No description provided for @stationAgentProfile.
  ///
  /// In fr, this message translates to:
  /// **'Profil de l\'agent station'**
  String get stationAgentProfile;

  /// No description provided for @stationScanQr.
  ///
  /// In fr, this message translates to:
  /// **'Scanner un QR'**
  String get stationScanQr;

  /// No description provided for @stationScanPrompt.
  ///
  /// In fr, this message translates to:
  /// **'Appuyez pour scanner le QR du client'**
  String get stationScanPrompt;

  /// No description provided for @stationManualEntry.
  ///
  /// In fr, this message translates to:
  /// **'Saisir un code manuel'**
  String get stationManualEntry;

  /// No description provided for @stationManualEquivalent.
  ///
  /// In fr, this message translates to:
  /// **'Même opération que le scan du QR client'**
  String get stationManualEquivalent;

  /// No description provided for @stationConsumptionHistory.
  ///
  /// In fr, this message translates to:
  /// **'Historique des consommations'**
  String get stationConsumptionHistory;

  /// No description provided for @stationProfileTitle.
  ///
  /// In fr, this message translates to:
  /// **'Profil'**
  String get stationProfileTitle;

  /// No description provided for @stationInformation.
  ///
  /// In fr, this message translates to:
  /// **'Informations'**
  String get stationInformation;

  /// No description provided for @stationNameLabel.
  ///
  /// In fr, this message translates to:
  /// **'Nom'**
  String get stationNameLabel;

  /// No description provided for @stationCodeLabel.
  ///
  /// In fr, this message translates to:
  /// **'Code'**
  String get stationCodeLabel;

  /// No description provided for @stationAddressLabel.
  ///
  /// In fr, this message translates to:
  /// **'Adresse'**
  String get stationAddressLabel;

  /// No description provided for @stationStatusLabel.
  ///
  /// In fr, this message translates to:
  /// **'Statut'**
  String get stationStatusLabel;

  /// No description provided for @stationInService.
  ///
  /// In fr, this message translates to:
  /// **'En service'**
  String get stationInService;

  /// No description provided for @stationOutOfService.
  ///
  /// In fr, this message translates to:
  /// **'Hors service'**
  String get stationOutOfService;

  /// No description provided for @stationPreferences.
  ///
  /// In fr, this message translates to:
  /// **'Préférences'**
  String get stationPreferences;

  /// No description provided for @stationDarkModeSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Appliqué à toute l\'application sur cet appareil.'**
  String get stationDarkModeSubtitle;

  /// No description provided for @stationLogout.
  ///
  /// In fr, this message translates to:
  /// **'Se déconnecter'**
  String get stationLogout;

  /// No description provided for @stationProfileServerRequired.
  ///
  /// In fr, this message translates to:
  /// **'Connectez-vous au service pour afficher le profil de la station.'**
  String get stationProfileServerRequired;

  /// No description provided for @stationLinkedOperator.
  ///
  /// In fr, this message translates to:
  /// **'Station liée et opérateur mobile.'**
  String get stationLinkedOperator;

  /// No description provided for @stationMobileOperator.
  ///
  /// In fr, this message translates to:
  /// **'Opérateur mobile'**
  String get stationMobileOperator;

  /// No description provided for @stationEmailLabel.
  ///
  /// In fr, this message translates to:
  /// **'E-mail'**
  String get stationEmailLabel;

  /// No description provided for @stationPhoneLabel.
  ///
  /// In fr, this message translates to:
  /// **'Téléphone'**
  String get stationPhoneLabel;

  /// No description provided for @stationSessionExpired.
  ///
  /// In fr, this message translates to:
  /// **'Session expirée. Reconnectez-vous.'**
  String get stationSessionExpired;

  /// No description provided for @stationCameraUnavailable.
  ///
  /// In fr, this message translates to:
  /// **'Caméra indisponible. Vérifiez les autorisations puis réessayez.'**
  String get stationCameraUnavailable;

  /// No description provided for @stationQrNotConsumable.
  ///
  /// In fr, this message translates to:
  /// **'QR non consommable'**
  String get stationQrNotConsumable;

  /// No description provided for @stationQrAlreadyConsumed.
  ///
  /// In fr, this message translates to:
  /// **'Ce QR a déjà été consommé et ne peut plus être utilisé.'**
  String get stationQrAlreadyConsumed;

  /// No description provided for @stationQrNotConsumableMessage.
  ///
  /// In fr, this message translates to:
  /// **'Ce QR ne peut pas être consommé.'**
  String get stationQrNotConsumableMessage;

  /// No description provided for @stationBackHome.
  ///
  /// In fr, this message translates to:
  /// **'Retour à l\'accueil'**
  String get stationBackHome;

  /// No description provided for @stationVerificationImpossible.
  ///
  /// In fr, this message translates to:
  /// **'Vérification impossible'**
  String get stationVerificationImpossible;

  /// No description provided for @stationBackToScan.
  ///
  /// In fr, this message translates to:
  /// **'Retour au scanner'**
  String get stationBackToScan;

  /// No description provided for @stationBackToEntry.
  ///
  /// In fr, this message translates to:
  /// **'Retour à la saisie'**
  String get stationBackToEntry;

  /// No description provided for @stationPinVerification.
  ///
  /// In fr, this message translates to:
  /// **'Vérification du PIN'**
  String get stationPinVerification;

  /// No description provided for @stationPinScanDescription.
  ///
  /// In fr, this message translates to:
  /// **'Saisissez votre PIN pour confirmer cette opération.'**
  String get stationPinScanDescription;

  /// No description provided for @stationPinManualDescription.
  ///
  /// In fr, this message translates to:
  /// **'Saisissez votre PIN station pour consommer ce QR.'**
  String get stationPinManualDescription;

  /// No description provided for @stationConsumptionRejected.
  ///
  /// In fr, this message translates to:
  /// **'Consommation du QR refusée par le service.'**
  String get stationConsumptionRejected;

  /// No description provided for @stationConsumptionFailed.
  ///
  /// In fr, this message translates to:
  /// **'La consommation du QR a échoué. Réessayez ou contactez l\'administrateur.'**
  String get stationConsumptionFailed;

  /// No description provided for @stationConsumptionUnconfirmed.
  ///
  /// In fr, this message translates to:
  /// **'Consommation non confirmée'**
  String get stationConsumptionUnconfirmed;

  /// No description provided for @stationConsumptionUnconfirmedMessage.
  ///
  /// In fr, this message translates to:
  /// **'L\'opération n\'a pas été confirmée. Vérifiez l\'historique avant de réessayer.'**
  String get stationConsumptionUnconfirmedMessage;

  /// No description provided for @stationOperationRejected.
  ///
  /// In fr, this message translates to:
  /// **'Opération refusée'**
  String get stationOperationRejected;

  /// No description provided for @stationScannerTitle.
  ///
  /// In fr, this message translates to:
  /// **'Scanner le QR du client'**
  String get stationScannerTitle;

  /// No description provided for @stationScannerSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Placez le QR du client dans le cadre pour le vérifier.'**
  String get stationScannerSubtitle;

  /// No description provided for @stationReactivateCamera.
  ///
  /// In fr, this message translates to:
  /// **'Réactiver la caméra'**
  String get stationReactivateCamera;

  /// No description provided for @stationQrVerificationTitle.
  ///
  /// In fr, this message translates to:
  /// **'Vérification du QR'**
  String get stationQrVerificationTitle;

  /// No description provided for @stationQrVerificationSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Contrôle avant consommation'**
  String get stationQrVerificationSubtitle;

  /// No description provided for @stationTotalAmount.
  ///
  /// In fr, this message translates to:
  /// **'Montant total'**
  String get stationTotalAmount;

  /// No description provided for @stationClient.
  ///
  /// In fr, this message translates to:
  /// **'Client'**
  String get stationClient;

  /// No description provided for @stationConsumptionAllowed.
  ///
  /// In fr, this message translates to:
  /// **'Consommation autorisée'**
  String get stationConsumptionAllowed;

  /// No description provided for @stationConsumptionAllowedMessage.
  ///
  /// In fr, this message translates to:
  /// **'Vous pouvez enregistrer la consommation de ce QR.'**
  String get stationConsumptionAllowedMessage;

  /// No description provided for @stationValidating.
  ///
  /// In fr, this message translates to:
  /// **'Validation…'**
  String get stationValidating;

  /// No description provided for @stationQrConsumedSuccess.
  ///
  /// In fr, this message translates to:
  /// **'QR consommé avec succès'**
  String get stationQrConsumedSuccess;

  /// No description provided for @stationConsumptionRecorded.
  ///
  /// In fr, this message translates to:
  /// **'La consommation a bien été enregistrée.'**
  String get stationConsumptionRecorded;

  /// No description provided for @stationDateTime.
  ///
  /// In fr, this message translates to:
  /// **'Date et heure'**
  String get stationDateTime;

  /// No description provided for @stationTransactionNumber.
  ///
  /// In fr, this message translates to:
  /// **'N° de transaction'**
  String get stationTransactionNumber;

  /// No description provided for @stationFinish.
  ///
  /// In fr, this message translates to:
  /// **'Terminer'**
  String get stationFinish;

  /// No description provided for @stationManualTitle.
  ///
  /// In fr, this message translates to:
  /// **'Saisie manuelle'**
  String get stationManualTitle;

  /// No description provided for @stationManualInstruction.
  ///
  /// In fr, this message translates to:
  /// **'Saisissez le code numérique affiché par le client. Cette opération est identique au scan du QR.'**
  String get stationManualInstruction;

  /// No description provided for @stationManualClientCode.
  ///
  /// In fr, this message translates to:
  /// **'Code manuel du client'**
  String get stationManualClientCode;

  /// No description provided for @stationManualFormat.
  ///
  /// In fr, this message translates to:
  /// **'Format attendu : 1234-5678-9012'**
  String get stationManualFormat;

  /// No description provided for @stationChecking.
  ///
  /// In fr, this message translates to:
  /// **'Vérification…'**
  String get stationChecking;

  /// No description provided for @stationCheck.
  ///
  /// In fr, this message translates to:
  /// **'Vérifier'**
  String get stationCheck;

  /// No description provided for @stationConsumable.
  ///
  /// In fr, this message translates to:
  /// **'Consommable'**
  String get stationConsumable;

  /// No description provided for @stationConsuming.
  ///
  /// In fr, this message translates to:
  /// **'Consommation…'**
  String get stationConsuming;

  /// No description provided for @stationConsume.
  ///
  /// In fr, this message translates to:
  /// **'Consommer'**
  String get stationConsume;

  /// No description provided for @stationEnterManualCode.
  ///
  /// In fr, this message translates to:
  /// **'Saisissez le code manuel affiché au client.'**
  String get stationEnterManualCode;

  /// No description provided for @stationCheckCodeFirst.
  ///
  /// In fr, this message translates to:
  /// **'Vérifiez le code manuel avant la consommation.'**
  String get stationCheckCodeFirst;

  /// No description provided for @stationHistorySubtitle.
  ///
  /// In fr, this message translates to:
  /// **'QR consommés par période'**
  String get stationHistorySubtitle;

  /// No description provided for @stationFilterAll.
  ///
  /// In fr, this message translates to:
  /// **'Tous'**
  String get stationFilterAll;

  /// No description provided for @stationFilterPending.
  ///
  /// In fr, this message translates to:
  /// **'Non régularisé'**
  String get stationFilterPending;

  /// No description provided for @stationFilterRegularized.
  ///
  /// In fr, this message translates to:
  /// **'Régularisé'**
  String get stationFilterRegularized;

  /// No description provided for @stationHistoryPartial.
  ///
  /// In fr, this message translates to:
  /// **'Résultat partiel : trop de consommations pour cette période. Réduisez la période choisie.'**
  String get stationHistoryPartial;

  /// No description provided for @stationHistoryPartialCount.
  ///
  /// In fr, this message translates to:
  /// **'Résultat partiel : {loaded} sur {total} consommations chargées. Réduisez la période choisie.'**
  String stationHistoryPartialCount(int loaded, int total);

  /// No description provided for @stationHistoryEndTitle.
  ///
  /// In fr, this message translates to:
  /// **'Fin de l\'historique'**
  String get stationHistoryEndTitle;

  /// No description provided for @stationHistoryEndMessage.
  ///
  /// In fr, this message translates to:
  /// **'Aucune autre consommation enregistrée.'**
  String get stationHistoryEndMessage;

  /// No description provided for @stationHistorySummary.
  ///
  /// In fr, this message translates to:
  /// **'Résumé des QR consommés'**
  String get stationHistorySummary;

  /// No description provided for @stationConsumedQr.
  ///
  /// In fr, this message translates to:
  /// **'QR consommés'**
  String get stationConsumedQr;

  /// No description provided for @stationTotal.
  ///
  /// In fr, this message translates to:
  /// **'Montant total'**
  String get stationTotal;

  /// No description provided for @stationUnknownClient.
  ///
  /// In fr, this message translates to:
  /// **'Client inconnu'**
  String get stationUnknownClient;

  /// No description provided for @stationUnknownStation.
  ///
  /// In fr, this message translates to:
  /// **'Station inconnue'**
  String get stationUnknownStation;

  /// No description provided for @stationFuelConsumption.
  ///
  /// In fr, this message translates to:
  /// **'Consommation de carburant'**
  String get stationFuelConsumption;

  /// No description provided for @stationQrDetail.
  ///
  /// In fr, this message translates to:
  /// **'Détail du QR'**
  String get stationQrDetail;

  /// No description provided for @stationConsumptionDate.
  ///
  /// In fr, this message translates to:
  /// **'Date de consommation'**
  String get stationConsumptionDate;

  /// No description provided for @stationRegularizationStatus.
  ///
  /// In fr, this message translates to:
  /// **'État de régularisation'**
  String get stationRegularizationStatus;

  /// No description provided for @stationRegularizationReference.
  ///
  /// In fr, this message translates to:
  /// **'Référence de régularisation'**
  String get stationRegularizationReference;

  /// No description provided for @stationRegularizationDate.
  ///
  /// In fr, this message translates to:
  /// **'Date de régularisation'**
  String get stationRegularizationDate;

  /// No description provided for @stationConsumptionDetail.
  ///
  /// In fr, this message translates to:
  /// **'Détail de la consommation'**
  String get stationConsumptionDetail;

  /// No description provided for @stationQrCode.
  ///
  /// In fr, this message translates to:
  /// **'Code QR'**
  String get stationQrCode;

  /// No description provided for @stationTransactionIdentifier.
  ///
  /// In fr, this message translates to:
  /// **'Identifiant de transaction'**
  String get stationTransactionIdentifier;

  /// No description provided for @stationClientIdentifier.
  ///
  /// In fr, this message translates to:
  /// **'Identifiant du client'**
  String get stationClientIdentifier;

  /// No description provided for @stationStationIdentifier.
  ///
  /// In fr, this message translates to:
  /// **'Identifiant de la station'**
  String get stationStationIdentifier;

  /// No description provided for @stationQrIdentifier.
  ///
  /// In fr, this message translates to:
  /// **'Identifiant du QR'**
  String get stationQrIdentifier;

  /// No description provided for @stationLotIdentifier.
  ///
  /// In fr, this message translates to:
  /// **'Identifiant du lot'**
  String get stationLotIdentifier;

  /// No description provided for @stationOperatorIdentifier.
  ///
  /// In fr, this message translates to:
  /// **'Identifiant de l’opérateur'**
  String get stationOperatorIdentifier;

  /// No description provided for @stationManualExample.
  ///
  /// In fr, this message translates to:
  /// **'Ex. 1234-5678-9012'**
  String get stationManualExample;

  /// No description provided for @paymentHistoryScreenSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Vos achats et leurs justificatifs de paiement'**
  String get paymentHistoryScreenSubtitle;

  /// No description provided for @paymentHistoryEmptyTitle.
  ///
  /// In fr, this message translates to:
  /// **'Aucun paiement'**
  String get paymentHistoryEmptyTitle;

  /// No description provided for @paymentHistoryEmptyMessage.
  ///
  /// In fr, this message translates to:
  /// **'Vos achats effectués apparaîtront ici avec leur preuve de paiement.'**
  String get paymentHistoryEmptyMessage;

  /// No description provided for @paymentHistoryPurchaseDetails.
  ///
  /// In fr, this message translates to:
  /// **'Détails de l’achat'**
  String get paymentHistoryPurchaseDetails;

  /// No description provided for @paymentHistoryPurchaseReference.
  ///
  /// In fr, this message translates to:
  /// **'Référence de l’achat'**
  String get paymentHistoryPurchaseReference;

  /// No description provided for @paymentHistoryCarnetsCount.
  ///
  /// In fr, this message translates to:
  /// **'Nombre de carnets'**
  String get paymentHistoryCarnetsCount;

  /// No description provided for @paymentHistoryTicketsCount.
  ///
  /// In fr, this message translates to:
  /// **'Nombre de tickets'**
  String get paymentHistoryTicketsCount;

  /// No description provided for @paymentHistoryOpenProof.
  ///
  /// In fr, this message translates to:
  /// **'Ouvrir'**
  String get paymentHistoryOpenProof;

  /// No description provided for @paymentHistoryViewProof.
  ///
  /// In fr, this message translates to:
  /// **'Voir la preuve'**
  String get paymentHistoryViewProof;

  /// No description provided for @paymentHistoryProofDownloaded.
  ///
  /// In fr, this message translates to:
  /// **'La preuve de paiement a été téléchargée.'**
  String get paymentHistoryProofDownloaded;

  /// No description provided for @paymentHistoryProofUnavailable.
  ///
  /// In fr, this message translates to:
  /// **'La preuve de paiement est temporairement indisponible.'**
  String get paymentHistoryProofUnavailable;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
