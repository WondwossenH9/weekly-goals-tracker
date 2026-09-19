import "package:flutter/material.dart";

class AppTheme {
  static const _seed = Color(0xFF3A6B5C); // muted green — "growth/progress"

  static ThemeData light() => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seed,
          brightness: Brightness.light,
        ),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      );

  static ThemeData dark() => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seed,
          brightness: Brightness.dark,
        ),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      );
}

/// Simple breakpoint used everywhere we need to switch between the phone
/// layout (bottom nav) and the desktop layout (side nav rail).
class Breakpoints {
  static const double desktop = 800;
  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= desktop;
}
