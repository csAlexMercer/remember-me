import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'theme/app_theme.dart';
import 'services/firebase_service.dart' as my_firebase;
import 'services/notification_service.dart';
import 'screens/dashboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase (Assuming user has placed google-services.json / GoogleService-Info.plist or using flutterfire config)
  // For Phase 1 we will try to catch initialization errors if not configured.
  try {
    await Firebase.initializeApp();
  } catch (e) {
    print("Firebase initialization error: \$e");
  }

  // Initialize Notifications
  await NotificationService().init();

  runApp(const RememberMeApp());
}

class RememberMeApp extends StatelessWidget {
  const RememberMeApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<my_firebase.FirebaseService>(
          create: (_) => my_firebase.FirebaseService(),
        ),
      ],
      child: MaterialApp(
        title: 'Remember Me',
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        home: const AuthWrapper(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final firebaseService = Provider.of<my_firebase.FirebaseService>(context, listen: false);

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

        // Auto sign-in anonymously for MVP
        firebaseService.signInAnonymously();
        
        return const Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text("Signing in..."),
              ],
            ),
          ),
        );
      },
    );
  }
}
