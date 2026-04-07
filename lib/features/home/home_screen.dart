import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/app_colors.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);

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
                    const Text(
                      'Know What You Take',
                      style: TextStyle(
                          fontSize: 14, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
            // Search bar
            SliverToBoxAdapter(child: SearchBarWidget()),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: GestureDetector(
        onTap: () => context.push('/search'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: const Row(
            children: [
              Icon(Icons.search, color: AppColors.textSecondary),
              SizedBox(width: 12),
              Text('Search supplements...',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 16)),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFE6F7F5),
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
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary)),
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
    ('Omega-3', Icons.water_drop_outlined),
    ('Probiotics', Icons.biotech_outlined),
    ('Multivitamin', Icons.medication_outlined),
    ('Collagen', Icons.spa_outlined),
    ('Adaptogens', Icons.eco_outlined),
    ('Nootropics', Icons.psychology_outlined),
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
          final (label, icon) = _categories[index];
          return ActionChip(
            avatar: Icon(icon, size: 18),
            label: Text(label),
            onPressed: () =>
                context.push('/search?category=${label.toLowerCase()}'),
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
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Center(
              child: Column(
                children: [
                  const Icon(Icons.qr_code_scanner,
                      size: 48, color: AppColors.textSecondary),
                  const SizedBox(height: 12),
                  const Text('No scans yet',
                      style: TextStyle(color: AppColors.textSecondary)),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Stack Health',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text(
                'Add supplements to your stack to see health insights',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 14)),
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
