import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/services/slash_commands.dart';

void main() {
  test('parses gateway-style slash commands', () {
    final parsed = parseSlash('/usage');
    expect(parsed?.name, '/usage');
    expect(parsed?.args, '');
  });

  test('parses /new with a title', () {
    final parsed = parseSlash('/new my-experiment');
    expect(parsed?.name, '/new');
    expect(parsed?.args, 'my-experiment');
  });

  test('ignores normal chat', () {
    expect(parseSlash('hello /new'), isNull);
  });
}
