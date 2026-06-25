# Doctrine métier — FuelToken V1 (carnet, wallet, QR, transfert)

Document de référence du cœur métier : le modèle de valeur et les opérations qui la
déplacent. Énonce principes, invariants testables et tests. Le code se conforme à cette
doctrine. Les contrôles d'accès (session, device-trust, rôle, PIN) sont régis par la
*Doctrine de sécurité mobile* ; toute opération de ce document leur est en plus soumise.

```text
---
doctrine: metier-fueltoken
version_doctrine: 1.0
statut: actif
prerequis: [securite-mobile]
principe_resolution_conflit: fail-closed
principe_valeur: la valeur ne se crée qu'à l'achat et ne se détruit qu'à la consommation
---
```

---

## 0. Modèle de valeur

### Principes

La valeur circule entre quatre objets, tous rattachés à la société FuelToken et ancrés
sur le client via son partenaire :

```text
Wallet    : le portefeuille d'un client (partenaire). Contient des carnets.
Carnet    : l'unité de valeur identifiable. Un carnet = un ensemble de faces.
QR        : un bon de consommation émis à partir d'un carnet, présenté en station.
Transaction : la trace immuable de chaque mouvement de valeur.
```

La règle qui domine tout le document : **la valeur ne se crée qu'à l'achat et ne se
détruit qu'à la consommation.** Tout le reste — transfert, émission de QR, séparation —
déplace la valeur sans en changer le total.

---

## 1. Wallet

### Principes

Le portefeuille appartient à un client unique dans la société FuelToken. Ses quantités
sont dérivées des carnets qu'il contient, jamais stockées en double.

### Invariants

```text
INV-W1  Un wallet est identifié par (partner_id, company_id), unique au niveau base.
INV-W2  Tout wallet appartient à la société FuelToken (company_id = société FuelToken).
INV-W3  Les quantités d'un wallet sont calculées à partir de ses carnets (non stockées
        en doublon) ; elles reflètent toujours l'état réel des carnets.
INV-W4  La création d'un wallet est idempotente : deux demandes concurrentes pour le même
        (partner_id, company_id) aboutissent à un seul wallet.
```

### Tests

```text
T-W1  Deux wallets pour le même (partner, company) => rejet base.
T-W2  Création concurrente du même wallet => un seul wallet, pas d'erreur remontée.
T-W3  Modifier un carnet => les quantités du wallet reflètent le changement à la lecture.
```

---

## 2. Carnet

### Principes

Le carnet est l'unité de valeur identifiable. Un carnet existe comme un enregistrement
unique, créé à l'approbation d'un achat, numéroté localement au lot, et porteur de son
lot d'origine pour toute sa vie. Ses faces se répartissent entre des états dont la somme
est invariante.

### Invariants

```text
INV-C1   Un carnet correspond à un enregistrement unique (une face_line = un carnet).
INV-C2   Conservation : qty_initial = qty_available + qty_qr_active + qty_qr_blocked
         + qty_consumed + qty_expired, à tout instant.
INV-C3   Un carnet est créé à l'approbation d'un achat ; il en existe un par carnet acheté.
INV-C4   Chaque carnet porte une identité stable et immuable : un numéro lisible
         (numéro de lot + index local) et un code court non devinable.
INV-C5   L'index de numérotation est local au lot d'achat et séquentiel ; il n'expose
         pas de compteur global.
INV-C6   Chaque carnet porte son lot d'origine (purchase_id, purchase_line_id), immuable,
         conservé à travers transfert, émission de QR et consommation.
INV-C7   Un carnet est dit intact si qty_available = qty_initial et qu'aucune autre face
         n'est engagée. Seul un carnet intact est transférable.
INV-C8   L'identité d'un carnet (numéro, code, lot) ne change jamais après création,
         y compris lors d'un transfert.
```

### Tests

```text
T-C1  Achat de N carnets approuvé => N enregistrements, numérotés 1..N localement au lot.
T-C2  À tout moment, somme des faces d'un carnet = qty_initial.
T-C3  Numéro et code d'un carnet inchangés après un transfert.
T-C4  Lot d'origine présent et identique sur le carnet, sur le QR émis, et sur la
      transaction de consommation.
T-C5  Carnet avec une face engagée (QR ou consommée) => non transférable.
```

---

## 3. Transfert de carnet

### Principes

