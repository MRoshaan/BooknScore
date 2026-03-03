import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/database_helper.dart';
import '../providers/match_provider.dart';
import '../providers/tournament_provider.dart';
import 'new_match_screen.dart';
import 'scoring_screen.dart';
import 'match_summary_screen.dart';

// ── Brand Palette ─────────────────────────────────────────────────────────────
const Color _accentGreen    = Color(0xFF39FF14);
const Color _accentGreenMid = Color(0xFF4CAF50);
const Color _surfaceDark    = Color(0xFF0A0A0A);
const Color _surfaceCard    = Color(0xFF141414);
const Color _surfaceCard2   = Color(0xFF1C1C1C);
const Color _textPrimary    = Colors.white;
const Color _textSecondary  = Color(0xFF8A8A8A);
const Color _liveRed        = Color(0xFFFF3D3D);
const Color _completedBlue  = Color(0xFF2196F3);
const Color _trophyGold     = Color(0xFFFFC107);

// ─────────────────────────────────────────────────────────────────────────────

class TournamentDashboardScreen extends StatefulWidget {
  const TournamentDashboardScreen({super.key, required this.tournamentId});
  final int tournamentId;

  @override
  State<TournamentDashboardScreen> createState() => _TournamentDashboardScreenState();
}

class _TournamentDashboardScreenState extends State<TournamentDashboardScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  Map<String, dynamic>? _tournament;
  List<Map<String, dynamic>> _matches = [];
  List<TeamStanding> _standings = [];
  bool _loadingMeta = true;
  bool _loadingStandings = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1 && !_tabController.indexIsChanging) {
        _loadStandings();
      }
    });
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool _concluding = false;

  // ── Data Loading ────────────────────────────────────────────────────────────

  Future<void> _loadAll() async {
    setState(() => _loadingMeta = true);
    try {
      final db = DatabaseHelper.instance;
      final t = await db.fetchTournament(widget.tournamentId);
      final m = await db.fetchMatchesByTournament(widget.tournamentId);
      if (mounted) {
        setState(() {
          _tournament = t;
          _matches = m;
          _loadingMeta = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMeta = false);
    }
  }

  Future<void> _loadStandings() async {
    if (_loadingStandings) return;
    setState(() => _loadingStandings = true);
    try {
      final s = await context
          .read<TournamentProvider>()
          .buildPointsTable(widget.tournamentId);
      if (mounted) setState(() { _standings = s; _loadingStandings = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingStandings = false);
    }
  }

  // ── Navigation ──────────────────────────────────────────────────────────────

  void _openScoring(int matchId) {
    context.read<MatchProvider>().loadMatch(matchId);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ScoringScreen(matchId: matchId)),
    ).then((_) => _loadAll());
  }

  Future<void> _addMatch() async {
    final t = _tournament;
    if (t == null) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NewMatchScreen(
          tournamentId: widget.tournamentId,
          tournamentName: t[DatabaseHelper.colName] as String,
        ),
      ),
    );
    if (mounted) _loadAll();
  }

  /// Shows a bottom sheet that lists all teams in the DB, letting the user
  /// pick one and insert it as a late-entry team into this tournament.
  Future<void> _addTeamToTournament() async {
    // Fetch every distinct team name from the players table.
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery(
      'SELECT DISTINCT ${DatabaseHelper.colTeam} FROM ${DatabaseHelper.tablePlayers} '
      'ORDER BY ${DatabaseHelper.colTeam} ASC',
    );
    final allTeamNames = rows
        .map((r) => r[DatabaseHelper.colTeam] as String)
        .toList();

    // Also include teams already registered in this tournament so the full
    // list is available even if players haven't been entered yet.
    final tournamentTeamRows =
        await DatabaseHelper.instance.fetchAllTournamentTeamRows(widget.tournamentId);
    final registeredNames =
        tournamentTeamRows.map((r) => r[DatabaseHelper.colTeamName] as String).toSet();

    // Merge: registered names first, then any extras from players table.
    final merged = <String>{...registeredNames, ...allTeamNames}.toList()..sort();

    if (!mounted) return;

    String? selected;
    final controller = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final filtered = controller.text.trim().isEmpty
                ? merged
                : merged
                    .where((n) => n
                        .toLowerCase()
                        .contains(controller.text.trim().toLowerCase()))
                    .toList();

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.group_add, color: _trophyGold, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Add Team to Tournament',
                        style: GoogleFonts.rajdhani(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: _textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Select an existing team to add as a late entry.',
                    style: GoogleFonts.rajdhani(
                        fontSize: 13, color: _textSecondary),
                  ),
                  const SizedBox(height: 14),
                  // Search field inside the sheet
                  TextField(
                    controller: controller,
                    style: GoogleFonts.rajdhani(
                        fontSize: 14, color: _textPrimary),
                    onChanged: (_) => setModalState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search team…',
                      hintStyle: GoogleFonts.rajdhani(
                          fontSize: 14, color: _textSecondary),
                      prefixIcon: const Icon(Icons.search,
                          color: _accentGreenMid, size: 18),
                      filled: true,
                      fillColor: _surfaceCard2,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: Text('No teams found.',
                            style: GoogleFonts.rajdhani(
                                fontSize: 14, color: _textSecondary)),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 280),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final name = filtered[i];
                          final isRegistered = registeredNames.contains(name);
                          final isSelected = selected == name;
                          return GestureDetector(
                            onTap: () => setModalState(() => selected = name),
                            child: Container(
                              margin:
                                  const EdgeInsets.symmetric(vertical: 3),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? _trophyGold.withAlpha(30)
                                    : _surfaceCard2,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected
                                      ? _trophyGold.withAlpha(120)
                                      : const Color(0xFF2A2A2A),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isSelected
                                        ? Icons.check_circle
                                        : Icons.group,
                                    color: isSelected
                                        ? _trophyGold
                                        : _textSecondary,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      name,
                                      style: GoogleFonts.rajdhani(
                                        fontSize: 15,
                                        fontWeight: isSelected
                                            ? FontWeight.w800
                                            : FontWeight.w600,
                                        color: isSelected
                                            ? _trophyGold
                                            : _textPrimary,
                                      ),
                                    ),
                                  ),
                                  if (isRegistered)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color:
                                            _accentGreenMid.withAlpha(25),
                                        borderRadius:
                                            BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'REGISTERED',
                                        style: GoogleFonts.rajdhani(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                          color: _accentGreenMid,
                                          letterSpacing: 1,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: selected == null
                          ? null
                          : () => Navigator.pop(ctx, selected),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _trophyGold,
                        disabledBackgroundColor:
                            _trophyGold.withAlpha(50),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(
                        'Add to Tournament',
                        style: GoogleFonts.rajdhani(
                            fontSize: 15, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    ).then((picked) async {
      if (picked == null || !mounted) return;
      final teamName = picked as String;
      // Skip if already registered.
      if (registeredNames.contains(teamName)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$teamName is already in this tournament.',
              style: GoogleFonts.rajdhani(fontSize: 14),
            ),
            backgroundColor: _surfaceCard,
          ),
        );
        return;
      }
      await DatabaseHelper.instance
          .insertTeamIntoTournament(widget.tournamentId, teamName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$teamName added to the tournament.',
              style: GoogleFonts.rajdhani(fontSize: 14),
            ),
            backgroundColor: _accentGreenMid,
          ),
        );
        _loadAll();
      }
    });
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loadingMeta) {
      return Scaffold(
        backgroundColor: _surfaceDark,
        body: const Center(child: CircularProgressIndicator(color: _accentGreen)),
      );
    }

    final t = _tournament;
    if (t == null) {
      return Scaffold(
        backgroundColor: _surfaceDark,
        appBar: AppBar(backgroundColor: _surfaceDark, foregroundColor: _textPrimary),
        body: Center(
          child: Text('Tournament not found.',
              style: GoogleFonts.rajdhani(color: _textSecondary, fontSize: 16)),
        ),
      );
    }

    final name   = t[DatabaseHelper.colName]   as String;
    final format = (t[DatabaseHelper.colFormat] as String? ?? 'league').toUpperCase();
    final status = t[DatabaseHelper.colStatus]  as String? ?? 'active';

    return Scaffold(
      backgroundColor: _surfaceDark,
      body: NestedScrollView(
        headerSliverBuilder: (context2, _) => [_buildAppBar(name, format, status)],
        body: Column(
          children: [
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _MatchesTab(
                    matches: _matches,
                    onTapMatch: _openScoring,
                    onAddMatch: _addMatch,
                    onAddTeam: _addTeamToTournament,
                    tournamentStatus: status,
                    tournament: t,
                  ),
                  _PointsTableTab(
                    standings: _standings,
                    loading: _loadingStandings,
                    onRefresh: _loadStandings,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(String name, String format, String status) {
    return SliverAppBar(
      expandedHeight: 140,
      pinned: true,
      backgroundColor: _surfaceDark,
      foregroundColor: _textPrimary,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1A1000), Color(0xFF0A0A0A)],
            ),
          ),
        ),
        titlePadding: const EdgeInsets.fromLTRB(56, 0, 16, 14),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.emoji_events, color: _trophyGold, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    name,
                    style: GoogleFonts.rajdhani(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: _textPrimary,
                      letterSpacing: 0.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                _FormatBadge(format),
                const SizedBox(width: 6),
                _TournamentStatusBadge(status),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: _surfaceDark,
      child: TabBar(
        controller: _tabController,
        indicatorColor: _trophyGold,
        indicatorWeight: 2.5,
        labelColor: _trophyGold,
        unselectedLabelColor: _textSecondary,
        labelStyle: GoogleFonts.rajdhani(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.5),
        unselectedLabelStyle: GoogleFonts.rajdhani(fontSize: 13, fontWeight: FontWeight.w600),
        tabs: const [
          Tab(text: 'MATCHES'),
          Tab(text: 'POINTS TABLE'),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// MATCHES TAB
// ══════════════════════════════════════════════════════════════════════════════

class _MatchesTab extends StatelessWidget {
  const _MatchesTab({
    required this.matches,
    required this.onTapMatch,
    required this.onAddMatch,
    required this.onAddTeam,
    required this.tournamentStatus,
    required this.tournament,
  });

  final List<Map<String, dynamic>> matches;
  final void Function(int matchId) onTapMatch;
  final VoidCallback onAddMatch;
  final VoidCallback onAddTeam;
  final String tournamentStatus;
  final Map<String, dynamic> tournament;

  @override
  Widget build(BuildContext context) {
    final isCompleted = tournamentStatus == 'completed';

    // Resolve winner name from tournament data for the champions banner.
    // winner_team_id is set when the Final match is completed.
    // As a fallback we inspect the matches for a 'Final' with a winner string.
    String? winnerName;
    final winnerTeamId = tournament[DatabaseHelper.colWinnerTeamId];
    if (winnerTeamId == null) {
      // Fallback: scan matches for a completed Final
      final finalMatch = matches.firstWhere(
        (m) =>
            m[DatabaseHelper.colMatchStage] == 'Final' &&
            m[DatabaseHelper.colStatus] == 'completed',
        orElse: () => {},
      );
      if (finalMatch.isNotEmpty) {
        final rawWinner = finalMatch[DatabaseHelper.colWinner] as String?;
        if (rawWinner != null && rawWinner.isNotEmpty) {
          // rawWinner is "TeamName won by X runs/wickets"
          final teamA = finalMatch[DatabaseHelper.colTeamA] as String? ?? '';
          final teamB = finalMatch[DatabaseHelper.colTeamB] as String? ?? '';
          final lower = rawWinner.toLowerCase();
          if (lower.contains(teamA.toLowerCase())) {
            winnerName = teamA;
          } else if (lower.contains(teamB.toLowerCase())) {
            winnerName = teamB;
          }
        }
      }
    }

    final live = matches
        .where((m) =>
            m[DatabaseHelper.colStatus] == 'live' ||
            m[DatabaseHelper.colStatus] == 'pending')
        .toList();
    final done = matches
        .where((m) => m[DatabaseHelper.colStatus] == 'completed')
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
      children: [
        // Champions banner — only when tournament is completed
        if (isCompleted) ...[
          _ChampionsBanner(winnerName: winnerName),
          const SizedBox(height: 16),
        ],

        // Add Match button — hidden when tournament is completed
        if (!isCompleted) ...[
          _AddMatchButton(onTap: onAddMatch),
          const SizedBox(height: 10),
          _AddTeamButton(onTap: onAddTeam),
          const SizedBox(height: 20),
        ],

        if (matches.isEmpty) ...[
          const SizedBox(height: 40),
          Center(
            child: Column(
              children: [
                Icon(Icons.sports_cricket, size: 64, color: _trophyGold.withAlpha(60)),
                const SizedBox(height: 16),
                Text('No Matches Yet',
                    style: GoogleFonts.rajdhani(
                        fontSize: 20, fontWeight: FontWeight.w700, color: _textSecondary)),
                const SizedBox(height: 8),
                Text('Tap "Add Match" to start playing.',
                    style: GoogleFonts.rajdhani(fontSize: 14, color: _textSecondary)),
              ],
            ),
          ),
        ] else ...[
          if (live.isNotEmpty) ...[
            _SectionHeader('ACTIVE', _liveRed),
            const SizedBox(height: 10),
            ...live.map((m) => _MatchCard(match: m, onTap: () => onTapMatch(m[DatabaseHelper.colId] as int), context: context)),
            const SizedBox(height: 20),
          ],
          if (done.isNotEmpty) ...[
            _SectionHeader('COMPLETED', _completedBlue),
            const SizedBox(height: 10),
            ...done.map((m) => _MatchCard(match: m, onTap: () => onTapMatch(m[DatabaseHelper.colId] as int), context: context)),
          ],
        ],
      ],
    );
  }
}

class _ChampionsBanner extends StatelessWidget {
  const _ChampionsBanner({required this.winnerName});
  final String? winnerName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A1E00), Color(0xFF1C1200)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _trophyGold.withAlpha(120), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: _trophyGold.withAlpha(40),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _trophyGold.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.emoji_events, color: _trophyGold, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TOURNAMENT CHAMPION',
                  style: GoogleFonts.rajdhani(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: _trophyGold,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  winnerName ?? 'Champion',
                  style: GoogleFonts.rajdhani(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: _textPrimary,
                    letterSpacing: 0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AddMatchButton extends StatelessWidget {
  const _AddMatchButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: ElevatedButton.icon(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: _trophyGold,
          foregroundColor: Colors.black,
          elevation: 8,
          shadowColor: _trophyGold.withAlpha(80),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: const Icon(Icons.add, size: 20),
        label: Text(
          'Add Match',
          style: GoogleFonts.rajdhani(
              fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 1),
        ),
      ),
    );
  }
}

class _AddTeamButton extends StatelessWidget {
  const _AddTeamButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: OutlinedButton.icon(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: _trophyGold,
          side: BorderSide(color: _trophyGold.withAlpha(140), width: 1.5),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: const Icon(Icons.group_add, size: 18),
        label: Text(
          'Add Late-Entry Team',
          style: GoogleFonts.rajdhani(
              fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.5),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, this.accent);
  final String title;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3, height: 16,
          decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 10),
        Text(title,
            style: GoogleFonts.rajdhani(
                fontSize: 11, fontWeight: FontWeight.w700,
                color: _textSecondary, letterSpacing: 2.5)),
      ],
    );
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({required this.match, required this.onTap, required this.context});
  final Map<String, dynamic> match;
  final VoidCallback onTap;
  final BuildContext context;

  @override
  Widget build(BuildContext ctx) {
    final id     = match[DatabaseHelper.colId]         as int;
    final teamA  = match[DatabaseHelper.colTeamA]      as String;
    final teamB  = match[DatabaseHelper.colTeamB]      as String;
    final overs  = match[DatabaseHelper.colTotalOvers] as int;
    final status = match[DatabaseHelper.colStatus]     as String;
    final created = match[DatabaseHelper.colCreatedAt] as String?;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: onTap,
        child: _TourneyCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _StatusBadge(status),
                  const Spacer(),
                  if (created != null)
                    Text(_relDate(created),
                        style: GoogleFonts.rajdhani(fontSize: 11, color: _textSecondary)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(teamA,
                        style: GoogleFonts.rajdhani(
                            fontSize: 17, fontWeight: FontWeight.w800, color: _textPrimary),
                        overflow: TextOverflow.ellipsis),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('VS',
                        style: GoogleFonts.rajdhani(
                            fontSize: 12, fontWeight: FontWeight.w900,
                            color: _trophyGold, letterSpacing: 2)),
                  ),
                  Expanded(
                    child: Text(teamB,
                        textAlign: TextAlign.right,
                        style: GoogleFonts.rajdhani(
                            fontSize: 17, fontWeight: FontWeight.w800, color: _textPrimary),
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.timer_outlined, size: 13, color: _textSecondary),
                  const SizedBox(width: 4),
                  Text('$overs overs',
                      style: GoogleFonts.rajdhani(
                          fontSize: 12, color: _textSecondary, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  if (status == 'completed')
                    GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => MatchSummaryScreen(matchId: id, teamA: teamA, teamB: teamB),
                      )),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _completedBlue.withAlpha(25),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: _completedBlue.withAlpha(70)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.bar_chart, size: 12, color: _completedBlue),
                          const SizedBox(width: 4),
                          Text('Summary',
                              style: GoogleFonts.rajdhani(
                                  fontSize: 11, fontWeight: FontWeight.w700, color: _completedBlue)),
                        ]),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Icon(Icons.arrow_forward_ios,
                      size: 12, color: status == 'completed' ? _trophyGold : _accentGreen),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _relDate(String iso) {
    try {
      final d = DateTime.parse(iso);
      final diff = DateTime.now().difference(d);
      if (diff.inDays == 0) return 'Today';
      if (diff.inDays == 1) return 'Yesterday';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${d.day}/${d.month}/${d.year}';
    } catch (_) { return ''; }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// POINTS TABLE TAB
// ══════════════════════════════════════════════════════════════════════════════

class _PointsTableTab extends StatelessWidget {
  const _PointsTableTab({
    required this.standings,
    required this.loading,
    required this.onRefresh,
  });

  final List<TeamStanding> standings;
  final bool loading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator(color: _accentGreen));
    }

    if (standings.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.table_chart_outlined, size: 64, color: _trophyGold.withAlpha(60)),
            const SizedBox(height: 16),
            Text('No completed matches yet.',
                style: GoogleFonts.rajdhani(
                    fontSize: 18, fontWeight: FontWeight.w700, color: _textSecondary)),
            const SizedBox(height: 8),
            Text('Points table will appear after matches complete.',
                style: GoogleFonts.rajdhani(fontSize: 13, color: _textSecondary),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh, color: _trophyGold),
              label: Text('Refresh',
                  style: GoogleFonts.rajdhani(
                      color: _trophyGold, fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        // Refresh row
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            GestureDetector(
              onTap: onRefresh,
              child: Row(
                children: [
                  const Icon(Icons.refresh, size: 14, color: _textSecondary),
                  const SizedBox(width: 4),
                  Text('Refresh',
                      style: GoogleFonts.rajdhani(
                          fontSize: 12, color: _textSecondary, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Leader card
        _LeaderCard(standings.first),
        const SizedBox(height: 20),

        // Table header
        _TableHeader(),
        const SizedBox(height: 6),

        // Rows
        ...standings.asMap().entries.map(
          (e) => _StandingRow(standing: e.value, position: e.key + 1, isLeader: e.key == 0),
        ),

        const SizedBox(height: 20),
        _NrrExplanation(),
      ],
    );
  }
}

class _LeaderCard extends StatelessWidget {
  const _LeaderCard(this.standing);
  final TeamStanding standing;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _trophyGold.withAlpha(40),
                _trophyGold.withAlpha(10),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _trophyGold.withAlpha(80), width: 1.5),
            boxShadow: [
              BoxShadow(color: _trophyGold.withAlpha(20), blurRadius: 20, offset: const Offset(0, 6)),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: _trophyGold.withAlpha(30),
                  shape: BoxShape.circle,
                  border: Border.all(color: _trophyGold.withAlpha(100)),
                ),
                child: const Icon(Icons.emoji_events, color: _trophyGold, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('LEADING',
                        style: GoogleFonts.rajdhani(
                            fontSize: 10, fontWeight: FontWeight.w700,
                            color: _trophyGold, letterSpacing: 2.5)),
                    Text(standing.teamName,
                        style: GoogleFonts.rajdhani(
                            fontSize: 22, fontWeight: FontWeight.w900, color: _textPrimary),
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${standing.points}',
                      style: GoogleFonts.rajdhani(
                          fontSize: 36, fontWeight: FontWeight.w900, color: _trophyGold,
                          height: 1)),
                  Text('pts',
                      style: GoogleFonts.rajdhani(
                          fontSize: 11, color: _trophyGold, fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _surfaceCard2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text('#', style: _headerStyle()),
          ),
          Expanded(
            child: Text('TEAM', style: _headerStyle()),
          ),
          _HeaderCell('P'),
          _HeaderCell('W'),
          _HeaderCell('L'),
          _HeaderCell('T'),
          _HeaderCell('NR'),
          _HeaderCell('PTS', color: _trophyGold),
          _HeaderCell('NRR', width: 58),
        ],
      ),
    );
  }

  TextStyle _headerStyle({Color color = _textSecondary}) => GoogleFonts.rajdhani(
    fontSize: 11, fontWeight: FontWeight.w700, color: color, letterSpacing: 1.5,
  );
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.label, {this.color = _textSecondary, this.width = 28});
  final String label;
  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(label,
          textAlign: TextAlign.center,
          style: GoogleFonts.rajdhani(
              fontSize: 11, fontWeight: FontWeight.w700, color: color, letterSpacing: 1.5)),
    );
  }
}

