{
    'name': 'ACPEC FuelToken Catalog',
    'version': '1.0.0',
    'category': 'ACPEC/FuelToken',
    'summary': 'Catalogue des types de carnets FuelToken',
    'author': 'ACPEC SARL',
    'website': 'https://acpec.odoorim.com',
    'license': 'OPL-1',
    'depends': ['acpec_fueltoken_base'],
    'data': [
        'security/ir.model.access.csv',
        'views/fuel_carnet_type_views.xml',
    ],
    'installable': True,
}
