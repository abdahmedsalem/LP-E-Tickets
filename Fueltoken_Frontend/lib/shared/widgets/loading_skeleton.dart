import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

enum AppLoadingSkeletonStyle {
  historyRows,
  qrCards,
  ticketGroups,
  purchaseOffers,
  qrGeneration,
}

class AppLoadingSkeleton extends StatefulWidget {
  const AppLoadingSkeleton({
    super.key,
    required this.style,
    this.itemCount = 5,
  });

  final AppLoadingSkeletonStyle style;
  final int itemCount;

  @override
  State<AppLoadingSkeleton> createState() => _AppLoadingSkeletonState();
}

class _AppLoadingSkeletonState extends State<AppLoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final opacity = 0.34 + (_controller.value * 0.36);
        switch (widget.style) {
          case AppLoadingSkeletonStyle.historyRows:
            return _HistorySkeletonList(
              opacity: opacity,
              itemCount: widget.itemCount,
            );
          case AppLoadingSkeletonStyle.qrCards:
            return _QrSkeletonList(
              opacity: opacity,
              itemCount: widget.itemCount,
            );
          case AppLoadingSkeletonStyle.ticketGroups:
            return _TicketSkeletonList(
              opacity: opacity,
              itemCount: widget.itemCount,
            );
          case AppLoadingSkeletonStyle.purchaseOffers:
            return _PurchaseSkeletonGrid(
              opacity: opacity,
              itemCount: widget.itemCount,
            );
          case AppLoadingSkeletonStyle.qrGeneration:
            return _QrGenerationSkeleton(
              opacity: opacity,
              itemCount: widget.itemCount,
            );
        }
      },
    );
  }
}

class _HistorySkeletonList extends StatelessWidget {
  const _HistorySkeletonList({required this.opacity, required this.itemCount});

  final double opacity;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < itemCount; i++) ...[
          _HistorySkeletonRow(opacity: opacity),
          if (i != itemCount - 1)
            const Divider(height: 1, thickness: 1, color: Color(0xFFE9ECEF)),
        ],
      ],
    );
  }
}

class _HistorySkeletonRow extends StatelessWidget {
  const _HistorySkeletonRow({required this.opacity});

  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 14, 4, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkeletonBlock(width: 118, height: 15, opacity: opacity),
                const SizedBox(height: 7),
                _SkeletonBlock(width: 82, height: 11, opacity: opacity),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _SkeletonBlock(width: 58, height: 13, opacity: opacity),
              const SizedBox(height: 5),
              _SkeletonBlock(width: 34, height: 10, opacity: opacity),
            ],
          ),
        ],
      ),
    );
  }
}

class _QrSkeletonList extends StatelessWidget {
  const _QrSkeletonList({required this.opacity, required this.itemCount});

  final double opacity;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < itemCount; i++) ...[
          _QrSkeletonCard(opacity: opacity),
          if (i != itemCount - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _QrSkeletonCard extends StatelessWidget {
  const _QrSkeletonCard({required this.opacity});

  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.line.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        children: [
          _SkeletonBlock(width: 58, height: 58, opacity: opacity, radius: 14),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkeletonBlock(width: 74, height: 16, opacity: opacity),
                const SizedBox(height: 8),
                _SkeletonBlock(width: 104, height: 11, opacity: opacity),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _SkeletonBlock(width: 58, height: 13, opacity: opacity),
              const SizedBox(height: 5),
              _SkeletonBlock(width: 28, height: 10, opacity: opacity),
            ],
          ),
        ],
      ),
    );
  }
}

class _TicketSkeletonList extends StatelessWidget {
  const _TicketSkeletonList({required this.opacity, required this.itemCount});

  final double opacity;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < itemCount; i++) ...[
          _TicketSkeletonCard(opacity: opacity),
          if (i != itemCount - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _PurchaseSkeletonGrid extends StatelessWidget {
  const _PurchaseSkeletonGrid({required this.opacity, required this.itemCount});

  final double opacity;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: itemCount,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: 54,
      ),
      itemBuilder: (context, _) => _PurchaseOfferSkeletonCard(opacity: opacity),
    );
  }
}

class _PurchaseOfferSkeletonCard extends StatelessWidget {
  const _PurchaseOfferSkeletonCard({required this.opacity});

  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          _SkeletonBlock(width: 22, height: 22, opacity: opacity, radius: 8),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkeletonBlock(width: 54, height: 12, opacity: opacity),
                const SizedBox(height: 4),
                _SkeletonBlock(width: 38, height: 10, opacity: opacity),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _SkeletonBlock(width: 26, height: 14, opacity: opacity),
        ],
      ),
    );
  }
}

class _QrGenerationSkeleton extends StatelessWidget {
  const _QrGenerationSkeleton({required this.opacity, required this.itemCount});

  final double opacity;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        _SkeletonBlock(width: 120, height: 12, opacity: opacity),
        const SizedBox(height: 12),
        for (var i = 0; i < itemCount; i++) ...[
          _QrGenerationRowSkeleton(opacity: opacity),
          if (i != itemCount - 1) const SizedBox(height: 10),
        ],
        const SizedBox(height: 18),
        _SkeletonBlock(width: 160, height: 12, opacity: opacity),
        const SizedBox(height: 10),
        _SkeletonBlock(
          width: double.infinity,
          height: 96,
          opacity: opacity,
          radius: 20,
        ),
      ],
    );
  }
}

class _QrGenerationRowSkeleton extends StatelessWidget {
  const _QrGenerationRowSkeleton({required this.opacity});

  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          _SkeletonBlock(width: 56, height: 56, opacity: opacity, radius: 16),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkeletonBlock(width: 116, height: 14, opacity: opacity),
                const SizedBox(height: 6),
                _SkeletonBlock(width: 88, height: 11, opacity: opacity),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _SkeletonBlock(width: 42, height: 14, opacity: opacity),
        ],
      ),
    );
  }
}

class _TicketSkeletonCard extends StatelessWidget {
  const _TicketSkeletonCard({required this.opacity});

  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _SkeletonBlock(
                  width: 60,
                  height: 60,
                  opacity: opacity,
                  radius: 30,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SkeletonBlock(width: 142, height: 15, opacity: opacity),
                      const SizedBox(height: 6),
                      _SkeletonBlock(width: 82, height: 11, opacity: opacity),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _SkeletonBlock(width: 58, height: 15, opacity: opacity),
                    const SizedBox(height: 5),
                    _SkeletonBlock(width: 30, height: 10, opacity: opacity),
                  ],
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.lineSoft)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Column(
                children: [
                  _SkeletonBlock(
                    width: double.infinity,
                    height: 14,
                    opacity: opacity,
                  ),
                  const SizedBox(height: 10),
                  _SkeletonBlock(
                    width: double.infinity,
                    height: 14,
                    opacity: opacity,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({
    required this.width,
    required this.height,
    required this.opacity,
    this.radius = 999,
  });

  final double width;
  final double height;
  final double opacity;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final block = Container(
      width: width.isFinite ? width : double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFDDE3E8),
        borderRadius: BorderRadius.circular(radius),
      ),
    );

    return Opacity(
      opacity: opacity,
      child: width.isFinite
          ? block
          : SizedBox(width: double.infinity, child: block),
    );
  }
}
