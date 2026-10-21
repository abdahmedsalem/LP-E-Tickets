# Suppression de compte depuis l’application

Le client confirme, consulte et peut enregistrer le rapport du portefeuille.
La valeur restante exige un abandon explicite, jamais présélectionné ; il peut
quitter ce parcours pour gérer ses tickets. Le PIN valide ensuite la suppression
immédiate côté Odoo. Le succès serveur déclenche un popup puis le retour à la
connexion. Les transactions financières restent cohérentes.

Toutes les données personnelles, captures et justificatifs d’achat sont
supprimés immédiatement lors de la suppression du compte. Seul l’historique des
mouvements sans données personnelles est gardé temporairement pendant trois
jours pour le suivi des opérations, puis purgé automatiquement car il n’est
ensuite plus nécessaire. La notice
affichée dans le rapport, son export et les pages `/privacy` et
`/account-deletion` doit reprendre exactement ce fonctionnement.

Après modification de la notice, un rapport déjà ouvert doit être rechargé avant
de confirmer : la notice fait partie de l'empreinte vérifiée par le serveur.

Voir [le contrat serveur, la récupération et les limites](flux_suppression_compte.md).
