# ACPEC Mobile Security V1 - Source modulaire

Ce dossier est la source active de la doctrine/specification **ACPEC Mobile Security V1**.

Il remplace le monolithe initial et l'additif comme sources opérationnelles. Le monolithe et l'additif restent des historiques de discussion, mais le développement doit partir de ces fichiers modulaires.

## Règle de consommation par IA / agent de dev

Toujours charger :

```text
00_decisions_invariants.md
```

Puis charger uniquement le ou les modules liés à la tâche.

Ne jamais charger tout le dossier sans raison. Ne jamais coder à partir d'un ancien additif si la règle a été intégrée dans un module.

## Index des modules actifs

| Fichier | Quand le charger | Contenu |
|---|---|---|
| `00_decisions_invariants.md` | Toujours | Décisions finales, invariants, interdits absolus, garde-fous anti-régression |
| `01_users_roles_lifecycle.md` | Création compte, rôles, portail, onboarding | Typologie users, mobile user portal-type, hardening, rôles, cycle de vie user, règles de validation de rôle |
| `02_auth_protocol_otp.md` | Login, OTP, relance app, erreur réseau | Téléphone-only, OTP, workflows d'authentification, réponse non énumérante |
| `03_sessions_tokens.md` | Session, access/refresh, rotation | Session mobile, tokens, rotation refresh avec fenêtre de grâce |
| `04_device_trust_stepup.md` | Nouveau device, SIM swap, step-up | États device, pending_trust, trusted, validation back-office par défaut, manager trusted optionnel, system_cooldown client, révocation |
| `05_pin_autolock.md` | PIN, lock local, biométrie | PIN local, confirmation action sensible, auto-lock |
| `06_odoo_integration.md` | ORM, ACL, station | `with_user`, `sudo`, risque portal grants, station/agent/transaction |
| `07_idempotency.md` | QR, double scan, retry client | Idempotency key, request_hash, verrouillage objet, double-spend |
| `08_config_dev_prod.md` | Environnements, config sécurité | Table config dédiée, options DEV/PROD, HTTPS, logs/secrets |
| `09_tests_poc.md` | Avant patch ou revue | POC bloquants, tables de transition, matrice d'autorisation, threat model, tests minimum |
| `10_backend_runtime_hardening_17A_21A.md` | Après patches backend | État runtime réellement implémenté : mobile-only, web fermé, refresh, device trust, PIN serveur |
| `11_flutter_security_contract_17A_21A.md` | Intégration Flutter | Contrat frontend : action_code, device_trust_state, erreurs, endpoints sensibles |

## ADR historiques

Les fichiers `adr/ADR-*.md` expliquent pourquoi certaines décisions ont été prises. Ils ne remplacent pas les modules actifs.

## Ordre recommandé avant développement

1. Lire `00_decisions_invariants.md`.
2. Lire le module concerné.
3. Vérifier `09_tests_poc.md` pour les POC/tests associés.
4. Coder un POC si la règle touche : portal-type user, `with_user`, refresh grace, idempotence concurrente, nouveau device.
5. Ne fusionner qu'après tests anti-régression.

## Décisions ouvertes

Les décisions ouvertes sont explicitement marquées `OPEN-*`. Elles ne doivent pas être devinées par l'agent de dev.

## Décisions ouvertes clôturées

```text
OPEN-CLIENT-001 : clients mobiles V1 <= 5000 ; res.users par client accepté ; pas de signup portail standard.
OPEN-MANAGER-001 : manager_field_validation_enabled=False par défaut ; validation manager trusted désactivée sauf activation explicite.
COH-DEVICE-001 : client device peut devenir trusted via system_cooldown après cooldown, scope low_value_only ; haute valeur reste back-office.
COH-ROLE-001 : manager ne peut jamais accorder ni retirer aucun rôle mobile, y compris station.
```


## État backend exécuté au 2026-06-19

Les patches 17A à 21A ont été appliqués dans le dépôt FuelToken : mobile-only portal baseline, fermeture web, rotation refresh avec grâce, device trust back-office, gate actions sensibles et PIN serveur. Charger aussi `10_backend_runtime_hardening_17A_21A.md` et `11_flutter_security_contract_17A_21A.md` pour toute reprise backend ou Flutter.
