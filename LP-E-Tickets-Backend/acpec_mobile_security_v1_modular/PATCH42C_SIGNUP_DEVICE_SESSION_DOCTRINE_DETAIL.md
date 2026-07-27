# Patch42C — Doctrine détaillée signup OTP, device stable et session pending

Statut : version détaillée à intégrer dans la documentation canonique.
Périmètre : choix retenu et aligné avec le code actuel Patch42C.
Objet : finalisation du signup OTP mobile avec création immédiate de session, `device_uid` stable obligatoire, device en `pending_trust`, et audit back-office en cas de refus technique.

---

## 0. Résumé du choix retenu

Patch42C ne crée plus un compte mobile “orphelin” après OTP register.
Après vérification OTP réussie, le backend crée immédiatement :

- le `res.users` mobile si nécessaire ;
- la session mobile ;
- les tokens `access_token` et `refresh_token` ;
- l’état device `pending_trust` ;
- le candidat d’approbation back-office.

La finalisation d’un signup OTP **exige un `device_uid` stable avant consommation de l’OTP**.

Si `device_uid` est absent ou non stable :

- le payload public reste générique : `SIGNUP_NOT_ALLOWED` ;
- le message public est en français ;
- le détail technique est enregistré dans la table d’audit back-office ;
- l’OTP n’est pas consommé ;
- aucun user n’est créé ;
- aucune session n’est créée ;
- aucune `account.request` n’est créée dans ce cas négatif.

Important : tout code public spécifique inventé pour exposer l’absence de device_uid est explicitement écarté.
Le contrat public existant reste `SIGNUP_NOT_ALLOWED` pour les refus d’inscription.

---

## 1. Doctrine langue : UI en français, technique en anglais

Règle canonique :

```text
Labels, messages publics, textes UI, messages utilisateur : français.
Codes machine, debug_reason, noms techniques, logs techniques : anglais stable.
```

Conséquences Patch42C :

```text
Payload public :
- error.code    = SIGNUP_NOT_ALLOWED
- error.message = Impossible de finaliser l’inscription avec ces informations.

Audit back-office :
- event_type   = mobile_signup_not_allowed
- code         = SIGNUP_NOT_ALLOWED
- debug_reason = register_otp_missing_or_unstable_device_uid_before_otp_consumption
```

Le détail `register_otp_missing_or_unstable_device_uid_before_otp_consumption` ne doit pas être affiché à l’utilisateur final.
Il est destiné au diagnostic back-office / audit / support technique.

---

## 2. Identité mobile V1

En V1, l’identité de connexion mobile est le numéro local mauritanien à 8 chiffres.

```text
res.users.login        = téléphone local 8 chiffres
res.users.mobile_phone = miroir technique du login
res.partner.phone      = contact Odoo, hors identité mobile V1
```

`mobile_phone` ne doit pas devenir une seconde identité indépendante.
Pour un utilisateur mobile V1 :

```text
mobile_phone = login
```

L’identité durable interne reste :

```text
res.users.id
```

Le wallet, les carnets, les transactions, les sessions et le trust doivent rester attachés au `user_id`, pas directement au numéro.

---

## 3. Changement de téléphone

Le changement de numéro ne doit pas être traité par création automatique d’un nouveau compte.

Procédure cible, hors Patch42C :

```text
- action back-office dédiée ;
- ancien login = ancien téléphone ;
- nouveau login = nouveau téléphone ;
- mobile_phone = nouveau login ;
- user_id inchangé ;
- historique métier inchangé ;
- motif obligatoire ;
- audit obligatoire ;
- révocation ou renouvellement contrôlé des sessions actives ;
- reconnexion OTP obligatoire avec le nouveau numéro.
```

Le transfert wallet user vers user reste une procédure exceptionnelle.
Le flux normal est la modification auditée du téléphone sur le même `user_id`.

---

## 4. Device UID

Le `device_uid` représente l’installation mobile.

En Patch42C, seuls les `device_uid` stables sont acceptés pour finaliser le signup OTP.

Règle stable actuelle côté code :

```text
device_uid non vide
ET
device_uid commence par ft-
```

Exemple réel :

```text
ft-android-dfc50f7e-e892-4f3c-9ad6-8cfd7c220ad1
```

Les placeholders legacy ou valeurs non stables ne doivent pas finaliser un signup OTP.
Ils ne doivent pas créer de compte, ne doivent pas créer de session, et ne doivent pas consommer l’OTP register.

---

## 5. Scope du trust device

La confiance device n’est jamais portée par le téléphone seul ni par le device seul.

Le scope V1 est :

```text
user_id + device_uid
```

Conséquences :

