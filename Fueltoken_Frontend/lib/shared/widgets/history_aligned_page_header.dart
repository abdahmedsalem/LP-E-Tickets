import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

class HistoryAlignedPageHeader extends StatelessWidget {
  const HistoryAlignedPageHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 16, 26, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                height: 1.2,
                letterSpacing: -0.2,
                color: AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
