import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'mila_tokens.dart';

/// The product's palette, which now comes from one place.
///
/// This app and the web console were designed independently and reconciled
/// never: different violet, different background, different surface, different
/// success, different danger. Somebody who used both was using two products.
/// Every value here is now the web app's, read from the generated
/// [MilaTokensDark] — regenerate with
/// `node scripts/export-design-tokens.mjs --dart <path>` in agentic-os.
///
/// The names are unchanged on purpose: 243 call sites keep working, and the
/// diff stays a palette change rather than a refactor.
///
/// Ink and fill are separate for the same reason they are on the web. A colour
/// that reads as an icon on a dark ground cannot also carry white text, so the
/// few places that put white on a solid colour take the `*Fill` variant.
/// [textTertiary] is the one that mattered most: it was 2.84:1, under the floor
/// for text at any size.
abstract final class MilaColors {
  /// Foreground accent — icons, active labels, links. 6.9:1 on the surface.
  static const violet = MilaTokensDark.primaryInk;

  /// The same accent where something white sits on top of it.
  static const violetFill = MilaTokensDark.primary;
  static const purple = MilaTokensDark.primaryHover;

  /// The second accent. CVD-validated on the web side so the palette never
  /// hinges on violet-versus-blue, which deuteranopia cannot separate.
  static const cyan = MilaTokensDark.teal;

  /// Brand-only, and the app's own: the orb is not a web object and the web
  /// palette has no pink to borrow.
  static const pink = Color(0xFFFF4FD8);

  static const surface = MilaTokensDark.surface;
  static const background = MilaTokensDark.bg;
  static const white = Color(0xFFFFFFFF);

  static const textPrimary = MilaTokensDark.text;
  static const textSecondary = MilaTokensDark.text2;
  static const textTertiary = MilaTokensDark.text3;
  static const divider = MilaTokensDark.border;
  static const cardBorder = MilaTokensDark.border;

  /// A boundary a finger has to find — an input outline, a checkbox edge.
  static const borderInteractive = MilaTokensDark.borderInteractive;

  static const danger = MilaTokensDark.errorInk;
  static const dangerFill = MilaTokensDark.dangerFill;
  static const success = MilaTokensDark.successInk;
  static const warning = MilaTokensDark.warningInk;

  static const primaryGradient = LinearGradient(
    colors: [violetFill, purple],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const orbGradient = LinearGradient(
    colors: [cyan, violetFill, purple, pink],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

abstract final class MilaTheme {
  static ThemeData dark() {
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: MilaColors.background,
      colorScheme: const ColorScheme.dark(
        // The scheme primary is a fill: Material puts onPrimary (white) on it.
        primary: MilaColors.violetFill,
        secondary: MilaColors.cyan,
        surface: MilaColors.surface,
        error: MilaColors.dangerFill,
        onPrimary: Colors.white,
        onSurface: MilaColors.textPrimary,
      ),
      splashFactory: InkSparkle.splashFactory,
    );

    final textTheme = GoogleFonts.interTextTheme(base.textTheme).copyWith(
      displayLarge: GoogleFonts.inter(
        fontSize: 40,
        fontWeight: FontWeight.w700,
        letterSpacing: -1,
      ),
      headlineLarge: GoogleFonts.inter(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
      ),
      headlineMedium: GoogleFonts.inter(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
      ),
      headlineSmall: GoogleFonts.inter(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
      ),
      titleLarge: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600),
      titleMedium: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
      titleSmall: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
      bodyLarge: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w400),
      bodyMedium: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w400),
      bodySmall: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: MilaColors.textSecondary,
      ),
      labelLarge: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
      labelMedium: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500),
      // 12px is the floor on both surfaces now. Nothing renders smaller.
      labelSmall: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: MilaColors.textSecondary,
      ),
    );

    return base.copyWith(
      textTheme: textTheme.apply(
        bodyColor: MilaColors.textPrimary,
        displayColor: MilaColors.textPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: const IconThemeData(color: MilaColors.textPrimary),
      ),
      dividerTheme: const DividerThemeData(
        color: MilaColors.divider,
        thickness: 1,
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? MilaColors.violet
              : const Color(0xFF2A3040),
        ),
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF141926),
        hintStyle: GoogleFonts.inter(
          color: MilaColors.textTertiary,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: MilaColors.borderInteractive),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: MilaColors.borderInteractive),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: MilaColors.violet, width: 1.4),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: MilaColors.surface,
        contentTextStyle: GoogleFonts.inter(color: Colors.white, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xFF141926),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
