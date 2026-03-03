import 'dart:io';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/database_helper.dart';

// ── Brand Palette ──────────────────────────────────────────────────────────────
const Color _accentGreen    = Color(0xFF39FF14);
const Color _surfaceDark    = Color(0xFF0A0A0A);
const Color _surfaceCard    = Color(0xFF141414);
const Color _surfaceCard2   = Color(0xFF1C1C1C);
const Color _textPrimary    = Colors.white;
const Color _textSecondary  = Color(0xFF8A8A8A);
const Color _trophyGold     = Color(0xFFFFC107);
const Color _goldLight      = Color(0xFFFFD700);
const Color _goldMid        = Color(0xFFFF8F00);
const Color _goldDark       = Color(0xFFE65100);

// ── Data model ─────────────────────────────────────────────────────────────────

class _PotsEntry {
  final int    playerId;
  final String name;
  final String? avatarPath;
  final int    score;
  final int    runs;
  final int    wickets;
  final int    catches;

  const _PotsEntry({
    required this.playerId,
    required this.name,
    this.avatarPath,
    required this.score,
    required this.runs,
    required this.wickets,
    required this.catches,
  });
}

// ─────────────────────────────────────────────────────────────────────────────

/// Full-screen celebration shown when the Final match of a knockout tournament
/// is completed.  Shows:
///  • Confetti rain
///  • Trophy + winning team name
///  • POTS (Player of the Tournament Series) FIFA-card-style award
///  • Full POTS leaderboard
class TournamentChampionsScreen extends StatefulWidget {
  const TournamentChampionsScreen({
    super.key,
    required this.tournamentId,
    required this.winnerTeamName,
  });

  final int    tournamentId;
  final String winnerTeamName;

  @override
  State<TournamentChampionsScreen> createState() =>
      _TournamentChampionsScreenState();
}

