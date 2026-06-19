# 09 - Spec exécutable, POC et tests

## Portée

Ce module transforme la doctrine en contrôles exécutables : tables d'états, matrice d'autorisation, threat model, POC bloquants, mapping règle -> helper/contrainte/test, et critères de release.

Lire avec `00_decisions_invariants.md`.

Règle de priorité : ce fichier ne crée pas une doctrine parallèle. En cas de doute, `00_decisions_invariants.md` gagne, puis le module spécialisé concerné.

## 9.0 Convention d'exécution

### Gravité

```text
P0 bloquant : fail = patch non mergeable / non livrable.
P1 majeur   : fail = patch mergeable seulement si contournement documenté et ticket ouvert.
P2 mineur   : fail = correction planifiée, pas de contournement sécurité.
```

### Format minimal d'un test exécutable

Chaque test ou POC doit expliciter :

```text
- ID stable ;
- module(s) lus ;
- préconditions / fixtures ;
- action ;
- assertions positives ;
- assertions négatives ;
- critère d'échec bloquant ;
- audit attendu si applicable.
```

### Nommage recommandé

```text
T09-USER-*      utilisateurs, portail, credentials web
T09-ROLE-*      rôles mobiles et attribution
T09-DEVICE-*    device trust, step-up, cooldown, max devices
T09-SESSION-*   access/refresh/session
T09-OTP-*       OTP et relance normale
T09-ODOO-*      ACL/rules, with_user, sudo métier
T09-IDEMP-*     idempotence, QR/ticket, concurrence
T09-CONFIG-*    DEV/PROD, HTTPS, flags, logs
```

### Échec bloquant global

Tout test est bloquant si l'un des événements suivants se produit :

```text
- mobile user obtient base.group_user, base.group_public ou groupe admin back-office ;
- mobile_only possède un credential web exploitable ;
- OTP accorde un rôle sensible ou rend automatiquement trusted un device station/manager ;
- manager terrain accorde ou retire un rôle mobile ;
- manager trusted valide un device alors que manager_field_validation_enabled=False ;
- system_cooldown s'applique à station/manager ou à une opération haute valeur ;
- opération sensible passe sans helper unique d'autorisation ;
- QR/ticket consommé deux fois ;
- idempotency_key réutilisée avec payload différent sans idempotency_conflict ;
- refresh previous hors fenêtre ne révoque pas la session ;
- blocage user/device laisse des refresh hashes utilisables ;
- log contient OTP, PIN, access token, refresh token ou secret.
```

## 9.1 Tables de transition d'états

### Mobile user state

| Test ID | État actuel | Événement | Résultat attendu | Invariants couverts |
|---|---|---|---|---|
| T09-USER-001 | pending | validation back-office | approved | INV-SENSITIVE-001 |
| T09-USER-002 | pending | blocage | blocked | INV-USER-006 |
| T09-USER-003 | pending | OTP réussi | session possible, opérations sensibles bloquées | INV-ROLE-001, INV-SENSITIVE-001 |
| T09-USER-004 | approved | blocage | blocked + révocation sessions + effacement refresh hashes | INV-USER-006, INV-REFRESH-004 |
| T09-USER-005 | approved | retrait validation | pending + sessions sensibles réévaluées ou révoquées | INV-SENSITIVE-001 |
| T09-USER-006 | approved | OTP réussi | session possible selon device | DEC-AUTH-002 |
| T09-USER-007 | blocked | OTP réussi | refusé | INV-USER-006 |
| T09-USER-008 | blocked | refresh | refusé | INV-USER-006, INV-REFRESH-004 |
| T09-USER-009 | blocked | réactivation back-office | pending ou approved selon action back-office auditée | INV-ROLE-005 |

### Device trust state

