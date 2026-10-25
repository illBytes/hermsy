import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/services/hermes_client.dart';

void main() {
  test('detects the virtual hermes-agent model error', () {
    expect(
      isVirtualModelError('HTTP 400: hermes-agent is not a valid model ID'),
      isTrue,
    );
    expect(isVirtualModelError('timeout'), isFalse);
  });

  test('classifies dropped sockets as transient', () {
    expect(isTransientDisconnect('ClientException: Connection closed'), isTrue);
    expect(isTransientDisconnect('bad request'), isFalse);
  });

  test('reads OpenAI-style error payloads', () {
    expect(
      describeHttpError(
        400,
        '{"error":{"message":"HTTP 400: hermes-agent is not a valid model ID"}}',
      ),
      'HTTP 400: hermes-agent is not a valid model ID',
    );
  });
}
