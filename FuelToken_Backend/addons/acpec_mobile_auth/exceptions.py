from odoo.exceptions import AccessError, ValidationError


class MobileAuthRateLimitError(ValidationError):
    """Raised when a public mobile authentication endpoint is throttled."""


class MobileSensitivePinBusy(AccessError):
    """Raised when the per-user PIN lock cannot be acquired within its bound.

    Another sensitive action is already mutating this user's PIN counters.
    This is a transient availability condition, NOT a wrong PIN: callers must
    surface it as "action already in progress" and must never increment
    mobile_pin_failed_count because of it.  It subclasses AccessError so the
    existing sensitive-action handlers keep catching it unchanged.
    """
