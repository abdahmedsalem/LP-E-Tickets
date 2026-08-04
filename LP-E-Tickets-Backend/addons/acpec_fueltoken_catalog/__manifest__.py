{
    'name': 'ACPEC Tickets Carburant Catalog',
    'version': '19.0.1.0.2',
    'category': 'ACPEC/Tickets Carburant',
    'summary': 'Catalogue des types de carnets FuelToken',
    'author': 'ACPEC SARL',
    'website': 'https://acpec.odoorim.com',
    'license': 'OPL-1',
    'depends': ['acpec_fueltoken_base'],
    'data': [
        'security/ir.model.access.csv',
        'security/fueltoken_catalog_rules.xml',
        'data/carnet_type_label_recompute_data.xml',
        'views/fuel_carnet_type_views.xml',
    ],
    'installable': True,
}
