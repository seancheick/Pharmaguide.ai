import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/app.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pharmaguide/services/pending_submission_intent.dart';
import 'package:pharmaguide/services/product_submission_service.dart';
import 'package:pharmaguide/features/scanner/missing_product_submission_sheet.dart';

/// Shaped like the app router: the tabs live in a shell, and the sign-in page
/// is a top-level route that in-app sign-in gates push over a tab.
GoRouter _router() => GoRouter(
  initialLocation: Routes.scan,
  routes: [
    ShellRoute(
      builder: (_, __, child) => Scaffold(body: child),
      routes: [
        GoRoute(path: Routes.home, builder: (_, __) => const Text('Home page')),
        GoRoute(path: Routes.scan, builder: (_, __) => const Text('Scan page')),
      ],
    ),
    GoRoute(
      path: Routes.authInvitation,
      builder: (_, __) => const Scaffold(body: Text('Sign-in page')),
    ),
    GoRoute(
      path: Routes.profileWizard,
      builder: (_, __) => const Scaffold(body: Text('Profile wizard')),
    ),
  ],
);

Future<GoRouter> _pumpRouter(WidgetTester tester) async {
  final router = _router();
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  return router;
}

void main() {
  setUp(() {
    // A returning account, so sign-in lands on home rather than the wizard.
    SharedPreferences.setMockInitialValues({'hasSeenProfileWizard': true});
  });

  testWidgets(
    'submission continuation retains exact attempt when navigator is unavailable',
    (tester) async {
      final identifier = ProductSubmissionIdentifier(
        observedCode: 'X002FLZ3X7',
        brandName: 'Natgrown',
        fullName: 'Fixture',
      );
      const id = '11111111-1111-4111-8111-111111111111';
      const rejected = '11111111-1111-4111-8111-111111111110';
      await PendingSubmissionIntent.saveAlternateProduct(
        identifier,
        id,
        resubmissionOf: rejected,
      );
      final resume = resumePendingSubmission(contextProvider: () => null);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 301));
      await resume;
      final retained = await PendingSubmissionIntent.consume();
      expect(retained!.submissionId, id);
      expect(retained.resubmissionOf, rejected);
      expect(retained.submissionIdentifier!.observedCode, 'X002FLZ3X7');
    },
  );
  testWidgets(
    'submission continuation retains intent when landing navigator is disposed',
    (tester) async {
      BuildContext? landing;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              landing = context;
              return const SizedBox();
            },
          ),
        ),
      );
      await PendingSubmissionIntent.saveAlternateProduct(
        ProductSubmissionIdentifier(
          observedCode: 'X002FLZ3X7',
          brandName: 'Natgrown',
          fullName: 'Fixture',
        ),
        '11111111-1111-4111-8111-111111111111',
      );
      final resume = resumePendingSubmission(contextProvider: () => landing);
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 301));
      await resume;
      expect(
        (await PendingSubmissionIntent.consume())!
            .submissionIdentifier!
            .observedCode,
        'X002FLZ3X7',
      );
    },
  );
  testWidgets(
    'delayed landing navigator automatically presents retained alternate attempt once',
    (tester) async {
      BuildContext? landing;
      final identifier = ProductSubmissionIdentifier(
        observedCode: 'X002FLZ3X7',
        brandName: 'Natgrown',
        fullName: 'Fixture',
      );
      const id = '11111111-1111-4111-8111-111111111111';
      const rejected = '11111111-1111-4111-8111-111111111110';
      await PendingSubmissionIntent.saveAlternateProduct(
        identifier,
        id,
        resubmissionOf: rejected,
      );
      final resume = resumePendingSubmission(
        contextProvider: () => landing,
        submissionService: ProductSubmissionService(backend: _PendingBackend()),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 301));
      await resume;
      expect(await PendingSubmissionIntent.peek(), isNotNull);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              landing = context;
              return const Scaffold(body: Text('Landing'));
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final capture = tester.widget<MissingProductSubmissionSheet>(
        find.byType(MissingProductSubmissionSheet),
      );
      expect(capture.identifier!.observedCode, 'X002FLZ3X7');
      expect(capture.submissionIdFactory!(), id);
      expect(capture.resubmissionOf, rejected);
      expect(await PendingSubmissionIntent.peek(), isNull);
      expect(find.byType(MissingProductSubmissionSheet), findsOneWidget);
    },
  );
  group('navigatePostAuthIfOnAuthPath', () {
    testWidgets('leaves a sign-in page pushed over a tab', (tester) async {
      // Every in-app sign-in gate (missing product, wishlist, stack, guest
      // scan limit) pushes the page, so this is the common path.
      final router = await _pumpRouter(tester);
      unawaited(router.push(Routes.authInvitation));
      await tester.pumpAndSettle();
      expect(find.text('Sign-in page'), findsOneWidget);

      navigatePostAuthIfOnAuthPath(router);
      await tester.pumpAndSettle();

      expect(find.text('Sign-in page'), findsNothing);
      expect(find.text('Home page'), findsOneWidget);
    });

    testWidgets('leaves the sign-in page onboarding went to', (tester) async {
      final router = await _pumpRouter(tester);
      router.go(Routes.authInvitation);
      await tester.pumpAndSettle();

      navigatePostAuthIfOnAuthPath(router);
      await tester.pumpAndSettle();

      expect(find.text('Sign-in page'), findsNothing);
      expect(find.text('Home page'), findsOneWidget);
    });

    testWidgets('keeps a signed-in user on their tab', (tester) async {
      // Token refreshes run this too; they must not pull anyone off a tab.
      final router = await _pumpRouter(tester);

      navigatePostAuthIfOnAuthPath(router);
      await tester.pumpAndSettle();

      expect(find.text('Scan page'), findsOneWidget);
    });

    testWidgets('does nothing before the router has a route', (tester) async {
      final router = _router();
      addTearDown(router.dispose);

      expect(() => navigatePostAuthIfOnAuthPath(router), returnsNormally);
    });
  });
}

class _PendingBackend implements ProductSubmissionBackend {
  @override
  String? get authenticatedUserId => '11111111-1111-4111-8111-111111111111';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
