import 'package:flutter/material.dart';

/// Tokens de color de la app: **versión oscura nativa del portafolio**
/// `tg-robot-ucab-portfolio`.
///
/// Fondo profundo `#0B0F19`, tarjetas `#111827` con bordes sutiles `#1E293B`,
/// acento cian/turquesa técnico (`#2DD4BF` / `#06B6D4`), verde de estado
/// (`#4ADE80`), ámbar de alerta (`#F59E0B`) y rojo de peligro (`#EF4444`).
abstract final class CockpitColors {
  // Superficies (de la más hundida a la más elevada). Paleta del modo oscuro
  // del portafolio `tg-robot-ucab-portfolio` (fondo #0B0F19, tarjetas
  // #111827 y bordes sutiles #1E293B).
  static const Color surfaceLowest = Color(
    0xFF070A12,
  ); // barra de app y de navegación
  static const Color surface = Color(0xFF0B0F19); // lienzo base
  static const Color surfaceLow = Color(0xFF111827); // tarjetas
  static const Color surfaceContainer = Color(0xFF162032); // celdas de métrica
  static const Color surfaceHigh = Color(
    0xFF1E293B,
  ); // botones secundarios, pozos
  static const Color surfaceHighest = Color(0xFF273449); // modales

  // Texto y contornos
  static const Color onSurface = Color(0xFFE5E7EB);
  static const Color onSurfaceVariant = Color(0xFF94A3B8);
  static const Color outline = Color(0xFF64748B);
  static const Color outlineVariant = Color(0xFF1E293B);
  static const Color borderSubtle = Color(0x14FFFFFF); // rgba(255,255,255,0.08)
  static const Color neutral = outline;

  // Primario: cian/turquesa técnico del portafolio.
  static const Color primary = Color(0xFF2DD4BF);
  static const Color primaryText = Color(0xFFCCFBF1);
  static const Color onPrimary = Color(0xFF042F2E);
  static const Color primaryDim = Color(0xFF06B6D4);
  static const Color primaryTonal = Color(0xFF134E4A);
  static const Color onPrimaryContainer = Color(0xFF0F766E);

  // Secundario: cian
  static const Color secondary = Color(0xFF67E8F9);
  static const Color secondaryContainer = Color(0xFF0E7490);

  // Estado OK (verde)
  static const Color ok = Color(0xFF4ADE80);
  static const Color okContainer = Color(0xFF86EFAC);
  static const Color okTonal = Color(0xFF14532D);

  // Alertas
  static const Color error = Color(
    0xFFF87171,
  ); // texto/contorno sobre fondo oscuro
  static const Color errorContainer = Color(
    0xFF7F1D1D,
  ); // Freno Remoto, etiquetas CRITICAL
  static const Color onErrorContainer = Color(0xFFFEE2E2);
  static const Color hazard = Color(
    0xFFEF4444,
  ); // relleno y resplandor de peligro
  static const Color warning = Color(
    0xFFF59E0B,
  ); // ámbar: precaución (20-50 cm, batería)
}

/// Estilos tipográficos del DESIGN.md: **Inter** para títulos y descripciones,
/// **JetBrains Mono** para toda la telemetría (cifras en columnas fijas).
abstract final class CockpitText {
  static const String sans = 'Inter';
  static const String mono = 'JetBrainsMono';

  static const List<FontFeature> tabular = <FontFeature>[
    FontFeature.tabularFigures(),
  ];

