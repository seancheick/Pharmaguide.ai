import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pharmaguide/main.dart' as app;
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/providers/detail_blob_provider.dart';
import 'package:pharmaguide/features/search/v2/search_v2_screen.dart';

// Drives normal app startup/search/detail. No fixture providers or state seeding.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.shouldPropagateDevicePointerEvents = true;
  WidgetController.hitTestWarningShouldBeFatal = true;
  testWidgets('normal catalog search reaches the exact product and explanation', (
    tester,
  ) async {
    const productId = String.fromEnvironment(
      'VERIFY_PRODUCT_ID',
      defaultValue: '295048',
    );
    const source = String.fromEnvironment('VERIFY_SOURCE_REVISION');
    const expectedVersion = String.fromEnvironment('VERIFY_CATALOG_VERSION');
    const expectedReason = String.fromEnvironment('VERIFY_EXPLANATION');
    expect(const bool.fromEnvironment('SCREENSHOT_MODE'), isFalse);
    expect(const String.fromEnvironment('SCREENSHOT_ROUTE'), isEmpty);
    expect(const String.fromEnvironment('DEV_ROUTE'), isEmpty);
    final evidence = <String, dynamic>{
      'source_revision_at_launch': source,
      'source_dirty_at_launch': const bool.fromEnvironment(
        'VERIFY_SOURCE_DIRTY',
      ),
      'source_identity_note':
          'HEAD plus retained source diff when dirty; not a release build attestation',
      'product_id': productId,
      'mode': 'normal_app_no_provider_overrides',
      'actions': <String>[],
    };
    final directory = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/verification',
    );
    await directory.create(recursive: true);
    Future<void> save() async {
      await File(
        '${directory.path}/native_journey.json',
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(evidence));
    }

    Future<void> waitFor(Finder finder, {int seconds = 45}) async {
      for (var i = 0; i < seconds * 2; i++) {
        await tester.pump(const Duration(milliseconds: 500));
        if (finder.evaluate().isNotEmpty) return;
      }
      throw TestFailure(
        'Normal app did not expose $finder within $seconds seconds',
      );
    }

    Future<void> capture(String name) async {
      final bytes = await binding.takeScreenshot(name);
      await File('${directory.path}/$name.png').writeAsBytes(bytes);
    }

    final originalErrorHandler = FlutterError.onError;
    final originalPlatformHandler = PlatformDispatcher.instance.onError;
    final unexpectedErrors = <String>[];
    try {
      app.main();
      for (var i = 0; i < 90; i++) {
        await tester.pump(const Duration(milliseconds: 500));
        if (find.text('Start scanning').evaluate().isNotEmpty ||
            find.text('Search supplements').evaluate().isNotEmpty) {
          break;
        }
      }
      final appErrorHandler = FlutterError.onError;
      final appPlatformHandler = PlatformDispatcher.instance.onError;
      FlutterError.onError = (details) {
        unexpectedErrors.add(details.exceptionAsString());
        appErrorHandler?.call(details);
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        unexpectedErrors.add(error.toString());
        return appPlatformHandler?.call(error, stack) ?? false;
      };
      if (find.text('Start scanning').evaluate().isNotEmpty) {
        await tester.tap(find.text('Start scanning'));
        (evidence['actions'] as List).add('onboarding: Start scanning');
        await tester.pump(const Duration(seconds: 2));
        if (find.text('Home').evaluate().isNotEmpty) {
          await tester.tap(find.text('Home').last);
        } else {
          debugPrint(
            'NATIVE_CONTROL_REQUIRED: tap Home in the owned simulator UIKit tab bar',
          );
        }
      }
      await waitFor(find.text('Search supplements'), seconds: 180);
      await capture('01-home');
      await tester.tap(find.text('Search supplements').first);
      await waitFor(find.byType(SearchV2Screen));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SearchV2Screen)),
      );
      final db = container.read(coreDatabaseProvider);
      final product = await db.findById(productId);
      expect(
        product,
        isNotNull,
        reason: 'Requested label is absent from the installed catalog',
      );
      evidence['installed_catalog_version'] = await db.readDbVersion();
      evidence['product_name'] = product!.productName;
      evidence['product_export_version'] = product.exportVersion;
      evidence['detail_blob_sha256'] = product.detailBlobSha256;
      if (expectedVersion.isNotEmpty) {
        expect(evidence['installed_catalog_version'], expectedVersion);
      }
      await tester.enterText(find.byType(TextField).first, product.productName);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      (evidence['actions'] as List).add('search: ${product.productName}');
      final tile = find.byKey(const ValueKey('search-product-$productId'));
      for (var i = 0; i < 30 && tile.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 500));
        if (i > 3) {
          final scrollable = find.byType(Scrollable);
          if (scrollable.evaluate().isNotEmpty) {
            await tester.drag(scrollable.first, const Offset(0, -250));
          }
        }
      }
      expect(
        tile,
        findsOneWidget,
        reason: 'Exact label must be reachable through normal search',
      );
      await tester.ensureVisible(tile);
      await tester.pump(const Duration(milliseconds: 500));
      expect(tile.hitTestable(), findsOneWidget);
      await capture('02-exact-label-search');
      await tester.tap(tile.hitTestable());
      await waitFor(find.text("What’s inside"));
      (evidence['actions'] as List).add('open exact label $productId');
      await tester.pump(const Duration(seconds: 2));
      final blob = await container.read(detailBlobProvider(productId).future);
      expect(
        blob,
        isNotNull,
        reason:
            'Declared product details unavailable; cannot verify explanation',
      );
      final pillars = blob!['quality_pillars_v4'] as Map;
      final verification = pillars['verification'] as Map;
      final reason = verification['reason'] as String;
      evidence['verification_reason'] = reason;
      evidence['quality_pillars_v4'] = pillars;
      evidence['quality_assessment_status'] = blob['quality_assessment_status'];
      evidence['safety_flags'] = blob['safety_flags'];
      evidence['display_ingredients'] = blob['display_ingredients'];
      final label = find.text('Testing & Brand');
      for (var i = 0; i < 18 && label.evaluate().isEmpty; i++) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -420));
        await tester.pump(const Duration(milliseconds: 400));
      }
      expect(label, findsWidgets);
      await Scrollable.ensureVisible(
        tester.element(label.first),
        alignment: 0.5,
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(label.first);
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.text(reason),
        findsWidgets,
        reason: 'Rendered explanation must equal the installed detail blob',
      );
      await Scrollable.ensureVisible(
        tester.element(find.text(reason).first),
        alignment: 0.5,
      );
      await tester.pump(const Duration(milliseconds: 500));
      await capture('03-verification-explanation');
      (evidence['actions'] as List).add(
        'expand Testing & Brand; verify exact explanation',
      );
      if (expectedReason.isNotEmpty) {
        expect(
          reason,
          expectedReason,
          reason: 'Requested correction is not delivered by this catalog',
        );
      }
      expect(
        unexpectedErrors,
        isEmpty,
        reason: 'App errors occurred during navigation',
      );
      evidence['result'] = 'journey_assertions_passed';
    } catch (error) {
      FlutterError.onError = originalErrorHandler;
      evidence['result'] = 'failed';
      evidence['failure'] = error.toString();
      rethrow;
    } finally {
      FlutterError.onError = originalErrorHandler;
      PlatformDispatcher.instance.onError = originalPlatformHandler;
      evidence['unexpected_app_errors'] = unexpectedErrors;
      evidence['error_monitor_scope'] =
          'after initial app screen; startup logs retained separately';
      await save();
      binding.reportData = {...?binding.reportData, ...evidence};
      debugPrint('Native journey evidence: ${directory.path}');
    }
  });
}
