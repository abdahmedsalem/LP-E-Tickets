def post_init_hook(env):
    """Patch36A: installing the test console must not mutate security settings."""
    return


def uninstall_hook(env):
    """Patch36A: uninstalling the test console must not mutate security settings."""
    return
