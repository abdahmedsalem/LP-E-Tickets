{
    'name': 'ACPEC FuelToken Test',
    'version': '19.0.1.1.0',
    'summary': 'Console navigateur de test pour les APIs FuelToken',
    'description': 'Console navigateur pour tester les APIs ACPEC Mobile Auth et FuelToken du bundle courant.',
    'category': 'Tools',
    'author': 'ACPEC SARL',
    'website': 'https://acpec.odoorim.com',
    'license': 'OPL-1',
    'depends': ['web', 'acpec_mobile_auth', 'acpec_fueltoken_api'],
    'data': [
        'views/test_templates.xml',
    ],
    'application': False,
    'installable': True,
}
