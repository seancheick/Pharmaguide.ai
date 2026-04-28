// Search launcher — read-only PGSearchField that opens /search on tap.
// Uses a calm static placeholder so the home hero feels composed rather than
// data-dependent.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/widgets/pg_search_field.dart';

class HomeSearchLauncher extends StatelessWidget {
  const HomeSearchLauncher({super.key});

  @override
  Widget build(BuildContext context) {
    return PGSearchField(
      readOnly: true,
      hintText: 'Search supplements',
      onTap: () => GoRouter.of(context).push(Routes.search),
    );
  }
}