  static const TextStyle displayLg = TextStyle(
    fontFamily: sans,
    fontSize: 40,
    height: 48 / 40,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.8,
  );
  static const TextStyle headlineLg = TextStyle(
    fontFamily: sans,
    fontSize: 32,
    height: 40 / 32,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle headlineLgMobile = TextStyle(
    fontFamily: sans,
    fontSize: 26,
    height: 34 / 26,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle headlineMd = TextStyle(
    fontFamily: sans,
    fontSize: 24,
    height: 32 / 24,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle headlineSm = TextStyle(
    fontFamily: sans,
    fontSize: 20,
    height: 28 / 20,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle titleMd = TextStyle(
    fontFamily: sans,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle bodyLg = TextStyle(
    fontFamily: sans,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w400,
  );
  static const TextStyle bodyMd = TextStyle(
    fontFamily: sans,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w400,
  );
  static const TextStyle bodySm = TextStyle(
    fontFamily: sans,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w400,
  );

  /// Lectura grande (22 px, 700, tabular-nums).
  static const TextStyle telemetryLg = TextStyle(
    fontFamily: mono,
    fontSize: 22,
    height: 28 / 22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.22,
    fontFeatures: tabular,
  );

  /// Lectura media (14 px, 500, tabular-nums).
  static const TextStyle telemetryMd = TextStyle(
    fontFamily: mono,
    fontSize: 14,
    height: 18 / 14,
    fontWeight: FontWeight.w500,
    fontFeatures: tabular,
  );

  /// Etiqueta de grupo diagnóstico (11 px, 400, mayúsculas, tabular-nums).
  static const TextStyle telemetrySm = TextStyle(
    fontFamily: mono,
    fontSize: 11,
    height: 14 / 11,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.44,
    fontFeatures: tabular,
  );

  /// Etiqueta de estado o de control (12 px, 600, mayúsculas, tabular-nums).
  static const TextStyle labelMd = TextStyle(
    fontFamily: mono,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.6,
    fontFeatures: tabular,
  );
}

/// Radios compartidos (4 / 8 / 12 / 16 px) y objetivo táctil mínimo (44 px).
abstract final class CockpitRadius {
  static const double sm = 4;
  static const double md = 8;
  static const double lg = 12;
  static const double xl = 16;
  static const double touchMin = 44;
}

/// Tema oscuro Material 3 del Cockpit. Se usa como `theme` y `darkTheme`.
ThemeData buildCockpitTheme() {
  const ColorScheme esquema = ColorScheme(
    brightness: Brightness.dark,
    primary: CockpitColors.primary,
    onPrimary: CockpitColors.onPrimary,
    primaryContainer: CockpitColors.primaryTonal,
    onPrimaryContainer: CockpitColors.primaryText,
    secondary: CockpitColors.secondary,
    onSecondary: Color(0xFF083344),
    secondaryContainer: CockpitColors.secondaryContainer,
    onSecondaryContainer: Color(0xFFCFFAFE),
    tertiary: CockpitColors.ok,
    onTertiary: Color(0xFF052E16),
    tertiaryContainer: CockpitColors.okTonal,
    onTertiaryContainer: CockpitColors.okContainer,
    error: CockpitColors.error,
    onError: Color(0xFF450A0A),
    errorContainer: CockpitColors.errorContainer,
    onErrorContainer: CockpitColors.onErrorContainer,
    surface: CockpitColors.surface,
    onSurface: CockpitColors.onSurface,
    surfaceDim: CockpitColors.surface,
    surfaceBright: Color(0xFF334155),
    surfaceContainerLowest: CockpitColors.surfaceLowest,
    surfaceContainerLow: CockpitColors.surfaceLow,
    surfaceContainer: CockpitColors.surfaceContainer,
    surfaceContainerHigh: CockpitColors.surfaceHigh,
    surfaceContainerHighest: CockpitColors.surfaceHighest,
    onSurfaceVariant: CockpitColors.onSurfaceVariant,
    outline: CockpitColors.outline,
    outlineVariant: CockpitColors.outlineVariant,
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: CockpitColors.onSurface,
    onInverseSurface: Color(0xFF111827),
    inversePrimary: Color(0xFF0F766E),
    surfaceTint: CockpitColors.primaryDim,
  );

  final TextTheme textos =
      const TextTheme(
        displayLarge: CockpitText.displayLg,
        headlineLarge: CockpitText.headlineLg,
        headlineMedium: CockpitText.headlineMd,
        headlineSmall: CockpitText.headlineSm,
        titleLarge: CockpitText.headlineSm,
        titleMedium: CockpitText.titleMd,
        titleSmall: CockpitText.titleMd,
        bodyLarge: CockpitText.bodyLg,
        bodyMedium: CockpitText.bodyMd,
        bodySmall: CockpitText.bodySm,
        labelLarge: CockpitText.labelMd,
        labelMedium: CockpitText.labelMd,
        labelSmall: CockpitText.telemetrySm,
      ).apply(
        bodyColor: CockpitColors.onSurface,
        displayColor: CockpitColors.onSurface,
      );

  final RoundedRectangleBorder formaControl = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(CockpitRadius.md),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: esquema,
    fontFamily: CockpitText.sans,
    textTheme: textos,
    scaffoldBackgroundColor: CockpitColors.surface,
    canvasColor: CockpitColors.surface,
    dividerTheme: const DividerThemeData(
      color: CockpitColors.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: CockpitColors.surfaceLowest,
      surfaceTintColor: Colors.transparent,
      foregroundColor: CockpitColors.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: CockpitColors.surfaceLowest,
      surfaceTintColor: Colors.transparent,
      indicatorColor: CockpitColors.primary.withValues(alpha: 0.16),
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CockpitRadius.xl),
      ),
      height: 72,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>(
        (Set<WidgetState> estados) => CockpitText.telemetrySm.copyWith(
          fontWeight: FontWeight.w600,
          color: estados.contains(WidgetState.selected)
              ? CockpitColors.primary
              : CockpitColors.onSurfaceVariant,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith<IconThemeData>(
        (Set<WidgetState> estados) => IconThemeData(
          size: 24,
          color: estados.contains(WidgetState.selected)
              ? CockpitColors.primary
              : CockpitColors.onSurfaceVariant,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: CockpitColors.primary,
        foregroundColor: CockpitColors.onPrimary,
        disabledBackgroundColor: CockpitColors.surfaceHigh,
        disabledForegroundColor: CockpitColors.outline,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: formaControl,
        textStyle: CockpitText.labelMd.copyWith(fontSize: 13),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: CockpitColors.surfaceHigh,
        foregroundColor: CockpitColors.onSurface,
        disabledForegroundColor: CockpitColors.outline,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        side: const BorderSide(color: CockpitColors.outlineVariant),
        shape: formaControl,
        textStyle: CockpitText.labelMd.copyWith(fontSize: 13),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: CockpitColors.primary,
        minimumSize: const Size(0, 40),
        shape: formaControl,
        textStyle: CockpitText.labelMd,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: CockpitColors.surfaceContainer,
        foregroundColor: CockpitColors.onSurfaceVariant,
        selectedBackgroundColor: CockpitColors.primary,
        selectedForegroundColor: CockpitColors.onPrimary,
        disabledBackgroundColor: CockpitColors.surfaceContainer,
        disabledForegroundColor: CockpitColors.outline,
        side: const BorderSide(color: CockpitColors.outlineVariant),
        textStyle: CockpitText.labelMd,
        visualDensity: VisualDensity.compact,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: CockpitColors.surfaceHighest,
      contentTextStyle: CockpitText.bodyMd.copyWith(
        color: CockpitColors.onSurface,
      ),
      shape: formaControl,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: CockpitColors.surfaceHighest,
        borderRadius: BorderRadius.circular(CockpitRadius.sm),
        border: Border.all(color: CockpitColors.outlineVariant),
      ),
      textStyle: CockpitText.telemetrySm.copyWith(
        color: CockpitColors.onSurface,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: CockpitColors.surfaceHighest,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: CockpitColors.outline,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(CockpitRadius.lg),
        ),
      ),
    ),
  );
}
