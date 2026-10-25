import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/models/chat_message.dart';
import 'package:hermes_app/screens/pin_screen.dart';
import 'package:hermes_app/services/at_rest_cipher.dart';
import 'package:hermes_app/services/conversation_store.dart';
import 'package:hermes_app/services/delivery_inbox.dart';
import 'package:hermes_app/services/pin_vault.dart';

class _MemoryVault extends PinVault {
  _MemoryVault() : super(iterations: 1000);

  final saved = <String, String>{};

  @override
  Future<String?> load(String key) async => saved[key];

  @override
  Future<void> save(String key, String? value) async =>
      value == null ? saved.remove(key) : saved[key] = value;
}

String hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('PIN', () {
    test('PBKDF2 matches the standard test vector', () {
      expect(
        hex(pbkdf2Sha256(utf8.encode('password'), utf8.encode('salt'), 1, 32)),
        '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
      );
    });

    test('is stored as a salted hash, never as the PIN', () async {
      final vault = _MemoryVault();
      final stored = await vault.write('2580');
      final saved = vault.saved[PinVault.storageKey]!;
      expect(saved, startsWith(r'pbkdf2-sha256$1000$4$'));
      expect(saved, isNot(contains('2580')));
      expect(stored.length, 4);
      expect(await stored.matches('2580'), isTrue);
      expect(await stored.matches('2581'), isFalse);

      // The same PIN twice gets two different salts.
      final other = _MemoryVault();
      await other.write('2580');
      expect(other.saved[PinVault.storageKey], isNot(saved));
    });

    test('a PIN saved in the clear by an older Hermsy is hashed', () async {
      final vault = _MemoryVault()..saved[PinVault.storageKey] = '1234';
      final stored = (await vault.read())!;
      expect(await stored.matches('1234'), isTrue);
      expect(vault.saved[PinVault.storageKey], startsWith('pbkdf2-sha256'));
    });

    test('the lockout is kept, and cleared away', () async {
      final vault = _MemoryVault();
      final until = DateTime.fromMillisecondsSinceEpoch(1792850000000);
      await vault.saveLockout(PinLockout(misses: 6, until: until));
      final again = await vault.lockout();
      expect(again.misses, 6);
      expect(again.until, until);
      await vault.saveLockout(PinLockout.none);
      expect(vault.saved.containsKey(PinVault.lockoutKey), isFalse);
      expect((await vault.lockout()).misses, 0);
    });

    Future<void> enter(WidgetTester tester, String digits) async {
      for (final digit in digits.split('')) {
        await tester.tap(find.text(digit).first);
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('wrong tries are saved, so closing Hermsy does not reset '
        'them', (tester) async {
      final saved = <PinLockout>[];
      await tester.pumpWidget(
        MaterialApp(
          home: PinScreen(
            pin: StoredPin.unhashed('1234'),
            lockout: const PinLockout(misses: 4),
            onLockout: saved.add,
            onUnlocked: () {},
          ),
        ),
      );
      // Four misses from before: this fifth one starts the wait.
      await enter(tester, '0000');
      expect(saved.last.misses, 5);
      expect(saved.last.until, isNotNull);
      expect(find.text('Too many attempts'), findsOneWidget);
      await tester.pump(const Duration(seconds: 31));
    });

    testWidgets('a wait from before closing goes on after reopening', (
      tester,
    ) async {
      var unlocked = false;
      await tester.pumpWidget(
        MaterialApp(
          home: PinScreen(
            pin: StoredPin.unhashed('1234'),
            lockout: PinLockout(
              misses: 5,
              until: DateTime.now().add(const Duration(seconds: 20)),
            ),
            onUnlocked: () => unlocked = true,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Too many attempts'), findsOneWidget);
      await enter(tester, '1234');
      expect(unlocked, isFalse, reason: 'the pad waits');

      await tester.pump(const Duration(seconds: 22));
      await enter(tester, '1234');
      await tester.pump(const Duration(milliseconds: 400));
      expect(unlocked, isTrue);
    });
  });

  group('encrypted at rest', () {
    final cipher = AtRestCipher.withKey(List.generate(32, (i) => i));
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('at_rest');
    });

    tearDown(() async => dir.delete(recursive: true));

    test('seals and opens; refuses a changed file', () async {
      final sealed = await cipher.seal(utf8.encode('Dentist at three'));
      expect(AtRestCipher.isSealed(sealed), isTrue);
      expect(
        utf8.decode(sealed, allowMalformed: true),
        isNot(contains('scan')),
      );
      expect(utf8.decode(await cipher.open(sealed)), 'Dentist at three');

      sealed[sealed.length - 20] ^= 1;
      expect(() => cipher.open(sealed), throwsA(anything));

      // Saved before Frank encrypted: read as it is.
      expect(utf8.decode(await cipher.open(utf8.encode('{"a":1}'))), '{"a":1}');
      final text = await cipher.sealText('{"id":"b1"}');
      expect(text, startsWith('frk1:'));
      expect(await cipher.openText(text), '{"id":"b1"}');
      expect(await cipher.openText('{"plain":true}'), '{"plain":true}');
    });

    test('chats on disk are unreadable without the key', () async {
      final store = ConversationStore(dir, cipher: cipher);
      await store.write(
        ConversationRecord(
          id: 'c1',
          title: 'Passport renewal',
          updatedAt: DateTime(2026, 10, 24),
          messages: [
            ChatMessage(
              id: 'u1',
              role: MessageRole.user,
              text: 'My passport number is X1234567',
            ),
          ],
        ),
      );
      for (final file in dir.listSync().whereType<File>()) {
        final bytes = file.readAsBytesSync();
        expect(AtRestCipher.isSealed(bytes), isTrue, reason: file.path);
        expect(
          utf8.decode(bytes, allowMalformed: true),
          isNot(contains('X1234567')),
        );
      }
      final again = await store.read('c1');
      expect(again!.messages.single.text, 'My passport number is X1234567');
      expect((await store.list()).single.title, 'Passport renewal');
    });

    test('chats and the Inbox saved in the clear are sealed once', () async {
      final plain = ConversationStore(dir);
      await plain.write(
        ConversationRecord(
          id: 'old',
          title: 'Old chat',
          updatedAt: DateTime(2026, 10, 1),
          messages: [
            ChatMessage(id: 'u1', role: MessageRole.user, text: 'Hello'),
          ],
        ),
      );
      final inboxDir = Directory('${dir.path}/inbox');
      await DeliveryInbox(inboxDir).add(
        DeliveryRecord(
          id: 'relay_1',
          title: 'Job',
          body: 'Done.',
          createdAt: DateTime(2026, 10, 1),
        ),
      );

      final sealedStore = ConversationStore(dir, cipher: cipher);
      expect((await sealedStore.read('old'))!.title, 'Old chat');
      await sealedStore.sealAll();
      final sealedInbox = DeliveryInbox(inboxDir, cipher: cipher);
      await sealedInbox.sealAll();

      for (final file in dir.listSync(recursive: true).whereType<File>()) {
        expect(
          AtRestCipher.isSealed(file.readAsBytesSync()),
          isTrue,
          reason: file.path,
        );
      }
      expect((await sealedStore.read('old'))!.messages.single.text, 'Hello');
      expect((await sealedInbox.list()).single.body, 'Done.');
    });
  });
}
