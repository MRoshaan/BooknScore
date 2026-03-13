import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../services/database_helper.dart';
import 'team_detail_screen.dart';

// ── Brand Palette ─────────────────────────────────────────────────────────────
const Color _tsSurface      = Color(0xFF0A0A0A);
const Color _tsCard         = Color(0xFF141414);
const Color _tsAccent       = Color(0xFF39FF14);
const Color _tsAccentMid    = Color(0xFF4CAF50);
const Color _tsGlassBorder  = Color(0x3239FF14);
const Color _tsTextPrimary  = Colors.white;
const Color _tsTextSecondary = Color(0xFF8A8A8A);
const Color _tsWinGreen     = Color(0xFF4CAF50);
const Color _tsLossRed      = Color(0xFFD32F2F);
// ─────────────────────────────────────────────────────────────────────────────

/// Displays all teams the current user is associated with (via created players
/// or matches). Tapping a team opens [TeamDetailScreen].
class TeamsScreen extends StatefulWidget {
  const TeamsScreen({super.key});

  @override
  State<TeamsScreen> createState() => _TeamsScreenState();
}

class _TeamsScreenState extends State<TeamsScreen> {
  /// Each entry: { 'name': String, 'playerCount': int, 'wins': int, 'losses': int }
  List<Map<String, dynamic>> _teams = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final userId = AuthService.instance.userId;
      final db = DatabaseHelper.instance;

      // Distinct team names from players created by user, plus teams from
      // the user's matches.
      List<String> teamNames;
      if (userId != null) {
        final rawDb = await db.database;
        final rows = await rawDb.rawQuery('''
          SELECT DISTINCT team_name FROM (
            SELECT team AS team_name FROM players WHERE created_by = ?
            UNION
            SELECT team_a AS team_name FROM matches WHERE created_by = ?
            UNION
            SELECT team_b AS team_name FROM matches WHERE created_by = ?
          )
          WHERE team_name IS NOT NULL AND team_name != ''
          ORDER BY team_name ASC
        ''', [userId, userId, userId]);
        teamNames = rows.map((r) => r['team_name'] as String).toList();
      } else {
        teamNames = await db.fetchDistinctTeamNames();
      }

      // For each team, fetch player count and W/L stats
      final List<Map<String, dynamic>> result = [];
      for (final name in teamNames) {
        final players = await db.fetchPlayersByTeam(name);
        final matches = await db.fetchMatchesByTeam(name);

        int wins = 0, losses = 0;
        for (final m in matches) {
          if (m[DatabaseHelper.colStatus] != 'completed') continue;
          final winner = (m[DatabaseHelper.colWinner] as String? ?? '').toLowerCase();
          if (winner.isEmpty) continue;
          if (winner.contains(name.toLowerCase())) {
            wins++;
          } else {
            losses++;
          }
        }

        result.add({
          'name':        name,
          'playerCount': players.length,
          'matchCount':  matches.length,
          'wins':        wins,
          'losses':      losses,
        });
      }

      if (mounted) {
        setState(() {
          _teams = result;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _tsSurface,
      body: RefreshIndicator(
        color: _tsAccent,
        backgroundColor: const Color(0xFF1A1A1A),
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            _buildAppBar(),
            if (_loading)
              const SliverFillRemaining(
                child: Center(
                  child: CircularProgressIndicator(color: _tsAccent),
                ),
              )
            else if (_teams.isEmpty)
              _buildEmptyState()
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _teamCard(_teams[i]),
                    childCount: _teams.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 120,
      floating: false,
      pinned: true,
      backgroundColor: _tsSurface,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, color: _tsTextPrimary, size: 18),
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: FlexibleSpaceBar(
        centerTitle: true,
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0F1F0F), Color(0xFF0A0A0A)],
            ),
          ),
        ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'My Teams',
              style: GoogleFonts.rajdhani(
                fontSize: 22, fontWeight: FontWeight.w900,
                color: _tsTextPrimary, letterSpacing: 1.5,
              ),
            ),
            Text(
              'SQUAD MANAGEMENT',
              style: GoogleFonts.rajdhani(
                fontSize: 8, fontWeight: FontWeight.w700,
                color: _tsAccent, letterSpacing: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return SliverFillRemaining(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shield_outlined, size: 72,
                color: _tsAccent.withAlpha(50)),
            const SizedBox(height: 20),
            Text(
              'No Teams Yet',
              style: GoogleFonts.rajdhani(
                fontSize: 22, fontWeight: FontWeight.w700,
                color: _tsTextSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add players with team names to build\nyour squads.',
              style: GoogleFonts.rajdhani(fontSize: 14, color: _tsTextSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _teamCard(Map<String, dynamic> team) {
    final name        = team['name'] as String;
    final playerCount = team['playerCount'] as int;
    final matchCount  = team['matchCount'] as int;
    final wins        = team['wins'] as int;
    final losses      = team['losses'] as int;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TeamDetailScreen(teamName: name),
          ),
        ).then((_) => _load()),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _tsCard.withAlpha(220),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _tsGlassBorder, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _tsAccent.withAlpha(20),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _tsAccent.withAlpha(50), width: 1),
                        ),
                        child: const Icon(Icons.shield_outlined,
                            color: _tsAccentMid, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: GoogleFonts.rajdhani(
                                fontSize: 18, fontWeight: FontWeight.w800,
                                color: _tsTextPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '$playerCount player${playerCount == 1 ? '' : 's'}'
                              ' · $matchCount match${matchCount == 1 ? '' : 'es'}',
                              style: GoogleFonts.rajdhani(
                                fontSize: 12, color: _tsTextSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right,
                          color: _tsTextSecondary, size: 20),
                    ],
                  ),
                  if (matchCount > 0) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _StatPill(label: 'W', value: wins.toString(),
                            color: _tsWinGreen),
                        const SizedBox(width: 8),
                        _StatPill(label: 'L', value: losses.toString(),
                            color: _tsLossRed),
                        const SizedBox(width: 8),
                        if (matchCount - wins - losses > 0)
                          _StatPill(
                            label: 'NR',
                            value: (matchCount - wins - losses).toString(),
                            color: _tsTextSecondary,
                          ),
                        const Spacer(),
                        Text(
                          wins > 0 && (wins + losses) > 0
                              ? 'Win rate ${((wins / (wins + losses)) * 100).toStringAsFixed(0)}%'
                              : '',
                          style: GoogleFonts.rajdhani(
                            fontSize: 12, color: _tsTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Stat pill ─────────────────────────────────────────────────────────────────

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(60), width: 1),
      ),
      child: Text(
        '$label $value',
        style: GoogleFonts.rajdhani(
          fontSize: 12, fontWeight: FontWeight.w700, color: color,
        ),
      ),
    );
  }
}
