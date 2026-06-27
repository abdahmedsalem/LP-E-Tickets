"""Tests anti-double-encaissement pour ``acpec.fuel.qr.action_consume_by_station``.

Deux classes complementaires :

* ``TestConsumeStationGuard`` — rapide, deterministe, sans commit. Verrouille la
  garantie *logique* (machine a etats + idempotence). A garder dans le gate CI
  par defaut : elle tourne dans la transaction de test rollbackee, sans residu.

* ``TestConsumeStationConcurrency`` — vrai test de concurrence. Il exerce le
  verrou ``SELECT ... FOR UPDATE`` en faisant rentrer DEUX transactions Postgres
  reellement independantes en collision sur le meme QR.

  Pourquoi des connexions psycopg dediees ? Le harnais de test Odoo enveloppe
  tout dans une transaction unique avec un *test cursor* qui serialise les
  acces : des threads partageant ce curseur ne se disputeraient jamais le verrou
  de ligne. On ouvre donc des curseurs reels via ``odoo.sql_db.db_connect`` et on
  *committe* les fixtures pour qu'elles soient visibles des deux connexions.
  C'est plus lourd (residu en base, identifiants suffixes pour rester
  re-executable) : ce test est tague separement, a lancer dans un job dedie.

Lancement :
    odoo -d <db> --test-enable --test-tags acpec_fueltoken_core
    # concurrence seule :
    odoo -d <db> --test-enable --test-tags acpec_concurrency
"""

import base64
import uuid

import odoo
from odoo import SUPERUSER_ID, api, fields
from odoo.exceptions import UserError
from odoo.tests import TransactionCase, tagged
from odoo.tools import mute_logger


# ---------------------------------------------------------------------------
# Fixtures partagees
# ---------------------------------------------------------------------------
class _ConsumeFixtureMixin:
    """Construit la chaine wallet -> achat -> face_line -> QR -> station.

    Reproduit le parcours metier reel (approbation d'achat puis emission d'un
    QR a partir du disponible) au lieu de poser des etats a la main : on teste
    ainsi le QR tel qu'il existe reellement en production.
    """

    QR_FACE_QTY = 4  # tickets emis dans le QR de test (< tickets disponibles)

    def _unique_carnet_type(self, env, company):
        """Type de carnet isole : le code est calcule depuis face_count/face_value
        et contraint unique par societe. On cherche une valeur de face libre."""
        carnet_model = env['acpec.fuel.carnet.type'].sudo()
        face_count = 10
        for face_value in range(900001, 900201):
            code = 'C%sT-%s' % (face_count, face_value)
            if not carnet_model.search(
                [('company_id', '=', company.id), ('code', '=', code)], limit=1
            ):
                return carnet_model.create({
                    'face_count': face_count,
                    'face_value': face_value,
                    'validity_days': 365,
                    'company_id': company.id,
                })
        raise AssertionError('Aucun code de carnet libre pour le test.')

    def _mobile_station_group_ids(self, env):
        """Groupes d'un utilisateur mobile-only station.

        Un user mobile ne doit jamais être créé comme Internal User puis enrichi.
        On passe les groupes mobiles directement au create(), comme le flux OTP.
        """
        xmlids = (
            'base.group_portal',
            'acpec_mobile_auth.group_mobile_auth_user',
            'acpec_fueltoken_base.group_fuel_station',
        )
        group_ids = []
        for xmlid in xmlids:
            group = env.ref(xmlid, raise_if_not_found=False)
            if group:
                group_ids.append(group.id)
        return group_ids

    def _station_mobile_user_vals(self, env, vals, mobile_phone):
        vals = dict(vals or {})
        label = str(mobile_phone or vals.get('login') or vals.get('name') or 'station-conc')
    
        # Doctrine tests mobiles FuelToken : numéros locaux canonique en 21xxxxxx.
        value = 2166136261
        for char in label:
            value ^= ord(char)
            value = (value * 16777619) % 1000000
        phone = "21%06d" % value
    
        # Ne jamais laisser les anciens labels de fixture devenir l'identité mobile.
        vals.pop('login', None)
        vals.pop('mobile_phone', None)
        vals.pop('email', None)
        vals.pop('groups_id', None)
    
        group_ids = self._mobile_station_group_ids(env)
        if group_ids:
            vals['group_ids'] = [(6, 0, group_ids)]
    
        vals['login'] = phone
        vals['mobile_phone'] = phone
        vals['mobile_only'] = True
        vals['mobile_state'] = vals.get('mobile_state') or 'approved'
        vals.setdefault(
            'password',
            env['res.users'].sudo()._acpec_mobile_unusable_password(),
        )
        return vals

    def _build_consume_fixture(self, env):
        """Cree et renvoie les ids utiles : qr, station, user station, face_line.

        Ne committe pas : l'appelant decide (rollback en test rapide, commit en
        test de concurrence)."""
        company = env.company
        suffix = uuid.uuid4().hex[:10]

        partner = env['res.partner'].sudo().create({
            'name': 'Client conso %s' % suffix,
        })
        carnet_type = self._unique_carnet_type(env, company)

        purchase = env['acpec.fuel.purchase'].sudo().create({
            'partner_id': partner.id,
            'company_id': company.id,
            'payment_reference': 'PAY-CONC-%s' % suffix,
        })
        env['acpec.fuel.purchase.line'].sudo().create({
            'purchase_id': purchase.id,
            'carnet_type_id': carnet_type.id,
            'carnet_qty': 1,  # 1 carnet * 10 tickets = 10 tickets disponibles
        })
        attachment = env['ir.attachment'].sudo().create({
            'name': 'preuve.pdf',
            'datas': base64.b64encode(b'%PDF-1.4\npreuve test\n').decode('ascii'),
            'mimetype': 'application/pdf',
            'res_model': purchase._name,
            'res_id': purchase.id,
            'type': 'binary',
        })
        purchase.write({'proof_attachment_ids': [(4, attachment.id)]})

        purchase.action_submit()
        purchase.action_approve()
        purchase._create_face_lines_after_approval()

        face_line = env['acpec.fuel.face.line'].sudo().search(
            [('purchase_id', '=', purchase.id)], limit=1
        )
        assert face_line, "L'approbation aurait du creer une face_line."

        wallet = env['acpec.fuel.wallet'].sudo().get_or_create(partner, company)

        qr = env['acpec.fuel.qr'].sudo().issue_from_available(
            wallet,
            [{'face_value': carnet_type.face_value, 'qty': self.QR_FACE_QTY}],
        )
        assert qr.state == 'active'
        assert qr.face_qty_total == self.QR_FACE_QTY

        station_user = env['res.users'].sudo().with_context(
            no_reset_password=True
        ).create(self._station_mobile_user_vals(env, {
            'name': 'Station conso %s' % suffix,
            'login': 'station-conc-%s' % suffix,
            'company_id': company.id,
            'company_ids': [(6, 0, [company.id])],
        }, 'station-conc-%s' % suffix))
        station = env['acpec.fuel.station'].sudo().create({
            'name': 'Station test %s' % suffix,
            'user_id': station_user.id,
            'company_id': company.id,
        })

        return {
            'qr_id': qr.id,
            'station_id': station.id,
            'station_user_id': station_user.id,
            'face_line_id': face_line.id,
            'partner_id': partner.id,
            'wallet_id': wallet.id,
            'purchase_id': purchase.id,
            'carnet_type_id': carnet_type.id,
            'attachment_id': attachment.id,
        }


