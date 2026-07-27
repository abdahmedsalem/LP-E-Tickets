import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/qr_token.dart';

/// Small QR thumbnail used in QR list cards. Color reflects the state.
class MiniQR extends StatelessWidget {
  const MiniQR({
    super.key,
    required this.data,
    required this.state,
    this.size = 56,
  });

  final String data;
  final QrState state;
  final double size;

  Color get _color {
    switch (state) {
      case QrState.active:
        return AppColors.ink;
      case QrState.blocked:
        return const Color(0xFF92400E);
      case QrState.consumed:
        return AppColors.muted;
      case QrState.expired:
        return AppColors.danger;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.line),
      ),
      child: QrImageView(
        data: data,
        version: QrVersions.auto,
        backgroundColor: Colors.white,
        gapless: true,
        eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: _color),
        dataModuleStyle: QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: _color,
        ),
      ),
    );
  }
}
