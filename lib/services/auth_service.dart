import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'sync_service.dart';

/// Authentication service using Supabase Auth.
/// 
/// Provides:
/// - Email/password sign in and sign up
/// - Session management
/// - Auth state streaming
/// - User profile management
class AuthService extends ChangeNotifier {
  AuthService._();
  static final AuthService instance = AuthService._();

  SupabaseClient get _client => Supabase.instance.client;
  
  User? _currentUser;
  bool _isLoading = false;
  String? _error;
  StreamSubscription<AuthState>? _authSubscription;

  // ══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ══════════════════════════════════════════════════════════════════════════

  User? get currentUser => _currentUser;
  String? get userId => _currentUser?.id;
  String? get userEmail => _currentUser?.email;
  bool get isAuthenticated => _currentUser != null;
  bool get isLoading => _isLoading;
  String? get error => _error;
  
  Session? get currentSession => _client.auth.currentSession;
  
  /// Stream of auth state changes
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  // ══════════════════════════════════════════════════════════════════════════
  // INITIALIZATION
  // ══════════════════════════════════════════════════════════════════════════

  /// Initialize the auth service and listen for auth state changes.
  /// Note: Does NOT call notifyListeners() - that happens after provider setup.
  Future<void> initialize() async {
    _currentUser = _client.auth.currentUser;
    
    _authSubscription?.cancel();
    _authSubscription = _client.auth.onAuthStateChange.listen(_onAuthStateChange);
    // Do NOT call notifyListeners() here - the provider isn't set up yet
  }

  /// Handle auth state changes asynchronously to avoid build-phase conflicts.
  void _onAuthStateChange(AuthState data) {
    final AuthChangeEvent event = data.event;
    final Session? session = data.session;
    
    if (event == AuthChangeEvent.signedIn) {
      _currentUser = session?.user;
      _error = null;
      // Kick off a full downward sync on every sign-in (including re-installs).
      // force:true bypasses the "skip if players exist" guard so community
      // matches are always downloaded regardless of local DB state.
      Future.microtask(
        () => SyncService.instance.syncDownInitialData(force: true),
      );
    } else if (event == AuthChangeEvent.signedOut) {
      _currentUser = null;
    } else if (event == AuthChangeEvent.tokenRefreshed) {
      _currentUser = session?.user;
    } else if (event == AuthChangeEvent.userUpdated) {
      _currentUser = session?.user;
    }
    
    // Use Future.microtask to defer notification outside build phase
    Future.microtask(() => notifyListeners());
  }

  /// Dispose of subscriptions.
  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SIGN IN
  // ══════════════════════════════════════════════════════════════════════════

