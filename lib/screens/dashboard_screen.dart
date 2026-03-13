import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/app_drawer.dart';
import 'scorecard_screen.dart';
import '../providers/tournament_provider.dart';
import 'new_match_screen.dart';
import 'scoring_screen.dart';
import 'analytics_screen.dart';
import 'players_screen.dart';
import 'match_summary_screen.dart';
import 'create_tournament_screen.dart';
import 'tournament_dashboard_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // 0 = Quick Matches, 1 = Tournaments, 2 = Analytics, 3 = Players
  int _currentTabIndex = 0;

  final GlobalKey<_QuickMatchTabState> _quickKey = GlobalKey<_QuickMatchTabState>();
  final GlobalKey<_TournamentsTabState> _tourKey  = GlobalKey<_TournamentsTabState>();

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      _QuickMatchTab(key: _quickKey),
      _TournamentsTab(key: _tourKey),
      const AnalyticsScreen(),
      const PlayersScreen(),
    ];
  }

  void _onTabTapped(int idx) {
    setState(() => _currentTabIndex = idx);
    // Refresh data when switching to a data-bearing tab
    if (idx == 0) _quickKey.currentState?._loadMatches();
    if (idx == 1) _tourKey.currentState?._load();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).appColors;
    return Scaffold(
      backgroundColor: c.surface,
      drawer: const WicketAppDrawer(),
      body: IndexedStack(
        index: _currentTabIndex,
        children: _screens,
      ),
      bottomNavigationBar: _buildBottomNav(c),
      floatingActionButton: _buildFAB(c),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildBottomNav(AppColors c) {
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.glassBorder, width: 1)),
      ),
      child: BottomNavigationBar(
        currentIndex: _currentTabIndex,
        onTap: _onTabTapped,
        backgroundColor: c.surface,
        selectedItemColor: c.neon,
        unselectedItemColor: c.textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: GoogleFonts.rajdhani(fontWeight: FontWeight.w700, fontSize: 11),
        unselectedLabelStyle: GoogleFonts.rajdhani(fontWeight: FontWeight.w600, fontSize: 11),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.sports_cricket_outlined),
            activeIcon: Icon(Icons.sports_cricket),
            label: 'Quick Match',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.emoji_events_outlined),
            activeIcon: Icon(Icons.emoji_events),
            label: 'Tournaments',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.analytics_outlined),
            activeIcon: Icon(Icons.analytics),
            label: 'Analytics',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people_outline),
            activeIcon: Icon(Icons.people),
            label: 'Players',
          ),
        ],
      ),
    );
  }

  Widget? _buildFAB(AppColors c) {
    if (_currentTabIndex == 0) {
      // Quick Match FAB
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        child: SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton.icon(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NewMatchScreen()),
              );
              if (mounted) _quickKey.currentState?._loadMatches();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: c.neon,
              foregroundColor: Colors.black,
              elevation: 12,
              shadowColor: c.neon.withAlpha(80),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.add, size: 22),
            label: Text(
              'Quick Match',
              style: GoogleFonts.rajdhani(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
      );
    }
    if (_currentTabIndex == 1) {
      // Create Tournament FAB
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        child: SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton.icon(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CreateTournamentScreen()),
              );
              if (mounted) _tourKey.currentState?._load();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: c.trophyGold,
              foregroundColor: Colors.black,
              elevation: 12,
              shadowColor: c.trophyGold.withAlpha(80),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.emoji_events, size: 22),
            label: Text(
              'Create Tournament',
              style: GoogleFonts.rajdhani(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
      );
    }
    return null;
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// QUICK MATCH TAB
// ══════════════════════════════════════════════════════════════════════════════

class _QuickMatchTab extends StatefulWidget {
  const _QuickMatchTab({super.key});
  @override
  State<_QuickMatchTab> createState() => _QuickMatchTabState();
}

