import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/theme/app_theme.dart';
import 'package:hermes_app/widgets/confirm_delete_chat.dart';

void main() {
  testWidgets('delete chat asks before removing', (tester) async {
    var confirmed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () async {
                  confirmed = await confirmDeleteChat(context);
                },
                child: const Text('Ask'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Ask'));
    await tester.pump();
    expect(find.text('Delete chat?'), findsOneWidget);
    expect(
      find.text('This removes the conversation from this phone.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(confirmed, isFalse);

    await tester.tap(find.text('Ask'));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pump();
    expect(confirmed, isTrue);
  });
}
