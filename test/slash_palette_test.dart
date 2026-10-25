import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/services/slash_commands.dart';
import 'package:hermes_app/theme/app_theme.dart';
import 'package:hermes_app/widgets/slash_palette.dart';

List<String> _names(String text) {
  return [for (final info in matchSlashCommands(text)) info.command];
}

void main() {
  test('a bare slash offers every local command', () {
    expect(_names('/'), [
      '/new',
      '/reset',
      '/clear',
      '/usage',
      '/status',
      '/stop',
      '/undo',
      '/help',
    ]);
  });

  test('filters by prefix, ignoring case', () {
    expect(_names('/s'), ['/status', '/stop']);
    expect(_names('/U'), ['/usage', '/undo']);
    expect(_names('/usage'), ['/usage']);
  });

  test('offers nothing for normal text, a space, or an unknown command', () {
    expect(_names(''), isEmpty);
    expect(_names('hello /new'), isEmpty);
    expect(_names(' /new'), isEmpty);
    expect(_names('/new my-chat'), isEmpty);
    expect(_names('/model'), isEmpty);
  });

  test('every palette command is one the controller understands', () {
    for (final info in slashCommandCatalog) {
      expect(parseSlash(info.command)?.name, info.command);
      expect(info.description, isNotEmpty);
    }
  });

  testWidgets('lists commands with descriptions and runs the tapped one', (
    tester,
  ) async {
    SlashCommandInfo? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Center(
            child: SlashPalette(
              commands: matchSlashCommands('/u'),
              onSelect: (info) => picked = info,
            ),
          ),
        ),
      ),
    );

    expect(find.text('COMMANDS'), findsOneWidget);
    expect(find.text('/usage'), findsOneWidget);
    expect(find.text('Tokens and cost for this chat'), findsOneWidget);
    expect(find.text('/undo'), findsOneWidget);
    expect(find.text('Remove the last exchange'), findsOneWidget);
    expect(find.text('/help'), findsNothing);

    await tester.tap(find.text('Remove the last exchange'));
    expect(picked?.command, '/undo');
  });

  testWidgets('rows are at least 44dp tall', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Center(
            child: SlashPalette(
              commands: matchSlashCommands('/help'),
              onSelect: (_) {},
            ),
          ),
        ),
      ),
    );

    final row = find.ancestor(
      of: find.text('/help'),
      matching: find.byType(AnimatedContainer),
    );
    expect(tester.getSize(row).height, greaterThanOrEqualTo(44));
  });
}
