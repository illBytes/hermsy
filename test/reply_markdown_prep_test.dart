import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/services/reply_markdown_prep.dart';
import 'package:hermes_app/theme/app_theme.dart';
import 'package:hermes_app/widgets/reply_code_block.dart';
import 'package:hermes_app/widgets/reply_markdown.dart';

void main() {
  test('fences a bare code dump so it is not scattered as prose', () {
    const raw = '''
Here is the helper:

def greet(name):
    return f"Hello {name}"
print(greet("Hermsy"))
''';
    final prepared = prepareReplyMarkdown(raw);
    expect(prepared, contains('```'));
    expect(prepared, contains('def greet(name):'));
  });

  test('leaves ordinary prose and lists alone', () {
    const raw = '''
Do these:

- buy milk
- call Alex
- lock the door
''';
    expect(prepareReplyMarkdown(raw), isNot(contains('```')));
  });

  test('fences a bare C++ dump as one block, not a split card', () {
    const raw = '''#include <iostream>
int main(){
std::out << "Hello World" << std::endl;
return 0;
}''';
    final prepared = prepareReplyMarkdown(raw);
    expect(
      prepared,
      '```\n'
      '#include <iostream>\n'
      'int main(){\n'
      'std::out << "Hello World" << std::endl;\n'
      'return 0;\n'
      '}\n'
      '```',
    );
  });

  test('unglues fences stuck to C++ so the snippet is one block', () {
    const raw = '''```#include <iostream>
int main(){
std::out << "Hello World" << std::endl;
return 0;
}```''';
    final prepared = prepareReplyMarkdown(raw);
    expect(
      prepared,
      '```\n'
      '#include <iostream>\n'
      'int main(){\n'
      'std::out << "Hello World" << std::endl;\n'
      'return 0;\n'
      '}\n'
      '```',
    );
  });

  test('keeps a language tag on its own opening fence', () {
    const raw = '```dart\nprint("hi");\n```';
    expect(prepareReplyMarkdown(raw), raw);
  });

  test('closes an unfinished fence while a reply is still streaming', () {
    const raw = 'Start\n```dart\nvoid main() {';
    expect(prepareReplyMarkdown(raw).trim().endsWith('```'), isTrue);
  });

  testWidgets('renders a fenced block in the code card', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: ReplyMarkdown(
            data: 'Use this:\n\n```dart\nprint("hi");\n```\n',
          ),
        ),
      ),
    );

    expect(find.byType(ReplyCodeBlock), findsOneWidget);
    expect(find.textContaining('print("hi");'), findsOneWidget);
    expect(find.text('dart'), findsOneWidget);
  });

  testWidgets('renders a bare C++ dump as one code card', (tester) async {
    const raw = '''#include <iostream>
int main(){
std::out << "Hello World" << std::endl;
return 0;
}''';
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: ReplyMarkdown(data: raw),
        ),
      ),
    );

    expect(find.byType(ReplyCodeBlock), findsOneWidget);
    expect(find.textContaining('#include <iostream>'), findsOneWidget);
    expect(find.textContaining('int main(){'), findsOneWidget);
    expect(find.textContaining('Hello World'), findsOneWidget);
  });

  testWidgets('renders glued C++ fences as one code card', (tester) async {
    const raw = '''```#include <iostream>
int main(){
std::out << "Hello World" << std::endl;
return 0;
}```''';
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: ReplyMarkdown(data: raw),
        ),
      ),
    );

    expect(find.byType(ReplyCodeBlock), findsOneWidget);
    expect(find.textContaining('#include <iostream>'), findsOneWidget);
    expect(find.textContaining('int main(){'), findsOneWidget);
    expect(find.textContaining('Hello World'), findsOneWidget);
  });
}
