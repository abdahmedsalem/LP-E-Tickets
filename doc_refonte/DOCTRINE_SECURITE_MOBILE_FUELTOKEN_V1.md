# Doctrine de sécurité mobile — FuelToken V1

Document de référence. Énonce les principes, les invariants testables et les tests
de la sécurité mobile FuelToken. Le code se conforme à cette doctrine.

---

## 0. Modèle de menace

La doctrine protège un système qui porte de la valeur (carnets, tickets carburant)
contre les menaces suivantes. Chaque menace est couverte par un ou plusieurs invariants
des sections suivantes.

```text
M1  Vol de session / jeton            => sessions à jetons à forte entropie, rotation,
                                          révocation, expiration (§3).
M2  Vol d'appareil                    => device blocable, refus dur au login (§2, INV-D7),
                                          compte blocable au login si le risque vise le
                                          compte (§2, INV-D11), actions sensibles derrière
                                          PIN (§5).
M3  SIM-swap (prise de contrôle du
    numéro par un tiers)              => OTP prouve le numéro, pas la personne ;
                                          tout appareil neuf reste pending_trust et passe
                                          par approbation humaine (§2, §6) ; blocage user
                                          persistant si prise de contrôle confirmée
                                          (§2, INV-D11).
M4  device_uid rejoué ou forgé        => le device_uid est un identifiant non attesté ;
                                          la confiance qu'on lui accorde est bornée par
                                          l'approbation admin et le transport chiffré (§2, §7).
M5  Recyclage de numéro               => résidu assumé, borné par device-trust (§8).
M6  Brute-force OTP                   => hachage, limitation de débit, bornage des essais (§6).
M7  Brute-force PIN                   => hachage fort, comptage sous verrou, blocage
                                          progressif (§5).
M8  Double-dépense / rejeu d'opération=> idempotence à contrainte base + verrous
                                          pessimistes (§5).
M9  Élévation / accès transverse      => cloisonnement société, rôles back-office,
                                          mur total avant device trusted (§1, §2, §5).
M10 Falsification de la trace         => journal d'audit immuable, audit transactionnel
                                          des actions autorisées (§7).
```

---

## 1. Périmètre société et identité

### Principes

FuelToken est mono-société. La base Odoo peut héberger plusieurs sociétés ; une seule
porte FuelToken — la **société FuelToken** — contexte unique de toute opération mobile.

L'identité de connexion d'un utilisateur mobile est son numéro de téléphone local
mauritanien à 8 chiffres. L'identité durable interne est `res.users.id` ; le numéro en
est la clé de recherche externe. Les objets métier s'ancrent sur `res.partner` et sont
donc indépendants du numéro.

### Invariants

```text
INV-S1  Une seule société porte FuelToken : la société FuelToken.
INV-S2  L'unicité est imposée par un index unique partiel sur res.company, actif sur les
        seules lignes dont le flag FuelToken est vrai. Activer une seconde société
        FuelToken échoue au niveau base.
INV-S3  Au démarrage, si l'état viole INV-S1, le readiness est CRITIQUE.
INV-S4  Tout objet métier mobile porte company_id = société FuelToken.
INV-S5  Aucun utilisateur d'une autre société n'atteint un objet FuelToken.

INV-I1  login, mobile_phone et le numéro 8 chiffres sont toujours égaux pour un
        utilisateur mobile. Changer le numéro modifie les deux champs ensemble.
INV-I2  login est unique dans la base Odoo.
INV-I3  mobile_phone est unique. C'est la source de vérité requêtable du numéro.
INV-I4  res.partner.phone est un contact. Aucune résolution d'identité ne le lit.
INV-I5  Un utilisateur a exactement un numéro.
INV-I6  L'identité durable est res.users.id. Wallet, carnets et historique sont ancrés
        sur res.partner et survivent à un changement de numéro sur le même utilisateur.
INV-I7  Le changement de numéro se fait exclusivement en back-office, sur le même
        res.users.id, de façon atomique, avec audit et révocation des sessions actives.
```

### Tests

