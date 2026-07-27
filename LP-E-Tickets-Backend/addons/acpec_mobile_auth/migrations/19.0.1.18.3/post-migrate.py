# -*- coding: utf-8 -*-
# Part of ACPEC. License LGPL-3.0 or later.
#
# Patch2T-A: one-shot migration of legacy unprefixed mobile fields on
# res.users to ACPEC-prefixed storage fields.
#
# Keep this logic in a versioned migration, not in models/res_users.py:init().

from psycopg2 import sql


def _column_exists(cr, column_name):
    cr.execute(
        """
        SELECT EXISTS (
            SELECT 1
              FROM information_schema.columns
             WHERE table_name = 'res_users'
               AND column_name = %s
        )
        """,
        (column_name,),
    )
    return bool(cr.fetchone()[0])


def _copy_char(cr, legacy_field, acpec_field):
    if not _column_exists(cr, legacy_field):
        return
    cr.execute(
        sql.SQL(
            """
            UPDATE res_users
               SET {acpec_field} = {legacy_field}
             WHERE ({acpec_field} IS NULL OR {acpec_field} = '')
               AND {legacy_field} IS NOT NULL
               AND {legacy_field} <> ''
            """
        ).format(
            acpec_field=sql.Identifier(acpec_field),
            legacy_field=sql.Identifier(legacy_field),
        )
    )


def _copy_scalar(cr, legacy_field, acpec_field):
    if not _column_exists(cr, legacy_field):
        return
    cr.execute(
        sql.SQL(
            """
            UPDATE res_users
               SET {acpec_field} = {legacy_field}
             WHERE {legacy_field} IS NOT NULL
               AND (
                    {acpec_field} IS NULL
                    OR {acpec_field} IS DISTINCT FROM {legacy_field}
               )
            """
        ).format(
            acpec_field=sql.Identifier(acpec_field),
            legacy_field=sql.Identifier(legacy_field),
        )
    )


def migrate(cr, version):
    cr.execute(
        """
        ALTER TABLE res_users
        ADD COLUMN IF NOT EXISTS acpec_mobile_phone varchar,
        ADD COLUMN IF NOT EXISTS acpec_mobile_state varchar,
        ADD COLUMN IF NOT EXISTS acpec_mobile_only boolean,
        ADD COLUMN IF NOT EXISTS acpec_mobile_pin_hash varchar,
        ADD COLUMN IF NOT EXISTS acpec_mobile_pin_salt varchar,
        ADD COLUMN IF NOT EXISTS acpec_mobile_pin_set boolean,
        ADD COLUMN IF NOT EXISTS acpec_mobile_pin_required boolean,
        ADD COLUMN IF NOT EXISTS acpec_mobile_pin_failed_count integer,
        ADD COLUMN IF NOT EXISTS acpec_mobile_pin_locked_until timestamp,
        ADD COLUMN IF NOT EXISTS acpec_mobile_pin_set_at timestamp
        """
    )

    _copy_char(cr, 'mobile_phone', 'acpec_mobile_phone')
    _copy_char(cr, 'mobile_state', 'acpec_mobile_state')
    _copy_char(cr, 'mobile_pin_hash', 'acpec_mobile_pin_hash')
    _copy_char(cr, 'mobile_pin_salt', 'acpec_mobile_pin_salt')

    _copy_scalar(cr, 'mobile_only', 'acpec_mobile_only')
    _copy_scalar(cr, 'mobile_pin_set', 'acpec_mobile_pin_set')
    _copy_scalar(cr, 'mobile_pin_required', 'acpec_mobile_pin_required')
    _copy_scalar(cr, 'mobile_pin_failed_count', 'acpec_mobile_pin_failed_count')
    _copy_scalar(cr, 'mobile_pin_locked_until', 'acpec_mobile_pin_locked_until')
    _copy_scalar(cr, 'mobile_pin_set_at', 'acpec_mobile_pin_set_at')

    cr.execute("DROP INDEX IF EXISTS res_users_acpec_mobile_only_phone_uniq")
    cr.execute("DROP INDEX IF EXISTS res_users_acpec_mobile_only_acpec_phone_uniq")
    cr.execute(
        """
        CREATE UNIQUE INDEX IF NOT EXISTS res_users_acpec_mobile_only_acpec_phone_uniq
            ON res_users(acpec_mobile_phone)
         WHERE acpec_mobile_only IS TRUE
           AND acpec_mobile_phone IS NOT NULL
           AND acpec_mobile_phone <> ''
        """
    )
