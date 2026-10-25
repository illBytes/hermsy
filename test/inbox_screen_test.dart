import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/screens/inbox_screen.dart';
import 'package:hermes_app/services/delivery_inbox.dart';
import 'package:hermes_app/theme/app_theme.dart';

void main() {
  testWidgets('empty inbox explains what lands here', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(body: InboxBody(items: [])),
      ),
    );

    expect(find.text('Nothing here yet'), findsOneWidget);
    expect(find.textContaining('scheduled job'), findsOneWidget);
    expect(find.textContaining('delivers it to frank'), findsOneWidget);
  });

  testWidgets('lists a saved delivery without opening image files', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: InboxBody(
            items: [
              DeliveryRecord(
                id: 'del_1',
                title: 'Banner ready',
                body: 'Saved as banners/day.svg',
                createdAt: DateTime.utc(2026, 9, 3, 10),
                remotePaths: const ['/opt/data/banners/day.svg'],
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Banner ready'), findsOneWidget);
    expect(find.text('Saved as banners/day.svg'), findsOneWidget);
    expect(find.text('day.svg'), findsOneWidget);
  });

  testWidgets('groups deliveries by day, newest first', (tester) async {
    final now = DateTime(2026, 9, 10, 18);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: InboxBody(
            now: now,
            items: [
              DeliveryRecord(
                id: 'del_3',
                title: 'Chart for the report',
                body: '',
                createdAt: DateTime(2026, 9, 10, 9, 30),
              ),
              DeliveryRecord(
                id: 'del_2',
                title: 'Logo draft',
                body: '',
                createdAt: DateTime(2026, 9, 9, 22),
              ),
              DeliveryRecord(
                id: 'del_1',
                title: 'Banner ready',
                body: '',
                createdAt: DateTime(2026, 9, 3, 10),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('YESTERDAY'), findsOneWidget);
    expect(find.text('THU 3 SEP'), findsOneWidget);
    final today = tester.getTopLeft(find.text('TODAY')).dy;
    final chart = tester.getTopLeft(find.text('Chart for the report')).dy;
    final yesterday = tester.getTopLeft(find.text('YESTERDAY')).dy;
    final logo = tester.getTopLeft(find.text('Logo draft')).dy;
    expect(today, lessThan(chart));
    expect(chart, lessThan(yesterday));
    expect(yesterday, lessThan(logo));
  });

  testWidgets('shows a title that repeats the first line only once', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: InboxBody(
            items: [
              DeliveryRecord(
                id: 'del_1',
                title: 'Weekly report',
                body: 'Weekly report\nRevenue is up on last week.',
                createdAt: DateTime.utc(2026, 9, 3, 10),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Weekly report'), findsOneWidget);
    expect(find.text('Revenue is up on last week.'), findsOneWidget);
  });

  testWidgets('long-press copies a delivery', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: InboxBody(
            items: [
              DeliveryRecord(
                id: 'del_1',
                title: 'Banner ready',
                body: 'Saved as banners/day.svg',
                createdAt: DateTime.utc(2026, 9, 3, 10),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.longPress(find.text('Banner ready'));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsNothing, reason: 'nothing to delete with');
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(copied, 'Banner ready\nSaved as banners/day.svg');
    expect(find.text('Copied'), findsOneWidget);
  });

  group('deleting', () {
    late Directory dir;
    late DeliveryInbox inbox;

    DeliveryRecord record(String id, String title, int hour) => DeliveryRecord(
      id: id,
      title: title,
      body: 'Body of $title',
      createdAt: DateTime(2026, 10, 24, hour),
    );

    /// File reads and writes finish in real time, one step per round.
    Future<void> idle(WidgetTester tester) async {
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
    }

    Future<void> pumpInbox(WidgetTester tester) async {
      dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('inbox'),
      ))!;
      inbox = DeliveryInbox(dir);
      await tester.runAsync(() async {
        await inbox.add(record('relay_a', 'Morning job', 7));
        await inbox.add(record('relay_b', 'Evening job', 19));
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: InboxScreen(inbox: inbox),
        ),
      );
      await tester.pumpAndSettle();
      await idle(tester);
      await tester.pumpAndSettle();
    }

    Future<List<String>> saved(WidgetTester tester) async =>
        (await tester.runAsync(inbox.list))!.map((r) => r.title).toList();

    testWidgets('swiping a message away deletes it, and Undo restores it', (
      tester,
    ) async {
      await pumpInbox(tester);
      addTearDown(() => tester.runAsync(() => dir.delete(recursive: true)));
      await tester.drag(find.text('Morning job'), const Offset(-600, 0));
      await tester.pumpAndSettle();
      await idle(tester);
      await tester.pumpAndSettle();

      expect(find.text('Morning job'), findsNothing);
      expect(find.text('Evening job'), findsOneWidget);
      expect(await saved(tester), ['Evening job']);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      await idle(tester);
      await tester.pumpAndSettle();
      expect(find.text('Morning job'), findsOneWidget);
      expect(await saved(tester), ['Evening job', 'Morning job']);
    });

    testWidgets('the Undo bar times out, and leaves with the inbox', (
      tester,
    ) async {
      await pumpInbox(tester);
      addTearDown(() => tester.runAsync(() => dir.delete(recursive: true)));
      await tester.drag(find.text('Morning job'), const Offset(-600, 0));
      await tester.pumpAndSettle();
      await idle(tester);
      await tester.pumpAndSettle();
      expect(find.text('Message deleted'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Message deleted'), findsNothing, reason: 'timed out');

      // Delete again and leave at once: the bar does not follow you.
      await tester.drag(find.text('Evening job'), const Offset(-600, 0));
      await tester.pumpAndSettle();
      await idle(tester);
      await tester.pumpAndSettle();
      expect(find.text('Message deleted'), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(theme: buildAppTheme(), home: const Scaffold()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Message deleted'), findsNothing);
    });

    testWidgets('new messages get a dot, and opening the Inbox sees them', (
      tester,
    ) async {
      dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('inbox'),
      ))!;
      addTearDown(() => tester.runAsync(() => dir.delete(recursive: true)));
      inbox = DeliveryInbox(dir);
      await tester.runAsync(() async {
        await inbox.add(record('relay_a', 'Seen job', 7));
        await inbox.add(
          record('relay_b', 'Evening job', 19).copyWith(read: false),
        );
      });
      expect(DeliveryInbox.unread.value, 1);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: InboxScreen(inbox: inbox),
        ),
      );
      await idle(tester);
      await tester.pumpAndSettle();
      // The dot reads as "New", merged into its card's label.
      expect(find.bySemanticsLabel(RegExp(r'\bNew\b')), findsOneWidget);
      expect(DeliveryInbox.unread.value, 0);
      expect((await tester.runAsync(inbox.list))!.every((r) => r.read), isTrue);
    });

    testWidgets('long-press offers Delete', (tester) async {
      await pumpInbox(tester);
      addTearDown(() => tester.runAsync(() => dir.delete(recursive: true)));
      await tester.longPress(find.text('Evening job'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await idle(tester);
      await tester.pumpAndSettle();

      expect(find.text('Evening job'), findsNothing);
      expect(await saved(tester), ['Morning job']);
      expect(find.text('Message deleted'), findsOneWidget);
    });
  });
}
