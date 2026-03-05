import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'dart:ui';

import '../providers/match_provider.dart';
import '../services/database_helper.dart';
import 'match_summary_screen.dart';
import 'scorecard_screen.dart';

// ── Brand Palette ────────────────────────────────────────────────────────────
const Color _primaryGreen  = Color(0xFF1B5E20);
const Color _accentGreen   = Color(0xFF4CAF50);
const Color _surfaceDark   = Color(0xFF0A0A0A);
const Color _surfaceCard   = Color(0xFF1A1A1A);
const Color _pitchGreen    = Color(0xFF0D3318);
const Color _glassBg       = Color(0x1A4CAF50);
const Color _glassBorder   = Color(0x334CAF50);
const Color _wicketRed     = Color(0xFFD32F2F);
const Color _extrasAmber   = Color(0xFFFFA000);
const Color _boundaryBlue  = Color(0xFF1565C0);
const Color _sixPurple     = Color(0xFF6A1B9A);
const Color _borderSubtle  = Color(0xFF2E4A2E);
const Color _textPrimary   = Colors.white;
const Color _textSecondary = Color(0xFFB0B0B0);
const Color _strikerGold   = Color(0xFFFFD700);
const Color _undoOrange    = Color(0xFFFF6B35);

class ScoringScreen extends StatefulWidget {
  const ScoringScreen({super.key, required this.matchId});

  final int matchId;

  @override
  State<ScoringScreen> createState() => _ScoringScreenState();
}

class _ScoringScreenState extends State<ScoringScreen> {
  // Track which dialogs are currently showing to prevent duplicates
  bool _isShowingOpeningDialog = false;
  bool _isShowingBatterDialog = false;
  bool _isShowingBowlerDialog = false;
  bool _isShowingInningsDialog = false;
  
