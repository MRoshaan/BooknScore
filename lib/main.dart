import 'dart:developer' as developer;
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // Added dotenv import

import 'providers/match_provider.dart';
import 'providers/tournament_provider.dart';
import 'providers/theme_provider.dart';
import 'services/auth_service.dart';
import 'services/sync_service.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'theme.dart';

// ══════════════════════════════════════════════════════════════════════════════
// BRAND PALETTE (kept for _SplashScreen which renders before theme is active)
// ══════════════════════════════════════════════════════════════════════════════
const Color primaryGreen   = Color(0xFF1B5E20);
const Color accentGreen    = Color(0xFF4CAF50);
const Color surfaceDark    = Color(0xFF0A0A0A);
const Color surfaceCard    = Color(0xFF1A1A1A);
const Color borderSubtle   = Color(0xFF2E4A2E);
const Color textPrimary    = Colors.white;
const Color textSecondary  = Color(0xFFB0B0B0);

// Singleton ThemeProvider — created once in main() so it can be loaded
// (SharedPreferences read) before runApp is called.
final ThemeProvider _themeProvider = ThemeProvider();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Global error handlers ─────────────────────────────────────────────────
  FlutterError.onError = (FlutterErrorDetails details) {
    developer.log(
      'Flutter framework error',
      name: 'BooknScore.FlutterError',
      error: details.exception,
      stackTrace: details.stack,
      level: 1000,
    );
    if (kDebugMode) {
      FlutterError.presentError(details);
    }
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    developer.log(
      'Uncaught platform/async error',
      name: 'BooknScore.PlatformError',
      error: error,
      stackTrace: stack,
      level: 1000,
    );
    return true;
  };

  // Load persisted theme before the first frame.
  await _themeProvider.load();

  // System UI overlay — updated reactively in WicketPkApp based on theme.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: surfaceDark,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Load environment variables
  await dotenv.load(fileName: ".env");

  // Initialize Supabase using hidden keys
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  // Initialize auth service
  await AuthService.instance.initialize();

  // Initialize sync service (starts connectivity monitoring).
  await SyncService.instance.initialize();

  runApp(const WicketPkApp());
}

class WicketPkApp extends StatelessWidget {
  const WicketPkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Theme — registered first so MaterialApp can consume it.
        ChangeNotifierProvider<ThemeProvider>.value(value: _themeProvider),
        // Auth Service
        ChangeNotifierProvider<AuthService>(
          create: (_) => AuthService.instance,
        ),
        // Match Provider
        ChangeNotifierProvider<MatchProvider>(
          create: (_) => MatchProvider(),
        ),
        // Tournament Provider
        ChangeNotifierProvider<TournamentProvider>(
          create: (_) => TournamentProvider(),
        ),
        // Sync Service
        ChangeNotifierProvider<SyncService>(
          create: (_) => SyncService(),
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: 'BooknScore',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: themeProvider.mode,
            home: const AuthGate(),
          );
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// AUTH GATE
// Redirects to Login or Dashboard based on auth state
// ══════════════════════════════════════════════════════════════════════════════

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, auth, _) {
        // Show animated splash while checking auth state
        if (auth.isLoading && auth.currentUser == null) {
          return const _SplashScreen();
        }

        // Route based on auth state
        if (auth.isAuthenticated) {
          return const DashboardScreen();
        } else {
          return const LoginScreen();
        }
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SPLASH SCREEN
// ══════════════════════════════════════════════════════════════════════════════

class _SplashScreen extends StatefulWidget {
  const _SplashScreen();

  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.6, curve: Curves.easeOut)),
    );
    _scaleAnim = Tween<double>(begin: 0.72, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.7, curve: Curves.easeOutBack)),
    );
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: surfaceDark,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: ScaleTransition(
            scale: _scaleAnim,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Radial glow behind logo ──────────────────────────
                Stack(
                  alignment: Alignment.center,
                  children: [
                    // Soft dark-green radial glow
                    Container(
                      width: 180,
                      height: 180,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            const Color(0xFF39FF14).withAlpha(40),
                            const Color(0xFF1B5E20).withAlpha(20),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.5, 1.0],
                        ),
                      ),
                    ),
                    // Logo container (120×120 — ~20 % bigger than old 100×100)
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [primaryGreen, accentGreen],
                        ),
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: accentGreen.withAlpha(80),
                            blurRadius: 28,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.sports_cricket,
                        size: 60,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                // ── App name ─────────────────────────────────────────
                Text(
                  'BOOKNSCORE', // <-- Updated Rebrand Here!
                  style: GoogleFonts.rajdhani(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: textPrimary,
                    letterSpacing: 5,
                  ),
                ),
                const SizedBox(height: 6),

                // ── Tagline ──────────────────────────────────────────
                Text(
                  'Score Every Ball.',
                  style: GoogleFonts.rajdhani(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: accentGreen,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 48),

                // ── Custom green dot loader ───────────────────────────
                const _GreenDotLoader(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Three animated dots that pulse left → middle → right in sequence.
class _GreenDotLoader extends StatefulWidget {
  const _GreenDotLoader();

  @override
  State<_GreenDotLoader> createState() => _GreenDotLoaderState();
}

class _GreenDotLoaderState extends State<_GreenDotLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            // Each dot leads by 0.33 of the cycle
            final phase = (_ctrl.value - i * 0.33).abs() % 1.0;
            // Scale 1.0 → 1.6 → 1.0 using a sine curve
            final scale = 1.0 + 0.6 * (0.5 - (phase - 0.5).abs()) * 2;
            final opacity = 0.35 + 0.65 * (0.5 - (phase - 0.5).abs()) * 2;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Opacity(
                opacity: opacity.clamp(0.35, 1.0),
                child: Transform.scale(
                  scale: scale.clamp(1.0, 1.6),
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: accentGreen,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}