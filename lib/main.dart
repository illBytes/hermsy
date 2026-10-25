import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:home_widget/home_widget.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'config/app_config.dart';
import 'presence/presence_engine.dart';
import 'presence/presence_shaders.dart';
import 'screens/chat_screen.dart';
import 'screens/brief_screen.dart';
import 'screens/inbox_screen.dart';
import 'screens/pin_screen.dart';
import 'screens/set_pin_screen.dart';
import 'screens/server_settings_screen.dart';
import 'screens/settings_screen.dart';
import 'services/app_settings.dart';
import 'services/at_rest_cipher.dart';
import 'services/biometric_gate.dart';
import 'services/brief_store.dart';
import 'services/brief_widget.dart';
import 'services/connection_store.dart';
import 'services/conversation_store.dart';
import 'services/delivery_inbox.dart';
import 'services/display_corners.dart';
import 'services/frank_haptics.dart';
import 'services/hermes_client.dart';
import 'services/pin_vault.dart';
import 'services/push_service.dart';
import 'services/voice_models.dart';
import 'voice/on_device_voice.dart';
import 'state/chat_controller.dart';
import 'theme/app_theme.dart';
import 'widgets/edge_glow.dart';
import 'widgets/frank_orb.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // Light or dark follows the system, from the very first frame.
  AppColors.use(PlatformDispatcher.instance.platformBrightness);
  SystemChrome.setSystemUIOverlayStyle(frankSystemBars());
  FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
  // The key that encrypts chats on the phone, made before anything is saved.
  await AtRestCipher.shared.ready();
  final connection = ConnectionStore();
  // Compile the glow and orb shaders before the first frame so the first
  // bloom never hitches and the first orbs never paint the fallback.
  await Future.wait([
    connection.load(),
    PresenceShaders.warmUp(),
    _precacheOrb(),
  ]);
  final voiceModels = VoiceModelStore();
  unawaited(voiceModels.load());
  // The Inbox badge, before anything new arrives; and anything saved before
  // Frank encrypted, encrypted now.
  unawaited(
    DeliveryInbox.open().then((inbox) async {
      await inbox.sealAll();
      await inbox.refreshUnread();
    }),
  );
  unawaited(ConversationStore.open().then((store) => store.sealAll()));
  runApp(
    FrankApp(
      connection: connection,
      push: PushService(connection: connection),
      voiceModels: voiceModels,
      homeScreenWidget: true,
      cipher: AtRestCipher.shared,
    ),
  );
}

Future<void> _precacheOrb() async {
  try {
    await FrankOrb.precache();
  } catch (_) {
    // The orb paints its canvas fallback until (or unless) the shader loads.
  }
}

class FrankApp extends StatefulWidget {
  const FrankApp({
    super.key,
    required this.connection,
    this.vault,
    this.settings,
    this.push,
    this.voiceModels,
    this.homeScreenWidget = false,
    this.cipher,
    this.widgetTaps,
    this.chatBuilder,
  });

  final ConnectionStore connection;
  final PinVault? vault;
  final AppSettings? settings;

  /// Push notifications. Tests leave it out, and push stays off.
  final PushService? push;

  /// On-device voice models (voice mode). Tests leave them out.
  final VoiceModelStore? voiceModels;

  /// Keep the home-screen Brief widget in step and open the Brief from it.
  /// Off in tests, which have no widget plugin.
  final bool homeScreenWidget;

  /// Encrypts what Frank keeps on the phone. Tests leave it out.
  final AtRestCipher? cipher;

  /// Taps on the home-screen widget, for tests: the plugin's own stream is
  /// used when [homeScreenWidget] is on.
  final Stream<Uri?>? widgetTaps;

  /// Builds the conversation for a server. Tests pass one with fake network
  /// and voice; the app builds the real one.
  @visibleForTesting
  final ChatController Function(AppConfig config)? chatBuilder;

  @override
  State<FrankApp> createState() => _FrankAppState();
}

enum _Stage { loading, createPin, changePin, locked, chat }

