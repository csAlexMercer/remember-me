import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'theme/app_theme.dart';
import 'services/firebase_service.dart' as my_firebase;
import 'services/notification_service.dart';
import 'screens/dashboard_screen.dart';
import 'screens/onboarding_screen.dart';

import 'services/theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kDebugMode) {
    debugPrint('[main] app bootstrap: start');
  }

  // Initialize Hive for local settings storage
  await Hive.initFlutter();
  if (kDebugMode) {
    debugPrint('[main] Hive initialized');
  }

  // Initialize Firebase
  try {
    await Firebase.initializeApp();
    if (kDebugMode) {
      debugPrint('[main] Firebase initialized');
    }
  } catch (e) {
    print("Firebase initialization error: $e");
  }

  // Initialize Google Sign-In (required before any sign-in calls)
  await GoogleSignIn.instance.initialize();
  if (kDebugMode) {
    debugPrint('[main] Google Sign-In initialized');
  }

  // Initialize Notifications
  if (kDebugMode) {
    debugPrint('[main] NotificationService init: start');
  }
  await NotificationService().init();
  if (kDebugMode) {
    debugPrint('[main] NotificationService init: complete');
  }

  runApp(const RememberMeApp());
  if (kDebugMode) {
    debugPrint('[main] runApp complete');
  }
}

class RememberMeApp extends StatelessWidget {
  const RememberMeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<my_firebase.FirebaseService>(
          create: (_) => my_firebase.FirebaseService(),
        ),
        ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: 'Remember Me',
            theme: AppTheme.lightTheme(themeProvider.primaryColor),
            darkTheme: AppTheme.darkTheme(themeProvider.primaryColor),
            themeMode: themeProvider.themeMode,
            home: const AuthWrapper(),
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final firebaseService = Provider.of<my_firebase.FirebaseService>(
      context,
      listen: false,
    );

    return StreamBuilder<User?>(
      stream: firebaseService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasData) {
          return const DashboardScreen();
        }

        // Return Onboarding Screen for unauthenticated users
        return const OnboardingScreen();
      },
    );
  }
}
