import 'package:shared_preferences/shared_preferences.dart';

class Config {
  static const _keyUrl = 'turso_url';
  static const _keyToken = 'turso_token';

  static Future<String> getUrl() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_keyUrl) ?? '';
  }

  static Future<String> getToken() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_keyToken) ?? '';
  }

  static Future<void> save(String url, String token) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_keyUrl, url.trim());
    await p.setString(_keyToken, token.trim());
  }

  static Future<bool> isConfigured() async {
    final url = await getUrl();
    final token = await getToken();
    return url.isNotEmpty && token.isNotEmpty;
  }
}