class _FrankAppState extends State<FrankApp>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  late final PinVault _vault;
  late final AppSettings _settings;
  late final FrankHaptics _haptics;
  late final PresenceEngine _presence;
  final _biometric = BiometricGate();
  StoredPin? _pin;
  PinLockout _lockout = PinLockout.none;
  bool _loading = true;
  bool _unlocked = false;
  bool _changingPin = false;
  bool _covered = false;
  DateTime? _backgroundedAt;
  ChatController? _chat;
  var _connectionGen = 0;
  final _nav = GlobalKey<NavigatorState>();
  final _routes = _RouteLog();

  /// Frank's Brief, shared by every chat.
  late final BriefStore _brief = BriefStore(
    connection: widget.connection,
    push: widget.push,
    cipher: widget.cipher,
  );

  /// Parakeet and Kokoro on the phone, shared by every chat.
  late final OnDeviceVoice? _onDeviceVoice = widget.voiceModels == null
      ? null
      : OnDeviceVoice(widget.voiceModels!, settings: _settings);

  /// Built once: settings changes rebuild the app, and a fresh ThemeData
  /// would make every themed widget rebuild (or animate) for nothing.
  final _darkTheme = buildAppTheme(Brightness.dark);
  final _lightTheme = buildAppTheme(Brightness.light);

  ConnectionStore get _connection => widget.connection;
  AppConfig get _config => _connection.current;

  @override
  void initState() {
    super.initState();
    _vault = widget.vault ?? PinVault();
    _settings = widget.settings ?? AppSettings();
    _haptics = FrankHaptics(_settings);
    _presence = PresenceEngine(vsync: this)..configure(_settings);
    _settings.addListener(_onSettings);
    widget.push?.addListener(_onPush);
    if (widget.homeScreenWidget) {
      _brief.addListener(_syncWidget);
      unawaited(
        HomeWidget.initiallyLaunchedFromHomeWidget().then(_onWidgetTap),
      );
    }
    final taps =
        widget.widgetTaps ??
        (widget.homeScreenWidget ? HomeWidget.widgetClicked : null);
    _widgetTaps = taps?.listen(_onWidgetTap);
    WidgetsBinding.instance.addObserver(this);
    // The corner radius needs an attached window.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCorners());
    _load();
  }

  Future<void> _load() async {
    final pin = await _vault.read();
    final lockout = await _vault.lockout();
    await _settings.load();
    if (!mounted) {
      return;
    }
    setState(() {
      _pin = pin;
      _lockout = lockout;
      _loading = false;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _settings.removeListener(_onSettings);
    widget.push?.removeListener(_onPush);
    _brief.removeListener(_syncWidget);
    _widgetTaps?.cancel();
    _presence.dispose();
    _chat?.dispose();
    _onDeviceVoice?.dispose();
    _brief.dispose();
    super.dispose();
  }

  StreamSubscription<Uri?>? _widgetTaps;
  bool _openBriefWhenUnlocked = false;

  /// The home-screen widget mirrors the latest brief and its settings.
  void _syncWidget() {
    if (widget.homeScreenWidget) {
      unawaited(updateBriefWidget(_brief.brief, _settings));
    }
  }

  /// A tap on the widget opens the Brief, after the unlock if Frank is
  /// locked.
  void _onWidgetTap(Uri? uri) {
    if (uri?.host != 'brief') {
      return;
    }
    _openBriefWhenUnlocked = true;
    _openPendingBrief();
  }

  /// Taps on the widget or a notification reach Frank a moment before it
  /// is back in the foreground, and the auto-lock only runs then: a page
  /// opened before that would be closed again by the lock. So they wait.
  bool get _readyToOpen {
    final state = WidgetsBinding.instance.lifecycleState;
    return mounted &&
        _unlocked &&
        (state == null || state == AppLifecycleState.resumed);
  }

  void _openPendingBrief() {
    if (!_openBriefWhenUnlocked || !_readyToOpen) {
      return;
    }
    _openBriefWhenUnlocked = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nav.currentState?.push(
        MaterialPageRoute<void>(
          builder: (context) =>
              BriefScreen(store: _brief, settings: _settings, chat: _chat),
        ),
      );
    });
  }

  void _onSettings() {
    _syncWidget();
    _presence.configure(_settings);
    SecureDisplay.apply(_settings.hideInSwitcher);
    // Reduce motion and haptics reach the lock screens and the app-wide
    // motion setting through this build.
    if (mounted) {
      setState(() {});
    }
  }

  void _loadCorners() {
    if (!mounted) {
      return;
    }
    final view = View.maybeOf(context);
    if (view != null) {
      DisplayCorners.load(view.devicePixelRatio);
    }
  }

  @override
  void didChangePlatformBrightness() => _followSystemBrightness();

  void _followSystemBrightness() {
    final brightness = View.of(context).platformDispatcher.platformBrightness;
    if (!AppColors.use(brightness)) {
      return;
    }
    SystemChrome.setSystemUIOverlayStyle(frankSystemBars());
    // Colours are read straight from AppColors, not looked up from the
    // theme, so nothing knows they changed: rebuild and repaint everything.
    void rebuild(Element element) {
      element.markNeedsBuild();
      element.renderObject?.markNeedsPaint();
      element.visitChildren(rebuild);
    }

    (context as Element).visitChildren(rebuild);
    setState(() {});
  }

  @override
  void didChangeMetrics() {
    // Retries until Android can report the corners; a no-op afterwards.
    _loadCorners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _coverForSwitcher(state != AppLifecycleState.resumed);
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      // Coming back runs paused -> hidden -> inactive -> resumed: keep the
      // moment the app left, not the moment it passed through hidden again.
      _backgroundedAt ??= DateTime.now();
      // A call goes on off screen (CallService): its reply is not paused.
      if (!(_chat?.inCall ?? false)) {
        _chat?.setForeground(false);
      }
      return;
    }
    if (state != AppLifecycleState.resumed) {
      return;
    }
    // In case the system switched while Frank was away and the change was
    // not delivered.
    _followSystemBrightness();
    final left = _backgroundedAt;
    _backgroundedAt = null;
    _chat?.setForeground(true);
    if (_unlocked) {
      widget.push?.catchUp();
    }
    // Like a phone call, a live call is never cut off by the lock: Frank
    // locks when you come back after it has ended.
    final inCall = _chat?.inCall ?? false;
    if (_unlocked &&
        !inCall &&
        _settings.autoLock &&
        left != null &&
        DateTime.now().difference(left) >= _settings.autoLockAfter) {
      _lock();
    }
    // Taps that came in while Frank was away open now, or after the unlock.
    _onPush();
    _openPendingBrief();
  }

  /// iOS has no FLAG_SECURE: cover the app while it is inactive so the app
  /// switcher snapshot shows only the canvas and a still orb.
  void _coverForSwitcher(bool away) {
    final cover = away &&
        _settings.hideInSwitcher &&
        defaultTargetPlatform == TargetPlatform.iOS;
    if (cover != _covered) {
      setState(() => _covered = cover);
    }
  }

  _Stage get _stage {
    if (_loading) {
      return _Stage.loading;
    }
    if (_pin == null) {
      return _Stage.createPin;
    }
    // The lock always wins: changing the PIN needs an unlocked app.
    if (!_unlocked) {
      return _Stage.locked;
    }
    return _changingPin ? _Stage.changePin : _Stage.chat;
  }

  @override
  Widget build(BuildContext context) {
    final stage = _stage;
    return MaterialApp(
      title: 'Hermsy',
      debugShowCheckedModeBanner: false,
      navigatorKey: _nav,
      navigatorObservers: [_routes],
      // The palette has already switched; switch the theme with it, at once,
      // so the two never disagree mid-animation.
      theme: AppColors.isDark ? _darkTheme : _lightTheme,
      themeAnimationDuration: Duration.zero,
      builder: (context, child) {
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: frankSystemBars(),
          child: PresenceScope(
            engine: _presence,
            child: _CalmMotion(
              enabled: _settings.reduceMotion,
              child: ColoredBox(
                color: AppColors.background,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ?child,
                    EdgeGlowLayer(engine: _presence),
                    if (_covered) const _SwitcherCover(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      home: _StageSwitcher(
        stageKey: stage == _Stage.chat ? 'chat_$_connectionGen' : stage.name,
        leavesInstantly: stage == _Stage.chat,
        reduceMotion: _settings.reduceMotion,
        child: _stageChild(stage),
      ),
    );
  }

  Widget _stageChild(_Stage stage) {
    switch (stage) {
      case _Stage.loading:
        return Scaffold(backgroundColor: AppColors.background);
      case _Stage.changePin:
        return SetPinScreen(
          title: 'Change PIN',
          onCancel: () => setState(() => _changingPin = false),
          onSaved: _savePin,
          enableHaptics: _settings.haptics,
          reduceMotion: _settings.reduceMotion,
        );
      case _Stage.createPin:
        return SetPinScreen(
          onSaved: _savePin,
          enableHaptics: _settings.haptics,
          reduceMotion: _settings.reduceMotion,
        );
      case _Stage.locked:
        return PinScreen(
          pin: _pin!,
          lockout: _lockout,
          onLockout: (lockout) {
            _lockout = lockout;
            unawaited(_vault.saveLockout(lockout));
          },
          onUnlocked: _unlock,
          biometric: _biometric,
          enableHaptics: _settings.haptics,
          reduceMotion: _settings.reduceMotion,
        );
      case _Stage.chat:
        // Built only after unlock, so nothing private renders behind the lock.
        return ChatScreen(
          key: ValueKey('chat_$_connectionGen'),
          controller: _controller(),
          onLock: _lock,
          onChangePin: () => setState(() => _changingPin = true),
          onSettings: _openSettings,
          brief: _brief,
        );
    }
  }

  ChatController _controller() {
    final existing = _chat;
    if (existing != null) {
      return existing;
    }
    final chat = widget.chatBuilder?.call(_config) ??
        ChatController(
          config: _config,
          client: HermesClient(
            baseUrl: _config.baseUrl,
            apiKey: _config.apiKey,
          ),
          haptics: _haptics,
          settings: _settings,
          onDeviceVoice: _onDeviceVoice,
        );
    _chat = chat;
    chat.addListener(_onChat);
    _followChatSoon();
    return chat;
  }

  var _wasInCall = false;

  /// A call that ends while Frank is away starts the lock's clock then, so
  /// Frank is not left open after a call that ended in your pocket.
  void _onChat() {
    final inCall = _chat?.inCall ?? false;
    if (_wasInCall && !inCall) {
      final state = WidgetsBinding.instance.lifecycleState;
      if (state != null && state != AppLifecycleState.resumed) {
        _backgroundedAt = DateTime.now();
      }
    }
    _wasInCall = inCall;
  }

  /// Point the glow at the current chat once this frame is built (attaching
  /// may repaint, which must not happen mid-build).
  void _followChatSoon() {
    // Asks for notification permission after the first unlock, not over the
    // lock screen.
    widget.push?.start();
    widget.push?.catchUp();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chat = _chat;
      if (mounted && chat != null && _unlocked) {
        _presence.attach(chat);
      }
      _onPush();
      _openPendingBrief();
    });
  }

  /// Opens the message a tapped notification points at, once Frank is
  /// unlocked (a tap while locked waits for the unlock).
  void _onPush() {
    final push = widget.push;
    if (!_readyToOpen || push == null || push.pendingOpen == null) {
      return;
    }
    final id = push.takePendingOpen()!;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final record = await push.relayRecordFor(id);
      final context = _nav.currentContext;
      if (record != null && context != null && context.mounted) {
        await showDeliveryReader(
          context,
          record,
          onReply: (record) => _chat?.replyTo(record),
        );
      }
    });
  }

  Future<void> _openSettings() async {
    await _nav.currentState?.push(
      MaterialPageRoute<void>(
        builder: (context) => SettingsScreen(
          settings: _settings,
          connection: _connection,
          chat: _chat,
          push: widget.push,
          voiceModels: widget.voiceModels,
          onDeviceVoice: _onDeviceVoice,
          onChangePin: () => setState(() => _changingPin = true),
          onLock: _lock,
          onConnectionSaved: _applyConnection,
        ),
      ),
    );
  }

  Future<void> _applyConnection(AppConfig next) async {
    _presence.detach();
    _chat?.dispose();
    _chat = null;
    if (!mounted) {
      return;
    }
    setState(() => _connectionGen++);
  }

  Future<void> _savePin(String pin) async {
    final creating = _pin == null;
    if (!creating && !_unlocked) {
      // A lock arrived while Change PIN was open: never accept a new PIN
      // (or unlock) without the old one.
      return;
    }
    final stored = await _vault.write(pin);
    if (!mounted) {
      return;
    }
    setState(() {
      _pin = stored;
      _changingPin = false;
      // Only the first PIN unlocks; changing it keeps the current state.
      if (creating) {
        _unlocked = true;
      }
    });
    if (creating) {
      _presence.event(PresenceEvent.unlock);
      _followChatSoon();
      if (!_config.looksConfigured) {
        // First run: straight to connecting Hermes (scan or type).
        WidgetsBinding.instance.addPostFrameCallback((_) => _connectHermes());
      }
    }
  }

  Future<void> _connectHermes() async {
    await _nav.currentState?.push(
      MaterialPageRoute<void>(
        builder: (context) => ServerSettingsScreen(
          initial: _config,
          onSave: (next) async {
            await _connection.save(next);
            await _applyConnection(next);
          },
        ),
      ),
    );
  }

  void _unlock() {
    // The lock screen already played the success haptic.
    setState(() => _unlocked = true);
    _presence.event(PresenceEvent.unlock);
    _followChatSoon();
  }

  void _lock() {
    _haptics.lock();
    _presence
      ..detach()
      ..silence();
    _dropRoutesAtOnce();
    setState(() {
      _unlocked = false;
      _changingPin = false;
    });
  }

  /// Removes every sheet, dialog and page above home without an exit
  /// animation, so no message preview or reader lingers over the lock.
  void _dropRoutesAtOnce() {
    final nav = _nav.currentState;
    if (nav == null) {
      return;
    }
    for (final route in _routes.routes.reversed.toList()) {
      if (!route.isFirst && route.isActive) {
        nav.removeRoute(route);
      }
    }
  }
}

