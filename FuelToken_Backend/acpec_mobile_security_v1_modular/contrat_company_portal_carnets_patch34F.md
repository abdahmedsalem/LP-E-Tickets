# Contrat Company Portal carnets - Patch34F

## Contexte

Patch34A a fixé la doctrine :

1 acpec.fuel.face.line = 1 carnet.

Patch34B a rendu l’émission QR explicite par face_line_id.

Patch34C a corrigé le transfert intact : le même carnet est déplacé vers le wallet destinataire.

Patch34D a nettoyé les libellés visibles.

Patch34E a figé le contrat mobile Flutter.

Patch34F aligne le Company Portal existant sur la doctrine carnet individualisé.

## Décision importante

Le module acpec_fueltoken_company_portal existe déjà.

Il fournit une surface portail Odoo pour les comptes société :

- tableau de bord société ;
- membres ;
- achats ;
- distributions ;
- détail de distribution.

Patch34F ne crée pas un nouveau portail.

Patch34F corrige le contrat de distribution du portail existant :

- l’utilisateur portail sélectionne désormais des carnets source individuels ;
- chaque ligne du formulaire contient un face_line_id ;
- chaque ligne représente un carnet ;
- le portail envoie carnet_qty = 1 par carnet sélectionné ;
- le moteur backend existant reste responsable des contrôles et du transfert.

## Contrat formulaire portail

Entrée portail recommandée :

line_0_face_line_id = 123
line_1_face_line_id = 124
line_2_face_line_id = 125

Transformation backend :

[
  {"face_line_id": 123, "carnet_qty": 1},
  {"face_line_id": 124, "carnet_qty": 1},
  {"face_line_id": 125, "carnet_qty": 1}
]

## Clé technique

La clé technique de sélection est :

face_line_id

Elle représente le carnet source à distribuer.

Côté métier, l’interface doit parler de :

Carnet source

et non de ligne de tickets ou ligne de faces.

## Règle carnet_qty

Après Patch34A, une face_line représente normalement un seul carnet.

Donc pour le Company Portal explicite :

carnet_qty = 1

Le champ carnet_qty est conservé pour compatibilité backend, wizard back-office et fallback legacy.

Il ne doit pas être utilisé par le portail pour regrouper plusieurs carnets sur un même face_line_id.

Si le portail veut distribuer plusieurs carnets, il doit envoyer plusieurs lignes avec des face_line_id différents.

## Fallback legacy

Patch34F conserve un fallback serveur pour l’ancien contrat type + quantité :

line_0_carnet_type_id
line_0_qty

Ce fallback est conservé uniquement pour compatibilité.

L’interface portail Patch34F ne doit plus l’utiliser.

## Règles backend obligatoires

La distribution société continue à passer par :

acpec.fuel.distributor.action_distribute_to_member(...)

Le backend vérifie notamment :

- le partenaire société est bien une société ;
- le partenaire société est portal-only ;
- le membre destinataire est un individu ;
- le membre est rattaché à la société ;
- le membre possède un utilisateur mobile actif et approuvé ;
- le wallet société possède le carnet source ;
- le carnet source est intact et transférable ;
- le même carnet ne peut pas apparaître plusieurs fois dans une distribution ;
- le transfert final respecte les règles Patch34C.

## Ce que le portail ne doit pas faire

Le Company Portal ne doit pas :

- créer directement acpec.fuel.carnet.transfer ;
- écrire directement sur acpec.fuel.face.line.wallet_id ;
- modifier qty_available ;
- valider un utilisateur mobile ;
- approuver un device mobile ;
- bypasser l’idempotency ;
- réimplémenter les règles de distribution.

## Affichage recommandé Company Portal

Liste des carnets société disponibles :

- identifiant principal : carnet_short_code ;
- identifiant complet : carnet_no ;
- type : carnet_type_name ou carnet_type_code ;
- valeur ticket : face_value ;
- nombre de tickets : face_count / qty_available ;
- expiration : expires_at ;
- statut : transférable ou non transférable.

Action distribution :

- sélectionner un ou plusieurs carnets ;
- envoyer une ligne par carnet ;
- chaque ligne contient face_line_id et carnet_qty = 1.

## Relation avec le wizard back-office

Le wizard back-office peut continuer à fonctionner par type de carnet et quantité demandée.

Il alloue ensuite les carnets disponibles depuis le wallet société.

Cette logique est acceptable pour le back-office.

Le Company Portal doit privilégier la sélection directe des carnets par face_line_id.

## Limites volontaires Patch34F

Patch34F ne crée pas de nouvelle route HTTP.

Patch34F ne change pas le moteur de transfert.

Patch34F ne modifie pas le contrat mobile Flutter.

Patch34F aligne uniquement le contrat et l’interface de distribution du Company Portal existant.

## Données legacy consolidées

Des anciennes données de test ou de production peuvent contenir des face_lines consolidées créées avant Patch34A :

- carnet_no vide ;
- carnet_short_code vide ;
- carnet_sequence = 0 ;
- transferable_carnet_count() > 1.

Ces lignes ne doivent pas être proposées dans le sélecteur explicite du Company Portal Patch34F.

Le portail explicite affiche uniquement les carnets individualisés Patch34A :

- carnet_no renseigné ;
- carnet_short_code renseigné ;
- carnet_sequence > 0 ;
- transferable_carnet_count() = 1.

Les lignes legacy restent traitables séparément par migration/réparation contrôlée ou par flux backend compatible, mais elles ne doivent pas être confondues avec un carnet source individuel dans l’interface portail.

## Validation différée de la distribution réelle

Au moment de Patch34F, la distribution réelle depuis le portail n’a pas été exécutée en bout-en-bout car aucun membre mobile actif/approuvé n’est encore disponible.

Cette situation est normale : la création et l’activation des utilisateurs mobiles doivent être finalisées proprement avec l’alignement Flutter.

Patch34F valide donc :

- le dashboard portail ;
- l’affichage des carnets individualisés ;
- l’exclusion des anciennes face_lines legacy consolidées ;
- le contrat de sélection par face_line_id ;
- la préparation du portail pour distribuer une ligne par carnet.

Le test complet suivant est reporté après alignement Flutter :

- création utilisateur mobile ;
- approbation mobile/device ;
- rattachement membre au compte société ;
- distribution portail vers ce membre ;
- vérification que le même face_line_id est déplacé vers le wallet membre ;
- vérification que dest_face_line_id pointe vers le même face_line_id.
