import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Frank's unlock PIN, as stored: a salted PBKDF2 hash (never the PIN) and
/// the PIN's length, for the dots.
class StoredPin {
  const StoredPin._(this.length, this._encoded);

  /// A PIN kept as it is, for tests that check the screen, not the hash.
  @visibleForTesting
  StoredPin.unhashed(String pin) : this._(pin.length, 'plain\$$pin');

  final int length;

  /// `pbkdf2-sha256$<iterations>$<length>$<salt>$<hash>`, base64 parts.
  final String _encoded;

  /// True when [entered] is the PIN. The hash runs off the UI thread.
  Future<bool> matches(String entered) async {
    final parts = _encoded.split(r'$');
    if (parts.first == 'plain') {
      return entered == parts[1];
    }
    final iterations = int.parse(parts[1]);
    final salt = base64.decode(parts[3]);
    final expected = base64.decode(parts[4]);
    final actual = await _derive(
      utf8.encode(entered),
      salt,
      iterations,
      expected.length,
    );
    return _sameBytes(actual, expected);
  }

  static Future<StoredPin> hash(String pin, {required int iterations}) async {
    final random = Random.secure();
    final salt = Uint8List.fromList(
      List.generate(16, (_) => random.nextInt(256)),
    );
    final hash = await _derive(utf8.encode(pin), salt, iterations, 32);
    return StoredPin._(
      pin.length,
      'pbkdf2-sha256\$$iterations\$${pin.length}\$${base64.encode(salt)}'
      '\$${base64.encode(hash)}',
    );
  }

  static StoredPin? decode(String encoded) {
    final parts = encoded.split(r'$');
    if (parts.length != 5 || parts.first != 'pbkdf2-sha256') {
      return null;
    }
    final length = int.tryParse(parts[2]);
    return length == null ? null : StoredPin._(length, encoded);
  }
}

/// Wrong PINs in a row, and until when the pad waits. Kept with the PIN,
/// so closing Frank does not reset the count.
class PinLockout {
  const PinLockout({this.misses = 0, this.until});

  static const none = PinLockout();

  final int misses;
  final DateTime? until;

  String encode() => '$misses|${until?.millisecondsSinceEpoch ?? ''}';

  static PinLockout decode(String? raw) {
    final parts = (raw ?? '').split('|');
    final misses = int.tryParse(parts.first) ?? 0;
    final at = parts.length > 1 ? int.tryParse(parts[1]) : null;
    return PinLockout(
      misses: misses,
      until: at == null ? null : DateTime.fromMillisecondsSinceEpoch(at),
    );
  }
}

/// The PIN and its lockout, in Android's secure storage (encrypted with a
/// key the hardware keeps).
class PinVault {
  PinVault({FlutterSecureStorage? storage, this.iterations = 100000})
    : _storage = storage ?? const FlutterSecureStorage();

  static const storageKey = 'frank.unlock_pin';
  static const lockoutKey = 'frank.unlock_lockout';

  final FlutterSecureStorage _storage;

  /// PBKDF2 rounds for a new hash: about a third of a second on a phone,
  /// so guessing every 4-digit PIN from a copied hash takes hours, not ms.
  final int iterations;

  /// The raw storage, overridden in tests.
  @protected
  Future<String?> load(String key) => _storage.read(key: key);

  @protected
  Future<void> save(String key, String? value) => value == null
      ? _storage.delete(key: key)
      : _storage.write(key: key, value: value);

  /// The PIN, or null before one is set. A PIN saved by an older Frank in
  /// the clear is hashed here, once.
  Future<StoredPin?> read() async {
    final value = await load(storageKey);
    if (value == null || value.isEmpty) {
      return null;
    }
    final stored = StoredPin.decode(value);
    if (stored != null) {
      return stored;
    }
    return write(value);
  }

  Future<StoredPin> write(String pin) async {
    final stored = await StoredPin.hash(pin, iterations: iterations);
    await save(storageKey, stored._encoded);
    return stored;
  }

  Future<PinLockout> lockout() async =>
      PinLockout.decode(await load(lockoutKey));

  Future<void> saveLockout(PinLockout lockout) => save(
    lockoutKey,
    lockout.misses == 0 && lockout.until == null ? null : lockout.encode(),
  );
}

/// The hash, off the UI thread. A few thousand rounds (tests) are not worth
/// an isolate and run in place.
Future<Uint8List> _derive(
  List<int> password,
  List<int> salt,
  int rounds,
  int length,
) {
  if (rounds <= 20000) {
    return Future.value(pbkdf2Sha256(password, salt, rounds, length));
  }
  return Isolate.run(() => pbkdf2Sha256(password, salt, rounds, length));
}

/// PBKDF2-HMAC-SHA256 (RFC 8018).
@visibleForTesting
Uint8List pbkdf2Sha256(
  List<int> password,
  List<int> salt,
  int rounds,
  int length,
) {
  final hmac = Hmac(sha256, password);
  final out = BytesBuilder();
  for (var block = 1; out.length < length; block++) {
    final first = Uint8List(salt.length + 4)
      ..setAll(0, salt)
      ..buffer.asByteData().setUint32(salt.length, block);
    var u = hmac.convert(first).bytes;
    final t = Uint8List.fromList(u);
    for (var i = 1; i < rounds; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    out.add(t);
  }
  return Uint8List.sublistView(out.toBytes(), 0, length);
}

/// Compares in constant time, so timing says nothing about the hash.
bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
