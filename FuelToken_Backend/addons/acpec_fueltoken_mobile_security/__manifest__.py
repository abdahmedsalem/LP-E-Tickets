{
    'name': 'ACPEC FuelToken Mobile Security',
    'version': '19.0.1.0.0',
    'category': 'ACPEC/FuelToken',
    'summary': 'Contraintes de sécurité mobile spécifiques à FuelToken',
    'author': 'ACPEC SARL',
    'website': 'https://acpec.odoorim.com',
    'license': 'OPL-1',
    'depends': ['acpec_mobile_auth', 'acpec_fueltoken_base'],
    'data': [
        'security/ir.model.access.csv',
        'views/mobile_phone_change_views.xml',
        'views/mobile_user_blocking_views.xml',
    ],
    'installable': True,
    'application': False,
}
