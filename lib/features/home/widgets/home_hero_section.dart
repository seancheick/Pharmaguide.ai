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

  /// Time-of-day greeting copy, exposed as a static pure function so the
  /// boundary hours can be unit-tested without rendering the widget.
  ///
  /// Bands:
  /// - 05:00–11:59 → `Good morning`
  /// - 12:00–16:59 → `Hello there`  (intentionally not "Good afternoon" —
  ///   product decision to use a warmer, less formal mid-day copy)
  /// - 17:00–20:59 → `Good evening`
  /// - 21:00–04:59 → `Good night`
  ///
  /// [hour] should be a 24-hour value (0..23) — typically `DateTime.now().hour`.
  @visibleForTesting
  static String greetingFor(int hour) {
    if (hour >= 5 && hour < 12) return 'Good morning';
    if (hour >= 12 && hour < 17) return 'Hello there';
    if (hour >= 17 && hour < 21) return 'Good evening';
    return 'Good night';
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
          '${greetingFor(DateTime.now().hour)}$name.',
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
