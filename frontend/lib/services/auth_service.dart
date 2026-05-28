import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/constants.dart';

class AuthService {
  // Use 10.0.2.2 for Android emulator to connect to localhost
  static String get baseUrl => AppConstants.baseUrl;
  static Map<String, dynamic>? currentUser;

  static Future<String?> login(String username, String password) async {
    try {
      final url = '$baseUrl/login';
      print('Attempting login to URL: $url');
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'X-App-Token': AppConstants.appToken,
        },
        body: jsonEncode({'username': username, 'password': password}),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        currentUser = data['user'];
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user', jsonEncode(currentUser));
        return null;
      } else {
        return 'Server status ${response.statusCode}: ${response.body}';
      }
    } catch (e) {
      print('Login Error: $e');
      return 'Error: $e (URL: $baseUrl/login)';
    }
  }

  static Future<void> logout() async {
    currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user');
  }

  static Future<void> loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userStr = prefs.getString('user');
    if (userStr != null) {
      currentUser = jsonDecode(userStr);
    }
  }

  static String get role => currentUser?['role'] ?? 'member';
  static int? get currentUserId => currentUser?['id'];
  static bool get isLoggedIn => currentUser != null;
}
