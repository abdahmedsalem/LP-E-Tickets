# Procédure support — suppression manuelle d'un compte

Responsable : équipe support ACPEC (support@acpec.mr).
Délai : au plus tard à l'échéance indiquée sur le reçu, 7 jours par défaut.
Ouvrir Mobile Auth > Opérations > Demandes de suppression chaque jour ; vérifier
également la file d'e-mails et le filtre « En retard ».

## 1. Prendre en charge

Ouvrir la demande et cliquer « Prendre en charge ». Le responsable est enregistré.
La demande faite dans l'application a déjà été authentifiée par la session et le
PIN ; ne pas imposer au client d'envoyer un deuxième e-mail au support.
Identifier le canal de confirmation utilisable avant d'effacer les coordonnées.
Pour un client sans e-mail, organiser un SMS ou un autre canal convenu ; l'envoi
n'est pas automatisé par ce module. Ne jamais demander le PIN ou l'OTP au client.

## 2. Régler les opérations encore ouvertes

Vérifier tickets, QR réservés/en cours en station, solde, achats et transferts en
attente. Faire résoudre chaque opération par l'équipe habilitée, sans annuler la
valeur des tickets ni effacer une opération financière. Renseigner le résultat
et les références dans « Traitement des tickets, QR et solde ». S'il n'y en a
aucun, l'indiquer explicitement. Escalader dès qu'une difficulté menace le délai.

## 3. Révoquer puis effacer

Cliquer « Révoquer les accès » : sessions actives et renouvelables révoquées,
PIN réinitialisé, compte désactivé. Ce n'est PAS l'effacement.

L'administrateur habilité réalise ensuite la suppression manuelle :

- Sur un compte sans obligation de conservation ni liens métier : supprimer
  l'utilisateur depuis les paramètres Odoo, puis le contact personnel associé
  s'il n'est pas partagé, et vérifier la suppression de leurs données annexes.
- Sur un compte lié à des opérations financières : inventorier les références
  avant toute suppression. Préserver transactions, factures et justificatifs
  requis ; supprimer les données de profil, photos, coordonnées et données
  d'appareils qui ne sont pas couvertes par une obligation de conservation.
  Vérifier également sessions historiques, demandes OTP, pièces jointes de
  profil et copies dans messages/journaux. Faire intervenir l'administrateur
  technique pour les enregistrements dont la suppression est restreinte.
- Ne pas supprimer un contact partagé ou une référence financière pour forcer
  la suppression d'un utilisateur. Ne pas considérer un champ masqué, un compte
  archivé ou un changement de nom comme preuve d'effacement de toutes les copies.

Vérifier l'absence des données visées et l'impossibilité de réutiliser les anciens
accès. Dans « Preuve de suppression », noter les catégories effacées, la date,
l'intervenant et la référence du rapport technique ; ne pas recopier les données
effacées dans ce champ.

## 4. Justifier ce qui reste

Pour chaque catégorie conservée, renseigner la justification validée par ACPEC,
la durée/date limite et les personnes autorisées à y accéder. Ce contrôle reste
nécessaire même si l'utilisateur Odoo a été supprimé : ses factures peuvent
encore exister. S'il ne reste rien, le préciser.

Aucune durée réglementaire n'est inventée par le logiciel. Faire valider la règle
applicable par la personne responsable de la conservation avant le traitement
d'un compte avec documents financiers. Traiter aussi les copies de sauvegarde
selon cette règle et éviter qu'une restauration ne réactive un compte supprimé.

## 5. Confirmer au client, puis clôturer

Envoyer manuellement la confirmation au client par le canal convenu. Ne pas
confondre un accusé de réception initial, un e-mail en file ou une alerte au support
avec une confirmation finale. Documenter le canal, la date et la référence de
l'envoi effectué ; traiter les échecs connus avant clôture.

Modèle à adapter aux opérations réellement réalisées :

> Votre demande [référence] a été traitée le [date]. Votre compte a été supprimé
> et ses accès révoqués. Les données personnelles non soumises à conservation
> ont été effacées. Restent conservés : [catégories], pour [justification],
> jusqu'à [échéance/durée]. Pour toute question : support@acpec.mr.

Cliquer « Clôturer après suppression et confirmation ». Le système contrôle les
rubriques obligatoires et les accès, puis horodate la clôture. La fiche devient
non modifiable par les opérateurs. Les attestations engagent l'opérateur ; elles
ne remplacent pas les opérations d'effacement ni une preuve de livraison.

## Vérification avant mise en service

Faire un exercice complet avec un compte fictif représentatif contenant des
transactions et un moyen réel de confirmation. Le test automatisé de suppression
physique couvre un compte vide, pas toutes les dépendances d'un compte financier.
La validation Apple reste distincte de cette procédure et des tests locaux.
