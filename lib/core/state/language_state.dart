import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageState extends ChangeNotifier {
  LanguageState._();

  static final LanguageState instance = LanguageState._();
  static const String _storageKey = 'app_language_code';
  static const String _assetPath = 'assets/txt/app_locales.json';

  String _languageCode = 'zh';
  Map<String, Map<String, String>> _translations = const {};

  String get languageCode => _languageCode;
  bool get isChinese => _languageCode == 'zh';

  Future<void> initialize() async {
    await _loadTranslations();
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_storageKey);
    if (saved == 'zh' || saved == 'en') {
      _languageCode = saved!;
    }
  }

  Future<void> setLanguage(String languageCode) async {
    if (languageCode != 'zh' && languageCode != 'en') return;
    if (_languageCode == languageCode) return;
    _languageCode = languageCode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, languageCode);
    notifyListeners();
  }

  String t(String key, {Map<String, Object?> args = const {}}) {
    var value =
        _translations[_languageCode]?[key] ??
        _translations['zh']?[key] ??
        key;
    for (final entry in args.entries) {
      value = value.replaceAll('{${entry.key}}', entry.value.toString());
    }
    return value;
  }

  Future<void> _loadTranslations() async {
    if (_translations.isNotEmpty) return;
    final raw = await rootBundle.loadString(_assetPath);
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return;
    _translations = decoded.map((language, values) {
      final map = values is Map ? values : const {};
      return MapEntry(
        language.toString(),
        map.map((key, value) => MapEntry(key.toString(), value.toString())),
      );
    });
  }
}

extension AppLocalizations on BuildContext {
  String tr(String key, {Map<String, Object?> args = const {}}) {
    return read<LanguageState>().t(key, args: args);
  }
}
