import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Frank's palette, in a dark and a light version.
///
/// The dark chrome is a quiet, cool-neutral black glass; the light one is
/// soft white glass on a cool off-white canvas. In both, color is reserved
/// for two things: Hermes gold for *you* and primary actions (send, PIN
/// dots, the current chat, primary buttons), and the aurora spectrum for
/// *Frank's* presence (edge glow, orb, live status). The light versions of
/// gold and the aurora are deeper so they read on white.
class FrankPalette {
  const FrankPalette({
    required this.brightness,
    required this.background,
    required this.glow,
    required this.sheet,
    required this.surface,
    required this.surfaceHigh,
    required this.surfacePressed,
    required this.userBubble,
    required this.codeBg,
    required this.hairline,
    required this.strokeStrong,
    required this.glassHighlight,
    required this.glass,
    required this.backdropGlow,
    required this.scrim,
    required this.text,
    required this.secondary,
    required this.hint,
    required this.disabled,
    required this.gold,
    required this.goldBright,
    required this.goldText,
    required this.goldDeep,
    required this.goldSoft,
    required this.onGold,
    required this.ion,
    required this.azure,
    required this.iris,
    required this.orchid,
    required this.rose,
    required this.solar,
    required this.whiteHot,
    required this.signal,
    required this.danger,
    required this.amber,
    required this.mint,
    required this.link,
    required this.statusListening,
    required this.statusTranscribing,
    required this.statusThinking,
    required this.statusSpeaking,
  });

  final Brightness brightness;
  final Color background;
  final Color glow;
  final Color sheet;
  final Color surface;
  final Color surfaceHigh;
  final Color surfacePressed;
  final Color userBubble;
  final Color codeBg;
  final Color hairline;
  final Color strokeStrong;
  final Color glassHighlight;
  final Color glass;
  final Color backdropGlow;
  final Color scrim;
  final Color text;
  final Color secondary;
  final Color hint;
  final Color disabled;
  final Color gold;
  final Color goldBright;
  final Color goldText;
  final Color goldDeep;
  final Color goldSoft;
  final Color onGold;
  final Color ion;
  final Color azure;
  final Color iris;
  final Color orchid;
  final Color rose;
  final Color solar;
  final Color whiteHot;
  final Color signal;
  final Color danger;
  final Color amber;
  final Color mint;
  final Color link;
  final Color statusListening;
  final Color statusTranscribing;
  final Color statusThinking;
  final Color statusSpeaking;

  static const dark = FrankPalette(
    brightness: Brightness.dark,
    background: Color(0xFF05060A),
    glow: Color(0xFF0A0C12),
    sheet: Color(0xFF0C0E14),
    surface: Color(0xFF0E1118),
    surfaceHigh: Color(0xFF151924),
    surfacePressed: Color(0xFF1C2130),
    userBubble: Color(0xFF171B24),
    codeBg: Color(0xFF0B0D13),
    hairline: Color(0x14FFFFFF),
    strokeStrong: Color(0x24FFFFFF),
    glassHighlight: Color(0x1AFFFFFF),
    glass: Color(0xB80E1118),
    backdropGlow: Color(0xFF101833),
    scrim: Color(0x99000000),
    text: Color(0xFFECEFF6),
    secondary: Color(0xFFA3AABB),
    hint: Color(0xFF7C8497),
    disabled: Color(0xFF4A5060),
    gold: Color(0xFFE6B54A),
    goldBright: Color(0xFFF7D77A),
    goldText: Color(0xFFF7D77A),
    goldDeep: Color(0xFFC8952F),
    goldSoft: Color(0x24E6B54A),
    onGold: Color(0xFF1A1206),
    ion: Color(0xFF3DF2E0),
    azure: Color(0xFF3B82FF),
    iris: Color(0xFF7C5CFF),
    orchid: Color(0xFFC86BFF),
    rose: Color(0xFFFF6B9A),
    solar: Color(0xFFFFB86B),
    whiteHot: Color(0xFFF2F7FF),
    signal: Color(0xFFFF5A6A),
    danger: Color(0xFFFF8A8A),
    amber: Color(0xFFFFB547),
    mint: Color(0xFF4BE3A0),
    link: Color(0xFF8FB4FF),
    statusListening: Color(0xFF3DF2E0),
    statusTranscribing: Color(0xFF6FB7FF),
    statusThinking: Color(0xFFB59CFF),
    statusSpeaking: Color(0xFFFF9F7A),
  );

