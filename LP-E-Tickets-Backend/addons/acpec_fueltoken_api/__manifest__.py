{
    'name': 'ACPEC FuelToken API',
    'version': '19.0.1.2.16',
    'category': 'ACPEC/FuelToken',
    'summary': 'API mobile et station FuelToken',
    'author': 'ACPEC SARL',
    'website': 'https://acpec.odoorim.com',
    'license': 'OPL-1',
    'depends': ['acpec_mobile_auth', 'acpec_mobile_auth_otp', 'acpec_fueltoken_core', 'acpec_fueltoken_mobile_security'],
    'data': [
        'views/fuel_transaction_mobile_audit_views.xml',
    ],
    'installable': True,
}
