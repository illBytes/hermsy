import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/brief.dart';

/// Edge-glow styles. Names are persisted, so only ever append.
enum PresenceStyle { off, ribbon, veil, pulse, twin, aura }

/// How bright Frank's edge glow is.
enum GlowIntensity { subtle, balanced, vivid }

class AppSettings extends ChangeNotifier {
  AppSettings({this._preferences});

  SharedPreferences? _preferences;

  bool haptics = true;
  bool speakReplies = false;
  bool autoLock = true;
  Duration autoLockAfter = const Duration(minutes: 1);
  PresenceStyle presence = PresenceStyle.aura;
  GlowIntensity glowIntensity = GlowIntensity.balanced;
  bool reduceMotion = false;
  bool hideInSwitcher = false;

  /// Voice models (about 800 MB) download only on Wi-Fi unless turned off.
  bool voiceModelsWifiOnly = true;

  /// Kokoro speaker id for Frank's voice in calls (3 is Heart).
  int callVoice = 3;

  /// How fast Frank talks in calls.
  double callSpeed = 1.0;

  static const callSpeeds = <double>[0.9, 1.0, 1.1, 1.2];

  /// Speak with Kokoro at full precision (an extra download) instead of
  /// the compressed build.
  bool kokoroFull = false;

  /// How long you can pause mid-thought in a call before Frank answers, in
  /// seconds (on top of the short silence that ends a stretch of speech).
  double callPause = 1.0;

  static final callPauses = <double, String>{
    0.4: 'Short',
    1.0: 'Normal',
    2.0: 'Long',
  };

  /// Who speaks in calls: a cloud provider the relay has a key for
  /// (`openai`, `elevenlabs`), or `kokoro` on this phone. Cloud by default:
  /// it sounds best and renders faster than the phone can.
  String callEngine = 'openai';

  /// The Brief's sections in the order you put them, and those you hid.
  List<String> briefOrder = List.of(briefSectionIds);
  Set<String> briefHidden = {};

  /// What the home-screen widget shows. Money is off by default: the
  /// widget sits on the home screen, outside Frank's lock.
  Set<String> widgetSections = {...defaultWidgetSections};
  bool widgetHeadline = true;
  bool widgetSuggestions = true;

  static const defaultWidgetSections = {'today', 'due', 'coming_up'};

  List<String> get briefShown =>
      [for (final id in briefOrder) if (!briefHidden.contains(id)) id];

  /// When the cloud voice fails (no connection, no credit), finish the call
  /// in Kokoro's voice instead of going quiet.
  bool callFallback = true;

  /// The chosen voice per cloud provider, and its name for display.
  final Map<String, String> _cloudVoices = {};
  final Map<String, String> _cloudVoiceNames = {};

  static const cloudVoiceDefaults = {'openai': 'marin'};

  String? cloudVoice(String provider) =>
      _cloudVoices[provider] ?? cloudVoiceDefaults[provider];

  String? cloudVoiceName(String provider) =>
      _cloudVoiceNames[provider] ??
      (provider == 'openai' && _cloudVoices[provider] == null ? 'Marin' : null);

  static const hapticsKey = 'frank.haptics';
  static const speakRepliesKey = 'frank.speak_replies';
  static const autoLockKey = 'frank.auto_lock';
  static const autoLockAfterKey = 'frank.auto_lock_after_sec';
  static const presenceKey = 'frank.presence_style';
  static const glowIntensityKey = 'frank.glow_intensity';
  static const reduceMotionKey = 'frank.reduce_motion';
  static const hideInSwitcherKey = 'frank.hide_in_switcher';
  static const voiceModelsWifiOnlyKey = 'frank.voice_models_wifi_only';
  static const callVoiceKey = 'frank.call_voice';
  static const callSpeedKey = 'frank.call_speed';
  static const callPauseKey = 'frank.call_pause';
  static const kokoroFullKey = 'frank.kokoro_full';
  static const callEngineKey = 'frank.call_engine';
  static const callFallbackKey = 'frank.call_fallback';
  static const briefOrderKey = 'frank.brief_order';
  static const briefHiddenKey = 'frank.brief_hidden';
  static const widgetSectionsKey = 'frank.widget_sections';
  static const widgetHeadlineKey = 'frank.widget_headline';
  static const widgetSuggestionsKey = 'frank.widget_suggestions';
  static const cloudVoiceKeyPrefix = 'frank.cloud_voice.';

  /// Picker order: the signature style first, off last.
  static const presenceOrder = <PresenceStyle>[
    PresenceStyle.aura,
    PresenceStyle.ribbon,
    PresenceStyle.twin,
    PresenceStyle.veil,
    PresenceStyle.pulse,
    PresenceStyle.off,
  ];

