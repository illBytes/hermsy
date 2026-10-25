import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/models/chat_message.dart';

void main() {
  test('extracts plain and multimodal content', () {
    expect(ChatMessage.textFromContent('hello'), 'hello');
    expect(
      ChatMessage.textFromContent([
        {'type': 'text', 'text': 'Look at this'},
        {'type': 'image_url', 'image_url': 'https://example.com/a.png'},
      ]),
      'Look at this',
    );
    expect(
      ChatMessage.imagesFromContent([
        {'type': 'text', 'text': 'Look at this'},
        {'type': 'image_url', 'image_url': 'https://example.com/a.png'},
      ]),
      ['https://example.com/a.png'],
    );
  });
}
