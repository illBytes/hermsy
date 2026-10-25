import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import 'app_settings.dart';
import 'at_rest_cipher.dart';
import 'brief_store.dart';
import 'brief_widget.dart';
import 'connection_store.dart';
import 'delivery_inbox.dart';
import 'relay_client.dart';
import 'relay_sync.dart';

enum PushStatus {
  /// Not started yet, or this build has no Firebase config.
  off,
  starting,

  /// The person said no to notifications (Android 13+ asks).
  denied,
  ready,
  failed,
}

/// Push notifications through Firebase Cloud Messaging and the Hermsy plugin.
///
/// A push carries nothing but "wake": the app then asks the plugin on its own
/// Hermes what is new, shows it, and files it in the Inbox. Console test
/// pushes (which carry a notification) show as sent.
class PushService extends ChangeNotifier {
  PushService({
    this.connection,
    RelayClient Function(AppConfig config)? relayFor,
    Future<DeliveryInbox> Function()? openInbox,
  }) : _relayFor = relayFor ?? RelayClient.new,
       _openInbox = openInbox ?? DeliveryInbox.open;

  /// The saved Hermes server, where the plugin answers.
  final ConnectionStore? connection;
  final RelayClient Function(AppConfig config) _relayFor;
  final Future<DeliveryInbox> Function() _openInbox;

  PushStatus _status = PushStatus.off;
  String? _token;
  String? _error;
  String? _relayError;
  String? _registered;
  String? _pendingOpen;
  var _briefVersion = 0;

  /// Goes up with each wake, so the Brief page looks for a new one.
  int get briefVersion => _briefVersion;
  Future<List<DeliveryRecord>>? _catchingUp;
  StreamSubscription<String>? _refresh;
  StreamSubscription<RemoteMessage>? _foreground;

  PushStatus get status => _status;

  /// This device's FCM token: the address a test push from the Firebase
  /// console (and the relay) sends to.
  String? get token => _token;
  String? get error => _error;

  /// Why the plugin could not be reached, when it could not.
  String? get relayError => _relayError;

  /// True once the relay knows where to push.
  bool get registered => _registered != null && _registered == _registrationKey;

  /// The relay message a tapped notification asked to open, until
  /// [takePendingOpen] hands it over.
  String? get pendingOpen => _pendingOpen;

  /// Skips Firebase: tests hand over a token as if FCM had issued it.
  @visibleForTesting
  void debugUseToken(String token) {
    _token = token;
    _status = PushStatus.ready;
  }

  String? takePendingOpen() {
    final id = _pendingOpen;
    _pendingOpen = null;
    return id;
  }

  AppConfig? get _config {
    final config = connection?.current;
    return config != null && config.looksConfigured ? config : null;
  }

  String? get _registrationKey {
    final config = _config;
    final token = _token;
    return config == null || token == null ? null : '${config.baseUrl}|$token';
  }