```text
T-S1  Activer FuelToken sur une seconde société => échec base (IntegrityError).
T-S2  Deux activations concurrentes sur deux sociétés => une seule réussit.
T-S3  État double simulé au démarrage => readiness CRITIQUE.
T-S4  Objet créé via le flux mobile => company_id = société FuelToken.
T-S5  Utilisateur d'une autre société => aucun objet FuelToken atteignable.
T-I1  Deux utilisateurs, même mobile_phone => rejet.
T-I2  Création d'un utilisateur mobile => login == mobile_phone == numéro.
T-I3  Changement de numéro => login et mobile_phone changent ensemble, user_id inchangé,
      wallet et carnets conservés.
T-I4  Modification de partner.phone => aucun effet sur l'identité ni la résolution.
T-I5  Ajout d'un second numéro à un utilisateur => rejet.
```

---

## 2. Appareil et confiance

### Principes

Un appareil est identifié par un `device_uid` généré par l'application mobile. C'est un
identifiant **non attesté** : la confiance qu'on lui accorde n'est valable que sous
transport chiffré (§7) et reste bornée par l'approbation humaine de tout appareil neuf.

Dans le backend, chaque couple durable `(user_id, device_uid stable)` est matérialisé
par un objet `acpec.mobile.device`. La confiance persistante est portée par cet objet
durable ; la session mobile est seulement le runtime tokenisé qui référence ce device.

La confiance est portée par le couple **utilisateur + appareil**, jamais par l'un seul.
Un appareil neuf naît non approuvé et n'accède à aucune fonction métier — ni action,
ni consultation — tant qu'un administrateur ne l'a pas approuvé.

### Invariants

```text
INV-D0  Chaque couple (user_id, device_uid stable) est représenté par un objet durable
        acpec.mobile.device. Les sessions mobiles référencent ce device durable.
        La confiance est portée par le device durable, pas par la session seule.
INV-D1  La confiance est l'état device_trust_state d'un couple (user_id, device_uid) :
        pending_trust, trusted ou blocked.
INV-D2  Tout couple (user, appareil) inconnu naît en pending_trust.
INV-D3  Un appareil ne passe en trusted que par une action d'approbation back-office.
        Aucune authentification mobile n'accorde le trust par elle-même.
INV-D4  Au plus un appareil trusted par utilisateur à un instant donné. Approuver un
        nouvel appareil révoque le trust des appareils précédents du même utilisateur.
INV-D5  Un même appareil physique peut être trusted pour plusieurs utilisateurs distincts ;
        chaque couple (user, appareil) a sa propre confiance, sans héritage croisé.
INV-D6  La confiance d'un couple survit au logout, à l'expiration et à la reconnexion :
        elle n'est perdue que par révocation, blocage, ou promotion d'un autre appareil
        du même utilisateur (INV-D4).
INV-D7  Un appareil blocked est refusé au login : aucune session n'est ouverte.
INV-D8  Tant que l'appareil de la session courante n'est pas trusted, aucune opération
        métier n'est servie — ni action sensible, ni consultation de données métier.
INV-D9  Approuver, bloquer ou révoquer un appareil s'applique à tout le couple
        (user, appareil) de façon cohérente et auditée.
INV-D10 Perte ou alerte : le back-office peut révoquer ou bloquer aussi bien
        l'utilisateur que l'appareil.
INV-D11 Un utilisateur mobile blocked est refusé à l'OTP et au login : OTP non
        consommé, aucune session ouverte, quel que soit l'appareil. Le blocage
        user est un état persistant, pas une simple révocation de sessions.
INV-D12 La réactivation d'un utilisateur mobile blocked ne restaure jamais
        automatiquement le trust device. Après réactivation user, chaque device
        conserve son état propre : pending_trust, trusted ou blocked.
```

### Tests