class _TournamentChampionsScreenState
    extends State<TournamentChampionsScreen>
    with SingleTickerProviderStateMixin {
  late final ConfettiController _confetti;
  late final AnimationController _scaleCtrl;
  late final Animation<double> _scaleAnim;

  bool _loading = true;
  List<_PotsEntry> _pots = [];

  @override
  void initState() {
    super.initState();

    _confetti = ConfettiController(duration: const Duration(seconds: 6));

    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _scaleAnim = CurvedAnimation(
      parent: _scaleCtrl,
      curve: Curves.elasticOut,
    );

    _loadData();
  }

  @override
  void dispose() {
    _confetti.dispose();
    _scaleCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final rows = await DatabaseHelper.instance.computePots(widget.tournamentId);
      final entries = rows
          .map((r) => _PotsEntry(
                playerId:   r['playerId']   as int,
                name:       r['playerName'] as String,
                avatarPath: r['avatarPath'] as String?,
                score:      r['score']      as int,
                runs:       r['runs']       as int,
                wickets:    r['wickets']    as int,
                catches:    r['catches']    as int,
              ))
          .toList();

      if (mounted) {
        setState(() {
          _pots    = entries;
          _loading = false;
        });
        // Start confetti + trophy entrance after data loads
        _confetti.play();
        _scaleCtrl.forward();
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surfaceDark,
      body: Stack(
        children: [
          // ── Background gradient ────────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.0, -0.4),
                radius: 1.2,
                colors: [Color(0xFF2A1E00), _surfaceDark],
                stops: [0.0, 0.7],
              ),
            ),
          ),

          // ── Main content ──────────────────────────────────────────────────
          SafeArea(
            child: CustomScrollView(
              slivers: [
                // Close button
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(
                      children: [
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close, color: _textSecondary),
                          tooltip: 'Close',
                        ),
                      ],
                    ),
                  ),
                ),

                // Trophy + winner
                SliverToBoxAdapter(
                  child: _TrophyHero(
                    winnerName: widget.winnerTeamName,
                    scaleAnim:  _scaleAnim,
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 32)),

                // POTS card
                if (!_loading) ...[
                  if (_pots.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: _PotsCard(pots: _pots.first),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),

                    // Leaderboard section header
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Row(
                          children: [
                            Container(
                              width: 4,
                              height: 16,
                              decoration: BoxDecoration(
                                color: _accentGreen,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'POTS LEADERBOARD',
                              style: GoogleFonts.rajdhani(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: _accentGreen,
                                letterSpacing: 2.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (ctx, i) => _LeaderboardRow(
                          rank:  i + 1,
                          entry: _pots[i],
                        ),
                        childCount: _pots.length,
                      ),
                    ),
                  ] else ...[
                    SliverToBoxAdapter(
                      child: Center(
                        child: Text(
                          'No player stats available.',
                          style: GoogleFonts.rajdhani(
                            color: _textSecondary, fontSize: 15),
                        ),
                      ),
                    ),
                  ],
                ] else ...[
                  const SliverToBoxAdapter(
                    child: Center(
                      child: CircularProgressIndicator(color: _trophyGold),
                    ),
                  ),
                ],

                const SliverToBoxAdapter(child: SizedBox(height: 48)),
              ],
            ),
          ),

          // ── Confetti ──────────────────────────────────────────────────────
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController:   _confetti,
              blastDirectionality: BlastDirectionality.explosive,
              numberOfParticles:   30,
              gravity:             0.2,
              emissionFrequency:   0.05,
              maxBlastForce:       20,
              minBlastForce:       8,
              colors: const [
                _trophyGold, _goldLight, _goldMid,
                _accentGreen, Colors.white, Colors.orangeAccent,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TROPHY HERO
// ─────────────────────────────────────────────────────────────────────────────

class _TrophyHero extends StatelessWidget {
  const _TrophyHero({required this.winnerName, required this.scaleAnim});

  final String          winnerName;
  final Animation<double> scaleAnim;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          ScaleTransition(
            scale: scaleAnim,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  colors: [_goldLight, _goldMid, _goldDark],
                ),
                boxShadow: [
                  BoxShadow(
                    color: _trophyGold.withAlpha(120),
                    blurRadius: 40,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Icon(Icons.emoji_events,
                  color: Color(0xFF1A1200), size: 64),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'TOURNAMENT CHAMPIONS',
            style: GoogleFonts.rajdhani(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: _trophyGold,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            winnerName,
            textAlign: TextAlign.center,
            style: GoogleFonts.rajdhani(
              fontSize: 34,
              fontWeight: FontWeight.w900,
              color: _textPrimary,
              letterSpacing: 0.5,
              shadows: [
                Shadow(
                  color: _trophyGold.withAlpha(80),
                  blurRadius: 16,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// POTS FIFA-STYLE CARD
// ─────────────────────────────────────────────────────────────────────────────

class _PotsCard extends StatelessWidget {
  const _PotsCard({required this.pots});

  final _PotsEntry pots;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section label
          Row(
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: _goldLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'PLAYER OF THE SERIES',
                style: GoogleFonts.rajdhani(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _goldLight,
                  letterSpacing: 3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // The card itself — centred
          Center(
            child: Container(
              width: 200,
              height: 270,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_goldLight, _goldMid, _goldDark, _goldMid, _goldLight],
                  stops: [0.0, 0.25, 0.5, 0.75, 1.0],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: _goldLight.withAlpha(120),
                    blurRadius: 28,
                    spreadRadius: 3,
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // Metallic sheen overlay
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withAlpha(40),
                          Colors.transparent,
                          Colors.white.withAlpha(20),
                        ],
                      ),
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    child: Column(
                      children: [
                        // Score + POTS badge
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${pots.score}',
                                  style: GoogleFonts.rajdhani(
                                    fontSize: 36,
                                    fontWeight: FontWeight.w900,
                                    color: const Color(0xFF1A1200),
                                    height: 1,
                                  ),
                                ),
                                Text(
                                  'PTS',
                                  style: GoogleFonts.rajdhani(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF3E2800),
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0x551A1200),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: const Color(0x881A1200),
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                'POTS',
                                style: GoogleFonts.rajdhani(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  color: const Color(0xFF1A1200),
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 4),

                        // Avatar
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              color: const Color(0x221A1200),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: pots.avatarPath != null &&
                                    pots.avatarPath!.isNotEmpty
                                ? Image.file(
                                    File(pots.avatarPath!),
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                  )
                                : Center(
                                    child: Icon(
                                      Icons.person,
                                      size: 60,
                                      color: const Color(0xFF3E2800)
                                          .withAlpha(180),
                                    ),
                                  ),
                          ),
                        ),

                        const SizedBox(height: 6),

                        // Player name
                        Text(
                          pots.name.toUpperCase(),
                          style: GoogleFonts.rajdhani(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF1A1200),
                            letterSpacing: 1,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),

                        const SizedBox(height: 6),

                        // Stats row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _CardStat(label: 'RNS', value: '${pots.runs}'),
                            _CardStat(label: 'WKT', value: '${pots.wickets}'),
                            _CardStat(label: 'CTC', value: '${pots.catches}'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardStat extends StatelessWidget {
  const _CardStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.rajdhani(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: const Color(0xFF1A1200),
          ),
        ),
        Text(
          label,
          style: GoogleFonts.rajdhani(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF3E2800),
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LEADERBOARD ROW
// ─────────────────────────────────────────────────────────────────────────────

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({required this.rank, required this.entry});
  final int        rank;
  final _PotsEntry entry;

  @override
  Widget build(BuildContext context) {
    final isTop3   = rank <= 3;
    final rankColor = rank == 1
        ? _trophyGold
        : rank == 2
            ? const Color(0xFFC0C0C0) // silver
            : rank == 3
                ? const Color(0xFFCD7F32) // bronze
                : _textSecondary;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isTop3
            ? _surfaceCard2.withAlpha(220)
            : _surfaceCard.withAlpha(200),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isTop3 ? rankColor.withAlpha(60) : Colors.transparent,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // Rank badge
          SizedBox(
            width: 32,
            child: Text(
              '#$rank',
              style: GoogleFonts.rajdhani(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: rankColor,
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Avatar
          CircleAvatar(
            radius: 20,
            backgroundColor: _surfaceCard2,
            backgroundImage: (entry.avatarPath != null &&
                    entry.avatarPath!.isNotEmpty)
                ? FileImage(File(entry.avatarPath!))
                : null,
            child: (entry.avatarPath == null || entry.avatarPath!.isEmpty)
                ? const Icon(Icons.person, color: _textSecondary, size: 20)
                : null,
          ),
          const SizedBox(width: 12),

          // Name
          Expanded(
            child: Text(
              entry.name,
              style: GoogleFonts.rajdhani(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Stats
          Row(
            children: [
              _MiniStat(icon: Icons.sports_cricket,
                  value: '${entry.runs}R'),
              const SizedBox(width: 8),
              _MiniStat(icon: Icons.sports_baseball,
                  value: '${entry.wickets}W'),
            ],
          ),
          const SizedBox(width: 12),

          // Score
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: rank == 1
                  ? _trophyGold.withAlpha(30)
                  : _surfaceDark,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: rank == 1
                    ? _trophyGold.withAlpha(80)
                    : Colors.transparent,
              ),
            ),
            child: Text(
              '${entry.score}',
              style: GoogleFonts.rajdhani(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: rank == 1 ? _trophyGold : _textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.icon, required this.value});
  final IconData icon;
  final String   value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 12, color: _textSecondary),
        const SizedBox(width: 2),
        Text(
          value,
          style: GoogleFonts.rajdhani(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _textSecondary,
          ),
        ),
      ],
    );
  }
}