  /// Asks for permission, fetches the token and registers with the relay.
  /// Safe to call again; it only runs once per launch.
  Future<void> start() async {
    if (_status != PushStatus.off) {
      return;
    }
    _set(PushStatus.starting);
    try {
      if (!await _initFirebase()) {
        _set(PushStatus.off);
        return;
      }
      await _initNotifications(onTap: _onNotificationTap);
      final launch = await _notifications.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        _onNotificationTap(launch!.notificationResponse);
      }
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        _set(PushStatus.denied);
        return;
      }
      _foreground = FirebaseMessaging.onMessage.listen(_showForeground);
      _refresh = messaging.onTokenRefresh.listen((token) {
        _token = token;
        notifyListeners();
        _register();
      });
      connection?.addListener(_register);
      _token = await messaging.getToken();
      if (kDebugMode) {
        // For a test push from the Firebase console, from `flutter run`.
        debugPrint('FCM token: $_token');
      }
      _set(PushStatus.ready);
      await _register();
    } catch (error) {
      _error = '$error';
      _set(PushStatus.failed);
    }
  }

  /// Tells the relay this phone's token: on start, when the token rotates,
  /// and when the server changes.
  Future<void> _register() async {
    final key = _registrationKey;
    final config = _config;
    final token = _token;
    if (key == null || config == null || token == null || key == _registered) {
      return;
    }
    final relay = _relayFor(config);
    try {
      await relay.registerDevice(token);
      _registered = key;
      _relayError = null;
    } catch (error) {
      _relayError = '$error';
    } finally {
      relay.close();
    }
    notifyListeners();
  }

  /// Files messages the app has not seen into the Inbox. Runs on open, on
  /// resume and with each push; overlapping calls share one run. Returns
  /// what it added.
  Future<List<DeliveryRecord>> catchUp() {
    return _catchingUp ??= _catchUp().whenComplete(() => _catchingUp = null);
  }

  Future<List<DeliveryRecord>> _catchUp() async {
    final config = _config;
    if (config == null) {
      return const [];
    }
    // A registration that failed (relay down, wrong key) retries here, on
    // every open and resume; once it has worked this returns at once.
    await _register();
    final relay = _relayFor(config);
    try {
      final added = await RelaySync(
        client: relay,
        inbox: await _openInbox(),
      ).catchUp();
      _relayError = null;
      if (added.isNotEmpty) {
        notifyListeners();
      }
      return added;
    } catch (error) {
      _relayError = '$error';
      notifyListeners();
      return const [];
    } finally {
      relay.close();
    }
  }

  /// The Inbox record for relay message [id], whose notification was
  /// tapped: it counts as read from here.
  Future<DeliveryRecord?> relayRecordFor(String id) async {
    final record = await _relayRecordFor(id);
    if (record != null) {
      await (await _openInbox()).markRead(record.id);
    }
    return record;
  }

  /// From the Inbox, after a catch-up if it is not there yet, or straight
  /// from the relay.
  Future<DeliveryRecord?> _relayRecordFor(String id) async {
    final inbox = await _openInbox();
    DeliveryRecord? find(List<DeliveryRecord> items) {
      for (final item in items) {
        if (item.id == '$relayRecordPrefix$id') {
          return item;
        }
      }
      return null;
    }

    final saved = find(await inbox.list());
    if (saved != null) {
      return saved;
    }
    await catchUp();
    final caught = find(await inbox.list());
    final config = _config;
    if (caught != null || config == null) {
      return caught;
    }
    final relay = _relayFor(config);
    try {
      final record = relayRecord(await relay.message(id));
      await inbox.add(record);
      return record;
    } catch (_) {
      return null;
    } finally {
      relay.close();
    }
  }

  void _onNotificationTap(NotificationResponse? response) {
    final id = response?.payload;
    if (id == null || id.isEmpty) {
      return;
    }
    _pendingOpen = id;
    notifyListeners();
  }

  void _set(PushStatus status) {
    _status = status;
    notifyListeners();
  }

  /// The system only shows pushes while Frank is in the background, so a
  /// push that arrives with Frank open is shown here.
  Future<void> _showForeground(RemoteMessage message) async {
    final notification = message.notification;
    if (notification != null) {
      await _notifications.show(
        id: _idFor(message),
        title: notification.title ?? 'Hermsy',
        body: notification.body,
        notificationDetails: _details(),
      );
      return;
    }
    // A wake: look for a new Brief, and show what reached the Inbox.
    _briefVersion++;
    notifyListeners();
    for (final record in await catchUp()) {
      await _showRecord(record);
    }
  }

  Future<void> _showRecord(DeliveryRecord record) async {
    final content = notificationContent(record.title, record.body);
    final id = record.id.substring(relayRecordPrefix.length);
    await _notifications.show(
      id: id.hashCode,
      title: content.title,
      body: content.body,
      notificationDetails: _details(expanded: content.expanded),
      payload: id,
    );
  }

  @override
  void dispose() {
    _refresh?.cancel();
    _foreground?.cancel();
    connection?.removeListener(_register);
    super.dispose();
  }
}

/// Runs in its own isolate when a push arrives while Frank is in the
/// background or closed. Must stay a top-level function.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  // A push with a notification is shown by the system already.
  if (message.notification != null) {
    return;
  }
  WidgetsFlutterBinding.ensureInitialized();
  if (!await _initFirebase()) {
    return;
  }
  await _initNotifications();
  AppConfig? config;
  try {
    final connection = ConnectionStore();
    await connection.load();
    config = connection.current.looksConfigured ? connection.current : null;
  } catch (_) {
    // Shown with the generic line; the text arrives with the next catch-up.
  }
  if (config == null) {
    return;
  }
  // A wake: show what is new, and redraw the widget if the Brief changed.
  await notifyNewMessages(config);
  await refreshBriefWidget(config);
}

