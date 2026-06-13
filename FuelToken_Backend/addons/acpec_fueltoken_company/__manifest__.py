{
    'name': 'ACPEC FuelToken Company Accounts',
    'version': '19.0.1.1.0',
    'category': 'ACPEC/FuelToken',
    'summary': 'Comptes Sociétés FuelToken pour le back-office ACPEC',
    'author': 'ACPEC SARL',
    'website': 'https://acpec.odoorim.com',
    'license': 'OPL-1',
    'depends': [
        'mail',
        'acpec_fueltoken_base',
        'acpec_fueltoken_backoffice_ui',
    ],
    'data': [
        'security/ir.model.access.csv',
        'security/fueltoken_company_rules.xml',
        'views/fuel_distributor_views.xml',
    ],
    'installable': True,
    'application': False,
    'auto_install': False,
}
