import 'package:flutter/material.dart';

/// Couleurs DE SIMONE C.I. : rouge du logo, vert « CÔTE D'IVOIRE », anthracite.
class K {
  static const red = Color(0xFFD7141A); // rouge interface (logo : #FF0000)
  static const redDark = Color(0xFFA30E13);
  static const redSoft = Color(0xFFFDE8E8);
  static const green = Color(0xFF3A6B18); // vert du logo
  static const greenBright = Color(0xFF2F8A1F);
  static const greenSoft = Color(0xFFE6F2DC);
  static const ink = Color(0xFF1F2124);
  static const anthracite = Color(0xFF2B2E33);
  static const muted = Color(0xFF6B6F76);
  static const line = Color(0xFFE2E3E6);
  static const bg = Color(0xFFF4F4F5);
  static const sunk = Color(0xFFECEDEF);
  static const amber = Color(0xFFB7790F); // bols du pit
  static const amberSoft = Color(0xFFFBF0DA);
  static const warn = Color(0xFFA35A08);
  static const warnSoft = Color(0xFFFCEBD3);
  static const wa = Color(0xFF1FA855);
}

ThemeData appTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: K.red, primary: K.red, secondary: K.anthracite, surface: Colors.white);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: K.bg,
    appBarTheme: const AppBarTheme(backgroundColor: Colors.white, foregroundColor: K.ink, elevation: 0, scrolledUnderElevation: 1, surfaceTintColor: Colors.white),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: K.redSoft,
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? K.red : K.muted)),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
          fontSize: 12, fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500, color: s.contains(WidgetState.selected) ? K.red : K.muted)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: K.red, width: 2)),
      isDense: true,
      filled: true,
      fillColor: Colors.white,
    ),
    filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            foregroundColor: K.anthracite,
            side: const BorderSide(color: K.line),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
    snackBarTheme: const SnackBarThemeData(backgroundColor: K.anthracite, behavior: SnackBarBehavior.floating),
    switchTheme: SwitchThemeData(thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : null),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? K.greenBright : null)),
  );
}

/// Logo DE SIMONE C.I. (sigle redessiné + nom).
class Brand extends StatelessWidget {
  final double size;
  final bool showCountry;
  const Brand({super.key, this.size = 84, this.showCountry = true});
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        Image.asset('assets/logo_mark.png', width: size, height: size, filterQuality: FilterQuality.high),
        SizedBox(height: size * .12),
        Text('DE SIMONE C.I.',
            style: TextStyle(color: const Color(0xFFFF0000), fontSize: size * .30, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, letterSpacing: 1)),
        if (showCountry)
          Text("CÔTE D'IVOIRE", style: TextStyle(color: K.green, fontSize: size * .14, fontWeight: FontWeight.w600, letterSpacing: 1.5)),
      ]);
}
