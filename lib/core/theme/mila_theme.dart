import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// MILA style guide palette.
abstract final class MilaColors {
  static const cyan = Color(0xFF00E5FF);
  static const violet = Color(0xFF7B61FF);
  static const purple = Color(0xFFA855F7);
  static const pink = Color(0xFFFF4FD8);
  static const surface = Color(0xFF1A1F2E);
  static const background = Color(0xFF0D111B);
  static const white = Color(0xFFFFFFFF);

  static const textPrimary = Colors.white;
  static const textSecondary = Color(0xFF9AA3B5);
  static const textTertiary = Color(0xFF5D6678);
  static const divider = Color(0x14FFFFFF);
  static const cardBorder = Color(0x1AFFFFFF);
  static const danger = Color(0xFFFF5A6E);
  static const success = Color(0xFF35D49B);

  static const primaryGradient = LinearGradient(
    colors: [violet, purple],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const orbGradient = LinearGradient(
    colors: [cyan, violet, purple, pink],
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
        primary: MilaColors.violet,
        secondary: MilaColors.cyan,
        surface: MilaColors.surface,
        error: MilaColors.danger,
        onPrimary: Colors.white,
        onSurface: MilaColors.textPrimary,
      ),
      splashFactory: InkSparkle.splashFactory,
    );

    final textTheme = GoogleFonts.interTextTheme(base.textTheme).copyWith(
      displayLarge: GoogleFonts.inter(
          fontSize: 40, fontWeight: FontWeight.w700, letterSpacing: -1),
      headlineLarge: GoogleFonts.inter(
          fontSize: 28, fontWeight: FontWeight.w600, letterSpacing: -0.5),
      headlineMedium: GoogleFonts.inter(
          fontSize: 24, fontWeight: FontWeight.w600, letterSpacing: -0.4),
      headlineSmall: GoogleFonts.inter(
          fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: -0.3),
      titleLarge: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600),
      titleMedium: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
      titleSmall: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
      bodyLarge: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w400),
      bodyMedium: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w400),
      bodySmall: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: MilaColors.textSecondary),
      labelLarge: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
      labelMedium: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500),
      labelSmall: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: MilaColors.textSecondary),
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
        titleTextStyle:
            GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600),
        iconTheme: const IconThemeData(color: MilaColors.textPrimary),
      ),
      dividerTheme:
          const DividerThemeData(color: MilaColors.divider, thickness: 1),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? MilaColors.violet
                : const Color(0xFF2A3040)),
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF141926),
        hintStyle: GoogleFonts.inter(
            color: MilaColors.textTertiary,
            fontSize: 14,
            fontWeight: FontWeight.w400),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: MilaColors.cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: MilaColors.cardBorder),
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
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      }),
    );
  }
}
