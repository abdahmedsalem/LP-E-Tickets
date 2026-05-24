import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/app_user.dart';
import '../../../data/models/station.dart';
import '../../../shared/widgets/api_required_view.dart';
import '../../../data/services/acpec_stations_mapper.dart';
import '../../../data/services/odoo_fueltoken_facade.dart';
import '../../../data/services/odoo_jsonrpc_client.dart'
    show OdooJsonRpcException;
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/app_status_lottie.dart';
import 'admin_shell_scaffold.dart';
import '../../auth/bloc/auth_bloc.dart';

class AdminStationsScreen extends StatefulWidget {
  const AdminStationsScreen({super.key});

  @override
  State<AdminStationsScreen> createState() => _AdminStationsScreenState();
}

class _AdminStationsScreenState extends State<AdminStationsScreen> {
  List<Station>? _acpecStations;
  bool _acpecLoading = false;
  String? _acpecError;

  @override
  void initState() {
    super.initState();
    if (AppEnvironment.useAcpecLiveData) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadAcpecStations());
    }
  }

  String _briefError(Object e) {
    if (e is OdooJsonRpcException && e.isOdooSessionExpired) {
      return 'Session expirée. Reconnectez-vous.';
    }
    return e.toString().replaceFirst('Exception: ', '').trim();
  }

  Future<void> _loadAcpecStations() async {
    if (!AppEnvironment.useAcpecLiveData) return;
    setState(() {
      _acpecLoading = true;
      _acpecError = null;
    });
    try {
      final user = context.read<AuthBloc>().state.user;
      if (user == null) throw Exception('Session requise.');
      final companyId = AppEnvironment.companyIdForUser(user);
      final raw = await OdooFueltokenFacade().adminStationsList(const {});
      final list = AcpecStationsMapper.fromRpcResult(
        raw,
        defaultCompanyId: companyId,
      );
      if (!mounted) return;
      setState(() {
        _acpecStations = list;
        _acpecLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _acpecError = _briefError(e);
        _acpecLoading = false;
      });
    }
  }

  Future<void> _openStationEditor({Station? existing}) async {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) return;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _StationEditorSheet(
        isCreate: existing == null,
        sessionUser: user,
        existing: existing,
      ),
    );
    if (ok == true && mounted) {
      await _loadAcpecStations();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            existing == null
                ? 'Station créée sur le serveur.'
                : 'Station mise à jour sur le serveur.',
          ),
        ),
      );
    }
  }

  Future<void> _onDisableStation(Station station) async {
    final sid = int.tryParse(station.id.trim());
    if (sid == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Identifiant station non numérique : impossible d’appeler disable.',
          ),
        ),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Désactiver cette station ?'),
        content: Text(
          '${station.name}\n\n'
          'La station sera enregistrée comme inactive.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Désactiver'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final raw = await OdooFueltokenFacade().adminStationsDisable({
        'station_id': sid,
      });
      _throwIfRpcBusinessError(raw);
      if (!mounted) return;
      await _loadAcpecStations();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Station désactivée (active = false).')),
      );
    } on OdooJsonRpcException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_briefError(e))));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_briefError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (AppEnvironment.useAcpecLiveData) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Stations'),
        ),
        body: _buildAcpecBody(),
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

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Stations'),
      ),
      body: const ApiRequiredView(),
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

  Widget _buildAcpecBody() {
    if (_acpecLoading && (_acpecStations == null || _acpecStations!.isEmpty)) {
      return const Center(child: AppLoadingLottie(size: 100));
    }
    if (_acpecError != null &&
        (_acpecStations == null || _acpecStations!.isEmpty)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 48,
                color: AppColors.danger.withValues(alpha: 0.85),
              ),
              const SizedBox(height: 16),
              Text(
                _acpecError!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _loadAcpecStations,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }

    final list = _acpecStations ?? const <Station>[];

    final activeCount = list.where((s) => s.active).length;
    final inactiveCount = list.length - activeCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: _StationTopChip(
                  label: 'Actives',
                  value: '$activeCount',
                  color: AppColors.success,
                  icon: Icons.check_circle_outline_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StationTopChip(
                  label: 'Inactives',
                  value: '$inactiveCount',
                  color: AppColors.warning,
                  icon: Icons.pause_circle_outline_rounded,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadAcpecStations,
            child: list.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 120),
                      EmptyState(
                        icon: Icons.local_gas_station_outlined,
                        title: 'Aucune station',
                        message:
                            'Le serveur n’a renvoyé aucune station pour ce périmètre.',
                        action: FilledButton.icon(
                          onPressed: () => _openStationEditor(),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Créer une station'),
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (ctx, i) => _AcpecStationCard(
                      station: list[i],
                      onEdit: () => _openStationEditor(existing: list[i]),
                      onDisableStation: list[i].active
                          ? _onDisableStation
                          : null,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

void _throwIfRpcBusinessError(dynamic raw) {
  if (raw is! Map) return;
  if (raw['ok'] == false) {
    throw Exception(raw['message']?.toString() ?? 'Opération refusée.');
  }
  final d = raw['data'];
  if (d is Map && d['ok'] == false) {
    throw Exception(d['message']?.toString() ?? 'Opération refusée.');
  }
}

String _stationSheetBriefError(Object e) {
  if (e is OdooJsonRpcException && e.isOdooSessionExpired) {
    return 'Session expirée. Reconnectez-vous.';
  }
  return e.toString().replaceFirst('Exception: ', '').trim();
}

class _StationTopChip extends StatelessWidget {
  const _StationTopChip({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _StationEditorSheet extends StatefulWidget {
  const _StationEditorSheet({
    required this.isCreate,
    required this.sessionUser,
    this.existing,
  });

  final bool isCreate;
  final AppUser sessionUser;
  final Station? existing;

  @override
  State<_StationEditorSheet> createState() => _StationEditorSheetState();
}

class _StationEditorSheetState extends State<_StationEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _code;
  late final TextEditingController _userId;
  late final TextEditingController _companyId;
  bool _active = true;
  bool _saving = false;
  String? _fieldError;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final u = widget.sessionUser;
    final cid = AppEnvironment.companyIdForUser(u);
    _name = TextEditingController(text: e?.name ?? '');
    _code = TextEditingController(text: e?.code ?? '');
    _userId = TextEditingController(text: _numericPrefill(u.id));
    _companyId = TextEditingController(text: _numericPrefill(cid));
    _active = e?.active ?? true;
  }

  /// Préremplit le champ seulement si la valeur est un entier Odoo plausible.
  static String _numericPrefill(String raw) {
    final n = int.tryParse(raw.trim());
    return n != null ? '$n' : '';
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _userId.dispose();
    _companyId.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _fieldError = null);
    final name = _name.text.trim();
    final code = _code.text.trim();
    if (name.isEmpty || code.isEmpty) {
      setState(() => _fieldError = 'Le nom et le code sont obligatoires.');
      return;
    }
    final uid = int.tryParse(_userId.text.trim());
    final comp = int.tryParse(_companyId.text.trim());
    if (uid == null || uid <= 0) {
      setState(() {
        _fieldError =
            'Indiquez un user_id Odoo numérique (ex. utilisateur rattaché à la station).';
      });
      return;
    }
    if (comp == null || comp <= 0) {
      setState(() {
        _fieldError = 'Indiquez un company_id Odoo numérique (ex. 1).';
      });
      return;
    }

    setState(() => _saving = true);
    try {
      final facade = OdooFueltokenFacade();
      final dynamic raw;
      if (widget.isCreate) {
        raw = await facade.adminStationsCreate({
          'name': name,
          'code': code,
          'user_id': uid,
          'company_id': comp,
          'active': _active,
        });
      } else {
        final sid = int.tryParse(widget.existing!.id.trim());
        if (sid == null || sid <= 0) {
          throw Exception(
            'Identifiant station non numérique : impossible d’appeler update.',
          );
        }
        raw = await facade.adminStationsUpdate({
          'station_id': sid,
          'name': name,
          'code': code,
          'user_id': uid,
          'company_id': comp,
          'active': _active,
        });
      }
      _throwIfRpcBusinessError(raw);
      if (!mounted) return;
      Navigator.pop(context, true);
    } on OdooJsonRpcException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_stationSheetBriefError(e))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_stationSheetBriefError(e))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final inset = MediaQuery.viewInsetsOf(context).bottom;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (ctx, scrollCtrl) {
        return Material(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          color: AppColors.surface,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.isCreate
                            ? 'Nouvelle station'
                            : 'Modifier la station',
                        style: GoogleFonts.dmSans(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              if (_fieldError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.dangerSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.danger.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      _fieldError!,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        height: 1.35,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottom + inset),
                  children: [
                    _SheetSectionTitle(
                      widget.isCreate
                          ? 'Nouvelle station'
                          : 'Modifier la station',
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Corps JSON attendu : name, code, user_id, company_id, active '
                      '(+ station_id pour la mise à jour).',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: AppColors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const _SheetSectionTitle('Identité'),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _name,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Nom affiché',
                        hintText: 'Ex. Station Tevragh Zeina',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _code,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Code',
                        hintText: 'Ex. ST-001',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 22),
                    const _SheetSectionTitle('Rattachements Odoo'),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _userId,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'user_id',
                        hintText: 'ID utilisateur Odoo (ex. 7)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _companyId,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'company_id',
                        hintText: 'ID société Odoo (ex. 1)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 22),
                    const _SheetSectionTitle('Statut'),
                    const SizedBox(height: 6),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Station active',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text(
                        'Si désactivée, la station ne doit plus être proposée aux flux métier.',
                        style: TextStyle(fontSize: 12, height: 1.3),
                      ),
                      value: _active,
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => _active = v),
                    ),
                    const SizedBox(height: 28),
                    FilledButton.icon(
                      onPressed: _saving ? null : _submit,
                      icon: _saving
                          ? const AppInlineLoading(size: 22)
                          : Icon(
                              widget.isCreate
                                  ? Icons.add_rounded
                                  : Icons.save_rounded,
                            ),
                      label: Text(
                        _saving
                            ? 'Enregistrement…'
                            : (widget.isCreate
                                  ? 'Créer sur le serveur'
                                  : 'Enregistrer les changements'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SheetSectionTitle extends StatelessWidget {
  const _SheetSectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.dmSans(
        fontSize: 14,
        fontWeight: FontWeight.w800,
        color: AppColors.ink,
        letterSpacing: -0.2,
      ),
    );
  }
}

class _AcpecStationCard extends StatelessWidget {
  const _AcpecStationCard({
    required this.station,
    required this.onEdit,
    this.onDisableStation,
  });

  final Station station;
  final VoidCallback onEdit;
  final Future<void> Function(Station)? onDisableStation;

  @override
  Widget build(BuildContext context) {
    final accent = station.active ? AppColors.success : AppColors.muted;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.line),
            boxShadow: AppColors.softShadow,
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(17),
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [accent, accent.withValues(alpha: 0.45)],
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                station.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                  color: AppColors.ink,
                                  height: 1.2,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _StatusPill(active: station.active),
                            if (station.active && onDisableStation != null)
                              PopupMenuButton<String>(
                                padding: EdgeInsets.zero,
                                icon: Icon(
                                  Icons.more_vert_rounded,
                                  color: AppColors.muted.withValues(
                                    alpha: 0.95,
                                  ),
                                ),
                                onSelected: (v) {
                                  if (v == 'disable') {
                                    onDisableStation!(station);
                                  }
                                },
                                itemBuilder: (ctx) => [
                                  const PopupMenuItem<String>(
                                    value: 'disable',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.do_not_disturb_on_outlined,
                                          size: 20,
                                          color: AppColors.danger,
                                        ),
                                        SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            'Désactiver (active = false)',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          station.code,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.muted,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.place_outlined,
                              size: 18,
                              color: AppColors.muted.withValues(alpha: 0.9),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                station.address,
                                style: const TextStyle(
                                  fontSize: 13,
                                  height: 1.35,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.body,
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
                            _MiniChip(
                              icon: Icons.apartment_outlined,
                              text: 'Société liée',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(
                    Icons.edit_outlined,
                    size: 20,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: active
            ? AppColors.success.withValues(alpha: 0.12)
            : AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: active
              ? AppColors.success.withValues(alpha: 0.35)
              : AppColors.lineSoft,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            active ? Icons.check_circle_outline : Icons.pause_circle_outline,
            size: 15,
            color: active ? AppColors.success : AppColors.muted,
          ),
          const SizedBox(width: 5),
          Text(
            active ? 'Active' : 'Inactive',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: active ? AppColors.success : AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.lineSoft),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.muted.withValues(alpha: 0.9)),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.body,
            ),
          ),
        ],
      ),
    );
  }
}