Transférer un carnet, c'est le **relocaliser** d'un wallet vers un autre dans la même
société : il change de détenteur sans perdre son identité ni se dédoubler. Seuls les
carnets intacts se transfèrent. L'opération est idempotente et protégée contre la
double-dépense.

### Invariants

```text
INV-TR1  Un transfert déplace un carnet en changeant son wallet détenteur ; il ne crée
         pas de nouveau carnet et ne duplique pas l'identité.
INV-TR2  Seul un carnet intact (INV-C7) est transférable. Un carnet entamé est refusé.
INV-TR3  Source et destinataire sont dans la même société FuelToken.
INV-TR4  Toute opération de transfert exige une clé d'idempotence ; l'unicité
         (wallet source, clé) est garantie au niveau base.
INV-TR5  La confirmation verrouille les wallets et les carnets concernés, relit leur état
         sous verrou, et revérifie l'appartenance au wallet source avant de déplacer.
         Deux transferts concurrents du même carnet : un seul aboutit.
INV-TR6  Un transfert conserve la valeur : le total des deux wallets avant = après.
INV-TR7  Un transfert produit deux écritures de transaction (débit source, crédit
         destinataire) référençant le carnet et son lot.
```

### Tests

```text
T-TR1  Transfert d'un carnet intact => carnet présent chez le destinataire avec même
       identité, absent chez la source.
T-TR2  Transfert d'un carnet entamé => refus.
T-TR3  Transfert vers une autre société => refus.
T-TR4  Retransmission séquentielle même clé d'idempotence => aucun double effet.
T-TR5  Deux transferts concurrents du même carnet => un seul réussit, l'autre refusé.
T-TR6  Somme des valeurs (source + destinataire) inchangée par le transfert.
T-TR7  Transfert => deux lignes de transaction cohérentes.
```

---

## 4. QR (bon de consommation)

### Principes

Un QR est un bon émis à partir d'un **carnet désigné**. Émettre un QR engage des faces
d'un carnet précis sans toucher aux autres carnets. Le QR suit une machine à états ; il
ne peut être consommé qu'une fois. Son identifiant n'est pas devinable.

### Invariants

```text
INV-Q1   Un QR est émis à partir d'un carnet désigné ; engager des faces d'un carnet
         n'affecte aucun autre carnet.
INV-Q2   L'émission déplace des faces de qty_available vers qty_qr_active du carnet
         source ; la valeur totale du carnet est conservée (INV-C2).
INV-Q3   L'allocation automatique remplit un carnet déjà entamé avant d'en ouvrir un
         nouveau, pour minimiser le nombre de carnets rendus non transférables.
INV-Q4   Un QR porte le carnet et le lot d'origine de ses faces (face_line_id,
         purchase_id, purchase_line_id).
INV-Q5   États du QR : active, blocked, consumed, expired. Les transitions sont
         explicites ; un QR consommé ou expiré ne redevient jamais actif.
INV-Q6   La consommation en station verrouille le QR et relit son état sous verrou ;
         seul un QR actif se consomme ; il passe alors à consumed.
INV-Q7   Un QR ne peut être consommé deux fois : la machine à états et le verrou le
         garantissent, et toute consommation exige une clé d'idempotence.
INV-Q8   L'identifiant public d'un QR est aléatoire et non devinable (pas de séquence).
INV-Q9   La consommation produit une transaction référençant le QR, le carnet et le lot.
```

### Tests

```text
T-Q1   Émettre un QR d'un carnet => faces engagées sur ce carnet seul ; autres carnets intacts.
T-Q2   Après émission, somme des faces du carnet source inchangée (conservation).
T-Q3   Allocation auto répétée => un même carnet est vidé avant qu'un nouveau soit ouvert.
T-Q4   QR => porte face_line, carnet et lot d'origine.
T-Q5   Consommer un QR actif => passe à consumed.
T-Q6   Consommer un QR déjà consommé => second refus.
T-Q7   Deux consommations concurrentes du même QR => une seule aboutit.
T-Q8   Identifiants de deux QR successifs => non séquentiels.
T-Q9   Consommation => transaction avec QR, carnet et lot.
```

---

## 5. Transaction et traçabilité de lot

### Principes

La transaction est la trace immuable de chaque mouvement de valeur. Elle dénormalise le
lot d'origine au moment de l'événement, ce qui fait du journal des transactions le
registre de provenance, indépendant de l'état courant des objets.

### Invariants

