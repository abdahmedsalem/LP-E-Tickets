# FuelToken mobile notifications scope

## V1 — local notifications

The mobile app currently uses local notifications via `flutter_local_notifications`.

Station consumption notifications are detected by the client app through transaction polling / app resume sync. This means the notification is delivered when the app is running, resumes, or refreshes its data. It is not a guaranteed server push when the app process is killed.

Expected station-consumption local notification:

- Title: `QR NNNN-NNNN-NNNN consommé`
- Body: `<amount> utilisés à <station>`

The notification must be deduplicated by station consumption transaction id.

## V2 — Firebase / Google push notifications

Open item: add true server push with Firebase Cloud Messaging / Google FCM.

Target behavior: when a station consumes a QR, the backend notifies the QR owner even if the app is closed.

Required V2 design:

- Register FCM token per trusted mobile device.
- Bind token to `stable_device_uid`, user, partner and company.
- Add backend register/unregister token endpoints.
- Send best-effort FCM notification after successful station consumption transaction.
- Deduplicate by transaction id.
- Audit sent / failed / no_token.
- Never block station consumption because push delivery failed.
- Notification tap should open QR detail or transaction history.
