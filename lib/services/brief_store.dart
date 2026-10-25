import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/brief.dart';
import 'at_rest_cipher.dart';
import 'connection_store.dart';
import 'hermes_client.dart';
import 'push_service.dart';
import 'relay_client.dart';

/// The name of the Hermes cron job that writes the brief.
const briefJobName = 'Hermsy Brief';

/// What the job was called before Hermsy was Hermsy; still run if that is
/// the only one a server has.
const legacyBriefJobName = 'Frank Brief';

String _cacheKeyFor(AppConfig config) => 'frank.brief.${config.baseUrl}';

/// Keeps [brief] as the last one seen for [config]'s server, encrypted
/// with [cipher] (tests leave it out).
Future<void> cacheBrief(
  AppConfig config,
  Brief brief, {
  SharedPreferences? preferences,
  AtRestCipher? cipher,
}) async {
  final json = jsonEncode(brief.toJson());
  await (preferences ?? await SharedPreferences.getInstance()).setString(
    _cacheKeyFor(config),
    cipher == null ? json : await cipher.sealText(json),
  );
}

/// The latest Brief: kept on the phone so the page opens at once,
/// refreshed from the relay on open and whenever a push says a new one is
/// waiting, and written afresh by Hermes on request.
class BriefStore extends ChangeNotifier {
  BriefStore({
    required this.connection,
    this.push,
    RelayClient Function(AppConfig config)? relayFor,
    HermesClient Function(AppConfig config)? hermesFor,
    SharedPreferences? preferences,
    this.cipher,
  }) : _relayFor = relayFor ?? RelayClient.new,
       _hermesFor =
           hermesFor ??
           ((config) =>
               HermesClient(baseUrl: config.baseUrl, apiKey: config.apiKey)),
       _preferences = preferences {
    push?.addListener(_onPush);
    _seenPush = push?.briefVersion ?? 0;
  }

  final ConnectionStore connection;
  final PushService? push;

  /// Encrypts the cached brief. Tests leave it out.
  final AtRestCipher? cipher;
  final RelayClient Function(AppConfig config) _relayFor;
  final HermesClient Function(AppConfig config) _hermesFor;
  SharedPreferences? _preferences;
  var _seenPush = 0;

  Brief? brief;
  bool loading = false;

  /// True while Hermes writes a fresh brief on request.
  bool writing = false;
  String? error;

  String get _cacheKey => _cacheKeyFor(connection.current);

  /// The cached brief first, then the relay's newest.
  Future<void> load() async {
    final preferences = _preferences ??= await SharedPreferences.getInstance();
    final cached = preferences.getString(_cacheKey);
    if (brief == null && cached != null) {
      try {
        final json = await (cipher?.openText(cached) ?? Future.value(cached));
        brief = Brief.fromJson(jsonDecode(json) as Map<String, dynamic>);
        notifyListeners();
        // Saved before Frank encrypted: encrypt it now.
        if (cipher != null && !AtRestCipher.isSealedText(cached)) {
          await cacheBrief(
            connection.current,
            brief!,
            preferences: preferences,
            cipher: cipher,
          );
        }
      } catch (_) {}
    }
    await refresh();
  }

  /// Fetches the newest brief from the relay. True when it changed.
  Future<bool> refresh() async {
    final config = connection.current;
    if (!config.looksConfigured) {
      return false;
    }
    loading = true;
    notifyListeners();
    final relay = _relayFor(config);
    try {
      final latest = await relay.latestBrief();
      error = null;
      if (latest == null || latest.id == brief?.id) {
        return false;
      }
      brief = latest;
      await cacheBrief(
        config,
        latest,
        preferences: _preferences ??= await SharedPreferences.getInstance(),
        cipher: cipher,
      );
      return true;
    } catch (err) {
      error = '$err';
      return false;
    } finally {
      relay.close();
      loading = false;
      notifyListeners();
    }
  }

  /// Asks Hermes to write a fresh brief now, then waits for it (up to two
  /// minutes; a push usually brings it sooner).
  Future<void> requestFresh({
    Duration timeout = const Duration(minutes: 2),
    Duration poll = const Duration(seconds: 6),
  }) async {
    if (writing) {
      return;
    }
    final config = connection.current;
    // The brief shown when you asked: a newer one ends the wait, whether it
    // came by this loop or by push.
    final asked = brief?.id;
    writing = true;
    error = null;
    notifyListeners();
    final hermes = _hermesFor(config);
    try {
      final started =
          await hermes.runJobNamed(briefJobName) ||
          await hermes.runJobNamed(legacyBriefJobName);
      if (!started) {
        error =
            'Hermes has no "$briefJobName" job yet. Set it up in Settings › Hermes.';
        return;
      }
      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(poll);
        if (brief?.id != asked) {
          return;
        }
        await refresh();
        if (brief?.id != asked) {
          return;
        }
      }
      error = 'Hermes is still writing the brief. It will appear when ready.';
    } catch (err) {
      error = '$err';
    } finally {
      writing = false;
      notifyListeners();
    }
  }

  void _onPush() {
    final version = push?.briefVersion ?? 0;
    if (version != _seenPush) {
      _seenPush = version;
      unawaited(refresh());
    }
  }

  @override
  void dispose() {
    push?.removeListener(_onPush);
    super.dispose();
  }
}