```text
Même user + même device_uid :
- peut hériter d’un état trusted déjà approuvé.

Même user + nouveau device_uid :
- repart en pending_trust.

Même device_uid + autre user :
- repart en pending_trust ;
- aucun héritage croisé.

Logout / expiration / relogin :
- ne suppriment pas le trust persistant du couple user_id + device_uid.
```

Patch42C ne change pas à lui seul toute la doctrine de blocage device.
Le refus dur d’un device `blocked` au login reste hors périmètre Patch42C s’il n’est pas déjà porté par le code courant. Il doit faire l’objet d’un patch séparé si la doctrine décide de le livrer.

---

## 6. Session mobile

La session mobile est l’objet runtime qui lie :

```text
user_id
device_uid
access_token
refresh_token
state
device_trust_state
```

Règle Patch42C :

```text
Aucune session d’inscription ne doit être créée sans device_uid stable.
```

Raison : sans `device_uid`, le back-office ne peut pas approuver l’appareil.
Le workflow `/activation-pending` devient alors incohérent.

---

## 7. Atomicité register OTP

Pour `verify-otp` avec `purpose = register`, l’ordre est obligatoire :

```text
1. retrouver le challenge pending ;
2. si purpose register : lire device_uid depuis kwargs ;
3. valider que device_uid est présent et stable ;
4. si device_uid absent ou non stable : refuser avant challenge.verify(code) ;
5. seulement ensuite : challenge.verify(code) ;
6. seulement ensuite : créer ou finaliser le user ;
7. seulement ensuite : créer la session mobile ;
8. renvoyer le payload session au frontend.
```

Interdits :

```text
- consommer l’OTP puis refuser pour device_uid absent ;
- créer le user puis échouer sur la session ;
- créer une session sans device_uid stable ;
- inventer un code public spécifique exposant l’absence de device_uid ;
- exposer le détail technique device_uid dans le message utilisateur.
```

---

## 8. Cas négatif : signup OTP sans device_uid stable

Cas :

```text
purpose = register
device_uid absent OU device_uid non stable
```

Comportement retenu :

```text
Retour public :
- ok      = false
- success = false
- error.code    = SIGNUP_NOT_ALLOWED
- error.message = Impossible de finaliser l’inscription avec ces informations.
```

Audit back-office :

```text
event_type   = mobile_signup_not_allowed
severity     = warning
code         = SIGNUP_NOT_ALLOWED
purpose      = register
public_message = Impossible de finaliser l’inscription avec ces informations.
debug_reason = register_otp_missing_or_unstable_device_uid_before_otp_consumption
company_id   = société courante
blocked      = True
success      = False
params       = paramètres redigés / nettoyés selon la logique d’audit existante
```

Effets interdits :

```text
- OTP consommé ;
- user créé ;
- account.request créée ;
- session créée.
```

Le `debug_reason` technique doit vivre dans l’audit back-office.
Il ne doit pas être le message public utilisateur.

---

## 9. Helper canonique retenu

Le refus du cas négatif doit passer par le helper canonique :

```text
_mobile_signup_not_allowed_response(...)
```

et non par un `_error_response(...)` spécifique.

Raison :

```text
_mobile_signup_not_allowed_response(...)
- journalise l’événement dans l’audit back-office ;
- conserve le code public SIGNUP_NOT_ALLOWED ;
- conserve le message public générique ;
- évite une nouvelle taxonomie publique non documentée.
```

Appel attendu pour Patch42C :

```python
return self._mobile_signup_not_allowed_response(
    params=kwargs,
    company=request.env.company,
    debug_reason='register_otp_missing_or_unstable_device_uid_before_otp_consumption',
    public_debug_reason='signup_not_allowed',
)
```

La société doit être transmise explicitement afin que l’audit back-office soit exploitable par les opérateurs.

---

## 10. Message public signup_not_allowed

Le message public canonique est :

```text
Impossible de finaliser l’inscription avec ces informations.
```

Ce message est en français.
Il est volontairement générique.

But :

```text
- ne pas exposer si le téléphone existe ;
- ne pas exposer si le problème vient du device_uid ;
- ne pas exposer un détail technique au client final ;
- laisser le diagnostic détaillé au back-office via l’audit.
```

Note d’implémentation : dans les helpers utilisés directement par les contrôleurs/tests, éviter un appel `_()` si le contexte Odoo ne garantit pas `env.uid`. Le message français littéral est acceptable pour ce chemin canonique.

---

## 11. Cas positif : finalisation signup OTP réussie

Après OTP register valide avec `device_uid` stable :

```text
- user créé ou retrouvé selon login ;
- login = téléphone local 8 chiffres ;
- mobile_phone = login ;
- mobile_state = self_registered ;
- session mobile créée immédiatement ;
- session.device_uid = device_uid envoyé par le frontend ;
- session.device_trust_state = pending_trust ;
- session.is_device_approval_candidate = True ;
- access_token et refresh_token renvoyés ;
- frontend redirige vers /activation-pending.
```

