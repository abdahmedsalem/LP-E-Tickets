{
    'name': 'ACPEC FuelToken Base',
    'version': '1.0.0',
    'category': 'ACPEC/FuelToken',
    'summary': 'Socle commun FuelToken',
    'author': 'ACPEC SARL',
    'website': 'https://acpec.odoorim.com',
    'license': 'OPL-1',
    'depends': ['base', 'mail'],
    'data': [
        'security/fueltoken_base_groups.xml',
        'security/ir.model.access.csv',
        'data/ir_sequence_data.xml',
        'views/fueltoken_base_menu_views.xml',
    ],
    'installable': True,
    'application': True,
}
