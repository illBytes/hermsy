// The Frank app wired to a scripted Hermes, in memory, for screenshots:
// shared by the design shots and the Play Store shots.
import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:hermes_app/config/app_config.dart';
import 'package:hermes_app/services/app_settings.dart';
import 'package:hermes_app/services/conversation_store.dart';
import 'package:hermes_app/services/delivery_inbox.dart';
import 'package:hermes_app/services/hermes_client.dart';
import 'package:hermes_app/services/pin_vault.dart';
import 'package:hermes_app/services/voice_service.dart';
import 'package:hermes_app/state/chat_controller.dart';

import 'fake_hermes.dart';

class ShotRig {
  ShotRig(Directory temp, {String? pin, bool healthy = true})
      : vault = MemoryPinVault(pin),
        hermes = FakeHermes(healthy: healthy),
        store = ConversationStore(Directory('${temp.path}/conversations')),
        inbox = DeliveryInbox(Directory('${temp.path}/inbox'));

  final boundary = GlobalKey();
  final MemoryPinVault vault;
  final FakeHermes hermes;
  final ConversationStore store;
  final DeliveryInbox inbox;
  final settings = AppSettings();
  final voice = ShotVoice();
  final chats = <ChatController>[];

  ChatController build(AppConfig config) {
    final chat = ChatController(
      config: config,
      client: HermesClient(
        baseUrl: config.baseUrl,
        apiKey: config.apiKey,
        httpClient: hermes.client,
      ),
      store: store,
      inbox: inbox,
      voice: voice,
      settings: settings,
    );
    chats.add(chat);
    return chat;
  }
}

/// The PIN vault in memory, with few hash rounds so tests stay quick. The
/// first PIN is stored as an older Frank stored it, in the clear.
class MemoryPinVault extends PinVault {
  MemoryPinVault(String? pin) : super(iterations: 1000) {
    if (pin != null) {
      saved[PinVault.storageKey] = pin;
    }
  }

  final saved = <String, String>{};

  @override
  Future<String?> load(String key) async => saved[key];

  @override
  Future<void> save(String key, String? value) async =>
      value == null ? saved.remove(key) : saved[key] = value;
}

class ShotVoice implements VoiceService {
  final levelFeed = StreamController<double>.broadcast();
  final wordsFeed = StreamController<String>.broadcast();
  final completions = StreamController<void>.broadcast();

  @override
  Stream<double> get levels => levelFeed.stream;

  @override
  Stream<String> get partials => wordsFeed.stream;

  @override
  Stream<void> get onComplete => completions.stream;

  @override
  Future<String> startRecording() async => '${Directory.systemTemp.path}/take.m4a';

  @override
  Future<String?> stopRecording() async => null;

  @override
  Future<void> cancelRecording() async {}

  @override
  Future<void> discard(String path) async {}

  @override
  Future<String> listenOnDevice() => Completer<String>().future;

  @override
  Future<void> stopDeviceListen() async {}

  @override
  Future<void> cancelDeviceListen() async {}

  @override
  Future<String> keepRecording(String path) async => path;

  @override
  Future<String> writeSpeechBytes(List<int> bytes, {String? extension}) async => 'speech.mp3';

  @override
  bool canPlayExtension(String extension) => true;

  @override
  Future<void> preparePlayback() async {}

  @override
  Future<void> play(String path) async {}

  @override
  Future<void> stopPlayback() async {}

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
