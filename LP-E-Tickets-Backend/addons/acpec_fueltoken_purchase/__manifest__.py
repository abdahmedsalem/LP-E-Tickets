{
    'name': 'ACPEC FuelToken Purchase',
    'version': '19.0.1.0.6',
    'category': 'ACPEC/FuelToken',
    'summary': 'Lots d’achat de carnets FuelToken',
    'author': 'ACPEC SARL',
    'website': 'https://acpec.odoorim.com',
    'license': 'OPL-1',
    'depends': ['acpec_fueltoken_catalog'],
    'data': [
        'security/ir.model.access.csv',
        'security/fueltoken_purchase_rules.xml',
        'data/fuel_payment_method_data.xml',
        'views/fuel_payment_method_views.xml',
        'views/fuel_purchase_views.xml',
    ],
    'installable': True,
}