  static const light = FrankPalette(
    brightness: Brightness.light,
    background: Color(0xFFF4F5F9),
    glow: Color(0xFFFFFFFF),
    sheet: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFEEF0F5),
    surfacePressed: Color(0xFFE3E6ED),
    userBubble: Color(0xFFE8EAF0),
    codeBg: Color(0xFFF1F2F6),
    hairline: Color(0x17000000),
    strokeStrong: Color(0x26000000),
    glassHighlight: Color(0xB3FFFFFF),
    glass: Color(0xD1FFFFFF),
    backdropGlow: Color(0xFFFFFFFF),
    scrim: Color(0x52000000),
    text: Color(0xFF14161C),
    secondary: Color(0xFF4D5465),
    hint: Color(0xFF687083),
    disabled: Color(0xFFB2B7C2),
    gold: Color(0xFFB8841C),
    goldBright: Color(0xFFE9B949),
    goldText: Color(0xFF8A5A08),
    goldDeep: Color(0xFF9A650A),
    goldSoft: Color(0x2BC8952F),
    onGold: Color(0xFF1A1206),
    ion: Color(0xFF0E9E92),
    azure: Color(0xFF2563EB),
    iris: Color(0xFF6A47F0),
    orchid: Color(0xFFA347E8),
    rose: Color(0xFFE0336F),
    solar: Color(0xFFE5791F),
    whiteHot: Color(0xFFFFE9B8),
    signal: Color(0xFFE5484D),
    danger: Color(0xFFC2353B),
    amber: Color(0xFFB86A00),
    mint: Color(0xFF0F8F5A),
    link: Color(0xFF2F6BDE),
    statusListening: Color(0xFF0E9E92),
    statusTranscribing: Color(0xFF2F7DD8),
    statusThinking: Color(0xFF7354DB),
    statusSpeaking: Color(0xFFD5622F),
  );
}

/// The colors in use: the dark or light [FrankPalette], following the
/// system. Read them while building or painting, never into a `static final`
/// or a cached field: [use] swaps the palette and the app rebuilds and
/// repaints everything in place (see `RepaintOnTheme`).
class AppColors {
  static FrankPalette _palette = FrankPalette.dark;

  static FrankPalette get palette => _palette;
  static bool get isDark => _palette.brightness == Brightness.dark;

  /// Switches the palette. Returns true when it changed.
  static bool use(Brightness brightness) {
    final next = brightness == Brightness.light
        ? FrankPalette.light
        : FrankPalette.dark;
    if (identical(next, _palette)) {
      return false;
    }
    _palette = next;
    return true;
  }

  // Canvas and surfaces (OLED; never pure #000 to avoid black smear).
  static Color get background => _palette.background;
  // raised canvas: drawer, sheets
  static Color get glow => _palette.glow;
  // solid: nothing ghosts through
  static Color get sheet => _palette.sheet;
  // groups, fields, cards
  static Color get surface => _palette.surface;
  // menus, chips, pressed rows
  static Color get surfaceHigh => _palette.surfaceHigh;
  static Color get surfacePressed => _palette.surfacePressed;
  static Color get userBubble => _palette.userBubble;
  static Color get codeBg => _palette.codeBg;
  // Strokes. Light edges instead of shadows on near-black.
  static Color get hairline => _palette.hairline;
  static Color get strokeStrong => _palette.strokeStrong;
  static Color get glassHighlight => _palette.glassHighlight;
  // Frosted panels (composer, header).
  static Color get glass => _palette.glass;
  // The soft light falling from above the top edge of every screen.
  static Color get backdropGlow => _palette.backdropGlow;
  // Behind dialogs, sheets and the drawer.
  static Color get scrim => _palette.scrim;

