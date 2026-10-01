"""Convert legacy scan locks once, preserving valid reservations."""
import logging
import secrets

_logger = logging.getLogger(__name__)


def migrate(cr, version):
    # Existing tokens identify reservations already using the new protocol.
    # Lock selected rows so a concurrent scan cannot be overwritten.
    cr.execute("""
        SELECT id, state, station_lock_user_id, station_lock_station_id,
               station_lock_until IS NOT NULL AND station_lock_until <= NOW() AT TIME ZONE 'UTC'
          FROM acpec_fuel_qr
         WHERE COALESCE(station_reservation_id, '') = ''
           AND (station_lock_user_id IS NOT NULL
                OR station_lock_station_id IS NOT NULL
                OR station_lock_until IS NOT NULL)
         FOR UPDATE
    """)
    released = preserved = 0
    for qr_id, state, user_id, station_id, expired in cr.fetchall():
        if expired or state not in ('active', 'blocked') or not (user_id and station_id):
            cr.execute("""
                UPDATE acpec_fuel_qr
                   SET station_lock_until = NULL, station_lock_user_id = NULL,
                       station_lock_station_id = NULL, station_reservation_id = NULL
                 WHERE id = %s
            """, [qr_id])
            released += 1
        else:
            cr.execute("""
                UPDATE acpec_fuel_qr
                   SET station_lock_until = NULL, station_reservation_id = %s
                 WHERE id = %s
            """, [secrets.token_urlsafe(32), qr_id])
            preserved += 1
    _logger.info('Station lock migration: %s obsolete locks released, %s reservations preserved', released, preserved)