```text
T-D1  Premier login d'un couple inconnu => pending_trust.
T-D2  Aucune séquence d'authentification mobile seule ne produit trusted sans action admin.
T-D3  Approuver un nouvel appareil => l'appareil précédemment trusted du même user
      repasse non-trusted (révocation à la promotion).
T-D4  Appareil partagé : deux users sur le même device_uid => deux confiances séparées ;
      truster l'un n'affecte pas l'autre.
T-D5  Logout / expiration / reconnexion sur un appareil approuvé => reste trusted.
T-D6  Appareil blocked => login refusé, aucune session.
T-D7  Appareil pending_trust => toute lecture ou action métier refusée côté backend
      (le masquage frontend ne suffit pas).
T-D8  Réinstallation : même device_uid réutilisé ; device_uid différent => pending_trust.
T-D9  Utilisateur mobile blocked => OTP/login refusés sur tout appareil, y compris
      appareil neuf ; aucune session ouverte ; OTP non consommé.
T-D10 Réactivation user blocked => aucun device ne redevient trusted automatiquement ;
      l'accès métier reste refusé tant qu'un device n'est pas explicitement trusted.
```

---

## 3. Session

### Principes

La session est l'objet runtime qui porte les jetons. Elle lie un utilisateur et un
appareil, jamais un numéro. Les jetons sont à forte entropie et stockés hachés.

### Invariants

```text
INV-T1  Une session lie user_id + device_id + device_uid et porte access_token,
        refresh_token, state et device_trust_state. Elle référence le device durable
        et hérite/voit son état de confiance sans jamais l'accorder elle-même.
INV-T2  Les jetons sont à forte entropie ; seul leur haché est stocké.
INV-T3  Le rafraîchissement effectue une rotation : une nouvelle session active est émise,
        l'ancienne passe en grâce à usage unique puis devient inexploitable.
INV-T4  Une reconnexion crée une session pending_trust ; elle hérite de l'état de
        confiance persistant du couple (user, appareil) selon §2, sans jamais l'accorder.
INV-T5  Une session révoquée, expirée ou en état non-actif n'autorise aucune opération.
INV-T6  La révocation d'un utilisateur ou d'un appareil rend ses sessions inexploitables.
INV-T7  Aucune session mobile n'existe sans device_uid stable.
```

### Tests

```text
T-T1  Session => contient user_id, device_uid, jetons hachés, états.
T-T2  Refresh => ancienne session utilisable une seule fois en grâce, puis rejetée.
T-T3  Rejeu d'un refresh hors grâce => rejet.
T-T4  Reconnexion => nouvelle session pending_trust, confiance héritée selon §2.
T-T5  Session révoquée/expirée => toute opération refusée.
T-T6  Révocation user/appareil => sessions liées inexploitables.
```

---

## 4. Inscription mobile

### Principes

L'inscription prouve le contrôle d'un numéro par OTP et crée un compte mobile
connectable destiné à enrôler un appareil. Elle n'accorde aucun rôle ni accès métier.

### Invariants

```text
INV-R1  La finalisation d'une inscription exige un device_uid stable, validé AVANT
        consommation de l'OTP et avant toute création de compte.
INV-R2  Si le device_uid est absent ou non stable : refus à contrat public générique,
        OTP non consommé, aucun utilisateur, aucune session, aucune demande de compte.
        Le motif technique détaillé vit dans l'audit back-office, jamais dans la réponse.
INV-R3  Une inscription valide crée l'utilisateur (login = numéro), une session
        pending_trust, et renvoie les jetons. L'utilisateur est connectable mais sans
        accès métier (§2).
INV-R4  L'inscription n'accorde aucun rôle métier. Le rôle de base n'est accordé qu'à
        l'approbation de l'appareil.
INV-R5  Le flux nominal après inscription conduit l'utilisateur à un écran d'attente
        d'activation. Toute absence de session exploitable est un échec explicite,
        jamais un retour silencieux.
```

### Tests

```text
T-R1  Inscription sans device_uid stable => refus générique, OTP non consommé,
      aucun user, aucune session, aucune demande de compte ; challenge réutilisable ensuite.
T-R2  Inscription avec device_uid stable => user créé, session pending_trust, jetons,
      aucun rôle métier accordé.
T-R3  Inscription puis approbation de l'appareil => rôle de base accordé à ce moment-là.
```

---

## 5. Actions sensibles

### Principes

Une action sensible déplace ou consomme de la valeur (transfert, émission/consommation
de QR). Elle exige un contexte de confiance complet et une confirmation par PIN, et elle
est tracée. Aucune facilité d'environnement ne relaxe ces contrôles.

### Invariants

