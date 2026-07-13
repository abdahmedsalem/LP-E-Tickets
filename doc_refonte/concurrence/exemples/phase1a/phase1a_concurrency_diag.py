# FuelToken — Phase 1A, diagnostic concurrent exécuté uniquement
# par le script PowerShell dans un clone temporaire de la base.
#
# Ce fichier ne doit pas être exécuté depuis Git Bash.
# Il n'applique aucun patch et n'écrit jamais dans la base source.

import json
import threading
import traceback

import odoo
from odoo import SUPERUSER_ID, api

from odoo.addons.acpec_fueltoken_core.tests.test_consume_station_concurrency import (
    _ConsumeFixtureMixin,
)


class Harness(_ConsumeFixtureMixin):
    pass


harness = Harness()
DB_NAME = env.cr.dbname
RESULTS = []


def emit(name, status, **details):
    row = {
        "scenario": name,
        "status": status,
        "details": details,
    }
    RESULTS.append(row)
    print(
        "LOCKDIAG_RESULT="
        + json.dumps(row, ensure_ascii=False, default=str),
        flush=True,
    )


def exception_details(exc):
    candidates = [
        exc,
        getattr(exc, "__cause__", None),
        getattr(exc, "__context__", None),
    ]
    pgcode = False
    for candidate in candidates:
        if candidate is not None and getattr(candidate, "pgcode", None):
            pgcode = candidate.pgcode
            break
    return {
        "class": "%s.%s"
        % (
            exc.__class__.__module__,
            exc.__class__.__name__,
        ),
        "pgcode": pgcode,
        "message": str(exc),
    }


def real_cursor():
    return odoo.sql_db.db_connect(DB_NAME).cursor()


def database_runtime():
    cr = real_cursor()
    try:
        cr.execute(
            """
            SELECT
                current_setting('transaction_isolation'),
                current_setting('lock_timeout'),
                current_setting('deadlock_timeout'),
                version()
            """
        )
        row = cr.fetchone()
        return {
            "transaction_isolation": row[0],
            "lock_timeout": row[1],
            "deadlock_timeout": row[2],
            "postgres_version": row[3],
        }
    finally:
        cr.rollback()
        cr.close()


def build_fixture(two_qrs=False):
    cr = real_cursor()
    try:
        setup_env = api.Environment(cr, SUPERUSER_ID, {})
        ids = harness._build_consume_fixture(setup_env)

        if two_qrs:
            face_line = setup_env[
                "acpec.fuel.face.line"
            ].browse(ids["face_line_id"])
            wallet = setup_env[
                "acpec.fuel.wallet"
            ].browse(ids["wallet_id"])
            client_user = setup_env[
                "res.users"
            ].browse(ids["client_user_id"])

            qr_two = setup_env[
                "acpec.fuel.qr"
            ]._issue_from_available_internal(
                client_user,
                wallet,
                [
                    {
                        "face_line_id": face_line.id,
                        "qty": harness.QR_FACE_QTY,
                    }
                ],
            )
            ids["qr2_id"] = qr_two.id

        cr.commit()
        return ids
    except Exception:
        cr.rollback()
        raise
    finally:
        cr.close()


def read_state(ids):
    cr = real_cursor()
    try:
        check_env = api.Environment(cr, SUPERUSER_ID, {})
        face = check_env[
            "acpec.fuel.face.line"
        ].browse(ids["face_line_id"]).exists()
        qr_ids = [ids["qr_id"]]
        if ids.get("qr2_id"):
            qr_ids.append(ids["qr2_id"])
        qrs = check_env[
            "acpec.fuel.qr"
        ].browse(qr_ids).exists()
        transaction_count = check_env[
            "acpec.fuel.transaction"
        ].search_count(
            [
                (
                    "transaction_type",
                    "=",
                    "consommation_station",
                ),
                (
                    "qr_id",
                    "in",
                    qr_ids,
                ),
            ]
        )

        counter_values = {
            "qty_initial": face.qty_initial,
            "qty_available": face.qty_available,
            "qty_qr_active": face.qty_qr_active,
            "qty_qr_blocked": face.qty_qr_blocked,
            "qty_consumed": face.qty_consumed,
            "qty_expired": face.qty_expired,
            "qty_transferred_out": face.qty_transferred_out,
        }
        accounted_total = (
            counter_values["qty_available"]
            + counter_values["qty_qr_active"]
            + counter_values["qty_qr_blocked"]
            + counter_values["qty_consumed"]
            + counter_values["qty_expired"]
            + counter_values["qty_transferred_out"]
        )
        return {
            "face_line_id": face.id,
            **counter_values,
            "accounted_total": accounted_total,
            "conservation_ok": accounted_total
            == counter_values["qty_initial"],
            "negative_counters": [
                name
                for name, value in counter_values.items()
                if name != "qty_initial" and value < 0
            ],
            "qr_states": {
                str(qr.id): qr.state
                for qr in qrs
            },
            "consume_transaction_count": transaction_count,
        }
    finally:
        cr.rollback()
        cr.close()


