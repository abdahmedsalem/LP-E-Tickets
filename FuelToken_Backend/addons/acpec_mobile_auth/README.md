# ACPEC Mobile Auth

Module d’authentification mobile ACPEC.

La version actuelle conserve une authentification par identifiant et code secret/mot de passe.
Cette couche est volontairement isolée afin de pouvoir remplacer plus tard le mécanisme par OTP sans modifier le cœur FuelToken.

Mobile app/API
- group_fuel_user      = mobile client
- group_fuel_station   = mobile station
- group_fuel_manager   = mobile gestionnaire

Back-office Odoo ACPEC
- group_fuel_admin     = admin / gestionnaire back-office FuelToken

Société portail
- base.group_portal
- acpec.fuel.distributor actif
- aucun groupe FuelToken mobile/back-office

Patch 1 — mobile-only users
- retirer base.group_portal des créations mobiles ;
- ne pas donner base.group_public ;
- mobile signup = groupes mobiles FuelToken seulement ;
- ajouter garde-fou mobile ≠ portal.

Patch 2 — séparation groupes
- group_fuel_user / station / manager = mobile app/API ;
- group_fuel_admin = back-office ACPEC ;
- retirer group_fuel_manager des menus/ACL back-office ;
- revoir l’héritage group_fuel_admin → group_fuel_manager.