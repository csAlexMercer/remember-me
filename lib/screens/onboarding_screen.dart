import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/firebase_service.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn(BuildContext context) async {
    setState(() => _isLoading = true);
    final firebaseService = Provider.of<FirebaseService>(
      context,
      listen: false,
    );
    final user = await firebaseService.signInWithGoogle();

    if (mounted) {
      setState(() => _isLoading = false);
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sign in failed or was canceled.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      // If sign in is successful, AuthWrapper will automatically navigate to Dashboard.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 32.0,
                vertical: 48.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  // App logo
                  Container(
                    height: 150,
                    width: 150,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: theme.colorScheme.primary.withOpacity(0.2),
                          blurRadius: 30,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(18),
                    child: Image.asset('app_logo.png', fit: BoxFit.contain),
                  ),
                  const SizedBox(height: 48),

                  // Title
                  Text(
                    'Remember Me',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: -1,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Subtitle
                  Text(
                    'Designed for the ADHD brain.\nActive retrieval, not a data graveyard.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),

                  const Spacer(flex: 2),

                  // Sign in Button
                  _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : ElevatedButton.icon(
                          onPressed: () => _handleSignIn(context),
                          icon: const Icon(Icons.login),
                          label: const Text(
                            'Continue with Google',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: theme.colorScheme.primary,
                            foregroundColor: theme.colorScheme.onPrimary,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),

                  const SizedBox(height: 24),

                  // Privacy Note
                  Text(
                    'By continuing, you agree that your thoughts are safely synced to your account.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withOpacity(
                        0.7,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
