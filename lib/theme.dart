import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Shared accent colours (identical in both themes) ─────────────────────────
// These never change between light and dark — they are the brand identity.
const Color kAccentNeon   = Color(0xFF39FF14); // neon green CTA / live indicator
const Color kAccentGreen  = Color(0xFF4CAF50); // mid green
const Color kAccentDark   = Color(0xFF1B5E20); // dark green (AppBar / FAB dark)
const Color kLiveRed      = Color(0xFFFF3D3D); // wicket / danger
const Color kCompletedBlue= Color(0xFF2196F3); // completed match badge
const Color kTrophyGold   = Color(0xFFFFC107); // tournament trophy

// ── Dark palette ──────────────────────────────────────────────────────────────
const Color _dkSurface    = Color(0xFF0A0A0A);
const Color _dkCard       = Color(0xFF141414);
const Color _dkCard2      = Color(0xFF1C1C1C);
const Color _dkBorder     = Color(0xFF2E4A2E);
const Color _dkTextPri    = Colors.white;
const Color _dkTextSec    = Color(0xFF8A8A8A);

// ── Light palette ─────────────────────────────────────────────────────────────
const Color _ltSurface    = Color(0xFFF0F4F0); // very slightly warm off-white
const Color _ltCard       = Color(0xFFFFFFFF);
const Color _ltCard2      = Color(0xFFEEF4EE);
const Color _ltBorder     = Color(0xFFB8D4B8);
const Color _ltTextPri    = Color(0xFF0D1F0D);
const Color _ltTextSec    = Color(0xFF4A6349);

// ─────────────────────────────────────────────────────────────────────────────
// AppTheme — call AppTheme.dark() / AppTheme.light() from MaterialApp
// ─────────────────────────────────────────────────────────────────────────────

