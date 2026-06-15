# ACPEC Mobile Auth

Module d’authentification mobile ACPEC.

## Doctrine d’authentification mobile

Le login mobile normal est :

    OTP -> access_token / refresh_token

Le `secret_code` est un PIN de confirmation mobile à 4 chiffres. Il ne doit jamais être utilisé comme mot de passe Odoo (`res.users.password`).

Pour les comptes mobiles créés par l’API, Odoo reçoit un mot de passe aléatoire long et inutilisable par l’utilisateur. Le PIN est stocké séparément sous forme hashée dans les champs dédiés `mobile_pin_hash` / `mobile_pin_salt`.

## Migration des anciens comptes mobiles

Les anciens comptes pour lesquels le PIN était implicitement le mot de passe Odoo ne sont pas migrables vers `mobile_pin_hash`, car le PIN clair n’est pas disponible.

La migration marque uniquement les utilisateurs mobile-only comme nécessitant une nouvelle définition de PIN :

    mobile_pin_set = False
    mobile_pin_required = True

Elle remplace aussi leur mot de passe Odoo par une valeur aléatoire longue, afin que `/web/login` ne soit jamais utilisable avec un PIN à 4 chiffres.

## Vérification du PIN

La méthode `check_mobile_pin()` existe pour les prochains patches d’enforcement côté serveur. Elle doit être appelée uniquement après une authentification mobile Bearer valide et dans le contexte d’une action sensible concrète.

Ne pas créer d’endpoint public générique `/verify-pin`.
