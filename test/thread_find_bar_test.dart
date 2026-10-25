import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/theme/app_theme.dart';
import 'package:hermes_app/widgets/thread_find_bar.dart';

void main() {
  testWidgets('find bar reports matches and steps through them', (tester) async {
    var next = 0;
    var previous = 0;
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ThreadFindBar(
            controller: TextEditingController(text: 'friday'),
            focusNode: FocusNode(),
            matchLabel: '2/5',
            hasQuery: true,
            hasMatches: true,
            onPrevious: () => previous += 1,
            onNext: () => next += 1,
            onClose: () => closed = true,
          ),
        ),
      ),
    );

    expect(find.text('Find in chat'), findsOneWidget);
    expect(find.text('2/5'), findsOneWidget);
    await tester.tap(find.byTooltip('Next match'));
    await tester.tap(find.byTooltip('Previous match'));
    await tester.tap(find.byTooltip('Close find'));
    expect(next, 1);
    expect(previous, 1);
    expect(closed, isTrue);
  });

  testWidgets('find bar says when nothing matches', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ThreadFindBar(
            controller: TextEditingController(text: 'zebra'),
            focusNode: FocusNode(),
            matchLabel: 'No matches',
            hasQuery: true,
            hasMatches: false,
            onPrevious: () {},
            onNext: () {},
            onClose: () {},
          ),
        ),
      ),
    );

    expect(find.text('No matches'), findsOneWidget);
    final next = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.keyboard_arrow_down_rounded),
    );
    final previous = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.keyboard_arrow_up_rounded),
    );
    expect(next.onPressed, isNull);
    expect(previous.onPressed, isNull);
  });
}