class _StandingRow extends StatelessWidget {
  const _StandingRow({
    required this.standing,
    required this.position,
    required this.isLeader,
  });
  final TeamStanding standing;
  final int position;
  final bool isLeader;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isLeader
            ? _trophyGold.withAlpha(12)
            : _surfaceCard.withAlpha(200),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isLeader
              ? _trophyGold.withAlpha(50)
              : const Color(0xFF1E1E1E),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: isLeader
                ? const Icon(Icons.emoji_events, size: 14, color: _trophyGold)
                : Text('$position',
                    style: GoogleFonts.rajdhani(
                        fontSize: 13, color: _textSecondary, fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: Text(standing.teamName,
                style: GoogleFonts.rajdhani(
                    fontSize: 14,
                    fontWeight: isLeader ? FontWeight.w800 : FontWeight.w600,
                    color: isLeader ? _trophyGold : _textPrimary),
                overflow: TextOverflow.ellipsis),
          ),
          _DataCell('${standing.played}'),
          _DataCell('${standing.won}', color: standing.won > 0 ? _accentGreenMid : null),
          _DataCell('${standing.lost}', color: standing.lost > 0 ? _liveRed.withAlpha(200) : null),
          _DataCell('${standing.tied}'),
          _DataCell('${standing.noResult}'),
          _DataCell('${standing.points}',
              bold: true, color: isLeader ? _trophyGold : _textPrimary),
          _DataCell(standing.nrrDisplay,
              width: 58,
              color: standing.nrr >= 0 ? _accentGreenMid : _liveRed.withAlpha(200)),
        ],
      ),
    );
  }
}

