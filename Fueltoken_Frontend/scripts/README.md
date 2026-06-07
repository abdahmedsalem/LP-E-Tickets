# FuelToken Scripts

## Start the app

| File | Platform |
| --- | --- |
| `run.sh` | macOS / Linux / Git Bash |
| `run.cmd` | Windows CMD |
| `run.ps1` | Windows PowerShell |
| `run_web.cmd` | Windows, publish the web app on the local Wi-Fi |
| `setup_env.cmd` | Windows, create `scripts\env\flutter.mobile.env` if missing |

### First time

1. Run `flutter pub get`.
2. Check `scripts/env/flutter.mobile.env`.
3. Start the app from the project root:
   - Windows CMD: `scripts\run.cmd`
   - Windows PowerShell: `.\scripts\run.ps1`
   - macOS/Linux: `./scripts/run.sh`

If `scripts/env` is empty, run `git pull` and then `scripts\setup_env.cmd`.

### Build release

Examples:

```bash
./scripts/run.sh build apk --release
./scripts/run.sh build appbundle --release
./scripts/run.sh build ipa --release
```

Windows PowerShell:

```powershell
.\scripts\run.ps1 build apk --release
```

### Web on local Wi-Fi

To share the app with devices on the same Wi-Fi:

1. Install Node.js if it is not already installed.
2. From the project root, run:

```powershell
scripts\run_web.cmd
```

The script:
- builds the Flutter web app
- starts a local server on port `8091`
- prints a shareable URL like `http://PC_IP:8091`
- proxies `/api/acpec/*` to the Odoo server configured in `scripts/env/flutter.mobile.env`

Share the printed LAN URL with the other devices on the same Wi-Fi.
