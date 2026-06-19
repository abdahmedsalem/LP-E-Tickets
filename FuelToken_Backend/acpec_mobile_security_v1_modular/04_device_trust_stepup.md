# 04 - Device trust et step-up V1

## Portée

Ce module définit la confiance device, le risque SIM swap, le step-up V1, la validation back-office, la validation manager bornée optionnelle, et le trust client par cooldown.

Lire avec `00_decisions_invariants.md`, `01_users_roles_lifecycle.md` et `06_odoo_integration.md`.

## 4.1 Principe

OTP téléphone reste le mécanisme d'entrée, mais il ne donne pas automatiquement tous les droits à un nouveau device.

Risque :

```text
SIM swap ou interception OTP
-> attaquant reçoit OTP
-> nouveau device enrôlé
-> accès potentiel aux opérations à valeur.
```

Décision :

```text
Un nouveau device peut créer une session après OTP,
mais il ne devient pas immédiatement trusted pour les opérations sensibles.
```

## 4.2 États device

```text
new            -> device nouvellement vu.
pending_trust  -> device enrôlé par OTP, pas validé pour opérations sensibles.
trusted        -> device validé pour les opérations autorisées par les rôles du user et le canal de trust.
blocked        -> device interdit.
```

Axe orthogonal :

```text
user approval = onboarding compte.
device trust = confiance par appareil.
```

Un user `approved` qui change de téléphone garde `approved`, mais le nouveau device repart en `pending_trust`.

## 4.3 Nouveau device

Si backend détecte nouveau device pour un utilisateur :

```text
1. OTP validé.
2. Vérifier max_active_devices_per_user / max_sensitive_role_devices_per_user.
3. Si limite dépassée : refuser l'enrôlement ou exiger back-office.
4. Sinon session créée.
5. Device = pending_trust.
6. Opérations sensibles bloquées ou plafonnées.
7. Transition éventuelle vers trusted selon canal autorisé : back_office, manager_trusted ou system_cooldown.
```

## 4.4 Restrictions pending_trust

Autorisé :

```text
consultation limitée ;
profil ;
vérification session ;
opérations non sensibles.
```

Bloqué ou plafonné :

```text
consommation QR ;
transfert carnet/ticket ;
validation financière ;
changement téléphone ;
logout all ;
révocation d'autres devices ;
opération qui modifie solde, droit ou transaction.
```

## 4.5 Step-up V1

Step-up accepté en V1 :

```text
1. Validation back-office.
2. Validation manager depuis device déjà trusted, bornée par §4.7, uniquement si `manager_field_validation_enabled=True`.
3. Trust système par cooldown uniquement pour device client mobile_base_user, selon §4.8.
```

Interdit :

```text
OTP SMS comme step-up contre SIM swap ;
OTP SMS comme step-up contre nouveau device ;
OTP SMS comme step-up contre device non trusted.
```

Raison : si l'attaquant contrôle la SIM ou le nouveau device, il reçoit aussi l'OTP.

En V1, le step-up n'est pas un bypass ponctuel d'une opération sensible. Le step-up produit ou refuse le trust du device. L'opération sensible exige ensuite un device trusted compatible avec son risque.

## 4.6 Validation back-office

Le back-office est le validateur principal.

Le back-office est le seul à pouvoir :

```text
- créer un mobile user ;
- accorder ou retirer mobile_station_user ;
- accorder ou retirer mobile_manager_user ;
- valider/trust un device de manager ;
- réactiver un compte blocked ;
- agir cross-station ou cross-company ;
- lever une limite max devices ;
- convertir un trust system_cooldown en trust back_office si nécessaire.
```

Audit :

```text
validated_by
validated_at
validation_reason
previous_state
new_state
```

## 4.7 Validation manager trusted bornée

La validation manager est désactivée par défaut :

```text
manager_field_validation_enabled = False
```

Si elle est activée explicitement, un manager peut valider terrain uniquement si toutes les conditions sont vraies :

```text
- manager approved ;
- manager agit depuis un device trusted ;
- cible = agent station déjà créé par back-office ;
- cible a déjà le rôle mobile_station_user ;
- cible appartient à sa station / son périmètre société ;
- action = trust d'un device station OU activation d'un agent station déjà créé.
```

Un manager ne peut jamais :

```text
- accorder ou retirer le rôle station ;
- accorder ou retirer le rôle manager ;
- valider le device d'un autre manager ;
- créer un mobile user ;
- agir hors de son périmètre station/société ;
- modifier son propre rôle ou son propre état de confiance.
```

Conséquence V1 par défaut : un manager mobile ne peut pas approuver ni truster un device `pending_trust` tant que l'option reste `False`.

## 4.8 Trust client par cooldown système

Le trust automatique immédiat après OTP est interdit.

Pour éviter une validation back-office manuelle de chaque changement de device client, la V1 autorise un canal limité :