| Test ID | État actuel | Événement | Résultat attendu | Invariants couverts |
|---|---|---|---|---|
| T09-DEVICE-001 | new | OTP réussi et limite devices OK | pending_trust | INV-DEVICE-001 |
| T09-DEVICE-002 | new | OTP réussi mais max_active_devices atteint | refusé ou back-office requis ; jamais auto-trusted | INV-DEVICE-008 |
| T09-DEVICE-003 | new | blocage | blocked | INV-DEVICE-002 |
| T09-DEVICE-004 | pending_trust | validation back-office | trusted, validation_channel=back_office, trust_scope=full, trusted_by/trusted_at renseignés | INV-DEVICE-004 |
| T09-DEVICE-005 | pending_trust | validation manager trusted avec manager_field_validation_enabled=False | refusé | DEC-STEPUP-003, FORBID-009 |
| T09-DEVICE-006 | pending_trust | validation manager trusted avec manager_field_validation_enabled=True | trusted seulement si agent station déjà créé, rôle station déjà attribué et périmètre OK | INV-DEVICE-005, INV-ROLE-006 |
| T09-DEVICE-007 | pending_trust | cooldown client écoulé + mobile_base_user uniquement + limites OK | trusted, validation_channel=system_cooldown, trusted_by=system, trust_scope=low_value_only | INV-DEVICE-004, INV-DEVICE-006 |
| T09-DEVICE-008 | pending_trust | cooldown écoulé mais rôle station/manager | refusé, reste pending_trust | DEC-DEVICE-004, FORBID-012 |
| T09-DEVICE-009 | pending_trust | consommation QR | refusé | INV-DEVICE-003 |
| T09-DEVICE-010 | pending_trust | opération client haute valeur | refusé ou back-office requis | INV-DEVICE-007 |
| T09-DEVICE-011 | pending_trust | blocage | blocked + révocation sessions device + effacement refresh hashes | INV-DEVICE-002, INV-REFRESH-004 |
| T09-DEVICE-012 | trusted | blocage | blocked + révocation sessions device + effacement refresh hashes | INV-DEVICE-002, INV-REFRESH-004 |
| T09-DEVICE-013 | trusted | retrait trust | pending_trust + sessions réévaluées ou révoquées | INV-SENSITIVE-002 |
| T09-DEVICE-014 | trusted | OTP réussi même device | reste trusted | DEC-AUTH-002 |
| T09-DEVICE-015 | trusted system_cooldown | opération haute valeur | refusé ou back-office requis | INV-DEVICE-007, FORBID-013 |
| T09-DEVICE-016 | blocked | OTP réussi | refusé | INV-DEVICE-002 |
| T09-DEVICE-017 | blocked | validation manager | refusé | INV-DEVICE-002 |
| T09-DEVICE-018 | blocked | réactivation back-office | pending_trust, jamais trusted automatique | INV-DEVICE-001 |

### Session state

| Test ID | État actuel | Événement | Résultat attendu | Invariants couverts |
|---|---|---|---|---|
| T09-SESSION-001 | active | access expiré | refresh requis | DEC-AUTH-003 |
| T09-SESSION-002 | active | refresh current valide | active + nouvelle paire access/refresh | DEC-REFRESH-001 |
| T09-SESSION-003 | active | refresh previous dans grâce | active + nouvelle paire ; previous_refresh_valid_until non prolongé | INV-REFRESH-002 |
| T09-SESSION-004 | active | refresh previous hors grâce | revoked, reason=refresh_reuse_out_of_grace | INV-REFRESH-003 |
| T09-SESSION-005 | active | logout volontaire | revoked | DEC-AUTH-003 |
| T09-SESSION-006 | active | blocage user/device | revoked + hashes current/previous effacés | INV-REFRESH-004 |
| T09-SESSION-007 | expired | refresh valide | active si refresh non expiré | DEC-REFRESH-001 |
| T09-SESSION-008 | revoked | /me | refusé | INV-USER-006 |
| T09-SESSION-009 | revoked | refresh | refusé | INV-REFRESH-004 |
| T09-SESSION-010 | blocked | toute requête | refusé | INV-USER-006, INV-DEVICE-002 |

