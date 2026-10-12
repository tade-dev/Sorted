import 'package:flutter/material.dart';
import '../../widgets/sorted_icon.dart';

import 'sorted_colors.dart';
import 'sorted_shape.dart';

ThemeData sortedTheme() {
  const c = SortedColors.light;

  // Material's type scale tracks letters out (0.1–0.5); the design is CSS
  // default tracking, so zero it before applying the families.
  final m = Typography.material2021().black;
  TextStyle? flat(TextStyle? t) => t?.copyWith(letterSpacing: 0);
  final base = TextTheme(
    displayLarge: flat(m.displayLarge),
    displayMedium: flat(m.displayMedium),
    displaySmall: flat(m.displaySmall),
    headlineLarge: flat(m.headlineLarge),
    headlineMedium: flat(m.headlineMedium),
    headlineSmall: flat(m.headlineSmall),
    titleLarge: flat(m.titleLarge),
    titleMedium: flat(m.titleMedium),
    titleSmall: flat(m.titleSmall),
    bodyLarge: flat(m.bodyLarge),
    bodyMedium: flat(m.bodyMedium),
    bodySmall: flat(m.bodySmall),
    labelLarge: flat(m.labelLarge),
    labelMedium: flat(m.labelMedium),
    labelSmall: flat(m.labelSmall),
  );
  final display = base.apply(fontFamily: 'Bricolage Grotesque');
  final body = base.apply(fontFamily: 'Plus Jakarta Sans');

  return ThemeData(
    useMaterial3: true,
    fontFamily: 'Plus Jakarta Sans',
    scaffoldBackgroundColor: c.background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: c.primary,
      primary: c.primary,
      surface: c.surface,
      error: const Color(0xFFB3261E),
    ),
    extensions: const <ThemeExtension<dynamic>>[c],
    textTheme: TextTheme(
      // Bricolage Grotesque: wordmark, hero numbers, headings.
      displayLarge: display.displayLarge?.copyWith(
        fontWeight: FontWeight.w700,
        fontSize: 68,
        color: c.ink,
      ),
      headlineLarge: display.headlineLarge?.copyWith(
        fontWeight: FontWeight.w700,
        fontSize: 32,
        letterSpacing: -0.8,
        color: c.ink,
      ),
      headlineMedium: display.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        fontSize: 28,
        letterSpacing: -0.6,
        color: c.ink,
      ),
      titleLarge: display.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        fontSize: 19,
        color: c.ink,
      ),
      // Plus Jakarta Sans: body, labels, captions.
      bodyLarge: body.bodyLarge?.copyWith(fontSize: 16, height: 1.5, color: c.ink),
      bodyMedium: body.bodyMedium?.copyWith(fontSize: 15, height: 1.45, color: c.muted),
      labelLarge: body.labelLarge?.copyWith(fontSize: 17, fontWeight: FontWeight.w600),
      labelMedium: body.labelMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.w600, color: c.ink),
      titleMedium: body.titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.w600, color: c.ink),
      titleSmall: body.titleSmall?.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: c.ink),
      bodySmall: body.bodySmall?.copyWith(fontSize: 13, color: c.muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(SortedShape.primaryButtonHeight),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SortedShape.primaryButtonRadius),
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SortedShape.cardRadius),
        side: BorderSide(color: c.line),
      ),
    ),
    // Setup's text field: 52 high, 14 radius, 1.5 px #DCE2EA, white, 16 px.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      hintStyle: body.bodyLarge?.copyWith(fontSize: 16, color: c.muted),
      labelStyle: body.bodyLarge?.copyWith(fontSize: 16, color: c.muted),
      floatingLabelBehavior: FloatingLabelBehavior.never,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c.line, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c.line, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c.primary, width: 1.5),
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(cursorColor: c.primary),
    // Welcome's "I already have an account": 48 high, 15/600, no fill.
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.ink,
        minimumSize: const Size(0, SortedShape.secondaryButtonHeight),
        textStyle: body.labelLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.ink,
        backgroundColor: c.surface,
        minimumSize: const Size(0, SortedShape.secondaryButtonHeight),
        side: BorderSide(color: c.line, width: 1.5),
        textStyle: body.labelLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    // Header from Draft / Reply / Order: 44 px chevron back, 16/600 title,
    // left-aligned, flat on the page colour.
    appBarTheme: AppBarTheme(
      backgroundColor: c.background,
      surfaceTintColor: Colors.transparent,
      foregroundColor: c.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      // A bare AppBar with no leading must not sit flush at x=0.
      titleSpacing: 16,
      toolbarHeight: 60,
      iconTheme: IconThemeData(color: c.ink, size: 24),
      titleTextStyle: body.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: c.ink,
      ),
    ),
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (_) => const SortedIcon(SortedIcons.back, size: 24),
    ),
    dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
  );
}
