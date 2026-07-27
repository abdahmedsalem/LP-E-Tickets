# 05 - PIN local et auto-lock

## Portée

Ce module définit le PIN local, la biométrie, la confirmation des actions sensibles et l'auto-lock.

Lire avec `00_decisions_invariants.md`.

## 5.1 Nature du PIN

Le PIN local n'est pas une authentification serveur.

```text
Le backend ne connaît pas le PIN.
Le PIN n'est jamais envoyé au backend.
Le PIN n'est jamais stocké en clair.
```

Stockage attendu :

```text
hash local + salt + secure storage
ou mécanisme équivalent Android Keystore / iOS Keychain.
```

## 5.2 Déverrouillage local

Si session longue serveur valide, l'utilisateur déverrouille par PIN ou biométrie au lieu de refaire OTP.

```text
Session longue valide + pas logout volontaire = PIN local, pas OTP.
```

## 5.3 Confirmation action sensible

Toute opération sensible redemande le PIN, même si l'utilisateur vient de déverrouiller l'application.

```text
Déverrouiller l'application != confirmer une opération sensible.
```

## 5.4 Limites du PIN

Le PIN local ne protège pas contre :

```text
token volé ;
client mobile modifié ;
SIM swap ;
nouveau device enrôlé par OTP.
```

Donc :

```text
PIN correct != autorisation serveur.
```

Le backend reste juge final.

## 5.5 Auto-lock

L'application se verrouille automatiquement après inactivité.

Exemple :

```text
auto_lock_seconds = 300
```

Workflow :

```text
1. User authentifié.
2. Inactivité >= délai configuré.
3. App revient à l'écran verrouillé.
4. Aucune donnée sensible affichée.
5. User saisit PIN ou biométrie.
6. Si session serveur valide : retour app.
7. Si session expirée : retour OTP.
```

Auto-lock ne révoque pas la session serveur.

## 5.6 Tests minimum

```text
- refresh token local présent -> écran PIN ;
- PIN absent après session restaurée -> création PIN, pas logout serveur ;
- auto-lock masque données sensibles ;
- opération sensible redemande PIN ;
- PIN correct ne saute pas les checks backend ;
- PIN échecs répétés -> politique locale appliquée.
```
