import 'package:flutter/material.dart';

final ValueNotifier<ThemeMode> appThemeMode = ValueNotifier(ThemeMode.system);
final ValueNotifier<Locale> appLocale = ValueNotifier(const Locale('fr'));
final ValueNotifier<double> appTextScale = ValueNotifier(1.0);
final ValueNotifier<Color> appSeedColor = ValueNotifier(const Color(0xFF075EF5));
