// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'Leader Petroleum E-Tickets';

  @override
  String get homeVerifiedAccount => 'Compte vérifié';

  @override
  String get homeQuickActions => 'Actions rapides';

  @override
  String get homeBuyCarnets => 'Commander des carnets';

  @override
  String get homeWalletTitle => 'Portefeuille Leader Petroleum';

  @override
  String get homeGenerateQr => 'Générer un QR';

  @override
  String get homeTransferCarnets => 'Transférer des carnets';

  @override
  String get homeTransferTickets => 'Transférer des tickets';

  @override
  String get commonRetry => 'Réessayer';

  @override
  String get navHome => 'Accueil';

  @override
  String get navCarnets => 'Carnets';

  @override
  String get navQr => 'QR';

  @override
  String get navWallet => 'Portefeuille';

  @override
  String get navHistory => 'Historique';

  @override
  String get carnetsTitle => 'Mes carnets';

  @override
  String get carnet => 'Carnet';

  @override
  String get carnetCodeUnavailable => 'Code carnet indisponible';

  @override
  String get carnetStatusExpired => 'Expiré';

  @override
  String get carnetStatusAvailable => 'Disponible';

  @override
  String get carnetStatusUnavailable => 'Indisponible';

  @override
  String carnetWithCode(String code) {
    return 'Carnet $code';
  }

  @override
  String carnetTypeFallback(String size, String value, String currency) {
    return 'Carnet - $size tickets x $value $currency';
  }

  @override
  String get carnetsLoadError => 'Erreur de chargement';

  @override
  String get carnetsEmptyTitle => 'Aucun carnet';

  @override
  String get carnetsEmptyMessage =>
      'Vous n\'avez encore aucun carnet disponible.';

  @override
  String filteredEmptyTitle(String filter) {
    return 'Aucun résultat pour « $filter »';
  }

  @override
  String carnetsFilteredEmptyMessage(String filter) {
    return 'Aucun carnet ne correspond au filtre « $filter » pour le moment.';
  }

  @override
  String get carnetsSummaryTitle => 'Résumé portefeuille';

  @override
  String get carnetsAvailableTickets => 'Tickets disponibles';

  @override
  String get carnetsValue => 'Valeur';

  @override
  String get carnetsActiveQr => 'QR actifs';

  @override
  String get carnetsExpired => 'Expirés';

  @override
  String get filterAll => 'Tous';

  @override
  String get filterAvailable => 'Disponibles';

  @override
  String get filterExpired => 'Expirés';

  @override
  String get carnetDetailTitle => 'Détail Carnet';

  @override
  String get carnetDetailDescription => 'Détail des tickets de ce carnet.';

  @override
  String get referenceCode => 'Code de référence';

  @override
  String get carnetFullNumber => 'N° complet du carnet';

  @override
  String get consumedQr => 'QR consommés';

  @override
  String get availableAmount => 'Montant disponible';

  @override
  String get notAvailable => 'Non disponible';

  @override
  String carnetExpiresOn(String date) {
    return 'Expire le $date';
  }

  @override
  String get qrsTitle => 'Mes QR';

  @override
  String get qrFilterActive => 'Actifs';

  @override
  String get qrFilterBlocked => 'Bloqués';

  @override
  String get qrFilterConsumed => 'Consommés';

  @override
  String get qrStatusActive => 'Actif';

  @override
  String get qrStatusBlocked => 'Bloqué';

  @override
  String get qrStatusConsumed => 'Consommé';

  @override
  String get qrStatusExpired => 'Expiré';

  @override
  String get qrsLoadError => 'Erreur de chargement';

  @override
  String get qrsEmptyTitle => 'Aucun QR';

  @override
  String get qrsNoResults => 'Aucun résultat';

  @override
  String get qrsEmptyMessage => 'Aucun QR n’est disponible pour le moment.';

  @override
  String get qrsFilterEmptyMessage =>
      'Ce filtre ne contient aucun QR. Essayez un autre filtre ou revenez à tous les résultats.';

  @override
  String qrsFilteredEmptyMessage(String filter) {
    return 'Aucun QR ne correspond au filtre « $filter » pour le moment.';
  }

  @override
  String get commonRefresh => 'Actualiser';

  @override
  String get sessionExpiredReconnect => 'Session expirée. Reconnectez-vous.';

  @override
  String get qrExpirationUndefined => 'Expiration non définie';

  @override
  String qrExpiresFrom(String date) {
    return 'Expire dès $date';
  }

  @override
  String qrConsumedOn(String date) {
    return 'Consommé le $date';
  }

  @override
  String qrExpiredFrom(String date) {
    return 'Expiré dès $date';
  }

  @override
  String get qrPartialExpiration => 'Expiration partielle détectée';

  @override
  String get walletMovementsTitle => 'Mouvements du portefeuille';

  @override
  String get transactionsHistoryTitle => 'Historique des opérations';

  @override
  String get stationHistoryTitle => 'Historique station';

  @override
  String get globalHistoryTitle => 'Historique global';

  @override
  String get walletEmptyTitle =>
      'Aucun mouvement de portefeuille pour l\'instant';

  @override
  String get walletEmptyMessage =>
      'Les commandes validées, générations de QR, transferts, réceptions et expirations apparaîtront ici.';

  @override
  String walletFilteredEmptyMessage(String filter) {
    return 'Aucun mouvement ne correspond au filtre « $filter » pour le moment.';
  }

  @override
  String get historyEmptyTitle => 'Aucun mouvement pour l\'instant';

  @override
  String get historyEmptyMessage =>
      'Vos commandes, la génération de QR et vos utilisations apparaîtront ici.';

  @override
  String historyFilteredEmptyMessage(String filter) {
    return 'Aucune opération ne correspond au filtre « $filter » pour le moment.';
  }

  @override
  String get stationHistoryEmptyTitle => 'Aucune consommation';

  @override
  String get stationHistoryEmptyMessage =>
      'Aucune consommation enregistrée pour cette période.';

  @override
  String get globalHistoryEmptyTitle => 'Historique vide';

  @override
  String get globalHistoryEmptyMessage =>
      'Synchronisez ou ajoutez des données : l\'historique global se remplira automatiquement.';

  @override
  String get dateFrom => 'Du';

  @override
  String get dateTo => 'Au';

  @override
  String get dateApply => 'Appliquer la période';

  @override
  String get loadNextPage => 'Charger la page suivante';

  @override
  String get scrollToLoadMore => 'Faites défiler pour charger plus';

  @override
  String get historyPeriodEnd => 'Fin de l\'historique pour cette période';

  @override
  String get today => 'Aujourd\'hui';

  @override
  String get yesterday => 'Hier';

  @override
  String get detail => 'Détail';

  @override
  String get filterPurchases => 'Achats';

  @override
  String get filterQrGenerations => 'Générations QR';

  @override
  String get filterTransfers => 'Transferts';

  @override
  String get filterReceipts => 'Réceptions';

  @override
  String get filterExpirations => 'Expirations';

  @override
  String get filterOrders => 'Commandes';

  @override
  String get filterSentReceived => 'Envoi / reçu';

  @override
  String get filterConsumption => 'Consommation';

  @override
  String get txOrderSubmitted => 'Commande de carnets';

  @override
  String get txOrderValidated => 'Carnets commandés';

  @override
  String get txOrderRejected => 'Commande de carnets rejetée';

  @override
  String get txQrGeneration => 'Génération de QR';

  @override
  String get txQrSplit => 'Séparation du QR';

  @override
  String get txQrWithdrawal => 'Retrait de tickets';

  @override
  String get txTicketTransfer => 'Transfert de tickets';

  @override
  String get txTicketReceipt => 'Réception de tickets';

  @override
  String get txCarnetTransfer => 'Transfert de carnets';

  @override
  String get txCarnetReceipt => 'Réception de carnets';

  @override
  String get txQrBlocked => 'QR bloqué';

  @override
  String get txFuelConsumption => 'Consommation de carburant';

  @override
  String get txQrExpiration => 'Expiration QR';

  @override
  String get walletCarnetExpiration => 'Expiration de carnet';

  @override
  String get txMovement => 'Mouvement';

  @override
  String get publicReference => 'Référence publique';

  @override
  String get buyer => 'Acheteur';

  @override
  String get note => 'Note';

  @override
  String get tickets => 'Tickets';

  @override
  String get withdrawnTickets => 'Tickets retirés';

  @override
  String get sender => 'Expéditeur';

  @override
  String get beneficiary => 'Bénéficiaire';

  @override
  String get station => 'Station';

  @override
  String get attendant => 'Pompiste';

  @override
  String get message => 'Message';

  @override
  String get qrBlockedExpiredTicketsMessage =>
      'QR bloqué à cause des tickets expirés';

  @override
  String get orderValidatedNote => 'Commande validée';

  @override
  String get orderRejectedNote => 'Commande refusée';

  @override
  String carnetWithValue(String value) {
    return 'Carnet $value';
  }

  @override
  String ticketCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tickets',
      one: '1 ticket',
      zero: '0 ticket',
    );
    return '$_temp0';
  }

  @override
  String ticketsFromCarnet(int count, String carnet) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tickets de $carnet',
      one: '1 ticket de $carnet',
    );
    return '$_temp0';
  }

  @override
  String expirationDateLabel(String date) {
    return 'Date d\'expiration : $date';
  }

  @override
  String get commonBack => 'Retour';

  @override
  String get commonConfirmReview => 'Vérifiez les éléments avant de confirmer.';

  @override
  String get commonPinVerification => 'Vérification du PIN';

  @override
  String get commonPinConfirmationDescription =>
      'Saisissez votre PIN pour confirmer cette opération.';

  @override
  String get commonGenericError => 'Une erreur est survenue. Réessayez.';

  @override
  String get commonPinIncorrect => 'Code PIN incorrect.';

  @override
  String get commonTooManyAttempts =>
      'Trop de tentatives. Réessayez plus tard.';

  @override
  String get commonNetworkError =>
      'Impossible de joindre le serveur. Vérifiez votre connexion.';

  @override
  String get commonServerUnavailable =>
      'Serveur momentanément indisponible. Vérifiez votre connexion ou réessayez plus tard.';

  @override
  String get commonSessionRequired => 'Session requise.';

  @override
  String get qrDetailTitle => 'Détails du QR';

  @override
  String get qrNotFound => 'QR introuvable.';

  @override
  String get qrServerRequiredForDetail =>
      'Connexion serveur requise pour afficher ce QR.';

  @override
  String get qrServerRequiredForManualCode =>
      'Connexion serveur requise pour révéler le code manuel.';

  @override
  String get qrServerRequiredForSeparation =>
      'Connexion serveur requise pour séparer un QR.';

  @override
  String get qrServerRequiredForWithdrawal =>
      'Connexion serveur requise pour retirer des tickets.';

  @override
  String get qrContent => 'Contenu';

  @override
  String get qrSeparateUsableHint =>
      'Séparez les tickets utilisables des tickets expirés.';

  @override
  String get qrSeparateActiveButton =>
      'Séparer la partie active dans un nouveau QR';

  @override
  String get qrManualCode => 'Code manuel';

  @override
  String get qrRevealManualCode => 'Révéler le code manuel';

  @override
  String get qrRevealManualCodeDescription =>
      'Saisissez votre PIN pour afficher temporairement le code manuel de consommation.';

  @override
  String get qrManualCodeActiveOnly =>
      'Le code manuel ne peut être révélé que pour un QR actif.';

  @override
  String get qrManualCodeUsageHint =>
      'Présentez ce code uniquement à la station au moment de la consommation.';

  @override
  String get qrManualCodeHiddenHint =>
      'Code manuel masqué. Touchez l\'œil et saisissez votre PIN pour l\'afficher temporairement.';

  @override
  String get qrManualCodeRevealed => 'Code manuel révélé temporairement.';

  @override
  String get qrManualCodeRevealFailed =>
      'Le code manuel n\'a pas pu être révélé. Réessayez ou contactez l\'administrateur.';

  @override
  String get expirationDate => 'Date d\'expiration';

  @override
  String get amount => 'Montant';

  @override
  String expiresOn(String date) {
    return 'Expire le $date';
  }

  @override
  String expiredOn(String date) {
    return 'Expiré le $date';
  }

  @override
  String get qrWithdrawTitle => 'Retirer des tickets';

  @override
  String get qrWithdrawInstruction => 'Sélectionnez les lignes à retirer.';

  @override
  String get qrSelectAtLeastOneLine =>
      'Sélectionnez au moins une ligne à retirer.';

  @override
  String get qrKeepAtLeastOneLine =>
      'Au moins une ligne doit rester dans le QR d’origine.';

  @override
  String get qrMissingLineIdentifier =>
      'Une ligne du QR est indisponible. Rechargez le QR.';

  @override
  String get qrOnlyActiveCanWithdraw =>
      'Seuls les QR actifs permettent un retrait.';

  @override
  String get qrSingleLineCannotWithdraw =>
      'Un QR contenant une seule ligne ne permet pas de retrait.';

  @override
  String get qrWithdrawalInProgress => 'Retrait...';

  @override
  String get qrWithdraw => 'Retirer';

  @override
  String qrWithdrawSelected(int count) {
    return 'Retirer ($count)';
  }

  @override
  String get selection => 'Sélection';

  @override
  String selectedLines(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count lignes sélectionnées',
      one: '1 ligne sélectionnée',
      zero: 'Aucune ligne sélectionnée',
    );
    return '$_temp0';
  }

  @override
  String get qrWithdrawalSuccess => 'Tickets retirés avec succès.';

  @override
  String get qrWithdrawalFailed =>
      'Le retrait des tickets a échoué. Réessayez.';

  @override
  String get qrSeparateTitle => 'Séparer les tickets valides';

  @override
  String get qrSeparateSubtitle =>
      'Les tickets expirés restent séparés des tickets encore utilisables.';

  @override
  String get qrOnlyBlockedCanSeparate =>
      'Seuls les QR bloqués peuvent être séparés.';

  @override
  String get qrSeparationInProgress => 'Séparation...';

  @override
  String get qrSeparate => 'Séparer';

  @override
  String get qrSeparationSuccess => 'QR séparé avec succès.';

  @override
  String get qrSeparationFailed => 'La séparation du QR a échoué. Réessayez.';

  @override
  String get qrSeparationDisclaimer =>
      'La séparation générera un nouveau QR pour les lignes non expirées.';

  @override
  String get currentDistribution => 'Répartition actuelle';

  @override
  String get ticketDistribution => 'Répartition des tickets';

  @override
  String get validTickets => 'Tickets valides';

  @override
  String get expiredTickets => 'Tickets expirés';

  @override
  String get validAmount => 'Montant valide';

  @override
  String get expiredAmount => 'Montant expiré';

  @override
  String get qrToSeparate => 'QR à séparer';

  @override
  String get qrValidLinesMoved =>
      'Les lignes non expirées seront déplacées dans un nouveau QR.';

  @override
  String get qrLines => 'Lignes du QR';

  @override
  String qrValidExpiredSummary(int valid, int expired) {
    return '$valid tickets valides · $expired tickets expirés';
  }

  @override
  String ticketStatusWithDate(String status, String date) {
    return '$status · $date';
  }

  @override
  String get statusActive => 'Actif';

  @override
  String get statusExpired => 'Expiré';

  @override
  String get purchaseOrderTitle => 'Commande de carnets';

  @override
  String get purchaseSelectInstruction =>
      'Sélectionnez les carnets et indiquez la quantité.';

  @override
  String get purchaseServerRequired =>
      'Connexion serveur requise pour afficher les offres.';

  @override
  String get purchaseNoOffersTitle => 'Aucun carnet disponible';

  @override
  String get purchaseNoOffersMessage =>
      'Aucune offre de carnet n\'est disponible pour le moment.';

  @override
  String get purchaseCartTotal => 'Total du panier';

  @override
  String get purchaseContinue => 'Continuer';

  @override
  String get purchaseQuantity => 'Quantité';

  @override
  String purchaseValidityDays(int days) {
    return 'Validité : $days jours';
  }

  @override
  String get purchaseAddProof => 'Ajouter la preuve de paiement';

  @override
  String get purchaseProofSelected => 'Preuve sélectionnée';

  @override
  String purchaseProofFormats(String size) {
    return 'JPG, PNG ou PDF — taille maximale $size.';
  }

  @override
  String get purchaseProofTitle => 'Preuve de paiement';

  @override
  String get purchaseProofInstruction =>
      'Vérifiez le panier, puis joignez un reçu ou un virement avant de confirmer.';

  @override
  String get purchaseSendOrder => 'Envoyer la commande';

  @override
  String get purchaseConfirmTitle => 'Confirmer la commande';

  @override
  String get purchaseConfirmInstruction =>
      'Vérifiez la commande de carnets avant de confirmer.';

  @override
  String get purchaseCancel => 'Annuler';

  @override
  String get purchaseApprovalHint =>
      'Les carnets seront crédités après approbation.';

  @override
  String get purchaseConfirmationDisclaimer =>
      'En confirmant, votre commande sera envoyée à un administrateur pour validation. Les carnets seront crédités après approbation.';

  @override
  String get purchaseProofRequired => 'La preuve de paiement est obligatoire.';

  @override
  String get purchaseProofUnreadable => 'La preuve de paiement est illisible.';

  @override
  String get purchaseSelectAtLeastOne => 'Indiquez au moins un ticket.';

  @override
  String purchaseMaxTickets(int count) {
    return 'Maximum $count tickets par commande.';
  }

  @override
  String get purchaseSuccessTitle => 'Commande de carnets enregistrée';

  @override
  String get purchaseSuccessMessage =>
      'Votre commande de carnets est en attente de validation.';

  @override
  String get purchasedCarnets => 'Carnets commandés';

  @override
  String get totalAmount => 'Montant total';

  @override
  String get date => 'Date';

  @override
  String get qrGenerationTitle => 'Génération de QR';

  @override
  String get qrGenerationSelectInstruction =>
      'Sélectionnez les carnets à inclure dans le QR.';

  @override
  String get qrGenerationChooseInstruction =>
      'Choisissez un carnet et une quantité.';

  @override
  String get qrGenerationEmptyTitle => 'Aucun ticket disponible';

  @override
  String get qrGenerationEmptyMessage =>
      'Commandez des carnets et attendez leur validation pour générer un QR.';

  @override
  String get qrGenerationSelectAtLeastOne => 'Sélectionnez au moins un carnet.';

  @override
  String get qrGenerationConfirmTitle => 'Confirmer la génération';

  @override
  String get qrGenerateButton => 'Générer le QR';

  @override
  String get qrGenerationDisclaimer =>
      'La génération du QR se fera à partir des carnets sélectionnés.';

  @override
  String get qrGenerationFailed => 'La génération du QR a échoué. Réessayez.';

  @override
  String get qrGenerationTotal => 'Montant total du QR';

  @override
  String get qrGenerate => 'Générer';

  @override
  String get qrGeneratedTitle => 'QR généré';

  @override
  String get qrGeneratedMessage =>
      'Votre QR est disponible dans la liste des QR.';

  @override
  String get usedCarnets => 'Carnets utilisés';

  @override
  String get purchaseDetailTitle => 'Détail de la commande';

  @override
  String get purchaseNotFound => 'Commande introuvable.';

  @override
  String get purchaseInformation => 'Informations';

  @override
  String get purchaseOrderLines => 'Lignes de commande';

  @override
  String get purchasePaymentProofs => 'Preuves de paiement';

  @override
  String get status => 'Statut';

  @override
  String get paymentReference => 'Référence de paiement';

  @override
  String get submittedOn => 'Soumis le';

  @override
  String get ticketsExpiration => 'Expiration des tickets';

  @override
  String get validatedOn => 'Validé le';

  @override
  String get validatedBy => 'Validé par';

  @override
  String get rejectionReason => 'Motif de rejet';

  @override
  String get purchaseTotal => 'Total de la commande';

  @override
  String get purchaseNoLines => 'Aucune ligne pour cette commande.';

  @override
  String get purchaseNoProof =>
      'Aucune preuve de paiement jointe à cette commande.';

  @override
  String get commonClose => 'Fermer';

  @override
  String get commonDownload => 'Télécharger';

  @override
  String get commonCancel => 'Annuler';

  @override
  String get commonContinue => 'Continuer';

  @override
  String get returnHome => 'Retour à l\'accueil';

  @override
  String get expirationUnknown => 'Expiration non renseignée';

  @override
  String get transferCarnetsTitle => 'Transfert de carnets';

  @override
  String get transferTicketsTitle => 'Transfert de tickets';

  @override
  String get transferCarnetsInstruction =>
      'Entrez le numéro du bénéficiaire, puis sélectionnez les carnets à transférer.';

  @override
  String get transferTicketsInstruction =>
      'Entrez le numéro du bénéficiaire, puis sélectionnez les tickets à transférer.';

  @override
  String get transferCarnetsEmptyTitle => 'Aucun carnet disponible';

  @override
  String get transferCarnetsEmptyMessage =>
      'Vos carnets disponibles apparaîtront ici.';

  @override
  String get transferTicketsEmptyTitle => 'Aucun ticket disponible';

  @override
  String get transferTicketsEmptyMessage =>
      'Vos tickets disponibles apparaîtront ici.';

  @override
  String get recipientPhoneHint => 'Numéro de téléphone du bénéficiaire';

  @override
  String get transferTotal => 'Total du transfert';

  @override
  String get transferOwnCarnetsForbidden =>
      'Vous ne pouvez pas transférer des carnets vers votre propre compte.';

  @override
  String get transferOwnTicketsForbidden =>
      'Vous ne pouvez pas transférer des tickets vers votre propre compte.';

  @override
  String get recipientPhoneRequired =>
      'Saisissez le téléphone du bénéficiaire.';

  @override
  String get recipientPhoneInvalid =>
      'Le numéro du bénéficiaire doit contenir 8 chiffres.';

  @override
  String get transferMissingCarnetLine =>
      'Un carnet est indisponible. Rechargez la liste.';

  @override
  String get transferMissingTicketLine =>
      'Un ticket est indisponible. Rechargez la liste.';

  @override
  String get transferTicketQuantityUnavailable =>
      'La quantité dépasse le nombre de tickets disponibles.';

  @override
  String get transferSelectCarnet =>
      'Sélectionnez au moins un carnet à transférer.';

  @override
  String get transferSelectTicket =>
      'Sélectionnez au moins un ticket à transférer.';

  @override
  String get transferRecipientNotFound =>
      'Aucun client ne correspond à ce numéro.';

  @override
  String get transferConfirmTitle => 'Confirmer le transfert';

  @override
  String get transferReviewCarnets =>
      'Vérifiez les carnets avant de confirmer.';

  @override
  String get transferReviewTickets =>
      'Vérifiez les tickets avant de confirmer.';

  @override
  String get transferredCarnets => 'Carnets transférés';

  @override
  String get transferredTickets => 'Tickets transférés';

  @override
  String get transferUnconfirmedCarnets =>
      'Action non confirmée. Vérifiez l\'état de vos carnets avant de réessayer.';

  @override
  String get transferUnconfirmedTickets =>
      'Action non confirmée. Vérifiez l\'état de vos tickets avant de réessayer.';

  @override
  String get transferRejected => 'Le transfert a été refusé par le serveur.';

  @override
  String get transferFailed =>
      'Le transfert a échoué. Réessayez ou contactez l\'administrateur.';

  @override
  String get transferSuccessTitle => 'Transfert confirmé';

  @override
  String transferFinalDisclaimer(String recipient) {
    return 'Le transfert vers $recipient est définitif et ne peut pas être annulé après confirmation.';
  }

  @override
  String get referenceIdentifier => 'Identifiant de référence';

  @override
  String get authSplashTagline => 'Bons carburant traçables';

  @override
  String get authWelcomeTitle => 'Bienvenue sur Tickets Carburant';

  @override
  String get authWelcomeMessage =>
      'Commandez, gérez et utilisez vos carnets de tickets carburant en toute sécurité.';

  @override
  String get authCreateAccount => 'Créer mon compte';

  @override
  String get authAlreadyAccount => 'Vous avez déjà un compte ?';

  @override
  String get authSignIn => 'Se connecter';

  @override
  String get authContacts => 'Contacts';

  @override
  String get authContactsHelp =>
      'Contactez votre support Tickets Carburant ou votre interlocuteur habituel pour obtenir de l\'aide.';

  @override
  String get authLoginTitle => 'Connexion';

  @override
  String get authLoginFailed =>
      'Connexion impossible. Vérifiez le numéro ou le code SMS.';

  @override
  String get authOtpIncorrect => 'Code SMS incorrect. Réessayez.';

  @override
  String get authPhoneRequired => 'Saisissez votre numéro de téléphone.';

  @override
  String get authPhoneInvalid =>
      'Saisissez un numéro de téléphone valide à 8 chiffres.';

  @override
  String authOtpLength(int count) {
    return 'Saisissez un code à $count chiffres.';
  }

  @override
  String authDigitsCount(int count) {
    return '$count chiffres';
  }

  @override
  String get authContinue => 'Continuer';

  @override
  String get authAccountVerification => 'Vérification du compte';

  @override
  String get authVerificationCode => 'Code de vérification';

  @override
  String authOtpSentTo(String phone) {
    return 'Nous avons envoyé un code par SMS au $phone.';
  }

  @override
  String get authEnterPhone =>
      'Saisissez votre téléphone pour vérifier votre compte.';

  @override
  String get authPhone => 'Téléphone';

  @override
  String get authSmsCode => 'Code SMS';

  @override
  String get authResendCode => 'Renvoyer le code';

  @override
  String get authChangePhone => 'Changer de numéro';

  @override
  String get authForgotPin => 'PIN oublié ?';

  @override
  String get authCreateAnAccount => 'Créer un compte';

  @override
  String get authDeviceStateTitle => 'État de l\'appareil';

  @override
  String get authDevicePendingState => 'En attente';

  @override
  String get authDeviceBlocked => 'Appareil bloqué';

  @override
  String get authActivationPending => 'Activation en attente';

  @override
  String get authDeviceBlockedMessage =>
      'Ce téléphone n\'est pas autorisé à utiliser les tickets carburant. Contactez l\'administrateur.';

  @override
  String get authActivationPendingMessage =>
      'Vous pourrez utiliser les tickets carburant après la validation de cet appareil par l\'administrateur.';

  @override
  String authDeviceState(String state) {
    return 'État de l\'appareil : $state';
  }

  @override
  String get authCheckAgain => 'Vérifier à nouveau';

  @override
  String get authLogout => 'Se déconnecter';

  @override
  String get authPinRecovery => 'Récupération du PIN';

  @override
  String get authPinRecoveryInstruction =>
      'Entrez votre numéro pour recevoir le code de vérification.';

  @override
  String get authNumber => 'Numéro';

  @override
  String get authSendCode => 'Envoyer le code';

  @override
  String get authCodeSentBySms =>
      'Le code est envoyé par SMS à votre numéro de téléphone.';

  @override
  String get authVerifyAndNewPin => 'Vérification et nouveau PIN';

  @override
  String get authVerifyAndNewPinInstruction =>
      'Saisissez le code reçu par SMS puis choisissez votre nouveau PIN.';

  @override
  String get authNewPin => 'Nouveau PIN';

  @override
  String get authFourDigits => '4 chiffres';

  @override
  String get authConfirmPin => 'Confirmer le PIN';

  @override
  String get authReenterPin => 'Saisissez à nouveau le PIN';

  @override
  String get authPinsMismatch => 'Les PIN ne correspondent pas.';

  @override
  String get authSavePin => 'Enregistrer le PIN';

  @override
  String get authNewPinInstruction =>
      'Choisissez un PIN numérique à 4 chiffres.';

  @override
  String get authPin => 'PIN';

  @override
  String get authConfirm => 'Confirmer';

  @override
  String get authSave => 'Enregistrer';

  @override
  String get authConfirmPinRequired => 'Confirmez votre PIN.';

  @override
  String get authRegistrationFailed =>
      'Inscription impossible avec ce numéro. Si vous avez déjà un compte, connectez-vous.';

  @override
  String get authFullName => 'Nom complet';

  @override
  String get authNameRequired => 'Le nom est obligatoire.';

  @override
  String get authDefinePin => 'Définir le PIN';

  @override
  String get authRegisterTitle => 'Créer un compte';

  @override
  String get authRegisterBrand => 'Leader Petroleum E-Tickets';

  @override
  String get authRegisterInstruction =>
      'Recevez un code SMS pour vérifier votre compte.';

  @override
  String get authSmsSent => 'Code SMS envoyé.';

  @override
  String get authOtpMissingExpired =>
      'Code SMS introuvable, expiré ou déjà utilisé. Demandez un nouveau code puis réessayez.';

  @override
  String get authVerification => 'Vérification';

  @override
  String authCodeSentShort(String destination) {
    return 'Code envoyé à $destination';
  }

  @override
  String get authVerify => 'Vérifier';

  @override
  String get authRequestInProgress => 'Demande en cours...';

  @override
  String get authOtpMissing => 'Code SMS introuvable';

  @override
  String get authRestartRegistrationMessage =>
      'Recommencez l\'inscription pour recevoir un nouveau code.';

  @override
  String get authRestartRegistration => 'Recommencer l\'inscription';

  @override
  String get authBackToLogin => 'Retour à la connexion';

  @override
  String get authConfirmYour => 'Confirmez votre';

  @override
  String get authMobileNumber => 'numéro mobile';

  @override
  String get authUnlockApp => 'Déverrouiller l\'application';

  @override
  String get authSessionRestored =>
      'Session restaurée. Saisissez votre PIN serveur pour continuer.';

  @override
  String authSessionRestoredFor(String name) {
    return 'Session restaurée pour $name. Saisissez votre PIN serveur pour continuer.';
  }

  @override
  String get authPinFourDigits => 'PIN à 4 chiffres';

  @override
  String get authUnlock => 'Déverrouiller';

  @override
  String get authCodeSent => 'Code envoyé.';

  @override
  String get authCodeResent => 'Code renvoyé par SMS.';

  @override
  String get authEnterSixDigitCode => 'Saisissez le code SMS à 6 chiffres.';

  @override
  String get authPinUpdated => 'PIN mis à jour. Connectez-vous.';

  @override
  String get authEnterPinFourDigits => 'Saisissez votre PIN à 4 chiffres.';

  @override
  String get authRestartToRequestCode =>
      'Recommencez l\'inscription pour demander un nouveau code.';

  @override
  String get authNewCodeRequested => 'Un nouveau code a été demandé.';

  @override
  String get authRegistrationIncomplete =>
      'L\'inscription n\'a pas pu être finalisée. Réessayez ou contactez l\'administrateur.';

  @override
  String get authRegistrationUnavailable =>
      'L\'inscription n\'est pas disponible sur cet appareil.';

  @override
  String get authSmsNotConfirmed =>
      'Le serveur n\'a pas confirmé l\'envoi du code SMS. Réessayez.';

  @override
  String get settingsTitle => 'Mon compte';

  @override
  String get settingsQuickAccess => 'Accès rapide';

  @override
  String get settingsPaymentHistory => 'Historique des paiements';

  @override
  String get settingsPaymentHistorySubtitle =>
      'Consultez vos opérations et règlements.';

  @override
  String get settingsAccountSecurity => 'Compte & sécurité';

  @override
  String get settingsDeleteAccount => 'Supprimer mon compte';

  @override
  String get settingsDeleteAccountSubtitle =>
      'Contactez le support pour la suppression';

  @override
  String get settingsDeleteAccountTitle => 'Demande de suppression du compte';

  @override
  String get settingsDeleteAccountMessage =>
      'La suppression est irréversible. Consultez la procédure officielle ACPEC pour envoyer votre demande et vérifier votre identité.';

  @override
  String get settingsDeletionGuide => 'Copier le lien de la procédure';

  @override
  String get settingsDeletionLinkCopied => 'Lien de suppression copié.';

  @override
  String settingsMemberSince(String date) {
    return 'Membre depuis $date';
  }

  @override
  String get settingsPreferences => 'Préférences';

  @override
  String get settingsLanguage => 'Langue';

  @override
  String get settingsFrench => 'Français';

  @override
  String get settingsArabic => 'العربية';

  @override
  String get settingsQuickUnlock => 'Déverrouillage rapide';

  @override
  String get settingsQuickUnlockSubtitle =>
      'Accédez plus rapidement à l\'application sur cet appareil.';

  @override
  String get settingsDarkMode => 'Mode sombre';

  @override
  String get settingsDarkModeSubtitle =>
      'Interface adaptée aux environnements peu éclairés.';

  @override
  String get settingsServiceConnection => 'Connexion au service';

  @override
  String get settingsServiceConnectionSubtitle =>
      'Vérifier si le service est disponible.';

  @override
  String get settingsCreateAccountSubtitle =>
      'Créer un compte avec le code reçu par SMS.';

  @override
  String get settingsLogoutTitle => 'Déconnexion';

  @override
  String get settingsLogoutQuestion =>
      'Voulez-vous quitter Leader Petroleum E-Tickets sur cet appareil ?';

  @override
  String get settingsLogoutSubtitle => 'Fin de session sur cet appareil';

  @override
  String get settingsCarnets => 'Carnets';

  @override
  String get settingsQr => 'QR';

  @override
  String get settingsConsumptions => 'Consommations';

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get notificationsMarkAllRead => 'Tout lu';

  @override
  String get notificationsEmptyTitle => 'Aucune notification';

  @override
  String get notificationsEmptyMessage =>
      'Les commandes validées, QR et transferts apparaîtront ici.';

  @override
  String get notificationsAmountUnavailable => 'Montant indisponible';

  @override
  String get notificationsQrUnavailable => 'Code QR indisponible';

  @override
  String get notificationsViewQr => 'Voir le QR';

  @override
  String get purchasesListTitle => 'Mes commandes';

  @override
  String get purchasesListSubtitle =>
      'Chaque carte résume la commande de carnets, le montant total et la date de validation.';

  @override
  String purchasesCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count commandes',
      one: '1 commande',
      zero: 'Aucune commande',
    );
    return '$_temp0';
  }

  @override
  String get purchasesApproved => 'Carnets commandés';

  @override
  String get purchasesRejected => 'Commandes rejetées';

  @override
  String get purchasesConnectionRequired => 'Connexion requise';

  @override
  String get purchasesEmptyTitle => 'Aucune commande';

  @override
  String get purchasesEmptyMessage =>
      'Créez une nouvelle commande pour retrouver ici son montant et sa validation.';

  @override
  String get purchasesNewOrder => 'Nouvelle commande';

  @override
  String get purchasesCarnetType => 'Type de carnet';

  @override
  String get purchasesValidationDate => 'Date de validation';

  @override
  String get purchasesPendingValidation => 'En attente de validation';

  @override
  String get filtersTitle => 'Filtres';

  @override
  String get filtersClearAll => 'Tout effacer';

  @override
  String get filtersViewResults => 'Voir les résultats';

  @override
  String get commonCloseTooltip => 'Fermer';

  @override
  String get authSessionNotFound => 'Session introuvable';

  @override
  String get authReconnectToContinue => 'Reconnectez-vous pour continuer.';

  @override
  String get walletBreakdownTitle => 'Répartition et suivi';

  @override
  String get walletBreakdownEmptyTitle => 'Pas encore de détail à afficher';

  @override
  String get walletBreakdownEmptyMessage =>
      'Les différentes répartitions de votre portefeuille apparaîtront ici.';

  @override
  String get walletByFaceValue => 'Par valeur de face';

  @override
  String get walletByFaceValueSubtitle =>
      'Disponible, QR actif, bloqué, consommé et expiré';

  @override
  String get walletByCarnetType => 'Par type de carnet';

  @override
  String get walletByCarnetTypeSubtitle => 'Répartition par carnet';

  @override
  String get walletNearExpiration => 'Tickets proches de l\'expiration';

  @override
  String get walletWatch => 'À surveiller';

  @override
  String get walletExpiredTickets => 'Tickets expirés';

  @override
  String get walletUnusable => 'Non utilisables';

  @override
  String get walletOverview => 'Vue d\'ensemble';

  @override
  String walletActiveCarnets(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count carnets actifs',
      one: '1 carnet actif',
      zero: 'Aucun carnet actif',
    );
    return '$_temp0';
  }

  @override
  String walletTicketsAtValue(String value) {
    return 'Tickets à $value';
  }

  @override
  String walletUsableSummary(Object amount, Object count) {
    return '$count utilisables · $amount';
  }

  @override
  String walletUnits(Object count) {
    return '$count unités';
  }

  @override
  String walletAvailableTicketsCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tickets disponibles',
      one: '1 ticket disponible',
      zero: 'Aucun ticket disponible',
    );
    return '$_temp0';
  }

  @override
  String walletFaceValue(String value) {
    return 'Valeur de face $value';
  }

  @override
  String walletTicketCountShort(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tickets',
      one: '1 ticket',
      zero: '0 ticket',
    );
    return '$_temp0';
  }

  @override
  String walletDueDate(String date) {
    return 'Échéance : $date';
  }

  @override
  String walletLot(String lot) {
    return 'Lot : $lot';
  }

  @override
  String get settingsService => 'Service';

  @override
  String get settingsBiometricUnavailable =>
      'Le déverrouillage biométrique n\'est pas disponible sur cet appareil.';

  @override
  String get settingsBiometricReason =>
      'Confirmez pour activer le déverrouillage biométrique.';

  @override
  String get settingsActivationCancelled => 'Activation annulée.';

  @override
  String get notificationsUnread => 'Non lues';

  @override
  String get notificationsRead => 'Lues';

  @override
  String get notificationsUpdateMessage =>
      'Une nouvelle information est disponible dans votre compte.';

  @override
  String get statusDraft => 'Brouillon';

  @override
  String get statusSubmitted => 'En attente';

  @override
  String get statusApproved => 'Validée';

  @override
  String get statusRejected => 'Refusée';

  @override
  String get commonNoItem => 'Aucun élément';

  @override
  String get quantity => 'Quantité';

  @override
  String get faceValue => 'Valeur de face';

  @override
  String get lotReference => 'Référence du lot';

  @override
  String get purchaseDeviceApprovalRequired =>
      'Cet appareil doit être validé avant de pouvoir créer une commande.';

  @override
  String get purchaseProofLoadFailed =>
      'Impossible de charger la preuve de paiement.';

  @override
  String get purchaseActionUnavailable =>
      'Cette action n\'est pas disponible pour cette commande.';

  @override
  String get purchaseDownloadUnavailable => 'Téléchargement indisponible.';

  @override
  String get purchaseProofDownloadFailed =>
      'Impossible de télécharger la preuve.';

  @override
  String get authRestartFromForgotPin => 'Reprenez depuis l\'écran PIN oublié.';

  @override
  String get authRestartFromOtp =>
      'Reprenez depuis la vérification du code SMS.';

  @override
  String supportReference(String reference) {
    return 'Référence support : $reference';
  }

  @override
  String get apiRequiredTitle => 'Service indisponible';

  @override
  String get apiRequiredMessage =>
      'Impossible de charger les données pour le moment. Vérifiez votre connexion et réessayez.';

  @override
  String get serviceStatusTitle => 'État du service';

  @override
  String get serviceCheckUnavailable =>
      'Le service ne peut pas être vérifié sur cet appareil pour le moment.';

  @override
  String get serviceConnectionFailed =>
      'Connexion au service impossible. Vérifiez votre réseau et réessayez.';

  @override
  String get commonUnexpectedError =>
      'Une erreur inattendue s\'est produite. Réessayez plus tard.';

  @override
  String installedVersion(String version) {
    return 'Version installée : $version';
  }

  @override
  String get updateRequiredTitle => 'Mise à jour requise';

  @override
  String get updateRequiredMessage =>
      'Installez la dernière version de Leader Petroleum E-Tickets pour continuer à utiliser le service.';

  @override
  String get serviceUnavailableTitle => 'Service indisponible';

  @override
  String get serviceUnavailableMessage =>
      'Le service ne répond pas correctement. Réessayez dans quelques instants.';

  @override
  String get updateAvailableTitle => 'Mise à jour disponible';

  @override
  String get updateAvailableMessage =>
      'Une version plus récente est disponible. Mettez l\'application à jour dès que possible.';

  @override
  String get serviceReadyTitle => 'Tout est en ordre';

  @override
  String get serviceReadyMessage =>
      'Votre application est à jour et le service répond normalement.';

  @override
  String get organizationsAvailable => 'Organisations disponibles';

  @override
  String get organizationsEmptyTitle => 'Aucune organisation';

  @override
  String get organizationsEmptyMessage =>
      'Aucune organisation à afficher pour le moment.';

  @override
  String get developmentDetails => 'Détail (mode développement)';

  @override
  String get signupSmsIntro =>
      'L\'inscription se fait avec le code reçu par SMS.';

  @override
  String get signupSmsInstructions =>
      'Renseignez vos informations sur l\'écran d\'inscription, puis validez le code reçu pour créer votre compte.';

  @override
  String get openRegistration => 'Ouvrir l\'inscription';

  @override
  String get walletStatusAvailable => 'Disponible';

  @override
  String get walletStatusActiveQr => 'En QR actif';

  @override
  String get walletStatusBlocked => 'Bloqué';

  @override
  String get walletStatusConsumed => 'Consommé';

  @override
  String get walletStatusExpired => 'Expiré';

  @override
  String get commonNotProvided => 'Non renseigné';

  @override
  String get purchaseUnconfirmed =>
      'Action non confirmée. Vérifiez l\'état de la commande avant de réessayer.';

  @override
  String get purchaseCannotOpen =>
      'Cette commande ne peut pas être ouverte. Vérifiez le lien ou réessayez.';

  @override
  String get purchaseOperationFailed =>
      'L\'opération n\'a pas abouti. Réessayez ou reconnectez-vous.';

  @override
  String get qrUnconfirmed =>
      'Action non confirmée. Vérifiez la liste de vos QR avant de réessayer.';

  @override
  String get languageSelectionTitle => 'Choisissez votre langue';

  @override
  String get languageSelectionMessage =>
      'Vous pourrez modifier ce choix plus tard dans les réglages.';

  @override
  String get languageSelectionContinue => 'Continuer';

  @override
  String get stationNavHome => 'Accueil';

  @override
  String get stationNavScan => 'Scanner';

  @override
  String get stationAgentFallback => 'Agent station';

  @override
  String stationAgentAtStation(String stationName) {
    return 'Agent station · $stationName';
  }

  @override
  String get stationAgentProfile => 'Profil de l\'agent station';

  @override
  String get stationScanQr => 'Scanner un QR';

  @override
  String get stationScanPrompt => 'Appuyez pour scanner le QR du client';

  @override
  String get stationManualEntry => 'Saisir un code manuel';

  @override
  String get stationManualEquivalent =>
      'Même opération que le scan du QR client';

  @override
  String get stationConsumptionHistory => 'Historique des consommations';

  @override
  String get stationProfileTitle => 'Profil';

  @override
  String get stationInformation => 'Informations';

  @override
  String get stationNameLabel => 'Nom';

  @override
  String get stationCodeLabel => 'Code';

  @override
  String get stationAddressLabel => 'Adresse';

  @override
  String get stationStatusLabel => 'Statut';

  @override
  String get stationInService => 'En service';

  @override
  String get stationOutOfService => 'Hors service';

  @override
  String get stationPreferences => 'Préférences';

  @override
  String get stationDarkModeSubtitle =>
      'Appliqué à toute l\'application sur cet appareil.';

  @override
  String get stationLogout => 'Se déconnecter';

  @override
  String get stationProfileServerRequired =>
      'Connectez-vous au service pour afficher le profil de la station.';

  @override
  String get stationLinkedOperator => 'Station liée et opérateur mobile.';

  @override
  String get stationMobileOperator => 'Opérateur mobile';

  @override
  String get stationEmailLabel => 'E-mail';

  @override
  String get stationPhoneLabel => 'Téléphone';

  @override
  String get stationSessionExpired => 'Session expirée. Reconnectez-vous.';

  @override
  String get stationCameraUnavailable =>
      'Caméra indisponible. Vérifiez les autorisations puis réessayez.';

  @override
  String get stationQrNotConsumable => 'QR non consommable';

  @override
  String get stationQrAlreadyConsumed =>
      'Ce QR a déjà été consommé et ne peut plus être utilisé.';

  @override
  String get stationQrNotConsumableMessage =>
      'Ce QR ne peut pas être consommé.';

  @override
  String get stationBackHome => 'Retour à l\'accueil';

  @override
  String get stationVerificationImpossible => 'Vérification impossible';

  @override
  String get stationBackToScan => 'Retour au scanner';

  @override
  String get stationBackToEntry => 'Retour à la saisie';

  @override
  String get stationPinVerification => 'Vérification du PIN';

  @override
  String get stationPinScanDescription =>
      'Saisissez votre PIN pour confirmer cette opération.';

  @override
  String get stationPinManualDescription =>
      'Saisissez votre PIN station pour consommer ce QR.';

  @override
  String get stationConsumptionRejected =>
      'Consommation du QR refusée par le service.';

  @override
  String get stationConsumptionFailed =>
      'La consommation du QR a échoué. Réessayez ou contactez l\'administrateur.';

  @override
  String get stationConsumptionUnconfirmed => 'Consommation non confirmée';

  @override
  String get stationConsumptionUnconfirmedMessage =>
      'L\'opération n\'a pas été confirmée. Vérifiez l\'historique avant de réessayer.';

  @override
  String get stationOperationRejected => 'Opération refusée';

  @override
  String get stationScannerTitle => 'Scanner le QR du client';

  @override
  String get stationScannerSubtitle =>
      'Placez le QR du client dans le cadre pour le vérifier.';

  @override
  String get stationReactivateCamera => 'Réactiver la caméra';

  @override
  String get stationQrVerificationTitle => 'Vérification du QR';

  @override
  String get stationQrVerificationSubtitle => 'Contrôle avant consommation';

  @override
  String get stationTotalAmount => 'Montant total';

  @override
  String get stationClient => 'Client';

  @override
  String get stationConsumptionAllowed => 'Consommation autorisée';

  @override
  String get stationConsumptionAllowedMessage =>
      'Vous pouvez enregistrer la consommation de ce QR.';

  @override
  String get stationValidating => 'Validation…';

  @override
  String get stationQrConsumedSuccess => 'QR consommé avec succès';

  @override
  String get stationConsumptionRecorded =>
      'La consommation a bien été enregistrée.';

  @override
  String get stationDateTime => 'Date et heure';

  @override
  String get stationTransactionNumber => 'N° de transaction';

  @override
  String get stationFinish => 'Terminer';

  @override
  String get stationManualTitle => 'Saisie manuelle';

  @override
  String get stationManualInstruction =>
      'Saisissez le code numérique affiché par le client. Cette opération est identique au scan du QR.';

  @override
  String get stationManualClientCode => 'Code manuel du client';

  @override
  String get stationManualFormat => 'Format attendu : 1234-5678-9012';

  @override
  String get stationChecking => 'Vérification…';

  @override
  String get stationCheck => 'Vérifier';

  @override
  String get stationConsumable => 'Consommable';

  @override
  String get stationConsuming => 'Consommation…';

  @override
  String get stationConsume => 'Consommer';

  @override
  String get stationEnterManualCode =>
      'Saisissez le code manuel affiché au client.';

  @override
  String get stationCheckCodeFirst =>
      'Vérifiez le code manuel avant la consommation.';

  @override
  String get stationHistorySubtitle => 'QR consommés par période';

  @override
  String get stationFilterAll => 'Tous';

  @override
  String get stationFilterPending => 'Non régularisé';

  @override
  String get stationFilterRegularized => 'Régularisé';

  @override
  String get stationHistoryPartial =>
      'Résultat partiel : trop de consommations pour cette période. Réduisez la période choisie.';

  @override
  String stationHistoryPartialCount(int loaded, int total) {
    return 'Résultat partiel : $loaded sur $total consommations chargées. Réduisez la période choisie.';
  }

  @override
  String get stationHistoryEndTitle => 'Fin de l\'historique';

  @override
  String get stationHistoryEndMessage =>
      'Aucune autre consommation enregistrée.';

  @override
  String get stationHistorySummary => 'Résumé des QR consommés';

  @override
  String get stationConsumedQr => 'QR consommés';

  @override
  String get stationTotal => 'Montant total';

  @override
  String get stationUnknownClient => 'Client inconnu';

  @override
  String get stationUnknownStation => 'Station inconnue';

  @override
  String get stationFuelConsumption => 'Consommation de carburant';

  @override
  String get stationQrDetail => 'Détail du QR';

  @override
  String get stationConsumptionDate => 'Date de consommation';

  @override
  String get stationRegularizationStatus => 'État de régularisation';

  @override
  String get stationRegularizationReference => 'Référence de régularisation';

  @override
  String get stationRegularizationDate => 'Date de régularisation';

  @override
  String get stationConsumptionDetail => 'Détail de la consommation';

  @override
  String get stationQrCode => 'Code QR';

  @override
  String get stationTransactionIdentifier => 'Identifiant de transaction';

  @override
  String get stationClientIdentifier => 'Identifiant du client';

  @override
  String get stationStationIdentifier => 'Identifiant de la station';

  @override
  String get stationQrIdentifier => 'Identifiant du QR';

  @override
  String get stationLotIdentifier => 'Identifiant du lot';

  @override
  String get stationOperatorIdentifier => 'Identifiant de l’opérateur';

  @override
  String get stationManualExample => 'Ex. 1234-5678-9012';

  @override
  String get paymentHistoryScreenSubtitle =>
      'Vos achats et leurs justificatifs de paiement';

  @override
  String get paymentHistoryEmptyTitle => 'Aucun paiement';

  @override
  String get paymentHistoryEmptyMessage =>
      'Vos achats effectués apparaîtront ici avec leur preuve de paiement.';

  @override
  String get paymentHistoryPurchaseDetails => 'Détails de l’achat';

  @override
  String get paymentHistoryPurchaseReference => 'Référence de l’achat';

  @override
  String get paymentHistoryCarnetsCount => 'Nombre de carnets';

  @override
  String get paymentHistoryTicketsCount => 'Nombre de tickets';

  @override
  String get paymentHistoryOpenProof => 'Ouvrir';

  @override
  String get paymentHistoryProofDownloaded =>
      'La preuve de paiement a été téléchargée.';

  @override
  String get paymentHistoryProofUnavailable =>
      'La preuve de paiement est temporairement indisponible.';
}
