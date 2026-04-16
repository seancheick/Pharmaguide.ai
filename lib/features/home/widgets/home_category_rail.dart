// Horizontal rail of popular supplement categories. Tapping a chip opens
// the search screen pre-filtered to that category slug.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_filter_chip.dart';

class HomeCategoryRail extends StatelessWidget {
  const HomeCategoryRail({super.key});

  static const _categories = <(String, String, IconData)>[
    ('Omega-3', 'omega_3', Icons.water_drop_outlined),
    ('Probiotics', 'probiotic', Icons.biotech_outlined),
    ('Multivitamin', 'multivitamin', Icons.medication_outlined),
    ('Magnesium', 'magnesium', Icons.bolt_outlined),
    ('Collagen', 'collagen', Icons.spa_outlined),
    ('Adaptogens', 'adaptogen', Icons.eco_outlined),
    ('Nootropics', 'nootropic', Icons.psychology_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.space20),
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppTheme.space8),
        itemBuilder: (context, index) {
          final (label, slug, icon) = _categories[index];
          return PGFilterChip(
            label: label,
            icon: icon,
            selected: false,
            onTap: () =>
                GoRouter.of(context).push('${Routes.search}?category=$slug'),
          );
        },
      ),
    );
  }
}