Le signup OTP prouve le contrôle du numéro.
Il ne donne pas automatiquement les rôles métier Tickets Carburant.

Le device doit rester en attente d’approbation back-office avant les actions sensibles.

---

## 12. Demande de compte account.request

Le flux signup peut créer une `acpec.mobile.auth.account.request`.

Patch42C finalise cette demande lorsque le signup OTP réussit.

Choix retenu :

```text
Si account.request est pending :
- écrire state = approved ;
- renseigner reviewed_at ;
- ne pas appeler action_approve().
```

Interdit dans Patch42C :

```text
account_request.action_approve()
```

Raison :

```text
action_approve()
- peut passer l’utilisateur en mobile_state = approved ;
- peut appliquer des groupes ;
- mélange validation de compte et validation device ;
- contourne la doctrine pending_trust.
```

Patch42C doit garder l’utilisateur en :

```text
mobile_state = self_registered
device_trust_state = pending_trust
```

Le back-office doit voir une file utile : les devices à approuver.
Il ne doit pas rester des demandes de compte fantômes en `pending` pour un signup déjà finalisé.

---

## 13. Frontend Flutter

Le frontend Flutter doit envoyer, au moment de `verifySignupOtp` :

```text
purpose = register
device_uid
device_name
platform
app_version
```

Exemple attendu :

```text
device_uid  = ft-android-...
device_name = Flutter Android
platform    = android
app_version = dev ou version réelle
```

Le backend Patch42C et le frontend envoyant `device_uid` doivent être livrés ensemble.
Backend seul sans frontend casse l’inscription mobile.

---

## 14. Écran pending

Le flux nominal après signup OTP réussi est :

```text
/activation-pending
```

`/signup/pending` n’est pas le flux nominal Patch42C.

Règle frontend :

```text
Si le backend ne renvoie pas une session exploitable après signup OTP :
- fail-closed ;
- message d’erreur explicite ;
- ne pas revenir silencieusement à /signup/pending.
```

---

## 15. Matrice de comportement Patch42C

| Cas | Téléphone | User | Device UID | OTP consommé | Session | Payload public | Audit |
|---|---|---|---|---|---|---|---|
| Signup valide | Nouveau téléphone | Créé | Stable `ft-...` | Oui | Créée | Session + tokens | Non bloquant |
| Signup sans device_uid | Nouveau téléphone | Non créé | Absent | Non | Aucune | `SIGNUP_NOT_ALLOWED` | `mobile_signup_not_allowed` |
| Signup device_uid non stable | Nouveau téléphone | Non créé | Non stable | Non | Aucune | `SIGNUP_NOT_ALLOWED` | `mobile_signup_not_allowed` |
| Signup doublon compte | Téléphone existant | Existant | Stable | Selon logique existante | Aucune nouvelle session signup | `SIGNUP_NOT_ALLOWED` | `mobile_signup_not_allowed` |
| Signup réussi + account.request pending | Nouveau téléphone | Créé | Stable | Oui | Créée | Session + tokens | request clôturée approved |
| Même device autre user | Autre téléphone | Autre user | Même UID | Oui si login valide | Créée | Session | trust repart pending |
| Nouveau device même user | Même téléphone | Même user | Nouveau UID | Oui si login valide | Créée | Session | trust repart pending |

---

## 16. Tests attendus

Tests négatifs :

```text
1. register OTP sans device_uid stable :
   - payload public SIGNUP_NOT_ALLOWED ;
   - message public français générique ;
   - audit back-office avec debug_reason technique anglais ;
   - company_id renseignée dans l’audit ;
   - aucun user créé ;
   - aucune account.request créée ;
   - aucune session créée ;
   - OTP non consommé et challenge réutilisable avec device_uid stable.

2. duplicate account :
   - le test doit fournir un device_uid stable ;
   - sinon il teste le mauvais cas, celui du payload incomplet ;
   - le résultat attendu reste SIGNUP_NOT_ALLOWED ;
   - l’audit doit indiquer le vrai motif duplicate/account_exists.
```

Tests positifs :

```text
1. signup OTP avec device_uid stable :
   - user self_registered ;
   - login = mobile_phone = téléphone local 8 chiffres ;
   - access_token présent ;
   - refresh_token présent ;
   - session_ref présent ;
   - device_uid dans la session ;
   - device_trust_state = pending_trust ;
   - is_device_approval_candidate = True ;
   - account.request pending devient approved sans action_approve().
```

Tests frontend :

```text
verifySignupOtp envoie :
- purpose=register ;
- device_uid ;
- device_name ;
- platform ;
- app_version.
```

---

