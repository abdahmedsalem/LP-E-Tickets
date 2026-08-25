import json

from odoo import http
from odoo.http import request


class FuelStationMapController(http.Controller):

    @http.route(
        '/fueltoken/stations/map',
        type='http',
        auth='user',
        methods=['GET'],
        sitemap=False,
    )
    def station_map(self, **kwargs):
        user = request.env.user
        if not user.has_group('acpec_fueltoken_base.group_fuel_admin'):
            return request.not_found()

        stations = request.env['acpec.fuel.station'].search(
            [
                ('active', '=', True),
                ('company_id', 'in', request.env.companies.ids),
            ],
            order='name, id',
        )

        station_data = []
        for station in stations:
            latitude = station.latitude
            longitude = station.longitude
            if latitude == 0 and longitude == 0:
                continue

            station_data.append({
                'id': station.id,
                'name': station.name,
                'address': station.address or '',
                'phone': station.phone or '',
                'latitude': latitude,
                'longitude': longitude,
            })

        return request.render(
            'acpec_fueltoken_backoffice_ui.station_map_page',
            {
                'mapbox_token': request.env['ir.config_parameter']
                    .sudo()
                    .get_param(
                        'acpec_fueltoken_backoffice_ui.mapbox_token',
                        '',
                    ),
                'mapbox_style': request.env['ir.config_parameter']
                    .sudo()
                    .get_param(
                        'acpec_fueltoken_backoffice_ui.mapbox_style',
                        'mapbox://styles/mapbox/standard',
                    ),
                'stations_json': json.dumps(
                    station_data,
                    ensure_ascii=False,
                    separators=(',', ':'),
                ),
            },
        )