  /// How light is laid down: added onto the dark canvas, but on a light one
  /// adding does nothing visible, so there it goes over as a tint.
  static BlendMode get glowBlend =>
      isDark ? BlendMode.plus : BlendMode.srcOver;

  /// A faint wash over whatever is behind: white on dark, black on light.
  /// [alpha] is the dark-mode opacity (0-255); light mode is a touch lighter
  /// because black on white reads stronger.
  static Color veil(int alpha) => isDark
      ? Color.fromARGB(alpha, 255, 255, 255)
      : Color.fromARGB((alpha * 0.8).round(), 0, 0, 0);
  // Text.
  static Color get text => _palette.text;
  static Color get secondary => _palette.secondary;
  // Tertiary text. The floor: at least 4.5:1 on the canvas and on raised
  // fills (surface, surfaceHigh, the user bubble, the drawer's current row).
  static Color get hint => _palette.hint;
  static Color get disabled => _palette.disabled;
  // Hermes gold: you, primary actions, selection.
  static Color get gold => _palette.gold;
  static Color get goldBright => _palette.goldBright;
  // Gold for words: bright on dark, deep enough to read on light.
  static Color get goldText => _palette.goldText;
  static Color get goldDeep => _palette.goldDeep;
  static Color get goldSoft => _palette.goldSoft;
  static Color get onGold => _palette.onGold;
  // Aurora spectrum: Frank's presence only.
  static Color get ion => _palette.ion;
  static Color get azure => _palette.azure;
  static Color get iris => _palette.iris;
  static Color get orchid => _palette.orchid;
  static Color get rose => _palette.rose;
  static Color get solar => _palette.solar;
  static Color get whiteHot => _palette.whiteHot;
  // Semantic.
  // error glow, borders
  static Color get signal => _palette.signal;
  // error copy (AA on canvas)
  static Color get danger => _palette.danger;
  // offline, reconnecting
  static Color get amber => _palette.amber;
  // connected
  static Color get mint => _palette.mint;
  static Color get link => _palette.link;
  // Status line colors by mood (header, drawer, presence preview chips).
  static Color get statusListening => _palette.statusListening;
  // also tools
  static Color get statusTranscribing => _palette.statusTranscribing;
  static Color get statusThinking => _palette.statusThinking;
  static Color get statusSpeaking => _palette.statusSpeaking;
}

/// Gradients. Gold is the only gradient on controls; the aurora gradients are
/// for Frank's presence (glow, orb, caret, live accents).
class AppGradients {
  static LinearGradient get gold => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.goldBright, AppColors.gold, AppColors.goldDeep],
    stops: const [0, 0.55, 1],
  );

  static LinearGradient get aurora => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.ion, AppColors.azure, AppColors.iris, AppColors.orchid],
    stops: const [0, 0.38, 0.72, 1],
  );

  static LinearGradient get auroraVertical => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [AppColors.ion, AppColors.azure, AppColors.iris],
  );
}

/// Four cyclic stops per state, shared by the edge glow and the orb so the
/// face and the aura always read as one organism.
/// Glow palettes per state. Each is one list per light/dark, kept for the
/// life of the app: the glow fades only when the list it is given changes.
class AppSpectrum {
  static final _dark = _Spectrum(FrankPalette.dark);
  static final _light = _Spectrum(FrankPalette.light);
  static _Spectrum get _now => AppColors.isDark ? _dark : _light;

