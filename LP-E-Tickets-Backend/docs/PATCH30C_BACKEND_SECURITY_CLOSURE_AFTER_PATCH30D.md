# Patch30C - Cloture backend securite mobile V1 apres Patch30D

## Statut

Patch30C est une cloture documentaire apres stabilisation de la securite mobile backend V1.

Point stable actuel :

- branche stable : main
- tag stable : security-runtime-v1-20260621-patch30D
- merge commit : 395529f
- patch commit : c6d1f7e

Patch30D devient la reference fonctionnelle pour le runtime securite mobile V1.

## Doctrine reset PIN mobile

Le reset PIN mobile est ratifie via le flux OTP public existant :

verify-otp + purpose='reset' + secret_code

Cette decision est volontaire. L'exigence d'une session Bearer existante a ete abandonnee, car elle n'ajoute pas de barriere reelle contre un attaquant possedant deja l'OTP SMS. Un OTP de login peut deja creer une session mobile sur un nouveau device en etat pending_trust.

La vraie barriere contre les actions sensibles reste le device trust, pas la simple possession d'une session.

## Separation des secrets

Regle non negociable :

secret_code = creation, initialisation et reset du PIN mobile
action_code = confirmation d'une action sensible

Consequences :

- secret_code est reserve aux flux setup/reset PIN.
- action_code est requis pour les actions sensibles.
- action_pin, pin, secret_code et autres alias ne doivent jamais etre acceptes comme preuve d'une action sensible.
- Le reset PIN rejette action_code, action_pin, pin et new_pin.

## Ordre de validation reset PIN

Le backend doit valider le nouveau secret_code avant de consommer l'OTP.

Objectif :

Un PIN absent, aliase ou malforme ne doit jamais bruler un OTP valide.

Sequence correcte :

1. charger le challenge OTP ;
2. si purpose == reset, rejeter les alias interdits ;
3. verifier la presence de secret_code ;
4. valider le format du secret_code ;
5. seulement ensuite appeler challenge.verify(code) ;
6. appeler user.set_mobile_pin(secret_code) ;
7. retourner une session mobile soumise au trust state normal.

## Non-escalade apres reset PIN

Le reset PIN ne valide aucune operation economique.

Apres reset PIN :

- un nouveau device reste pending_trust ;
- une session issue d'un reset PIN ne contourne pas le device-trust gate ;
- aucune action sensible ne peut etre executee tant que le device n'est pas trusted ;
- les actions sensibles continuent d'exiger action_code, idempotency key, device trusted et hash serveur.

Le reset PIN n'est donc pas une preuve forte anti-SIM-swap. C'est un mecanisme de recuperation de PIN. La protection contre SIM-swap reste portee par le controle trusted device et par la validation back-office des devices.

## Reset PIN back-office

Le back-office peut forcer une reinitialisation PIN via une action administrative.

Cette action :

- efface les champs mobile_pin_* ;
- positionne mobile_pin_required=True ;
- remet les compteurs et locks a zero ;
- ne definit jamais un nouveau PIN pour l'utilisateur.

Le PIN reste choisi par l'utilisateur mobile via le flux OTP reset.

## Audit transfert mobile

L'audit mobile du transfert de carnets est porte par acpec_fueltoken_api, pas par acpec_fueltoken_core.

Architecture retenue :

acpec_fueltoken_core :
- reste mobile-agnostic ;
- ne connait pas mobile_session_id ;
- ne connait pas device_uid ;
- expose action_confirm(actor_user=...).

acpec_fueltoken_api :
- ajoute action_confirm_mobile() ;
- enveloppe action_confirm(actor_user=...) ;
- ecrit l'audit mobile sur le transfert ;
- ecrit l'audit mobile sur les transactions generees.

Champs d'audit ajoutes cote API :

Sur acpec.fuel.carnet.transfer :
- mobile_session_id
- device_uid

Sur acpec.fuel.transaction :
- actor_user_id
- mobile_session_id
- device_uid

L'ecriture d'audit sur les transactions utilise le contexte controle :

allow_fuel_transaction_update=True

Ce contexte correspond au garde append-only existant des transactions.

## Acteur strict dans core

Le seul durcissement accepte dans acpec_fueltoken_core est l'acteur strict.

Regle :

Sous sudo, actor_user absent => erreur.
Hors sudo, fallback env.user.

Ce changement ameliore la tracabilite sans introduire de dependance mobile dans le core.

## Tests de non-regression

Les tests valides couvrent notamment :

- reset admin efface le PIN sans definir un nouveau PIN ;
- hard block PIN puis reset via verify-otp purpose='reset' ;
- rejet comportemental de action_code, action_pin, pin, new_pin sur reset PIN ;
- absence de consommation OTP si alias ou secret_code malforme ;
- reutilisation possible du meme OTP apres correction du secret_code ;
- purpose='login' avec secret_code ne modifie pas le PIN ;
- audit transfert mobile sur transfert et transactions ;
- absence de couplage mobile dans acpec_fueltoken_core.

## Garde-fous de cloture

Avant tout tag ou merge futur lie a cette zone, executer :

git diff --check

grep -RIn "mobile_session\|device_uid\|action_confirm_mobile" addons/acpec_fueltoken_core

grep -RIn "get_module_path\|open(module_path\|with open" addons/acpec_mobile_auth_otp/tests/test_mobile_pin_reset_otp.py

Critere de stabilite :

- 0 failed, 0 error(s)
- aucun mobile_session/device_uid dans core
- aucun test source-file factice
- diff sans churn CRLF

## Conclusion

Patch30D cloture le runtime securite mobile backend V1 avec :

- reset PIN recuperable par OTP ;
- separation stricte secret_code / action_code ;
- device trust conserve comme barriere des actions sensibles ;
- audit mobile des transferts hors core ;
- core mobile-agnostic ;
- tests comportementaux de non-regression.

Patch30C documente cette decision comme doctrine stable.
