import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/features/profile/v2/profile_setup_v2_screen.dart';
import 'package:pharmaguide/features/profile/v2/profile_wizard_v2_screen.dart';

class _UnavailableProfileDb extends UserDatabase {
  _UnavailableProfileDb() : super.memory();
  bool failReads = true;
  @override
  Future<UserProfile?> getProfile() {
    if (failReads) throw Exception('synthetic profile read failure');
    return super.getProfile();
  }
}

void main() {
  for (final wizard in [false, true]) {
    testWidgets(
      'profile ${wizard ? "wizard" : "editor"} withholds editing until failed load retries',
      (tester) async {
        final db = _UnavailableProfileDb();
        addTearDown(db.close);
        await db.saveProfile(
          const ProfileState(
            nickname: 'Saved',
            conditions: ['pregnancy'],
          ).toCompanion(),
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [userDatabaseProvider.overrideWithValue(db)],
            child: MaterialApp(
              home: wizard
                  ? const ProfileWizardV2Screen()
                  : const ProfileSetupV2Screen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text("Couldn't load your profile"), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
        expect(find.text('Save profile'), findsNothing);
        expect(find.text('Continue'), findsNothing);
        db.failReads = false;
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
        expect(find.text("Couldn't load your profile"), findsNothing);
        expect(
          find.text(wizard ? 'Welcome to PharmaGuide.' : 'HEALTH CONDITIONS'),
          findsOneWidget,
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(Scaffold).first),
        );
        expect(container.read(profileProvider).conditions, ['pregnancy']);
        expect(container.read(profileProvider).nickname, 'Saved');
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
