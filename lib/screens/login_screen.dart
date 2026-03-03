import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';

// ── Brand Palette ────────────────────────────────────────────────────────────
const Color _primaryGreen  = Color(0xFF1B5E20);
const Color _accentGreen   = Color(0xFF4CAF50);
const Color _surfaceDark   = Color(0xFF0A0A0A);
// ignore: unused_element
const Color _surfaceCard   = Color(0xFF1A1A1A);
const Color _glassBg       = Color(0x1A4CAF50);
const Color _glassBorder   = Color(0x334CAF50);
const Color _inputFill     = Color(0xFF1E1E1E);
const Color _hintColor     = Color(0xFF757575);
const Color _textPrimary   = Colors.white;
const Color _textSecondary = Color(0xFFB0B0B0);
const Color _errorRed      = Color(0xFFD32F2F);

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _displayNameCtrl = TextEditingController();
  
  bool _isSignUp = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _displayNameCtrl.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _toggleMode() {
    setState(() {
      _isSignUp = !_isSignUp;
      _formKey.currentState?.reset();
      context.read<AuthService>().clearError();
    });
    _animController.reset();
    _animController.forward();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthService>();
    
    bool success;
    if (_isSignUp) {
      success = await auth.signUpWithEmail(
        email: _emailCtrl.text,
        password: _passwordCtrl.text,
        displayName: _displayNameCtrl.text.trim().isNotEmpty 
            ? _displayNameCtrl.text.trim() 
            : null,
      );
      
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Account created! Please verify your email.',
              style: GoogleFonts.rajdhani(fontWeight: FontWeight.w600),
            ),
            backgroundColor: _accentGreen,
          ),
        );
      }
    } else {
      success = await auth.signInWithEmail(
        email: _emailCtrl.text,
        password: _passwordCtrl.text,
      );
    }

    if (!success && mounted) {
      // Error is shown via Consumer
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please enter your email first',
            style: GoogleFonts.rajdhani(fontWeight: FontWeight.w600),
          ),
          backgroundColor: _errorRed,
        ),
      );
      return;
    }

    final auth = context.read<AuthService>();
    final success = await auth.sendPasswordResetEmail(email);
    
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Password reset email sent!',
            style: GoogleFonts.rajdhani(fontWeight: FontWeight.w600),
          ),
          backgroundColor: _accentGreen,
        ),
      );
    }
  }

  Future<void> _signInWithGoogle() async {
    final auth = context.read<AuthService>();
    final success = await auth.signInWithGoogle();
    if (!success && mounted && auth.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            auth.error!,
            style: GoogleFonts.rajdhani(fontWeight: FontWeight.w600),
          ),
          backgroundColor: _errorRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surfaceDark,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: FadeTransition(
            opacity: _fadeAnim,
            child: Column(
              children: [
                const SizedBox(height: 60),
                
                // ── Logo Section ─────────────────────────────────────────────
                _buildLogo(),
                const SizedBox(height: 48),
                
                // ── Form Card ────────────────────────────────────────────────
                _buildFormCard(),
                const SizedBox(height: 24),
                
                // ── Toggle Mode ──────────────────────────────────────────────
                _buildToggleMode(),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        // App icon
        Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_primaryGreen, _accentGreen],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: _accentGreen.withAlpha(80),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(
            Icons.sports_cricket,
            size: 45,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 20),
        
        // App name
        Text(
          'WICKET.PK',
          style: GoogleFonts.rajdhani(
            fontSize: 32,
            fontWeight: FontWeight.w900,
            color: _textPrimary,
            letterSpacing: 5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Professional Cricket Scoring',
          style: GoogleFonts.rajdhani(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: _textSecondary,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildFormCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _glassBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _glassBorder, width: 1),
          ),
          child: Consumer<AuthService>(
            builder: (context, auth, _) {
              return Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Text(
                      _isSignUp ? 'Create Account' : 'Welcome Back',
                      style: GoogleFonts.rajdhani(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: _textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isSignUp 
                          ? 'Sign up to start scoring matches'
                          : 'Sign in to continue',
                      style: GoogleFonts.rajdhani(
                        fontSize: 14,
                        color: _textSecondary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Error message
                    if (auth.error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _errorRed.withAlpha(30),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _errorRed.withAlpha(80)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, color: _errorRed, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                auth.error!,
                                style: GoogleFonts.rajdhani(
                                  color: _errorRed,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    
                    // Display name (sign up only)
                    if (_isSignUp) ...[
                      TextFormField(
                        controller: _displayNameCtrl,
                        textCapitalization: TextCapitalization.words,
                        style: GoogleFonts.rajdhani(
                          color: _textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: _inputDecoration(
                          label: 'Display Name',
                          hint: 'Your name',
                          icon: Icons.person_outline,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    
                    // Email
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      style: GoogleFonts.rajdhani(
                        color: _textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: _inputDecoration(
                        label: 'Email',
                        hint: 'your@email.com',
                        icon: Icons.email_outlined,
                      ),
                      validator: AuthService.validateEmail,
                    ),
                    const SizedBox(height: 16),
                    
                    // Password
                    TextFormField(
                      controller: _passwordCtrl,
                      obscureText: _obscurePassword,
                      style: GoogleFonts.rajdhani(
                        color: _textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: _inputDecoration(
                        label: 'Password',
                        hint: '••••••••',
                        icon: Icons.lock_outline,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword 
                                ? Icons.visibility_off 
                                : Icons.visibility,
                            color: _hintColor,
                            size: 20,
                          ),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      validator: AuthService.validatePassword,
                    ),
                    
                    // Confirm password (sign up only)
                    if (_isSignUp) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _confirmPasswordCtrl,
                        obscureText: _obscureConfirmPassword,
                        style: GoogleFonts.rajdhani(
                          color: _textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: _inputDecoration(
                          label: 'Confirm Password',
                          hint: '••••••••',
                          icon: Icons.lock_outline,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirmPassword 
                                  ? Icons.visibility_off 
                                  : Icons.visibility,
                              color: _hintColor,
                              size: 20,
                            ),
                            onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                          ),
                        ),
                        validator: (v) => AuthService.validateConfirmPassword(v, _passwordCtrl.text),
                      ),
                    ],
                    
                    // Forgot password (sign in only)
                    if (!_isSignUp) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _forgotPassword,
                          child: Text(
                            'Forgot Password?',
                            style: GoogleFonts.rajdhani(
                              color: _accentGreen,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    
                     // Submit button
                    SizedBox(
                      height: 54,
                      child: ElevatedButton(
                        onPressed: auth.isLoading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accentGreen,
                          disabledBackgroundColor: _accentGreen.withAlpha(100),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: auth.isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _isSignUp ? Icons.person_add : Icons.login,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    _isSignUp ? 'Create Account' : 'Sign In',
                                    style: GoogleFonts.rajdhani(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),

                    // ── Divider ──────────────────────────────────────────
                    if (!_isSignUp) ...[
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          const Expanded(child: Divider(color: Color(0xFF2A2A2A))),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'OR',
                              style: GoogleFonts.rajdhani(
                                color: _hintColor,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const Expanded(child: Divider(color: Color(0xFF2A2A2A))),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ── Google Sign-In button ─────────────────────────
                      SizedBox(
                        height: 54,
                        child: OutlinedButton(
                          onPressed: auth.isLoading ? null : _signInWithGoogle,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _textPrimary,
                            side: const BorderSide(color: Color(0xFF2A2A2A), width: 1.5),
                            backgroundColor: _inputFill,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Google "G" logo rendered with coloured squares
                              SizedBox(
                                width: 22,
                                height: 22,
                                child: CustomPaint(painter: _GoogleLogoPainter()),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Sign in with Google',
                                style: GoogleFonts.rajdhani(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: _textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildToggleMode() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          _isSignUp ? 'Already have an account?' : "Don't have an account?",
          style: GoogleFonts.rajdhani(
            color: _textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        TextButton(
          onPressed: _toggleMode,
          child: Text(
            _isSignUp ? 'Sign In' : 'Sign Up',
            style: GoogleFonts.rajdhani(
              color: _accentGreen,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    String? hint,
    IconData? icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon != null ? Icon(icon, color: _hintColor, size: 20) : null,
      suffixIcon: suffixIcon,
      labelStyle: GoogleFonts.rajdhani(
        color: _hintColor,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: GoogleFonts.rajdhani(color: _hintColor),
      filled: true,
      fillColor: _inputFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _accentGreen, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _errorRed),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _errorRed, width: 2),
      ),
    );
  }
}

// ── Google "G" logo painter ──────────────────────────────────────────────────
// Draws the four-colour Google "G" using a simple arc-based approach so we
// avoid bundling an image asset just for the sign-in button.
class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double cx = size.width / 2;
    final double cy = size.height / 2;
    final double radius = size.width / 2;

    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: radius);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.38
      ..strokeCap = StrokeCap.butt;

    // Red arc (top-right)
    paint.color = const Color(0xFFEA4335);
    canvas.drawArc(rect, -1.57, 1.57, false, paint); // 12 o'clock → 3 o'clock

    // Yellow arc (bottom-right)
    paint.color = const Color(0xFFFBBC05);
    canvas.drawArc(rect, 0.0, 1.57, false, paint); // 3 → 6

    // Green arc (bottom-left)
    paint.color = const Color(0xFF34A853);
    canvas.drawArc(rect, 1.57, 1.57, false, paint); // 6 → 9

    // Blue arc (top-left)
    paint.color = const Color(0xFF4285F4);
    canvas.drawArc(rect, 3.14, 1.57, false, paint); // 9 → 12

    // Blue horizontal bar for the "G" crossbar
    final barPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..strokeWidth = radius * 0.38
      ..strokeCap = StrokeCap.square;
    canvas.drawLine(
      Offset(cx, cy),
      Offset(cx + radius, cy),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
