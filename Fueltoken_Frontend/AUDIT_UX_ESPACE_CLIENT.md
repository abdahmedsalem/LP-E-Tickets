# Audit UX - Espace client FuelToken

Date: 2026-06-05

## Perimetre audite

Cet audit couvre l'espace client Flutter:

- Navigation principale client: `Accueil`, `Carnets`, `QR`, `Historique`, `Profil`.
- Workflows client: nouvel achat, generation QR, transfert de carnets, retrait QR, separation QR.
- Ecrans secondaires: detail QR, detail achat, notifications, confirmations et ecrans de succes.

Fichiers principalement observes:

- `lib/features/home/screens/client_shell_scaffold.dart`
- `lib/features/home/screens/user_home_screen.dart`
- `lib/features/home/screens/faces_detail_screen.dart`
- `lib/features/qr/screens/qr_list_screen.dart`
- `lib/features/qr/screens/qr_detail_screen.dart`
- `lib/features/qr/screens/emit_qr_screen.dart`
- `lib/features/qr/screens/transfer_carnets_screen.dart`
- `lib/features/qr/screens/retirer_qr_screen.dart`
- `lib/features/qr/screens/separer_qr_screen.dart`
- `lib/features/purchases/screens/submit_purchase_screen.dart`
- `lib/features/purchases/screens/purchases_list_screen.dart`
- `lib/features/transactions/screens/transactions_screen.dart`
- `lib/features/settings/screens/settings_screen.dart`
- `lib/features/settings/screens/notifications_screen.dart`
- `lib/shared/widgets/purchase_submit_success_dialog.dart`

## Synthese executive

L'espace client est fonctionnel et couvre les parcours metier principaux. Les actions critiques ont globalement un flux clair: selection, confirmation, succes, rafraichissement des donnees et retour vers l'accueil ou la liste QR selon le cas.

Les principaux risques UX restants sont:

- incoherences visuelles entre headers, cartes et boutons selon les ecrans;
- textes mal encodes visibles dans plusieurs ecrans et commentaires;
- libelles metier parfois mixtes francais/anglais ou peu naturels;
- navigation parfois heterogene entre `context.push`, `context.go`, `Navigator.push` et `rootNavigator`;
- surcharge d'information dans certains ecrans de confirmation et d'historique;
- absence d'un systeme centralise pour les formats de dates, montants, labels d'etat et actions de retour.

## Parcours audites

### 1. Accueil client

Points positifs:

- Le solde est visible rapidement.
- Les trois actions principales sont accessibles des l'accueil: acheter, generer QR, transferer.
- Le pull-to-refresh est present via le wallet.

Problemes UX:

- Le texte `Acheter  carnet` contient un double espace et devrait etre `Acheter un carnet`.
- Le texte `Transfer carnets` melange anglais/francais; utiliser `Transferer des carnets`.
- `Generer un QR code multi tickets` est long dans une carte et risque d'etre coupe; preferer `Generer un QR`.
- Le transfert est ouvert avec `Navigator.of(rootNavigator: true).push(...)` alors que les autres actions utilisent `context.push`. Cela rend la navigation moins previsible.
- Les trois quick actions ont un format compact; les textes longs creent une hierarchie moins lisible.

Recommandations:

- Uniformiser les libelles: `Acheter`, `Generer QR`, `Transferer`.
- Utiliser `context.push('/transfer-carnets')` pour le transfert afin de respecter le routeur.
- Ajouter une courte phrase sous les actions ou un ordre metier: acheter -> generer QR -> transferer.

Priorite: haute.

### 2. Navigation client

Points positifs:

- La barre client expose les cinq sections importantes.
- Le tap sur l'onglet courant revient a l'etat initial via `goBranch(initialLocation: true)`.
- Les bus de refresh sont declenches selon l'onglet.

Problemes UX:

- La barre a une hauteur fixe de `86`, qui peut occuper beaucoup d'espace sur petits ecrans.
- Les labels courts sont lisibles, mais `Historique` peut etre serre avec cinq onglets.
- Les refresh automatiques au changement d'onglet peuvent donner une impression de lenteur si les endpoints sont lents.

Recommandations:

