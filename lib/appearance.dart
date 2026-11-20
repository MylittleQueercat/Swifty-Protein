import 'package:flutter/material.dart';

const brandPine = Color(0xff1b2a27);
const brandIvory = Color(0xfff5edda);

ThemeData buildAppTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xff527766),
    brightness: brightness,
    primary: dark ? const Color(0xffafc8ab) : const Color(0xff35594b),
    onPrimary: dark ? brandPine : const Color(0xfffffaf0),
    tertiary: dark ? const Color(0xffdda58c) : const Color(0xff864c37),
    onTertiary: dark ? const Color(0xff3a2119) : Colors.white,
    surface: dark ? brandPine : const Color(0xfff8f3e8),
    onSurface: dark ? brandIvory : brandPine,
    onSurfaceVariant: dark ? const Color(0xffc0ccc0) : const Color(0xff4d6156),
    surfaceContainerLowest: dark
        ? const Color(0xff14211e)
        : const Color(0xfffffcf5),
    surfaceContainerLow: dark
        ? const Color(0xff22332e)
        : const Color(0xfff3ede0),
    surfaceContainer: dark ? const Color(0xff293c35) : const Color(0xffeee7d9),
    surfaceContainerHigh: dark
        ? const Color(0xff31463e)
        : const Color(0xffe8e1d2),
    surfaceContainerHighest: dark
        ? const Color(0xff394e45)
        : const Color(0xffe1d9ca),
    outline: dark ? const Color(0xff90a396) : const Color(0xff62786b),
    outlineVariant: dark ? const Color(0xff465b50) : const Color(0xffc8d0c5),
  );

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    appBarTheme: AppBarThemeData(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    ),
    listTileTheme: ListTileThemeData(iconColor: scheme.primary),
  );
}

class Appearance extends InheritedWidget {
  const Appearance({
    super.key,
    required this.mode,
    required this.onChanged,
    required super.child,
  });

  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;

  static Appearance of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Appearance>()!;

  @override
  bool updateShouldNotify(Appearance oldWidget) => mode != oldWidget.mode;
}

class AppearanceButton extends StatelessWidget {
  const AppearanceButton({super.key});

  @override
  Widget build(BuildContext context) {
    final appearance = Appearance.of(context);
    return PopupMenuButton<ThemeMode>(
      tooltip: 'Appearance',
      icon: Icon(switch (appearance.mode) {
        ThemeMode.system => Icons.brightness_auto_outlined,
        ThemeMode.light => Icons.light_mode_outlined,
        ThemeMode.dark => Icons.dark_mode_outlined,
      }),
      initialValue: appearance.mode,
      onSelected: appearance.onChanged,
      itemBuilder: (context) => [
        for (final (mode, label) in const [
          (ThemeMode.system, 'Use system setting'),
          (ThemeMode.light, 'Light'),
          (ThemeMode.dark, 'Dark'),
        ])
          CheckedPopupMenuItem(
            value: mode,
            checked: appearance.mode == mode,
            child: Text(label),
          ),
      ],
    );
  }
}
