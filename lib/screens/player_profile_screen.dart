import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/database_helper.dart';

// ── Brand palette ─────────────────────────────────────────────────────────────
const Color _accentGreen   = Color(0xFF4CAF50);
const Color _surfaceDark   = Color(0xFF0A0A0A);
const Color _surfaceCard   = Color(0xFF1A1A1A);
const Color _glassBg       = Color(0x1A4CAF50);
const Color _glassBorder   = Color(0x334CAF50);
const Color _textPrimary   = Colors.white;
const Color _textSecondary = Color(0xFFB0B0B0);
const Color _textMuted     = Color(0xFF666666);
const Color _boundaryBlue  = Color(0xFF1E88E5);
const Color _sixPurple     = Color(0xFFAB47BC);
const Color _wicketRed     = Color(0xFFEF5350);

/// ESPN-style all-time career profile for a single player.
///
/// Shows:
///   - Player name, team, role
///   - Career batting aggregates (innings, runs, avg, SR, 4s, 6s)
///   - Career bowling aggregates (wickets, overs, economy, best bowling)
class PlayerProfileScreen extends StatefulWidget {
  final int playerId;
  final String playerName;

  const PlayerProfileScreen({
    super.key,
    required this.playerId,
    required this.playerName,
  });

  @override
  State<PlayerProfileScreen> createState() => _PlayerProfileScreenState();
}