class _QuickMatchTabState extends State<_QuickMatchTab> {
  List<Map<String, dynamic>> _matches = [];
  bool _loading = true;
  SyncState _syncStatus = SyncState.idle;
  StreamSubscription<SyncState>? _syncSub;

  @override
  void initState() {
    super.initState();
    _loadMatches();
    _syncStatus = SyncService.instance.state;
    _syncSub = SyncService.instance.syncStatusStream.listen((s) {
      if (!mounted) return;
      setState(() => _syncStatus = s);
      // Re-query local DB whenever a sync finishes so new matches appear.
      if (s == SyncState.idle || s == SyncState.synced) {
        _reloadMatchesFromDb();
      }
    });
  }

  /// Lightweight re-query of local SQLite — no network call, no spinner.
  Future<void> _reloadMatchesFromDb() async {
    try {
      final userId = AuthService.instance.userId;
      final List<Map<String, dynamic>> all;
      if (userId != null) {
        all = await DatabaseHelper.instance.fetchRecentMatches(userId);
      } else {
        all = await DatabaseHelper.instance.fetchQuickMatches();
      }
      if (mounted) setState(() => _matches = all);
    } catch (_) {
      // Non-fatal — silently ignore.
    }
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    super.dispose();
  }

  Future<void> _loadMatches() async {
    setState(() => _loading = true);
    try {
      final userId = AuthService.instance.userId;
      final List<Map<String, dynamic>> all;
      if (userId != null) {
        all = await DatabaseHelper.instance.fetchRecentMatches(userId);
      } else {
        all = await DatabaseHelper.instance.fetchQuickMatches();
      }
      if (mounted) setState(() { _matches = all; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openMatch(Map<String, dynamic> match) {
    final id      = match[DatabaseHelper.colId]        as int;
    final teamA   = match[DatabaseHelper.colTeamA]     as String;
    final teamB   = match[DatabaseHelper.colTeamB]     as String;
    final status  = match[DatabaseHelper.colStatus]    as String;
    final creator = match[DatabaseHelper.colCreatedBy] as String?;
    final userId  = AuthService.instance.userId;

    // Completed matches → direct to Scorecard (read-only), bypassing summary.
    if (status == 'completed') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ScorecardScreen(matchId: id, teamA: teamA, teamB: teamB),
        ),
      ).then((_) { if (mounted) _loadMatches(); });
    } else if (status == 'live' || status == 'ongoing' || status == 'pending') {
      // Ongoing / live / pending matches:
      // Creator → resume in ScoringScreen (loadMatch is called exclusively by
      // ScoringScreen.initState to avoid double-load race conditions).
      // Non-creator → read-only scorecard.
      if (creator != null && creator == userId) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ScoringScreen(matchId: id)),
        ).then((_) { if (mounted) _loadMatches(); });
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ScorecardScreen(matchId: id, teamA: teamA, teamB: teamB),
          ),
        ).then((_) { if (mounted) _loadMatches(); });
      }
    } else {
      // Fallback: show scorecard for any unknown status.
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ScorecardScreen(matchId: id, teamA: teamA, teamB: teamB),
        ),
      ).then((_) { if (mounted) _loadMatches(); });
    }
  }

  Future<void> _syncNow() async {
    final c = Theme.of(context).appColors;
    try {
      final result = await SyncService.instance.syncAll();
      if (!mounted) return;
      _showSnack(
        result.totalSynced > 0
            ? 'Synced ${result.totalSynced} items to cloud'
            : 'Everything up to date',
        result.totalSynced > 0 ? c.accentGreen : c.textSecondary,
        Icons.cloud_done,
      );
    } catch (e) {
      if (!mounted) return;
      _showSnack('Sync failed', Colors.redAccent, Icons.cloud_off);
    }
  }

  void _showSnack(String msg, Color bg, IconData icon) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(icon, color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(msg, style: GoogleFonts.rajdhani(fontWeight: FontWeight.w600))),
      ]),
      backgroundColor: bg,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).appColors;
    return CustomScrollView(
      slivers: [
        _buildAppBar(c),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          sliver: _loading
              ? SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator(color: c.accentGreen)),
                )
              : _buildContent(c),
        ),
      ],
    );
  }

  Widget _buildAppBar(AppColors c) {
    return SliverAppBar(
      expandedHeight: 130,
      floating: false,
      pinned: true,
      backgroundColor: c.surface,
      automaticallyImplyLeading: false,
      leading: Builder(
        builder: (ctx) => IconButton(
          icon: Icon(Icons.menu, color: c.textSecondary, size: 22),
          onPressed: () => Scaffold.of(ctx).openDrawer(),
          tooltip: 'Menu',
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        centerTitle: true,
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [c.surface, c.card],
            ),
          ),
        ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'BooknScore',
              style: GoogleFonts.rajdhani(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: c.textPrimary,
                letterSpacing: 2,
              ),
            ),
            Text(
              'LIVE CRICKET SCORER',
              style: GoogleFonts.rajdhani(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: c.accentGreen,
                letterSpacing: 3.5,
              ),
            ),
          ],
        ),
      ),
      actions: [
        _buildSyncButton(c),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildSyncButton(AppColors c) {
    if (_syncStatus == SyncState.syncing) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: SizedBox(
          width: 20, height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
        ),
      );
    }
    IconData icon;
    Color color;
    switch (_syncStatus) {
      case SyncState.synced:  icon = Icons.cloud_done;  color = c.accentGreen; break;
      case SyncState.offline: icon = Icons.cloud_off;   color = c.textSecondary; break;
      case SyncState.error:   icon = Icons.cloud_sync;  color = Colors.orange;   break;
      default:                icon = Icons.cloud_queue; color = c.textSecondary;
    }
    return IconButton(icon: Icon(icon, color: color), onPressed: _syncNow);
  }

  Widget _buildContent(AppColors c) {
    if (_matches.isEmpty) return _buildEmptyState(c);

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (ctx, i) {
          // Index 0: section header
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(top: 18, bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 18,
                    decoration: BoxDecoration(
                      color: c.accentGreen,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'RECENT MATCHES',
                    style: GoogleFonts.rajdhani(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: c.textSecondary,
                      letterSpacing: 2.5,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Scaffold.of(ctx).openDrawer(),
                    child: Text(
                      'See all',
                      style: GoogleFonts.rajdhani(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: c.accentGreen,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
          // Indices 1..N: match cards
          final m = _matches[i - 1];
          return _matchCard(ctx, m, c);
        },
        childCount: _matches.length + 1, // +1 for header
      ),
    );
  }

  Widget _buildEmptyState(AppColors c) {
    return SliverFillRemaining(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sports_cricket, size: 72, color: c.accentGreen.withAlpha(60)),
            const SizedBox(height: 20),
            Text(
              'No Matches Yet',
              style: GoogleFonts.rajdhani(
                fontSize: 22, fontWeight: FontWeight.w700, color: c.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap "Quick Match" below to start your first match.',
              style: GoogleFonts.rajdhani(fontSize: 14, color: c.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 110),
          ],
        ),
      ),
    );
  }

  Widget _matchCard(BuildContext ctx, Map<String, dynamic> match, AppColors c) {
    final id     = match[DatabaseHelper.colId]       as int;
    final teamA  = match[DatabaseHelper.colTeamA]    as String;
    final teamB  = match[DatabaseHelper.colTeamB]    as String;
    final overs  = match[DatabaseHelper.colTotalOvers] as int;
    final status = match[DatabaseHelper.colStatus]   as String;
    final created = match[DatabaseHelper.colCreatedAt] as String?;

    final isOngoing = status == 'live' || status == 'ongoing' || status == 'pending';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => _openMatch(match),
        child: _PremiumCard(
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
              const SizedBox(height: 14),
              _TeamsRow(teamA: teamA, teamB: teamB),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.timer_outlined, size: 13, color: c.textSecondary),
                  const SizedBox(width: 5),
                  Text('$overs overs',
                      style: GoogleFonts.rajdhani(
                          fontSize: 13, color: c.textSecondary, fontWeight: FontWeight.w600)),
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
                          Icon(Icons.bar_chart, size: 13, color: c.completedBlue),
                          const SizedBox(width: 4),
                          Text('Summary',
                              style: GoogleFonts.rajdhani(
                                  fontSize: 11, fontWeight: FontWeight.w700, color: c.completedBlue)),
                        ]),
                      ),
                    ),
                  if (isOngoing)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: c.liveRed.withAlpha(20),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: c.liveRed.withAlpha(60)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.play_circle_outline, size: 13, color: c.liveRed),
                        const SizedBox(width: 4),
                        Text('Resume',
                            style: GoogleFonts.rajdhani(
                                fontSize: 11, fontWeight: FontWeight.w700, color: c.liveRed)),
                      ]),
                    ),
                  const SizedBox(width: 8),
                  Icon(Icons.arrow_forward_ios, size: 13, color: c.accentGreen),
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
// TOURNAMENTS TAB
// ══════════════════════════════════════════════════════════════════════════════

