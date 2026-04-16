// Editorial home-screen greeting: date pill, personalized greeting, tagline.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';

class HomeHeroSection extends StatelessWidget {
  final String? nickname;
  const HomeHeroSection({super.key, required this.nickname});

  static const _days = [
    'MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY',
    'FRIDAY', 'SATURDAY', 'SUNDAY',
  ];
  static const _months = [
    'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE',
    'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER',
  ];

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = DateTime.now();
    final dateLabel = '${_days[now.weekday - 1]}  ·  '
        '${_months[now.month - 1]} ${now.day}';
    final name =
        (nickname != null && nickname!.isNotEmpty) ? ', $nickname' : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Date label — small, uppercase, teal
        Text(
          dateLabel,
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
            color: scheme.primary,
          ),
        ),
        const SizedBox(height: AppTheme.space12),
        // Greeting — large, tight letter-spacing
        Text(
          '${_greeting()}$name.',
          style: theme.textTheme.headlineLarge?.copyWith(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
            height: 1.12,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Know what you take.',
          style: theme.textTheme.titleMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w400,
            letterSpacing: -0.1,
          ),
        ),
      ],
    );
  }
}
