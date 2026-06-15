from odoo.exceptions import ValidationError


class MobileAuthRateLimitError(ValidationError):
    """Raised when a public mobile authentication endpoint is throttled."""
