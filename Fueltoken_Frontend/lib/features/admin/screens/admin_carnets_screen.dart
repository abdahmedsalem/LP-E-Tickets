import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/config/odoo_api_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/carnet_type.dart';
import '../../../data/services/acpec_carnet_catalog_service.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/odoo_jsonrpc_client.dart'
    show OdooJsonRpcException;
import '../../../shared/widgets/app_status_lottie.dart';
import 'admin_shell_scaffold.dart';
import '../../auth/bloc/auth_bloc.dart';

class AdminCarnetsScreen extends StatefulWidget {
  const AdminCarnetsScreen({super.key});
  @override
  State<AdminCarnetsScreen> createState() => _AdminCarnetsScreenState();
}

class _AdminCarnetsScreenState extends State<AdminCarnetsScreen> {
  List<CarnetType> _types = [];
  bool _loading = true;
  String? _loadError;
  AcpecCarnetCatalogLoadResult? _catalogResult;
  bool _catalogFromAdminTypesList = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  String _briefError(Object e) {
    if (e is OdooJsonRpcException && e.isOdooSessionExpired) {
      return 'Session Odoo expirée. Déconnectez-vous puis reconnectez-vous.';
    }
    final s = e.toString().replaceFirst('Exception: ', '').trim();
    if (s.isEmpty) return 'Une erreur est survenue.';
    if (s.length > 100) {
      return 'Une erreur est survenue. Réessayez ou reconnectez-vous.';
    }
    return s;
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      if (AppEnvironment.useAcpecLiveData) {
        final user = context.read<AuthBloc>().state.user;
        final result = await AcpecCarnetCatalogService.instance
            .loadAdminCatalog(companyId: AppEnvironment.companyIdForUser(user));
        if (mounted) {
          setState(() {
            _types = result.types;
            _catalogResult = result;
            _catalogFromAdminTypesList =
                AcpecCarnetCatalogService.lastCatalogTypesFromAdminList;
            _loading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _types = const [];
            _catalogResult = null;
            _catalogFromAdminTypesList = false;
            _loading = false;
            _loadError =
                'Connexion serveur ACPEC requise pour gérer les types de ticket.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = _briefError(e);
          _loading = false;
        });
      }
    }
  }