- Garder les cinq onglets, mais surveiller les petits ecrans Android.
- Ajouter un indicateur de chargement discret uniquement dans le contenu, pas dans la barre.
- Eviter les refresh trop agressifs si les donnees sont deja recentes.

Priorite: moyenne.

### 3. Mes carnets

Points positifs:

- Les carnets ont des filtres rapides: tous, actifs, expires.
- Le popup detail carnet donne une vue utile: etat, expiration, valeur faciale, tickets totaux, repartition.
- Les labels de type carnet utilisent le format metier `Carnet N x montant`.

Problemes UX:

- Plusieurs textes apparaissent mal encodes dans le code et peuvent etre visibles selon les chemins: `Session expiree`, `Repartition`, `Expire`.
- Le popup detail contient beaucoup de chiffres; il peut etre difficile de distinguer ce qui est disponible, bloque, actif QR, consomme ou expire.
- Les termes `activeQty`, `blockedQty`, `qrActiveQty` correspondent au modele mais doivent etre traduits de facon simple dans l'UI.

Recommandations:

- Corriger l'encodage UTF-8 de tout l'ecran.
- Dans le popup, mettre `Tickets disponibles` comme valeur principale.
- Regrouper les autres statuts dans une section secondaire `Details`.
- Ajouter une explication courte: `Les tickets bloques sont dans un QR avec lignes expirees`.

Priorite: haute.

### 4. Liste QR

Points positifs:

- Les filtres QR sont utiles: tous, actifs, bloques, consommes.
- Les cartes affichent un mini QR, l'etat, la date et le montant.
- L'action vers le detail QR est directe.

Problemes UX:

- Les labels de type `Bloques`, `Consomme`, `Consommee le`, `Expiree le` montrent un probleme d'encodage ou de coherence grammaticale.
- Le montant affiche `MRU` en tres petit, ce qui peut reduire la comprehension.
- La date `Actif le` est ambigue; pour un QR actif, `Cree le` ou `Genere le` est plus clair.
- Un QR bloque est determine par `hasMixedExpiration`, ce qui est metierement correct mais pas explique a l'utilisateur.

Recommandations:

- Remplacer les dates par des labels stables: `Genere le`, `Consomme le`, `Expire le`, `Bloque depuis`.
- Ajouter un message explicatif pour les QR bloques dans le detail.
- Corriger l'encodage des labels.

Priorite: haute.

### 5. Detail QR

Points positifs:

- L'ecran detail regroupe QR visuel, montant, dates et composition.
- Les actions contextuelles sont conditionnees par l'etat: retirer si actif, separer si bloque.
- La navigation vers retirer/separer utilise les routes dediees.

Problemes UX:

- La logique `canRetirer` exige `totalQty > 1`, ce qui est correct, mais l'utilisateur doit comprendre pourquoi un QR de 1 ticket n'est pas retirable.
- La fleche retour a ete harmonisee recemment, mais le projet contient encore plusieurs implementations locales de header.
- Les libelles d'etat et dates doivent rester strictement coherents avec la liste QR.

Recommandations:

- Si un QR a un seul ticket, afficher un texte clair: `Un QR contenant un seul ticket ne peut pas etre retire`.
- Centraliser le header detail QR via `AppBarHeader` avec options.
- Centraliser les labels QR dans un helper pour eviter les variations.

Priorite: moyenne.

### 6. Generation QR

Points positifs:

- Le parcours a une confirmation avant emission.
- Le payload est construit a partir des lignes disponibles.
- Apres succes, les caches et bus sont rafraichis.
- La navigation retourne vers `/home`.

Problemes UX:

- Le succes generation QR revient directement a l'accueil avec toast, alors que achat et transfert ont un ecran final. Cela peut etre percu comme moins informatif.
- Les cards ont une zone quantite harmonisee avec achat, mais il faut continuer a surveiller les overflows sur petits appareils.
- Les textes avec accents dans certains chemins sont encore mal encodes.

Recommandations:

- Choisir une seule convention de succes: soit ecran final pour achat/QR/transfert, soit toast + retour. La meilleure option est un ecran final court pour les trois.
- Garder le retour final a `/home`, comme demande.
- Ajouter test widget golden ou snapshot sur les cards quantite pour eviter les regressions de layout.

Priorite: moyenne.

