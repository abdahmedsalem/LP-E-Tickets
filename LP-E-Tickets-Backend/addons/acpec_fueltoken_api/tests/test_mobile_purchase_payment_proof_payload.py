# -*- coding: utf-8 -*-
import base64
from types import SimpleNamespace
from unittest.mock import patch

from odoo.tests.common import TransactionCase, tagged

from odoo.addons.acpec_fueltoken_api.controllers import api_mobile as api_mobile_module
from odoo.addons.acpec_fueltoken_api.controllers.api_mobile import AcpecFuelTokenMobileApi


@tagged("post_install", "-at_install")
class TestMobilePurchasePaymentProofPayload(TransactionCase):

    def test_mobile_purchase_proof_payload_exposes_url_and_detail_data(self):
        proof_data = base64.b64encode(
            bytes.fromhex("89504e470d0a1a0a") + b"mobile proof"
        ).decode("ascii")
        purchase = self.env["acpec.fuel.purchase"]._create_internal({
            "partner_id": self.env.user.partner_id.id,
            "company_id": self.env.company.id,
            "payment_reference": "PAY-MOBILE-PROOF",
        })
        attachment = self.env["ir.attachment"].sudo().create({
            "name": "preuve-mobile.png",
            "datas": proof_data,
            "mimetype": "image/png",
            "res_model": purchase._name,
            "res_id": purchase.id,
            "type": "binary",
        })

        controller = AcpecFuelTokenMobileApi()
        fake_request = SimpleNamespace(env=self.env)
        with patch.object(api_mobile_module, "request", fake_request):
            attachments = controller._purchase_proof_attachments(purchase)

        self.assertIn(attachment, attachments)

        summary = controller._purchase_proof_attachment_payload(attachment)
        self.assertEqual(summary["filename"], "preuve-mobile.png")
        self.assertEqual(summary["url"], "/web/content/%s" % attachment.id)
        self.assertEqual(
            summary["download_url"],
            "/web/content/%s?download=true" % attachment.id,
        )
        self.assertNotIn("proof_data", summary)

        detail = controller._purchase_proof_attachment_payload(
            attachment,
            include_data=True,
        )
        self.assertEqual(detail["proof_data"], proof_data)
        self.assertEqual(detail["payment_proof_data"], proof_data)
        self.assertEqual(detail["attachment_data"], proof_data)
        self.assertEqual(detail["image_data"], proof_data)
        self.assertEqual(detail["proof_image_data"], proof_data)

        wallet = SimpleNamespace(
            partner_id=self.env.user.partner_id,
            company_id=self.env.company,
        )
        controller._mobile_wallet = lambda: wallet

        with patch.object(api_mobile_module, "request", fake_request):
            list_response = controller.purchases()
            list_with_data_response = controller.purchases(include_proof_data=True)
            detail_response = controller.purchase_detail(purchase_id=purchase.id)

        list_item = list_response["data"]["items"][0]
        self.assertEqual(list_item["id"], purchase.id)
        self.assertEqual(list_item["payment_reference"], "PAY-MOBILE-PROOF")
        self.assertEqual(list_item["payment_proof_path"], "/web/content/%s" % attachment.id)
        self.assertEqual(list_item["proof_attachment_id"], attachment.id)
        self.assertNotIn("proof_data", list_item["proof_attachments"][0])

        list_item_with_data = list_with_data_response["data"]["items"][0]
        self.assertEqual(
            list_item_with_data["proof_attachments"][0]["proof_data"],
            proof_data,
        )
        self.assertEqual(
            list_item_with_data["proofs"][0]["attachment_data"],
            proof_data,
        )
        self.assertEqual(list_item_with_data["proof_data"], proof_data)
        self.assertEqual(list_item_with_data["payment_proof_data"], proof_data)
        self.assertEqual(list_item_with_data["image_data"], proof_data)
        self.assertEqual(list_item_with_data["proof_image_data"], proof_data)
        self.assertEqual(list_item_with_data["proof_filename"], "preuve-mobile.png")
        self.assertEqual(list_item_with_data["proof_mimetype"], "image/png")

        detail_payload = detail_response["data"]
        self.assertEqual(detail_payload["id"], purchase.id)
        self.assertEqual(detail_payload["payment_reference"], "PAY-MOBILE-PROOF")
        self.assertEqual(detail_payload["proof_image_data"], proof_data)
        self.assertEqual(detail_payload["image_data"], proof_data)
        self.assertEqual(detail_payload["proof_attachments"][0]["proof_data"], proof_data)
        self.assertEqual(detail_payload["proofs"][0]["download_url"], "/web/content/%s?download=true" % attachment.id)
