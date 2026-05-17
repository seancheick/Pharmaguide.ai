import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/features/search/v2/search_v2_screen.dart';
import 'package:pharmaguide/services/recent_searches_service.dart';

class _FakeRecentSearchesService extends RecentSearchesService {
  @override
  Future<List<String>> getRecent() async => const [];
}

void main() {
  testWidgets('keyboard-open layout does not reserve shell nav padding', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recentSearchesServiceProvider.overrideWithValue(
            _FakeRecentSearchesService(),
          ),
        ],
        child: const MaterialApp(home: SearchV2Screen()),
      ),
    );
    await tester.pump();

    final bottomPaddings = tester
        .widgetList<Padding>(find.byType(Padding))
        .map((w) => w.padding.resolve(TextDirection.ltr).bottom);

    expect(bottomPaddings, contains(V2Spacing.space8));
  });
}
