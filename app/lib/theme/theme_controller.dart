import 'package:flutter/widgets.dart';
import '../core/services.dart';
import 'tokens.dart';

/// Settings > Display: Light mode, Dark mode or Use device default settings.
enum ThemeChoice { light, dark, system }

/// Holds the resident's display choice, saves it on the device and keeps
/// [KColors.palette] in step with it (and with the phone's setting when
/// "Use device default settings" is on).
class KTheme extends ChangeNotifier {
  KTheme({required this.store, ThemeChoice initial = ThemeChoice.light}) : _choice = initial {
    _apply();
  }

  final LocalStore store;
  ThemeChoice _choice;
  ThemeChoice get choice => _choice;

  /// Reads the saved choice. Light is the default (the designs are light-first).
  static Future<ThemeChoice> load(LocalStore store) async {
    final v = await store.readTheme();
    return ThemeChoice.values.firstWhere((c) => c.name == v, orElse: () => ThemeChoice.light);
  }

  Brightness get _platform => WidgetsBinding.instance.platformDispatcher.platformBrightness;

  Brightness get brightness => switch (_choice) {
        ThemeChoice.light => Brightness.light,
        ThemeChoice.dark => Brightness.dark,
        ThemeChoice.system => _platform,
      };

  Future<void> set(ThemeChoice c) async {
    if (c == _choice) return;
    _choice = c;
    _apply();
    notifyListeners();
    await store.writeTheme(c.name);
  }

  /// Called when the phone switches between light and dark.
  void platformChanged() {
    if (_choice != ThemeChoice.system) return;
    final before = KColors.palette;
    _apply();
    if (before != KColors.palette) notifyListeners();
  }

  void _apply() => KColors.palette = brightness == Brightness.dark ? KPalette.dark : KPalette.light;
}