class _PlayerProfileScreenState extends State<PlayerProfileScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _player;
  Map<String, dynamic>? _career;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = DatabaseHelper.instance;
      final player = await db.fetchPlayer(widget.playerId);
      final career = await db.getCareerStats(widget.playerId);
      if (mounted) {
        setState(() {
          _player  = player;
          _career  = career;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surfaceDark,
      appBar: AppBar(
        backgroundColor: _surfaceDark,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: _accentGreen),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.playerName,
          style: GoogleFonts.rajdhani(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _glassBorder),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accentGreen))
          : _error != null
              ? _buildError()
              : _buildBody(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'Could not load profile.\n$_error',
          style: GoogleFonts.rajdhani(color: _textSecondary, fontSize: 16),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildBody() {
    final career = _career!;
    final player = _player;

    final String team    = (player?[DatabaseHelper.colTeam] as String?) ?? '';
    final String role    = (player?[DatabaseHelper.colRole] as String?) ?? '';

    final int     batInnings    = career['batInnings']    as int;
    final int     batRuns       = career['batRuns']       as int;
    final int     notOuts       = career['notOuts']       as int;
    final double  batAverage    = (career['batAverage']   as num).toDouble();
    final double  batSR         = (career['batStrikeRate'] as num).toDouble();
    final int     batFours      = career['batFours']      as int;
    final int     batSixes      = career['batSixes']      as int;
    final int     batBalls      = career['batBalls']      as int;

    final int     bowlWickets   = career['bowlWickets']   as int;
    final int     bowlOvers     = career['bowlOvers']     as int;
    final int     bowlBalls     = career['bowlBalls']     as int;
    final int     bowlRuns      = career['bowlRunsConceded'] as int;
    final double  bowlEconomy   = (career['bowlEconomy']  as num).toDouble();
    final String  bestBowling   = career['bestBowling']   as String;

    final bool hasBatting = batInnings > 0;
    final bool hasBowling = bowlWickets > 0 || bowlOvers > 0 || bowlBalls > 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Player hero card ────────────────────────────────────────────
          _buildHeroCard(team, role),
          const SizedBox(height: 20),

          // ── Batting stats ───────────────────────────────────────────────
          if (hasBatting) ...[
            _sectionLabel('BATTING'),
            const SizedBox(height: 8),
            _buildBattingCard(
              innings:    batInnings,
              runs:       batRuns,
              notOuts:    notOuts,
              average:    batAverage,
              strikeRate: batSR,
              fours:      batFours,
              sixes:      batSixes,
              balls:      batBalls,
            ),
            const SizedBox(height: 20),
          ],

          // ── Bowling stats ───────────────────────────────────────────────
          if (hasBowling) ...[
            _sectionLabel('BOWLING'),
            const SizedBox(height: 8),
            _buildBowlingCard(
              wickets:  bowlWickets,
              overs:    bowlOvers,
              balls:    bowlBalls,
              runs:     bowlRuns,
              economy:  bowlEconomy,
              best:     bestBowling,
            ),
            const SizedBox(height: 20),
          ],

          // ── Nothing recorded yet ────────────────────────────────────────
          if (!hasBatting && !hasBowling)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Text(
                  'No career data recorded yet.',
                  style: GoogleFonts.rajdhani(
                    color: _textMuted,
                    fontSize: 16,
                  ),
                ),
              ),
            ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ── Hero card ──────────────────────────────────────────────────────────────

  Widget _buildHeroCard(String team, String role) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _glassBorder),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _accentGreen.withAlpha(20),
            _surfaceCard,
          ],
        ),
      ),
      child: Row(
        children: [
          // Avatar circle
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _glassBg,
              border: Border.all(color: _accentGreen, width: 2),
            ),
            child: Center(
              child: Text(
                widget.playerName.isNotEmpty
                    ? widget.playerName[0].toUpperCase()
                    : '?',
                style: GoogleFonts.rajdhani(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: _accentGreen,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Name / team / role
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.playerName,
                  style: GoogleFonts.rajdhani(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: _textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (team.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    team,
                    style: GoogleFonts.rajdhani(
                      fontSize: 13,
                      color: _accentGreen,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (role.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _glassBg,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: _glassBorder),
                    ),
                    child: Text(
                      role.toUpperCase(),
                      style: GoogleFonts.rajdhani(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _textSecondary,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Batting card ───────────────────────────────────────────────────────────

  Widget _buildBattingCard({
    required int innings,
    required int runs,
    required int notOuts,
    required double average,
    required double strikeRate,
    required int fours,
    required int sixes,
    required int balls,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _glassBorder),
      ),
      child: Column(
        children: [
          // Primary row: big numbers
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                _bigStat('RUNS', '$runs',
                    color: runs >= 100 ? _boundaryBlue : _textPrimary),
                _bigStat('AVG', average == 0
                    ? '-'
                    : average.toStringAsFixed(2)),
                _bigStat('SR', balls == 0
                    ? '-'
                    : strikeRate.toStringAsFixed(1)),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFF2A2A2A)),
          // Secondary row: innings, 4s, 6s, balls
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                _smallStat('INN', '$innings'),
                _smallStat('NO', '$notOuts'),
                _smallStat('4s', '$fours',
                    color: fours > 0 ? _boundaryBlue : _textSecondary),
                _smallStat('6s', '$sixes',
                    color: sixes > 0 ? _sixPurple : _textSecondary),
                _smallStat('BALLS', '$balls'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Bowling card ───────────────────────────────────────────────────────────

  Widget _buildBowlingCard({
    required int wickets,
    required int overs,
    required int balls,
    required int runs,
    required double economy,
    required String best,
  }) {
    final oversStr = balls == 0 ? '$overs' : '$overs.$balls';
    return Container(
      decoration: BoxDecoration(
        color: _surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _glassBorder),
      ),
      child: Column(
        children: [
          // Primary row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                _bigStat('WICKETS', '$wickets',
                    color: wickets >= 5 ? _wicketRed : _textPrimary),
                _bigStat('ECONOMY', economy == 0
                    ? '-'
                    : economy.toStringAsFixed(2)),
                _bigStat('BEST', best),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFF2A2A2A)),
          // Secondary row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                _smallStat('OVERS', oversStr),
                _smallStat('RUNS', '$runs'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _sectionLabel(String label) {
    return Text(
      label,
      style: GoogleFonts.rajdhani(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: _accentGreen,
        letterSpacing: 2.5,
      ),
    );
  }

  Widget _bigStat(String label, String value, {Color? color}) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.rajdhani(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: color ?? _textPrimary,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.rajdhani(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: _textMuted,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _smallStat(String label, String value, {Color? color}) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.rajdhani(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: color ?? _textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.rajdhani(
              fontSize: 10,
              color: _textMuted,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}