/// Fetches the newest brief and redraws the widget with it, from the push
/// isolate while Frank is closed. The brief is cached too, so the app opens
/// on it.
@visibleForTesting
Future<void> refreshBriefWidget(
  AppConfig config, {
  RelayClient Function(AppConfig config)? relayFor,
}) async {
  final relay = (relayFor ?? RelayClient.new)(config);
  try {
    final brief = await relay.latestBrief();
    if (brief == null) {
      return;
    }
    final settings = AppSettings();
    await settings.load();
    await cacheBrief(config, brief, cipher: AtRestCipher.shared);
    await updateBriefWidget(brief, settings);
  } catch (_) {
    // The widget keeps the last brief; the app refreshes it on open.
  } finally {
    relay.close();
  }
}

/// Shows a notification for each message the plugin has that no
/// notification has been shown for, from the push isolate. It does not file
/// them: the Inbox is written only by the app itself (catch-up), so two
/// isolates never write the same file.
@visibleForTesting
Future<int> notifyNewMessages(
  AppConfig config, {
  RelayClient Function(AppConfig config)? relayFor,
  SharedPreferences? preferences,
  Future<void> Function(RelayMessage message)? show,
}) async {
  final cursor = MessageCursor(
    preferences ?? await SharedPreferences.getInstance(),
    config.baseUrl,
  );
  final relay = (relayFor ?? RelayClient.new)(config);
  final shown = <RelayMessage>[];
  try {
    final store = cursor.store;
    var since = store == null ? 0 : cursor.notifiedFor(store) ?? cursor.seq;
    var page = await relay.messagesSince(since);
    if (page.store != store && since != 0) {
      // A store not seen before: everything in it is new.
      since = 0;
      page = await relay.messagesSince(0);
    }
    // Anything older than a day was surely seen, or no longer matters.
    final cutoff = DateTime.now().subtract(const Duration(days: 1));
    var last = since;
    while (true) {
      for (final message in page.messages) {
        if (message.createdAt.isAfter(cutoff)) {
          shown.add(message);
        }
      }
      if (page.messages.isEmpty || page.next <= last) {
        break;
      }
      last = page.next;
      page = await relay.messagesSince(last);
    }
    // The newest few: a long list of notifications helps nobody.
    for (final message in shown.reversed.take(5).toList().reversed) {
      await (show ?? _showMessage)(message);
    }
    await cursor.notified(page.store, last);
  } catch (_) {
    // The app catches up when it opens.
  } finally {
    relay.close();
  }
  return shown.length;
}

Future<void> _showMessage(RelayMessage message) async {
  final content = notificationContent(message.title, message.text);
  await _notifications.show(
    id: message.id.hashCode,
    title: content.title,
    body: content.body,
    notificationDetails: _details(expanded: content.expanded),
    payload: message.id,
  );
}

/// What a notification for a message titled [title] says.
({String title, String body, String? expanded}) notificationContent(
  String title,
  String text,
) {
  final preview = relayPreview(text);
  final plain = relayPlainText(text);
  return (
    title: title.isEmpty ? 'Hermsy' : title,
    body: preview.isEmpty ? 'New message from Hermsy' : preview,
    // Expanded, the notification shows the start of the whole message.
    expanded: plain.length > preview.length
        ? (plain.length > 1500 ? '${plain.substring(0, 1499)}…' : plain)
        : null,
  );
}

final _notifications = FlutterLocalNotificationsPlugin();

const _channel = AndroidNotificationChannel(
  // Also named in AndroidManifest.xml as FCM's default channel.
  'frank_messages',
  'Messages from Hermsy',
  description: 'Cron results and other messages Hermsy sends on its own',
  importance: Importance.high,
);

NotificationDetails _details({String? expanded}) => NotificationDetails(
  android: AndroidNotificationDetails(
    _channel.id,
    _channel.name,
    channelDescription: _channel.description,
    importance: Importance.high,
    priority: Priority.high,
    // On a locked phone only "Hermsy" shows, not what Hermes wrote.
    visibility: NotificationVisibility.private,
    styleInformation: expanded == null
        ? null
        : BigTextStyleInformation(expanded),
  ),
);

int _idFor(RemoteMessage message) =>
    (message.data['message_id'] ?? message.messageId ?? message.sentTime)
        .hashCode;

/// False when this build has no Firebase config (no google-services.json).
Future<bool> _initFirebase() async {
  if (Firebase.apps.isNotEmpty) {
    return true;
  }
  try {
    await Firebase.initializeApp();
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> _initNotifications({
  DidReceiveNotificationResponseCallback? onTap,
}) async {
  await _notifications.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        // FirebaseMessaging.requestPermission asks instead.
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    ),
    onDidReceiveNotificationResponse: onTap,
  );
  await _notifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(_channel);
}
