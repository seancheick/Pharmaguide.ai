import 'package:flutter/material.dart';
import 'package:pharmaguide/core/constants/app_colors.dart';

/// Orange banner shown when a product contains proprietary blends.
/// Proprietary blends hide individual ingredient amounts, limiting analysis.
class BlendWarningBanner extends StatelessWidget {
  const BlendWarningBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.orange.withAlpha(20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.orange.withAlpha(80)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.visibility_off_outlined,
            color: AppColors.orange,
            size: 18,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'This product contains proprietary blends — ingredient amounts '
              'are hidden. Our analysis is limited.',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.orange,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