class _TournamentsTab extends StatefulWidget {
  const _TournamentsTab({super.key});
  @override
  State<_TournamentsTab> createState() => _TournamentsTabState();
}

class _TournamentsTabState extends State<_TournamentsTab> {
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    context.read<TournamentProvider>().loadTournaments();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).appColors;
    return Consumer<TournamentProvider>(
      builder: (context, provider, _) {
        return CustomScrollView(
          slivers: [
            // App bar
            SliverAppBar(
              pinned: true,
              backgroundColor: c.surface,
              automaticallyImplyLeading: false,
              title: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tournaments',
                      style: GoogleFonts.rajdhani(
                          fontSize: 24, fontWeight: FontWeight.w900, color: c.textPrimary)),
                  Text('LEAGUE & KNOCKOUT ENGINE',
                      style: GoogleFonts.rajdhani(
                          fontSize: 9, fontWeight: FontWeight.w700,
                          color: c.trophyGold, letterSpacing: 3)),
                ],
              ),
            ),

            // Content
            if (provider.isLoading)
              SliverFillRemaining(
                child: Center(child: CircularProgressIndicator(color: c.accentGreen)),
              )
            else if (provider.tournaments.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.emoji_events, size: 72, color: c.trophyGold.withAlpha(60)),
                      const SizedBox(height: 20),
                      Text('No Tournaments Yet',
                          style: GoogleFonts.rajdhani(
                              fontSize: 22, fontWeight: FontWeight.w700, color: c.textSecondary)),
                      const SizedBox(height: 8),
                      Text(
                        "You haven't created any tournaments yet. Tap + to start one.",
                        style: GoogleFonts.rajdhani(fontSize: 14, color: c.textSecondary),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 110),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => _tournamentCard(provider.tournaments[i], c),
                    childCount: provider.tournaments.length,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _tournamentCard(Map<String, dynamic> t, AppColors c) {
    final id     = t[DatabaseHelper.colId]    as int;
    final name   = t[DatabaseHelper.colName]  as String;
    final format = t[DatabaseHelper.colFormat] as String? ?? 'league';
    final status = t[DatabaseHelper.colStatus] as String? ?? 'active';
    final teamsRaw = t[DatabaseHelper.colTeams] as String? ?? '';
    final teams = teamsRaw.split(',').where((s) => s.isNotEmpty).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => TournamentDashboardScreen(tournamentId: id)),
        ).then((_) => _load()),
        child: _PremiumCard(
          accentColor: c.trophyGold,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: status == 'active'
                          ? c.accentGreen.withAlpha(25)
                          : c.completedBlue.withAlpha(25),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: status == 'active'
                            ? c.accentGreen.withAlpha(80)
                            : c.completedBlue.withAlpha(80),
                      ),
                    ),
                    child: Text(
                      status == 'active' ? 'ACTIVE' : 'COMPLETED',
                      style: GoogleFonts.rajdhani(
                        fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5,
                        color: status == 'active' ? c.accentGreen : c.completedBlue,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: c.trophyGold.withAlpha(20),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      format.toUpperCase(),
                      style: GoogleFonts.rajdhani(
                        fontSize: 10, fontWeight: FontWeight.w700,
                        letterSpacing: 1.5, color: c.trophyGold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.emoji_events, size: 20, color: c.trophyGold),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      name,
                      style: GoogleFonts.rajdhani(
                        fontSize: 20, fontWeight: FontWeight.w800, color: c.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: teams.take(6).map((team) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: c.card2,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: c.border),
                  ),
                  child: Text(team,
                      style: GoogleFonts.rajdhani(
                          fontSize: 11, color: c.textSecondary, fontWeight: FontWeight.w600)),
                )).toList()
                  ..addAll(teams.length > 6
                      ? [Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: c.card2,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text('+${teams.length - 6} more',
                              style: GoogleFonts.rajdhani(
                                  fontSize: 11, color: c.textSecondary)),
                        )]
                      : []),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.group_outlined, size: 13, color: c.textSecondary),
                  const SizedBox(width: 4),
                  Text('${teams.length} teams',
                      style: GoogleFonts.rajdhani(
                          fontSize: 12, color: c.textSecondary, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text('View Dashboard',
                      style: GoogleFonts.rajdhani(
                          fontSize: 12, fontWeight: FontWeight.w700, color: c.trophyGold)),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_ios, size: 12, color: c.trophyGold),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// REUSABLE WIDGET ATOMS
// ══════════════════════════════════════════════════════════════════════════════

/// Glass-morphism card with optional accent border glow.
class _PremiumCard extends StatelessWidget {
  const _PremiumCard({required this.child, this.accentColor});
  final Widget child;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).appColors;
    final border = accentColor ?? c.accentGreen;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: c.card.withAlpha(230),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border.withAlpha(40), width: 1),
            boxShadow: [
              BoxShadow(
                color: border.withAlpha(15),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _TeamsRow extends StatelessWidget {
  const _TeamsRow({required this.teamA, required this.teamB});
  final String teamA;
  final String teamB;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).appColors;
    return Row(
      children: [
        Expanded(
          child: Text(teamA,
              style: GoogleFonts.rajdhani(
                  fontSize: 18, fontWeight: FontWeight.w800, color: c.textPrimary),
              overflow: TextOverflow.ellipsis),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text('VS',
              style: GoogleFonts.rajdhani(
                  fontSize: 13, fontWeight: FontWeight.w900,
                  color: c.accentGreen, letterSpacing: 2)),
        ),
        Expanded(
          child: Text(teamB,
              textAlign: TextAlign.right,
              style: GoogleFonts.rajdhani(
                  fontSize: 18, fontWeight: FontWeight.w800, color: c.textPrimary),
              overflow: TextOverflow.ellipsis),
        ),
      ],
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
      case 'ongoing':
        bg = c.liveRed.withAlpha(30); fg = c.liveRed; label = 'LIVE'; break;
      case 'completed':
        bg = c.completedBlue.withAlpha(30); fg = c.completedBlue; label = 'COMPLETED'; break;
      default:
        bg = c.accentGreen.withAlpha(20); fg = c.accentGreen; label = 'PENDING';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
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
          Text(label, style: GoogleFonts.rajdhani(
              fontSize: 10, fontWeight: FontWeight.w700,
              color: fg, letterSpacing: 1.5)),
        ],
      ),
    );
  }
}