### OTP state

| Test ID | État actuel | Événement | Résultat attendu | Invariants couverts |
|---|---|---|---|---|
| T09-OTP-001 | pending | verify correct avant expiration | consumed + session serveur créée/restaurée | DEC-AUTH-002 |
| T09-OTP-002 | pending | verify faux | attempts +1 ou blocked selon seuil | DEC-AUTH-002 |
| T09-OTP-003 | pending | expiration | expired | DEC-AUTH-002 |
| T09-OTP-004 | pending | trop tentatives | blocked | DEC-AUTH-002 |
| T09-OTP-005 | consumed | verify | refusé | DEC-AUTH-002 |
| T09-OTP-006 | expired | verify | refusé | DEC-AUTH-002 |
| T09-OTP-007 | blocked | verify | refusé | INV-USER-006 |
| T09-OTP-008 | pending | verify correct nouveau device station/manager | session possible + device pending_trust ; jamais trusted automatique | INV-DEVICE-001, FORBID-007 |

## 9.2 Matrice d'autorisation minimale

| Test ID | Rôle | User state | Device state / canal | Contexte | Opération | Résultat attendu |
|---|---|---|---|---|---|---|
| T09-AUTHZ-001 | mobile_base_user | approved | trusted back_office | n/a | consultation profil | autorisé |
| T09-AUTHZ-002 | mobile_base_user | approved | trusted system_cooldown low_value_only | n/a | opération client basse valeur | autorisé si plafond OK |
| T09-AUTHZ-003 | mobile_base_user | approved | trusted system_cooldown low_value_only | n/a | opération haute valeur | refusé / back-office requis |
| T09-AUTHZ-004 | mobile_base_user | pending | trusted | n/a | opération sensible | refusé |
| T09-AUTHZ-005 | mobile_base_user | approved | pending_trust | n/a | transfert valeur | plafonné/refusé selon risque ; haute valeur refusée |
| T09-AUTHZ-006 | mobile_base_user | approved | trusted | n/a | consommation QR station | refusé |
| T09-AUTHZ-007 | mobile_station_user | approved | pending_trust | affectation active | consommation QR | refusé validation requise |
| T09-AUTHZ-008 | mobile_station_user | approved | trusted back_office/manager_trusted | affectation active | consommation QR | autorisé si règles métier OK |
| T09-AUTHZ-009 | mobile_station_user | approved | trusted system_cooldown | affectation active | consommation QR | impossible/refusé, system_cooldown interdit station |
| T09-AUTHZ-010 | mobile_station_user | approved | trusted | hors station | consommation QR | refusé |
| T09-AUTHZ-011 | mobile_manager_user | approved | pending_trust | périmètre OK | validation agent | refusé |
| T09-AUTHZ-012 | mobile_manager_user | approved | trusted | périmètre OK | trust device agent station | refusé par défaut si manager_field_validation_enabled=False ; autorisé seulement si True et périmètre OK |
| T09-AUTHZ-013 | mobile_manager_user | approved | trusted | périmètre OK | accorder rôle station | refusé, back-office uniquement |
| T09-AUTHZ-014 | mobile_manager_user | approved | trusted | périmètre OK | retirer rôle station | refusé, back-office uniquement |
| T09-AUTHZ-015 | mobile_manager_user | approved | trusted | autre manager | trust device manager | refusé |
| T09-AUTHZ-016 | mobile_manager_user | approved | trusted | hors périmètre | validation agent | refusé |
| T09-AUTHZ-017 | tout rôle | blocked | tout état | n/a | toute opération | refusé |
| T09-AUTHZ-018 | tout rôle | approved | blocked | n/a | toute opération | refusé |
| T09-AUTHZ-019 | tout rôle | approved | max devices atteint | nouvel appareil | enrôlement | refusé ou back-office requis ; jamais auto-trusted |
| T09-AUTHZ-020 | portal standard non mobile | n/a | n/a | n/a | endpoint mobile | refusé |
| T09-AUTHZ-021 | back-office user interne | n/a | n/a | n/a | endpoint mobile | refusé sauf endpoint explicitement back-office |