# ---------------------------------------------------------------------------
# 1) Garde logique : rapide, deterministe, sans commit
# ---------------------------------------------------------------------------
@tagged('-at_install', 'post_install')
class TestConsumeStationGuard(_ConsumeFixtureMixin, TransactionCase):

    def setUp(self):
        super().setUp()
        ids = self._build_consume_fixture(self.env)
        self.qr = self.env['acpec.fuel.qr'].browse(ids['qr_id'])
        self.station = self.env['acpec.fuel.station'].browse(ids['station_id'])
        self.station_user = self.env['res.users'].browse(ids['station_user_id'])
        self.face_line = self.env['acpec.fuel.face.line'].browse(ids['face_line_id'])

    def test_double_consume_is_blocked_by_state(self):
        """Une 2e consommation du meme QR doit echouer, sans double decrement."""
        consumed_before = self.face_line.qty_consumed
        active_before = self.face_line.qty_qr_active

        tx = self.qr.action_consume_by_station(self.station, user=self.station_user)
        self.assertTrue(tx, "La premiere consommation doit reussir.")
        self.assertEqual(self.qr.state, 'consumed')

        self.face_line.invalidate_recordset()
        self.assertEqual(
            self.face_line.qty_consumed, consumed_before + self.QR_FACE_QTY,
            "qty_consumed doit augmenter exactement de la quantite du QR.",
        )
        self.assertEqual(
            self.face_line.qty_qr_active, active_before - self.QR_FACE_QTY,
            "qty_qr_active doit diminuer exactement de la quantite du QR.",
        )

        # 2e tentative -> refus, et aucun effet sur les quantites.
        with self.assertRaises(UserError):
            self.qr.action_consume_by_station(self.station, user=self.station_user)

        self.face_line.invalidate_recordset()
        self.assertEqual(
            self.face_line.qty_consumed, consumed_before + self.QR_FACE_QTY,
            "La consommation refusee ne doit RIEN encaisser de plus.",
        )

    def test_consume_is_idempotent_on_key(self):
        """Deux appels avec la meme cle d'idempotence -> meme transaction, un seul effet."""
        consumed_before = self.face_line.qty_consumed
        key = 'idem-%s' % uuid.uuid4().hex

        tx1 = self.qr.action_consume_by_station(
            self.station, user=self.station_user, idempotency_key=key)
        tx2 = self.qr.action_consume_by_station(
            self.station, user=self.station_user, idempotency_key=key)

        self.assertEqual(
            tx1.id, tx2.id,
            "La meme cle d'idempotence doit renvoyer la meme transaction.",
        )
        self.face_line.invalidate_recordset()
        self.assertEqual(
            self.face_line.qty_consumed, consumed_before + self.QR_FACE_QTY,
            "Le rejeu idempotent ne doit encaisser qu'une fois.",
        )

    def test_cross_company_consume_is_blocked(self):
        """Une station d'une autre societe ne peut pas consommer le QR.

        On ne mute pas la societe de la station existante : le modele impose que
        l'utilisateur station appartienne a la societe de la station
        (_check_station_user_company). On cree donc une station etrangere
        coherente et on tente de consommer le QR de la societe courante."""
        other_company = self.env['res.company'].sudo().create({
            'name': 'Autre societe %s' % uuid.uuid4().hex[:6],
        })
        foreign_suffix = uuid.uuid4().hex[:8]
        foreign_user = self.env['res.users'].sudo().with_context(
            no_reset_password=True
        ).create(self._station_mobile_user_vals(self.env, {
            'name': 'Station etrangere',
            'login': 'station-foreign-%s' % foreign_suffix,
            'company_id': other_company.id,
            'company_ids': [(6, 0, [other_company.id])],
        }, 'station-foreign-%s' % foreign_suffix))
        foreign_station = self.env['acpec.fuel.station'].sudo().create({
            'name': 'Station etrangere %s' % uuid.uuid4().hex[:6],
            'user_id': foreign_user.id,
            'company_id': other_company.id,
        })
        with self.assertRaises(UserError):
            self.qr.action_consume_by_station(foreign_station, user=foreign_user)
        self.assertEqual(self.qr.state, 'active')


