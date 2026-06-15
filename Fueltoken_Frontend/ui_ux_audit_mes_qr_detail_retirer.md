# Audit UI/UX - Mes QR, Détail QR, Retirer

## Périmètre
- Écran `Mes QR`
- Écran `Détail QR`
- Écran `Retirer`

## Résumé Exécutif
L’interface est globalement propre et cohérente, mais la lecture métier reste trop subtile sur les états importants: QR actif, bloqué, expiré et ligne retirée.
Le principal problème n’est pas la mise en page, mais la hiérarchie visuelle et la clarté des états.

## Constats

### 1. `Mes QR` manque de différenciation forte entre les états
Les cartes montrent bien le QR, le badge d’état, le montant et la date, mais les différences entre actif, bloqué, consommé et expiré restent peu marquées.

- Référence: `lib/features/qr/screens/qr_list_screen.dart`
- Zones clés:
  - carte QR: lignes autour de `QrCard`
  - badge d’état: `QrStateBadge`
  - filtre: `QrFilterRow`

Impact:
- L’utilisateur comprend l’état global, mais pas instantanément la nature métier du QR.
- Les QR bloqués peuvent être perçus comme des QR normaux avec une simple variation de couleur.

Recommandation:
- Renforcer la distinction visuelle des états avec des variantes plus nettes:
  - QR actif: rendu standard
  - QR bloqué: accent orange ou ambre plus visible
  - QR expiré: tonalité rouge/grisée plus marquée
  - QR consommé: rendu plus neutre et plus discret

### 2. `Détail QR` reste trop plat pour un QR bloqué
L’écran détail affiche la composition de manière propre, mais les lignes expirées et valides sont présentées dans le même flux visuel.
Pour un QR bloqué, l’utilisateur doit lire chaque ligne pour comprendre ce qui reste exploitable.

- Référence: `lib/features/qr/screens/qr_detail_screen.dart`
- Zones clés:
  - en-tête de détail
  - carte QR principale
  - carte `Composition`

Impact:
- La logique métier est présente, mais elle n’est pas immédiatement lisible.
- La partie expirée n’a pas assez de poids visuel pour être identifiée en un coup d’œil.

Recommandation:
- Conserver la carte unique, mais renforcer légèrement la hiérarchie:
  - fond légèrement grisé pour les lignes expirées
  - libellé `Expirée le` pour les lignes expirées
  - éventuel badge discret `Expirée`
- Garder le fond général blanc pour ne pas alourdir l’écran.

### 3. `Retirer` est fonctionnel, mais un peu redondant
L’écran propose une sélection de lignes, une carte de synthèse et un bouton fixe en bas.
Le parcours fonctionne, mais il demande un peu trop de lecture verticale avant l’action finale.

- Référence: `lib/features/qr/screens/retirer_qr_screen.dart`
- Zones clés:
  - titre et introduction
  - liste des lignes à retirer
  - carte de synthèse `Sélection`
  - bouton d’action fixé en bas

Impact:
- L’utilisateur doit scanner l’écran pour comprendre l’effet de sa sélection.
- La carte de synthèse et le bouton du bas se font un peu concurrence.

Recommandation:
- Garder le bouton fixé en bas, mais simplifier le corps:
  - synthèse plus compacte
  - mettre davantage en évidence le total sélectionné
  - alléger l’introduction textuelle

## Recommandations Prioritaires

### Priorité 1
Clarifier visuellement les QR bloqués et expirés dans `Détail QR`.

### Priorité 2
Renforcer la hiérarchie des états dans `Mes QR`.

### Priorité 3
Alléger le parcours de sélection dans `Retirer`.

## Direction de design recommandée
- Fond principal blanc conservé
- États signalés par couleur, pas par surcharge
- QR bloqué et expiré doivent être reconnaissables en moins de 2 secondes
- Les cartes doivent rester lisibles sur mobile sans multiplier les blocs

## Conclusion
Le socle visuel est bon.
Le gain principal viendra d’une meilleure hiérarchie des états et d’un langage visuel plus explicite entre liste, détail et retrait.
