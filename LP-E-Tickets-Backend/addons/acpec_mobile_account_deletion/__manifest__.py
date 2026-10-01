{
    'name': 'ACPEC Mobile Account Deletion Requests',
    'version': '19.0.1.0.2',
    'license': 'OPL-1',
    'depends': ['acpec_mobile_auth'],
    'data': [
        'security/ir.model.access.csv',
        'security/rules.xml',
        'data/config_data.xml',
        'data/cron_data.xml',
        'views/requests.xml',
    ],
    'installable': True,
}