  static List<Color> get listening => _now.listening;
  static List<Color> get transcribing => _now.transcribing;
  static List<Color> get thinking => _now.thinking;
  static List<Color> get tool => _now.tool;
  static List<Color> get responding => _now.responding;
  static List<Color> get speaking => _now.speaking;
  static List<Color> get reconnecting => _now.reconnecting;
  static List<Color> get error => _now.error;

  /// The unlock / welcome sweep: Hermes gold.
  static List<Color> get welcome => _now.welcome;
  static List<Color> get idle => _now.idle;
}

class _Spectrum {
  _Spectrum(FrankPalette p)
    : listening = List.unmodifiable([p.ion, p.azure, p.iris, p.orchid]),
      transcribing = List.unmodifiable([p.azure, p.iris, p.ion, p.iris]),
      thinking = List.unmodifiable([
        p.iris,
        p.orchid,
        p.azure,
        const Color(0xFF9D7BFF),
      ]),
      tool = List.unmodifiable([
        p.azure,
        p.ion,
        // A white-hot core on dark; on light, white would vanish.
        p.brightness == Brightness.dark
            ? const Color(0xFFE8FFFF)
            : const Color(0xFF38BDF8),
        p.ion,
      ]),
      responding = List.unmodifiable([p.ion, p.azure, p.iris, p.orchid]),
      speaking = List.unmodifiable([p.orchid, p.rose, p.solar, p.rose]),
      reconnecting = List.unmodifiable(const [
        Color(0xFF5A6275),
        Color(0xFF8B93A7),
        Color(0xFF5A6275),
        Color(0xFF8B93A7),
      ]),
      error = List.unmodifiable([
        p.signal,
        const Color(0xFFFF8A5B),
        p.signal,
        const Color(0xFFC8436B),
      ]),
      welcome = List.unmodifiable([
        p.goldBright,
        p.solar,
        p.whiteHot,
        p.gold,
      ]),
      idle = List.unmodifiable(const [
        Color(0xFF52C9C0),
        Color(0xFF4A7BD6),
        Color(0xFF6F5BD0),
        Color(0xFFA46CCB),
      ]);

  final List<Color> listening;
  final List<Color> transcribing;
  final List<Color> thinking;
  final List<Color> tool;
  final List<Color> responding;
  final List<Color> speaking;
  final List<Color> reconnecting;
  final List<Color> error;
  final List<Color> welcome;
  final List<Color> idle;
}

class AppRadii {
  static const xs = 6.0; // inline code, bubble tail
  static const sm = 10.0; // icon tiles
  static const md = 14.0; // fields, chips, code blocks
  static const lg = 20.0; // bubbles, groups, cards
  static const xl = 26.0; // composer capsule
  static const sheet = 28.0; // sheet top corners
  static const pill = 999.0;
}

/// 4pt grid.
class AppSpace {
  static const x0 = 2.0;
  static const x1 = 4.0;
  static const x2 = 8.0;
  static const x3 = 12.0;
  static const x4 = 16.0;
  static const x5 = 20.0;
  static const x6 = 24.0;
  static const x8 = 32.0;
  static const x10 = 40.0;
  static const x14 = 56.0;

  static const gutter = 16.0; // screen edge
  static const reading = 20.0; // assistant prose edge
  static const turnGap = 16.0; // between speakers
  static const groupGap = 4.0; // same speaker, close in time
  static const minTouch = 48.0;
}

class AppMotion {
  static const instant = Duration(milliseconds: 90);
  static const quick = Duration(milliseconds: 140);
  static const short = Duration(milliseconds: 200);
  static const medium = Duration(milliseconds: 280);
  static const long = Duration(milliseconds: 420);
  static const xl = Duration(milliseconds: 600);
  static const sequence = Duration(milliseconds: 980);
  static const unlock = Duration(milliseconds: 1100);