## 17. Critères de validation Patch42C

Patch42C est considéré valide si :

```text
1. Signup OTP sans device_uid stable refuse avant challenge.verify(code).
2. Le refus public utilise SIGNUP_NOT_ALLOWED.
3. Aucun code public spécifique exposant l’absence de device_uid n’est introduit.
4. Le message public est français et générique.
5. Le motif technique est en anglais dans l’audit back-office.
6. L’audit back-office contient company_id.
7. Aucun user, aucune account.request, aucune session ne sont créés dans le cas négatif.
8. Le même challenge reste vérifiable ensuite avec device_uid stable.
9. Signup OTP avec device_uid stable crée user + session + tokens.
10. La session est pending_trust et candidate approbation.
11. account.request pending devient approved sans action_approve().
12. Frontend envoie device_uid dans verifySignupOtp.
13. Le flux nominal va vers /activation-pending.
14. Aucun flux nominal ne dépend de /signup/pending.
```

---

## 18. Hors périmètre Patch42C

Patch42C ne doit pas embarquer :

```text
- refus dur des devices blocked au login si non déjà livré par le code courant ;
- action back-office de changement de téléphone ;
- refonte identité personne/numéro ;
- séparation avancée SIM/personne ;
- nettoyage global des anciens tests SMS hors périmètre ;
- remplacement général de tous les usages de ir.config_parameter ;
- modification de res.partner.phone ;
- renommage technique des modèles/champs.
```

Ces sujets peuvent être documentés comme décisions ouvertes ou patches futurs, mais ne doivent pas polluer Patch42C.

---

## 19. Règle de release

Patch42C backend et le patch Flutter `verifySignupOtp` doivent être déployés ensemble.

Ordre interdit :

```text
1. déployer backend Patch42C ;
2. garder un frontend qui n’envoie pas device_uid ;
3. tenter inscription mobile.
```

Résultat attendu de cet ordre interdit :

```text
SIGNUP_NOT_ALLOWED
audit : register_otp_missing_or_unstable_device_uid_before_otp_consumption
aucun compte créé
```

Ordre correct :

```text
1. backend Patch42C ;
2. frontend signup qui envoie device_uid ;
3. test inscription mobile sur device réel ou émulateur Android ;
4. vérification back-office du device pending_trust ;
5. approbation device ;
6. test actions sensibles.
```

---

## 20. Synthèse finale

Patch42C fixe le trou fonctionnel suivant :

```text
Avant :
OTP register pouvait créer un compte sans session exploitable et sans device_uid,
ce qui cassait le workflow d’activation device.

Après :
OTP register exige un device_uid stable, crée immédiatement une session pending_trust,
retourne les tokens, et alimente la file back-office d’approbation device.
```

La règle clé est :

```text
Pas de device_uid stable => pas de consommation OTP, pas de user, pas de session,
payload public SIGNUP_NOT_ALLOWED, détail technique en audit back-office.
```

---

## 21. Additif Patch42D — validations register avant consommation OTP

Patch42D complète l’atomicité Patch42C.

Règle ajoutée :

```text
Pour purpose = register, les validations payload bloquantes connues doivent être faites avant challenge.verify(code).
```

Ordre cible :

```text
1. lire name, secret_code, company_id et device_uid ;
2. déterminer la société d’audit si company_id est fourni ;
3. refuser device_uid absent/non stable avant consommation OTP ;
4. refuser name manquant avant consommation OTP ;
5. refuser secret_code manquant ou invalide avant consommation OTP ;
6. résoudre la société cible avant consommation OTP ;
7. seulement ensuite appeler challenge.verify(code).
```

Règle d’implémentation :

```text
Aucune validation pre-verify ne doit laisser remonter une exception non capturée.
Les erreurs contrôlées doivent être retournées par réponse JSON.
Les refus signup audités doivent passer par _mobile_signup_not_allowed_response(...) afin de préserver l’audit back-office avant le return.
Pas de raise volontaire dans le flux contrôleur.
Pas d’assert runtime dans le flux contrôleur.
```

Effet attendu :

```text
Un OTP register valide ne doit pas être consommé si le payload register est incomplet ou invalide.
Le même challenge doit rester réutilisable après correction du payload.
```

Patch42D ne change pas la doctrine account.request de Patch42C :

```text
account.request.state = approved signifie demande traitée/clôturée,
tandis que res.users.acpec_mobile_state = self_registered signifie compte créé mais accès métier non encore approuvé.
```

Correction complémentaire figée par Patch42D :

```text
account.request.name est une référence technique générée par séquence et doit rester unique.
Le nom humain du client doit être stocké dans account.request.name_display.
Deux clients peuvent avoir le même nom humain.
L'identité métier mobile repose sur signup_identifier / phone / login.
```
