{
    'name': 'ACPEC Mobile Account Deletion Requests',
    'version': '19.0.1.2.0',
    'license': 'OPL-1',
    'depends': ['acpec_mobile_auth', 'acpec_fueltoken_base', 'acpec_fueltoken_mobile_security', 'acpec_fueltoken_core', 'acpec_mobile_auth_otp'],
    'data': [
        'security/ir.model.access.csv',
        'security/rules.xml',
        'data/config_data.xml',
        'data/cron_data.xml',
        'views/requests.xml',
    ],
    'installable': True,
}
