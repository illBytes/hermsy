import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_app/services/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('defaults to haptics and a one-minute auto-lock', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings(preferences: await SharedPreferences.getInstance());
    await settings.load();

    expect(settings.haptics, isTrue);
    expect(settings.speakReplies, isFalse);
    expect(settings.autoLock, isTrue);
    expect(settings.autoLockAfter, const Duration(minutes: 1));
    expect(settings.presence, PresenceStyle.aura);
    expect(settings.glowIntensity, GlowIntensity.balanced);
    expect(settings.glowGain, 1.0);
    expect(settings.reduceMotion, isFalse);
    expect(settings.hideInSwitcher, isFalse);
    expect(AppSettings.labelFor(Duration.zero), 'Immediately');
    expect(AppSettings.labelFor(const Duration(minutes: 1)), '1 minute');
  });

  test('persists haptics and lock delay', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = AppSettings(preferences: prefs);
    await settings.load();
    await settings.setHaptics(false);
    await settings.setSpeakReplies(true);
    await settings.setAutoLockAfter(Duration.zero);
    await settings.setPresence(PresenceStyle.off);
    await settings.setGlowIntensity(GlowIntensity.vivid);
    await settings.setReduceMotion(true);
    await settings.setHideInSwitcher(true);

    final again = AppSettings(preferences: prefs);
    await again.load();
    expect(again.haptics, isFalse);
    expect(again.speakReplies, isTrue);
    expect(again.autoLockAfter, Duration.zero);
    expect(again.presence, PresenceStyle.off);
    expect(again.glowIntensity, GlowIntensity.vivid);
    expect(again.glowGain, greaterThan(1.0));
    expect(again.reduceMotion, isTrue);
    expect(again.hideInSwitcher, isTrue);
  });

  test('an earlier saved style survives the new Aura default', () async {
    SharedPreferences.setMockInitialValues({AppSettings.presenceKey: 'ribbon'});
    final settings = AppSettings(preferences: await SharedPreferences.getInstance());
    await settings.load();
    expect(settings.presence, PresenceStyle.ribbon);
  });

  test('presence labels cover every style', () {
    expect(AppSettings.presenceLabel(PresenceStyle.off), 'Off');
    expect(AppSettings.presenceFrom('twin'), PresenceStyle.twin);
    expect(AppSettings.presenceFrom('nope'), PresenceStyle.aura);
    expect(AppSettings.presenceFrom(null), PresenceStyle.aura);
    for (final style in PresenceStyle.values) {
      expect(AppSettings.presenceLabel(style), isNotEmpty);
      expect(AppSettings.presenceSubtitle(style), isNotEmpty);
      expect(AppSettings.presenceOrder, contains(style));
    }
    expect(AppSettings.presenceLabel(PresenceStyle.aura), 'Aura');
    expect(AppSettings.glowIntensityFrom('subtle'), GlowIntensity.subtle);
    expect(AppSettings.glowIntensityFrom('nope'), GlowIntensity.balanced);
  });
}
