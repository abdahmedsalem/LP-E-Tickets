# Variables d’environnement mobile

Après **clone** ou **pull**, ce dossier doit contenir :

| Fichier | Rôle |
| --- | --- |
| **`flutter.mobile.env`** | Lu par `run.sh` / `run.ps1` / `run.cmd` |
| **`flutter.mobile.example.env`** | Modèle (même contenu si besoin) |
| **`README.md`** | Ce fichier |

## Windows — le dossier `env` n’apparaît pas ?

1. Dans l’explorateur, ouvrez **`scripts`** puis **`env`** (pas seulement la racine du projet).
2. Dans le terminal, à la racine du projet (`pubspec.yaml` visible) :

```powershell
git pull
dir scripts\env
.\scripts\setup_env.cmd
.\scripts\run.cmd
```

Ne pas utiliser `./scripts/run.sh` dans **CMD** classique — préférez **`scripts\run.cmd`** ou PowerShell **`.\scripts\run.ps1`**.

## macOS / Linux

```bash
git pull
ls scripts/env/
./scripts/run.sh
```

## Surcharge personnelle (optionnel)

Fichier non versionné : **`flutter.mobile.local.env`** (écrase les valeurs de `flutter.mobile.env`).
