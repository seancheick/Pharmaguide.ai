// Dynamic citation strip — reads product count & build date from the DB
// manifest and renders the trust footer on the home screen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/widgets/pg_citation_strip.dart';
import 'package:pharmaguide/core/widgets/pg_shimmer_box.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';

class HomeCitationStrip extends ConsumerWidget {
  const HomeCitationStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogAsync = ref.watch(catalogInfoProvider);

    final info = catalogAsync.asData?.value;
    if (info == null) {
      return const PGShimmerBox(height: 72, radius: 16);
    }
    final sourceCount = info.productCount;
    final buildDate = info.buildDate ?? DateTime.now();

    return PGCitationStrip(
      sourceCount: sourceCount,
      updatedAt: buildDate,
      disclaimer: 'PharmaGuide is not medical advice. Always consult your '
          'healthcare provider before starting or stopping a supplement.',
    );
  }
}
