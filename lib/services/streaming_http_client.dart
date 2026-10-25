import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Dart's default [HttpClient.idleTimeout] is 15 seconds. Hermes often sits
/// quiet longer than that (thinking, tools, a slow first token), so the phone
/// closes the SSE socket and the reply stops mid-sentence.
const Duration streamingIdleTimeout = Duration(hours: 1);
const Duration streamingConnectTimeout = Duration(seconds: 30);

http.Client createStreamingHttpClient({HttpClient? inner}) {
  final client = inner ?? HttpClient();
  client
    ..idleTimeout = streamingIdleTimeout
    ..connectionTimeout = streamingConnectTimeout;
  return IOClient(client);
}