### 7. Nouvel achat

Points positifs:

- Le parcours inclut selection, preuve, confirmation et succes.
- Le retour succes va vers `/home`.
- La commande affiche bien qu'elle est en attente de validation.
- Les cartes de selection sont visuellement proches de la generation QR.

Problemes UX:

- La preuve de paiement est obligatoire dans le code; si la demande metier evolue, l'ecran doit rendre cette contrainte visible tres tot.
- Les cartes achat ont beaucoup subi de micro-ajustements; risque de fragilite visuelle.
- Le nombre de tickets selectionne et le montant total doivent rester visibles sans scroller.

Recommandations:

- Afficher explicitement `Preuve de paiement obligatoire` pres du bouton de soumission.
- Garder le total dans la barre basse, mais ajouter un message d'erreur inline si aucune preuve.
- Ajouter tests de non-regression sur achat: selection quantite, confirmation, retour accueil.

Priorite: haute.

### 8. Transfert de carnets

Points positifs:

- Le transfert distingue les carnets transferables.
- Si aucun carnet n'est transferable, l'input destinataire est masque.
- La confirmation affiche le receveur.
- Le succes retourne a l'accueil.

Problemes UX:

- L'ecran transfert est parfois ouvert hors routeur depuis l'accueil avec `rootNavigator`.
- Le libelle de transfert doit rester consistent: `Transferer`, `Transfert`, `Client receveur`.
- Le concept de carnet transferable peut etre opaque: l'utilisateur ne sait pas pourquoi certains carnets ne sont pas affiches.

Recommandations:

- Naviguer via `/transfer-carnets`.
- Ajouter une phrase sous le titre: `Seuls les carnets complets et non utilises sont transferables`.
- Dans l'etat vide, afficher: `Aucun carnet transferable. Les carnets partiels ou deja utilises dans un QR ne peuvent pas etre transferes.`

Priorite: haute.

### 9. Retrait QR

Points positifs:

- Le retrait est bloque pour les QR non actifs ou contenant un seul ticket.
- Le retour apres succes force `/qr`.
- La confirmation a ete simplifiee pour garder uniquement le montant.

Problemes UX:

- L'utilisateur doit comprendre la difference entre `retirer du QR` et `separer QR`.
- Le message pour QR a un seul ticket doit etre visible et pedagogique.
- Le flux ne presente pas d'ecran final, seulement toast + retour liste QR.

Recommandations:

- Ajouter un sous-titre court: `Retirez une partie des tickets pour creer un nouveau QR`.
- Garder le retour a `/qr`.
- Si aucun ticket selectionne, afficher un message inline proche des quantites, pas seulement toast.

Priorite: moyenne.

### 10. Separation QR

Points positifs:

- Le flux cible les QR bloques.
- La confirmation explique que la separation cree un nouveau QR pour les lignes non expirees.
- Le retour apres succes force `/qr`.

Problemes UX:

- Le terme `Separer` peut etre moins clair que `Debloquer les tickets valides`.
- Plusieurs textes sont encore mal encodes dans ce fichier.
- La confirmation peut etre dense avec lignes, tickets valides, tickets expires.

Recommandations:

- Titre utilisateur recommande: `Separer les tickets valides`.
- Ajouter une explication en une phrase: `Les tickets expires restent separes des tickets encore utilisables`.
- Corriger UTF-8.

Priorite: moyenne.

### 11. Historique

Points positifs:

- Les filtres rapides couvrent les cas principaux.
- L'historique fusionne transactions et achats soumis.
- Pagination et plage de dates existent.

Problemes UX:

- L'ecran est potentiellement complexe: filtres type, filtres rapides, date range, pagination.
- Les transactions QR, achats, consommations et transferts peuvent se melanger sans hierarchie visuelle suffisante.
- Certains commentaires et libelles montrent des caracteres mal encodes.

Recommandations:

- Garder un filtre principal simplifie: `Tous`, `Achats`, `QR`, `Transferts`, `Consommations`.
- Mettre les filtres avances/date dans un bottom sheet.
- Ajouter des icones et couleurs stables par type de transaction.

Priorite: moyenne.

### 12. Profil / Parametres

Points positifs:

