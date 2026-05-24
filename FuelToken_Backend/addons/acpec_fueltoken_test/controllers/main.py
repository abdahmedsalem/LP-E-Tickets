import json
from markupsafe import Markup

from odoo import http
from odoo.http import request

from .catalog_mobile_auth import API_CATALOG_MOBILE_AUTH
from .catalog_fueltoken import API_CATALOG_FUELTOKEN


API_CATALOG = API_CATALOG_MOBILE_AUTH + API_CATALOG_FUELTOKEN


class AcpecFuelTokenTestController(http.Controller):

    @http.route('/acpec/fueltoken/test', type='http', auth='public', methods=['GET'], csrf=False)
    def fueltoken_test_page(self, **kwargs):
        values = {
            'api_catalog_json': Markup(json.dumps(API_CATALOG, ensure_ascii=False)),
            'page_title': 'ACPEC FuelToken API Test',
        }
        return request.render('acpec_fueltoken_test.test_page', values)
