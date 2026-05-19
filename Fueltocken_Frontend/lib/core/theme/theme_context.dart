import 'package:flutter/material.dart';

/// Couleurs dérivées du [Theme] courant (clair / sombre synchronisés).
extension FuelThemeContext on BuildContext {
  Color get fuelPageBackground => Theme.of(this).scaffoldBackgroundColor;

  Color get fuelSurface => Theme.of(this).colorScheme.surface;

  Color get fuelSurfaceContainerLow =>
      Theme.of(this).colorScheme.surfaceContainerLow;

  Color get fuelSurfaceContainerHigh =>
      Theme.of(this).colorScheme.surfaceContainerHighest;

  Color get fuelOnSurface => Theme.of(this).colorScheme.onSurface;

  Color get fuelOnSurfaceMuted =>
      Theme.of(this).colorScheme.onSurfaceVariant;

  Color get fuelOutline => Theme.of(this).colorScheme.outline;

  bool get fuelIsDark => Theme.of(this).brightness == Brightness.dark;
}