```text
INV-TX1  Chaque mouvement de valeur (achat, transfert, émission, blocage, expiration,
         consommation) produit une ou des écritures de transaction.
INV-TX2  Les transactions sont en ajout seul : elles ne sont ni modifiées ni supprimées.
INV-TX3  Chaque ligne de transaction porte le lot d'origine (purchase_id,
         purchase_line_id) et, selon l'événement, le carnet, le QR et le transfert.
INV-TX4  La vie d'un lot se reconstruit entièrement en parcourant les transactions par
         purchase_id : achat -> wallets -> transferts -> émissions -> consommations.
INV-TX5  La provenance se lit dans les transactions, pas dans l'état courant des objets
         (qui évolue) ; le lot dénormalisé est figé à l'instant de l'événement.
```

### Tests

```text
T-TX1  Chaque opération de valeur => transaction(s) correspondante(s).
T-TX2  Tentative de modification/suppression d'une transaction => refus.
T-TX3  Ligne de transaction => lot d'origine présent ; carnet/QR/transfert selon le cas.
T-TX4  Requête par purchase_id => historique complet du lot reconstitué.
```

---

## 6. Invariants transverses de valeur

### Principes

Au-delà de chaque opération, des garanties globales tiennent en permanence sur la valeur.

### Invariants

```text
INV-VAL1  La valeur n'est créée qu'à l'achat (création de carnets) et détruite qu'à la
          consommation. Aucune autre opération ne change le total de valeur du système.
INV-VAL2  Toute mutation économique (transfert, émission, consommation) est idempotente :
          une clé d'idempotence est exigée et son unicité est garantie au niveau base.
INV-VAL3  Toute mutation économique sérialise l'accès aux objets de valeur concernés par
          verrou pessimiste, avec relecture sous verrou ; aucun search-avant-create comme
          seule protection de concurrence.
INV-VAL4  Toute opération de valeur est soumise aux contrôles de la doctrine de sécurité
          (session valide, appareil trusted, rôle requis, action_code valide, audit).
INV-VAL5  Toute opération de valeur respecte le cloisonnement société (INV-S4/S5 sécurité).
```

### Tests

```text
T-VAL1  Sur une séquence d'opérations sans achat ni consommation => total de valeur constant.
T-VAL2  Mutation sans clé d'idempotence => refus.
T-VAL3  Mutations concurrentes sur le même objet => sérialisées, pas de double effet.
T-VAL4  Opération de valeur sans appareil trusted ou sans PIN => refus (renvoi sécurité).
```

---

## 7. Anti-patterns (interdits)

```text
ANTI-M1  Stocker une quantité de wallet en doublon de l'état des carnets (contre INV-W3).
ANTI-M2  Recréer/dupliquer un carnet lors d'un transfert au lieu de le relocaliser
         (contre INV-TR1).
ANTI-M3  Transférer un carnet entamé (contre INV-TR2).
ANTI-M4  search() avant create()/write() comme seule protection de double-dépense
         (contre INV-VAL3).
ANTI-M5  Identifiant de carnet ou de QR séquentiel/devinable exposé publiquement
         (contre INV-C5/Q8).
ANTI-M6  Permettre une transition d'état QR qui réactive un QR consommé/expiré
         (contre INV-Q5).
ANTI-M7  Modifier ou supprimer une transaction (contre INV-TX2).
ANTI-M8  Toute opération qui change le total de valeur hors achat/consommation
         (contre INV-VAL1).
```

---

## 8. Checklist de conformité

```text
Une implémentation métier est conforme si et seulement si :
[ ] wallet unique par (partner, company), quantités dérivées des carnets ;
[ ] un carnet = un enregistrement, conservation des faces vérifiée en continu ;
[ ] carnet créé à l'approbation d'achat, numéroté localement, lot d'origine immuable ;
[ ] transfert = relocalisation d'un carnet intact, même société, idempotent, verrouillé ;
[ ] QR émis d'un carnet désigné, machine à états sans réactivation, consommation unique ;
[ ] identifiants carnet/QR publics non devinables ;
[ ] toute mutation économique : idempotence base + verrou + relecture sous verrou ;
[ ] transactions en ajout seul, portant le lot d'origine ;
[ ] total de valeur invariant hors achat/consommation ;
[ ] contrôles de sécurité (§ doctrine sécurité) appliqués à chaque opération ;
[ ] chaque INV-* couvert par au moins un test citant son ID ;
[ ] aucun anti-pattern (§7) présent.
```