/// Keeps the navigator's live routes in order, so locking can remove them
/// without animating them out over the lock screen.
class _RouteLog extends NavigatorObserver {
  final routes = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.remove(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.remove(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : routes.indexOf(oldRoute);
    if (newRoute == null) {
      if (index >= 0) {
        routes.removeAt(index);
      }
    } else if (index >= 0) {
      routes[index] = newRoute;
    } else {
      routes.add(newRoute);
    }
  }
}

/// Moves between loading, PIN setup, the lock and the chat.
///
/// Unlocking: the lock screen leans gently forward (1 → 1.06) and fades
/// while the chat fades in and rises 8dp, under the gold welcome glow.
/// Locking: the chat leaves instantly, so its content never lingers behind
/// the arriving lock. Reduce motion: a short crossfade.
class _StageSwitcher extends StatelessWidget {
  const _StageSwitcher({
    required this.stageKey,
    required this.leavesInstantly,
    required this.reduceMotion,
    required this.child,
  });

  final String stageKey;

  /// The incoming stage disappears without a transition when replaced.
  final bool leavesInstantly;
  final bool reduceMotion;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final calm = reduceMotion || AppMotion.reduced(context);
    return ColoredBox(
      color: AppColors.background,
      child: AnimatedSwitcher(
        duration: calm ? AppMotion.short : const Duration(milliseconds: 560),
        reverseDuration: leavesInstantly
            ? Duration.zero
            : calm
                ? AppMotion.short
                : const Duration(milliseconds: 380),
        // One widget shape for both motion modes: toggling Reduce motion
        // swaps the transition in place instead of rebuilding the chat.
        transitionBuilder: (child, animation) =>
            _StageTransition(animation: animation, calm: calm, child: child),
        child: KeyedSubtree(key: ValueKey(stageKey), child: child),
      ),
    );
  }
}

