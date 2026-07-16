import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'strings.dart';

/// App settings: SFX on by default, music OFF by default, language RU/EN.
class AppSettings extends ChangeNotifier {
  bool _sfxOn = true;
  bool _musicOn = true; // ragtime on by default — it's lovely!
  String _lang = 'ru';

  bool get sfxOn => _sfxOn;
  bool get musicOn => _musicOn;
  String get lang => _lang;

  set sfxOn(bool v) {
    _sfxOn = v;
    _save();
    notifyListeners();
  }

  set musicOn(bool v) {
    _musicOn = v;
    _save();
    notifyListeners();
  }

  set lang(String v) {
    _lang = v;
    L10n.lang = v;
    _save();
    notifyListeners();
  }

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _sfxOn = p.getBool('sfxOn') ?? true;
      _musicOn = p.getBool('musicOn') ?? true;
      _lang = p.getString('lang') ?? 'ru';
    } catch (_) {
      // keep defaults if storage is unavailable
    }
    L10n.lang = _lang;
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('sfxOn', _sfxOn);
      await p.setBool('musicOn', _musicOn);
      await p.setString('lang', _lang);
    } catch (_) {}
  }
}
