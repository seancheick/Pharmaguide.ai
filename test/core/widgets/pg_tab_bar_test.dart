import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_theme.dart';
import 'package:pharmaguide/core/widgets/pg_frosted_nav_bar.dart';
import 'package:pharmaguide/core/widgets/pg_tab_bar.dart';

const _tabs = [
  PGTab(
    label: 'Home',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home_rounded,
    symbol: 'house',
    selectedSymbol: 'house.fill',
  ),
  PGTab(
    label: 'Stack',
    icon: Icons.layers_outlined,
    selectedIcon: Icons.layers_rounded,
    symbol: 'square.stack.3d.up',
    selectedSymbol: 'square.stack.3d.up.fill',
  ),
];

/// Records what the framework asks the iOS side to create.
class _PlatformViews {
  final creates = <Map<String, Object?>>[];
  final calls = <MethodCall>[];

  void install(WidgetTester tester) {
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (call) {
      if (call.method == 'create') {
        final args = Map<String, Object?>.from(call.arguments as Map);
        final bytes = args['params'] as Uint8List?;
        args['decoded'] = bytes == null
            ? null
            : const StandardMessageCodec().decodeMessage(
                ByteData.sublistView(bytes),
              );
        creates.add(args);
      }
      return Future.value();
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        null,
      ),
    );
  }

  int get id => creates.single['id'] as int;
  Map<Object?, Object?> get params =>
      creates.single['decoded']! as Map<Object?, Object?>;

  void recordViewChannel(WidgetTester tester) {
    final channel = MethodChannel('pharmaguide/tab_bar_$id');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) {
      calls.add(call);
      return Future.value();
    });
  }

  Future<void> tapFromIOS(WidgetTester tester, int index) async {
    final channel = MethodChannel('pharmaguide/tab_bar_$id');
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(MethodCall('select', index)),
      (_) {},
    );
  }
}

Widget _host({
  required bool native,
  required int selected,
  required ValueChanged<int> onSelected,
  ThemeData? theme,
}) {
  return MaterialApp(
    theme: theme ?? V2Theme.light,
    home: Scaffold(
      extendBody: true,
      bottomNavigationBar: PGTabBar(
        tabs: _tabs,
        selectedIndex: selected,
        onSelected: onSelected,
        nativeGlass: native,
      ),
    ),
  );
}

void main() {
  group('iosMajorVersion', () {
    test('reads the major version iOS reports', () {
      expect(iosMajorVersion('Version 26.5 (Build 23F77)'), 26);
      expect(iosMajorVersion('Version 18.5 (Build 22F76)'), 18);
      expect(iosMajorVersion('26.0'), 26);
    });

    test('is null when there is no number', () {
      expect(iosMajorVersion('unknown'), isNull);
    });
  });

  testWidgets('without native glass it is the frosted bar and selects', (
    tester,
  ) async {
    final selected = <int>[];
    await tester.pumpWidget(
      _host(native: false, selected: 0, onSelected: selected.add),
    );
    expect(find.byType(PGFrostedNavBar), findsOneWidget);
    expect(find.byType(UiKitView), findsNothing);
    await tester.tap(find.text('Stack'));
    expect(selected, [1]);
  });

  testWidgets('the test host is not iOS 26, so it falls back by default', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: V2Theme.light,
        home: Scaffold(
          bottomNavigationBar: PGTabBar(
            tabs: _tabs,
            selectedIndex: 0,
            onSelected: (_) {},
          ),
        ),
      ),
    );
    expect(find.byType(PGFrostedNavBar), findsOneWidget);
  });

  testWidgets('with native glass it asks iOS for Apple\'s tab bar', (
    tester,
  ) async {
    final views = _PlatformViews()..install(tester);
    await tester.pumpWidget(
      _host(native: true, selected: 1, onSelected: (_) {}),
    );
    await tester.pump();

    expect(find.byType(PGFrostedNavBar), findsNothing);
    final view = tester.widget<UiKitView>(find.byType(UiKitView));
    expect(view.viewType, 'pharmaguide/tab_bar');
    expect(views.creates.single['viewType'], 'pharmaguide/tab_bar');
    expect(views.params['labels'], ['Home', 'Stack']);
    expect(views.params['symbols'], ['house', 'square.stack.3d.up']);
    expect(views.params['selectedSymbols'], [
      'house.fill',
      'square.stack.3d.up.fill',
    ]);
    expect(views.params['selectedIndex'], 1);
    expect(views.params['dark'], isFalse);
    expect(views.params['tint'], V2Palette.light.accent.toARGB32());
  });

  testWidgets('a tap on the iOS bar selects, and selection flows back', (
    tester,
  ) async {
    final views = _PlatformViews()..install(tester);
    final selected = <int>[];
    var index = 0;
    late StateSetter setIndex;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          setIndex = setState;
          return _host(
            native: true,
            selected: index,
            onSelected: (i) {
              selected.add(i);
              setState(() => index = i);
            },
          );
        },
      ),
    );
    await tester.pump();
    views.recordViewChannel(tester);

    await views.tapFromIOS(tester, 1);
    await tester.pump();
    expect(selected, [1]);

    setIndex(() => index = 0);
    await tester.pump();
    expect(
      views.calls.where((c) => c.method == 'setSelectedIndex').last.arguments,
      0,
    );
  });

  testWidgets('dark theme is passed on and updated live', (tester) async {
    final views = _PlatformViews()..install(tester);
    var theme = V2Theme.dark;
    late StateSetter setTheme;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          setTheme = setState;
          return _host(
            native: true,
            selected: 0,
            onSelected: (_) {},
            theme: theme,
          );
        },
      ),
    );
    await tester.pump();
    expect(views.params['dark'], isTrue);
    expect(views.params['tint'], V2Palette.dark.accent.toARGB32());
    views.recordViewChannel(tester);

    setTheme(() => theme = V2Theme.light);
    await tester.pumpAndSettle();
    final style = views.calls.where((c) => c.method == 'setStyle').last;
    expect((style.arguments as Map)['dark'], isFalse);
  });

  testWidgets(
    'the native bar is UIKit height, so the capsule is not stretched',
    (tester) async {
      _PlatformViews().install(tester);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(402, 874),
            padding: EdgeInsets.only(bottom: 34),
          ),
          child: _host(native: true, selected: 0, onSelected: (_) {}),
        ),
      );
      await tester.pump();
      // 49 pt is UITabBar's standard height above the home indicator (what
      // UITabBarController gives it). A taller frame stretches the iOS 26
      // capsule vertically.
      expect(tester.getSize(find.byType(UiKitView)).height, 49 + 34);
    },
  );
}
