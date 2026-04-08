import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/services/connectivity_service.dart';

/// A slim banner that appears at the top of screens when offline or syncing.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(connectionStatusProvider);

    return statusAsync.when(
      data: (status) {
        if (status == ConnectionStatus.online) {
          return const SizedBox.shrink();
        }
        final isOffline = status == ConnectionStatus.offline;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.space16,
            vertical: AppTheme.space4,
          ),
          color: isOffline
              ? AppTheme.severityCaution.withValues(alpha: 0.15)
              : AppTheme.brandTeal.withValues(alpha: 0.15),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isOffline ? Icons.cloud_off : Icons.sync,
                size: 14,
                color: isOffline
                    ? AppTheme.severityCaution
                    : AppTheme.brandTeal,
              ),
              const SizedBox(width: 6),
              Text(
                isOffline ? 'Offline — using cached data' : 'Syncing...',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isOffline
                      ? AppTheme.severityCaution
                      : AppTheme.brandTeal,
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
