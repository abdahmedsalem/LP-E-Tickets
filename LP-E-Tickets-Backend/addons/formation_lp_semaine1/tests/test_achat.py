from odoo.exceptions import UserError, ValidationError
from odoo.tests.common import TransactionCase


class TestFormationAchat(TransactionCase):

    def test_calcul_et_soumission(self):
        carnet_type = self.env['formation.lp.carnet.type'].create({
            'name': 'Carnet 10 tickets', 'face_count': 10, 'face_value': 500,
        })
        partner = self.env['res.partner'].create({'name': 'Client de formation'})
        achat = self.env['formation.lp.achat'].create({
            'name': 'ACHAT-TEST-001',
            'partner_id': partner.id,
            'company_id': self.env.company.id,
        })
        ligne = self.env['formation.lp.achat.line'].create({
            'achat_id': achat.id,
            'carnet_type_id': carnet_type.id,
            'carnet_qty': 2,
            'face_count': 10,
            'face_value': 500,
        })

        self.assertEqual(ligne.ticket_qty, 20)
        self.assertEqual(ligne.amount_total, 10000)
        self.assertEqual(achat.ticket_total, 20)
        self.assertEqual(achat.amount_total, 10000)

        achat.action_submit()
        self.assertEqual(achat.state, 'submitted')
        with self.assertRaises(UserError):
            ligne.write({'carnet_qty': 3})

    def test_quantite_invalide(self):
        carnet_type = self.env['formation.lp.carnet.type'].create({
            'name': 'Carnet de test', 'face_count': 10, 'face_value': 500,
        })
        partner = self.env['res.partner'].create({'name': 'Client de test'})
        achat = self.env['formation.lp.achat'].create({
            'partner_id': partner.id,
            'company_id': self.env.company.id,
        })

        with self.assertRaises(ValidationError):
            self.env['formation.lp.achat.line'].create({
                'achat_id': achat.id,
                'carnet_type_id': carnet_type.id,
                'carnet_qty': 0,
                'face_count': 10,
                'face_value': 500,
            })
