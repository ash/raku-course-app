import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Fixed brand colours (do NOT change between light and dark).
class AppColors {
  // Raku's Camelia butterfly is pink/magenta — used as the brand accent.
  static const rakuAccent = Color(0xFFE6308A);
  static const rakuAccentDim = Color(0xFFB02468);

  // Code blocks are always dark in BOTH themes for legible syntax colours.
  static const codeBg = Color(0xFF14121A);
  static const codeText = Color(0xFFECECF1);
  static const codeComment = Color(0xFF7A6B8A);
  static const codeString = Color(0xFF9BE3A4);
  static const codeNumber = Color(0xFFF0A45A);
  static const codeSigil = Color(0xFFE6308A); // $ @ % & sigils
  static const codeKeyword = Color(0xFFC58AF0);
  static const codeType = Color(0xFF7FC8F8);
  static const codeRegex = Color(0xFFF2C46D);
  static const codeOutput = Color(0xFF8FE3D0);
  static const codeError = Color(0xFFFF8A80);
  static const codeDim = Color(0xFF9A93AA);
  static const codeBorder = Color(0xFF302C3A);

  // Per-part accent colours (one per top-level part, index 0..7).
  static const partColors = <Color>[
    Color(0xFF8A7CF0), // About — violet
    Color(0xFFE6308A), // Essentials — Raku magenta
    Color(0xFF1FA89A), // Advanced — teal
    Color(0xFFE08A00), // Objects/IO — amber
    Color(0xFF4A7BE8), // Regexes — blue
    Color(0xFF3FA34D), // Paradigms — green
    Color(0xFFC79A1E), // The Final Test — gold
    Color(0xFFD0603A), // Addendum — terracotta
  ];

  static Color partColor(int i) => partColors[i % partColors.length];
}

/// Adaptive chrome colours resolved from the active theme.
@immutable
class Palette extends ThemeExtension<Palette> {
  final Color bg;
  final Color surface;
  final Color surface2;
  final Color stroke;
  final Color text;
  final Color textDim;
  final Color inlineCode;

  const Palette({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.stroke,
    required this.text,
    required this.textDim,
    required this.inlineCode,
  });

  static const dark = Palette(
    bg: Color(0xFF0E0D12),
    surface: Color(0xFF18161F),
    surface2: Color(0xFF221F2B),
    stroke: Color(0xFF302C3A),
    text: Color(0xFFECECF1),
    textDim: Color(0xFF9A93AA),
    inlineCode: Color(0xFFF06AB0),
  );

  static const light = Palette(
    bg: Color(0xFFF7F5FA),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFEDEAF3),
    stroke: Color(0xFFE2DEEA),
    text: Color(0xFF1B1922),
    textDim: Color(0xFF6B6678),
    inlineCode: Color(0xFFB02468),
  );

  @override
  Palette copyWith({
    Color? bg,
    Color? surface,
    Color? surface2,
    Color? stroke,
    Color? text,
    Color? textDim,
    Color? inlineCode,
  }) => Palette(
    bg: bg ?? this.bg,
    surface: surface ?? this.surface,
    surface2: surface2 ?? this.surface2,
    stroke: stroke ?? this.stroke,
    text: text ?? this.text,
    textDim: textDim ?? this.textDim,
    inlineCode: inlineCode ?? this.inlineCode,
  );

  @override
  Palette lerp(ThemeExtension<Palette>? other, double t) {
    if (other is! Palette) return this;
    return Palette(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      stroke: Color.lerp(stroke, other.stroke, t)!,
      text: Color.lerp(text, other.text, t)!,
      textDim: Color.lerp(textDim, other.textDim, t)!,
      inlineCode: Color.lerp(inlineCode, other.inlineCode, t)!,
    );
  }
}

extension PaletteX on BuildContext {
  Palette get palette => Theme.of(this).extension<Palette>() ?? Palette.dark;
}

/// A real monospaced face on each platform. iOS has no font that answers to
/// the generic name 'monospace', so code there fell back to the proportional
/// system font; Menlo ships with every iOS version the app supports.
String get kMonoFont =>
    defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS
    ? 'Menlo'
    : 'monospace';
const kMonoFallback = <String>['Menlo', 'Courier', 'monospace'];

ThemeData _theme(Brightness brightness, Palette p) {
  final base = ThemeData(brightness: brightness, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: p.bg,
    extensions: [p],
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: AppColors.rakuAccent,
          brightness: brightness,
        ).copyWith(
          surface: p.surface,
          primary: AppColors.rakuAccent,
          onPrimary: Colors.white,
          secondary: AppColors.rakuAccent,
        ),
    textTheme: base.textTheme.apply(bodyColor: p.text, displayColor: p.text),
    appBarTheme: AppBarTheme(
      backgroundColor: p.bg,
      elevation: 0,
      centerTitle: false,
      foregroundColor: p.text,
      titleTextStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: p.text,
      ),
    ),
    splashFactory: InkRipple.splashFactory,
  );
}

ThemeData buildDarkTheme() => _theme(Brightness.dark, Palette.dark);
ThemeData buildLightTheme() => _theme(Brightness.light, Palette.light);
