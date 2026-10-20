# Suppression de compte : parcours immédiat

Le client ouvre Paramètres > Supprimer mon compte, confirme son intention,
consulte le rapport du portefeuille et peut l’enregistrer ou le capturer.
L’enregistrement est facultatif. Le rapport ne contient aucun secret de QR
permettant un retrait et devient une copie informative après suppression.

Si des tickets restent, le client peut quitter ce parcours pour gérer son
portefeuille avec les fonctions existantes. Sinon, une case non cochée exige
l’abandon explicite de la valeur. La suppression ne simule aucun remboursement
ni transfert. Un achat non réglé ou un QR réservé en station bloque l’effacement.
Un portefeuille modifié depuis le rapport impose de le relire.

Le bouton « Confirmer la suppression de mon compte » ouvre la vérification PIN.
Après confirmation du serveur, le seul popup de succès apparaît deux secondes,
puis l’application nettoie la session locale et revient à la connexion.
Le parcours est aussi accessible aux clients en attente d’activation : session
valide et PIN requis, sans imposer l’approbation de l’appareil. Les autres actions
sensibles continuent d’exiger un appareil approuvé.

## Installation et contrat serveur

Mettre à jour le module Odoo `acpec_mobile_account_deletion` version
`19.0.1.1.0` et redémarrer le serveur. Il dépend désormais aussi de FuelToken
Core et Mobile Auth OTP.

Configurer le paramètre système
`acpec_mobile_account_deletion.retention_notice` : catégories financières
conservées, justification, durée et accès. Sans cette politique, le parcours
refuse de démarrer. Une politique de base locale de test ne doit pas être
utilisée comme politique de production.

Routes JSON-RPC sous `/api/acpec/mobile_auth/v1/account-deletion` :

- `preview` : session requise ; rapport, obstacles, notice de conservation et
  empreinte de l’état du portefeuille.
- `execute` : session et `action_code` requis, `confirmed: true`, `snapshot`,
  `waive_value` explicite si nécessaire, `recovery_key` UUID aléatoire.
- `recover` : reçu sans données personnelles, accessible avec la seule clé de
  récupération. Un rejeu de `execute` avec cette clé restitue le reçu après la
  révocation, sans répéter l’effacement.

L’utilisateur cible provient uniquement de la session. Un `user_id` fourni par
le client ne sélectionne jamais le compte. Le PIN utilise la vérification
serveur existante et ses limites de tentatives.

Le traitement verrouille les données métier, vérifie l’empreinte et neutralise
les QR actifs. Les tickets concernés passent de QR actif à QR bloqué ; aucune
quantité n’est détruite. Une transaction de blocage documente ce changement.
La valeur abandonnée reste dans les traces du compte inaccessible. Carnets,
achats et transactions ne sont ni supprimés ni réaffectés.

Le profil et les coordonnées sont effacés, le login remplacé et le PIN supprimé.
Les copies du profil, demandes d’inscription, OTP, sessions et appareils sont
purgés. Les métadonnées personnelles des audits sont effacées par une fonction
privée contrôlée ; les événements restent conservés et leurs API publiques
restent immuables. Le libellé stocké du portefeuille est recalculé.

Effacement et audit de succès partagent une transaction. Une erreur annule les
changements métier. Aucun envoi d’e-mail ou livraison de notification n’est
attesté artificiellement : la confirmation est le résultat serveur.

Les anciennes routes `status` et `request` et le traitement manuel restent
disponibles pour les anciennes versions mobiles et le backoffice.

## Coupure réseau

Flutter persiste une clé aléatoire en stockage sécurisé avant l’envoi. Si cette
persistance échoue, aucune suppression n’est envoyée. Odoo ne conserve que son
empreinte ; le reçu peut être retrouvé pendant sept jours. Un timeout n’est
jamais un succès sans vérification via `recover`. Le parcours et l’écran de
connexion récupèrent le résultat après interruption. La clé est effacée après
le popup. Aucun PIN n’est conservé pour rejouer une demande. Jetons, préférences
de connexion et caches locaux sont nettoyés.

## Validation et limites

Les tests HTTP vérifient session, PIN, confirmation, rejouement, récupération
sans session et rollback sur échec d’audit. Les tests métier couvrent la valeur,
les QR réservés, la conservation des pièces financières et la purge des copies
personnelles prises en charge. Flutter vérifie le consentement, le PIN, le
popup et l’absence de faux succès après un timeout.

Les pièces financières légalement nécessaires restent soumises à la politique
configurée. Les copies exportées par le client restent sous son contrôle.
Sauvegardes, journaux d’infrastructure, intégrations et données d’autres modules
nécessitent leur propre politique de conservation et d’effacement. Les fichiers
supprimés suivent le nettoyage Odoo du filestore. Une restauration doit
réappliquer les suppressions avant réouverture.

Ces limites sont à vérifier avant production : les tests locaux ne constituent
ni une certification Apple ni une validation juridique.