def consume_in_fresh_cursor(ids, qr_key):
    cr = real_cursor()
    try:
        operation_env = api.Environment(
            cr,
            SUPERUSER_ID,
            {},
        )
        qr = operation_env[
            "acpec.fuel.qr"
        ].browse(ids[qr_key])
        station = operation_env[
            "acpec.fuel.station"
        ].browse(ids["station_id"])
        station_user = operation_env[
            "res.users"
        ].browse(ids["station_user_id"])
        transaction = harness._consume_qr_internal(
            qr,
            station,
            station_user,
        )
        cr.commit()
        return {
            "ok": True,
            "transaction_id": transaction.id,
        }
    except Exception as exc:
        cr.rollback()
        return {
            "ok": False,
            "error": exception_details(exc),
        }
    finally:
        cr.close()


def scenario_distinct_qrs_same_face_line():
    name = "distinct_qrs_same_face_line"
    ids = build_fixture(two_qrs=True)
    initial = read_state(ids)
    cr_one = real_cursor()
    cr_two = real_cursor()

    first_result = False
    second_first_attempt = False
    second_fresh_retry = False

    try:
        cr_one.execute("SET LOCAL lock_timeout = '5s'")
        cr_two.execute("SET LOCAL lock_timeout = '5s'")

        cr_one.execute(
            """
            SELECT id
            FROM acpec_fuel_qr
            WHERE id = %s
            FOR UPDATE
            """,
            (ids["qr_id"],),
        )
        cr_two.execute(
            """
            SELECT id
            FROM acpec_fuel_qr
            WHERE id = %s
            FOR UPDATE
            """,
            (ids["qr2_id"],),
        )

        env_one = api.Environment(
            cr_one,
            SUPERUSER_ID,
            {},
        )
        env_two = api.Environment(
            cr_two,
            SUPERUSER_ID,
            {},
        )

        face_one = env_one[
            "acpec.fuel.face.line"
        ].browse(ids["face_line_id"])
        face_two = env_two[
            "acpec.fuel.face.line"
        ].browse(ids["face_line_id"])

        snapshot_one = {
            "qty_qr_active": face_one.qty_qr_active,
            "qty_consumed": face_one.qty_consumed,
        }
        snapshot_two = {
            "qty_qr_active": face_two.qty_qr_active,
            "qty_consumed": face_two.qty_consumed,
        }

        qr_one = env_one[
            "acpec.fuel.qr"
        ].browse(ids["qr_id"])
        station_one = env_one[
            "acpec.fuel.station"
        ].browse(ids["station_id"])
        station_user_one = env_one[
            "res.users"
        ].browse(ids["station_user_id"])

        transaction_one = harness._consume_qr_internal(
            qr_one,
            station_one,
            station_user_one,
        )
        cr_one.commit()
        first_result = {
            "ok": True,
            "transaction_id": transaction_one.id,
        }

        qr_two = env_two[
            "acpec.fuel.qr"
        ].browse(ids["qr2_id"])
        station_two = env_two[
            "acpec.fuel.station"
        ].browse(ids["station_id"])
        station_user_two = env_two[
            "res.users"
        ].browse(ids["station_user_id"])

        try:
            transaction_two = harness._consume_qr_internal(
                qr_two,
                station_two,
                station_user_two,
            )
            cr_two.commit()
            second_first_attempt = {
                "ok": True,
                "transaction_id": transaction_two.id,
            }
        except Exception as exc:
            cr_two.rollback()
            second_first_attempt = {
                "ok": False,
                "error": exception_details(exc),
            }

        if not second_first_attempt["ok"]:
            second_fresh_retry = consume_in_fresh_cursor(
                ids,
                "qr2_id",
            )

        final = read_state(ids)
        expected = {
            "qty_qr_active": 0,
            "qty_consumed": harness.QR_FACE_QTY * 2,
            "consume_transaction_count": 2,
        }
        final_is_expected = (
            final["qty_qr_active"]
            == expected["qty_qr_active"]
            and final["qty_consumed"]
            == expected["qty_consumed"]
            and final["consume_transaction_count"]
            == expected["consume_transaction_count"]
            and set(final["qr_states"].values())
            == {"consumed"}
            and final["conservation_ok"]
            and not final["negative_counters"]
        )

        if (
            second_first_attempt["ok"]
            and not final_is_expected
        ):
            verdict = "critical_committed_inconsistency"
        elif (
            not second_first_attempt["ok"]
            and second_fresh_retry
            and second_fresh_retry.get("ok")
            and final_is_expected
        ):
            verdict = (
                "concurrency_failure_then_fresh_retry_success"
            )
        elif (
            second_first_attempt["ok"]
            and final_is_expected
        ):
            verdict = (
                "both_transactions_committed_correctly"
            )
        else:
            verdict = "unexpected_or_inconclusive"

        emit(
            name,
            verdict,
            ids=ids,
            initial=initial,
            transaction_one_snapshot=snapshot_one,
            transaction_two_snapshot=snapshot_two,
            transaction_one=first_result,
            transaction_two_first_attempt=second_first_attempt,
            transaction_two_fresh_retry=second_fresh_retry,
            expected=expected,
            final=final,
        )
    except Exception as exc:
        try:
            cr_one.rollback()
        except Exception:
            pass
        try:
            cr_two.rollback()
        except Exception:
            pass
        emit(
            name,
            "fatal_scenario_error",
            error=exception_details(exc),
            traceback=traceback.format_exc(),
        )
    finally:
        try:
            cr_one.close()
        except Exception:
            pass
        try:
            cr_two.close()
        except Exception:
            pass


