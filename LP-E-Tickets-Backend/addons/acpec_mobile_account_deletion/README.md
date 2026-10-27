# Suppression de compte mobile

Ce module propose deux parcours distincts : une demande traitée par l’équipe
support et une suppression immédiate confirmée dans l’application. Les deux
parcours sont exposés par l’API mobile et exigent une session valide.

## Demande traitée par le support

Le délai par défaut est de 7 jours et l’adresse support par défaut est
`support@acpec.mr`. Ces valeurs peuvent être ajustées dans les paramètres Odoo
de la base : `acpec_mobile_account_deletion.processing_days` et
`acpec_mobile_account_deletion.support_email`. Le délai accepté est compris
entre 1 et 90 jours. Une valeur invalide empêche la création de la demande ;
une valeur valide déjà configurée est conservée.

Routes POST JSON-RPC :

- `/api/acpec/mobile_auth/v1/account-deletion/status`
- `/api/acpec/mobile_auth/v1/account-deletion/request` avec
  `{confirmed: true, action_code: "PIN"}`.

L'identité provient de la session. Les tentatives répétées conservent le même reçu
et la même échéance. Le PIN exige un appareil approuvé.

Dans le back-office, le responsable prend la demande en charge, révoque les accès,
documente le traitement des tickets et du solde, puis confirme la suppression au
client avant de clôturer. La clôture efface les données personnelles qu’Odoo peut
supprimer sans enlever les enregistrements financiers requis.

La tâche planifiée alerte le support des demandes échues ; elle ne supprime pas
les comptes automatiquement. Le menu des demandes se trouve dans FuelToken,
sous « Opérations du jour ».

Les courriels sont mis en file dans la même transaction que la demande. Ils ne
sont pas considérés comme livrés ; le support doit surveiller les échecs SMTP.

## Suppression immédiate dans l’application

Le parcours mobile présente d’abord un aperçu du portefeuille. L’utilisateur
confirme ensuite son code PIN et, s’il reste un solde ou des tickets, accepte
explicitement leur abandon. L’aperçu est vérifié une nouvelle fois au moment de
la suppression pour détecter tout changement intervenu entre-temps.

Routes POST JSON-RPC :

- `/api/acpec/mobile_auth/v1/account-deletion/preview`
- `/api/acpec/mobile_auth/v1/account-deletion/execute`
- `/api/acpec/mobile_auth/v1/account-deletion/recover`

Les sessions et accès sont révoqués dans la même transaction que l’effacement.
Les informations personnelles, pièces justificatives et preuves de paiement
sont supprimées immédiatement. Les mouvements anonymisés restent disponibles
pendant 3 jours, puis la tâche planifiée les purge. Un reçu opaque permet de
vérifier la fin de l’opération pendant 7 jours.

Les deux parcours conservent les enregistrements financiers nécessaires et
protègent les comptes partagés ou opérationnels contre une suppression mobile.
La clôture manuelle exige une attestation de l’opérateur ; elle ne vérifie pas
automatiquement chaque enregistrement externe au module.

Tests locaux : utiliser une base dédiée et un filtre strict, par exemple
`-d station_lock_audit_20260925 --db-filter=^station_lock_audit_20260925$`
avec `-u acpec_mobile_account_deletion --test-enable --test-tags /acpec_mobile_account_deletion --stop-after-init --http-port=8079 --max-cron-threads=0`.

Procédure opérationnelle : [guide du support](docs/procedure-support.md).
