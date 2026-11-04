import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/constants/app_constants.dart';
import 'core/crypto/crypto_service.dart';
import 'core/database/database_service.dart';
import 'core/notifications/notification_service.dart';
import 'core/theme/app_theme.dart';
import 'services/connection_service.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/home/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize core offline services
  await CryptoService().init();
  await DatabaseService().database; // Warm up SQLite DB
  await NotificationService().init(); // Setup push notifications

  runApp(const OffmasApp());
}

class OffmasApp extends StatelessWidget {
  const OffmasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const _StartupRouter(),
    );
  }
}

/// Decides whether to show Onboarding or Home based on saved name.
class _StartupRouter extends StatefulWidget {
  const _StartupRouter();

  @override
  State<_StartupRouter> createState() => _StartupRouterState();
}

class _StartupRouterState extends State<_StartupRouter> {
  bool _checking = true;
  bool _hasName = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(AppConstants.prefDisplayName) ?? '';
    if (name.isNotEmpty) {
      await ConnectionService().init();
    }
    setState(() {
      _hasName = name.isNotEmpty;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: AppTheme.darkBackground,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_tethering,
                  color: AppTheme.primaryEmerald, size: 60),
              SizedBox(height: 20),
              Text(
                'OFFMAS',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4,
                ),
              ),
              SizedBox(height: 8),
              CircularProgressIndicator(
                color: AppTheme.primaryEmerald,
                strokeWidth: 2,
              ),
            ],
          ),
        ),
      );
    }

    return _hasName ? const HomeScreen() : const OnboardingScreen();
  }
}