- Les statistiques compte donnent une vue rapide: achats, QR, consommations.
- Les preferences langue, biometrie et theme sont presentes.
- Pull-to-refresh possible.

Problemes UX:

- `NIF demo 21450033` semble etre une donnee de demonstration et ne doit pas rester en production.
- Les statistiques declenchent plusieurs appels API, dont transactions paginees; cela peut ralentir l'ouverture du profil.
- Les libelles `Etat du service` et `Verification de la version et des organisations` sont techniques.

Recommandations:

- Remplacer le NIF demo par une vraie donnee ou masquer le champ si absent.
- Charger les stats en lazy/background avec skeleton.
- Reformuler `Etat du service` en `Connexion ACPEC`.

Priorite: haute pour le NIF demo, moyenne pour le reste.

### 13. Notifications

Points positifs:

- Les notifications d'achat sont synchronisees.
- Le bouton `Tout lu` existe.
- Les cartes achat distinguent validation et rejet.

Problemes UX:

- Beaucoup de commentaires et certains labels dans le fichier sont mal encodes.
- Pour les notifications achat, le tap marque lu mais ne navigue pas vers le detail achat, contrairement aux notifications generiques.
- L'ecran utilise un header custom different des autres.

Recommandations:

- Corriger UTF-8.
- Sur tap d'une notification achat, marquer lu puis ouvrir le detail achat si `actionRoute` existe.
- Harmoniser le header avec `AppBarHeader` ou le style de retour simple sans background.

Priorite: moyenne.

## Problemes transverses prioritaires

### P0 - Encodage UTF-8

Impact:

- Les libelles utilisateur peuvent apparaitre corrompus.
- L'image de marque et la comprehension sont fortement degradees.

Exemples observes:

- Exemples de formes corrompues observees: variantes de `Generer`, `Transferer`, `Separer`, `Valides`, `Creez`.
- Commentaires corrompus dans plusieurs fichiers.

Recommandation:

- Convertir tous les fichiers Dart en UTF-8 sans BOM.
- Ajouter une verification CI qui detecte les sequences mojibake les plus frequentes.

Priorite: critique.

### P1 - Navigation et retours

Etat actuel:

- Achat: succes -> bouton retour `/home`.
- Generation QR: succes -> retour direct `/home`.
- Transfert: succes -> bouton retour `/home`.
- Retrait QR: succes -> retour `/qr`.
- Separation QR: succes -> retour `/qr`.

Risques:

- Plusieurs APIs de navigation coexistent: `context.push`, `context.go`, `Navigator.push`, `rootNavigator`.
- Les retours peuvent diverger selon le chemin d'entree.

Recommandation:

- Definir une convention:
  - Actions principales hors tabs: `context.push(route)`.
  - Succes final achat/QR/transfert: `context.go('/home')`.
  - Succes final actions QR detail: `context.go('/qr')`.
  - Back simple: `popOrGoClientHome(context)` si racine possible.

Priorite: haute.

### P1 - Headers et fleches retour

Impact:

- L'utilisateur percoit des ecrans de familles differentes alors qu'ils appartiennent au meme espace client.

Recommandation:

- Utiliser `AppBarHeader` partout.
- Garder deux variantes seulement:
  - header grand pour actions principales;
  - header compact avec `plainBackButton` pour details.

Priorite: haute.

### P1 - Libelles metier

Problemes:

- Melange francais/anglais: `Transfer carnets`.
- Libelles ambigus: `Actif le`, `Separer`, `Retirer`.

Recommandation:

- Creer une table centrale de labels:
  - `Acheter un carnet`
  - `Generer un QR`
  - `Transferer des carnets`
  - `Retirer du QR`
  - `Separer les tickets valides`
  - `Genere le`
  - `Expire le`
  - `Consomme le`

Priorite: haute.

### P2 - Densite d'information

Problemes:

- Certains ecrans de detail et historique affichent trop d'informations au meme niveau.
- Les confirmations peuvent contenir des sections detaillees qui ralentissent la decision.

Recommandation:

- Mettre l'information principale en haut: montant, tickets, destinataire, etat.
- Deplacer les details dans des sections collapsibles ou secondaires.

Priorite: moyenne.

### P2 - Etats vides et erreurs

Problemes:

