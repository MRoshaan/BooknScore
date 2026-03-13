import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../services/database_helper.dart';
import 'create_team_screen.dart';
import 'team_detail_screen.dart';

// ── Brand Palette ─────────────────────────────────────────────────────────────
const Color _tlSurface       = Color(0xFF0A0A0A);
const Color _tlCard          = Color(0xFF141414);
const Color _tlAccent        = Color(0xFF39FF14);
const Color _tlAccentMid     = Color(0xFF4CAF50);
const Color _tlGlassBorder   = Color(0x3239FF14);
const Color _tlTextPrimary   = Colors.white;
const Color _tlTextSecondary = Color(0xFF8A8A8A);
// ─────────────────────────────────────────────────────────────────────────────

/// Dedicated team management screen.
///
/// Shows all teams created by the current user (from the [teams] table),
/// with a FAB to create a new team.  Tapping a team navigates to
/// [TeamDetailScreen] (which shows the full player roster for that team name).
class TeamsListScreen extends StatefulWidget {
  const TeamsListScreen({super.key});

  @override
  State<TeamsListScreen> createState() => _TeamsListScreenState();
}

class _TeamsListScreenState extends State<TeamsListScreen> {
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
      final rows   = await DatabaseHelper.instance.fetchTeamsByUser(userId);

      // For each team, attach player count (FK-based) and W/L stats.
      final enriched = <Map<String, dynamic>>[];
      for (final row in rows) {
        final teamId  = row[DatabaseHelper.colId] as int;
        final name    = row[DatabaseHelper.colName] as String? ?? '';

        // Player count: prefer FK-based lookup; fall back to TEXT match so
        // teams created before v21 still show a non-zero count.
        final byId   = await DatabaseHelper.instance.fetchPlayersByTeamId(teamId);
        final byText = byId.isEmpty
            ? await DatabaseHelper.instance.fetchPlayersByTeam(name)
            : <Map<String, dynamic>>[];
        final playerCount = byId.isNotEmpty ? byId.length : byText.length;

        // Match stats: wins and losses from the text-based match history.
        final matches = await DatabaseHelper.instance.fetchMatchesByTeam(name);
        int wins   = 0;
        int losses = 0;
        for (final m in matches) {
          final winner = m[DatabaseHelper.colWinner] as String?;
          final status = m[DatabaseHelper.colStatus] as String?;
          if (status != 'completed' || winner == null) continue;
          if (winner == name) {
            wins++;
          } else if (winner != 'Draw') {
            losses++;
          }
        }

        enriched.add({
          ...row,
          'playerCount': playerCount,
          'wins':        wins,
          'losses':      losses,
          'played':      matches.where((m) =>
              m[DatabaseHelper.colStatus] == 'completed').length,
        });
      }

      if (mounted) {
        setState(() {
          _teams   = enriched;
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
      backgroundColor: _tlSurface,
      floatingActionButton: FloatingActionButton(
        backgroundColor: _tlAccent,
        foregroundColor: Colors.black,
        onPressed: _openCreateTeam,
        child: const Icon(Icons.add, size: 28),
      ),
      body: RefreshIndicator(
        color: _tlAccent,
        backgroundColor: const Color(0xFF1A1A1A),
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            _buildAppBar(),
            if (_loading)
              const SliverFillRemaining(
                child: Center(
                  child: CircularProgressIndicator(color: _tlAccent),
                ),
              )
            else if (_teams.isEmpty)
              _buildEmptyState()
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
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
      backgroundColor: _tlSurface,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new,
            color: _tlTextPrimary, size: 18),
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
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: _tlTextPrimary,
                letterSpacing: 1.5,
              ),
            ),
            Text(
              'TEAM MANAGEMENT',
              style: GoogleFonts.rajdhani(
                fontSize: 8,
                fontWeight: FontWeight.w700,
                color: _tlAccent,
                letterSpacing: 3,
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
            Icon(Icons.shield_outlined,
                size: 72, color: _tlAccent.withAlpha(50)),
            const SizedBox(height: 20),
            Text(
              'No Teams Yet',
              style: GoogleFonts.rajdhani(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: _tlTextSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap + to create your first team.',
              style: GoogleFonts.rajdhani(
                  fontSize: 14, color: _tlTextSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _teamCard(Map<String, dynamic> team) {
    final name        = team[DatabaseHelper.colName] as String? ?? '';
    final playerCount = team['playerCount'] as int? ?? 0;
    final teamId      = team[DatabaseHelper.colId] as int;
    final wins        = team['wins']   as int? ?? 0;
    final losses      = team['losses'] as int? ?? 0;
    final played      = team['played'] as int? ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TeamDetailScreen(teamName: name),
          ),
        ).then((_) => _load()),
        onLongPress: () => _confirmDelete(teamId, name),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _tlCard.withAlpha(220),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _tlGlassBorder, width: 1),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _tlAccent.withAlpha(20),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: _tlAccent.withAlpha(50), width: 1),
                    ),
                    child: const Icon(Icons.shield_outlined,
                        color: _tlAccentMid, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: GoogleFonts.rajdhani(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: _tlTextPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              '$playerCount player${playerCount == 1 ? '' : 's'}',
                              style: GoogleFonts.rajdhani(
                                fontSize: 12,
                                color: _tlTextSecondary,
                              ),
                            ),
                            if (played > 0) ...[
                              const SizedBox(width: 10),
                              Container(
                                width: 3,
                                height: 3,
                                decoration: BoxDecoration(
                                  color: _tlTextSecondary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                '$wins W  $losses L',
                                style: GoogleFonts.rajdhani(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: wins > losses
                                      ? _tlAccent
                                      : _tlTextSecondary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right,
                      color: _tlTextSecondary, size: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  void _openCreateTeam() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateTeamScreen()),
    ).then((_) => _load());
  }

  Future<void> _confirmDelete(int teamId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(
          'Delete "$name"?',
          style: GoogleFonts.rajdhani(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'This removes the team record only. Players in this team are not deleted.',
          style: GoogleFonts.rajdhani(color: _tlTextSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: GoogleFonts.rajdhani(color: _tlTextSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete',
                style: GoogleFonts.rajdhani(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await DatabaseHelper.instance.deleteTeam(teamId);
      _load();
    }
  }
}
