# -*- coding: utf-8 -*-


def _test_mobile_phone(label):
    value = 2166136261

    for char in str(label):
        value ^= ord(char)
        value = (value * 16777619) % 1000000

    return "23%06d" % value


def _group_ids(env, xmlids):
    result = []

    for xmlid in xmlids:
        group = env.ref(
            xmlid,
            raise_if_not_found=False,
        )
        if group:
            result.append(group.id)

    return result


def create_mobile_test_user(
    env,
    company,
    label,
    role,
    partner=False,
):
    role_groups = {
        'client': (
            'base.group_portal',
            'acpec_mobile_auth.group_mobile_auth_user',
            'acpec_fueltoken_base.group_fuel_user',
        ),
        'station': (
            'base.group_portal',
            'acpec_mobile_auth.group_mobile_auth_user',
            'acpec_fueltoken_base.group_fuel_station',
        ),
        'manager': (
            'base.group_portal',
            'acpec_mobile_auth.group_mobile_auth_user',
            'acpec_fueltoken_base.group_fuel_manager',
        ),
    }

    if role not in role_groups:
        raise ValueError(
            "Rôle mobile de test inconnu : %s"
            % role
        )

    phone = _test_mobile_phone(
        "%s-%s"
        % (
            role,
            label,
        )
    )

    user_model = env[
        'res.users'
    ].sudo().with_context(
        acpec_mobile_allow_password_write=True,
        no_reset_password=True,
    )

    vals = {
        'name': '[TEST_ODOO_AUTO] %s' % label,
        'login': phone,
        'email': '%s@example.test' % phone,
        'active': True,
        'company_id': company.id,
        'company_ids': [
            (
                6,
                0,
                [company.id],
            ),
        ],
        'group_ids': [
            (
                6,
                0,
                _group_ids(
                    env,
                    role_groups[role],
                ),
            ),
        ],
    }

    if partner:
        partner = env[
            'res.partner'
        ].sudo().browse(
            partner.id
            if hasattr(partner, 'id')
            else int(partner or 0)
        ).exists()

        if not partner:
            raise ValueError(
                "Partenaire de l'utilisateur test introuvable."
            )

        partner.sudo().write({
            'company_id': company.id,
        })
        vals['partner_id'] = partner.id

    if 'mobile_phone' in user_model._fields:
        vals['mobile_phone'] = phone

    if 'acpec_mobile_phone' in user_model._fields:
        vals['acpec_mobile_phone'] = phone

    if 'acpec_mobile_only' in user_model._fields:
        vals['acpec_mobile_only'] = True

    if 'acpec_mobile_state' in user_model._fields:
        vals['acpec_mobile_state'] = 'approved'

    unusable_password = getattr(
        user_model,
        '_acpec_mobile_unusable_password',
        False,
    )
    if unusable_password:
        vals['password'] = (
            user_model._acpec_mobile_unusable_password()
        )

    user = user_model.create(vals)

    if hasattr(user, 'set_mobile_pin'):
        user.set_mobile_pin('1234')

    return user
