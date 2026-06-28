# Audit — Document de référence Flutter API FuelToken

## Verdict

Le document de référence API mobile est solide pour démarrer l’alignement Flutter. Il reflète le backend réel, couvre le transport JSON-RPC, les endpoints, les payloads, les codes d’erreur et les points ouverts.

Il manque principalement :
- une section environnement local Flutter ;
- une consigne explicite pour le nouveau chat/agent IA ;
- un lien plus fort avec `AGENTS.md` ;
- une séparation claire entre contrat backend réel, décisions Flutter et points ouverts.

## Points forts

- Le document rappelle que le contrat reflète le backend réel et qu’un champ non listé ne doit pas être inventé.
- Le transport JSON-RPC est explicite.
- La règle `result.ok` puis `result.error.code` est correcte.
- Les invariants `device_uid`, `device_trust_state`, `action_code`, `idempotency_key` sont bien présents.
- Les points ouverts `request-otp shape`, `ok/success`, `uid/id`, `qr_numeric_code` sont correctement signalés.

## Points à améliorer

### 1. Environnement

Ajouter dans la passation Flutter :

```powershell
cd D:\dev\github\fuelToken\Fueltoken_Frontend

flutter clean
flutter pub get

$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
& $adb reverse tcp:8019 tcp:8019
& $adb reverse --list

flutter run -d R5CY213Z12F
```

### 2. Base URL

Documenter explicitement :

```text
backend local PC : port 8019
appareil Android via adb reverse : http://127.0.0.1:8019
```

### 3. Rôle d’AGENTS.md

`AGENTS.md` doit porter les règles opérationnelles pour l’agent Flutter :
- ne pas inventer d’endpoint ;
- ne pas matcher `error.message` ;
- ne pas afficher `debug_reason` ;
- gérer `reference`;
- gérer `pending_trust`;
- gérer `request-otp` avec/sans `challenge_id`;
- lancer `flutter analyze` et `flutter test`.

### 4. Passation nouveau chat

Préparer un document séparé de passation synthétique. Il ne doit pas recopier tout le contrat API, mais indiquer quoi lire, quoi faire, quoi ne pas faire, et comment lancer l’environnement.

## Décision recommandée

Créer ou mettre à jour dans le repo Flutter :

```text
AGENTS.md
PASSATION_FLUTTER_API_CONTRACT.md
```

Aucun code Flutter ne doit être modifié dans cette étape documentaire.