  void _showBackendMissingDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Accès à la gestion'),
        content: const Text(
          'La gestion des offres en ligne n’est pas disponible sur cette version '
          'de l’application. Contactez votre support pour plus d’informations.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _addNew() async {
    if (AppEnvironment.useAcpecLiveData) {
      if (!OdooApiConfig.isConfigured) {
        _showBackendMissingDialog();
        return;
      }
      if (!mounted) return;
      final user = context.read<AuthBloc>().state.user;
      final cid =
          int.tryParse(AppEnvironment.companyIdForUser(user).trim()) ?? 1;
      final ok = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => _CarnetTypeEditorSheet(
          mode: _CarnetEditorMode.create,
          defaultCompanyId: cid,
        ),
      );
      if (ok == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Type créé sur le serveur.')),
        );
        await _refresh();
      }
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Connexion serveur ACPEC requise pour créer un type de ticket.',
          ),
        ),
      );
    }
  }

  Future<void> _editType(CarnetType t) async {
    if (!AppEnvironment.useAcpecLiveData || !OdooApiConfig.isConfigured) return;
    final pid = int.tryParse(t.id.trim());
    if (pid == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Identifiant de type non numérique : modification via l’API impossible.',
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    final user = context.read<AuthBloc>().state.user;
    final cid = int.tryParse(AppEnvironment.companyIdForUser(user).trim()) ?? 1;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CarnetTypeEditorSheet(
        mode: _CarnetEditorMode.edit,
        defaultCompanyId: cid,
        existing: t,
        carnetTypeId: pid,
      ),
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Type mis à jour sur le serveur.')),
      );
      await _refresh();
    }
  }

  Future<void> _tryDelete(CarnetType t) async {
    final isAcpec = AppEnvironment.useAcpecLiveData;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isAcpec ? 'Désactiver ce type ?' : 'Supprimer ce type ?'),
        content: Text(
          isAcpec
              ? '${t.code} · ${t.name}\n\n'
                    'Le type sera marqué comme inactif sur le serveur.'
              : '${t.code} · ${t.name}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: Text(isAcpec ? 'Désactiver' : 'Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (isAcpec) {
      if (!OdooApiConfig.isConfigured) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Serveur Odoo non configuré.')),
        );
        return;
      }
      final pk = int.tryParse(t.id.trim());
      if (pk == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Identifiant non numérique : impossible d’appeler carnet-types/delete.',
            ),
          ),
        );
        return;
      }
      try {
        await OdooFueltokenFacade().adminCarnetTypesDelete({
          'carnet_type_id': pk,
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Type désactivé sur le serveur (active = false).'),
          ),
        );
        await _refresh();
      } on OdooJsonRpcException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.isOdooSessionExpired
                  ? 'Session expirée. Reconnectez-vous.'
                  : e.message,
            ),
          ),
        );
      } catch (err) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_briefError(err))));
      }
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Connexion serveur ACPEC requise pour supprimer ce type.',
          ),
        ),
      );
    }
  }

  bool get _showCatalogStatusCard {
    if (!AppEnvironment.useAcpecLiveData) return false;
    final r = _catalogResult;
    if (r == null) return false;
    if (_catalogFromAdminTypesList) return false;
    if (r.bothRpcFailed) return true;
    final facesOnly = r.facesOnlyQuery;
    return facesOnly
        ? r.facesError != null
        : (r.facesError != null ||
              r.walletError != null ||
              r.purchasesError != null);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: scheme.onSurface,
        automaticallyImplyLeading: false,
        title: Text(
          'Types de carnet',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: scheme.onSurface,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addNew,
        backgroundColor: AppColors.primary,
        tooltip: 'Nouveau type de carnet',
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Nouveau type',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
      body: _loading
          ? const Center(child: AppLoadingLottie(size: 100))
          : _loadError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _loadError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                itemCount:
                    _types.length +
                    (_showCatalogStatusCard ? 1 : 0) +
                    (_types.isEmpty ? 1 : 0),
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) {
                  if (_showCatalogStatusCard && i == 0) {
                    final r = _catalogResult!;
                    final bothFailed = r.bothRpcFailed;
                    return Card(
                      color: bothFailed
                          ? AppColors.dangerSurface
                          : AppColors.warningSurface,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              bothFailed
                                  ? 'Connexion interrompue'
                                  : 'Synchronisation partielle',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: bothFailed
                                    ? AppColors.danger
                                    : AppColors.warning,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              bothFailed
                                  ? 'Impossible de charger les types. Vérifiez le réseau puis réessayez.'
                                  : 'Certains éléments n’ont pas pu être chargés. La liste peut être incomplète.',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  final statusOffset = _showCatalogStatusCard ? 1 : 0;
                  if (_types.isEmpty && i == statusOffset) {
                    final failed = _catalogResult?.bothRpcFailed ?? false;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Text(
                        failed
                            ? 'Aucun type pour l’instant. Vérifiez la connexion puis réessayez.'
                            : 'Aucun type de carnet. Appuyez sur + pour en créer un.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: failed
                              ? AppColors.danger
                              : AppColors.textMuted,
                          fontWeight: failed
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    );
                  }
                  final idx = i - statusOffset;
                  if (idx < 0 || idx >= _types.length) {
                    return const SizedBox.shrink();
                  }
                  final t = _types[idx];
                  return _AdminCarnetTypeCard(
                    type: t,
                    onEdit:
                        AppEnvironment.useAcpecLiveData &&
                            OdooApiConfig.isConfigured &&
                            int.tryParse(t.id.trim()) != null
                        ? () => _editType(t)
                        : null,
                    onDelete:
                        (!AppEnvironment.useAcpecLiveData ||
                            OdooApiConfig.isConfigured)
                        ? () => _tryDelete(t)
                        : null,
                    deleteTooltip: AppEnvironment.useAcpecLiveData
                        ? 'Désactiver (active = false)'
                        : 'Retirer',
                  );
                },
              ),
            ),
      bottomNavigationBar: AdminBottomTabsBar(
        selectedIndex: 2,
        onTap: (index) {
          switch (index) {
            case 0:
              context.go('/admin');
              return;
            case 1:
              context.go('/admin/achats');
              return;
            case 2:
              context.go('/admin/profile');
              return;
          }
        },
      ),
    );
  }
}

