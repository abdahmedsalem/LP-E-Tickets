// SUPPRIMÉ — M-02
//
// FuelRepository était une implémentation en mémoire (655 lignes) jamais
// connectée à l'API réelle. Sa logique métier divergeait du backend sur
// plusieurs points (splitQr, QrState.split, TxType.qrSplit, etc.).
//
// Toutes les données passent désormais par OdooFueltokenFacade.
