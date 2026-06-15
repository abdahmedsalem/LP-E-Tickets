# Audit OTP, inscription et recuperation de mot de passe

Date: 2026-06-15

## Portee

Audit base sur le frontend Flutter present dans ce depot et sur le contrat d'API documente dans `docs/`.

### Fichiers frontend audites

- `lib/data/services/odoo_auth_service.dart`
- `lib/features/auth/screens/register_screen.dart`
- `lib/features/auth/screens/register_verify_otp_screen.dart`
- `lib/features/auth/screens/forgot_password_screen.dart`
- `lib/features/auth/screens/forgot_otp_flow_screens.dart`
- `lib/features/auth/bloc/auth_bloc.dart`
- `lib/data/repositories/auth_repository.dart`
- `lib/core/config/odoo_auth_rpc_config.dart`
- `lib/core/config/app_api_config.dart`

### References API / contrat

- `docs/odoo_acpec_api_catalog.json`
- `docs/ODOO_JSONRPC_INTEGRATION.md`
- `docs/ACPEC_LIVE_WORKFLOW.md`
- `docs/PRODUCTION_STEPS.md`

## Conclusion courte

Le flux OTP d'inscription est correctement branche cote frontend pour la demande et la verification.

Le flux OTP de recuperation de mot de passe est incomplet en mode live dans ce depot: la demande et la validation OTP existent, mais la definition du nouveau mot de passe ne met pas a jour le backend. Le code actuel ne modifie que le stockage local `AuthRepository`.

Le depot ne contient pas le backend serveur lui-meme, donc l'audit backend est limite au contrat documente et aux attentes du client Flutter. Je ne peux pas certifier l'implementation serveur sans le code backend ou les logs Odoo.

## Flux OTP d'inscription

### Ce qui est correctement branche

- L'ecran d'inscription declenche bien une demande OTP via `OdooAuthService.instance.requestSignupOtp(...)`.
- La route utilisee est `ODOO_RPC_REQUEST_OTP_PATH`, par defaut `/api/acpec/mobile_auth/v1/request-otp`.
- Le payload contient:
  - `identifier`
  - `purpose: 'register'`
- Le retour normalise les champs `otp_challenge_id`, `otp_challenge_ref`, `otp_expires_at`, `otp_delivery`.
- L'ecran OTP d'inscription verifie le code avec `verifySignupOtp(...)`.
- Apres validation, l'ecran declenche `AuthSessionEstablished(user)`.

### Point faible important

- Apres validation OTP, le frontend n'appelle pas de mecanisme explicite de persistance de session ou de jetons.
- Le bloc `AuthBloc` ne recoit que `AuthSessionEstablished(user)`, pas `AuthRemoteRegistrationCompleted`.
- Dans ce depot, cela signifie surtout que la finalisation durable est supposee etre geree par le backend Odoo lui-meme via sa session ou ses jetons, mais ce comportement ne peut pas etre verifie ici.

### Risque

- Si le backend renvoie des tokens JWT ou necessite une action de completion supplementaire, le frontend ne les sauvegarde pas dans le flux d'inscription actuel.
- Le code `AuthRemoteRegistrationCompleted` et `AuthRepository.adoptRemoteUser(...)` existent, mais ne sont pas utilises par l'ecran d'inscription actuel.

### Statut

- Demande OTP: OK
- Validation OTP: OK
- Finalisation durable du compte/session: a verifier cote backend, frontend insuffisamment explicite

## Flux recuperation de mot de passe

### Ce qui est correctement branche

- L'ecran de demande envoie une requete OTP via `requestPasswordResetOtp(...)`.
- La route utilisee est `ODOO_RPC_REQUEST_OTP_PATH`.
- Le payload contient:
  - `identifier`
  - `purpose: 'forgot_password'`
- L'ecran de verification OTP envoie `verifyPasswordResetOtp(...)`.
- La navigation vers l'ecran de nouveau mot de passe est bien enchainee apres validation.

### Probleme bloquant

- L'ecran `ResetPasswordAfterOtpScreen` applique le nouveau mot de passe via:
  - `AuthRepository.instance.resetPasswordForIdentifier(...)`
  - `AuthRepository.instance.syncLocalPasswordIfExists(...)`
- Ces methodes ne modifient que l'etat local en memoire.
- Il n'existe pas de mutation backend correspondante dans le flux actuel de ce depot.

### Consequence

- En mode live Odoo / ACPEC, la reinitialisation du mot de passe n'est pas appliquee cote backend dans ce depot.
- Le flux peut afficher un succes local, puis l'utilisateur echouera ensuite a se reconnecter si le backend ne fournit pas une mutation equivalente.

