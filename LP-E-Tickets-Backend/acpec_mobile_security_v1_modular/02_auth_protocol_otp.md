# 02 - Protocole d'authentification mobile et OTP

## Portée

Ce module définit le login téléphone-only, l'OTP, les workflows de premier login, de relance normale et d'erreur réseau.

Lire avec `00_decisions_invariants.md`, `03_sessions_tokens.md`, `04_device_trust_stepup.md` et `05_pin_autolock.md` selon la tâche.

## 2.1 Login téléphone-only

Le login mobile se fait uniquement par téléphone.

Interdit :

```text
email comme identifiant mobile ;
identifiant contenant @ ;
préremplissage frontend par email.
```

Frontend :

```text
- afficher que le login attendu est un numéro de téléphone ;
- ne jamais préremplir avec email ;
- refuser/nettoyer tout identifiant contenant @.
```

Backend :

```text
- refuser tout identifiant contenant @ ;
- rechercher par téléphone mobile ;
- ne jamais utiliser email comme identifiant OTP mobile.
```

## 2.2 Rôle de l'OTP

```text
OTP = création ou restauration de session serveur.
PIN = déverrouillage local d'une session existante.
```

OTP ne doit pas être demandé à chaque relance normale si un refresh token valide existe.

OTP SMS n'est pas un step-up contre SIM swap ou nouveau device. Voir module 04.

## 2.3 Sécurité OTP

OTP ne doit pas être stocké en clair.

Le hash OTP n'est pas une protection forte en soi, car un OTP 6 chiffres est bruteforçable si la base fuite.

Protections obligatoires :

```text
expiration courte ;
usage unique ;
nombre maximal de tentatives ;
rate limit ;
anti-flood ;
journalisation.
```

## 2.4 Réponse non énumérante

`request-otp` ne doit pas révéler si le téléphone existe.

Réponse recommandée :

```text
Si ce numéro est éligible, un code sera envoyé.
```

Le backend peut ne rien envoyer si le téléphone est inconnu, mais la réponse API reste similaire.

## 2.5 Workflow premier login

```text
1. App ouverte.
2. Aucune session locale exploitable.
3. Écran téléphone.
4. Saisie numéro.
5. Appel request-otp.
6. Backend vérifie :
   - identifiant = téléphone ;
   - pas d'email ;
   - user mobile enabled ;
   - user non blocked ;
   - user portal-type ;
   - user non internal ;
   - user non public ;
   - user non admin back-office ;
   - rate limits OTP.
7. Backend génère OTP si éligible.
8. Réponse non énumérante.
9. Utilisateur saisit OTP.
10. Appel verify-otp.
11. Backend vérifie OTP correct, non expiré, non consommé, tentatives OK.
12. Backend crée/renouvelle session mobile.
13. App stocke tokens en secure storage.
14. Si PIN local absent : forcer création PIN.
15. Accès selon acpec_mobile_state et device_trust_state.
```

## 2.6 Workflow relance normale

Si refresh token local existe :

```text
1. App ouverte.
2. Session locale détectée.
3. Écran PIN / biométrie.
4. Déverrouillage local.
5. Appel /me ou /refresh.
6. Si session serveur valide : accès application.
7. Si session expirée/révoquée : effacement local puis retour OTP.
```

Règle :

```text
Session longue valide + pas logout volontaire = PIN local, pas OTP.
```

## 2.7 Erreur réseau

```text
Erreur réseau != logout.
Erreur réseau != refresh expiré.
Erreur réseau != session révoquée.
```

Comportement :

```text
1. App tente /me ou /refresh.
2. Réseau échoue.
3. Afficher erreur réseau.
4. Ne pas révoquer session serveur.
5. Ne pas effacer refresh token local automatiquement.
6. Permettre retry.
```

## 2.8 Tests minimum

```text
- téléphone accepté ;
- email refusé ;
- identifiant avec @ refusé ;
- réponse request-otp non énumérante ;
- OTP expiré refusé ;
- OTP déjà utilisé refusé ;
- OTP faux incrémente tentatives ;
- blocked user refuse request/verify ;
- erreur réseau ne logout pas ;
- relance normale utilise PIN, pas OTP.
```
