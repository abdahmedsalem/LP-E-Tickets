import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/user_role.dart';

/// Retour : si la pile du tab a des écrans, pop ; sinon retour à l’accueil client.
void popOrGoClientHome(BuildContext context) {
  popOrGoRoleHome(context, UserRole.user);
}

/// Retour selon le rôle (client / station / admin) quand on est à la racine d’un onglet.
void popOrGoRoleHome(BuildContext context, UserRole role) {
  if (context.canPop()) {
    context.pop();
    return;
  }
  switch (role) {
    case UserRole.user:
      context.go('/home');
      return;
    case UserRole.station:
      context.go('/station');
      return;
    case UserRole.admin:
      context.go('/admin');
      return;
  }
}