## 9.3 Threat model léger

| Test ID | Actif | Menace | Contrôle | Test exécutable |
|---|---|---|---|---|
| T09-THREAT-001 | Numéro téléphone / OTP | SIM swap | Nouveau device pending_trust + validation BO par défaut ; manager trusted seulement si option activée ; pas SMS step-up | new_device_consume_refused |
| T09-THREAT-002 | Device client | SIM swap patient | system_cooldown seulement low_value_only ; haute valeur exige back-office | system_cooldown_high_value_refused |
| T09-THREAT-003 | Refresh token | Réponse réseau perdue | Fenêtre de grâce courte | refresh_lost_response_retry_ok |
| T09-THREAT-004 | Refresh token | Rejeu hors fenêtre | Révocation session | refresh_reuse_out_of_grace_revokes |
| T09-THREAT-005 | Mobile user portal-type | Fuite via ACL portal | Audit portal grants + checks mobiles explicites | portal_rules_scope_poc |
| T09-THREAT-006 | Device trust | Manager compromis | Validation manager bornée, pas cross-company/station, pas manager->manager, pas attribution rôle | manager_scope_refused |
| T09-THREAT-007 | QR/ticket | Double consommation même appel | Idempotency key + response replay | idempotent_retry_same_result |
| T09-THREAT-008 | QR/ticket | Double consommation avec clés différentes | Verrouillage objet / unique(ticket_id) | concurrent_consume_only_once |
| T09-THREAT-009 | Rôle station | SIM swap agent | Rôle attribué != device trusted ; system_cooldown interdit station | station_role_pending_device_refused |
| T09-THREAT-010 | Max devices | Fraude / prolifération devices | max_active_devices_per_user + back-office pour dépassement | max_devices_enrollment_refused |
| T09-THREAT-011 | Logs | fuite tokens/OTP | Masquage systématique | log_secret_scan |
| T09-THREAT-012 | Portail Odoo standard | signup non contrôlé | signup portail standard refusé pour mobile_only | portal_signup_mobile_refused |

## 9.4 POC bloquants ordonnés avant refonte complète

### POC 1 - mobile user portal-type sans credential web

Modules à lire : `00`, `01`, `02`, `08`, `09`.

Préconditions :

```text
- un mobile user de test existe ou est créé par back-office/endpoint contrôlé ;
- un portal user standard non mobile existe ;
- un back-office user interne existe.
```

Actions :

```text
1. Inspecter groupes et champs du mobile user.
2. Tenter login web / reset password / signup / API key / passkey si disponible.
3. Tenter request-otp avec téléphone, puis avec email ou identifiant contenant @.
4. Tenter endpoint mobile avec portal user standard et back-office user interne.
```

Assertions :

```text
- base.group_portal présent ;
- acpec_mobile_auth.group_mobile_auth_user présent ;
- acpec_mobile_enabled=True ;
- acpec_mobile_only=True ;
- base.group_user absent ;
- base.group_public absent ;
- groupe admin back-office absent ;
- `password=False` ou absence vérifiable de mot de passe web utilisable ;
- reset password / signup portail / API key / passkey / TOTP web refusés ou inutilisables pour `mobile_only` ;
- email / identifiant avec @ refusé côté backend ;
- portal user standard non mobile refusé par endpoint mobile ;
- back-office user interne refusé par endpoint mobile sauf endpoint explicitement back-office.
```

Critère d'échec P0 :

```text
Tout mobile_only capable d'ouvrir une session web, de créer/utiliser un credential web, ou portant base.group_user/base.group_public/admin est bloquant.
```