  /// Sign in with email and password.
  Future<bool> signInWithEmail({
    required String email,
    required String password,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      
      if (response.user != null) {
        _currentUser = response.user;
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _error = 'Sign in failed. Please try again.';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } on AuthException catch (e) {
      _error = _parseAuthError(e);
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'An unexpected error occurred: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // GOOGLE SIGN IN
  // ══════════════════════════════════════════════════════════════════════════

  static const _webClientId =
      '545880533706-hgjvmnqeaqjvat1e6nup5uvmti92n7j1.apps.googleusercontent.com';

  /// A single GoogleSignIn instance pinned to the web/server client ID so that
  /// Google always includes an `idToken` (server-side OAuth flow).
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId: _webClientId,
  );

  /// Sign in with Google via Supabase OAuth.
  ///
  /// Uses the native Google Sign-In plugin to obtain an `idToken`, then
  /// exchanges it with Supabase for a session.  Returns `true` on success.
  Future<bool> signInWithGoogle() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      debugPrint('[AuthService] signInWithGoogle: starting. serverClientId=$_webClientId');

      // Sign out any previously cached account so the picker always appears
      // and a fresh token (with idToken) is guaranteed.
      await _googleSignIn.signOut();

      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      debugPrint('[AuthService] googleUser=$googleUser');
      debugPrint('[AuthService] googleUser.email=${googleUser?.email}');
      debugPrint('[AuthService] googleUser.displayName=${googleUser?.displayName}');
      debugPrint('[AuthService] googleUser.id=${googleUser?.id}');
      debugPrint('[AuthService] googleUser.serverAuthCode=${googleUser?.serverAuthCode}');

      if (googleUser == null) {
        // User cancelled the sign-in flow.
        debugPrint('[AuthService] signInWithGoogle: user cancelled.');
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      debugPrint('[AuthService] googleAuth.idToken=${googleAuth.idToken}');
      debugPrint('[AuthService] googleAuth.accessToken=${googleAuth.accessToken}');
      debugPrint('[AuthService] googleAuth.serverAuthCode=${googleAuth.serverAuthCode}');

      final idToken = googleAuth.idToken;
      if (idToken == null) {
        debugPrint('[AuthService] ERROR: idToken is null. '
            'Verify that the serverClientId matches the Web Client in Google Cloud Console '
            'and that the SHA-1 fingerprint is registered for this app.');
        _error = 'Google Sign-In failed: no ID token received.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      debugPrint('[AuthService] Exchanging idToken with Supabase...');
      final response = await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: googleAuth.accessToken,
      );

      debugPrint('[AuthService] Supabase response.user=${response.user}');

      if (response.user != null) {
        _currentUser = response.user;
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _error = 'Google Sign-In failed. Please try again.';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } on AuthException catch (e) {
      debugPrint('[AuthService] AuthException: ${e.message}');
      _error = _parseAuthError(e);
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e, st) {
      debugPrint('[AuthService] Unexpected error: $e\n$st');
      _error = 'Google Sign-In error: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SIGN UP
  // ══════════════════════════════════════════════════════════════════════════

  /// Sign up with email and password.
  Future<bool> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        data: displayName != null ? {'display_name': displayName} : null,
      );
      
      if (response.user != null) {
        _currentUser = response.user;
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _error = 'Sign up failed. Please try again.';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } on AuthException catch (e) {
      _error = _parseAuthError(e);
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'An unexpected error occurred: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SIGN OUT
  // ══════════════════════════════════════════════════════════════════════════

  /// Sign out the current user.
  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _client.auth.signOut();
      _currentUser = null;
      _error = null;
    } catch (e) {
      _error = 'Failed to sign out: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PASSWORD RESET
  // ══════════════════════════════════════════════════════════════════════════

  /// Send password reset email.
  Future<bool> sendPasswordResetEmail(String email) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _client.auth.resetPasswordForEmail(email.trim());
      _isLoading = false;
      notifyListeners();
      return true;
    } on AuthException catch (e) {
      _error = _parseAuthError(e);
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Failed to send reset email: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ══════════════════════════════════════════════════════════════════════════

  /// Clear any error messages.
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Parse Supabase auth errors into user-friendly messages.
  String _parseAuthError(AuthException e) {
    final message = e.message.toLowerCase();
    
    if (message.contains('invalid login credentials') || 
        message.contains('invalid email or password')) {
      return 'Invalid email or password';
    }
    if (message.contains('email not confirmed')) {
      return 'Please verify your email address';
    }
    if (message.contains('user already registered') ||
        message.contains('email already in use')) {
      return 'An account with this email already exists';
    }
    if (message.contains('password')) {
      return 'Password must be at least 6 characters';
    }
    if (message.contains('email')) {
      return 'Please enter a valid email address';
    }
    if (message.contains('network') || message.contains('connection')) {
      return 'Network error. Please check your connection';
    }
    if (message.contains('too many requests') || message.contains('rate limit')) {
      return 'Too many attempts. Please try again later';
    }
    
    return e.message;
  }

  /// Validate email format.
  static String? validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email is required';
    }
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value.trim())) {
      return 'Please enter a valid email';
    }
    return null;
  }

  /// Validate password.
  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }
    if (value.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }

  /// Validate confirm password.
  static String? validateConfirmPassword(String? value, String password) {
    if (value == null || value.isEmpty) {
      return 'Please confirm your password';
    }
    if (value != password) {
      return 'Passwords do not match';
    }
    return null;
  }
}