### Statut

- Demande OTP: OK
- Validation OTP: OK
- Definition du nouveau mot de passe cote backend: non couverte
- Securite metier du reset: insuffisante en live

## Verification des scenarios

### 1. Inscription

- Numero local valide par `validateMrLocalPhone`.
- Conversion en format international `+222XXXXXXXX`.
- Demande OTP envoyee.
- Saisie OTP verifiee.
- Connexion en memoire declenchee.

Verdict:

- Fonctionnel pour un parcours UI.
- Persistant / backend durable: a confirmer.

### 2. Renvoyer OTP inscription

- Present via `requestSignupOtpResend(...)`.
- Le `challengeId` est mis a jour si le backend en renvoie un nouveau.

Verdict:

- Correct sur le principe.
- Pas de backoff ni de throttling cote UI.

### 3. Reinitialisation mot de passe

- Demande OTP: OK.
- Verification OTP: OK.
- Nouveau mot de passe: local-only.

Verdict:

- Parcours incomplet pour le live.

### 4. Renvoyer OTP recuperation

- Present via `requestPasswordResetOtp(...)`.

Verdict:

- Correct sur le plan frontend.
- La validite metier depend entierement du backend.

### 5. Connexion apres inscription / reset

- L'application s'appuie sur `AuthBloc` et eventuellement sur la session Odoo / stockage local.
- Si le backend n'a pas cree ou maintenu la session, la persistance peut etre instable.

Verdict:

- Risque de faux positif UX.

## Points techniques observes

### Routes et contrat

- Le client attend:
  - `/api/acpec/mobile_auth/v1/request-otp`
  - `/api/acpec/mobile_auth/v1/verify-otp`
  - `/api/acpec/mobile_auth/v1/signup`
- Ces routes existent dans la config par defaut et dans le catalogue Odoo documente.

### Drapeaux d'environnement

- `ODOO_USE_ACPEC_AUTH=true` est requis pour activer les routes OTP / auth.
- `ODOO_JSONRPC_BASE_URL` est requis pour la base Odoo.
- `API_BASE_URL` / `OTP_API_BASE_URL` existent encore dans la configuration, mais le flux OTP audite ne depend pas de ce service dans le code courant.

### Incoherence documentaire

- `docs/ODOO_JSONRPC_INTEGRATION.md` et `docs/PRODUCTION_STEPS.md` mentionnent encore un ancien modele REST OTP.
- Le code actuel du flux OTP d'inscription / reset utilise par l'app pointe vers Odoo JSON-RPC via `OdooAuthService`.

Impact:

- Risque de confusion lors du deploiement.
- Les operateurs peuvent configurer le mauvais backend pour l'OTP.

## Risques classes

### Critique

- Reinitialisation mot de passe non persistee cote backend.

### Haute

- Inscription OTP potentiellement non persistante si le backend ne pose pas lui-meme une session durable.

### Moyenne

- Pas de throttling / anti-spam visible sur les demandes OTP.
- Messages d'erreur parfois trop techniques et variables selon les ecrans.

### Faible

- Documentation restante sur l'ancien service OTP REST, susceptible de creer de la confusion.

## Recommandations

### A corriger en priorite

1. Brancher la reinitialisation du mot de passe sur une mutation backend reelle.
2. Clarifier le contrat de finalisation d'inscription:
   - soit le backend cree la session,
   - soit le frontend doit sauvegarder explicitement les jetons / session.
3. Reviser la documentation pour supprimer la confusion entre OTP JSON-RPC et ancien OTP REST.

### A securiser

1. Ajouter une expiration affichee et exploitee cote UI pour les challenges OTP.
2. Ajouter un throttling / delai minimum entre renvois OTP.
3. Normaliser tous les messages d'erreur utilisateur.

### A tester

1. Inscription avec OTP valide.
2. Inscription avec OTP expire.
3. Renvoyer OTP plusieurs fois.
4. Recuperation mot de passe avec OTP valide.
5. Recuperation mot de passe avec OTP expire.
6. Reconnexion apres reset sur backend live.

## Verdict final

Le frontend sait:

- declencher une demande OTP,
- envoyer les bons parametres,
- recevoir et reagir a la reponse,
- enchaîner vers l'ecran de verification.

Mais le systeme n'est pas encore totalement coherent en bout de chaine:

- l'inscription n'a pas de finalisation durable explicitement persistee cote client,
- la recuperation de mot de passe n'applique pas le changement cote backend,
- la documentation conserve des restes d'un ancien modele OTP REST qui n'est plus aligne avec le code actuel.
