# Ressources partagées FuelToken

```text
version       : 1.0
date          : 2026-07-13
baseline      : 892a3d3af7bfe95d2cfaa84b972fbefe9bc402f9
statut        : cartographie initiale
```

## 1. Domaine économique

### `acpec.fuel.wallet`

Rôle :

- propriétaire ou conteneur économique ;
- source/destination des transferts ;
- point d'entrée d'émission QR.

Writers principaux :

- émission QR ;
- transfert carnet ;
- transfert tickets ;
- distribution portail ;
- créations/ajustements internes.

### `acpec.fuel.face.line`

Rôle :

- carnet économique ou fragment économique ;
- ressource canonique des quantités.

Invariant :

```text
qty_initial =
  qty_available
+ qty_qr_active
+ qty_qr_blocked
+ qty_consumed
+ qty_expired
+ qty_transferred_out
```

Tous les compteurs restent non négatifs.

Plusieurs QR peuvent partager la même `face_line`.

Writers principaux :

- approbation achat ;
- émission QR ;
- consommation ;
- retirer ;
- séparer ;
- transfert carnet ;
- transfert tickets ;
- distribution portail ;
- expiration cron.

### `acpec.fuel.qr`

Rôle :

- instrument de consommation ;
- état actif, bloqué, consommé ou expiré ;
- référence publique distincte du code secret.

Writers principaux :

- émission ;
- consommation ;
- retirer ;
- séparer ;
- blocage/déblocage ;
- expiration ;
- vérification pouvant rafraîchir l'état.

### `acpec.fuel.qr.line`

Rôle :

- allocation d'une quantité QR sur une `face_line`.

Risque :

```text
un QR touche plusieurs face_line
plusieurs QR touchent la même face_line
```

### `acpec.fuel.transaction`

Rôle :

- ledger économique et référence publique `operation_ref`.

Risques :

- doublon d'effet ;
- transaction absente après mutation ;
- plusieurs transactions pour la même intention ;
- visibilité partielle.

### Achats

```text
acpec.fuel.purchase
acpec.fuel.purchase.line
```

Flux :

- soumission ;
- approbation ;
- rejet ;
- création de `face_line` à l'approbation ;
- transaction unique du cycle selon la doctrine métier.

### Transferts

```text
acpec.fuel.carnet.transfer
acpec.fuel.ticket.transfer
```

Ressources :

- wallet source ;
- wallet destination ;
- `face_line` source ;
- éventuelles lignes destination ;
- transactions source/destination.

## 2. Domaine sécurité et identité

### `res.users`

Rôle :

- identité ;
- société ;
- rôles ;
- PIN et compteurs sensibles.

Writers :

- confirmation PIN ;
- reset PIN ;
- inscription ;
- approbation de compte ;
- blocage ;
- actions sensibles simultanées.

### Device

Rôle :

- identité d'appareil ;
- état pending/trusted/blocked ;
- lien avec user et sessions.

Writers :

- inscription/login ;
- approbation ;
- blocage ;
- remplacement ;
- synchronisation des sessions.

### Session

Rôle :

- access token ;
- refresh token ;
- révocation ;
- famille de rotation ;
- `last_seen_at`.

Writers :

- login ;
- refresh ;
- logout ;
- trust/block device ;
- touch best-effort.

### OTP et bucket

Rôle :

- challenge à usage unique ;
- expiration ;
- compteurs ;
- rate limiting.

Ressource externe associée :

```text
fournisseur SMS
```

## 3. Domaine technique

### Audit `SEC-*`

Trace de sécurité, distincte de l'idempotence économique.

### Marker `ERR-*`

Agrégation technique, distincte du ledger et des intentions.

### Intention mobile

Ressource locale potentielle :

- `idempotency_key` ;
- fingerprint ;
- état pending/unknown/terminal ;
- utilisateur et device.

Elle ne doit contenir aucun PIN ni code QR secret en clair.

## 4. Groupes à étudier ensemble

```text
face_line + QR + QR lines + transaction
wallets + face_line + transferts + transaction
purchase + purchase lines + face_line + transaction
user + device + session
OTP + bucket + fournisseur SMS
cron expiration + ressources économiques touchées
```