# ---------------------------------------------------------------------------
# 2) Concurrence reelle, deterministe : collision sur le verrou de ligne
# ---------------------------------------------------------------------------
@tagged('-at_install', 'post_install', 'acpec_concurrency')
class TestConsumeStationConcurrency(_ConsumeFixtureMixin, TransactionCase):
    """Prouve que ``_lock_records`` (SELECT ... FOR UPDATE) serialise les
    consommations concurrentes du meme QR, sans dependre du timing de threads.

    Pourquoi pas de threads ? Le harnais de test Odoo garde une transaction de
    test ouverte et serialise les acces ; un racing de threads y est fragile
    (blocages, non-determinisme). On reproduit ici la collision de maniere
    *deterministe* avec deux connexions psycopg reelles et un ``lock_timeout``
    court :

      1. La connexion A verrouille la ligne QR (comme le ferait une conso en
         cours) et ne committe pas.
      2. La connexion B tente la conso : son FOR UPDATE bute sur le verrou de A
         et abandonne au bout du ``lock_timeout`` -> preuve que l'acces
         concurrent est bien bloque (aucune conso ne passe pendant le verrou).
      3. A realise la conso et committe.
      4. B retente : il relit l'etat ``consumed`` et leve ``UserError``.

    Resultat garanti : une seule conso encaisse, jamais deux.
    """

    def _real_cursor(self, db_name):
        return odoo.sql_db.db_connect(db_name).cursor()

    def test_concurrent_consume_is_serialized_and_spends_once(self):
        db_name = self.env.cr.dbname

        # Fixtures construites ET committees sur une connexion DEDIEE : le
        # curseur de test (self.env.cr) interdit tout commit ; on ne le touche
        # jamais. Les donnees vivent hors de la transaction de test.
        setup_cr = self._real_cursor(db_name)
        try:
            setup_env = api.Environment(setup_cr, SUPERUSER_ID, {})
            ids = self._build_consume_fixture(setup_env)
            setup_cr.commit()
        finally:
            setup_cr.close()

        qr_id = ids['qr_id']
        station_id = ids['station_id']
        user_id = ids['station_user_id']

        cr_a = self._real_cursor(db_name)
        cr_b = self._real_cursor(db_name)
        try:
            # --- A : prend et conserve le verrou de la ligne QR ---------------
            cr_a.execute(
                'SELECT id FROM acpec_fuel_qr WHERE id = %s FOR UPDATE',
                (qr_id,),
            )

            # --- B : tente de consommer ; doit buter sur le verrou de A -------
            cr_b.execute("SET lock_timeout = '3s'")
            env_b = api.Environment(cr_b, SUPERUSER_ID, {})
            qr_b = env_b['acpec.fuel.qr'].browse(qr_id)
            station_b = env_b['acpec.fuel.station'].browse(station_id)
            user_b = env_b['res.users'].browse(user_id)
            blocked = False
            # Le verrou de A fera echouer le FOR UPDATE de B au bout du
            # lock_timeout : Odoo journalise cette annulation en ERROR (il loggue
            # toute exception DB) alors que c'est le comportement attendu ici.
            # On etouffe ce log precis pour ne pas polluer la sortie CI.
            with mute_logger('odoo.sql_db'):
                try:
                    qr_b.action_consume_by_station(station_b, user=user_b)
                    cr_b.commit()
                except Exception:  # LockNotAvailable attendu (verrou indisponible)
                    blocked = True
                    cr_b.rollback()
            self.assertTrue(
                blocked,
                "La conso B aurait du etre bloquee par le verrou FOR UPDATE de A.",
            )

            # --- A : realise la conso pendant qu'il detient le verrou ---------
            env_a = api.Environment(cr_a, SUPERUSER_ID, {})
            qr_a = env_a['acpec.fuel.qr'].browse(qr_id)
            station_a = env_a['acpec.fuel.station'].browse(station_id)
            user_a = env_a['res.users'].browse(user_id)
            tx_a = qr_a.action_consume_by_station(station_a, user=user_a)
            self.assertTrue(tx_a, "La conso A aurait du reussir.")
            cr_a.commit()

            # --- B : retente, le verrou est libre mais l'etat est 'consumed' --
            with self.assertRaises(UserError):
                qr_b.action_consume_by_station(station_b, user=user_b)
            cr_b.rollback()

            # --- Invariant en base, via une connexion fraiche -----------------
            check_cr = self._real_cursor(db_name)
            try:
                check_env = api.Environment(check_cr, SUPERUSER_ID, {})
                qr = check_env['acpec.fuel.qr'].browse(qr_id)
                face_line = check_env['acpec.fuel.face.line'].browse(ids['face_line_id'])
                self.assertEqual(qr.state, 'consumed')
                self.assertEqual(
                    face_line.qty_consumed, self.QR_FACE_QTY,
                    "Le QR ne doit avoir ete encaisse qu'une seule fois.",
                )
                self.assertEqual(face_line.qty_qr_active, 0)
                tx_count = check_env['acpec.fuel.transaction'].search_count([
                    ('qr_id', '=', qr_id),
                    ('transaction_type', '=', 'consommation_station'),
                ])
                self.assertEqual(tx_count, 1, "Une seule conso doit etre journalisee.")
            finally:
                check_cr.close()
        finally:
            try:
                cr_a.rollback()
            except Exception:
                pass
            cr_a.close()
            try:
                cr_b.rollback()
            except Exception:
                pass
            cr_b.close()
            self._cleanup_committed(db_name, ids)

    def _cleanup_committed(self, db_name, ids):
        """Nettoyage best-effort des donnees committees.

        Les identifiants sont suffixes par un uuid, donc un nettoyage partiel ne
        bloque jamais une re-execution ; on tolere les erreurs d'ondelete."""
        cr = odoo.sql_db.db_connect(db_name).cursor()
        try:
            env = api.Environment(cr, SUPERUSER_ID, {})
            order = [
                ('acpec.fuel.transaction', [('qr_id', '=', ids['qr_id'])]),
                ('acpec.fuel.qr', [('id', '=', ids['qr_id'])]),
                ('acpec.fuel.face.line', [('id', '=', ids['face_line_id'])]),
                ('acpec.fuel.station', [('id', '=', ids['station_id'])]),
                ('acpec.fuel.purchase', [('id', '=', ids['purchase_id'])]),
                ('acpec.fuel.wallet', [('id', '=', ids['wallet_id'])]),
                ('res.users', [('id', '=', ids['station_user_id'])]),
                ('res.partner', [('id', '=', ids['partner_id'])]),
                ('acpec.fuel.carnet.type', [('id', '=', ids['carnet_type_id'])]),
                ('ir.attachment', [('id', '=', ids['attachment_id'])]),
            ]
            for model, domain in order:
                try:
                    recs = env[model].sudo().search(domain)
                    if recs:
                        if model == 'acpec.fuel.transaction':
                            recs = recs.with_context(allow_fuel_transaction_unlink=True)
                        recs.unlink()
                        cr.commit()
                except Exception:
                    cr.rollback()
        finally:
            cr.close()
