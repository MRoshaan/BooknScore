import 'dart:developer' as developer;
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'providers/match_provider.dart';
import 'providers/tournament_provider.dart';
import 'services/auth_service.dart';
import 'services/sync_service.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';

// ══════════════════════════════════════════════════════════════════════════════
// SUPABASE CONFIGURATION
// Replace these with your actual Supabase project credentials
// ══════════════════════════════════════════════════════════════════════════════
const String supabaseUrl = 'https://cwqhnuzerggivwcrhiui.supabase.co';
const String supabaseAnonKey = 'sb_publishable_yhNNdwBIsVRjogAwNyHU0A_sD345Zeu';

// ══════════════════════════════════════════════════════════════════════════════
// BRAND PALETTE
// ══════════════════════════════════════════════════════════════════════════════
const Color primaryGreen   = Color(0xFF1B5E20);
const Color accentGreen    = Color(0xFF4CAF50);
const Color surfaceDark    = Color(0xFF0A0A0A);
const Color surfaceCard    = Color(0xFF1A1A1A);
const Color borderSubtle   = Color(0xFF2E4A2E);
const Color textPrimary    = Colors.white;
const Color textSecondary  = Color(0xFFB0B0B0);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Global error handlers ─────────────────────────────────────────────────
  // Catch all Flutter framework errors (layout, render, build-phase) and log
  // them instead of showing the default red "error" screen in production.
  FlutterError.onError = (FlutterErrorDetails details) {
    developer.log(
      'Flutter framework error',
      name: 'WicketPk.FlutterError',
      error: details.exception,
      stackTrace: details.stack,
      level: 1000, // SEVERE
    );
    // In debug builds, keep the default behaviour (prints red screen + logs).
    if (kDebugMode) {
      FlutterError.presentError(details);
    }
  };

  // Catch all asynchronous/platform errors that escape the Flutter zone.
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    developer.log(
      'Uncaught platform/async error',
      name: 'WicketPk.PlatformError',
      error: error,
      stackTrace: stack,
      level: 1000,
    );
    return true; // Mark as handled — prevents crash dialogs on Android.
  };

  // Set system UI overlay style for premium dark theme
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: surfaceDark,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Initialize Supabase
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  // Initialize auth service
  await AuthService.instance.initialize();

  // Initialize sync service (starts connectivity monitoring).
  // Must be called after Supabase.initialize() so the Supabase client exists.
  await SyncService.instance.initialize();

  runApp(const WicketPkApp());
}

class WicketPkApp extends StatelessWidget {
  const WicketPkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Auth Service - use create with existing instance to ensure proper lifecycle
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
      child: MaterialApp(
        title: 'Wicket.pk',
        debugShowCheckedModeBanner: false,
        theme: _buildDarkTheme(),
        home: const AuthGate(),
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: surfaceDark,
      primaryColor: primaryGreen,
      colorScheme: const ColorScheme.dark(
        primary: accentGreen,
        secondary: accentGreen,
        surface: surfaceCard,
        error: Color(0xFFD32F2F),
      ),
      
      // AppBar theme
      appBarTheme: AppBarTheme(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.rajdhani(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 1.2,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      
      // Card theme
      cardTheme: CardThemeData(
        color: surfaceCard,
        elevation: 4,
        shadowColor: Colors.black.withAlpha(60),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: borderSubtle, width: 1),
        ),
      ),
      
      // Input decoration theme
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1E1E1E),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accentGreen, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD32F2F)),
        ),
        labelStyle: GoogleFonts.rajdhani(
          color: textSecondary,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: GoogleFonts.rajdhani(color: textSecondary),
      ),
      
      // Elevated button theme
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentGreen,
          foregroundColor: Colors.white,
          elevation: 6,
          shadowColor: accentGreen.withAlpha(100),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.rajdhani(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
      ),
      
      // Text button theme
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accentGreen,
          textStyle: GoogleFonts.rajdhani(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      
      // Bottom navigation bar theme
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surfaceCard,
        selectedItemColor: accentGreen,
        unselectedItemColor: textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        selectedLabelStyle: GoogleFonts.rajdhani(
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
        unselectedLabelStyle: GoogleFonts.rajdhani(
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
      
      // Dialog theme
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        titleTextStyle: GoogleFonts.rajdhani(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: GoogleFonts.rajdhani(
          color: textSecondary,
          fontSize: 14,
        ),
      ),
      
      // Bottom sheet theme
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      
      // Floating action button theme
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accentGreen,
        foregroundColor: Colors.white,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      
      // Snackbar theme
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceCard,
        contentTextStyle: GoogleFonts.rajdhani(
          color: textPrimary,
          fontWeight: FontWeight.w600,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      
      // Progress indicator theme
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: accentGreen,
      ),
      
      // Text theme
      textTheme: GoogleFonts.rajdhaniTextTheme(
        ThemeData.dark().textTheme,
      ).apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
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
        // Show loading while checking auth state
        if (auth.isLoading && auth.currentUser == null) {
          return Scaffold(
            backgroundColor: surfaceDark,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // App logo/icon
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: primaryGreen,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: accentGreen.withAlpha(60),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.sports_cricket,
                      size: 50,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'WICKET.PK',
                    style: GoogleFonts.rajdhani(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: textPrimary,
                      letterSpacing: 4,
                    ),
                  ),
                  const SizedBox(height: 32),
                  const CircularProgressIndicator(color: accentGreen),
                ],
              ),
            ),
          );
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