/// The chat fades in and rises 8dp (after a short delay, so the lock's
/// lean-out leads); lock and PIN screens lean from 1.06 and fade. Calm:
/// a plain crossfade.
class _StageTransition extends StatelessWidget {
  const _StageTransition({
    required this.animation,
    required this.calm,
    required this.child,
  });

  final Animation<double> animation;
  final bool calm;
  final Widget child;

  static const _rise = Interval(0.3, 1, curve: AppMotion.enter);

  @override
  Widget build(BuildContext context) {
    final key = child.key;
    final chat = key is ValueKey<String> && key.value.startsWith('chat');
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = animation.value;
        double opacity;
        Matrix4 transform;
        if (calm) {
          opacity = t;
          transform = Matrix4.identity();
        } else if (chat) {
          final rise = _rise.transform(t);
          opacity = rise;
          transform = Matrix4.translationValues(0, 8 * (1 - rise), 0);
        } else {
          final leaving = animation.status == AnimationStatus.reverse;
          final lean = leaving
              ? Curves.easeInCubic.transform(t)
              : AppMotion.enter.transform(t);
          opacity = lean.clamp(0.0, 1.0);
          final scale = 1.06 + (1 - 1.06) * lean;
          transform = Matrix4.diagonal3Values(scale, scale, 1);
        }
        return Opacity(
          opacity: opacity,
          child: Transform(
            transform: transform,
            alignment: Alignment.center,
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// The in-app Reduce motion setting, applied to every route, sheet and
/// dialog the same way the OS "remove animations" switch is, so every
/// `AppMotion.reduced(context)` check below follows it.
class _CalmMotion extends StatelessWidget {
  const _CalmMotion({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Always the same shape, so toggling the setting never rebuilds the
    // navigator (and the open chat) from scratch.
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: enabled && !media.disableAnimations
          ? media.copyWith(disableAnimations: true)
          : media,
      child: child,
    );
  }
}

/// What the iOS app switcher sees while "Hide in app switcher" is on: the
/// canvas and a still orb, nothing from the conversation.
class _SwitcherCover extends StatelessWidget {
  const _SwitcherCover();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: const Center(child: FrankOrb(size: 72)),
    );
  }
}
