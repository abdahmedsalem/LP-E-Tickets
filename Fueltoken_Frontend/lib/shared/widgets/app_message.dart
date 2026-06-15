import 'dart:async';

import 'package:flutter/material.dart';

/// Système de messages contextuels en haut de l'écran.
///
/// Usage :
///   AppMessage.error(context, 'Numéro de téléphone obligatoire.');
///   AppMessage.success(context, 'Transfert confirmé avec succès.');
///   AppMessage.warning(context, 'Aucun carnet sélectionné.');
///   AppMessage.info(context, 'Code OTP envoyé par SMS.');
class AppMessage {
  AppMessage._();

  // ─── Public API ──────────────────────────────────────────────────────────

  static void error(BuildContext context, String message) =>
      _show(context, message, _MessageType.error);

  static void success(BuildContext context, String message) =>
      _show(context, message, _MessageType.success);

  static void warning(BuildContext context, String message) =>
      _show(context, message, _MessageType.warning);

  static void info(BuildContext context, String message) =>
      _show(context, message, _MessageType.info);

  // ─── Internal ────────────────────────────────────────────────────────────

  static OverlayEntry? _current;
  static Timer? _dismissTimer;

  static void _show(BuildContext context, String message, _MessageType type) {
    if (message.trim().isEmpty) return;

    // Fermer l'éventuel message précédent
    _dismiss();

    final overlay = Overlay.of(context, rootOverlay: true);

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) =>
          _AppMessageWidget(message: message, type: type, onDismiss: _dismiss),
    );

    _current = entry;
    overlay.insert(entry);

    // Auto-dismiss après une durée selon la longueur du message
    final ms = message.length > 80 ? 4500 : 3000;
    _dismissTimer = Timer(Duration(milliseconds: ms), _dismiss);
  }

  static void _dismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _current?.remove();
    _current = null;
  }
}

enum _MessageType { error, success, warning, info }

class _AppMessageWidget extends StatefulWidget {
  const _AppMessageWidget({
    required this.message,
    required this.type,
    required this.onDismiss,
  });

  final String message;
  final _MessageType type;
  final VoidCallback onDismiss;

  @override
  State<_AppMessageWidget> createState() => _AppMessageWidgetState();
}

class _AppMessageWidgetState extends State<_AppMessageWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Color get _bg {
    switch (widget.type) {
      case _MessageType.error:
        return const Color(0xFFDC2626); // rouge
      case _MessageType.success:
        return const Color(0xFF16A34A); // vert
      case _MessageType.warning:
        return const Color(0xFFD97706); // ambre
      case _MessageType.info:
        return const Color(0xFF2563EB); // bleu
    }
  }

  IconData get _icon {
    switch (widget.type) {
      case _MessageType.error:
        return Icons.error_outline_rounded;
      case _MessageType.success:
        return Icons.check_circle_outline_rounded;
      case _MessageType.warning:
        return Icons.warning_amber_rounded;
      case _MessageType.info:
        return Icons.info_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top + 8;

    return Positioned(
      top: top,
      left: 12,
      right: 12,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _opacity,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: widget.onDismiss,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: _bg.withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(_icon, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: widget.onDismiss,
                      child: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