class AppTheme {
  AppTheme._();

  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        surface: _dkSurface,
        card: _dkCard,
        card2: _dkCard2,
        border: _dkBorder,
        textPrimary: _dkTextPri,
        textSecondary: _dkTextSec,
        accent: kAccentGreen,
        accentForeground: Colors.black,
        appBarBg: kAccentDark,
        appBarFg: Colors.white,
        inputFill: const Color(0xFF1E1E1E),
        inputBorder: const Color(0xFF2A2A2A),
        glassBg: Color(0x1A4CAF50),
        glassBorder: Color(0x334CAF50),
      );

  static ThemeData light() => _build(
        brightness: Brightness.light,
        surface: _ltSurface,
        card: _ltCard,
        card2: _ltCard2,
        border: _ltBorder,
        textPrimary: _ltTextPri,
        textSecondary: _ltTextSec,
        accent: kAccentDark,       // darker green for contrast on white
        accentForeground: Colors.white,
        appBarBg: kAccentDark,
        appBarFg: Colors.white,
        inputFill: const Color(0xFFEAF2EA),
        inputBorder: const Color(0xFFB8D4B8),
        glassBg: Color(0x151B5E20),
        glassBorder: Color(0x2A1B5E20),
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color surface,
    required Color card,
    required Color card2,
    required Color border,
    required Color textPrimary,
    required Color textSecondary,
    required Color accent,
    required Color accentForeground,
    required Color appBarBg,
    required Color appBarFg,
    required Color inputFill,
    required Color inputBorder,
    required Color glassBg,
    required Color glassBorder,
  }) {
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: surface,
      primaryColor: kAccentDark,

      colorScheme: ColorScheme(
        brightness: brightness,
        primary: accent,
        onPrimary: accentForeground,
        secondary: kAccentGreen,
        onSecondary: Colors.black,
        surface: card,
        onSurface: textPrimary,
        error: kLiveRed,
        onError: Colors.white,
        // Store custom palette values in extensions (see AppColors below)
      ),

      // ── AppBar ─────────────────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor: appBarBg,
        foregroundColor: appBarFg,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.rajdhani(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: appBarFg,
          letterSpacing: 1.2,
        ),
        iconTheme: IconThemeData(color: appBarFg),
      ),

      // ── Cards ──────────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        color: card,
        elevation: isDark ? 4 : 2,
        shadowColor: Colors.black.withAlpha(isDark ? 60 : 30),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border, width: 1),
        ),
      ),

      // ── Inputs ────────────────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFill,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: inputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: inputBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kLiveRed),
        ),
        labelStyle: GoogleFonts.rajdhani(
            color: textSecondary, fontWeight: FontWeight.w600),
        hintStyle: GoogleFonts.rajdhani(color: textSecondary),
      ),

      // ── Buttons ───────────────────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: accentForeground,
          elevation: 6,
          shadowColor: accent.withAlpha(100),
          padding:
              const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.rajdhani(
              fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 1),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle:
              GoogleFonts.rajdhani(fontWeight: FontWeight.w600),
        ),
      ),

      // ── Bottom Nav ────────────────────────────────────────────────────────
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: card,
        selectedItemColor: accent,
        unselectedItemColor: textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        selectedLabelStyle:
            GoogleFonts.rajdhani(fontWeight: FontWeight.w700, fontSize: 12),
        unselectedLabelStyle:
            GoogleFonts.rajdhani(fontWeight: FontWeight.w600, fontSize: 12),
      ),

      // ── Dialogs ───────────────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        titleTextStyle: GoogleFonts.rajdhani(
            color: textPrimary, fontSize: 20, fontWeight: FontWeight.w700),
        contentTextStyle:
            GoogleFonts.rajdhani(color: textSecondary, fontSize: 14),
      ),

      // ── Bottom Sheets ─────────────────────────────────────────────────────
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        shape: const RoundedRectangleBorder(
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(20))),
      ),

      // ── FAB ───────────────────────────────────────────────────────────────
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: accentForeground,
        elevation: 8,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
      ),

      // ── Snackbar ──────────────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: card,
        contentTextStyle: GoogleFonts.rajdhani(
            color: textPrimary, fontWeight: FontWeight.w600),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8)),
      ),

      // ── Progress indicators ───────────────────────────────────────────────
      progressIndicatorTheme:
          ProgressIndicatorThemeData(color: accent),

      // ── Text ──────────────────────────────────────────────────────────────
      textTheme: GoogleFonts.rajdhaniTextTheme(
        isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
      ).apply(bodyColor: textPrimary, displayColor: textPrimary),

      // ── Dividers ──────────────────────────────────────────────────────────
      dividerTheme: DividerThemeData(color: border, thickness: 1),

      // ── Store extra palette values as extensions ──────────────────────────
      extensions: [
        AppColors(
          surface: surface,
          card: card,
          card2: card2,
          border: border,
          textPrimary: textPrimary,
          textSecondary: textSecondary,
          accent: accent,
          glassBg: glassBg,
          glassBorder: glassBorder,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AppColors — ThemeExtension that carries the full custom palette.
//
// Usage in any widget:
//   final c = Theme.of(context).appColors;
//   Container(color: c.card, ...)
// ─────────────────────────────────────────────────────────────────────────────

class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.surface,
    required this.card,
    required this.card2,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.accent,
    required this.glassBg,
    required this.glassBorder,
  });

  final Color surface;
  final Color card;
  final Color card2;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color accent;
  final Color glassBg;
  final Color glassBorder;

  // Fixed accent colours that never change with theme:
  Color get neon          => kAccentNeon;
  Color get accentGreen   => kAccentGreen;
  Color get accentDark    => kAccentDark;
  Color get liveRed       => kLiveRed;
  Color get completedBlue => kCompletedBlue;
  Color get trophyGold    => kTrophyGold;

  @override
  AppColors copyWith({
    Color? surface,
    Color? card,
    Color? card2,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? accent,
    Color? glassBg,
    Color? glassBorder,
  }) {
    return AppColors(
      surface:       surface       ?? this.surface,
      card:          card          ?? this.card,
      card2:         card2         ?? this.card2,
      border:        border        ?? this.border,
      textPrimary:   textPrimary   ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      accent:        accent        ?? this.accent,
      glassBg:       glassBg       ?? this.glassBg,
      glassBorder:   glassBorder   ?? this.glassBorder,
    );
  }

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      surface:       Color.lerp(surface,       other.surface,       t)!,
      card:          Color.lerp(card,          other.card,          t)!,
      card2:         Color.lerp(card2,         other.card2,         t)!,
      border:        Color.lerp(border,        other.border,        t)!,
      textPrimary:   Color.lerp(textPrimary,   other.textPrimary,   t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      accent:        Color.lerp(accent,        other.accent,        t)!,
      glassBg:       Color.lerp(glassBg,       other.glassBg,       t)!,
      glassBorder:   Color.lerp(glassBorder,   other.glassBorder,   t)!,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Convenience extension — call Theme.of(context).appColors anywhere
// ─────────────────────────────────────────────────────────────────────────────

extension AppThemeExtension on ThemeData {
  /// Returns the [AppColors] extension.  Never null because both
  /// [AppTheme.dark] and [AppTheme.light] always register it.
  AppColors get appColors => extension<AppColors>()!;
}