```text
INV-A1  Une action sensible exige toutes les conditions : session valide, utilisateur
        mobile-only, appareil de la session trusted, rôle métier requis, et action_code
        (PIN) valide.
INV-A2  Le PIN est haché fort ; les échecs sont comptés sous verrou ; le blocage est
        progressif. Le PIN n'est jamais relaxé par aucun mode.
INV-A3  Toute mutation économique exige une clé d'idempotence ; l'unicité est garantie
        au niveau base, et les enregistrements de valeur sont verrouillés pendant
        l'opération (pas de double-dépense, pas de rejeu).
INV-A4  Un objet de valeur ne peut être consommé deux fois ; sa machine à états et son
        verrou le garantissent.
INV-A5  Le cloisonnement société et le rôle sont vérifiés à chaque opération ; rien ne
        s'appuie sur l'authentification ambiante.
INV-A6  Toute action sensible — autorisée ou refusée — est journalisée à l'audit
        immuable, secrets masqués.
```

### Tests

```text
T-A1  Action sensible sans appareil trusted => refus.
T-A2  Action sensible sans rôle requis => refus.
T-A3  Action sensible avec PIN invalide => refus + comptage ; blocage après le seuil.
T-A4  Deux mutations économiques concurrentes à même clé d'idempotence => une seule effet.
T-A5  Double consommation du même QR => second refus.
T-A6  Action autorisée et action refusée => toutes deux présentes à l'audit, sans secret.
```

---

## 6. Authentification OTP

### Principes

L'OTP prouve le contrôle d'un numéro. Le code est haché, sa délivrance limitée en débit,
sa vérification bornée en essais. L'OTP crée ou restaure une session ; il n'accorde
jamais la confiance d'appareil ni un rôle métier.

### Invariants

```text
INV-O1  Le code OTP est haché ; aucune valeur en clair n'est stockée ni renvoyée.
INV-O2  La délivrance est limitée par identifiant (minute / jour) et la vérification
        bornée en essais avant blocage temporaire du challenge.
INV-O3  La réponse publique d'inscription et de connexion est uniforme : elle n'indique
        pas si un numéro existe.
INV-O4  Un OTP vérifié crée une session pending_trust et ne confère ni trust ni rôle.
```

### Tests

```text
T-O1  Aucun code OTP en clair en base ni dans une réponse.
T-O2  Dépassement des essais => challenge bloqué temporairement.
T-O3  Réponses publiques identiques pour numéro existant et inexistant.
```

---

## 7. Prérequis transverses

### Principes

La sécurité du modèle repose sur trois garanties d'environnement qui ne sont pas
négociables.

### Invariants

```text
INV-X1  Tout le trafic mobile passe en transport chiffré. Le device_uid et les jetons
        ne transitent jamais en clair.
INV-X2  Production / sécurité stricte est le comportement par défaut ; les facilités de
        développement n'existent que par assertion positive d'environnement, et ne
        relaxent jamais device-trust, rôle, session, PIN, idempotence ni audit.
INV-X3  Action sensible autorisée et réussie : l'audit success/allowed est écrit
        dans la même transaction que l'action métier, sans try/except. Si l'audit
        échoue, le savepoint rollback l'action métier et ré-émet l'exception : ce
        qui n'est pas auditable n'est pas autorisé.
INV-X3b Refus sécurité avant autorisation : l'audit de refus est écrit via une
        transaction séparée committed, afin de survivre au rollback/savepoint du
        flux refusé. Si cette écriture échoue, _logger.exception est le dernier recours.
        Ce chemin est une preuve de refus indépendante, jamais un best-effort sur
        une action autorisée.
INV-X3c _logger est du diagnostic opérationnel. Il complète l'audit en base, mais
        ne le remplace jamais comme preuve métier/sécurité.
INV-X3d Aucun secret brut (OTP, PIN/action_code, jeton, secret, QR complet) ne peut
        apparaître dans une ligne d'audit ni dans un log Python.
ANTI-X3 Interdit : un helper unique qui avale les erreurs d'audit pour les succès
        comme pour les refus. Succès autorisé et refus sécurité utilisent deux
        chemins nommés et visibles au point d'appel ; aucun succès autorisé ne
        peut continuer sans preuve d'audit en base.
```