### POC 2 - audit ACL/rules portal + `with_user(mobile_user)`

Modules à lire : `00`, `01`, `04`, `06`, `07`, `09`.

Préconditions :

```text
- mobile user station approved ;
- device station trusted via back_office ou manager_trusted autorisé ;
- station active ;
- affectation station-agent active ;
- QR/ticket actif ;
- au moins un enregistrement hors périmètre station/société.
```

Actions :

```text
1. Lister groupes directs et implied du mobile user réel.
2. Lister groupes implied par base.group_portal.
3. Lister ACL et record rules du mobile user réel et de base.group_portal.
4. Exécuter les opérations de lecture/écriture critiques en with_user(mobile_user).
5. Exécuter la consommation QR station en with_user(mobile_user).
6. Rejouer les mêmes accès hors station/société.
7. Documenter tout sudo métier nécessaire.
```

Assertions :

```text
- pas d'AccessError inattendu sur l'opération autorisée ;
- pas de fuite record rules hors périmètre ;
- `base.group_portal` présent mais jamais suffisant seul pour une action mobile ;
- create_uid/write_uid cohérents si with_user est utilisé ;
- operator_user_id, mobile_session_id, device_uid, station_id, company_id renseignés ;
- sudo métier absent ou justifié avec audit explicite ;
- idempotency_key obligatoire pour consommation QR.
```

Critère d'échec P0 :

```text
Une opération sensible autorisée uniquement par base.group_portal, ou un sudo métier sans audit, bloque le patch.
```


### Résultats POC terrain 2026-06-19 à intégrer au gate

Constats issus de la base `fueltoken` Odoo 19 :

```text
- `res.users` Odoo 19 expose les groupes via `group_ids` dans cet environnement.
- User test `32342005 / Khira` : share=True, non interne, group_mobile_auth_user=True.
- Non-conformité initiale observée : base.group_portal absent sur ce user test.
- `group_fuel_station` est présent et ses ACL observées sont principalement lecture seule sur station/transaction.
- Les record rules station utilisent encore le legacy `station.user_id`, pas encore `station.agent`.
- `base.group_portal` apporte des ACL/rules larges : sale.order, account.move, account.move.line, res.users, API keys, passkeys, TOTP, payment.token, mail/discuss, et objets FuelToken portail société.
- Conclusion : corriger le baseline pour rendre `base.group_portal` obligatoire, mais bloquer les credentials web et ne jamais autoriser une action mobile par le portail seul.
```

### POC 3 - lifecycle user/device

Modules à lire : `00`, `01`, `03`, `04`, `08`, `09`.

Préconditions :

```text
- un user client mobile_base_user ;
- un user station mobile_station_user ;
- un user manager mobile_manager_user ;
- devices new/pending_trust/trusted/blocked ;
- manager_field_validation_enabled=False par défaut.
```

Actions :

```text
1. Enrôler un nouveau device client, station et manager après OTP.
2. Vérifier pending_trust initial.
3. Tenter opérations sensibles avant trust.
4. Valider/truster par back-office.
5. Tenter validation manager avec option False.
6. Activer option True dans un test isolé et tenter uniquement device station dans périmètre.
7. Bloquer user puis device.
8. Tester max_active_devices_per_user et max_sensitive_role_devices_per_user.
```

Assertions :

```text
- nouveau device => pending_trust ;
- rôle sensible attribué != device trusted ;
- station/manager jamais trusted par system_cooldown ;
- manager_field_validation_enabled=False bloque toute validation manager ;
- si True, manager ne valide que device station dans son périmètre ;
- manager ne crée pas user et n'accorde/retire aucun rôle ;
- blocage user/device révoque sessions et efface hashes refresh current/previous ;
- dépassement max devices refuse enrôlement ou exige back-office ; jamais auto-trusted.
```

