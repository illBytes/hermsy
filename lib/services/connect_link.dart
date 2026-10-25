/// A Hermes address and key from a `hermsy://connect` link: what the QR
/// code from `hermes-spawn connect` holds.
///
///     hermsy://connect?url=https%3A%2F%2Fhermes.example.com&key=...
///
/// Null for anything else, so a stray QR code is simply not taken.
({String url, String key})? parseConnectLink(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || uri.scheme != 'hermsy' || uri.host != 'connect') {
    return null;
  }
  final url = uri.queryParameters['url']?.trim() ?? '';
  final key = uri.queryParameters['key']?.trim() ?? '';
  final address = Uri.tryParse(url);
  if (address == null ||
      address.scheme != 'https' ||
      address.host.isEmpty ||
      key.isEmpty) {
    return null;
  }
  return (url: url, key: key);
}