def scenario_lock_cycle_face_line_qr():
    name = "lock_cycle_face_line_qr"
    ids = build_fixture(two_qrs=False)
    cr_face = real_cursor()
    cr_qr = real_cursor()
    outcomes = {}
    barrier = threading.Barrier(2)

    try:
        cr_face.execute("SET LOCAL lock_timeout = '8s'")
        cr_qr.execute("SET LOCAL lock_timeout = '8s'")

        cr_face.execute(
            """
            SELECT id
            FROM acpec_fuel_face_line
            WHERE id = %s
            FOR UPDATE
            """,
            (ids["face_line_id"],),
        )
        cr_qr.execute(
            """
            SELECT id
            FROM acpec_fuel_qr
            WHERE id = %s
            FOR UPDATE
            """,
            (ids["qr_id"],),
        )

        def face_then_qr():
            try:
                barrier.wait(timeout=5)
                cr_face.execute(
                    """
                    SELECT id
                    FROM acpec_fuel_qr
                    WHERE id = %s
                    FOR UPDATE
                    """,
                    (ids["qr_id"],),
                )
                outcomes["face_then_qr"] = {
                    "ok": True,
                    "acquired": True,
                }
            except Exception as exc:
                outcomes["face_then_qr"] = {
                    "ok": False,
                    "error": exception_details(exc),
                }
            finally:
                try:
                    cr_face.rollback()
                except Exception:
                    pass

        def qr_then_face():
            try:
                barrier.wait(timeout=5)
                cr_qr.execute(
                    """
                    SELECT id
                    FROM acpec_fuel_face_line
                    WHERE id = %s
                    FOR UPDATE
                    """,
                    (ids["face_line_id"],),
                )
                outcomes["qr_then_face"] = {
                    "ok": True,
                    "acquired": True,
                }
            except Exception as exc:
                outcomes["qr_then_face"] = {
                    "ok": False,
                    "error": exception_details(exc),
                }
            finally:
                try:
                    cr_qr.rollback()
                except Exception:
                    pass

        thread_one = threading.Thread(
            target=face_then_qr,
            name="face-then-qr",
        )
        thread_two = threading.Thread(
            target=qr_then_face,
            name="qr-then-face",
        )
        thread_one.start()
        thread_two.start()
        thread_one.join(timeout=15)
        thread_two.join(timeout=15)

        pgcodes = {
            value.get("error", {}).get("pgcode")
            for value in outcomes.values()
            if not value.get("ok")
        }

        if "40P01" in pgcodes:
            verdict = "deadlock_detected"
        elif (
            thread_one.is_alive()
            or thread_two.is_alive()
            or len(outcomes) != 2
        ):
            verdict = "threads_not_completed"
        elif any(
            not value.get("ok")
            for value in outcomes.values()
        ):
            verdict = "lock_failure_without_deadlock_code"
        else:
            verdict = "unexpected_both_cross_locks_acquired"

        emit(
            name,
            verdict,
            ids=ids,
            outcomes=outcomes,
        )
    except Exception as exc:
        emit(
            name,
            "fatal_scenario_error",
            error=exception_details(exc),
            traceback=traceback.format_exc(),
        )
    finally:
        try:
            cr_face.rollback()
        except Exception:
            pass
        try:
            cr_qr.rollback()
        except Exception:
            pass
        try:
            cr_face.close()
        except Exception:
            pass
        try:
            cr_qr.close()
        except Exception:
            pass