Critère d'échec P0 :

```text
Un device station/manager trusted automatiquement après OTP ou cooldown système est bloquant.
```

### POC 4 - refresh grace window

Modules à lire : `00`, `02`, `03`, `08`, `09`.

Préconditions :

```text
- session mobile active ;
- access token expiré ou proche expiration ;
- refresh_grace_seconds entre 30 et 60 ;
- previous_refresh_retry_count limité.
```

Actions :

```text
1. Appeler /refresh avec current refresh valide.
2. Simuler réponse perdue côté client.
3. Rejouer /refresh avec l'ancien refresh token pendant la fenêtre de grâce.
4. Vérifier génération d'une nouvelle paire.
5. Vérifier que previous_refresh_valid_until n'est pas prolongé.
6. Rejouer hors fenêtre de grâce.
7. Bloquer user/device et tenter refresh.
```

Assertions :

```text
- refresh current valide remplace current par un nouveau hash ;
- ancien current devient previous avec valid_until fixe ;
- retry dans la fenêtre accepté et génère une nouvelle paire ;
- retry dans la fenêtre incrémente previous_refresh_retry_count ;
- valid_until non prolongé par retry ;
- retry hors fenêtre révoque la session ;
- user/device blocked efface current_refresh_token_hash et previous_refresh_token_hash ;
- aucun token clair en log.
```

Critère d'échec P0 :

```text
Toute prolongation de previous_refresh_valid_until par retry, ou toute session bloquée ressuscitée par refresh, bloque le patch.
```

### POC 5 - idempotence + double consommation QR/ticket

Modules à lire : `00`, `04`, `06`, `07`, `09`.

Préconditions :

```text
- agent station approved ;
- device trusted full ;
- affectation station active ;
- QR/ticket actif ;
- contrainte unique d'idempotence en base ;
- verrouillage objet ou unique(ticket_id) côté consommation.
```

Actions :

```text
1. Consommer QR avec idempotency_key K et payload P.
2. Rejouer K avec payload P.
3. Rejouer K avec payload P différent.
4. Lancer deux consommations concurrentes avec deux clés différentes visant le même ticket.
5. Tenter consommation d'un ticket déjà consommé.
6. Inspecter safe_response_json et logs.
```

Assertions :

```text
- même K + même request_hash => même résultat mémorisé ;
- même K + request_hash différent => idempotency_conflict ;
- deux clés différentes sur même ticket => une seule consommation métier ;
- ticket consommé = état terminal ;
- mobile_session_id/device_uid exclus de la clé unique ;
- mobile_session_id/device_uid conservés en audit ;
- safe_response_json ne contient pas OTP/PIN/tokens/secrets ;
- create_uid/operator_user_id/station_id/company_id cohérents.
```

Critère d'échec P0 :

```text
Toute double consommation effective du même QR/ticket bloque le patch.
```

### POC 6 - trust client `system_cooldown` low_value_only

Modules à lire : `00`, `04`, `08`, `09`.

Préconditions :

```text
- client mobile_base_user approved ;
- aucun rôle station/manager ;
- device pending_trust ;
- client_device_cooldown_enabled=True ;
- client_system_cooldown_trust_scope=low_value_only ;
- client_system_cooldown_allows_high_value=False.
```

Actions :

```text
1. Tenter trust avant cooldown.
2. Avancer/simuler délai client_device_cooldown_hours.
3. Appliquer transition system_cooldown.
4. Tenter opération basse valeur.
5. Tenter opération haute valeur.
6. Rejouer scénario avec user station puis manager.
```

Assertions :

```text
- avant cooldown : reste pending_trust ;
- après cooldown : trusted_by=system, validation_channel=system_cooldown, trust_scope=low_value_only ;
- opération basse valeur autorisée seulement si plafond OK ;
- opération haute valeur refusée/back-office requis ;
- station/manager refusés, sans transition trusted.
```

