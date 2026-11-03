// image_picker hands the sheet a copy in the app's shared temp folder. Nothing
// else removes it, and it sits outside the account's folder, so Remove from
// this phone and the switch guard can't reach it (ADR-013).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/history/add_health_event_sheet.dart';
import 'package:pharmaguide/features/history/providers/health_history_providers.dart';
import 'package:pharmaguide/services/history/health_attachment_store.dart';

const _picker = MethodChannel('plugins.flutter.io/image_picker');

void main() {
  late Directory temp;
  late UserDatabase database;
  late List<File> picks;

  File pickCopy(String name) =>
      File(p.join(temp.path, name))..writeAsBytesSync(const [1, 2, 3]);

  setUp(() {
    temp = Directory.systemTemp.createTempSync('attachment-sheet-');
    database = UserDatabase.memory();
    picks = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_picker, (_) async {
          return picks.removeAt(0).path;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_picker, null);
    await database.close();
    temp.deleteSync(recursive: true);
  });

  Future<void> openSheet(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userDatabaseProvider.overrideWithValue(database),
          healthAttachmentStoreProvider.overrideWithValue(
            HealthAttachmentStore(
              root: () async => Directory(p.join(temp.path, 'stored')),
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => showAddHealthEventSheet(context, ref),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> attach(WidgetTester tester, File copy) async {
    picks.add(copy);
    await tester.tap(find.byIcon(Icons.attach_file_rounded));
    await tester.pumpAndSettle();
    expect(find.text(p.basename(copy.path)), findsOneWidget);
  }

  testWidgets('keeps the copy while the sheet can still save it', (
    tester,
  ) async {
    final copy = pickCopy('picked.png');
    await openSheet(tester);
    await attach(tester, copy);
    expect(copy.existsSync(), isTrue);
  });

  testWidgets('removes the copy when the sheet closes unsaved', (tester) async {
    final copy = pickCopy('picked.png');
    await openSheet(tester);
    await attach(tester, copy);

    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();

    expect(copy.existsSync(), isFalse);
  });

  testWidgets('removes the copy when the photo is taken off the event', (
    tester,
  ) async {
    final copy = pickCopy('picked.png');
    await openSheet(tester);
    await attach(tester, copy);

    await tester.tap(find.byTooltip('Remove attachment'));
    await tester.pumpAndSettle();

    expect(copy.existsSync(), isFalse);
  });

  testWidgets('removes only the old copy when another photo replaces it', (
    tester,
  ) async {
    final first = pickCopy('first.png');
    final second = pickCopy('second.png');
    await openSheet(tester);
    await attach(tester, first);
    await attach(tester, second);

    expect(first.existsSync(), isFalse);
    expect(second.existsSync(), isTrue);
  });

  Future<void> save(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).first, 'Lab visit');
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Save event'));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();
  }

  List<FileSystemEntity> stored() {
    final root = Directory(p.join(temp.path, 'stored'));
    return root.existsSync() ? root.listSync() : const [];
  }

  testWidgets('removes the copy once the event is saved', (tester) async {
    final copy = pickCopy('picked.png');
    await openSheet(tester);
    await attach(tester, copy);

    await save(tester);

    expect(stored(), hasLength(1));
    expect(copy.existsSync(), isFalse);
  });

  testWidgets('keeps the copy after a failed save, so a retry can use it', (
    tester,
  ) async {
    final copy = pickCopy('picked.png');
    // A file where the attachments folder should be makes the save fail.
    final blocker = File(p.join(temp.path, 'stored'))
      ..writeAsBytesSync(const [0]);
    await openSheet(tester);
    await attach(tester, copy);

    await save(tester);

    expect(find.text('Save event'), findsOneWidget);
    expect(copy.existsSync(), isTrue);

    blocker.deleteSync();
    await save(tester);

    expect(stored(), hasLength(1));
    expect(copy.existsSync(), isFalse);
  });
}
