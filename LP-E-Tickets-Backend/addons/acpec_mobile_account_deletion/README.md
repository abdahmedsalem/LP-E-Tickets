# Demandes de suppression de compte

Installer ou mettre à jour ce module sur Odoo 19 avec `-u acpec_mobile_account_deletion`.
Délai par défaut : 7 jours. Destinataire support : support@acpec.mr.
Vérifier les paramètres `acpec_mobile_account_deletion.processing_days` et
`acpec_mobile_account_deletion.support_email` sur chaque base. Une valeur de délai
invalide refuse la demande ; une valeur existante valide n'est pas écrasée.

Le mobile utilise deux routes POST JSON-RPC authentifiées :
- `/api/acpec/mobile_auth/v1/account-deletion/status`
- `/api/acpec/mobile_auth/v1/account-deletion/request` avec
  `{confirmed: true, action_code: "PIN"}`.
L'identité provient de la session. Les tentatives répétées conservent le même reçu
et la même échéance. Le PIN exige un appareil approuvé.

Menu : Mobile Auth > Opérations > Demandes de suppression.
La préparation révoque les accès et désactive le compte mobile, sans clôturer la
demande ni annoncer une suppression des données. La tâche planifiée alerte le
support des demandes échues ; elle n'exécute pas de suppression automatique.

Les e-mails sont mis en file dans la même transaction que la demande, jamais
expédiés avant sa validation. Le support doit surveiller le délai et les échecs
SMTP. Aucun e-mail sortant réel n'est nécessaire aux tests.

La clôture manuelle exige un compte rendu, une preuve de suppression effective,
le traitement des tickets et du solde, une justification/durée des données
conservées (même si le compte a été supprimé), ainsi que le canal, la date et la
référence de confirmation au client. Elle est refusée si le compte ou une
session active/renouvelable subsiste. La preuve de suppression est une attestation
opérateur, pas un contrôle automatique de toutes les données Odoo.

Les transactions, factures et justificatifs ne sont pas effacés par ce module.
La politique de conservation et la procédure d'effacement des autres données
doivent être validées avant la mise en service. La désactivation seule ne répond
pas à l'exigence Apple de suppression de compte.

Tests locaux : utiliser une base dédiée et un filtre strict, par exemple
`-d station_lock_audit_20260925 --db-filter=^station_lock_audit_20260925$`
avec `-u acpec_mobile_account_deletion --test-enable --test-tags /acpec_mobile_account_deletion --stop-after-init --http-port=8079 --max-cron-threads=0`.

Procédure opérationnelle : [guide du support](docs/procedure-support.md).
