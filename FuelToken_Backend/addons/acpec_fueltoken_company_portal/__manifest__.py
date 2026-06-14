{
    'name': 'ACPEC FuelToken Company Portal',
    'version': '19.0.1.1.0',
    'category': 'ACPEC/FuelToken',
    'summary': 'Portail société FuelToken : consultation et demande d’achat',
    'author': 'ACPEC SARL',
    'website': 'https://acpec.odoorim.com',
    'license': 'OPL-1',
    'depends': [
        'portal',
        'acpec_fueltoken_catalog',
        'acpec_fueltoken_company',
        'acpec_fueltoken_core',
        'acpec_fueltoken_purchase',
    ],
    'data': [
        'security/ir.model.access.csv',
        'security/company_portal_rules.xml',
        'views/company_portal_templates.xml',
    ],
    'installable': True,
    'application': False,
    'auto_install': False,
}
