import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/database_helper.dart';
import '../providers/tournament_provider.dart';
import '../theme.dart';
import 'new_match_screen.dart';
import 'scoring_screen.dart';
import 'scorecard_screen.dart';
import 'match_summary_screen.dart';
import '../services/auth_service.dart';
import 'team_history_screen.dart';

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
  String? _resolvedWinnerName;

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

  /// Sort a match list newest-first by [created_at], falling back gracefully.
  List<Map<String, dynamic>> _sortedNewestFirst(List<Map<String, dynamic>> list) {
    final sorted = List<Map<String, dynamic>>.from(list);
    sorted.sort((a, b) {
      final ca = a[DatabaseHelper.colCreatedAt] as String?;
      final cb = b[DatabaseHelper.colCreatedAt] as String?;
      if (ca == null && cb == null) return 0;
      if (ca == null) return 1;
      if (cb == null) return -1;
      try {
        return DateTime.parse(cb).compareTo(DateTime.parse(ca));
      } catch (_) {
        return 0;
      }
    });
    return sorted;
  }

  Future<void> _loadAll() async {
    setState(() => _loadingMeta = true);
    try {
      final db = DatabaseHelper.instance;
      final t = await db.fetchTournament(widget.tournamentId);
      final m = await db.fetchMatchesByTournament(widget.tournamentId);

      String? winnerName;
      final winnerTeamId = t?[DatabaseHelper.colWinnerTeamId];
      if (winnerTeamId != null) {
        final rawDb = await db.database;
        final rows = await rawDb.query(
          DatabaseHelper.tableTournamentTeams,
          columns: [DatabaseHelper.colTeamName],
          where: '${DatabaseHelper.colId} = ?',
          whereArgs: [winnerTeamId],
          limit: 1,
        );
        if (rows.isNotEmpty) {
          winnerName = rows.first[DatabaseHelper.colTeamName] as String?;
        }
      }

      if (mounted) {
        setState(() {
          _tournament = t;
          _matches = _sortedNewestFirst(m);
          _resolvedWinnerName = winnerName;
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

  void _openMatch(Map<String, dynamic> match) {
    final id      = match[DatabaseHelper.colId]        as int;
    final teamA   = match[DatabaseHelper.colTeamA]     as String? ?? '';
    final teamB   = match[DatabaseHelper.colTeamB]     as String? ?? '';
    final status  = match[DatabaseHelper.colStatus]    as String? ?? '';
    final creator = match[DatabaseHelper.colCreatedBy] as String?;
    final userId  = AuthService.instance.userId;

    if (status == 'completed') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ScorecardScreen(matchId: id, teamA: teamA, teamB: teamB),
        ),
      ).then((_) => _loadAll());
    } else if (creator != null && creator == userId) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ScoringScreen(matchId: id)),
      ).then((_) => _loadAll());
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ScorecardScreen(matchId: id, teamA: teamA, teamB: teamB),
        ),
      ).then((_) => _loadAll());
    }
  }

  Future<void> _addMatch() async {
    final t = _tournament;
    if (t == null) return;
    final format = t[DatabaseHelper.colFormat] as String? ?? 'league';
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NewMatchScreen(
          tournamentId:     widget.tournamentId,
          tournamentFormat: format,
        ),
      ),
    );
    if (mounted) _loadAll();
  }

  Future<void> _addTeamToTournament() async {
    final c = Theme.of(context).appColors;

    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery(
      'SELECT DISTINCT ${DatabaseHelper.colTeam} FROM ${DatabaseHelper.tablePlayers} '
      'ORDER BY ${DatabaseHelper.colTeam} ASC',
    );
    final allTeamNames = rows.map((r) => r[DatabaseHelper.colTeam] as String).toList();

    final tournamentTeamRows =
        await DatabaseHelper.instance.fetchAllTournamentTeamRows(widget.tournamentId);
    final registeredNames =
        tournamentTeamRows.map((r) => r[DatabaseHelper.colTeamName] as String).toSet();

    final merged = <String>{...registeredNames, ...allTeamNames}.toList()..sort();

    if (!mounted) return;

    String? selected;
    final searchController = TextEditingController();

    Future<void> showCreateTeamDialog(
      BuildContext sheetCtx,
      void Function(void Function()) setModalState,
    ) async {
      final dc = Theme.of(sheetCtx).appColors;
      final newTeamController = TextEditingController();
      String? dialogError;

      await showDialog<void>(
        context: sheetCtx,
        barrierDismissible: false,
        builder: (dialogCtx) {
          return StatefulBuilder(
            builder: (dialogCtx, setDialogState) {
              return AlertDialog(
                backgroundColor: dc.card,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: Row(
                  children: [
                    Icon(Icons.add_circle_outline, color: dc.accentGreen, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Create New Team',
                      style: GoogleFonts.rajdhani(
                        fontSize: 17, fontWeight: FontWeight.w800, color: dc.textPrimary,
                      ),
                    ),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Enter a name for the new team. It will be created and '
                      'immediately added to this tournament.',
                      style: GoogleFonts.rajdhani(fontSize: 13, color: dc.textSecondary),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: newTeamController,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      style: GoogleFonts.rajdhani(fontSize: 15, color: dc.textPrimary),
                      onChanged: (_) {
                        if (dialogError != null) setDialogState(() => dialogError = null);
                      },
                      decoration: InputDecoration(
                        hintText: 'Team Name',
                        hintStyle: GoogleFonts.rajdhani(fontSize: 14, color: dc.textSecondary),
                        errorText: dialogError,
                        errorStyle: GoogleFonts.rajdhani(fontSize: 12, color: dc.liveRed),
                        prefixIcon: Icon(Icons.group_add, color: dc.accentGreen, size: 18),
                        filled: true,
                        fillColor: dc.card2,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: dc.accentGreen, width: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogCtx),
                    child: Text('Cancel',
                        style: GoogleFonts.rajdhani(fontSize: 14, color: dc.textSecondary)),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: dc.accentGreen,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () async {
                      final name = newTeamController.text.trim();
                      if (name.isEmpty) {
                        setDialogState(() => dialogError = 'Team name cannot be empty.');
                        return;
                      }
                      try {
                        await DatabaseHelper.instance
                            .createTeamAndAddToTournament(widget.tournamentId, name);
                        if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                        if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                        if (mounted) {
                          _loadAll();
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('$name created and added to the tournament.',
                                style: GoogleFonts.rajdhani(fontSize: 14)),
                            backgroundColor: dc.accentGreen,
                          ));
                        }
                      } on StateError catch (e) {
                        setDialogState(() => dialogError = e.message);
                      } catch (_) {
                        setDialogState(() => dialogError = 'Something went wrong. Try again.');
                      }
                    },
                    child: Text('Create & Add',
                        style: GoogleFonts.rajdhani(fontSize: 14, fontWeight: FontWeight.w800)),
                  ),
                ],
              );
            },
          );
        },
      );
      newTeamController.dispose();
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final bc = Theme.of(ctx).appColors;
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final filtered = searchController.text.trim().isEmpty
                ? merged
                : merged
                    .where((n) => n.toLowerCase()
                        .contains(searchController.text.trim().toLowerCase()))
                    .toList();

            return Padding(
              padding: EdgeInsets.only(
                left: 20, right: 20, top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.group_add, color: bc.trophyGold, size: 20),
                      const SizedBox(width: 8),
                      Text('Add Team to Tournament',
                          style: GoogleFonts.rajdhani(
                              fontSize: 18, fontWeight: FontWeight.w800, color: bc.textPrimary)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('Select an existing team or create a new one.',
                      style: GoogleFonts.rajdhani(fontSize: 13, color: bc.textSecondary)),
                  const SizedBox(height: 14),
                  TextField(
                    controller: searchController,
                    style: GoogleFonts.rajdhani(fontSize: 14, color: bc.textPrimary),
                    onChanged: (_) => setModalState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search team…',
                      hintStyle: GoogleFonts.rajdhani(fontSize: 14, color: bc.textSecondary),
                      prefixIcon: Icon(Icons.search, color: bc.accentGreen, size: 18),
                      filled: true,
                      fillColor: bc.card2,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => showCreateTeamDialog(ctx, setModalState),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: bc.accentGreen,
                        side: BorderSide(color: bc.accentGreen, width: 1.2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                      icon: const Icon(Icons.add, size: 16),
                      label: Text('+ Create New Team',
                          style: GoogleFonts.rajdhani(
                              fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: Text('No teams found.',
                            style: GoogleFonts.rajdhani(fontSize: 14, color: bc.textSecondary)),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 240),
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
                              margin: const EdgeInsets.symmetric(vertical: 3),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected ? bc.trophyGold.withAlpha(30) : bc.card2,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected ? bc.trophyGold.withAlpha(120) : bc.border,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isSelected ? Icons.check_circle : Icons.group,
                                    color: isSelected ? bc.trophyGold : bc.textSecondary,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(name,
                                        style: GoogleFonts.rajdhani(
                                          fontSize: 15,
                                          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                          color: isSelected ? bc.trophyGold : bc.textPrimary,
                                        )),
                                  ),
                                  if (isRegistered)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: bc.accentGreen.withAlpha(25),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text('REGISTERED',
                                          style: GoogleFonts.rajdhani(
                                              fontSize: 9, fontWeight: FontWeight.w700,
                                              color: bc.accentGreen, letterSpacing: 1)),
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
                      onPressed: selected == null ? null : () => Navigator.pop(ctx, selected),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: bc.trophyGold,
                        disabledBackgroundColor: bc.trophyGold.withAlpha(50),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text('Add to Tournament',
                          style: GoogleFonts.rajdhani(fontSize: 15, fontWeight: FontWeight.w800)),
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
      if (registeredNames.contains(teamName)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$teamName is already in this tournament.',
              style: GoogleFonts.rajdhani(fontSize: 14)),
          backgroundColor: c.card,
        ));
        return;
      }
      await DatabaseHelper.instance.insertTeamIntoTournament(widget.tournamentId, teamName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$teamName added to the tournament.',
              style: GoogleFonts.rajdhani(fontSize: 14)),
          backgroundColor: c.accentGreen,
        ));
        _loadAll();
      }
    });
    searchController.dispose();
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).appColors;
    if (_loadingMeta) {
      return Scaffold(
        backgroundColor: c.surface,
        body: Center(child: CircularProgressIndicator(color: c.accentGreen)),
      );
    }

    final t = _tournament;
    if (t == null) {
      return Scaffold(
        backgroundColor: c.surface,
        appBar: AppBar(backgroundColor: c.surface, foregroundColor: c.textPrimary),
        body: Center(
          child: Text('Tournament not found.',
              style: GoogleFonts.rajdhani(color: c.textSecondary, fontSize: 16)),
        ),
      );
    }

    final name   = t[DatabaseHelper.colName]   as String;
    final format = (t[DatabaseHelper.colFormat] as String? ?? 'league').toUpperCase();
    final status = t[DatabaseHelper.colStatus]  as String? ?? 'active';

    return Scaffold(
      backgroundColor: c.surface,
      body: NestedScrollView(
        headerSliverBuilder: (context2, _) => [_buildAppBar(context2, name, format, status)],
        body: Column(
          children: [
            _buildTabBar(c),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _MatchesTab(
                    matches: _matches,
                    onTapMatch: _openMatch,
                    onAddMatch: _addMatch,
                    onAddTeam: _addTeamToTournament,
                    tournamentStatus: status,
                    tournament: t,
                    resolvedWinnerName: _resolvedWinnerName,
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

  Widget _buildAppBar(BuildContext ctx, String name, String format, String status) {
    final c = Theme.of(ctx).appColors;
    return SliverAppBar(
      expandedHeight: 140,
      pinned: true,
      backgroundColor: c.surface,
      foregroundColor: c.textPrimary,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [c.surface, c.card],
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
                Icon(Icons.emoji_events, color: c.trophyGold, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(name,
                      style: GoogleFonts.rajdhani(
                        fontSize: 18, fontWeight: FontWeight.w900,
                        color: c.textPrimary, letterSpacing: 0.5,
                      ),
                      overflow: TextOverflow.ellipsis),
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

  Widget _buildTabBar(AppColors c) {
    return Container(
      color: c.surface,
      child: TabBar(
        controller: _tabController,
        indicatorColor: c.trophyGold,
        indicatorWeight: 2.5,
        labelColor: c.trophyGold,
        unselectedLabelColor: c.textSecondary,
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
    this.resolvedWinnerName,
  });

  final List<Map<String, dynamic>> matches;
  final void Function(Map<String, dynamic> match) onTapMatch;
  final VoidCallback onAddMatch;
  final VoidCallback onAddTeam;
  final String tournamentStatus;
  final Map<String, dynamic> tournament;
  final String? resolvedWinnerName;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).appColors;
    final isCompleted = tournamentStatus == 'completed';

    String? winnerName = resolvedWinnerName;
    if (winnerName == null) {
      final winnerTeamId = tournament[DatabaseHelper.colWinnerTeamId];
      if (winnerTeamId == null) {
        final finalMatch = matches.firstWhere(
          (m) =>
              m[DatabaseHelper.colMatchStage] == 'Final' &&
              m[DatabaseHelper.colStatus] == 'completed',
          orElse: () => {},
        );
        if (finalMatch.isNotEmpty) {
          final rawWinner = finalMatch[DatabaseHelper.colWinner] as String?;
          if (rawWinner != null && rawWinner.isNotEmpty) {
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
    }

    final live = matches
        .where((m) =>
            m[DatabaseHelper.colStatus] == 'live' ||
            m[DatabaseHelper.colStatus] == 'pending')
        .toList()
      ..sort((a, b) {
        final ca = a[DatabaseHelper.colCreatedAt] as String?;
        final cb = b[DatabaseHelper.colCreatedAt] as String?;
        if (ca == null && cb == null) return 0;
        if (ca == null) return 1;
        if (cb == null) return -1;
        try { return DateTime.parse(cb).compareTo(DateTime.parse(ca)); }
        catch (_) { return 0; }
      });
    final done = matches
        .where((m) => m[DatabaseHelper.colStatus] == 'completed')
        .toList()
      ..sort((a, b) {
        final ca = a[DatabaseHelper.colCreatedAt] as String?;
        final cb = b[DatabaseHelper.colCreatedAt] as String?;
        if (ca == null && cb == null) return 0;
        if (ca == null) return 1;
        if (cb == null) return -1;
        try { return DateTime.parse(cb).compareTo(DateTime.parse(ca)); }
        catch (_) { return 0; }
      });

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
      children: [
        if (isCompleted) ...[
          _ChampionsBanner(winnerName: winnerName),
          const SizedBox(height: 16),
        ],
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
                Icon(Icons.sports_cricket, size: 64, color: c.trophyGold.withAlpha(60)),
                const SizedBox(height: 16),
                Text('No Matches Yet',
                    style: GoogleFonts.rajdhani(
                        fontSize: 20, fontWeight: FontWeight.w700, color: c.textSecondary)),
                const SizedBox(height: 8),
                Text('Tap "Add Match" to start playing.',
                    style: GoogleFonts.rajdhani(fontSize: 14, color: c.textSecondary)),
              ],
            ),
          ),
        ] else ...[
          if (live.isNotEmpty) ...[
            _SectionHeader('ACTIVE', c.liveRed),
            const SizedBox(height: 10),
            ...live.map((m) => _MatchCard(match: m, onTap: () => onTapMatch(m), context: context)),
            const SizedBox(height: 20),
          ],
          if (done.isNotEmpty) ...[
            _SectionHeader('COMPLETED', c.completedBlue),
            const SizedBox(height: 10),
            ...done.map((m) => _MatchCard(match: m, onTap: () => onTapMatch(m), context: context)),
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
    final c = Theme.of(context).appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A1E00), Color(0xFF1C1200)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.trophyGold.withAlpha(120), width: 1.5),
        boxShadow: [
          BoxShadow(color: c.trophyGold.withAlpha(40), blurRadius: 16, spreadRadius: 2),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: c.trophyGold.withAlpha(30), shape: BoxShape.circle,
            ),
            child: Icon(Icons.emoji_events, color: c.trophyGold, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TOURNAMENT CHAMPION',
                    style: GoogleFonts.rajdhani(
                        fontSize: 11, fontWeight: FontWeight.w800,
                        color: c.trophyGold, letterSpacing: 2)),
                const SizedBox(height: 2),
                Text(winnerName ?? 'Champion',
                    style: GoogleFonts.rajdhani(
                        fontSize: 20, fontWeight: FontWeight.w900,
                        color: c.textPrimary, letterSpacing: 0.5),
                    overflow: TextOverflow.ellipsis),
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
    final c = Theme.of(context).appColors;
    return SizedBox(
      height: 50,
      child: ElevatedButton.icon(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: c.trophyGold,
          foregroundColor: Colors.black,
          elevation: 8,
          shadowColor: c.trophyGold.withAlpha(80),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: const Icon(Icons.add, size: 20),
        label: Text('Add Match',
            style: GoogleFonts.rajdhani(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 1)),
      ),
    );
  }
}

class _AddTeamButton extends StatelessWidget {
  const _AddTeamButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).appColors;
    return SizedBox(
      height: 46,
      child: OutlinedButton.icon(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: c.trophyGold,
          side: BorderSide(color: c.trophyGold.withAlpha(140), width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: const Icon(Icons.group_add, size: 18),
        label: Text('Add Late-Entry Team',
            style: GoogleFonts.rajdhani(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
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
    final c = Theme.of(context).appColors;
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
                color: c.textSecondary, letterSpacing: 2.5)),
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
    final c = Theme.of(ctx).appColors;
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
                        style: GoogleFonts.rajdhani(fontSize: 11, color: c.textSecondary)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(teamA,
                        style: GoogleFonts.rajdhani(
                            fontSize: 17, fontWeight: FontWeight.w800, color: c.textPrimary),
                        overflow: TextOverflow.ellipsis),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('VS',
                        style: GoogleFonts.rajdhani(
                            fontSize: 12, fontWeight: FontWeight.w900,
                            color: c.trophyGold, letterSpacing: 2)),
                  ),
                  Expanded(
                    child: Text(teamB,
                        textAlign: TextAlign.right,
                        style: GoogleFonts.rajdhani(
                            fontSize: 17, fontWeight: FontWeight.w800, color: c.textPrimary),
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.timer_outlined, size: 13, color: c.textSecondary),
                  const SizedBox(width: 4),
                  Text('$overs overs',
                      style: GoogleFonts.rajdhani(
                          fontSize: 12, color: c.textSecondary, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  if (status == 'completed')
                    GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => MatchSummaryScreen(matchId: id, teamA: teamA, teamB: teamB),
                      )),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: c.completedBlue.withAlpha(25),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: c.completedBlue.withAlpha(70)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.bar_chart, size: 12, color: c.completedBlue),
                          const SizedBox(width: 4),
                          Text('Summary',
                              style: GoogleFonts.rajdhani(
                                  fontSize: 11, fontWeight: FontWeight.w700, color: c.completedBlue)),
                        ]),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Icon(Icons.arrow_forward_ios,
                      size: 12, color: status == 'completed' ? c.trophyGold : c.accentGreen),
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
    final c = Theme.of(context).appColors;
    if (loading) {
      return Center(child: CircularProgressIndicator(color: c.accentGreen));
    }

    if (standings.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.table_chart_outlined, size: 64, color: c.trophyGold.withAlpha(60)),
            const SizedBox(height: 16),
            Text('No completed matches yet.',
                style: GoogleFonts.rajdhani(
                    fontSize: 18, fontWeight: FontWeight.w700, color: c.textSecondary)),
            const SizedBox(height: 8),
            Text('Points table will appear after matches complete.',
                style: GoogleFonts.rajdhani(fontSize: 13, color: c.textSecondary),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: onRefresh,
              icon: Icon(Icons.refresh, color: c.trophyGold),
              label: Text('Refresh',
                  style: GoogleFonts.rajdhani(
                      color: c.trophyGold, fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            GestureDetector(
              onTap: onRefresh,
              child: Row(
                children: [
                  Icon(Icons.refresh, size: 14, color: c.textSecondary),
                  const SizedBox(width: 4),
                  Text('Refresh',
                      style: GoogleFonts.rajdhani(
                          fontSize: 12, color: c.textSecondary, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _LeaderCard(standings.first),
        const SizedBox(height: 20),
        _TableHeader(),
        const SizedBox(height: 6),
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
    final c = Theme.of(context).appColors;
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
              colors: [c.trophyGold.withAlpha(40), c.trophyGold.withAlpha(10)],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.trophyGold.withAlpha(80), width: 1.5),
            boxShadow: [
              BoxShadow(color: c.trophyGold.withAlpha(20), blurRadius: 20, offset: const Offset(0, 6)),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: c.trophyGold.withAlpha(30),
                  shape: BoxShape.circle,
                  border: Border.all(color: c.trophyGold.withAlpha(100)),
                ),
                child: Icon(Icons.emoji_events, color: c.trophyGold, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('LEADING',
                        style: GoogleFonts.rajdhani(
                            fontSize: 10, fontWeight: FontWeight.w700,
                            color: c.trophyGold, letterSpacing: 2.5)),
                    Text(standing.teamName,
                        style: GoogleFonts.rajdhani(
                            fontSize: 22, fontWeight: FontWeight.w900, color: c.textPrimary),
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${standing.points}',
                      style: GoogleFonts.rajdhani(
                          fontSize: 36, fontWeight: FontWeight.w900, color: c.trophyGold, height: 1)),
                  Text('pts',
                      style: GoogleFonts.rajdhani(
                          fontSize: 11, color: c.trophyGold, fontWeight: FontWeight.w600)),
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
    final c = Theme.of(context).appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.card2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text('#', style: _headerStyle(c.textSecondary)),
          ),
          Expanded(child: Text('TEAM', style: _headerStyle(c.textSecondary))),
          _HeaderCell('P'),
          _HeaderCell('W'),
          _HeaderCell('L'),
          _HeaderCell('T'),
          _HeaderCell('NR'),
          _HeaderCell('PTS', isGold: true),
          _HeaderCell('NRR', width: 58),
        ],
      ),
    );
  }

  TextStyle _headerStyle(Color color) => GoogleFonts.rajdhani(
    fontSize: 11, fontWeight: FontWeight.w700, color: color, letterSpacing: 1.5,
  );
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.label, {this.isGold = false, this.width = 28});
  final String label;
  final bool isGold;
  final double width;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).appColors;
    final color = isGold ? c.trophyGold : c.textSecondary;
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
    final c = Theme.of(context).appColors;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isLeader ? c.trophyGold.withAlpha(12) : c.card.withAlpha(200),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isLeader ? c.trophyGold.withAlpha(50) : c.border,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: isLeader
                ? Icon(Icons.emoji_events, size: 14, color: c.trophyGold)
                : Text('$position',
                    style: GoogleFonts.rajdhani(
                        fontSize: 13, color: c.textSecondary, fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TeamHistoryScreen(teamName: standing.teamName),
                ),
              ),
              child: Text(
                standing.teamName,
                style: GoogleFonts.rajdhani(
                    fontSize: 14,
                    fontWeight: isLeader ? FontWeight.w800 : FontWeight.w600,
                    color: isLeader ? c.trophyGold : c.accentGreen,
                    decoration: TextDecoration.underline,
                    decorationColor: isLeader ? c.trophyGold.withAlpha(80) : c.accentGreen.withAlpha(80)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          _DataCell('${standing.played}'),
          _DataCell('${standing.won}', color: standing.won > 0 ? c.accentGreen : null),
          _DataCell('${standing.lost}', color: standing.lost > 0 ? c.liveRed.withAlpha(200) : null),
          _DataCell('${standing.tied}'),
          _DataCell('${standing.noResult}'),
          _DataCell('${standing.points}', bold: true, color: isLeader ? c.trophyGold : c.textPrimary),
          _DataCell(standing.nrrDisplay,
              width: 58,
              color: standing.nrr >= 0 ? c.accentGreen : c.liveRed.withAlpha(200)),
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
    final c = Theme.of(context).appColors;
    return SizedBox(
      width: width,
      child: Text(value,
          textAlign: TextAlign.center,
          style: GoogleFonts.rajdhani(
              fontSize: 13,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: color ?? c.textSecondary)),
    );
  }
}

class _NrrExplanation extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).appColors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.card2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('NET RUN RATE (NRR)',
              style: GoogleFonts.rajdhani(
                  fontSize: 11, fontWeight: FontWeight.w700,
                  color: c.textSecondary, letterSpacing: 2)),
          const SizedBox(height: 6),
          Text(
            'NRR = (Runs Scored ÷ Overs Faced) − (Runs Conceded ÷ Overs Bowled)\n'
            'All-out innings: actual overs faced. Full-over innings: max overs.',
            style: GoogleFonts.rajdhani(fontSize: 12, color: c.textSecondary, height: 1.5),
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
    final c = Theme.of(context).appColors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.card.withAlpha(230),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.trophyGold.withAlpha(35), width: 1),
            boxShadow: [
              BoxShadow(color: c.trophyGold.withAlpha(12), blurRadius: 12, offset: const Offset(0, 4)),
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
    final c = Theme.of(context).appColors;
    Color bg, fg;
    String label;
    switch (status) {
      case 'live':
        bg = c.liveRed.withAlpha(30); fg = c.liveRed; label = 'LIVE'; break;
      case 'completed':
        bg = c.completedBlue.withAlpha(30); fg = c.completedBlue; label = 'COMPLETED'; break;
      default:
        bg = c.accentGreen.withAlpha(20); fg = c.accentGreen; label = 'PENDING';
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
                color: c.liveRed, shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: c.liveRed.withAlpha(140), blurRadius: 4)],
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
    final c = Theme.of(context).appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: c.trophyGold.withAlpha(20),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(format,
          style: GoogleFonts.rajdhani(
              fontSize: 9, fontWeight: FontWeight.w700,
              color: c.trophyGold, letterSpacing: 1.5)),
    );
  }
}

class _TournamentStatusBadge extends StatelessWidget {
  const _TournamentStatusBadge(this.status);
  final String status;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).appColors;
    final isActive = status == 'active';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: isActive ? c.accentGreen.withAlpha(20) : c.completedBlue.withAlpha(20),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        isActive ? 'ACTIVE' : 'COMPLETED',
        style: GoogleFonts.rajdhani(
            fontSize: 9, fontWeight: FontWeight.w700,
            color: isActive ? c.accentGreen : c.completedBlue, letterSpacing: 1.5),
      ),
    );
  }
}