```text
validation_channel = system_cooldown
trusted_by = system
```

Conditions obligatoires :

```text
- user approved ;
- rôle = mobile_base_user uniquement ;
- aucun rôle mobile_station_user ;
- aucun rôle mobile_manager_user ;
- device pending_trust ;
- client_device_cooldown_enabled = True ;
- délai client_device_cooldown_hours écoulé depuis l'enrôlement ;
- aucune alerte suspecte sur la session/device ;
- limites max_active_devices_per_user respectées.
```

Effet :

```text
Le device devient trusted avec trust_scope = low_value_only.
```

Règle de sécurité :

```text
system_cooldown ne protège pas contre un attaquant patient après SIM swap.
Donc le plafond haute valeur reste actif : opérations haute valeur, transferts sensibles,
changement téléphone, logout all et révocation d'autres devices exigent trust back-office.
```

Interdits :

```text
system_cooldown pour agent station ;
system_cooldown pour manager ;
system_cooldown pour consommation QR station ;
system_cooldown comme autorisation haute valeur.
```

## 4.9 Règles FuelToken

### Client mobile

```text
Nouveau device client
-> pending_trust ;
-> consultation limitée et opérations non sensibles ;
-> après cooldown configuré : trusted via system_cooldown, scope low_value_only ;
-> opérations haute valeur restent bloquées jusqu'à validation back-office.
```

### Agent station

```text
Création compte par back-office
-> mobile_station_user + affectation station
-> OTP -> PIN
-> device pending_trust
-> consommation QR bloquée
-> validation back-office
-> OU manager trusted borné uniquement si manager_field_validation_enabled=True
-> device trusted
-> consommation QR autorisée selon règles métier
```

Aucun cooldown système ne peut rendre trusted un device station.

### Manager mobile

```text
Création compte par back-office uniquement
-> mobile_manager_user
-> OTP -> PIN
-> device pending_trust
-> validations critiques bloquées
-> validation back-office uniquement
-> device trusted
```

Aucun cooldown système et aucun autre manager ne peut rendre trusted un device manager.

## 4.10 Enforcement unique opérations sensibles

Toute opération sensible passe par un helper unique. Vérifications à la main dans chaque endpoint interdites.

```python
def _require_trusted_sensitive(user, device, required_role, operation_risk='normal'):
    self._require_mobile_auth()            # session + access token valides
    assert user.acpec_mobile_state == 'approved'
    assert device.device_trust_state == 'trusted'
    self._require_mobile_group(user, required_role)

    if device.validation_channel == 'system_cooldown':
        assert required_role == 'mobile_base_user'
        assert operation_risk == 'low_value'
        assert device.trust_scope == 'low_value_only'

    # société / station / affectation / record rules / idempotence
    # restent vérifiées par l'opération métier.
```

Aucun endpoint sensible ne vérifie ces axes en piecemeal.

## 4.11 Audit transition device trust

Champs obligatoires :

```text
trusted_by              # user back-office/manager, ou literal 'system'
trusted_at
old_trust_state
new_trust_state
validation_channel = back_office | manager_trusted | system_cooldown
trust_scope = full | low_value_only
reason
```

Pour `system_cooldown`, `trusted_by='system'`, `validation_channel='system_cooldown'` et `trust_scope='low_value_only'` sont obligatoires.

## 4.12 Limite du nombre de devices

Définitions :

```text
active device = pending_trust ou trusted.
blocked/revoked device = non actif.
```

Politique V1 :

```text
Si un nouvel enrôlement dépasse max_active_devices_per_user :
-> ne pas auto-truster ;
-> refuser l'enrôlement ou demander intervention back-office ;
-> journaliser device_limit_reached.

Si l'utilisateur a un rôle sensible station/manager et dépasse max_sensitive_role_devices_per_user :
-> validation back-office obligatoire ;
-> aucune validation manager ;
-> aucun system_cooldown.
```

## 4.13 Tests minimum

```text
- nouveau device -> pending_trust ;
- pending_trust bloque consommation QR ;
- client base pending_trust -> trusted via system_cooldown seulement après cooldown ;
- system_cooldown crée trusted_by='system', validation_channel='system_cooldown', trust_scope='low_value_only' ;
- system_cooldown refuse station/manager ;
- system_cooldown refuse opération haute valeur ;
- trusted device autorise selon rôle et trust_scope ;
- blocked device refuse session ;
- manager pending_trust ne peut rien valider ;
- manager trusted ne peut pas accorder rôle station ;
- manager trusted ne peut pas valider autre manager ;
- manager trusted ne peut valider aucun device si manager_field_validation_enabled=False ;
- manager trusted ne peut pas agir hors périmètre ;
- back-office peut trust manager ;
- rôle attribué != device trusted ;
- blocage device révoque sessions ;
- dépassement max_active_devices_per_user bloque nouvel enrôlement ou impose back-office.
```