  static const standard = Cubic(0.2, 0.0, 0.0, 1.0);
  static const enter = Cubic(0.05, 0.7, 0.1, 1.0);
  static const exit = Cubic(0.3, 0.0, 0.8, 0.15);
  static const glowBloom = Cubic(0.16, 1.0, 0.3, 1.0);
  static const glowDrain = Cubic(0.7, 0.0, 0.84, 0.0);
  static const sweep = Cubic(0.4, 0.0, 0.2, 1.0);
  static const flight = Cubic(0.2, 0.8, 0.2, 1.0);

  /// Press feedback: a touch of overshoot.
  static const pressSpring = SpringDescription(
    mass: 1,
    stiffness: 520,
    damping: 30,
  );

  /// True when the OS asks for less motion.
  static bool reduced(BuildContext context) {
    return MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  }
}

/// Type scale on the platform font (Roboto / SF). Monospace is used for code
/// and numeric telemetry only.
class AppText {
  static const mono = 'monospace';
  static const monoFallback = [
    'Roboto Mono',
    'Menlo',
    'SF Mono',
    'Courier New',
    'monospace',
  ];

  static TextStyle get display => TextStyle(
    color: AppColors.text,
    fontSize: 30,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.6,
  );
  static TextStyle get largeTitle => TextStyle(
    color: AppColors.text,
    fontSize: 28,
    height: 1.21,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.5,
  );
  static TextStyle get title => TextStyle(
    color: AppColors.text,
    fontSize: 18,
    height: 1.33,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  );
  static TextStyle get headline => TextStyle(
    color: AppColors.text,
    fontSize: 17,
    height: 1.41,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  );

  /// Assistant prose: generous leading for reading.
  static TextStyle get body => TextStyle(
    color: AppColors.text,
    fontSize: 16,
    height: 1.55,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.05,
  );
  static TextStyle get bodyUser => TextStyle(
    color: AppColors.isDark ? const Color(0xFFF2F4F8) : AppColors.text,
    fontSize: 15.5,
    height: 1.42,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.05,
  );
  static TextStyle get bodySmall => TextStyle(
    color: AppColors.secondary,
    fontSize: 14,
    height: 1.43,
    fontWeight: FontWeight.w400,
  );
  static TextStyle get label => TextStyle(
    color: AppColors.text,
    fontSize: 15,
    height: 1.33,
    fontWeight: FontWeight.w500,
  );
  static TextStyle get caption => TextStyle(
    color: AppColors.secondary,
    fontSize: 12.5,
    height: 1.28,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
  );

  /// Section labels, day separators, chips. Pass UPPERCASE text.
  static TextStyle get micro => TextStyle(
    color: AppColors.hint,
    fontSize: 11,
    height: 1.27,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.1,
  );

  static TextStyle get code => TextStyle(
    color: AppColors.isDark ? const Color(0xFFDDE3F0) : const Color(0xFF1F2430),
    fontSize: 13,
    height: 1.54,
    letterSpacing: 0,
    fontFamily: mono,
    fontFamilyFallback: monoFallback,
  );