  late MatchProvider _provider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _provider = context.read<MatchProvider>();
      _provider.addListener(_onProviderChanged);
      if (_provider.matchId != widget.matchId) {
        _provider.loadMatch(widget.matchId).then((_) {
          // After the match finishes loading, immediately check whether
          // the opening players dialog is needed. This handles the case
          // where the provider may not fire a change notification that
          // the listener catches in time (e.g. first-ever load).
          if (!mounted) return;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _checkAndShowDialogs();
          });
        });
      } else {
        // Match already loaded — check right now in case it needs players.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _checkAndShowDialogs();
        });
      }
    });
  }

  @override
  void dispose() {
    // Safely remove listener
    try {
      _provider.removeListener(_onProviderChanged);
    } catch (_) {
      // Provider might already be disposed
    }
    super.dispose();
  }

  void _onProviderChanged() {
    if (!mounted) return;
    
    // Schedule dialog checks for next frame to avoid build issues
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _checkAndShowDialogs();
    });
  }

  void _checkAndShowDialogs() {
    if (!mounted) return;
    
    final provider = context.read<MatchProvider>();
    
    // Match is over — no dialogs needed; the build() will show the
    // completion screen automatically via the matchEnded branch.
    if (provider.matchEnded || provider.matchStatus == 'completed') return;
    
    // Priority order: Opening players > New batter > New bowler > Innings change
    if (provider.needsOpeningPlayers && !_isShowingOpeningDialog) {
      _showOpeningPlayersDialog();
    } else if (provider.needsNewBatter && !_isShowingBatterDialog && !_isShowingOpeningDialog) {
      _showNewBatterModal();
    } else if (provider.needsNewBowler && !_isShowingBowlerDialog && !_isShowingOpeningDialog) {
      _showNewBowlerModal();
    } else if (provider.needsInningsChange && !_isShowingInningsDialog) {
      _showInningsChangeModal();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MatchProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading) {
          return Scaffold(
            backgroundColor: _surfaceDark,
            body: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: _accentGreen),
                  SizedBox(height: 20),
                  Text(
                    'Loading match...',
                    style: TextStyle(
                      fontSize: 16,
                      color: _textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        if (provider.error != null) {
          return Scaffold(
            backgroundColor: _surfaceDark,
            appBar: AppBar(
              backgroundColor: _primaryGreen,
              title: const Text('Error'),
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 64, color: _wicketRed),
                    const SizedBox(height: 16),
                    Text(
                      provider.error!,
                      style: GoogleFonts.rajdhani(
                        fontSize: 16,
                        color: _textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () => provider.loadMatch(widget.matchId),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accentGreen,
                      ),
                      child: Text(
                        'Retry',
                        style: GoogleFonts.rajdhani(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        if (provider.matchEnded) {
          return _buildMatchCompleteScreen(provider);
        }

        return Scaffold(
          backgroundColor: _surfaceDark,
          appBar: _buildAppBar(provider),
          body: Column(
            children: [
              // ── Top: Live Scoreboard — rebuilds on any score change ─────
              Expanded(
                flex: 6,
                child: _ScoreboardPanel(provider: provider),
              ),

              // ── Divider ─────────────────────────────────────────────────
              const _Divider(),

              // ── Commentary Feed ──────────────────────────────────────────
              Selector<MatchProvider, List<String>>(
                selector: (_, p) => p.commentary,
                shouldRebuild: (prev, next) => prev.length != next.length,
                builder: (ctx, feed, _) => _CommentaryFeed(entries: feed),
              ),

              // ── Bottom: Scoring Panel — targeted Selector rebuild ───────
              Expanded(
                flex: 5,
                child: Selector<MatchProvider, _ScoringPanelData>(
                  selector: (_, p) => _ScoringPanelData(
                    isProcessing: p.isProcessing,
                    needsNewBatter: p.needsNewBatter,
                    needsNewBowler: p.needsNewBowler,
                    needsOpeningPlayers: p.needsOpeningPlayers,
                    matchEnded: p.matchEnded,
                    matchStatus: p.matchStatus,
                    matchId: p.matchId,
                    teamA: p.teamA,
                    teamB: p.teamB,
                  ),
                  builder: (ctx, data, _) {
                    final p = ctx.read<MatchProvider>();
                    return _ScoringPanel(
                      provider: p,
                      panelData: data,
                      onUndo: () => _handleUndo(p),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMatchCompleteScreen(MatchProvider provider) {
    return Scaffold(
      backgroundColor: _surfaceDark,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_pitchGreen, _surfaceDark],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Trophy icon with glow
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        _strikerGold.withAlpha(50),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Icon(
                    Icons.emoji_events,
                    size: 100,
                    color: _strikerGold,
                  ),
                ),
                const SizedBox(height: 32),
                
                Text(
                  'MATCH COMPLETE',
                  style: GoogleFonts.rajdhani(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _accentGreen,
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 12),
                
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    provider.matchResult ?? 'Match Completed',
                    style: GoogleFonts.rajdhani(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: _textPrimary,
                      height: 1.2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 48),

                // View Summary button
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MatchSummaryScreen(
                          matchId: provider.matchId!,
                          teamA: provider.teamA,
                          teamB: provider.teamB,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.bar_chart),
                  label: Text(
                    'View Match Summary',
                    style: GoogleFonts.rajdhani(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _accentGreen,
                    side: const BorderSide(color: _accentGreen, width: 1.5),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // View Scorecard button
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ScorecardScreen(
                          matchId: provider.matchId!,
                          teamA: provider.teamA,
                          teamB: provider.teamB,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.table_chart),
                  label: Text(
                    'View Scorecard',
                    style: GoogleFonts.rajdhani(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _accentGreen,
                    side: const BorderSide(color: _accentGreen, width: 1.5),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                ElevatedButton.icon(
                  onPressed: () {
                    provider.clearMatch();
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.home),
                  label: Text(
                    'Back to Dashboard',
                    style: GoogleFonts.rajdhani(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accentGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(MatchProvider provider) {
    return AppBar(
      backgroundColor: _primaryGreen,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        onPressed: () {
          provider.clearMatch();
          Navigator.of(context).pop();
        },
        tooltip: 'Back',
      ),
      title: Column(
        children: [
          Text(
            '${provider.teamA}  vs  ${provider.teamB}',
            style: GoogleFonts.rajdhani(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 1.1,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: _accentGreen,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _accentGreen.withAlpha(150),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                provider.matchStatus == 'live' ? 'LIVE' : 'INNINGS ${provider.currentInnings}',
                style: GoogleFonts.rajdhani(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: _accentGreen,
                  letterSpacing: 3,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        // View Scorecard
        IconButton(
          icon: const Icon(Icons.table_chart, size: 22),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ScorecardScreen(
                matchId: provider.matchId!,
                teamA: provider.teamA,
                teamB: provider.teamB,
              ),
            ),
          ),
          tooltip: 'View Scorecard',
        ),
        // Swap strike manually
        IconButton(
          icon: const Icon(Icons.swap_horiz, size: 22),
          onPressed: () => provider.swapStrike(),
          tooltip: 'Swap strike',
        ),
        // Match settings (Tapeball Dynamics)
        IconButton(
          icon: const Icon(Icons.settings, size: 22),
          onPressed: () => _showMatchSettingsDialog(provider),
          tooltip: 'Match settings',
        ),
        // More options
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) => _handleMenuAction(value, provider),
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'end_innings', child: Text('End Innings')),
            const PopupMenuItem(value: 'end_match', child: Text('End Match')),
          ],
        ),
      ],
    );
  }

  void _showMatchSettingsDialog(MatchProvider provider) {
    final oversCtrl = TextEditingController(text: provider.totalOvers.toString());
    final squadCtrl = TextEditingController(text: provider.squadSize.toString());
    final formKey = GlobalKey<FormState>();

    showDialog<void>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: _surfaceCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.settings, color: _accentGreen, size: 22),
            const SizedBox(width: 12),
            Text(
              'Match Settings',
              style: GoogleFonts.rajdhani(
                color: _textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 20,
              ),
            ),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: oversCtrl,
                keyboardType: TextInputType.number,
                style: GoogleFonts.rajdhani(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
                decoration: InputDecoration(
                  labelText: 'Total Overs',
                  labelStyle: GoogleFonts.rajdhani(color: _textSecondary, fontWeight: FontWeight.w600),
                  prefixIcon: Icon(Icons.repeat, color: _accentGreen, size: 20),
                  filled: true,
                  fillColor: _surfaceDark,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: _borderSubtle),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: _borderSubtle),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: _accentGreen, width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  if (n == null || n < 1) return 'Enter a valid number of overs';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: squadCtrl,
                keyboardType: TextInputType.number,
                style: GoogleFonts.rajdhani(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
                decoration: InputDecoration(
                  labelText: 'Squad Size',
                  labelStyle: GoogleFonts.rajdhani(color: _textSecondary, fontWeight: FontWeight.w600),
                  prefixIcon: Icon(Icons.group, color: _accentGreen, size: 20),
                  filled: true,
                  fillColor: _surfaceDark,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: _borderSubtle),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: _borderSubtle),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: _accentGreen, width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  if (n == null || n < 2) return 'Minimum squad size is 2';
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: Text('Cancel', style: GoogleFonts.rajdhani(color: _textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _accentGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(dCtx);
              provider.updateMatchSettings(
                newOvers: int.parse(oversCtrl.text.trim()),
                newSquadSize: int.parse(squadCtrl.text.trim()),
              );
            },
            child: Text(
              'Save',
              style: GoogleFonts.rajdhani(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ),
        ],
      ),
    ).whenComplete(() {
      oversCtrl.dispose();
      squadCtrl.dispose();
    });
  }

  void _handleUndo(MatchProvider provider) async {
    if (provider.isProcessing) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surfaceCard,
        title: Row(
          children: [
            Icon(Icons.undo, color: _undoOrange, size: 24),
            const SizedBox(width: 12),
            Text(
              'Undo Last Ball?',
              style: GoogleFonts.rajdhani(
                color: _textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        content: Text(
          'This will reverse the last ball event including runs, wickets, and stats.',
          style: GoogleFonts.rajdhani(color: _textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.rajdhani(color: _textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Undo',
              style: GoogleFonts.rajdhani(
                color: _undoOrange,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      await provider.undoLastBall();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Last ball undone',
              style: GoogleFonts.rajdhani(fontWeight: FontWeight.w600),
            ),
            backgroundColor: _undoOrange,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _handleMenuAction(String action, MatchProvider provider) async {
    switch (action) {
      case 'end_innings':
        if (provider.currentInnings < 2) {
          final confirm = await _showConfirmDialog(
            'End Innings?',
            'This will start the second innings.',
          );
          if (confirm == true) {
            provider.endInnings();
          }
        }
        break;
      case 'end_match':
        final confirm = await _showConfirmDialog(
          'End Match?',
          'This will complete the match.',
        );
        if (confirm == true) {
          await provider.completeMatch();
        }
        break;
    }
  }

  Future<bool?> _showConfirmDialog(String title, String content) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surfaceCard,
        title: Text(
          title,
          style: GoogleFonts.rajdhani(
            color: _textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          content,
          style: GoogleFonts.rajdhani(color: _textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.rajdhani(color: _textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Confirm',
              style: GoogleFonts.rajdhani(color: _accentGreen),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // OPENING PLAYERS DIALOG (Striker, Non-Striker, Opening Bowler)
  // ═══════════════════════════════════════════════════════════════════════════

  void _showOpeningPlayersDialog() {
    if (!mounted || _isShowingOpeningDialog) return;
    _isShowingOpeningDialog = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _InitialPlayersDialog(
        onDismissed: () {
          _isShowingOpeningDialog = false;
        },
      ),
    ).then((_) {
      _isShowingOpeningDialog = false;
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // NEW BATTER MODAL (Text Entry)
  // ═══════════════════════════════════════════════════════════════════════════

  void _showNewBatterModal() {
    if (!mounted || _isShowingBatterDialog) return;
    _isShowingBatterDialog = true;

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _NewBatterModal(
        onDismissed: () {
          _isShowingBatterDialog = false;
        },
      ),
    ).then((_) {
      _isShowingBatterDialog = false;
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // NEW BOWLER MODAL (Text Entry)
  // ═══════════════════════════════════════════════════════════════════════════

  void _showNewBowlerModal() {
    if (!mounted || _isShowingBowlerDialog) return;
    _isShowingBowlerDialog = true;

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _NewBowlerModal(
        onDismissed: () {
          _isShowingBowlerDialog = false;
        },
      ),
    ).then((_) {
      _isShowingBowlerDialog = false;
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INNINGS CHANGE MODAL
  // ═══════════════════════════════════════════════════════════════════════════

  void _showInningsChangeModal() {
    if (!mounted || _isShowingInningsDialog) return;
    _isShowingInningsDialog = true;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        // Read provider with listen: false to avoid registering the dialog as a listener
        final provider = ctx.read<MatchProvider>();
        
        return AlertDialog(
          backgroundColor: _surfaceCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _accentGreen.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.sports_cricket, color: _accentGreen, size: 28),
              ),
              const SizedBox(width: 12),
              Text(
                'Innings Complete',
                style: GoogleFonts.rajdhani(
                  color: _textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Score summary card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _glassBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _glassBorder),
                ),
                child: Column(
                  children: [
                    Text(
                      provider.battingTeam.toUpperCase(),
                      style: GoogleFonts.rajdhani(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _accentGreen,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${provider.totalRuns}/${provider.totalWickets}',
                      style: GoogleFonts.rajdhani(
                        fontSize: 42,
                        fontWeight: FontWeight.w900,
                        color: _textPrimary,
                      ),
                    ),
                    Text(
                      '(${provider.oversDisplay} overs)',
                      style: GoogleFonts.rajdhani(
                        fontSize: 14,
                        color: _textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              // Target info
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _primaryGreen.withAlpha(40),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _primaryGreen.withAlpha(100)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.flag, color: _accentGreen, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${provider.bowlingTeam} needs ${provider.totalRuns + 1} to win',
                        style: GoogleFonts.rajdhani(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () {
                  // 1. Capture provider reference BEFORE closing the dialog
                  final providerRef = provider;
                  
                  // 2. Safely close the dialog first
                  if (ctx.mounted) {
                    Navigator.of(ctx).pop();
                  }
                  
                  // 3. Wait for dialog to completely unmount before triggering notifyListeners()
                  Future.delayed(const Duration(milliseconds: 100), () {
                    providerRef.endInnings();
                  });
                },
                icon: const Icon(Icons.play_arrow),
                label: Text(
                  'Start 2nd Innings',
                  style: GoogleFonts.rajdhani(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ).then((_) {
      _isShowingInningsDialog = false;
    });
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SCORING PANEL DATA (Selector value object — only the fields _ScoringPanel needs)
// ══════════════════════════════════════════════════════════════════════════════

class _ScoringPanelData {
  const _ScoringPanelData({
    required this.isProcessing,
    required this.needsNewBatter,
    required this.needsNewBowler,
    required this.needsOpeningPlayers,
    required this.matchEnded,
    required this.matchStatus,
    required this.matchId,
    required this.teamA,
    required this.teamB,
  });

  final bool isProcessing;
  final bool needsNewBatter;
  final bool needsNewBowler;
  final bool needsOpeningPlayers;
  final bool matchEnded;
  final String matchStatus;
  final int? matchId;
  final String teamA;
  final String teamB;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _ScoringPanelData &&
          isProcessing == other.isProcessing &&
          needsNewBatter == other.needsNewBatter &&
          needsNewBowler == other.needsNewBowler &&
          needsOpeningPlayers == other.needsOpeningPlayers &&
          matchEnded == other.matchEnded &&
          matchStatus == other.matchStatus &&
          matchId == other.matchId &&
          teamA == other.teamA &&
          teamB == other.teamB;

  @override
  int get hashCode => Object.hash(
        isProcessing,
        needsNewBatter,
        needsNewBowler,
        needsOpeningPlayers,
        matchEnded,
        matchStatus,
        matchId,
        teamA,
        teamB,
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// THIN DIVIDER (const widget)
// ══════════════════════════════════════════════════════════════════════════════

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) =>
      const ColoredBox(color: _borderSubtle, child: SizedBox(height: 1, width: double.infinity));
}

// ══════════════════════════════════════════════════════════════════════════════
// COMMENTARY FEED
// ══════════════════════════════════════════════════════════════════════════════

class _CommentaryFeed extends StatelessWidget {
  const _CommentaryFeed({required this.entries});

  final List<String> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 72,
      color: const Color(0xFF0D0D0D),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: ListView.builder(
        reverse: false,
        itemCount: entries.length > 5 ? 5 : entries.length,
        itemBuilder: (_, i) {
          final text = entries[i];
          // Highlight special events in different colours
          final isWicket = text.contains('OUT!');
          final isSix    = text.contains('SIX!');
          final isFour   = text.contains('FOUR!');

          final Color textColor = isWicket
              ? _wicketRed
              : isSix
                  ? _strikerGold
                  : isFour
                      ? _accentGreen
                      : _textSecondary;

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Text(
              text,
              style: GoogleFonts.robotoMono(
                fontSize: 11,
                color: textColor,
                fontWeight: (isWicket || isSix || isFour)
                    ? FontWeight.w700
                    : FontWeight.w400,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SCOREBOARD PANEL (Enhanced Glassmorphism)
// ══════════════════════════════════════════════════════════════════════════════

class _ScoreboardPanel extends StatelessWidget {
  const _ScoreboardPanel({required this.provider});

  final MatchProvider provider;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_pitchGreen, _surfaceDark],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              const SizedBox(height: 8),
              
              // Batting team label
              Text(
                provider.battingTeam.toUpperCase(),
                style: GoogleFonts.rajdhani(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _accentGreen,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 4),

              // Main score with glow effect
              ShaderMask(
                shaderCallback: (bounds) => LinearGradient(
                  colors: [_textPrimary, _textPrimary.withAlpha(200)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ).createShader(bounds),
                child: Text(
                  provider.scoreDisplay,
                  style: GoogleFonts.rajdhani(
                    fontSize: 72,
                    fontWeight: FontWeight.w900,
                    color: _textPrimary,
                    height: 1,
                    letterSpacing: -2,
                  ),
                ),
              ),
              const SizedBox(height: 4),

              // Overs, CRR, and RRR
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '(${provider.oversDisplay}',
                    style: GoogleFonts.rajdhani(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _textSecondary,
                    ),
                  ),
                  if (provider.totalOvers > 0)
                    Text(
                      ' / ${provider.totalOvers}',
                      style: GoogleFonts.rajdhani(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _textSecondary,
                      ),
                    ),
                  Text(
                    ' ov)',
                    style: GoogleFonts.rajdhani(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _textSecondary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  _buildStatBadge('CRR', provider.currentRunRateDisplay),
                  if (provider.currentInnings == 2 && provider.target != null) ...[
                    const SizedBox(width: 10),
                    _buildStatBadge('RRR', provider.requiredRunRateDisplay, highlight: true),
                  ],
                ],
              ),
              
              // Target info for 2nd innings
              if (provider.currentInnings == 2 && provider.target != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _accentGreen.withAlpha(30),
                        _accentGreen.withAlpha(10),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _accentGreen.withAlpha(50)),
                  ),
                  child: Text(
                    'Need ${provider.runsNeeded} from ${provider.ballsRemaining} balls',
                    style: GoogleFonts.rajdhani(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: _accentGreen,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),

              // ── Active Batters (Glassmorphism Card) ─────────────────────
              _buildBattersCard(context),
              const SizedBox(height: 10),

              // ── Current Bowler ──────────────────────────────────────────
              _buildBowlerCard(),
              const SizedBox(height: 10),

              // Stats row
              _buildStatsRow(),
              const SizedBox(height: 10),

              // Current over timeline
              _CurrentOverTimeline(balls: provider.currentOverBalls),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBattersCard(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _glassBg,
                _glassBg.withAlpha(10),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _glassBorder, width: 1),
          ),
          child: Column(
            children: [
              // Header row with Retire/Declare action
              Row(
                children: [
                  Icon(Icons.sports_cricket, color: _accentGreen, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    'BATTING',
                    style: GoogleFonts.rajdhani(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _textSecondary,
                      letterSpacing: 2,
                    ),
                  ),
                  const Spacer(),
                  // Retire / Declare button
                  GestureDetector(
                    onTap: () => _showRetireDeclareDialog(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _wicketRed.withAlpha(20),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _wicketRed.withAlpha(80), width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.logout, color: _wicketRed, size: 12),
                          const SizedBox(width: 4),
                          Text(
                            'RETIRE / DECLARE',
                            style: GoogleFonts.rajdhani(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: _wicketRed,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              
              // Striker
              _buildBatterRow(
                name: provider.strikerName,
                stats: provider.strikerStats,
                sr: provider.strikerStrikeRate,
                isStriker: true,
              ),
              const SizedBox(height: 8),
              
              // Non-striker
              _buildBatterRow(
                name: provider.nonStrikerName,
                stats: provider.nonStrikerStats,
                sr: provider.nonStrikerStrikeRate,
                isStriker: false,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRetireDeclareDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: _surfaceCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.logout, color: _wicketRed, size: 20),
            const SizedBox(width: 10),
            Text(
              'Retire / Declare',
              style: GoogleFonts.rajdhani(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
              ),
            ),
          ],
        ),
        content: Text(
          'Choose an action for the current striker:',
          style: GoogleFonts.rajdhani(
            fontSize: 15,
            color: _textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: Text(
              'Cancel',
              style: GoogleFonts.rajdhani(color: _textSecondary, fontWeight: FontWeight.w600),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dCtx);
              provider.recordWicket(wicketType: 'retired_hurt');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _extrasAmber,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(
              'Retire Hurt',
              style: GoogleFonts.rajdhani(fontWeight: FontWeight.w700),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dCtx);
              provider.endInnings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _wicketRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(
              'Declare Innings',
              style: GoogleFonts.rajdhani(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBatterRow({
    required String name,
    required Map<String, int> stats,
    required double sr,
    required bool isStriker,
  }) {
    return Row(
      children: [
        // Striker indicator
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: isStriker ? _strikerGold : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(
              color: isStriker ? _strikerGold : _borderSubtle,
              width: 2,
            ),
            boxShadow: isStriker
                ? [BoxShadow(color: _strikerGold.withAlpha(100), blurRadius: 6)]
                : null,
          ),
        ),
        const SizedBox(width: 10),
        
        // Name
        Expanded(
          flex: 3,
          child: Text(
            name,
            style: GoogleFonts.rajdhani(
              fontSize: 15,
              fontWeight: isStriker ? FontWeight.w800 : FontWeight.w600,
              color: isStriker ? _textPrimary : _textSecondary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        
        // Runs
        SizedBox(
          width: 42,
          child: Text(
            '${stats['runs']}',
            style: GoogleFonts.rajdhani(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: _textPrimary,
            ),
            textAlign: TextAlign.right,
          ),
        ),
        
        // Balls
        SizedBox(
          width: 32,
          child: Text(
            '(${stats['balls']})',
            style: GoogleFonts.rajdhani(
              fontSize: 12,
              color: _textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        
        // 4s
        _buildMiniStatBadge('${stats['fours']}', _boundaryBlue),
        const SizedBox(width: 4),
        
        // 6s
        _buildMiniStatBadge('${stats['sixes']}', _sixPurple),
        const SizedBox(width: 8),
        
        // SR
        SizedBox(
          width: 48,
          child: Text(
            sr.toStringAsFixed(1),
            style: GoogleFonts.rajdhani(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _textSecondary,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildMiniStatBadge(String value, Color color) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: color.withAlpha(40),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withAlpha(100), width: 1),
      ),
      alignment: Alignment.center,
      child: Text(
        value,
        style: GoogleFonts.rajdhani(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  Widget _buildBowlerCard() {
    final stats = provider.bowlerStats;
    final overs = stats['overs'] as int;
    final balls = stats['balls'] as int;
    final oversStr = balls > 0 ? '$overs.$balls' : '$overs.0';
    final economy = (stats['economy'] as double).toStringAsFixed(2);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _surfaceCard.withAlpha(180),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderSubtle.withAlpha(100), width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.sports_baseball, color: _textSecondary, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              provider.bowlerName,
              style: GoogleFonts.rajdhani(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Overs
          _buildBowlerStat('O', oversStr),
          const SizedBox(width: 14),
          // Maidens
          _buildBowlerStat('M', '${stats['maidens']}'),
          const SizedBox(width: 14),
          // Runs
          _buildBowlerStat('R', '${stats['runs']}'),
          const SizedBox(width: 14),
          // Wickets
          _buildBowlerStat('W', '${stats['wickets']}', color: _wicketRed),
          const SizedBox(width: 14),
          // Economy
          _buildBowlerStat('Econ', economy),
        ],
      ),
    );
  }

  Widget _buildBowlerStat(String label, String value, {Color? color}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: GoogleFonts.rajdhani(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: color ?? _textPrimary,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.rajdhani(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: _textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildStatBadge(String label, String value, {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: highlight ? _wicketRed.withAlpha(30) : _glassBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: highlight ? _wicketRed.withAlpha(80) : _glassBorder,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: GoogleFonts.rajdhani(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: _textSecondary,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.rajdhani(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: highlight ? _wicketRed : _accentGreen,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildMiniStat('4s', '${provider.fours}', _boundaryBlue),
        const SizedBox(width: 16),
        _buildMiniStat('6s', '${provider.sixes}', _sixPurple),
        const SizedBox(width: 16),
        _buildMiniStat('Extras', '${provider.extras}', _extrasAmber),
      ],
    );
  }

  Widget _buildMiniStat(String label, String value, Color color) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: color.withAlpha(40),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withAlpha(100), width: 1),
          ),
          alignment: Alignment.center,
          child: Text(
            value,
            style: GoogleFonts.rajdhani(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: GoogleFonts.rajdhani(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: _textSecondary,
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// CURRENT OVER TIMELINE
// ══════════════════════════════════════════════════════════════════════════════

class _CurrentOverTimeline extends StatelessWidget {
  const _CurrentOverTimeline({required this.balls});

  final List<BallEvent> balls;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'THIS OVER',
          style: GoogleFonts.rajdhani(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: Colors.white38,
            letterSpacing: 2.5,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 38,
          child: balls.isEmpty
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(6, (_) => _buildEmptySlot()),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: balls.map((ball) => _buildBallChip(ball)).toList(),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildEmptySlot() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: _surfaceCard.withAlpha(100),
        shape: BoxShape.circle,
        border: Border.all(color: _borderSubtle.withAlpha(50), width: 1),
      ),
      alignment: Alignment.center,
      child: Text(
        '•',
        style: GoogleFonts.rajdhani(
          fontSize: 14,
          color: _textSecondary.withAlpha(100),
        ),
      ),
    );
  }

  Widget _buildBallChip(BallEvent ball) {
    Color bgColor;
    Color borderColor;

    if (ball.isWicket) {
      bgColor = _wicketRed;
      borderColor = _wicketRed;
    } else if (ball.extraType == 'wide' || ball.extraType == 'no_ball') {
      bgColor = _extrasAmber.withAlpha(180);
      borderColor = _extrasAmber;
    } else if (ball.runsScored == 4 && ball.isBoundary) {
      bgColor = _boundaryBlue;
      borderColor = _boundaryBlue;
    } else if (ball.runsScored == 6 && ball.isBoundary) {
      bgColor = _sixPurple;
      borderColor = _sixPurple;
    } else {
      bgColor = _borderSubtle.withAlpha(180);
      borderColor = _borderSubtle;
    }

    final label = ball.displayLabel;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: bgColor.withAlpha(80),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: GoogleFonts.rajdhani(
          fontSize: label.length > 2 ? 8 : (label.length > 1 ? 10 : 13),
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SCORING PANEL (With Prominent UNDO Button)
// ══════════════════════════════════════════════════════════════════════════════

class _ScoringPanel extends StatefulWidget {
  const _ScoringPanel({
    required this.provider,
    required this.panelData,
    required this.onUndo,
  });

  final MatchProvider provider;
  final _ScoringPanelData panelData;
  final VoidCallback onUndo;

  @override
  State<_ScoringPanel> createState() => _ScoringPanelState();
}

class _ScoringPanelState extends State<_ScoringPanel> {
  bool _showExtras = false;

  @override
  Widget build(BuildContext context) {
    final provider = widget.provider;
    final data = widget.panelData;
    final isCompleted = data.matchEnded || data.matchStatus == 'completed';
    final isBlocked = data.needsNewBatter || data.needsNewBowler || data.needsOpeningPlayers;

    // When match is completed, show a read-only "View Match Summary" button
    // instead of the full scoring keypad.
    if (isCompleted) {
      return Container(
        color: const Color(0xFF0A0A0A),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Center(
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MatchSummaryScreen(
                    matchId: data.matchId!,
                    teamA: data.teamA,
                    teamB: data.teamB,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.bar_chart),
            label: Text(
              'View Match Summary',
              style: GoogleFonts.rajdhani(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF4CAF50),
              side: const BorderSide(color: Color(0xFF4CAF50), width: 1.5),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      );
    }

    return AbsorbPointer(
      absorbing: data.isProcessing || isBlocked,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: (data.isProcessing || isBlocked) ? 0.4 : 1.0,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            children: [
              // Section header with extras toggle AND undo button
              Row(
                children: [
                  // Undo button (prominent)
                  GestureDetector(
                    onTap: widget.onUndo,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _undoOrange.withAlpha(25),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _undoOrange.withAlpha(100), width: 1.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.undo, color: _undoOrange, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            'UNDO',
                            style: GoogleFonts.rajdhani(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: _undoOrange,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  
                  Text(
                    _showExtras ? 'EXTRAS' : 'SCORE THIS BALL',
                    style: GoogleFonts.rajdhani(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white38,
                      letterSpacing: 2,
                    ),
                  ),
                  const Spacer(),
                  
                  // Extras toggle — prominent ElevatedButton
                  ElevatedButton.icon(
                    onPressed: () => setState(() => _showExtras = !_showExtras),
                    icon: Icon(
                      _showExtras ? Icons.sports_cricket : Icons.add_circle_outline,
                      size: 16,
                    ),
                    label: Text(
                      _showExtras ? 'RUNS' : 'EXTRAS',
                      style: GoogleFonts.rajdhani(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _showExtras
                          ? _extrasAmber.withAlpha(180)
                          : _extrasAmber,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: _showExtras ? 0 : 4,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Main scoring grid
              Expanded(
                child: _showExtras
                    ? _buildExtrasGrid(provider)
                    : _buildRunsGrid(provider),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRunsGrid(MatchProvider provider) {
    return Column(
      children: [
        // Row 1: 0, 1, 2
        Expanded(
          child: Row(
            children: [
              _RunButton(label: '0', onTap: () => provider.recordRuns(0)),
              const SizedBox(width: 8),
              _RunButton(label: '1', onTap: () => provider.recordRuns(1)),
              const SizedBox(width: 8),
              _RunButton(label: '2', onTap: () => provider.recordRuns(2)),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Row 2: 3, 4, 6
        Expanded(
          child: Row(
            children: [
              _RunButton(label: '3', onTap: () => provider.recordRuns(3)),
              const SizedBox(width: 8),
              _RunButton(
                label: '4',
                color: _boundaryBlue,
                onTap: () => provider.recordRuns(4, isBoundary: true),
              ),
              const SizedBox(width: 8),
              _RunButton(
                label: '6',
                color: _sixPurple,
                onTap: () => provider.recordRuns(6, isBoundary: true),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Wicket button
        Expanded(
          child: _WicketButton(onTap: () => _showWicketDialog(provider)),
        ),
        const SizedBox(height: 8),

        // Quick extras row
        Expanded(
          child: Row(
            children: [
              _ExtrasButton(
                label: 'Wide',
                icon: Icons.swap_horiz,
                onTap: () => _showExtrasRunPicker(context, 'wide', provider),
              ),
              const SizedBox(width: 8),
              _ExtrasButton(
                label: 'No Ball',
                icon: Icons.block,
                onTap: () => _showExtrasRunPicker(context, 'no_ball', provider),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildExtrasGrid(MatchProvider provider) {
    return Column(
      children: [
        // Wide + runs
        Expanded(
          child: Row(
            children: [
              _ExtrasButton(
                label: 'Wide',
                icon: Icons.swap_horiz,
                onTap: () => _showExtrasRunPicker(context, 'wide', provider),
              ),
              const SizedBox(width: 8),
              _ExtrasButton(
                label: 'Wd +1',
                icon: Icons.add,
                onTap: () => _showExtrasRunPicker(context, 'wide', provider),
              ),
              const SizedBox(width: 8),
              _ExtrasButton(
                label: 'Wd +4',
                icon: Icons.looks_4,
                onTap: () => _showExtrasRunPicker(context, 'wide', provider),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // No ball + runs
        Expanded(
          child: Row(
            children: [
              _ExtrasButton(
                label: 'No Ball',
                icon: Icons.block,
                onTap: () => _showExtrasRunPicker(context, 'no_ball', provider),
              ),
              const SizedBox(width: 8),
              _ExtrasButton(
                label: 'Nb +1',
                icon: Icons.add,
                onTap: () => _showExtrasRunPicker(context, 'no_ball', provider),
              ),
              const SizedBox(width: 8),
              _ExtrasButton(
                label: 'Nb +4',
                icon: Icons.looks_4,
                onTap: () => _showExtrasRunPicker(context, 'no_ball', provider),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Byes
        Expanded(
          child: Row(
            children: [
              _ByeButton(label: '1 Bye', onTap: () => provider.recordBye(1)),
              const SizedBox(width: 8),
              _ByeButton(label: '2 Byes', onTap: () => provider.recordBye(2)),
              const SizedBox(width: 8),
              _ByeButton(label: '4 Byes', onTap: () => provider.recordBye(4)),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Leg byes
        Expanded(
          child: Row(
            children: [
              _LegByeButton(label: '1 Lb', onTap: () => provider.recordLegBye(1)),
              const SizedBox(width: 8),
              _LegByeButton(label: '2 Lb', onTap: () => provider.recordLegBye(2)),
              const SizedBox(width: 8),
              _LegByeButton(label: '4 Lb', onTap: () => provider.recordLegBye(4)),
            ],
          ),
        ),
      ],
    );
  }

  /// Shows a BottomSheet run-picker for Wide or No Ball extras.
  ///
  /// For Wide: all additional runs are extras.
  /// For No Ball: shows an "off bat / extras" sub-choice before the run picker
  /// so the caller can distinguish batter runs from pure extras.
  void _showExtrasRunPicker(
    BuildContext context,
    String extraType,
    MatchProvider provider,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _ExtrasRunPickerSheet(
        extraType: extraType,
        provider: provider,
      ),
    );
  }

  void _showWicketDialog(MatchProvider provider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: _surfaceCard.withAlpha(240),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              border: Border.all(color: _glassBorder),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _wicketRed.withAlpha(30),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.sports_cricket, color: _wicketRed, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'WICKET TYPE',
                      style: GoogleFonts.rajdhani(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _wicketTypeChip('Bowled', provider, ctx),
                    _wicketTypeChip('Caught', provider, ctx),
                    _wicketTypeChip('LBW', provider, ctx),
                    _wicketTypeChip('Run Out', provider, ctx),
                    _wicketTypeChip('Stumped', provider, ctx),
                    _wicketTypeChip('Hit Wicket', provider, ctx),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _wicketTypeChip(String type, MatchProvider provider, BuildContext ctx) {
    return GestureDetector(
      onTap: () {
        final wicketKey = type.toLowerCase().replaceAll(' ', '_');
        if (wicketKey == 'run_out') {
          Navigator.pop(ctx);
          _showRunOutDialog(provider);
        } else {
          Navigator.pop(ctx);
          provider.recordWicket(wicketType: wicketKey);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: _wicketRed.withAlpha(30),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _wicketRed.withAlpha(100), width: 1.5),
        ),
        child: Text(
          type,
          style: GoogleFonts.rajdhani(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: _wicketRed,
          ),
        ),
      ),
    );
  }

  void _showRunOutDialog(MatchProvider provider) {
    int _runsCompleted = 0;
    String _runType = 'off_bat'; // 'off_bat' | 'bye' | 'leg_bye'

    showDialog<void>(
      context: context,
      builder: (dCtx) => StatefulBuilder(
        builder: (dCtx, setDState) => AlertDialog(
          backgroundColor: _surfaceCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _wicketRed.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.directions_run, color: _wicketRed, size: 22),
              ),
              const SizedBox(width: 12),
              Text(
                'Run Out Details',
                style: GoogleFonts.rajdhani(
                  color: _textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Runs completed before run-out:',
                style: GoogleFonts.rajdhani(
                  color: _textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              // Runs selector: 0, 1, 2, 3
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [0, 1, 2, 3].map((n) {
                  final selected = _runsCompleted == n;
                  return GestureDetector(
                    onTap: () => setDState(() => _runsCompleted = n),
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: selected ? _wicketRed : _surfaceDark,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected ? _wicketRed : _borderSubtle,
                          width: 2,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$n',
                        style: GoogleFonts.rajdhani(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: selected ? Colors.white : _textSecondary,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              Text(
                'Run type:',
                style: GoogleFonts.rajdhani(
                  color: _textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                children: [
                  _runTypeChip('Off Bat', 'off_bat', _runType, (v) => setDState(() => _runType = v)),
                  _runTypeChip('Byes', 'bye', _runType, (v) => setDState(() => _runType = v)),
                  _runTypeChip('Leg Byes', 'leg_bye', _runType, (v) => setDState(() => _runType = v)),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: Text('Cancel', style: GoogleFonts.rajdhani(color: _textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _wicketRed,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                Navigator.pop(dCtx);
                final isOffBat = _runType == 'off_bat';
                provider.recordWicket(
                  wicketType: 'run_out',
                  runsScored: isOffBat ? _runsCompleted : 0,
                  extraType: isOffBat ? null : _runType,
                  extraRuns: isOffBat ? 0 : _runsCompleted,
                );
              },
              child: Text(
                'Confirm',
                style: GoogleFonts.rajdhani(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _runTypeChip(String label, String value, String current, void Function(String) onSelect) {
    final selected = current == value;
    return GestureDetector(
      onTap: () => onSelect(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _accentGreen.withAlpha(40) : _surfaceDark,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? _accentGreen : _borderSubtle,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.rajdhani(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: selected ? _accentGreen : _textSecondary,
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// BUTTON WIDGETS (Enhanced)
// ══════════════════════════════════════════════════════════════════════════════

class _RunButton extends StatelessWidget {
  const _RunButton({
    required this.label,
    required this.onTap,
    this.color,
  });

  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final bg = color ?? _surfaceCard;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color ?? _borderSubtle, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: (color ?? Colors.black).withAlpha(60),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.rajdhani(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _WicketButton extends StatelessWidget {
  const _WicketButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [_wicketRed, _wicketRed.withAlpha(180)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: _wicketRed.withAlpha(100),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.sports_cricket, color: Colors.white, size: 24),
            const SizedBox(width: 12),
            Text(
              'WICKET',
              style: GoogleFonts.rajdhani(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExtrasButton extends StatelessWidget {
  const _ExtrasButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: _extrasAmber.withAlpha(20),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _extrasAmber.withAlpha(120), width: 1.5),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: _extrasAmber, size: 20),
              const SizedBox(height: 4),
              Text(
                label,
                style: GoogleFonts.rajdhani(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: _extrasAmber,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ByeButton extends StatelessWidget {
  const _ByeButton({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.teal.withAlpha(20),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.teal.withAlpha(120), width: 1.5),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.rajdhani(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Colors.teal,
            ),
          ),
        ),
      ),
    );
  }
}

class _LegByeButton extends StatelessWidget {
  const _LegByeButton({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.cyan.withAlpha(20),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.cyan.withAlpha(120), width: 1.5),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.rajdhani(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Colors.cyan,
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// EXTRAS RUN PICKER SHEET
// ══════════════════════════════════════════════════════════════════════════════

/// A BottomSheet that lets the scorer pick how many additional runs to add
/// to a Wide or No Ball. For No Ball, a preceding "Off bat / Extras" choice
/// is shown first so the correct cricket-scoring rules can be applied.
class _ExtrasRunPickerSheet extends StatefulWidget {
  const _ExtrasRunPickerSheet({
    required this.extraType,
    required this.provider,
  });

  /// 'wide' or 'no_ball'
  final String extraType;
  final MatchProvider provider;

  @override
  State<_ExtrasRunPickerSheet> createState() => _ExtrasRunPickerSheetState();
}

class _ExtrasRunPickerSheetState extends State<_ExtrasRunPickerSheet> {
  // For no_ball only: null = not yet chosen, true = off bat, false = not off bat
  bool? _noBallOffBat;

  void _record(int additionalRuns) {
    final providerRef = widget.provider;

    if (context.mounted) Navigator.of(context).pop();

    Future.delayed(const Duration(milliseconds: 100), () {
      if (widget.extraType == 'wide') {
        providerRef.recordWide(additionalRuns: additionalRuns);
      } else {
        // no_ball
        final batterRuns = _noBallOffBat ?? false;
        providerRef.recordNoBall(
          additionalRuns: additionalRuns,
          batterRuns: batterRuns,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isWide = widget.extraType == 'wide';
    final title  = isWide ? 'WIDE' : 'NO BALL';
    final color  = _extrasAmber;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: _surfaceCard.withAlpha(240),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: _glassBorder),
          ),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withAlpha(30),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      isWide ? Icons.swap_horiz : Icons.block,
                      color: color,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    title,
                    style: GoogleFonts.rajdhani(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // No Ball: off-bat vs extras sub-choice
              if (!isWide) ...[
                Text(
                  'RUNS TYPE',
                  style: GoogleFonts.rajdhani(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _textSecondary,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _runTypeChip('Off Bat', _noBallOffBat == true, () {
                      setState(() => _noBallOffBat = true);
                    }),
                    const SizedBox(width: 10),
                    _runTypeChip('Extras', _noBallOffBat == false, () {
                      setState(() => _noBallOffBat = false);
                    }),
                  ],
                ),
                const SizedBox(height: 16),
              ],

              // Additional runs picker
              Text(
                'ADDITIONAL RUNS',
                style: GoogleFonts.rajdhani(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: _textSecondary,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),

              // Disable run buttons for no_ball until type is chosen
              AbsorbPointer(
                absorbing: !isWide && _noBallOffBat == null,
                child: AnimatedOpacity(
                  opacity: (!isWide && _noBallOffBat == null) ? 0.35 : 1.0,
                  duration: const Duration(milliseconds: 150),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [0, 1, 2, 3, 4, 6].map((runs) {
                      return GestureDetector(
                        onTap: () => _record(runs),
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: color.withAlpha(25),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: color.withAlpha(120), width: 1.5),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '$runs',
                            style: GoogleFonts.rajdhani(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: color,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _runTypeChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? _extrasAmber.withAlpha(50) : _glassBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? _extrasAmber : _glassBorder,
            width: selected ? 2 : 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.rajdhani(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: selected ? _extrasAmber : _textSecondary,
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// INITIAL PLAYERS DIALOG (Dedicated StatefulWidget for proper lifecycle)
// ══════════════════════════════════════════════════════════════════════════════

class _InitialPlayersDialog extends StatefulWidget {
  const _InitialPlayersDialog({required this.onDismissed});
  
  final VoidCallback onDismissed;

  @override
  State<_InitialPlayersDialog> createState() => _InitialPlayersDialogState();
}

class _InitialPlayersDialogState extends State<_InitialPlayersDialog> {
  late final TextEditingController _strikerController;
  late final TextEditingController _nonStrikerController;
  late final TextEditingController _bowlerController;
  final _formKey = GlobalKey<FormState>();

  List<String> _battingPlayers = [];
  List<String> _bowlingPlayers = [];

  @override
  void initState() {
    super.initState();
    _strikerController = TextEditingController();
    _nonStrikerController = TextEditingController();
    _bowlerController = TextEditingController();
    _loadPlayers();
  }

  Future<void> _loadPlayers() async {
    final provider = context.read<MatchProvider>();
    final batting = await DatabaseHelper.instance.fetchPlayersByTeam(provider.battingTeam);
    final bowling = await DatabaseHelper.instance.fetchPlayersByTeam(provider.bowlingTeam);
    if (!mounted) return;
    setState(() {
      _battingPlayers = batting.map((p) => p[DatabaseHelper.colName] as String).toList();
      _bowlingPlayers = bowling.map((p) => p[DatabaseHelper.colName] as String).toList();
    });
  }

  @override
  void dispose() {
    _strikerController.dispose();
    _nonStrikerController.dispose();
    _bowlerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _surfaceCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _primaryGreen.withAlpha(40),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.sports_cricket, color: _accentGreen, size: 28),
          ),
          const SizedBox(width: 12),
          Text(
            'Opening Players',
            style: GoogleFonts.rajdhani(
              color: _textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 20,
            ),
          ),
        ],
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              _buildAutocomplete(
                controller: _strikerController,
                suggestions: _battingPlayers,
                label: 'Striker',
                hint: 'Opening batter (striker)',
                icon: Icons.sports_cricket,
                iconColor: _strikerGold,
                validator: (v) {
                  final val = v?.trim() ?? '';
                  if (val.isEmpty) return 'Enter striker name';
                  final other = _nonStrikerController.text.trim();
                  if (other.isNotEmpty && val.toLowerCase() == other.toLowerCase()) {
                    return 'Striker and non-striker cannot be the same player';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _buildAutocomplete(
                controller: _nonStrikerController,
                suggestions: _battingPlayers,
                label: 'Non-Striker',
                hint: 'Opening batter (non-striker)',
                icon: Icons.sports_cricket,
                iconColor: _accentGreen,
                validator: (v) {
                  final val = v?.trim() ?? '';
                  if (val.isEmpty) return 'Enter non-striker name';
                  final other = _strikerController.text.trim();
                  if (other.isNotEmpty && val.toLowerCase() == other.toLowerCase()) {
                    return 'Cannot be the same as striker';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _buildAutocomplete(
                controller: _bowlerController,
                suggestions: _bowlingPlayers,
                label: 'Opening Bowler',
                hint: 'Bowler for first over',
                icon: Icons.sports_baseball,
                iconColor: _boundaryBlue,
                validator: (v) => v?.trim().isEmpty == true ? 'Enter bowler name' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: _handleSubmit,
            icon: const Icon(Icons.play_arrow),
            label: Text(
              'Start Match',
              style: GoogleFonts.rajdhani(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _accentGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAutocomplete({
    required TextEditingController controller,
    required List<String> suggestions,
    required String label,
    required String hint,
    required IconData icon,
    required Color iconColor,
    required String? Function(String?) validator,
  }) {
    InputDecoration decoration = InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: GoogleFonts.rajdhani(
        color: _textSecondary,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: GoogleFonts.rajdhani(
        color: _textSecondary.withAlpha(100),
      ),
      prefixIcon: Icon(icon, color: iconColor, size: 20),
      filled: true,
      fillColor: _surfaceDark,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: _borderSubtle),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: _borderSubtle),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: iconColor, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: _wicketRed),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );

    if (suggestions.isEmpty) {
      // No suggestions loaded yet — plain validated text field
      return TextFormField(
        controller: controller,
        style: GoogleFonts.rajdhani(fontSize: 16, fontWeight: FontWeight.w600, color: _textPrimary),
        decoration: decoration,
        validator: validator,
        textCapitalization: TextCapitalization.words,
      );
    }

    return Autocomplete<String>(
      optionsBuilder: (textEditingValue) {
        final query = textEditingValue.text.toLowerCase();
        if (query.isEmpty) return suggestions;
        return suggestions.where((s) => s.toLowerCase().startsWith(query));
      },
      onSelected: (selection) => controller.text = selection,
      fieldViewBuilder: (ctx, acController, focusNode, onSubmitted) {
        // Keep our external controller in sync
        acController.addListener(() {
          if (acController.text != controller.text) {
            controller.text = acController.text;
          }
        });
        return TextFormField(
          controller: acController,
          focusNode: focusNode,
          style: GoogleFonts.rajdhani(fontSize: 16, fontWeight: FontWeight.w600, color: _textPrimary),
          decoration: decoration,
          validator: (_) => validator(controller.text),
          textCapitalization: TextCapitalization.words,
          onFieldSubmitted: (_) => onSubmitted(),
        );
      },
      optionsViewBuilder: (ctx, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          color: _surfaceCard,
          borderRadius: BorderRadius.circular(10),
          elevation: 8,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: options.length,
              itemBuilder: (_, i) {
                final opt = options.elementAt(i);
                return InkWell(
                  onTap: () => onSelected(opt),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Text(
                      opt,
                      style: GoogleFonts.rajdhani(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _textPrimary,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required Color iconColor,
    required String? Function(String?) validator,
  }) {
    return TextFormField(
      controller: controller,
      style: GoogleFonts.rajdhani(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: _textPrimary,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: GoogleFonts.rajdhani(
          color: _textSecondary,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: GoogleFonts.rajdhani(
          color: _textSecondary.withAlpha(100),
        ),
        prefixIcon: Icon(icon, color: iconColor, size: 20),
        filled: true,
        fillColor: _surfaceDark,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _borderSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: iconColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _wicketRed),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      validator: validator,
      textCapitalization: TextCapitalization.words,
    );
  }

  void _handleSubmit() {
    if (!_formKey.currentState!.validate()) return;

    // 1. Capture values and provider reference BEFORE closing the dialog
    final provider = context.read<MatchProvider>();
    final strikerName = _strikerController.text.trim();
    final nonStrikerName = _nonStrikerController.text.trim();
    final bowlerName = _bowlerController.text.trim();

    // 2. Safely close the dialog
    if (context.mounted) {
      Navigator.of(context).pop();
    }

    // 3. Wait for dialog to completely unmount before triggering notifyListeners()
    Future.delayed(const Duration(milliseconds: 100), () {
      provider.setOpeningPlayers(
        strikerName: strikerName,
        nonStrikerName: nonStrikerName,
        bowlerName: bowlerName,
      );
    });
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// NEW BATTER MODAL (Dedicated StatefulWidget for proper lifecycle)
// ══════════════════════════════════════════════════════════════════════════════

class _NewBatterModal extends StatefulWidget {
  const _NewBatterModal({required this.onDismissed});
  
  final VoidCallback onDismissed;

  @override
  State<_NewBatterModal> createState() => _NewBatterModalState();
}

class _NewBatterModalState extends State<_NewBatterModal> {
  late final TextEditingController _controller;
  final _formKey = GlobalKey<FormState>();
  List<String> _suggestions = [];
  Set<String> _dismissedNames = {};

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _loadSuggestions();
  }

  Future<void> _loadSuggestions() async {
    final provider = context.read<MatchProvider>();
    final players = await DatabaseHelper.instance.fetchPlayersByTeam(provider.battingTeam);

    // Fetch dismissed player IDs for this innings so we can exclude them.
    Set<int> dismissedIds = {};
    if (provider.matchId != null) {
      dismissedIds = await DatabaseHelper.instance.fetchDismissedPlayerIds(
        provider.matchId!,
        provider.currentInnings,
      );
    }

    // Also exclude currently active batters (striker & non-striker).
    final activeIds = <int>{
      if (provider.strikerId != null) provider.strikerId!,
      if (provider.nonStrikerId != null) provider.nonStrikerId!,
    };

    // Build dismissed name set for validator (case-insensitive comparison).
    final dismissed = players
        .where((p) => dismissedIds.contains(p[DatabaseHelper.colId] as int))
        .map((p) => (p[DatabaseHelper.colName] as String).toLowerCase())
        .toSet();

    if (!mounted) return;
    setState(() {
      _dismissedNames = dismissed;
      _suggestions = players
          .where((p) {
            final id = p[DatabaseHelper.colId] as int;
            return !activeIds.contains(id) && !dismissedIds.contains(id);
          })
          .map((p) => p[DatabaseHelper.colName] as String)
          .toList();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    if (!_formKey.currentState!.validate()) return;

    // 1. Capture values and provider reference BEFORE closing the dialog
    final provider = context.read<MatchProvider>();
    final name = _controller.text.trim();

    // 2. Safely close the modal
    if (context.mounted) {
      Navigator.of(context).pop();
    }

    // 3. Wait for modal to completely unmount before triggering notifyListeners()
    Future.delayed(const Duration(milliseconds: 100), () {
      provider.setNewBatterWithName(name);
    });
  }

  InputDecoration _batterInputDecoration() {
    return InputDecoration(
      labelText: 'Batter Name',
      hintText: 'Enter new batter name',
      labelStyle: GoogleFonts.rajdhani(color: _textSecondary, fontWeight: FontWeight.w600),
      hintStyle: GoogleFonts.rajdhani(color: _textSecondary.withAlpha(100)),
      prefixIcon: Icon(Icons.person_add, color: _accentGreen, size: 22),
      filled: true,
      fillColor: _surfaceDark,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _borderSubtle),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _borderSubtle),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _accentGreen, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<MatchProvider>();
    
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: _surfaceCard.withAlpha(240),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              border: Border.all(color: _glassBorder),
            ),
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _wicketRed.withAlpha(30),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.sports_cricket, color: _wicketRed, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'WICKET!',
                              style: GoogleFonts.rajdhani(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: _wicketRed,
                                letterSpacing: 2,
                              ),
                            ),
                            Text(
                              'New Batter',
                              style: GoogleFonts.rajdhani(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: _textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Wickets badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _wicketRed.withAlpha(40),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _wicketRed.withAlpha(100)),
                        ),
                        child: Text(
                          '${provider.totalWickets}/${provider.squadSize - 1}',
                          style: GoogleFonts.rajdhani(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: _wicketRed,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Input field with autocomplete
                  if (_suggestions.isEmpty)
                    TextFormField(
                      controller: _controller,
                      autofocus: true,
                      style: GoogleFonts.rajdhani(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary,
                      ),
                      decoration: _batterInputDecoration(),
                      validator: (v) {
                        final name = v?.trim() ?? '';
                        if (name.isEmpty) return 'Enter batter name';
                        if (_dismissedNames.contains(name.toLowerCase())) {
                          return 'This player has already been dismissed';
                        }
                        final nonStriker = context.read<MatchProvider>().nonStrikerName.trim();
                        if (name.toLowerCase() == nonStriker.toLowerCase()) {
                          return 'New batter cannot be the current non-striker';
                        }
                        return null;
                      },
                      textCapitalization: TextCapitalization.words,
                      onFieldSubmitted: (_) => _handleSubmit(),
                    )
                  else
                    Autocomplete<String>(
                      optionsBuilder: (tev) {
                        final q = tev.text.toLowerCase();
                        if (q.isEmpty) return _suggestions;
                        return _suggestions.where((s) => s.toLowerCase().startsWith(q));
                      },
                      onSelected: (v) => _controller.text = v,
                      fieldViewBuilder: (ctx, acCtrl, focusNode, onSubmitted) {
                        acCtrl.addListener(() {
                          if (acCtrl.text != _controller.text) _controller.text = acCtrl.text;
                        });
                        return TextFormField(
                          controller: acCtrl,
                          focusNode: focusNode,
                          autofocus: true,
                          style: GoogleFonts.rajdhani(fontSize: 18, fontWeight: FontWeight.w700, color: _textPrimary),
                          decoration: _batterInputDecoration(),
                          validator: (_) {
                            final name = _controller.text.trim();
                            if (name.isEmpty) return 'Enter batter name';
                            if (_dismissedNames.contains(name.toLowerCase())) {
                              return 'This player has already been dismissed';
                            }
                            final nonStriker = context.read<MatchProvider>().nonStrikerName.trim();
                            if (name.toLowerCase() == nonStriker.toLowerCase()) {
                              return 'New batter cannot be the current non-striker';
                            }
                            return null;
                          },
                          textCapitalization: TextCapitalization.words,
                          onFieldSubmitted: (_) { onSubmitted(); _handleSubmit(); },
                        );
                      },
                      optionsViewBuilder: (ctx, onSelected, options) => Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          color: _surfaceCard,
                          borderRadius: BorderRadius.circular(10),
                          elevation: 8,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 180),
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: options.length,
                              itemBuilder: (_, i) {
                                final opt = options.elementAt(i);
                                return InkWell(
                                  onTap: () => onSelected(opt),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    child: Text(opt, style: GoogleFonts.rajdhani(fontSize: 15, fontWeight: FontWeight.w600, color: _textPrimary)),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),

                  // Submit button
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: _handleSubmit,
                      icon: const Icon(Icons.check, size: 22),
                      label: Text(
                        'SEND TO CREASE',
                        style: GoogleFonts.rajdhani(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accentGreen,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// NEW BOWLER MODAL (Dedicated StatefulWidget for proper lifecycle)
// ══════════════════════════════════════════════════════════════════════════════

class _NewBowlerModal extends StatefulWidget {
  const _NewBowlerModal({required this.onDismissed});
  
  final VoidCallback onDismissed;

  @override
  State<_NewBowlerModal> createState() => _NewBowlerModalState();
}

class _NewBowlerModalState extends State<_NewBowlerModal> {
  late final TextEditingController _controller;
  final _formKey = GlobalKey<FormState>();
  List<String> _suggestions = [];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _loadSuggestions();
  }

  Future<void> _loadSuggestions() async {
    final provider = context.read<MatchProvider>();
    final players = await DatabaseHelper.instance.fetchPlayersByTeam(provider.bowlingTeam);
    if (!mounted) return;
    setState(() {
      _suggestions = players.map((p) => p[DatabaseHelper.colName] as String).toList();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    if (!_formKey.currentState!.validate()) return;

    // 1. Capture values and provider reference BEFORE closing the dialog
    final provider = context.read<MatchProvider>();
    final name = _controller.text.trim();

    // 2. Safely close the modal
    if (context.mounted) {
      Navigator.of(context).pop();
    }

    // 3. Wait for modal to completely unmount before triggering notifyListeners()
    Future.delayed(const Duration(milliseconds: 100), () {
      provider.setNewBowlerWithName(name);
    });
  }

  InputDecoration _bowlerInputDecoration() {
    return InputDecoration(
      labelText: 'Bowler Name',
      hintText: 'Enter bowler name',
      labelStyle: GoogleFonts.rajdhani(color: _textSecondary, fontWeight: FontWeight.w600),
      hintStyle: GoogleFonts.rajdhani(color: _textSecondary.withAlpha(100)),
      prefixIcon: Icon(Icons.sports_baseball, color: _accentGreen, size: 22),
      filled: true,
      fillColor: _surfaceDark,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _borderSubtle),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _borderSubtle),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _accentGreen, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<MatchProvider>();
    
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: _surfaceCard.withAlpha(240),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              border: Border.all(color: _glassBorder),
            ),
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _accentGreen.withAlpha(30),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.sports_baseball, color: _accentGreen, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'END OF OVER ${provider.completedOvers}',
                              style: GoogleFonts.rajdhani(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: _accentGreen,
                                letterSpacing: 2,
                              ),
                            ),
                            Text(
                              'New Bowler',
                              style: GoogleFonts.rajdhani(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: _textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Overs badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _glassBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _glassBorder),
                        ),
                        child: Text(
                          'Over ${provider.completedOvers + 1}',
                          style: GoogleFonts.rajdhani(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: _accentGreen,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  
                  // Info text
                  Text(
                    'Enter the name of the bowler for the next over',
                    style: GoogleFonts.rajdhani(
                      fontSize: 13,
                      color: _textSecondary,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Input field with autocomplete
                  if (_suggestions.isEmpty)
                    TextFormField(
                      controller: _controller,
                      autofocus: true,
                      style: GoogleFonts.rajdhani(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary,
                      ),
                      decoration: _bowlerInputDecoration(),
                      validator: (v) {
                        if (v?.trim().isEmpty == true) return 'Enter bowler name';
                        final prev = context.read<MatchProvider>().previousBowlerName;
                        if (prev != null && v!.trim().toLowerCase() == prev.toLowerCase()) {
                          return '$prev cannot bowl consecutive overs';
                        }
                        return null;
                      },
                      textCapitalization: TextCapitalization.words,
                      onFieldSubmitted: (_) => _handleSubmit(),
                    )
                  else
                    Autocomplete<String>(
                      optionsBuilder: (tev) {
                        final q = tev.text.toLowerCase();
                        if (q.isEmpty) return _suggestions;
                        return _suggestions.where((s) => s.toLowerCase().startsWith(q));
                      },
                      onSelected: (v) => _controller.text = v,
                      fieldViewBuilder: (ctx, acCtrl, focusNode, onSubmitted) {
                        acCtrl.addListener(() {
                          if (acCtrl.text != _controller.text) _controller.text = acCtrl.text;
                        });
                        return TextFormField(
                          controller: acCtrl,
                          focusNode: focusNode,
                          autofocus: true,
                          style: GoogleFonts.rajdhani(fontSize: 18, fontWeight: FontWeight.w700, color: _textPrimary),
                          decoration: _bowlerInputDecoration(),
                          validator: (_) {
                            if (_controller.text.trim().isEmpty) return 'Enter bowler name';
                            final prev = context.read<MatchProvider>().previousBowlerName;
                            if (prev != null && _controller.text.trim().toLowerCase() == prev.toLowerCase()) {
                              return '$prev cannot bowl consecutive overs';
                            }
                            return null;
                          },
                          textCapitalization: TextCapitalization.words,
                          onFieldSubmitted: (_) { onSubmitted(); _handleSubmit(); },
                        );
                      },
                      optionsViewBuilder: (ctx, onSelected, options) => Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          color: _surfaceCard,
                          borderRadius: BorderRadius.circular(10),
                          elevation: 8,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 180),
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: options.length,
                              itemBuilder: (_, i) {
                                final opt = options.elementAt(i);
                                return InkWell(
                                  onTap: () => onSelected(opt),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    child: Text(opt, style: GoogleFonts.rajdhani(fontSize: 15, fontWeight: FontWeight.w600, color: _textPrimary)),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),

                  // Submit button
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: _handleSubmit,
                      icon: const Icon(Icons.check, size: 22),
                      label: Text(
                        'START BOWLING',
                        style: GoogleFonts.rajdhani(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accentGreen,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
