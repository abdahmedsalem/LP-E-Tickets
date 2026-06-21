{
    'name': 'ACPEC FuelToken Back-office UI',
    'version': '19.0.1.3.7',
    'category': 'ACPEC/FuelToken',
    'summary': 'Menus et libellés métier pour le back-office Tickets Carburant',
    'author': 'ACPEC SARL',
    'website': 'https://acpec.odoorim.com',
    'license': 'OPL-1',
    'depends': [
        'acpec_fueltoken_reports',
        'acpec_mobile_auth',
        'acpec_mobile_auth_otp',
    ],
    'data': [
        # Les actions doivent être chargées avant les menuitem qui les référencent.
        'views/backoffice_search_views.xml',
        'views/backoffice_action_views.xml',
        'views/mobile_users_backoffice_views.xml',
        'views/mobile_auth_french_views.xml',
        # Les menus sont chargés en dernier : ils référencent des actions
        # définies dans backoffice_action_views.xml et mobile_users_backoffice_views.xml.
        'views/backoffice_menu_views.xml',
        'views/ticket_label_views.xml',
    ],
    'installable': True,
    'application': False,
    'auto_install': False,
}