Critère d'échec P0 :

```text
system_cooldown qui autorise haute valeur, consommation QR station, station ou manager bloque le patch.
```

### POC 7 - config DEV/PROD et scan logs

Modules à lire : `00`, `02`, `03`, `08`, `09`.

Préconditions :

```text
- configuration DEV explicite ;
- configuration PROD/release ;
- flux OTP, refresh, consommation QR exécutés au moins une fois.
```

Actions :

```text
1. Vérifier HTTP autorisé seulement en DEV local explicite.
2. Vérifier HTTP refusé en PROD/release.
3. Vérifier OTP fixe uniquement côté backend DEV.
4. Scanner logs après request-otp, verify-otp, refresh et consommation QR.
5. Vérifier que les flags obsolètes new_device_requires_* ne pilotent aucune décision V1.
```

Assertions :

```text
- HTTPS obligatoire en PROD/release ;
- ACPEC_ALLOW_INSECURE_HTTP ou équivalent impossible en release ;
- OTP fixe DEV impossible en PROD ;
- logs masquent OTP/PIN/access/refresh/secrets/QR sensible complet ;
- acpec.mobile.security.config est la source principale des politiques ;
- ir.config_parameter ne devient pas source principale de sécurité mobile.
```

Critère d'échec P0 :

```text
Un secret en log ou HTTP accepté en release/prod bloque le patch.
```

## 9.5 Mapping règle -> helper / contrainte / test

| Règle | Implémentation attendue | Test/POC minimum |
|---|---|---|
| INV-USER-001 à INV-USER-005 | contrainte `res.users` mobile_only + helper de création mobile | POC 1, T09-USER-* |
| INV-USER-006 | révocation sessions user blocked + refus auth | POC 3, T09-USER-004, T09-USER-007, T09-USER-008 |
| INV-ROLE-001 à INV-ROLE-004 | attribution rôles back-office uniquement + OTP sans effet rôle | POC 1, POC 3 |
| INV-ROLE-005 | audit changement de rôle | POC 3 |
| INV-ROLE-006 à INV-ROLE-007 | action manager sans grant/revoke rôle | POC 3, T09-AUTHZ-013, T09-AUTHZ-014 |
| INV-DEVICE-001 à INV-DEVICE-008 | modèle device + transition unique de trust | POC 3, POC 6 |
| INV-PIN-001 à INV-PIN-002 | PIN local frontend + confirmation locale, sans bypass backend | tests module 05 + POC 3 |
| INV-SENSITIVE-001 à INV-SENSITIVE-004 | helper unique `_require_trusted_sensitive` ou équivalent | POC 2, POC 3, POC 5 |
| INV-REFRESH-001 à INV-REFRESH-004 | `/refresh` avec verrou session, hash current/previous, grâce fixe | POC 4 |
| INV-IDEMP-001 à INV-IDEMP-005 | contrainte SQL idempotence + request_hash + verrou objet/unique(ticket_id) | POC 5 |
| INV-ODOO-001 à INV-ODOO-003 | audit portal grants + checks mobiles explicites + helper sensible | POC 2 |
| DEC-ENV-001, DEC-LOG-001 | gates DEV/PROD + masquage logs | POC 7 |

## 9.6 Tests obligatoires par module

Cette section sert de checklist de release. Les tests détaillés restent dans chaque module, mais chaque ligne ci-dessous doit avoir au moins un test automatisé ou un POC documenté.

