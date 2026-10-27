# LP E-Tickets — backend de test

Prérequis : Docker avec Docker Compose. Le premier démarrage télécharge PostgreSQL 15 ; une connexion Internet est nécessaire.

## Tester l’image GitLab

Depuis ce dossier (image AMD64 exécutée aussi sur Mac Apple Silicon) :

```bash
docker compose -f compose.yaml -f compose.gitlab.yaml pull
docker compose -f compose.yaml -f compose.gitlab.yaml up -d
docker compose -f compose.yaml -f compose.gitlab.yaml logs -f odoo
```

Cette configuration utilise le tag `latest` de GitLab, le port local 8079
et les volumes dédiés au projet `lp-etickets-backend-test`.
Le code provient de l’image téléchargée ; les modifications locales du dépôt
ne sont pas montées dans ce conteneur.

## PC Intel/AMD (Linux ou Docker Desktop Windows/Mac Intel)

Depuis ce dossier :

```bash
docker load -i lp-etickets-backend-1.0-amd64.tar.gz
docker compose up -d
docker compose logs -f odoo
```

## Mac Apple Silicon / Linux ARM64

```bash
docker load -i lp-etickets-backend-1.0-arm64.tar.gz
docker compose -f compose.yaml -f compose.arm64.yaml up -d
docker compose logs -f odoo
```

Attendre le message `Modules loaded` lors du premier démarrage.

- Odoo : http://localhost:8079/web/login
- Console de test API : http://localhost:8079/acpec/fueltoken/test
- Base : `lp-etickets-test`
- Identifiant Odoo : `admin`
- Mot de passe Odoo initial : `admin`

Ces identifiants et la configuration sont réservés au test local. Le port est limité à localhost. Les tâches planifiées sont désactivées.

Le démarrage initialise une base neuve et installe les modules API, console de test, portail sociétés, rapports et suppression de compte, avec leurs dépendances. Les images contiennent tous les modules du dossier addons au moment du build. Elles ne contiennent pas la base locale, ses pièces jointes ou sa configuration SMS. Créer les données métier et configurer le fournisseur OTP selon les tests souhaités ; aucun accès à la production n'est préconfiguré.

Les données persistent dans des volumes dédiés. Pour arrêter sans les effacer :

```bash
docker compose stop
```

Pour reconstruire depuis la racine du dépôt :

```bash
docker buildx build --platform linux/amd64 -t lp-etickets-backend:1.0-amd64 --load ./LP-E-Tickets-Backend
docker buildx build --platform linux/arm64 -t lp-etickets-backend:1.0-arm64 --load ./LP-E-Tickets-Backend
```

Pour partager, envoyer le fichier image de l'architecture choisie avec `compose.yaml`, ce README et, pour ARM64, `compose.arm64.yaml`.

## Vérifications effectuées

Le 28 septembre 2026 : installation sur bases neuves réussie pour ARM64 et AMD64 (45 modules avec dépendances). Sur ARM64 : page de connexion et console API HTTP 200, authentification admin réussie. Intégrité gzip des deux archives vérifiée ; empreintes dans `SHA256SUMS`. Les parcours métier complets et les envois SMS ne sont pas couverts par ces vérifications.
