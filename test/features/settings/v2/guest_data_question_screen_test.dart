import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/settings/v2/guest_data_question_screen.dart';
import 'package:pharmaguide/core/theme/v2/v2_theme.dart';

void main() {
  Future<List<bool>> pumpQuestion(WidgetTester tester) async {
    final answers = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: V2Theme.light,
        home: GuestDataQuestionScreen(onAnswer: answers.add),
      ),
    );
    return answers;
  }

  testWidgets('asks the approved question', (tester) async {
    await pumpQuestion(tester);
    expect(
      find.text('Add the items already on this phone to your account?'),
      findsOneWidget,
    );
  });

  testWidgets('yes and no each give their own answer', (tester) async {
    final answers = await pumpQuestion(tester);
    await tester.tap(find.text('Yes, add them'));
    await tester.tap(find.text('No, leave them out'));
    expect(answers, [true, false]);
  });

  testWidgets('back gives no answer and stays on the question', (tester) async {
    final answers = await pumpQuestion(tester);
    await tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
    await tester.pumpAndSettle();
    expect(answers, isEmpty);
    expect(find.text('Yes, add them'), findsOneWidget);
  });
}