### Tests

```text
T-X1  Trafic non chiffré hors environnement de développement => refusé / readiness.
T-X2  En mode développement actif : appareil non trusted, mauvais rôle, mauvais PIN,
      QR déjà consommé => toujours refusés (invariants non relaxés).
T-X3a Échec d'écriture d'audit sur une action sensible autorisée => l'action est annulée.
T-X3b Refus sécurité avant autorisation => l'action est refusée et une ligne d'audit
      de refus existe malgré le rollback/savepoint du flux refusé.
T-X3c Action autorisée puis erreur métier => aucun audit success/allowed n'est conservé.
T-X3d Audit/logging ne contient aucun secret brut.
T-X4  Modification ou suppression d'une ligne d'audit => refus.
```

---

## 8. Risques résiduels assumés

```text
RES-1  Recyclage de numéro. Le numéro étant l'identité, un numéro réattribué par
       l'opérateur à une autre personne permet, par contrôle de la SIM, d'atteindre
       le compte de l'ancien titulaire. Le risque est borné : tout appareil neuf reste
       pending_trust, donc aucune action ni consultation métier (§2) sans approbation
       back-office ; l'administrateur voit un appareil neuf sur un compte existant.
       Une séparation personne / numéro est hors périmètre V1.

RES-2  device_uid non attesté. La reconnaissance d'un appareil repose sur un identifiant
       fourni par le client. Sa valeur de sécurité tient au transport chiffré (INV-X1) et
       au fait qu'un appareil neuf passe toujours par approbation humaine (INV-D2, INV-D3).
       Aucune attestation matérielle n'est exigée en V1.

RES-3  Pas de gel wallet séparé en V1. La valeur est protégée par la pile d'accès :
       session valide, utilisateur autorisé, device trusted, rôle requis, PIN/action_code,
       idempotence et verrous. Le blocage user/device rend la valeur inatteignable
       sans ajouter un état métier wallet supplémentaire.
```

---

## 9. Invariants de cohérence globale

```text
GLB-1  Aucune opération métier (lecture ou action) sans : session valide (§3) +
       appareil trusted pour cette session (§2) + cloisonnement société (§1).
GLB-2  Aucune action sensible sans, en plus : rôle requis + PIN valide + idempotence (§5).
GLB-3  Toute décision de sécurité se prend côté backend ; le frontend ne fait
       qu'afficher l'état que le backend impose.
GLB-4  Toute exception, ambiguïté ou état inconnu se résout en refus (fail-closed).
```

## Addendum Patch43H1 - manager mobile valideur positif et approbation achat

INV-H0C-MANAGER-POSITIVE-VALIDATOR  Le manager mobile FuelToken est un valideur positif limité. Il n'est pas un administrateur système mobile. Son périmètre API est fermé : lectures nécessaires à la décision, approbation d'achat et approbation de device pending_trust uniquement. Les rejets, créations/modifications structurelles station/carnet/type et rapports administratifs restent réservés au back-office/backend administratif.

T-H0C-MANAGER-POSITIVE-VALIDATOR  Les tests source-level vérifient que seules les actions sensibles `purchase_approve` et `device_approve_pending_trust` utilisent `_sensitive_action_transaction`, que les lectures autorisées passent par `_admin_user`, et que les méthodes back-office-only échouent via `_raise_mobile_manager_backoffice_only`.

INV-H0D-PURCHASE-APPROVAL-PARTNER-TRUSTED-ACCESS  L'approbation d'achat via API manager mobile est plus stricte que l'approbation back-office. Elle exige le device trusted du manager, l'action_code, l'idempotency_key, le cloisonnement société, et un accès mobile actif trusted pour le `partner_id` de l'achat. Les objets économiques restent attachés au partenaire ; `purchase.action_approve()` n'est pas modifié par cet invariant.

T-H0D-PURCHASE-APPROVAL-PARTNER-TRUSTED-ACCESS  Les tests runtime couvrent le refus si le partenaire de l'achat n'a aucun accès mobile trusted actif, le refus si son device est pending_trust ou blocked, et la réussite lorsque le manager et le partenaire satisfont les prérequis.
