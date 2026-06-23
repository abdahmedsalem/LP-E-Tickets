# Patch37A — Code QR numérique 12 chiffres

Date : 2026-06-23
Projet : Tickets Carburant / FuelToken
Périmètre : backend QR actif, API mobile, API station

## 1. Décision fonctionnelle

Le QR actif possède désormais deux représentations de validation :

- QR graphique : représentation scannable par caméra.
- Code QR numérique : représentation numérique saisissable manuellement.

Le Code QR numérique n'est pas un code station et n'est pas un mécanisme séparé.
Il identifie le même QR actif que le QR graphique.

Libellé utilisateur retenu :

- Code QR numérique

Format affiché :

- 12 chiffres groupés 4-4-4
- Exemple : 9873-9484-9383

Valeur normalisée :

- 987394849383

## 2. Règle de consommation

Au moment de la consommation, la station peut :

- scanner le QR graphique ;
- ou saisir le Code QR numérique.

Les deux modes résolvent le même enregistrement acpec.fuel.qr.

La consommation reste centralisée dans :

- acpec.fuel.qr.action_consume_by_station(...)

Donc les protections existantes restent valables :

- station autorisée ;
- société station = société QR ;
- session mobile station valide ;
- device trusted ;
- action_code obligatoire ;
- idempotency_key obligatoire ;
- verrou FOR UPDATE sur le QR ;
- usage unique ;
- anti double consommation ;
- audit transaction consommation_station.

## 3. Stockage sécurité

Le Code QR numérique n'est pas stocké en clair.

Champ ajouté :

- qr_numeric_code_hash

Libellé Odoo :

- Empreinte du Code QR numérique

Le code affichable est dérivé côté serveur à partir du public_code, d'un paramètre interne non secret et d'un secret serveur.
L'empreinte de recherche est aussi calculée côté serveur.
En cas de collision, le paramètre interne est régénéré pour obtenir un Code QR numérique unique.

Cette approche permet :

- de ne pas stocker le code en clair ;
- de réafficher le Code QR numérique dans les payloads mobile ;
- de rechercher rapidement le QR depuis une saisie station.

Point d'attention production :

- le secret serveur utilisé pour dériver le Code QR numérique doit rester stable pendant la durée de vie des QR actifs ;
- le paramètre interne du Code QR numérique doit être conservé avec le QR ;
- si le secret change, les QR actifs peuvent conserver leur QR graphique, mais leur Code QR numérique dérivé peut changer ;
- en V1, ce risque est acceptable si les QR ont une durée de vie courte, mais il doit être connu.

## 4. Contrat API mobile

Les payloads QR mobile exposent désormais :

- public_code
- qr_numeric_code

Exemple conceptuel :

- public_code : QR-...
- qr_numeric_code : 9873-9484-9383

Le champ qr_numeric_code_hash n'est jamais exposé dans les payloads mobile.

## 5. Contrat API station

Les endpoints station existants sont conservés :

- /api/acpec/fueltoken/v1/station/qr/check
- /api/acpec/fueltoken/v1/station/qr/use

Ils acceptent désormais exactement une des deux références :

- public_code
- qr_numeric_code

Si les deux sont fournis, la requête est rejetée.

Si aucun des deux n'est fourni, la requête est rejetée.

La résolution du QR se fait avant l'appel à action_consume_by_station(...).
Après résolution, le flux métier est identique à une consommation par QR graphique.

## 6. Erreurs publiques

Le message public ne doit pas exposer de détails techniques inutiles.

Terminologie publique retenue :

- QR graphique
- Code QR numérique

Termes à éviter en UI normale :

- public_code
- qr_numeric_code
- hash
- token
- empreinte, sauf dans les vues techniques/back-office.

## 7. Tests Patch37A

Tests ciblés validés :

- TestQrIssueRuntimePolicy
- TestStationQrUseRuntimePolicy
- TestConsumeStationGuard

Résultat ciblé :

- 19 post-tests
- 0 failed
- 0 error(s)

Cas couverts :

- génération du Code QR numérique lors de l'émission QR ;
- format 4-4-4 ;
- non-exposition de l'empreinte dans le payload ;
- check station par Code QR numérique ;
- consommation station par Code QR numérique ;
- rejet du mélange QR graphique + Code QR numérique ;
- conservation des protections action_code, device trust, idempotency et anti double consommation.