def isolate_cron_fixture(ids, expire_available):
    cr = real_cursor()
    try:
        cr.execute(
            """
            UPDATE acpec_fuel_qr
            SET state = 'consumed'
            WHERE id <> %s
              AND state IN ('active', 'blocked')
            """,
            (ids["qr_id"],),
        )
        cr.execute(
            """
            UPDATE acpec_fuel_face_line
            SET expires_at = NULL
            WHERE id <> %s
            """,
            (ids["face_line_id"],),
        )
        if expire_available:
            cr.execute(
                """
                UPDATE acpec_fuel_face_line
                SET expires_at =
                    (NOW() AT TIME ZONE 'UTC')
                    - INTERVAL '1 hour'
                WHERE id = %s
                """,
                (ids["face_line_id"],),
            )
        else:
            cr.execute(
                """
                UPDATE acpec_fuel_face_line
                SET expires_at = NULL
                WHERE id = %s
                """,
                (ids["face_line_id"],),
            )
        cr.commit()
    except Exception:
        cr.rollback()
        raise
    finally:
        cr.close()


def scenario_cron_available_contention():
    name = "cron_available_loop_contention"
    ids = build_fixture(two_qrs=False)
    isolate_cron_fixture(
        ids,
        expire_available=True,
    )
    cr_lock = real_cursor()
    cr_cron = real_cursor()

    try:
        cr_lock.execute(
            """
            SELECT id
            FROM acpec_fuel_face_line
            WHERE id = %s
            FOR UPDATE
            """,
            (ids["face_line_id"],),
        )
        cr_cron.execute(
            "SET LOCAL lock_timeout = '700ms'"
        )
        cron_env = api.Environment(
            cr_cron,
            SUPERUSER_ID,
            {},
        )

        returned_normally = False
        error = False
        try:
            cron_env[
                "acpec.fuel.qr"
            ]._cron_process_expiration()
            returned_normally = True
        except Exception as exc:
            error = exception_details(exc)
        finally:
            cr_cron.rollback()

        if error:
            verdict = (
                "exception_propagated_whole_cron_would_fail"
            )
        elif returned_normally:
            verdict = "unexpected_returned_normally"
        else:
            verdict = "inconclusive"

        emit(
            name,
            verdict,
            ids=ids,
            returned_normally=returned_normally,
            error=error,
        )
    except Exception as exc:
        emit(
            name,
            "fatal_scenario_error",
            error=exception_details(exc),
            traceback=traceback.format_exc(),
        )
    finally:
        try:
            cr_lock.rollback()
        except Exception:
            pass
        try:
            cr_cron.rollback()
        except Exception:
            pass
        try:
            cr_lock.close()
        except Exception:
            pass
        try:
            cr_cron.close()
        except Exception:
            pass


def scenario_cron_qr_contention():
    name = "cron_qr_loop_contention"
    ids = build_fixture(two_qrs=False)
    isolate_cron_fixture(
        ids,
        expire_available=False,
    )
    cr_lock = real_cursor()
    cr_cron = real_cursor()

    try:
        cr_lock.execute(
            """
            SELECT id
            FROM acpec_fuel_qr
            WHERE id = %s
            FOR UPDATE
            """,
            (ids["qr_id"],),
        )
        cr_cron.execute(
            "SET LOCAL lock_timeout = '700ms'"
        )
        cron_env = api.Environment(
            cr_cron,
            SUPERUSER_ID,
            {},
        )

        returned_normally = False
        error = False
        try:
            cron_env[
                "acpec.fuel.qr"
            ]._cron_process_expiration()
            returned_normally = True
        except Exception as exc:
            error = exception_details(exc)
        finally:
            cr_cron.rollback()

        if returned_normally and not error:
            verdict = (
                "contention_swallowed_method_returned_success"
            )
        elif error:
            verdict = "exception_propagated"
        else:
            verdict = "inconclusive"

        emit(
            name,
            verdict,
            ids=ids,
            returned_normally=returned_normally,
            error=error,
        )
    except Exception as exc:
        emit(
            name,
            "fatal_scenario_error",
            error=exception_details(exc),
            traceback=traceback.format_exc(),
        )
    finally:
        try:
            cr_lock.rollback()
        except Exception:
            pass
        try:
            cr_cron.rollback()
        except Exception:
            pass
        try:
            cr_lock.close()
        except Exception:
            pass
        try:
            cr_cron.close()
        except Exception:
            pass


print(
    "LOCKDIAG_META="
    + json.dumps(
        {
            "database": DB_NAME,
            "runtime": database_runtime(),
            "source_database_modified": False,
            "patch_applied": False,
        },
        ensure_ascii=False,
        default=str,
    ),
    flush=True,
)

scenario_distinct_qrs_same_face_line()
scenario_lock_cycle_face_line_qr()
scenario_cron_available_contention()
scenario_cron_qr_contention()

print(
    "LOCKDIAG_SUMMARY="
    + json.dumps(
        RESULTS,
        ensure_ascii=False,
        default=str,
    ),
    flush=True,
)
