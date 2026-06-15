# Audit UI/UX - Flux achat, transfert, generation QR et historique

Date: 2026-06-13

## Perimetre

Audit cible sur les ecrans suivants:

- `lib/features/purchases/screens/submit_purchase_screen.dart`
- `lib/features/qr/screens/transfer_carnets_screen.dart`
- `lib/features/qr/screens/emit_qr_screen.dart`
- `lib/features/transactions/screens/transactions_screen.dart`
- ecrans relies de confirmation et succes:
  - `lib/features/purchases/screens/purchase_confirmation_screen.dart`
  - `lib/features/qr/screens/transfer_confirmation_screen.dart`
  - `lib/features/qr/screens/qr_action_confirmation_screen.dart`
  - `lib/shared/widgets/purchase_submit_success_dialog.dart`

## Synthese Executives

Le flux est metierement complet et les parcours critiques sont presents. Les ecrans principaux ont deja une base visuelle correcte, avec cartes, headers, et confirmations. Le probleme principal n’est pas la fonctionnalite brute, mais la coherence UX entre les ecrans et la lisibilite des informations critiques.

Les risques les plus visibles sont:

- surcharge d’information sur certains ecrans de confirmation et dans l’historique;
- incoherence ponctuelle des tailles de titres, montants et sous-titres;
- trop de variantes de composants pour afficher un montant ou un etat;
- hierarchie visuelle parfois trop forte sur le detail, pas assez forte sur la decision principale;
- differences de navigation et de retour entre flux achat, QR et transfert.

## Points Forts

### 1. Structure metier claire

- Le parcours achat suit une vraie sequence: selection, confirmation, preuve, succes.
- Le parcours transfert suit une vraie sequence: selection, confirmation, succes.
- La generation QR est aussi structuree avec confirmation avant execution.
- L’historique regroupe les evenements en cartes et sections.

### 2. Usage coherent des cards

- Les ecrans d’achat, transfert et historique ont tous une base visuelle card-based.
- Le style general est suffisamment proche pour pouvoir etre harmonise sans re-design complet.

### 3. Effort de clarte sur les confirmations

- Les ecrans de confirmation reduisent le risque d’erreur en montrant un resume avant action.
- Les ecrans de succes evitent de laisser l’utilisateur sans feedback.

## Constats Par Flux

### Achat

Ce qui fonctionne:

- selection des carnets lisible;
- bouton d’action final clair;
- confirmation et succes bien distincts;
- affichage du total en bas utile pour la decision.

Points de friction:

- la densite d’information reste forte sur les cartes d’offre;
- la preuve de paiement est une contrainte metier forte, mais elle peut arriver trop tard dans la perception utilisateur;
- le montant et les labels ne sont pas toujours presents avec la meme hiérarchie visuelle selon l’etape.

Recommandations:

- afficher la contrainte de preuve plus tot, juste sous le titre ou le champ de selection;
- conserver un seul style de montant pour toutes les etapes;
- reduire le texte secondaire dans les cartes d’offre.

Priorite: haute.

### Transfert

Ce qui fonctionne:

- la liste des carnets transferables est orientee action;
- le destinataire est clairement demande;
- le succes est affiche apres l’action.

Points de friction:

- le concept de carnet transferable n’est pas evident pour un utilisateur non technique;
- les cartes peuvent encore etre trop denses entre le nom du carnet, l’expiration, le montant et la selection;
- le statut d’etat vide doit expliquer pourquoi aucun carnet n’est transferible.

Recommandations:

- ajouter une phrase pedagogique courte sous le titre;
- expliciter les raisons d’exclusion des carnets non visibles;
- garder le montant au meme format que l’achat.

Priorite: haute.

### Generation QR

Ce qui fonctionne:

- la selection des lignes est claire;
- la confirmation permet de verifier les quantites et le total;
- le succes referme le parcours correctement.

Points de friction:

- les cartes de composition peuvent devenir longues si le carnet, la quantite et l’expiration sont tous mis au meme niveau;
- la distinction entre montant principal et detail secondaire doit rester stricte;
- la page peut perdre en lisibilite sur petits ecrans si les sections ne sont pas compactees.

Recommandations:

