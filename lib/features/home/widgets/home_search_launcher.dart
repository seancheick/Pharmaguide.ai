// Search launcher — read-only PGSearchField that opens /search on tap.
// Displays "Search N+ supplements…" using the live catalog count when loaded.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/widgets/pg_search_field.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';

class HomeSearchLauncher extends ConsumerWidget {
  const HomeSearchLauncher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(catalogInfoProvider).asData?.value.productCount;
    final label = count != null
        ? 'Search $count+ supplements…'
        : 'Search supplements…';
    return PGSearchField(
      readOnly: true,
      hintText: label,
      onTap: () => GoRouter.of(context).push(Routes.search),
    );
  }
}
