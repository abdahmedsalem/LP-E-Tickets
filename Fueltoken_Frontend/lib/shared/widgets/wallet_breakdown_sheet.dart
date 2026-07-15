import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

import '../../core/utils/formatters.dart';

import '../../data/models/wallet_breakdown_extras.dart';

import 'empty_state.dart';
import 'face_value_chip.dart';

/// Corps défilable : héros solde + répartitions (écran détail portefeuille).

class WalletBreakdownBody extends StatelessWidget {
  const WalletBreakdownBody({
    super.key,

    required this.walletAmountMru,

    this.totalTickets,

    this.extras,

    this.scrollController,

    this.padding = EdgeInsets.zero,
  });

  final int walletAmountMru;

  final int? totalTickets;

  final WalletBreakdownExtras? extras;

  final ScrollController? scrollController;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final bottom = MediaQuery.paddingOf(context).bottom;

    return ListView(
      controller: scrollController,

      padding: padding.add(EdgeInsets.only(bottom: 16 + bottom)),

      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),

          child: _WalletBreakdownHero(
            walletAmountMru: walletAmountMru,

            totalTickets: totalTickets,
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),

          child: Row(
            children: [
              Container(
                width: 4,

                height: 18,

                decoration: BoxDecoration(
                  color: AppColors.leaderGreen,

                  borderRadius: BorderRadius.circular(4),
                ),
              ),

              const SizedBox(width: 10),

              Text(
                'Répartition et suivi',

                style: TextStyle(
                  fontSize: 16,

                  fontWeight: FontWeight.w800,

                  color: scheme.onSurface,

                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
        ),

        Divider(
          height: 1,

          thickness: 1,

          color: scheme.outline.withValues(alpha: 0.18),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),

          child: Builder(
            builder: (context) {
              final e = extras;

              if (e == null || e.isEmpty) {
                return const EmptyState(
                  icon: Icons.insights_outlined,
                  title: 'Pas encore de détail à afficher',
                  message:
                      'Lorsque votre portefeuille contiendra plusieurs répartitions, elles apparaîtront ici.',
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,

                mainAxisSize: MainAxisSize.min,

                children: [
                  _Section(
                    title: 'Par valeur de face',

                    subtitle: 'Disponible, QR actif, bloqué, consommé, expiré',

                    child: _BreakdownBlock(
                      value: e.breakdownByFaceValue,

                      mode: _BreakdownDisplayMode.faceValue,
                    ),
                  ),

                  _Section(
                    title: 'Par type de carnet',

                    subtitle: 'Répartition par carnet',

                    child: _BreakdownBlock(
                      value: e.breakdownByCarnetType,

                      mode: _BreakdownDisplayMode.carnetType,
                    ),
                  ),

                  _Section(
                    title: 'Faces proches de l’expiration',

                    subtitle: 'À surveiller',

                    child: _FaceExpiryList(items: e.nearExpirationFaces),
                  ),

                  _Section(
                    title: 'Faces expirées',

                    subtitle: 'Non utilisables',

                    child: _FaceExpiryList(items: e.expiredFaces),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _WalletBreakdownHero extends StatelessWidget {
  const _WalletBreakdownHero({
    required this.walletAmountMru,

    this.totalTickets,
  });

  final int walletAmountMru;

  final int? totalTickets;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,

      decoration: BoxDecoration(
        gradient: AppColors.clientHomeWalletGradient,

        borderRadius: BorderRadius.circular(20),

        boxShadow: [
          BoxShadow(
            color: const Color(0xFF064E3B).withValues(alpha: 0.28),

            blurRadius: 20,

            offset: const Offset(0, 10),

            spreadRadius: -6,
          ),
        ],
      ),

      child: Stack(
        clipBehavior: Clip.none,

        children: [
          Positioned(
            right: -16,

            bottom: -8,

            child: Icon(
              Icons.account_balance_wallet_rounded,

              size: 96,

              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),

            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  'Vue d’ensemble',

                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),

                    fontSize: 12,

                    fontWeight: FontWeight.w700,

                    letterSpacing: 0.2,
                  ),
                ),

                const SizedBox(height: 10),

                FittedBox(
                  fit: BoxFit.scaleDown,

                  alignment: Alignment.centerLeft,

                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,

                    textBaseline: TextBaseline.alphabetic,

                    children: [
                      Text(
                        Formatters.numberFr(walletAmountMru),

                        style: TextStyle(
                          color: Colors.white,

                          fontSize: 36,

                          fontWeight: FontWeight.w800,

                          letterSpacing: -1,

                          height: 1,
                        ),
                      ),

                      SizedBox(width: 8),

                      Text(
                        Formatters.defaultCurrency,

                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),

                          fontSize: 15,

                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),

                if (totalTickets != null && totalTickets! > 0) ...[
                  const SizedBox(height: 14),

                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,

                      vertical: 8,
                    ),

                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),

                      borderRadius: BorderRadius.circular(999),

                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.28),
                      ),
                    ),

                    child: Row(
                      mainAxisSize: MainAxisSize.min,

                      children: [
                        Icon(
                          Icons.confirmation_number_outlined,

                          size: 18,

                          color: Colors.white.withValues(alpha: 0.95),
                        ),

                        const SizedBox(width: 8),

                        Text(
                          '${Formatters.numberFr(totalTickets!)} carnets actifs',

                          style: const TextStyle(
                            color: Colors.white,

                            fontSize: 13,

                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _BreakdownDisplayMode { faceValue, carnetType }

class _Section extends StatelessWidget {
  const _Section({required this.title, this.subtitle, required this.child});

  final String title;

  final String? subtitle;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final cardBg = Color.alphaBlend(
      scheme.primary.withValues(alpha: 0.04),

      scheme.surface,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),

      child: Container(
        width: double.infinity,

        decoration: BoxDecoration(
          color: cardBg,

          borderRadius: BorderRadius.circular(16),

          border: Border.all(color: scheme.outline.withValues(alpha: 0.22)),

          boxShadow: AppColors.softShadow,
        ),

        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            Text(
              title,

              style: TextStyle(
                fontSize: 13,

                fontWeight: FontWeight.w800,

                letterSpacing: -0.2,

                color: scheme.onSurface,
              ),
            ),

            if (subtitle != null) ...[
              const SizedBox(height: 2),

              Text(
                subtitle!,

                style: TextStyle(
                  fontSize: 11,

                  fontWeight: FontWeight.w500,

                  height: 1.3,

                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],

            const SizedBox(height: 10),

            child,
          ],
        ),
      ),
    );
  }
}

class _BreakdownBlock extends StatelessWidget {
  const _BreakdownBlock({required this.value, required this.mode});

  final Object? value;

  final _BreakdownDisplayMode mode;

  @override
  Widget build(BuildContext context) {
    if (value == null) {
      return _emptyHint(context, '—');
    }

    if (mode == _BreakdownDisplayMode.faceValue) {
      final rows = _WalletBreakdownParsers.faceRows(value);

      if (rows != null && rows.isNotEmpty) {
        return Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),

              _FaceBreakdownCard(row: rows[i]),
            ],
          ],
        );
      }

      final simple = _WalletBreakdownParsers.simpleFaceQtyMap(value);

      if (simple != null && simple.isNotEmpty) {
        return _SimpleFaceQtyGrid(map: simple);
      }
    } else {
      final carnet = _WalletBreakdownParsers.carnetRows(value);

      if (carnet != null && carnet.isNotEmpty) {
        return Column(
          children: [
            for (var i = 0; i < carnet.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),

              _CarnetBreakdownCard(row: carnet[i]),
            ],
          ],
        );
      }

      final faceAsCarnet = _WalletBreakdownParsers.faceRows(value);

      if (faceAsCarnet != null && faceAsCarnet.isNotEmpty) {
        return Column(
          children: [
            for (var i = 0; i < faceAsCarnet.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),

              _FaceBreakdownCard(row: faceAsCarnet[i]),
            ],
          ],
        );
      }
    }

    if (value is List) {
      final list = value as List<dynamic>;

      if (list.isEmpty) {
        return _emptyHint(context, 'Vide');
      }

      return _FaceExpiryList(items: list);
    }

    if (value is Map) {
      final m = Map<dynamic, dynamic>.from(value as Map);

      if (m.isEmpty) {
        return _emptyHint(context, 'Vide');
      }

      return _GenericKeyValueCard(entries: m.entries.toList());
    }

    return _monoCard(context, value.toString());
  }
}

// --- Parsers (tolère plusieurs formes API) -----------------------------

class _WalletBreakdownParsers {
  _WalletBreakdownParsers._();

  static int _n(dynamic v) {
    if (v == null) return 0;

    if (v is int) return v;

    if (v is num) return v.round();

    final s = v.toString().trim().replaceAll(',', '.');

    if (s.isEmpty) return 0;

    final d = double.tryParse(s);

    if (d != null) return d.round();

    return int.tryParse(s.split('.').first) ?? 0;
  }

  /// Lignes riches (qty + montants) par valeur de face.

  static List<Map<String, dynamic>>? faceRows(dynamic raw) {
    if (raw is List) {
      final out = <Map<String, dynamic>>[];

      for (final e in raw) {
        if (e is! Map) continue;

        final m = Map<String, dynamic>.from(e);

        final fv = _n(m['face_value'] ?? m['denomination'] ?? m['value']);

        if (fv <= 0) continue;

        out.add(m);
      }

      if (out.isEmpty) return null;

      out.sort(
        (a, b) => _n(
          b['face_value'] ?? b['denomination'] ?? b['value'],
        ).compareTo(_n(a['face_value'] ?? a['denomination'] ?? a['value'])),
      );

      return out;
    }

    if (raw is Map) {
      final out = <Map<String, dynamic>>[];

      for (final e in raw.entries) {
        if (e.value is Map) {
          final row = Map<String, dynamic>.from(e.value as Map);

          if (!row.containsKey('face_value') &&
              !row.containsKey('denomination')) {
            row['face_value'] = _n(e.key);
          }

          if (_n(row['face_value'] ?? row['denomination'] ?? 0) <= 0) {
            continue;
          }

          out.add(row);
        }
      }

      if (out.isEmpty) return null;

      out.sort(
        (a, b) => _n(
          b['face_value'] ?? b['denomination'] ?? b['value'],
        ).compareTo(_n(a['face_value'] ?? a['denomination'] ?? a['value'])),
      );

      return out;
    }

    return null;
  }

  /// Map simple valeur ? quantité (tickets disponibles seulement).

  static Map<int, int>? simpleFaceQtyMap(dynamic raw) {
    if (raw is! Map) return null;

    final out = <int, int>{};

    for (final e in raw.entries) {
      if (e.value is Map) return null;

      final fv = _n(e.key);

      final qty = _n(e.value);

      if (fv > 0 && qty != 0) {
        out[fv] = (out[fv] ?? 0) + qty;
      }
    }

    return out.isEmpty ? null : out;
  }

  static List<Map<String, dynamic>>? carnetRows(dynamic raw) {
    if (raw is List) {
      final out = <Map<String, dynamic>>[];

      for (final e in raw) {
        if (e is! Map) continue;

        final m = Map<String, dynamic>.from(e);

        final hasCarnet =
            m.containsKey('carnet_type_id') ||
            m.containsKey('carnet_type_code') ||
            m.containsKey('carnet_type_name') ||
            m.containsKey('carnet_code');

        if (!hasCarnet) continue;

        out.add(m);
      }

      return out.isEmpty ? null : out;
    }

    if (raw is Map) {
      final out = <Map<String, dynamic>>[];

      for (final e in raw.entries) {
        if (e.value is Map) {
          final row = Map<String, dynamic>.from(e.value as Map);

          if (!row.containsKey('carnet_type_id') &&
              !row.containsKey('carnet_type_code')) {
            row['carnet_type_code'] = e.key.toString();
          }

          out.add(row);
        }
      }

      return out.isEmpty ? null : out;
    }

    return null;
  }
}

// --- Carte « par valeur de face » --------------------------------------

class _FaceBreakdownCard extends StatelessWidget {
  const _FaceBreakdownCard({required this.row});

  final Map<String, dynamic> row;

  int _n(String k1, [String? k2]) {
    return _WalletBreakdownParsers._n(row[k1] ?? (k2 != null ? row[k2] : null));
  }

  @override
  Widget build(BuildContext context) {
    final fv = _WalletBreakdownParsers._n(
      row['face_value'] ?? row['denomination'] ?? row['value'],
    );

    final qAvail = _n('qty_available', 'available_qty');

    final qQr = _n('qty_qr_active');

    final qBlk = _n('qty_qr_blocked');

    final qCons = _n('qty_consumed');

    final qExp = _n('qty_expired');

    final aAvail = _pickAmount(row, 'amount_available', qAvail, fv);

    final aQr = _pickAmount(row, 'amount_qr_active', qQr, fv);

    final aBlk = _pickAmount(row, 'amount_qr_blocked', qBlk, fv);

    final aCons = _pickAmount(row, 'amount_consumed', qCons, fv);

    final aExp = _pickAmount(row, 'amount_expired', qExp, fv);

    final stats = <_StatEntry>[
      _StatEntry(
        Icons.account_balance_wallet_outlined,

        AppColors.success,

        'Disponible',

        qAvail,

        aAvail,
      ),

      _StatEntry(
        Icons.qr_code_2_rounded,

        AppColors.primary,

        'En QR actif',

        qQr,

        aQr,
      ),

      _StatEntry(
        Icons.lock_outline_rounded,

        AppColors.warning,

        'Bloqué',

        qBlk,

        aBlk,
      ),

      _StatEntry(
        Icons.local_gas_station_outlined,

        AppColors.body,

        'Consommé',

        qCons,

        aCons,
      ),

      _StatEntry(
        Icons.schedule_outlined,

        AppColors.muted,

        'Expiré',

        qExp,

        aExp,
      ),
    ];

    final totalTickets = qAvail + qQr + qBlk + qCons + qExp;

    return Container(
      width: double.infinity,

      decoration: BoxDecoration(
        color: AppColors.surface,

        borderRadius: BorderRadius.circular(18),

        border: Border.all(color: AppColors.line),

        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.04),

            blurRadius: 16,

            offset: const Offset(0, 6),
          ),
        ],
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,

        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),

            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primarySoft, AppColors.surface],

                begin: Alignment.topLeft,

                end: Alignment.bottomRight,
              ),

              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(17),
              ),
            ),

            child: Row(
              children: [
                FaceValueChip(value: fv, size: 48, gradient: true),

                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      Text(
                        'Billets à ${Formatters.money(fv)}',

                        style: TextStyle(
                          fontSize: 15,

                          fontWeight: FontWeight.w800,

                          color: AppColors.ink,

                          letterSpacing: -0.2,
                        ),
                      ),

                      const SizedBox(height: 2),

                      Text(
                        '${Formatters.numberFr(qAvail + qQr)} utilisables · ${Formatters.money(aAvail + aQr)}',

                        style: TextStyle(
                          fontSize: 12,

                          fontWeight: FontWeight.w600,

                          color: AppColors.body,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),

            child: totalTickets > 0
                ? _TicketMixBar(
                    segments: [
                      _BarSeg(qAvail, AppColors.success),

                      _BarSeg(qQr, AppColors.primary),

                      _BarSeg(qBlk, AppColors.warning),

                      _BarSeg(qCons, AppColors.body.withValues(alpha: 0.45)),

                      _BarSeg(qExp, AppColors.muted.withValues(alpha: 0.5)),
                    ],
                  )
                : Container(
                    height: 8,

                    decoration: BoxDecoration(
                      color: AppColors.lineSoft,

                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
          ),

          const Divider(height: 1, color: AppColors.lineSoft),

          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),

            child: Column(
              children: [
                for (final s in stats)
                  if (s.qty > 0 || s.amountMru > 0) _StatTile(entry: s),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static int _pickAmount(
    Map<String, dynamic> row,

    String amountKey,

    int qty,

    int fv,
  ) {
    final direct = _WalletBreakdownParsers._n(row[amountKey]);

    if (direct > 0) return direct;

    if (qty > 0 && fv > 0) return qty * fv;

    return 0;
  }
}

class _StatEntry {
  const _StatEntry(this.icon, this.color, this.label, this.qty, this.amountMru);

  final IconData icon;

  final Color color;

  final String label;

  final int qty;

  final int amountMru;
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.entry});

  final _StatEntry entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),

      child: Row(
        children: [
          Container(
            width: 36,

            height: 36,

            decoration: BoxDecoration(
              color: entry.color.withValues(alpha: 0.12),

              borderRadius: BorderRadius.circular(10),
            ),

            child: Icon(entry.icon, size: 18, color: entry.color),
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Text(
              entry.label,

              style: const TextStyle(
                fontSize: 13,

                fontWeight: FontWeight.w600,

                color: AppColors.ink2,
              ),
            ),
          ),

          Column(
            crossAxisAlignment: CrossAxisAlignment.end,

            children: [
              Text(
                '${Formatters.numberFr(entry.qty)} u.',

                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,

                  fontWeight: FontWeight.w700,

                  color: AppColors.ink,
                ),
              ),

              Text(
                Formatters.money(entry.amountMru),
                style: const TextStyle(
                  fontSize: 11,

                  fontWeight: FontWeight.w600,

                  color: AppColors.muted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BarSeg {
  const _BarSeg(this.qty, this.color);

  final int qty;

  final Color color;
}

class _TicketMixBar extends StatelessWidget {
  const _TicketMixBar({required this.segments});

  final List<_BarSeg> segments;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),

      child: SizedBox(
        height: 8,

        width: double.infinity,

        child: Row(
          children: [
            for (final s in segments)
              if (s.qty > 0)
                Expanded(
                  flex: s.qty,

                  child: Container(color: s.color),
                ),
          ],
        ),
      ),
    );
  }
}

// --- Grille simple (map valeur ? qty) ----------------------------------

class _SimpleFaceQtyGrid extends StatelessWidget {
  const _SimpleFaceQtyGrid({required this.map});

  final Map<int, int> map;

  @override
  Widget build(BuildContext context) {
    final entries = map.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));

    return Column(
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),

            decoration: BoxDecoration(
              color: AppColors.surface,

              borderRadius: BorderRadius.circular(16),

              border: Border.all(color: AppColors.line),
            ),

            child: Row(
              children: [
                FaceValueChip(value: entries[i].key, size: 44),

                const SizedBox(width: 12),

                Expanded(
                  child: Text(
                    '${Formatters.numberFr(entries[i].value)} ticket${entries[i].value > 1 ? 's' : ''} disponible${entries[i].value > 1 ? 's' : ''}',

                    style: const TextStyle(
                      fontSize: 13,

                      fontWeight: FontWeight.w600,

                      color: AppColors.body,
                    ),
                  ),
                ),

                Text(
                  Formatters.numberFr(entries[i].key * entries[i].value),

                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 15,

                    fontWeight: FontWeight.w800,

                    color: AppColors.ink,
                  ),
                ),

                SizedBox(width: 4),

                Text(
                  Formatters.defaultCurrency,

                  style: TextStyle(
                    fontSize: 10,

                    color: AppColors.muted,

                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// --- Carte « par type de carnet » -------------------------------------

class _CarnetBreakdownCard extends StatelessWidget {
  const _CarnetBreakdownCard({required this.row});

  final Map<String, dynamic> row;

  int _n(String k) => _WalletBreakdownParsers._n(row[k]);

  @override
  Widget build(BuildContext context) {
    final title = row['carnet_type_name']?.toString().trim().isNotEmpty == true
        ? row['carnet_type_name'].toString().trim()
        : (row['name']?.toString().trim().isNotEmpty == true
              ? row['name'].toString().trim()
              : (row['carnet_type_code']?.toString() ??
                    row['code']?.toString() ??
                    'Carnet ${_n('carnet_type_id')}'));

    final fv = _n('face_value');

    final qAvail = _n('qty_available') != 0
        ? _n('qty_available')
        : _n('available_qty');

    final qQr = _n('qty_qr_active');

    final qCons = _n('qty_consumed');

    final qExp = _n('qty_expired');

    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(14),

      decoration: BoxDecoration(
        color: AppColors.surface,

        borderRadius: BorderRadius.circular(16),

        border: Border.all(color: AppColors.line),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              Container(
                padding: const EdgeInsets.all(10),

                decoration: BoxDecoration(
                  color: AppColors.accentVioletSoft,

                  borderRadius: BorderRadius.circular(12),
                ),

                child: const Icon(
                  Icons.style_outlined,

                  color: AppColors.accentViolet,

                  size: 22,
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    Text(
                      title,

                      style: TextStyle(
                        fontSize: 14,

                        fontWeight: FontWeight.w800,

                        color: AppColors.ink,
                      ),
                    ),

                    if (fv > 0)
                      Text(
                        'Valeur de face ${Formatters.money(fv)}',

                        style: const TextStyle(
                          fontSize: 12,

                          fontWeight: FontWeight.w500,

                          color: AppColors.muted,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Wrap(
            spacing: 8,

            runSpacing: 8,

            children: [
              if (qAvail > 0) _MiniPill('Dispo', qAvail, AppColors.success),

              if (qQr > 0) _MiniPill('QR', qQr, AppColors.primary),

              if (qCons > 0) _MiniPill('Consommé', qCons, AppColors.body),

              if (qExp > 0) _MiniPill('Expiré', qExp, AppColors.muted),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniPill extends StatelessWidget {
  const _MiniPill(this.label, this.qty, this.color);

  final String label;

  final int qty;

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),

      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),

        borderRadius: BorderRadius.circular(999),

        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),

      child: Text(
        '$label · ${Formatters.numberFr(qty)}',

        style: TextStyle(
          fontSize: 11,

          fontWeight: FontWeight.w700,

          color: color,
        ),
      ),
    );
  }
}

// --- Faces expiration / expirées ---------------------------------------

class _FaceExpiryList extends StatelessWidget {
  const _FaceExpiryList({required this.items});

  final List<dynamic> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return _emptyHint(context, 'Aucun élément');
    }

    return Column(
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),

            child: _FaceExpiryTile(item: items[i]),
          ),
      ],
    );
  }
}

class _FaceExpiryTile extends StatelessWidget {
  const _FaceExpiryTile({required this.item});

  final dynamic item;

  @override
  Widget build(BuildContext context) {
    if (item is! Map) {
      return _monoCard(context, item.toString());
    }

    final m = Map<String, dynamic>.from(item);

    final fv = _WalletBreakdownParsers._n(
      m['face_value'] ?? m['denomination'] ?? m['value'],
    );

    final qty = _WalletBreakdownParsers._n(
      m['qty'] ?? m['qty_available'] ?? m['available_qty'] ?? m['quantity'],
    );

    final exp =
        m['expiration_date']?.toString() ??
        m['expiry']?.toString() ??
        m['expires_on']?.toString();

    final lot =
        m['lot_ref']?.toString() ??
        m['purchase_ref']?.toString() ??
        m['lot_id']?.toString();

    if (fv <= 0 && exp == null && lot == null) {
      return _GenericKeyValueCard(entries: m.entries.toList());
    }

    return Container(
      padding: const EdgeInsets.all(12),

      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,

        borderRadius: BorderRadius.circular(14),

        border: Border.all(color: AppColors.line),
      ),

      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          if (fv > 0) FaceValueChip(value: fv, size: 40, gradient: false),

          if (fv > 0) const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                if (qty > 0)
                  Text(
                    '$qty ticket${qty > 1 ? 's' : ''}',

                    style: const TextStyle(
                      fontSize: 13,

                      fontWeight: FontWeight.w700,

                      color: AppColors.ink,
                    ),
                  ),

                if (exp != null && exp.isNotEmpty)
                  Text(
                    'Échéance : $exp',

                    style: const TextStyle(fontSize: 12, color: AppColors.body),
                  ),

                if (lot != null && lot.isNotEmpty && lot != 'null')
                  Text(
                    'Lot : $lot',

                    style: const TextStyle(
                      fontSize: 11,

                      color: AppColors.muted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- Fallback lisible (sans JSON brut) ---------------------------------

class _GenericKeyValueCard extends StatelessWidget {
  const _GenericKeyValueCard({required this.entries});

  final List<MapEntry<dynamic, dynamic>> entries;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,

      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),

      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,

        borderRadius: BorderRadius.circular(14),

        border: Border.all(color: AppColors.line),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),

              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  Expanded(
                    flex: 2,

                    child: Text(
                      _humanKey(e.key.toString()),

                      style: const TextStyle(
                        fontSize: 12,

                        fontWeight: FontWeight.w700,

                        color: AppColors.body,
                      ),
                    ),
                  ),

                  Expanded(
                    flex: 3,

                    child: Text(
                      _humanValue(e.value),

                      textAlign: TextAlign.end,

                      style: TextStyle(
                        fontSize: 12,

                        fontWeight: FontWeight.w600,

                        color: AppColors.ink,

                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _humanKey(String k) {
    return k
        .replaceAll('_', ' ')
        .replaceAllMapped(RegExp(r'\b\w'), (m) => m.group(0)!.toUpperCase());
  }

  static String _humanValue(dynamic v) {
    if (v == null) return '—';

    if (v is Map) {
      final parts = <String>[];

      for (final e in v.entries) {
        parts.add('${_humanKey(e.key.toString())}: ${e.value}');
      }

      return parts.join(', ');
    }

    return v.toString();
  }
}

Widget _emptyHint(BuildContext context, String text) {
  final scheme = Theme.of(context).colorScheme;

  return Container(
    width: double.infinity,

    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),

    decoration: BoxDecoration(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.25),

      borderRadius: BorderRadius.circular(14),

      border: Border.all(color: scheme.outline.withValues(alpha: 0.2)),
    ),

    child: Text(
      text,

      style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
    ),
  );
}

Widget _monoCard(BuildContext context, String body) {
  final scheme = Theme.of(context).colorScheme;

  return Container(
    width: double.infinity,

    padding: const EdgeInsets.all(14),

    decoration: BoxDecoration(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),

      borderRadius: BorderRadius.circular(14),

      border: Border.all(color: scheme.outline.withValues(alpha: 0.25)),
    ),

    child: Text(
      body,

      style: TextStyle(
        fontSize: 12,

        height: 1.45,

        color: scheme.onSurface,

        fontWeight: FontWeight.w500,
      ),
    ),
  );
}