class _DataCell extends StatelessWidget {
  const _DataCell(this.value, {this.color, this.bold = false, this.width = 28});
  final String value;
  final Color? color;
  final bool bold;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(value,
          textAlign: TextAlign.center,
          style: GoogleFonts.rajdhani(
              fontSize: 13,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: color ?? _textSecondary)),
    );
  }
}

class _NrrExplanation extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surfaceCard2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('NET RUN RATE (NRR)',
              style: GoogleFonts.rajdhani(
                  fontSize: 11, fontWeight: FontWeight.w700,
                  color: _textSecondary, letterSpacing: 2)),
          const SizedBox(height: 6),
          Text(
            'NRR = (Runs Scored ÷ Overs Faced) − (Runs Conceded ÷ Overs Bowled)\n'
            'All-out innings: actual overs faced. Full-over innings: max overs.',
            style: GoogleFonts.rajdhani(
                fontSize: 12, color: _textSecondary, height: 1.5),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SMALL WIDGET ATOMS
// ══════════════════════════════════════════════════════════════════════════════

class _TourneyCard extends StatelessWidget {
  const _TourneyCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _surfaceCard.withAlpha(230),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _trophyGold.withAlpha(35), width: 1),
            boxShadow: [
              BoxShadow(color: _trophyGold.withAlpha(12), blurRadius: 12, offset: const Offset(0, 4)),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge(this.status);
  final String status;

  @override
  Widget build(BuildContext context) {
    Color bg, fg;
    String label;
    switch (status) {
      case 'live':
        bg = _liveRed.withAlpha(30); fg = _liveRed; label = 'LIVE'; break;
      case 'completed':
        bg = _completedBlue.withAlpha(30); fg = _completedBlue; label = 'COMPLETED'; break;
      default:
        bg = _accentGreen.withAlpha(20); fg = _accentGreen; label = 'PENDING';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg, borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withAlpha(70)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == 'live') ...[
            Container(
              width: 5, height: 5,
              margin: const EdgeInsets.only(right: 5),
              decoration: BoxDecoration(
                color: _liveRed, shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: _liveRed.withAlpha(140), blurRadius: 4)],
              ),
            ),
          ],
          Text(label,
              style: GoogleFonts.rajdhani(
                  fontSize: 10, fontWeight: FontWeight.w700, color: fg, letterSpacing: 1.5)),
        ],
      ),
    );
  }
}

class _FormatBadge extends StatelessWidget {
  const _FormatBadge(this.format);
  final String format;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: _trophyGold.withAlpha(20),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(format,
          style: GoogleFonts.rajdhani(
              fontSize: 9, fontWeight: FontWeight.w700,
              color: _trophyGold, letterSpacing: 1.5)),
    );
  }
}

class _TournamentStatusBadge extends StatelessWidget {
  const _TournamentStatusBadge(this.status);
  final String status;

  @override
  Widget build(BuildContext context) {
    final isActive = status == 'active';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: isActive ? _accentGreen.withAlpha(20) : _completedBlue.withAlpha(20),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        isActive ? 'ACTIVE' : 'COMPLETED',
        style: GoogleFonts.rajdhani(
            fontSize: 9, fontWeight: FontWeight.w700,
            color: isActive ? _accentGreen : _completedBlue, letterSpacing: 1.5),
      ),
    );
  }
}
