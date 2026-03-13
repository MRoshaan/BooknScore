import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';
import '../theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).appColors;

    return Scaffold(
      backgroundColor: c.surface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Settings'),
        backgroundColor: kAccentDark,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── Section header ─────────────────────────────────────────────────
          _SectionHeader(label: 'APPEARANCE', c: c),
          const SizedBox(height: 12),

          // ── Theme tile ─────────────────────────────────────────────────────
          _ThemeModeTile(c: c),

          const SizedBox(height: 32),

          // ── About section ──────────────────────────────────────────────────
          _SectionHeader(label: 'ABOUT', c: c),
          const SizedBox(height: 12),
          _InfoTile(
            icon: Icons.sports_cricket_outlined,
            label: 'BooknScore',
            value: 'Cricket scoring, your way',
            c: c,
          ),
          const SizedBox(height: 8),
          _InfoTile(
            icon: Icons.info_outline,
            label: 'Version',
            value: '2.0.0',
            c: c,
          ),
        ],
      ),
    );
  }
}

// ── Section header ─────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.c});
  final String label;
  final AppColors c;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: GoogleFonts.rajdhani(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: c.accent,
        letterSpacing: 2.5,
      ),
    );
  }
}

// ── Theme mode tile ────────────────────────────────────────────────────────────

class _ThemeModeTile extends StatelessWidget {
  const _ThemeModeTile({required this.c});
  final AppColors c;

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<ThemeProvider>();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: c.accent.withAlpha(25),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.accent.withAlpha(60), width: 1),
                ),
                child: Icon(Icons.palette_outlined, color: c.accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'App Theme',
                      style: GoogleFonts.rajdhani(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                    Text(
                      'Choose how BooknScore looks',
                      style: GoogleFonts.rajdhani(
                        fontSize: 12,
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Segmented toggle ───────────────────────────────────────────────
          _ThemeSegmentedControl(
            current: tp.mode,
            c: c,
            onChanged: (mode) async {
              // Capture context-dependent values before the async gap.
              final platformBrightness = MediaQuery.platformBrightnessOf(context);
              final tp = context.read<ThemeProvider>();
              await tp.setMode(mode);
              // Update status bar brightness to match the new theme.
              final brightness = switch (mode) {
                ThemeMode.light => Brightness.dark,   // dark icons on light bar
                ThemeMode.dark  => Brightness.light,  // light icons on dark bar
                ThemeMode.system =>
                  platformBrightness == Brightness.light
                      ? Brightness.dark
                      : Brightness.light,
              };
              SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
                statusBarBrightness: brightness,
                statusBarIconBrightness: brightness,
              ));
            },
          ),
        ],
      ),
    );
  }
}

// ── Segmented control ──────────────────────────────────────────────────────────

class _ThemeSegmentedControl extends StatelessWidget {
  const _ThemeSegmentedControl({
    required this.current,
    required this.c,
    required this.onChanged,
  });

  final ThemeMode current;
  final AppColors c;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: ThemeProvider.allModes.map((mode) {
        final isSelected = mode == current;
        final isFirst = mode == ThemeProvider.allModes.first;
        final isLast  = mode == ThemeProvider.allModes.last;

        final radius = BorderRadius.horizontal(
          left:  Radius.circular(isFirst ? 10 : 0),
          right: Radius.circular(isLast  ? 10 : 0),
        );

        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(mode),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? c.accent : c.card2,
                borderRadius: radius,
                border: Border.all(
                  color: isSelected ? c.accent : c.border,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _iconFor(mode),
                    size: 20,
                    color: isSelected ? _iconFgFor(c) : c.textSecondary,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ThemeProvider.label(mode),
                    style: GoogleFonts.rajdhani(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? _iconFgFor(c) : c.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  IconData _iconFor(ThemeMode mode) => switch (mode) {
        ThemeMode.system => Icons.brightness_auto,
        ThemeMode.light  => Icons.light_mode_outlined,
        ThemeMode.dark   => Icons.dark_mode_outlined,
      };

  /// Icon / text foreground when the segment is selected.
  /// In light theme the accent is dark green → use white.
  /// In dark theme the accent is mid-green → use black.
  Color _iconFgFor(AppColors c) {
    // accent == kAccentDark (0xFF1B5E20) in light theme → needs white fg
    // accent == kAccentGreen (0xFF4CAF50) in dark theme → needs black fg
    return c.accent == kAccentDark ? Colors.white : Colors.black;
  }
}

// ── Info tile ─────────────────────────────────────────────────────────────────

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.c,
  });

  final IconData icon;
  final String label;
  final String value;
  final AppColors c;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border, width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, color: c.accent, size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.rajdhani(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.rajdhani(
              fontSize: 13,
              color: c.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
