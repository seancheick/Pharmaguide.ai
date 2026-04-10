import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/app_colors.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final colors = AppColors.of(context);

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _greeting(profile.nickname),
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Know What You Take',
                      style: TextStyle(
                          fontSize: 14, color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
            // Search bar
            const SliverToBoxAdapter(child: SearchBarWidget()),
            // Profile completeness banner
            if (profile.completeness < 60)
              SliverToBoxAdapter(
                  child: ProfileCompletenessBanner(
                      completeness: profile.completeness)),
            // Category filters
            const SliverToBoxAdapter(child: CategoryFilterChips()),
            // Recent scans placeholder
            const SliverToBoxAdapter(child: RecentScansWidget()),
            // Stack health placeholder
            const SliverToBoxAdapter(child: StackHealthWidget()),
          ],
        ),
      ),
    );
  }

  String _greeting(String? nickname) {
    final hour = DateTime.now().hour;
    final name =
        (nickname != null && nickname.isNotEmpty) ? ', $nickname' : '';
    if (hour < 12) return 'Good morning$name!';
    if (hour < 17) return 'Good afternoon$name!';
    return 'Good evening$name!';
  }
}

// --- Modular Widgets ---

class SearchBarWidget extends StatelessWidget {
  const SearchBarWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: GestureDetector(
        onTap: () => context.push('/search'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              Icon(Icons.search, color: colors.textSecondary),
              const SizedBox(width: 12),
              Text(
                'Search supplements...',
                style: TextStyle(color: colors.textSecondary, fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProfileCompletenessBanner extends StatelessWidget {
  final int completeness;
  const ProfileCompletenessBanner({super.key, required this.completeness});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.brandTeal.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Complete your profile',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                      '$completeness% complete — add health info for personalized scores',
                      style: TextStyle(
                          fontSize: 13, color: colors.textSecondary)),
                ],
              ),
            ),
            TextButton(
              onPressed: () => context.push('/profile/setup'),
              child: const Text('Complete'),
            ),
          ],
        ),
      ),
    );
  }
}

class CategoryFilterChips extends StatelessWidget {
  const CategoryFilterChips({super.key});

  static const _categories = [
    ('Omega-3', 'omega_3', Icons.water_drop_outlined),
    ('Probiotics', 'probiotic', Icons.biotech_outlined),
    ('Multivitamin', 'multivitamin', Icons.medication_outlined),
    ('Collagen', 'collagen', Icons.spa_outlined),
    ('Adaptogens', 'adaptogen', Icons.eco_outlined),
    ('Nootropics', 'nootropic', Icons.psychology_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final (label, category, icon) = _categories[index];
          return ActionChip(
            avatar: Icon(icon, size: 18),
            label: Text(label),
            onPressed: () => context.push('/search?category=$category'),
          );
        },
      ),
    );
  }
}

class RecentScansWidget extends StatelessWidget {
  const RecentScansWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Recent Scans',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.border),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.qr_code_scanner,
                      size: 48, color: colors.textSecondary),
                  const SizedBox(height: 12),
                  Text('No scans yet',
                      style: TextStyle(color: colors.textSecondary)),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => context.go('/scan'),
                    child: const Text('Scan your first supplement'),
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

class StackHealthWidget extends StatelessWidget {
  const StackHealthWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Stack Health',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
                'Add supplements to your stack to see health insights',
                style: TextStyle(color: colors.textSecondary, fontSize: 14)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => context.go('/stack'),
              child: const Text('Build Your Stack'),
            ),
          ],
        ),
      ),
    );
  }
}
