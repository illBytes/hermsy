import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Encrypts what Frank keeps on the phone (chats, the Inbox, the Brief)
/// with AES-256-GCM. The key is random, made once, and kept in Android's
/// secure storage, which a key in the phone's hardware protects: the files
/// alone, copied off the phone, cannot be read.
///
/// Anything saved before Frank encrypted reads as it is, and is encrypted
/// the next time it is saved (or by [ConversationStore.sealAll]).
class AtRestCipher {
  AtRestCipher({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage(),
      _fixedKey = null;

  /// A cipher with a key given outright, for tests.
  @visibleForTesting
  AtRestCipher.withKey(List<int> key)
    : _storage = null,
      _fixedKey = SecretKey(key);

  /// The one the app uses.
  static final shared = AtRestCipher();

  static const keyName = 'frank.at_rest_key';

  /// Starts every sealed file: "FRK" and a version byte.
  static const _magic = [0x46, 0x52, 0x4B, 0x01];

  /// Starts every sealed string kept in preferences.
  static const _textPrefix = 'frk1:';

  final FlutterSecureStorage? _storage;
  final SecretKey? _fixedKey;
  final _algorithm = AesGcm.with256bits();
  Future<SecretKey>? _key;

  /// Makes (or reads) the key now. The app does this before anything is
  /// saved, so two parts of it never make two different keys.
  Future<void> ready() => _secretKey();

  Future<SecretKey> _secretKey() => _key ??= () async {
    final fixed = _fixedKey;
    if (fixed != null) {
      return fixed;
    }
    final storage = _storage!;
    final saved = await storage.read(key: keyName);
    if (saved != null) {
      return SecretKey(base64.decode(saved));
    }
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    await storage.write(key: keyName, value: base64.encode(bytes));
    return SecretKey(bytes);
  }();

  static bool isSealed(List<int> bytes) {
    if (bytes.length < _magic.length) {
      return false;
    }
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) {
        return false;
      }
    }
    return true;
  }

  /// `magic | nonce (12) | ciphertext | tag (16)`.
  Future<Uint8List> seal(List<int> plain) async {
    final box = await _algorithm.encrypt(plain, secretKey: await _secretKey());
    return Uint8List.fromList([
      ..._magic,
      ...box.nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }

  /// [bytes] decrypted, or as they are when they were never sealed. Fails
  /// if a sealed file was changed.
  Future<List<int>> open(List<int> bytes) async {
    if (!isSealed(bytes)) {
      return bytes;
    }
    final body = bytes.sublist(_magic.length);
    final box = SecretBox(
      body.sublist(12, body.length - 16),
      nonce: body.sublist(0, 12),
      mac: Mac(body.sublist(body.length - 16)),
    );
    return _algorithm.decrypt(box, secretKey: await _secretKey());
  }

  Future<String> sealText(String text) async =>
      '$_textPrefix${base64.encode(await seal(utf8.encode(text)))}';

  Future<String> openText(String text) async {
    if (!text.startsWith(_textPrefix)) {
      return text;
    }
    final sealed = base64.decode(text.substring(_textPrefix.length));
    return utf8.decode(await open(sealed));
  }

  static bool isSealedText(String text) => text.startsWith(_textPrefix);
}
