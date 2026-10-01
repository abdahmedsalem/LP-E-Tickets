# Demande de suppression de compte

Voir [le parcours et ses limites](flux_suppression_compte.md).

Le bouton des paramètres enregistre une demande après confirmation et saisie du
PIN. Le reçu confirme la demande, pas l'effacement des données. Le délai par défaut
est de 7 jours. Les notifications sont mises en file d'e-mail pour le support et,
si une adresse existe, pour le client.

Installer ou mettre à jour le module `acpec_mobile_account_deletion` avant de
publier le frontend. Vérifier le délai configuré, le serveur de messagerie et la
procédure opérationnelle de suppression/confirmation. Les données légalement
conservées doivent être identifiées avec leurs durées et justifications.

Les tests Flutter de service vérifient le contrat, les réponses invalides et la
récupération du reçu. Les tests Odoo couvrent aussi les appels HTTP authentifiés.
Ils ne remplacent pas la vérification de l'effacement effectif, de la livraison
d'e-mail et du parcours complet sur iPhone.
