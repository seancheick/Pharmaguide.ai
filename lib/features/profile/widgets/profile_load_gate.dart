import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';

/// Both profile editors wait for the same persisted baseline before accepting
/// edits. A failed read must never turn into an empty profile that can be saved.
class ProfileLoadGate extends ConsumerWidget {
  const ProfileLoadGate({super.key, required this.builder});

  final Widget Function(BuildContext context, WidgetRef ref) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(profileLoadedProvider)
        .when(
          skipLoadingOnRefresh: false,
          data: (_) => builder(context, ref),
          loading: () => const Scaffold(
            body: SafeArea(child: Center(child: CircularProgressIndicator())),
          ),
          error: (_, __) => Scaffold(
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text("Couldn't load your profile"),
                      const SizedBox(height: 12),
                      const Text(
                        'Your saved details have not been changed. Retry before editing your profile.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () {
                          ref.invalidate(profileProvider);
                          ref.invalidate(profileLoadedProvider);
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
  }
}