  /// Timers, counts, match labels.
  static TextStyle get tabular => TextStyle(
    color: AppColors.secondary,
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

/// Transparent system bars, with icons that read on the current palette:
/// Frank draws edge to edge, under the status bar and the gesture handle.
SystemUiOverlayStyle frankSystemBars() {
  final dark = AppColors.isDark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    statusBarBrightness: dark ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: dark
        ? Brightness.light
        : Brightness.dark,
    systemNavigationBarContrastEnforced: false,
  );
}

/// Frank's Material theme for [brightness], built from that palette.
ThemeData buildAppTheme([Brightness brightness = Brightness.dark]) {
  final previous = AppColors.palette.brightness;
  AppColors.use(brightness);
  try {
    return _buildTheme();
  } finally {
    AppColors.use(previous);
  }
}

ThemeData _buildTheme() {
  final dark = AppColors.isDark;
  final scheme = ColorScheme(
    brightness: AppColors.palette.brightness,
    primary: AppColors.gold,
    onPrimary: AppColors.onGold,
    secondary: AppColors.ion,
    onSecondary: AppColors.background,
    surface: AppColors.surface,
    onSurface: AppColors.text,
    surfaceContainerHighest: AppColors.surfaceHigh,
    error: AppColors.signal,
    onError: Colors.white,
    outline: AppColors.strokeStrong,
    outlineVariant: AppColors.hairline,
  );

  return ThemeData(
    brightness: AppColors.palette.brightness,
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    canvasColor: AppColors.background,
    splashFactory: InkSparkle.splashFactory,
    highlightColor: Colors.transparent,
    splashColor: dark ? const Color(0x14FFFFFF) : const Color(0x0F000000),
    visualDensity: VisualDensity.standard,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: AppColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: AppText.title,
      iconTheme: IconThemeData(color: AppColors.secondary, size: 22),
      systemOverlayStyle: frankSystemBars(),
    ),
    iconTheme: IconThemeData(color: AppColors.secondary, size: 22),
    textTheme: TextTheme(
      displaySmall: AppText.display,
      headlineMedium: AppText.largeTitle,
      titleLarge: AppText.title,
      titleMedium: AppText.headline,
      bodyLarge: AppText.body,
      bodyMedium: TextStyle(
        color: AppColors.text,
        fontSize: 15,
        height: 1.4,
        letterSpacing: 0.05,
      ),
      bodySmall: AppText.bodySmall,
      labelLarge: AppText.label,
      labelSmall: AppText.caption,
    ),
    dividerTheme: DividerThemeData(
      color: AppColors.hairline,
      thickness: 1,
      space: 1,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: AppColors.secondary,
      textColor: AppColors.text,
      titleTextStyle: AppText.label,
      subtitleTextStyle: AppText.bodySmall,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      minVerticalPadding: 12,
    ),
    inputDecorationTheme: InputDecorationTheme(
      hintStyle: TextStyle(color: AppColors.hint, fontSize: 16),
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (!states.contains(WidgetState.selected)) {
          return AppColors.secondary;
        }
        return dark ? AppColors.onGold : Colors.white;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? AppColors.gold
            : AppColors.surfaceHigh;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? Colors.transparent
            : AppColors.strokeStrong;
      }),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: AppColors.gold,
      selectionColor: AppColors.gold.withValues(alpha: 0.3),
      selectionHandleColor: AppColors.gold,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: AppColors.gold,
      linearTrackColor: AppColors.surfaceHigh,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.surfaceHigh,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      textStyle: AppText.label,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.strokeStrong),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: AppColors.sheet,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: dark
          ? const Color(0x99000000)
          : const Color(0x52000000),
      elevation: 0,
      showDragHandle: false,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadii.sheet),
        ),
        side: BorderSide(color: AppColors.hairline),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: AppText.headline,
      contentTextStyle: AppText.bodySmall,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        side: BorderSide(color: AppColors.strokeStrong),
      ),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: AppColors.glow,
      surfaceTintColor: Colors.transparent,
      scrimColor: dark ? const Color(0x99000000) : const Color(0x52000000),
      elevation: 0,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.surfaceHigh,
      contentTextStyle: AppText.label,
      actionTextColor: AppColors.gold,
      elevation: 0,
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        side: BorderSide(color: AppColors.strokeStrong),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.strokeStrong),
      ),
      textStyle: TextStyle(color: AppColors.text, fontSize: 12.5),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.gold,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.gold,
        foregroundColor: AppColors.onGold,
        minimumSize: const Size(64, 52),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.text,
        minimumSize: const Size(64, 48),
        side: BorderSide(color: AppColors.strokeStrong),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        side: WidgetStateProperty.all(
          BorderSide(color: AppColors.strokeStrong),
        ),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? AppColors.goldSoft
              : Colors.transparent;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? AppColors.gold
              : AppColors.secondary;
        }),
      ),
    ),
  );
}