- mettre le total en avant, puis les lignes de composition en second;
- garder l’expiration en texte secondaire;
- conserver des cartes a hauteur previsible.

Priorite: moyenne a haute.

### Historique

Ce qui fonctionne:

- les regroupements par jour sont utiles;
- les cartes de transaction donnent une lecture chronologique;
- le mode “expand/collapse” permet d’eviter d’afficher tout le detail d’un coup.

Points de friction:

- l’historique peut rapidement devenir trop charge visuellement;
- les lignes detaillees peuvent encore paraitre trop “techniques”;
- les differents types d’evenements ne sont pas toujours immediatement distinguables au premier regard.

Recommandations:

- garder une hierarchie simple: titre, date, montant, etat;
- ne montrer les details qu’au besoin dans le dropdown;
- distinguer visuellement les familles d’evenements par couleur ou badge.

Priorite: moyenne.

## Problemes Transverses

### 1. Cohérence typographique

Constat:

- les tailles de titres varient encore entre ecrans;
- les montants utilisent parfois des styles differents selon le contexte;
- certaines cartes donnent trop de poids au texte secondaire.

Impact:

- sensation de produit hétérogène;
- fatigue de lecture;
- impression de “reconstruction” entre ecrans qui devraient appartenir au meme systeme.

Recommandation:

- standardiser 3 niveaux seulement:
  - titre d’etape;
  - ligne principale;
  - texte secondaire;
  - montant inline.

Priorite: haute.

### 2. Cohérence des montants

Constat:

- certains montants sont presents en format inline, d’autres en texte brut;
- la taille et le poids du `MRU` peuvent varier;
- le montant est parfois plus visible que le contexte, parfois l’inverse.

Impact:

- lecture moins rapide;
- impression de duplication de styles;
- risque de confusion dans les ecrans de revue.

Recommandation:

- utiliser un seul composant de montant dans tous les parcours;
- le garder identique en taille, couleur, graisse, et traitement du `MRU`.

Priorite: critique.

### 3. Navigation et sortie de flux

Constat:

- les sorties de flux ne suivent pas toujours le meme schéma;
- certaines actions reviennent a l’accueil, d’autres a la liste QR, d’autres restent sur le contexte;
- les success screens ne sont pas toutes alignées entre achat, QR et transfert.

Impact:

- effort cognitif supplementaire;
- impression de parcours fragmentes.

Recommandation:

- definir un contrat clair:
  - achat et transfert: retour accueil;
  - actions QR de details: retour liste QR;
  - success screens: meme pattern visuel et meme comportement de retour.

Priorite: haute.

### 4. Etats vides et erreurs

Constat:

- certains etats vides sont tres directs, mais pas toujours explicatifs;
- les erreurs techniques peuvent remonter de facon trop brute.

Impact:

- baisse de confiance;
- blocage sans prochaine action claire.

Recommandation:

- pour chaque etat vide, preciser:
  - pourquoi l’utilisateur ne voit rien;
  - quoi faire ensuite.
- pour chaque erreur, fournir un bouton `Reessayer` ou `Retour`.

Priorite: moyenne.

## Recommandations Prioritaires

### P0

- Harmoniser le style des montants et du `MRU`.
- Standardiser les titres de flux et de sections.
- Homogeneiser les retours de confirmation/succes.

### P1

- Clarifier les messages sur les carnets transferables.
- Simplifier les cartes d’offre et les details de l’historique.
- Mieux separer resume et details.

### P2

- Ajouter des micro-textes d’aide pour les actions metier moins evidentes.
- Renforcer l’accessibilite visuelle: contraste, zones tactiles, taille des textes secondaires.

## Plan Recommande

1. Etape 1: figer les composants UI de base.
2. Etape 2: appliquer un systeme unique pour les montants, titres et badges.
3. Etape 3: simplifier les ecrans de confirmation et l’historique.
4. Etape 4: ajouter des tests de non-regression visuelle ou widget sur les parcours critiques.

## Conclusion

Le produit est fonctionnel, mais il manque encore un niveau de coherence visuelle et narrative entre les ecrans. Le plus gros gain UX viendra de la standardisation des montants, des titres, des retours de flux et de la reduction de densite sur les details.