| Module | Tests minimaux obligatoires |
|---|---|
| 01 users / roles / lifecycle | mobile_only portal-type ; credential web inutilisable ; groupes interdits refusés ; rôles sensibles back-office only ; audit rôle ; signup portail standard refusé |
| 02 auth / OTP | téléphone-only ; email/@ refusé ; request-otp non énumérant ; OTP expiré/consommé/faux refusé ; relance normale PIN/refresh ; erreur réseau ne logout pas |
| 03 sessions / refresh | rotation ; retry en grâce ; non-prolongation grâce ; hors grâce révoque ; blocage user/device efface hashes |
| 04 device / step-up | new->pending_trust ; station/manager pas auto-trusted ; manager False bloque ; manager True borné ; system_cooldown low_value_only client ; max devices |
| 05 PIN / auto-lock | PIN local requis ; PIN correct ne bypass pas serveur ; confirmation action sensible ; auto-lock ; wipe/lockout local selon politique |
| 06 Odoo / station | audit ACL portal ; endpoint refuse portal standard ; with_user POC ; station/affectation/company ; sudo métier audité |
| 07 idempotence | contrainte unique ; request_hash conflict ; concurrence même clé ; concurrence clés différentes ; ticket terminal ; safe_response_json sans secret |
| 08 config / logs | HTTPS PROD ; HTTP DEV explicite ; OTP fixe DEV only ; source config dédiée ; flags obsolètes ignorés ; scan logs secrets |

## 9.7 Règle de release

```text
Aucun patch d'auth mobile ne passe en production sans :
- 00 respecté ;
- module concerné lu ;
- POC bloquant applicable passé ;
- tests anti-régression ajoutés ;
- résultat P0 = 0 ;
- décision sudo métier documentée si with_user échoue ;
- scan logs secrets passé.
```

Pour un patch local de POC non production, le merge en branche expérimentale peut être accepté avec P0 connu seulement si :

```text
- le P0 est précisément le comportement que le POC cherche à exposer ;
- le P0 est isolé hors main/prod ;
- aucune livraison release n'est faite avant correction.
```

## 9.8 Tests de cohérence inter-modules

```text
- INV-SENSITIVE-002 cohérent avec helper _require_trusted_sensitive ;
- validation_channel enum cohérent entre 04, 08 et 09 ;
- trust_scope enum cohérent entre 04, 08 et 09 ;
- manager ne peut accorder ni retirer aucun rôle dans 00, 01, 04, 09 ;
- system_cooldown existe en config, audit, table d'état et matrice ;
- system_cooldown est limité mobile_base_user + low_value_only ;
- max_active_devices_per_user a une politique et un test ;
- max_sensitive_role_devices_per_user a une politique et un test ;
- aucun flag obsolète new_device_requires_* n'est utilisé comme source de vérité ;
- device_uid et mobile_session_id sont audit, jamais preuve cryptographique ni clé unique idempotence ;
- ADR ne contredit pas 00 ni les modules actifs.
```

## 9.9 Intégrité des artefacts

```text
- README référence tous les modules actifs ;
- AGENTS impose 00 + module concerné ;
- ADR ne remplace jamais la spec active ;
- manifest.json liste tous les modules actifs ;
- décisions ouvertes absentes ou explicitement clôturées ;
- CHANGELOG résume toute modification normative ;
- aucun nouveau document monolithique parallèle n'est créé.
```

## 9.10 Décisions clôturées à tester

```text
OPEN-CLIENT-001 clôturé : volume cible clients mobiles <= 5000.
Test : provisioning client par back-office ou endpoint contrôlé ; signup portail standard refusé.

OPEN-MANAGER-001 clôturé : manager_field_validation_enabled=False par défaut.
Test : manager trusted ne peut pas truster un device pending lorsque l'option est False.
Test optionnel : si True, manager trusted ne peut valider que device station dans son périmètre et ne peut accorder aucun rôle.

COH-DEVICE-001 clôturé : system_cooldown client low_value_only.
Test : device client base peut devenir trusted low_value_only après cooldown ; haute valeur refusée ; station/manager refusés.

COH-ROLE-001 clôturé : manager ne peut jamais accorder ni retirer aucun rôle mobile.
Test : toute tentative manager d'ajout/retrait mobile_station_user ou mobile_manager_user est refusée et auditée.
```
