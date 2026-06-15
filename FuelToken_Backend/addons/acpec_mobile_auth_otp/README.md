# ACPEC Mobile Auth OTP

This module adds OTP challenge creation and verification for the ACPEC mobile authentication layer.


## OTP code length vs signup secret code

SMS OTP codes are 6 digits for the Chinguisoft validation API. When the hidden system parameter `acpec_mobile_auth.otp_code_length` is absent, the backend generates 6 digits.
This is intentionally separate from the signup confirmation `secret_code`, which remains exactly 4 digits and is validated by the base `acpec_mobile_auth` module.

Contract rule:

- `code` = SMS OTP received from Chinguisoft, exactly 6 digits.
- `secret_code` = mobile confirmation PIN chosen by the user, exactly 4 digits. It is stored as a dedicated mobile PIN hash and must never be used as `res.users.password`.

Do not validate the SMS OTP with the `secret_code` rule, and do not relax `secret_code` to 6 digits. The Odoo user password is generated as a long random unusable value; mobile login remains OTP -> Bearer tokens.

## OTP rate limits

The public OTP endpoints are protected against SMS pumping with sliding-window limits based on existing OTP challenges:

- same identifier / minute, default 1
- same identifier / day, default 10
- same IP / hour, default 30
- registration OTP same IP / day, default 100

Set a limit to `0` in Odoo Settings to disable that specific limit.

A throttled request returns the API error code `RATE_LIMITED` with a neutral message. This lets mobile clients stop retry loops and display a retry-later message without exposing account existence.

## Reverse proxy requirement

When Odoo is exposed behind nginx, Traefik, a load balancer, or another reverse proxy, enable `proxy_mode = True` in `odoo.conf` and configure the proxy to pass the real client IP using standard forwarded headers such as `X-Forwarded-For` and `X-Real-IP`.

Without this, Odoo may see the proxy IP for every request. The IP/hour limit would then either block unrelated users together or become operationally misleading.

Because mobile networks can put many users behind the same public NAT address, keep the IP/hour limit broad and rely primarily on the identifier limits for targeted protection.

## Anti-enumeration note

This rate-limit counts OTP challenges that were actually created. It reduces SMS pumping and cost abuse, but it is not a complete account-enumeration fix. Enumeration hardening requires uniform responses for existing and non-existing accounts and should be handled in a separate patch.
