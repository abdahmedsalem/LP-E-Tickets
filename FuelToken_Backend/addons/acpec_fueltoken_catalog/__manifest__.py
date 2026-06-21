{
    'name': 'ACPEC Tickets Carburant Catalog',
    'version': '1.0.0',
    'category': 'ACPEC/Tickets Carburant',
    'summary': 'Catalogue des types de carnets FuelToken',
    'author': 'ACPEC SARL',
    'website': 'https://acpec.odoorim.com',
    'license': 'OPL-1',
    'depends': ['acpec_fueltoken_base'],
    'data': [
        'security/ir.model.access.csv',
        'security/fueltoken_catalog_rules.xml',
        'views/fuel_carnet_type_views.xml',
    ],
    'installable': True,
}
