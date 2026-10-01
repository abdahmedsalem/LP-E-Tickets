# Suppression de compte : état vérifié du parcours

Le parcours démarre dans Paramètres > Supprimer mon compte : affichage du délai,
confirmation, PIN, demande Odoo et reçu consultable après une coupure réseau.
Le délai par défaut et celui des nouvelles installations est de 7 jours. Une
configuration existante doit être vérifiée avant déploiement.

Les demandes sont mises en file d'e-mail pour support@acpec.mr. Si le compte
possède une adresse e-mail, un accusé de réception est également mis en file.
Un e-mail en file n'est pas une preuve de livraison ; le serveur sortant doit
être configuré et les échecs traités par l'équipe.

Le bouton Odoo « Révoquer les accès (préparation) » révoque les sessions actives
et renouvelables, réinitialise le PIN et désactive le compte. Il laisse la demande
« En traitement ». Cette action ne supprime pas les données personnelles et
n'envoie aucune confirmation de suppression.

Le traitement planifié alerte le support des demandes en retard. Il ne marque
pas les demandes comme supprimées et ne désactive pas automatiquement les
comptes à échéance. L'équipe doit traiter les demandes dans les 7 jours annoncés.

La clôture manuelle exige : compte inactif ou supprimé, absence de sessions actives
ou renouvelables, compte rendu, preuve de suppression des données personnelles,
traitement des tickets et du solde, justification et durée des données conservées
même si le compte a été supprimé, canal/date/référence de confirmation au client. Ces justificatifs sont saisis par le
responsable : leur présence ne constitue pas une preuve automatique d'effacement.

Les transactions, factures et pièces justificatives doivent être conservées selon
la règle validée par ACPEC. La durée et le fondement de conservation restent à
préciser. Les données personnelles non concernées doivent être réellement
supprimées selon une procédure vérifiée.

## Limites de validation

Aucune validation Apple n'est acquise. Apple autorise un traitement manuel avec
délai et confirmation au client, mais une simple désactivation ne suffit pas :
https://developer.apple.com/support/offering-account-deletion-in-your-app/

Restent à valider : procédure d'effacement, durée de conservation, confirmation
au client même sans e-mail, livraison SMTP, essai sur iPhone et configuration
réelle du serveur de production. Les tests locaux ne prouvent pas ces points.

Le support suit le [guide opérationnel](../../LP-E-Tickets-Backend/addons/acpec_mobile_account_deletion/docs/procedure-support.md).