- Les etats vides sont presents mais pas toujours explicatifs.
- Les erreurs session/serveur sont parfois techniques.

Recommandation:

- Normaliser les messages:
  - session expiree: `Votre session a expire. Reconnectez-vous.`
  - aucune donnee: expliquer pourquoi et quelle action faire.
  - erreur serveur: proposer `Reessayer`.

Priorite: moyenne.

## Checklist de regression UX

Avant livraison, tester manuellement sur Android petit ecran et ecran standard:

- Connexion client puis affichage accueil.
- Achat complet: selection carnet, quantite, preuve, confirmation, succes, retour accueil.
- Achat sans preuve: message clair.
- Generation QR: selection, confirmation, succes, retour accueil.
- Transfert avec carnets transferables: destinataire, confirmation, succes, retour accueil.
- Transfert sans carnet transferable: message vide et input destinataire masque.
- Liste QR: filtres tous/actifs/bloques/consommes.
- Detail QR actif avec plusieurs tickets: action retirer visible.
- Detail QR actif avec un seul ticket: retrait impossible et message clair.
- Retrait QR: confirmation avec montant seulement, succes, retour liste QR.
- Detail QR bloque: action separation visible.
- Separation QR: confirmation, succes, retour liste QR.
- Mes carnets: filtre actif/expire, popup detail.
- Historique: filtres, scroll pagination, refresh.
- Profil: stats, langue, biometrie, mode sombre, deconnexion.
- Notifications: achat valide/rejete, tout lu, navigation detail si disponible.

## Plan d'action recommande

### Phase 1 - Stabilisation visible

- Corriger UTF-8 dans tous les fichiers client.
- Corriger les libelles rapides de l'accueil.
- Harmoniser tous les headers client.
- Remplacer la navigation transfert accueil par route `/transfer-carnets`.
- Ajouter messages explicites pour QR 1 ticket et carnets non transferables.

### Phase 2 - Robustesse workflow

- Ajouter tests widget ou integration pour achat, generation QR, transfert, retrait, separation.
- Ajouter tests de navigation: succes achat/QR/transfert -> `/home`, succes retrait/separation -> `/qr`.
- Ajouter tests de non-regression sur etats vides.

### Phase 3 - Qualite produit

- Centraliser labels, dates et formats metier.
- Simplifier les filtres historique.
- Harmoniser les ecrans de succes.
- Ajouter instrumentation analytics pour connaitre les abandons de parcours.

## Conclusion

L'espace client est proche d'un flux produit utilisable. Les priorites avant production sont l'encodage UTF-8, l'harmonisation de navigation, la coherence des headers et la clarification des libelles metier. Les workflows principaux sont presents, mais ils doivent etre verrouilles par des tests de navigation et des tests d'etats vides pour eviter les regressions dues aux ajustements UI frequents.

## Suivi des corrections appliquees

Date: 2026-06-05

Corrections appliquees:

- Accueil: libelles rapides simplifies (`Acheter un carnet`, `Generer un QR`, `Transferer des carnets`).
- Accueil: ouverture du transfert via la route `/transfer-carnets`, sans `rootNavigator`.
- Profil: suppression du NIF de demonstration.
- Profil: `Etat du service` reformule en `Connexion ACPEC`.
- Profil: libelles statistiques corriges (`QR emis`, `Consommes`).
- Transfert: ajout d'une explication sur les carnets transferables.
- Transfert: etat vide enrichi quand aucun carnet n'est transferable.
- Achat: indication visible que la preuve de paiement est obligatoire.
- Liste QR: dates clarifiees (`Genere le`, `Bloque le`, `Consomme le`, `Expire le`).
- Detail QR: message explicite quand un QR a un seul ticket et ne peut pas etre retire.
- Separation QR: textes visibles principaux corriges.

Validation:

- `dart format` execute sur les fichiers corriges.
- `dart analyze` cible: aucun probleme trouve.

Reste a traiter:

- `lib/features/settings/screens/notifications_screen.dart` contient encore des sequences mojibake dans certaines chaines et commentaires. Le fichier doit etre normalise en UTF-8 ou reecrit par blocs plus larges avant correction complete, car les patchs ligne par ligne ne correspondent pas aux octets reels du fichier.