enum _CarnetEditorMode { create, edit }

class _CarnetTypeEditorSheet extends StatefulWidget {
  const _CarnetTypeEditorSheet({
    required this.mode,
    required this.defaultCompanyId,
    this.existing,
    this.carnetTypeId,
  });

  final _CarnetEditorMode mode;
  final int defaultCompanyId;
  final CarnetType? existing;
  final int? carnetTypeId;

  @override
  State<_CarnetTypeEditorSheet> createState() => _CarnetTypeEditorSheetState();
}

String _carnetCodeFrom(int faceCount, int faceValue) =>
    'C${faceCount}T-$faceValue';

String _carnetPreviewFrom(int faceCount, int faceValue, String currency) {
  final base = _carnetCodeFrom(faceCount, faceValue);
  final c = currency.trim();
  return c.isEmpty ? '$base + devise société' : '$base$c';
}

class _CarnetTypeEditorSheetState extends State<_CarnetTypeEditorSheet> {
  late final TextEditingController _faceCount;
  late final TextEditingController _faceValue;
  late final TextEditingController _validityDays;
  bool _submitting = false;

  bool get _isEdit => widget.mode == _CarnetEditorMode.edit;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _faceCount = TextEditingController(text: '${e.size}');
      _faceValue = TextEditingController(text: '${e.faceValue}');
      _validityDays = TextEditingController(text: '${e.validityDays}');
    } else {
      _faceCount = TextEditingController();
      _faceValue = TextEditingController();
      _validityDays = TextEditingController();
    }
  }

  @override
  void dispose() {
    _faceCount.dispose();
    _faceValue.dispose();
    _validityDays.dispose();
    super.dispose();
  }

  int? get _parsedFaceCount => int.tryParse(_faceCount.text.trim());

  int? get _parsedFaceValue => int.tryParse(_faceValue.text.trim());

  int? get _parsedValidityDays => int.tryParse(_validityDays.text.trim());

  String get _previewName {
    final fc = _parsedFaceCount;
    final fv = _parsedFaceValue;
    if (fc == null || fv == null || fc <= 0 || fv <= 0) return '—';
    return _carnetPreviewFrom(fc, fv, widget.existing?.displayCurrency ?? '');
  }

  Future<void> _submit() async {
    final fc = _parsedFaceCount ?? 0;
    final fv = _parsedFaceValue ?? 0;
    final vd = _parsedValidityDays ?? 0;
    if (fc <= 0 || fv <= 0 || vd <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Indiquez le nombre de tickets, la valeur nominale et la durée de validité.',
          ),
        ),
      );
      return;
    }
    final cid = widget.defaultCompanyId;
    setState(() => _submitting = true);
    try {
      final base = <String, dynamic>{
        'face_count': fc,
        'face_value': fv,
        'validity_days': vd,
        'company_id': cid,
        'active': _isEdit ? (widget.existing?.active ?? true) : true,
      };
      if (widget.mode == _CarnetEditorMode.edit) {
        final id = widget.carnetTypeId;
        if (id == null) throw Exception('carnet_type_id manquant.');
        await OdooFueltokenFacade().adminCarnetTypesUpdate({
          'carnet_type_id': id,
          ...base,
        });
      } else {
        await OdooFueltokenFacade().adminCarnetTypesCreate(base);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on OdooJsonRpcException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.isOdooSessionExpired
                ? 'Session expirée. Reconnectez-vous.'
                : e.message,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final isEdit = _isEdit;
    final lineAmount = (_parsedFaceCount ?? 0) * (_parsedFaceValue ?? 0);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          border: Border.all(color: AppColors.line),
          boxShadow: AppColors.softShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primarySurface,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      isEdit ? Icons.edit_outlined : Icons.add_circle_outline,
                      color: AppColors.primaryDark,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isEdit
                              ? 'Modifier le type'
                              : 'Nouveau type de carnet',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isEdit
                              ? 'Ajustez les paramètres du carnet'
                              : 'Le nom et le code sont générés automatiquement',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.muted,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 12 + bottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _faceCount,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Nombre de tickets par carnet',
                        hintText: 'Ex. 10',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _faceValue,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Valeur nominale du ticket',
                        hintText: 'Ex. 500',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _validityDays,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Validité (jours après validation du lot)',
                        hintText: 'Ex. 365',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.lineSoft),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Identifiants générés',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.muted.withValues(alpha: 0.95),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _previewName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.infoSurface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.12),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.calculate_outlined,
                            size: 20,
                            color: AppColors.primaryDark.withValues(alpha: 0.9),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              lineAmount > 0
                                  ? 'Montant carnet : ${Formatters.money(lineAmount)}'
                                  : 'Montant carnet calculé à partir des champs ci-dessus',
                              style: const TextStyle(
                                fontSize: 12,
                                height: 1.35,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primaryDark,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _submitting ? null : _submit,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _submitting
                          ? const AppInlineLoading(size: 22)
                          : Text(
                              isEdit ? 'Enregistrer' : 'Créer',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminCarnetTypeCard extends StatelessWidget {
  const _AdminCarnetTypeCard({
    required this.type,
    this.onEdit,
    this.onDelete,
    this.deleteTooltip = 'Retirer',
  });

  final CarnetType type;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final String deleteTooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = type.active ? AppColors.success : AppColors.muted;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.18)),
        boxShadow: AppColors.softShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 10, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            type.name,
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: scheme.onSurface,
                              height: 1.2,
                              letterSpacing: -0.15,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            type.active ? 'Actif' : 'Inactif',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: accent,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _StatChip(
                          icon: Icons.payments_outlined,
                          label:
                              '${Formatters.number(type.faceValue)} ${type.displayCurrency}',
                          accent: AppColors.primary,
                        ),
                        _StatChip(
                          icon: Icons.confirmation_number_outlined,
                          label:
                              '${type.size} ticket${type.size > 1 ? 's' : ''}',
                          accent: AppColors.success,
                        ),
                        _StatChip(
                          icon: Icons.summarize_outlined,
                          label:
                              '${Formatters.number(type.totalAmount)} ${type.displayCurrency}',
                          accent: accent,
                        ),
                        _StatChip(
                          icon: Icons.event_outlined,
                          label: '${type.validityDays} j après validation',
                          accent: AppColors.warning,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (onEdit != null || onDelete != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (onEdit != null)
                      _CardActionButton(
                        icon: Icons.edit_outlined,
                        color: AppColors.primaryDark,
                        tooltip: 'Modifier',
                        onPressed: onEdit,
                      ),
                    if (onDelete != null)
                      _CardActionButton(
                        icon: Icons.delete_outline_rounded,
                        color: AppColors.danger,
                        tooltip: deleteTooltip,
                        onPressed: onDelete,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CardActionButton extends StatelessWidget {
  const _CardActionButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: color.withValues(alpha: 0.10),
        foregroundColor: color,
      ),
      icon: Icon(icon, size: 20),
      onPressed: onPressed,
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: accent),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}
