import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'firebase_options.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'utils/constants.dart';
import 'services/auth_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Global update info
  bool needsUpdate = false;
  String updateUrl = "";

  // Initialize Remote Config
  try {
    final remoteConfig = FirebaseRemoteConfig.instance;
    await remoteConfig.setConfigSettings(RemoteConfigSettings(
      fetchTimeout: const Duration(minutes: 1),
      minimumFetchInterval: const Duration(hours: 1), 
    ));
    // Set default values before fetching
    await remoteConfig.setDefaults(const {
      "api_url": "http://127.0.0.1:5000/api",
      "app_version": "1.0.0",
      "update_url": "",
    });
    await remoteConfig.fetchAndActivate();
    
    // Override local API URL with Remote Config API URL
    String remoteUrl = remoteConfig.getString('api_url');
    if (remoteUrl.isNotEmpty) {
      AppConstants.baseUrl = remoteUrl;
    }

    // Check for Updates
    const String currentVersion = "1.0.0";
    String latestVersion = remoteConfig.getString('app_version');
    updateUrl = remoteConfig.getString('update_url');
    needsUpdate = latestVersion != currentVersion && updateUrl.isNotEmpty;

  } catch (e) {
    debugPrint("Failed to fetch remote config: $e");
  }

  // Load Custom API URL if exists locally (overrides remote config for developer testing)
  final prefs = await SharedPreferences.getInstance();
  final customUrl = prefs.getString('custom_api_url');
  if (customUrl != null && customUrl.isNotEmpty) {
    AppConstants.baseUrl = customUrl;
  }
  
  // Initialize Global Notification Service with Navigator Key
  await NotificationService().init(navigatorKey: navigatorKey);
  
  // Initialize Auth Service
  await AuthService.loadUser();
  
  runApp(TribalApp(needsUpdate: needsUpdate, updateUrl: updateUrl));
}

class TribalApp extends StatelessWidget {
  final bool needsUpdate;
  final String updateUrl;
  
  const TribalApp({super.key, this.needsUpdate = false, this.updateUrl = ""});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'ميثاق الدية العشائرية لعشائر البو حمدان',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      // Responsive: clamp text scale to prevent huge text on mobile/tablet
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        // Clamp text scale factor between 0.85 and 1.1
        final clampedTextScaler = mediaQuery.textScaler.clamp(
          minScaleFactor: 0.85,
          maxScaleFactor: 1.1,
        );
        return MediaQuery(
          data: mediaQuery.copyWith(textScaler: clampedTextScaler),
          child: child!,
        );
      },
      home: SplashScreen(needsUpdate: needsUpdate, updateUrl: updateUrl),
    );
  }
}