  static const lockDelays = <Duration>[
    Duration.zero,
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 5),
  ];

  Future<void> load() async {
    _preferences ??= await SharedPreferences.getInstance();
    haptics = _preferences!.getBool(hapticsKey) ?? true;
    speakReplies = _preferences!.getBool(speakRepliesKey) ?? false;
    autoLock = _preferences!.getBool(autoLockKey) ?? true;
    final seconds = _preferences!.getInt(autoLockAfterKey);
    if (seconds != null) {
      autoLockAfter = Duration(seconds: seconds);
    }
    presence = presenceFrom(_preferences!.getString(presenceKey));
    glowIntensity = glowIntensityFrom(_preferences!.getString(glowIntensityKey));
    reduceMotion = _preferences!.getBool(reduceMotionKey) ?? false;
    hideInSwitcher = _preferences!.getBool(hideInSwitcherKey) ?? false;
    voiceModelsWifiOnly =
        _preferences!.getBool(voiceModelsWifiOnlyKey) ?? true;
    callVoice = _preferences!.getInt(callVoiceKey) ?? 3;
    callSpeed = _preferences!.getDouble(callSpeedKey) ?? 1.0;
    callPause = _preferences!.getDouble(callPauseKey) ?? 1.0;
    kokoroFull = _preferences!.getBool(kokoroFullKey) ?? false;
    callEngine = _preferences!.getString(callEngineKey) ?? 'openai';
    callFallback = _preferences!.getBool(callFallbackKey) ?? true;
    final order = _preferences!.getStringList(briefOrderKey) ?? const [];
    briefOrder = [
      for (final id in order)
        if (briefSectionIds.contains(id)) id,
      // Sections added in a later version join at the end.
      for (final id in briefSectionIds)
        if (!order.contains(id)) id,
    ];
    briefHidden = {...?_preferences!.getStringList(briefHiddenKey)};
    widgetSections = {
      ...(_preferences!.getStringList(widgetSectionsKey) ??
          defaultWidgetSections),
    };
    widgetHeadline = _preferences!.getBool(widgetHeadlineKey) ?? true;
    widgetSuggestions = _preferences!.getBool(widgetSuggestionsKey) ?? true;
    for (final provider in const ['openai', 'elevenlabs']) {
      final voice = _preferences!.getString('$cloudVoiceKeyPrefix$provider');
      if (voice != null) {
        _cloudVoices[provider] = voice;
      }
      final name = _preferences!.getString(
        '${cloudVoiceKeyPrefix}name.$provider',
      );
      if (name != null) {
        _cloudVoiceNames[provider] = name;
      }
    }
    notifyListeners();
  }

  /// Multiplier the edge glow applies to its brightness.
  double get glowGain {
    switch (glowIntensity) {
      case GlowIntensity.subtle:
        return 0.6;
      case GlowIntensity.balanced:
        return 1.0;
      case GlowIntensity.vivid:
        return 1.35;
    }
  }

  Future<void> setGlowIntensity(GlowIntensity value) async {
    glowIntensity = value;
    notifyListeners();
    await _preferences?.setString(glowIntensityKey, value.name);
  }

  Future<void> setReduceMotion(bool value) async {
    reduceMotion = value;
    notifyListeners();
    await _preferences?.setBool(reduceMotionKey, value);
  }

  Future<void> setVoiceModelsWifiOnly(bool value) async {
    voiceModelsWifiOnly = value;
    notifyListeners();
    await _preferences?.setBool(voiceModelsWifiOnlyKey, value);
  }

  Future<void> setCallVoice(int value) async {
    callVoice = value;
    notifyListeners();
    await _preferences?.setInt(callVoiceKey, value);
  }

  Future<void> setCallEngine(String value) async {
    callEngine = value;
    notifyListeners();
    await _preferences?.setString(callEngineKey, value);
  }

  Future<void> setWidgetSection(String id, bool shown) async {
    shown ? widgetSections.add(id) : widgetSections.remove(id);
    notifyListeners();
    await _preferences?.setStringList(
      widgetSectionsKey,
      widgetSections.toList(),
    );
  }

  Future<void> setWidgetHeadline(bool value) async {
    widgetHeadline = value;
    notifyListeners();
    await _preferences?.setBool(widgetHeadlineKey, value);
  }

  Future<void> setWidgetSuggestions(bool value) async {
    widgetSuggestions = value;
    notifyListeners();
    await _preferences?.setBool(widgetSuggestionsKey, value);
  }

  Future<void> setBriefOrder(List<String> order) async {
    briefOrder = List.of(order);
    notifyListeners();
    await _preferences?.setStringList(briefOrderKey, briefOrder);
  }

  Future<void> setBriefShown(String id, bool shown) async {
    shown ? briefHidden.remove(id) : briefHidden.add(id);
    notifyListeners();
    await _preferences?.setStringList(briefHiddenKey, briefHidden.toList());
  }

  Future<void> setCallFallback(bool value) async {
    callFallback = value;
    notifyListeners();
    await _preferences?.setBool(callFallbackKey, value);
  }

  Future<void> setCloudVoice(
    String provider,
    String voice, {
    required String name,
  }) async {
    _cloudVoices[provider] = voice;
    _cloudVoiceNames[provider] = name;
    notifyListeners();
    await _preferences?.setString('$cloudVoiceKeyPrefix$provider', voice);
    await _preferences?.setString('${cloudVoiceKeyPrefix}name.$provider', name);
  }

  Future<void> setCallSpeed(double value) async {
    callSpeed = value;
    notifyListeners();
    await _preferences?.setDouble(callSpeedKey, value);
  }

  Future<void> setKokoroFull(bool value) async {
    kokoroFull = value;
    notifyListeners();
    await _preferences?.setBool(kokoroFullKey, value);
  }

  Future<void> setCallPause(double value) async {
    callPause = value;
    notifyListeners();
    await _preferences?.setDouble(callPauseKey, value);
  }

  Future<void> setHideInSwitcher(bool value) async {
    hideInSwitcher = value;
    notifyListeners();
    await _preferences?.setBool(hideInSwitcherKey, value);
  }

  Future<void> setPresence(PresenceStyle value) async {
    presence = value;
    notifyListeners();
    await _preferences?.setString(presenceKey, value.name);
  }

  Future<void> setHaptics(bool value) async {
    haptics = value;
    notifyListeners();
    await _preferences?.setBool(hapticsKey, value);
  }

  Future<void> setSpeakReplies(bool value) async {
    speakReplies = value;
    notifyListeners();
    await _preferences?.setBool(speakRepliesKey, value);
  }

  Future<void> setAutoLock(bool value) async {
    autoLock = value;
    notifyListeners();
    await _preferences?.setBool(autoLockKey, value);
  }

  Future<void> setAutoLockAfter(Duration value) async {
    autoLockAfter = value;
    notifyListeners();
    await _preferences?.setInt(autoLockAfterKey, value.inSeconds);
  }

  static String labelFor(Duration delay) {
    if (delay == Duration.zero) {
      return 'Immediately';
    }
    if (delay.inSeconds < 60) {
      return '${delay.inSeconds} seconds';
    }
    if (delay.inMinutes == 1) {
      return '1 minute';
    }
    return '${delay.inMinutes} minutes';
  }

  static PresenceStyle presenceFrom(String? raw) {
    for (final style in PresenceStyle.values) {
      if (style.name == raw) {
        return style;
      }
    }
    return PresenceStyle.aura;
  }

  static GlowIntensity glowIntensityFrom(String? raw) {
    for (final value in GlowIntensity.values) {
      if (value.name == raw) {
        return value;
      }
    }
    return GlowIntensity.balanced;
  }

  static String glowIntensityLabel(GlowIntensity value) {
    switch (value) {
      case GlowIntensity.subtle:
        return 'Subtle';
      case GlowIntensity.balanced:
        return 'Balanced';
      case GlowIntensity.vivid:
        return 'Vivid';
    }
  }

  static String presenceLabel(PresenceStyle style) {
    switch (style) {
      case PresenceStyle.off:
        return 'Off';
      case PresenceStyle.ribbon:
        return 'Ribbon';
      case PresenceStyle.veil:
        return 'Veil';
      case PresenceStyle.pulse:
        return 'Pulse';
      case PresenceStyle.twin:
        return 'Twin';
      case PresenceStyle.aura:
        return 'Aura';
    }
  }

  static String presenceSubtitle(PresenceStyle style) {
    switch (style) {
      case PresenceStyle.off:
        return 'No edge light. The orb still shows what Hermsy is doing';
      case PresenceStyle.ribbon:
        return 'One comet of light circles the frame';
      case PresenceStyle.veil:
        return 'A steady ring of color, slowly turning';
      case PresenceStyle.pulse:
        return 'The frame breathes in place. The calmest option';
      case PresenceStyle.twin:
        return 'Two lights chase each other around the edge';
      case PresenceStyle.aura:
        return 'Living light flows around the screen and follows your voice';
    }
  }
}
