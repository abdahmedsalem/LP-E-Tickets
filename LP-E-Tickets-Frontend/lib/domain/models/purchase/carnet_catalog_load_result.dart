import 'carnet_type.dart';

/// Résultat métier du chargement du catalogue, y compris les diagnostics
/// nécessaires à l'interface lorsque certaines sources sont indisponibles.
class AcpecCarnetCatalogLoadResult {
  const AcpecCarnetCatalogLoadResult({
    required this.types,
    this.facesOnlyQuery = false,
    this.carnetTypesFromAdminList = false,
    this.carnetTypesError,
    this.carnetTypesResponsePreview,
    this.facesError,
    this.facesResponsePreview,
    this.walletError,
    this.walletResponsePreview,
    this.purchasesError,
    this.purchasesResponsePreview,
  });

  final List<CarnetType> types;
  final bool carnetTypesFromAdminList;
  final String? carnetTypesError;
  final String? carnetTypesResponsePreview;
  final bool facesOnlyQuery;
  final String? facesError;
  final String? facesResponsePreview;
  final String? walletError;
  final String? walletResponsePreview;
  final String? purchasesError;
  final String? purchasesResponsePreview;

  bool get bothRpcFailed {
    if (facesOnlyQuery) {
      return types.isEmpty && facesError != null && carnetTypesError != null;
    }
    return types.isEmpty &&
        facesError != null &&
        walletError != null &&
        purchasesError != null;
  }

  bool get hasAnyRpcSuccess {
    if (facesOnlyQuery) return facesError == null || carnetTypesError == null;
    return facesError == null ||
        walletError == null ||
        purchasesError == null ||
        carnetTypesError == null;
  }
}
