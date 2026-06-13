{
    'name': 'ACPEC FuelToken Back-office UI',
    'version': '19.0.1.0.0',
    'category': 'ACPEC/FuelToken',
    'summary': 'Menus et libellés métier pour le back-office FuelToken',
    'author': 'ACPEC SARL',
    'website': 'https://acpec.odoorim.com',
    'license': 'OPL-1',
    'depends': [
        'acpec_fueltoken_reports',
        'acpec_mobile_auth_otp',
    ],
    'data': [
        # Les actions doivent être chargées avant les menuitem qui les référencent.
        'views/backoffice_action_views.xml',
        'views/backoffice_menu_views.xml',
        'views/mobile_auth_french_views.xml',
    ],
    'installable': True,
    'application': False,
    'auto_install': False,
}
