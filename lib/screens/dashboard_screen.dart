import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../services/auth_service.dart';
import '../providers/match_provider.dart';
import '../providers/tournament_provider.dart';
import 'new_match_screen.dart';
import 'scoring_screen.dart';
import 'analytics_screen.dart';
import 'players_screen.dart';
import 'match_summary_screen.dart';
import 'create_tournament_screen.dart';
import 'tournament_dashboard_screen.dart';

// ── Brand Palette ─────────────────────────────────────────────────────────────
const Color _accentGreen    = Color(0xFF39FF14);   // neon-green accent
const Color _accentGreenMid = Color(0xFF4CAF50);   // softer green for less-prominent elements
const Color _surfaceDark    = Color(0xFF0A0A0A);
const Color _surfaceCard    = Color(0xFF141414);
const Color _surfaceCard2   = Color(0xFF1C1C1C);
const Color _glassBorder    = Color(0x3239FF14);
const Color _textPrimary    = Colors.white;
const Color _textSecondary  = Color(0xFF8A8A8A);
const Color _liveRed        = Color(0xFFFF3D3D);
const Color _completedBlue  = Color(0xFF2196F3);
const Color _trophyGold     = Color(0xFFFFC107);

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
    return Scaffold(
      backgroundColor: _surfaceDark,
      body: IndexedStack(
        index: _currentTabIndex,
        children: _screens,
      ),
      bottomNavigationBar: _buildBottomNav(),
      floatingActionButton: _buildFAB(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _glassBorder, width: 1)),
      ),
      child: BottomNavigationBar(
        currentIndex: _currentTabIndex,
        onTap: _onTabTapped,
        backgroundColor: _surfaceDark,
        selectedItemColor: _accentGreen,
        unselectedItemColor: _textSecondary,
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

  Widget? _buildFAB() {
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
              backgroundColor: _accentGreen,
              foregroundColor: Colors.black,
              elevation: 12,
              shadowColor: _accentGreen.withAlpha(80),
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
              backgroundColor: _trophyGold,
              foregroundColor: Colors.black,
              elevation: 12,
              shadowColor: _trophyGold.withAlpha(80),
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
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  StreamSubscription<SyncState>? _syncSub;

  List<Map<String, dynamic>> get _filtered {
    if (_searchQuery.isEmpty) return _matches;
    final q = _searchQuery.toLowerCase();
    return _matches.where((m) {
      final a = (m[DatabaseHelper.colTeamA] as String).toLowerCase();
      final b = (m[DatabaseHelper.colTeamB] as String).toLowerCase();
      return a.contains(q) || b.contains(q);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadMatches();
    _syncStatus = SyncService.instance.state;
    _syncSub = SyncService.instance.syncStatusStream.listen((s) {
      if (mounted) setState(() => _syncStatus = s);
    });
    _searchCtrl.addListener(() => setState(() => _searchQuery = _searchCtrl.text));
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMatches() async {
    setState(() => _loading = true);
    try {
      // Quick matches = no tournament_id
      final all = await DatabaseHelper.instance.fetchQuickMatches();
      if (mounted) setState(() { _matches = all; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openScoring(int matchId) {
    context.read<MatchProvider>().loadMatch(matchId);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ScoringScreen(matchId: matchId)),
    ).then((_) { if (mounted) _loadMatches(); });
  }

  Future<void> _syncNow() async {
    try {
      final result = await SyncService.instance.syncAll();
      if (!mounted) return;
      _showSnack(
        result.totalSynced > 0
            ? 'Synced ${result.totalSynced} items to cloud'
            : 'Everything up to date',
        result.totalSynced > 0 ? _accentGreenMid : _textSecondary,
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
    return CustomScrollView(
      slivers: [
        _buildAppBar(),
        SliverToBoxAdapter(child: _buildSearchBar()),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          sliver: _loading
              ? const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator(color: _accentGreen)),
                )
              : _buildContent(),
        ),
      ],
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 130,
      floating: false,
      pinned: true,
      backgroundColor: _surfaceDark,
      automaticallyImplyLeading: false,
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
              'Wicket.pk',
              style: GoogleFonts.rajdhani(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: _textPrimary,
                letterSpacing: 2,
              ),
            ),
            Text(
              'LIVE CRICKET SCORER',
              style: GoogleFonts.rajdhani(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: _accentGreen,
                letterSpacing: 3.5,
              ),
            ),
          ],
        ),
      ),
      actions: [
        _buildSyncButton(),
        IconButton(
          icon: const Icon(Icons.logout, color: Colors.white54, size: 20),
          onPressed: _showLogoutDialog,
          tooltip: 'Sign out',
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildSyncButton() {
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
      case SyncState.synced:  icon = Icons.cloud_done;  color = _accentGreenMid; break;
      case SyncState.offline: icon = Icons.cloud_off;   color = Colors.white38;  break;
      case SyncState.error:   icon = Icons.cloud_sync;  color = Colors.orange;   break;
      default:                icon = Icons.cloud_queue; color = Colors.white54;
    }
    return IconButton(icon: Icon(icon, color: color), onPressed: _syncNow);
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: TextField(
        controller: _searchCtrl,
        style: GoogleFonts.rajdhani(fontSize: 15, color: _textPrimary),
        decoration: InputDecoration(
          hintText: 'Search quick matches...',
          hintStyle: GoogleFonts.rajdhani(fontSize: 15, color: _textSecondary),
          prefixIcon: const Icon(Icons.search, color: _accentGreenMid, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: _textSecondary, size: 18),
                  onPressed: _searchCtrl.clear,
                )
              : null,
          filled: true,
          fillColor: _surfaceCard,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _accentGreen, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final matches = _filtered;
    if (matches.isEmpty) return _buildEmptyState();

    final live = matches.where((m) =>
      m[DatabaseHelper.colStatus] == 'live' || m[DatabaseHelper.colStatus] == 'pending'
    ).toList();
    final done = matches.where((m) => m[DatabaseHelper.colStatus] == 'completed').toList();

    return SliverList(
      delegate: SliverChildListDelegate([
        if (live.isNotEmpty) ...[
          _sectionHeader('ACTIVE', _liveRed),
          const SizedBox(height: 10),
          ...live.map((m) => _matchCard(m)),
          const SizedBox(height: 20),
        ],
        if (done.isNotEmpty) ...[
          _sectionHeader('COMPLETED', _completedBlue),
          const SizedBox(height: 10),
          ...done.map((m) => _matchCard(m)),
        ],
        const SizedBox(height: 110),
      ]),
    );
  }

  Widget _buildEmptyState() {
    return SliverFillRemaining(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sports_cricket, size: 72, color: _accentGreen.withAlpha(60)),
            const SizedBox(height: 20),
            Text(
              _searchQuery.isNotEmpty ? 'No results found' : 'No Quick Matches Yet',
              style: GoogleFonts.rajdhani(
                fontSize: 22, fontWeight: FontWeight.w700, color: _textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isNotEmpty
                  ? 'Try a different search.'
                  : 'Tap "Quick Match" below to start scoring.',
              style: GoogleFonts.rajdhani(fontSize: 14, color: _textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 110),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, Color accent) {
    return Row(
      children: [
        Container(
          width: 3, height: 18,
          decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: GoogleFonts.rajdhani(
            fontSize: 11, fontWeight: FontWeight.w700,
            color: _textSecondary, letterSpacing: 2.5,
          ),
        ),
      ],
    );
  }

  Widget _matchCard(Map<String, dynamic> match) {
    final id     = match[DatabaseHelper.colId]       as int;
    final teamA  = match[DatabaseHelper.colTeamA]    as String;
    final teamB  = match[DatabaseHelper.colTeamB]    as String;
    final overs  = match[DatabaseHelper.colTotalOvers] as int;
    final status = match[DatabaseHelper.colStatus]   as String;
    final created = match[DatabaseHelper.colCreatedAt] as String?;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => _openScoring(id),
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
                        style: GoogleFonts.rajdhani(fontSize: 11, color: _textSecondary)),
                ],
              ),
              const SizedBox(height: 14),
              _TeamsRow(teamA: teamA, teamB: teamB),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.timer_outlined, size: 13, color: _textSecondary),
                  const SizedBox(width: 5),
                  Text('$overs overs',
                      style: GoogleFonts.rajdhani(
                          fontSize: 13, color: _textSecondary, fontWeight: FontWeight.w600)),
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
                          const Icon(Icons.bar_chart, size: 13, color: _completedBlue),
                          const SizedBox(width: 4),
                          Text('Summary',
                              style: GoogleFonts.rajdhani(
                                  fontSize: 11, fontWeight: FontWeight.w700, color: _completedBlue)),
                        ]),
                      ),
                    ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_ios, size: 13, color: _accentGreenMid),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _surfaceCard2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Sign Out', style: GoogleFonts.rajdhani(fontWeight: FontWeight.w700, color: _textPrimary)),
        content: Text('Are you sure you want to sign out?',
            style: GoogleFonts.rajdhani(color: _textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.rajdhani(color: _textSecondary, fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () async { Navigator.pop(context); await AuthService.instance.signOut(); },
            child: Text('Sign Out', style: GoogleFonts.rajdhani(color: Colors.redAccent, fontWeight: FontWeight.w700)),
          ),
        ],
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
    return Consumer<TournamentProvider>(
      builder: (context, provider, _) {
        return CustomScrollView(
          slivers: [
            // App bar
            SliverAppBar(
              pinned: true,
              backgroundColor: _surfaceDark,
              automaticallyImplyLeading: false,
              title: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tournaments',
                      style: GoogleFonts.rajdhani(
                          fontSize: 24, fontWeight: FontWeight.w900, color: _textPrimary)),
                  Text('LEAGUE & KNOCKOUT ENGINE',
                      style: GoogleFonts.rajdhani(
                          fontSize: 9, fontWeight: FontWeight.w700,
                          color: _trophyGold, letterSpacing: 3)),
                ],
              ),
            ),

            // Content
            if (provider.isLoading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator(color: _accentGreen)),
              )
            else if (provider.tournaments.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.emoji_events, size: 72, color: _trophyGold.withAlpha(60)),
                      const SizedBox(height: 20),
                      Text('No Tournaments Yet',
                          style: GoogleFonts.rajdhani(
                              fontSize: 22, fontWeight: FontWeight.w700, color: _textSecondary)),
                      const SizedBox(height: 8),
                      Text('Tap "Create Tournament" below.',
                          style: GoogleFonts.rajdhani(fontSize: 14, color: _textSecondary)),
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
                    (_, i) => _tournamentCard(provider.tournaments[i]),
                    childCount: provider.tournaments.length,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _tournamentCard(Map<String, dynamic> t) {
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
          accentColor: _trophyGold,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: status == 'active'
                          ? _accentGreen.withAlpha(25)
                          : _completedBlue.withAlpha(25),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: status == 'active'
                            ? _accentGreen.withAlpha(80)
                            : _completedBlue.withAlpha(80),
                      ),
                    ),
                    child: Text(
                      status == 'active' ? 'ACTIVE' : 'COMPLETED',
                      style: GoogleFonts.rajdhani(
                        fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5,
                        color: status == 'active' ? _accentGreen : _completedBlue,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _trophyGold.withAlpha(20),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      format.toUpperCase(),
                      style: GoogleFonts.rajdhani(
                        fontSize: 10, fontWeight: FontWeight.w700,
                        letterSpacing: 1.5, color: _trophyGold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.emoji_events, size: 20, color: _trophyGold),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      name,
                      style: GoogleFonts.rajdhani(
                        fontSize: 20, fontWeight: FontWeight.w800, color: _textPrimary,
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
                    color: _surfaceCard2,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF2A2A2A)),
                  ),
                  child: Text(team,
                      style: GoogleFonts.rajdhani(
                          fontSize: 11, color: _textSecondary, fontWeight: FontWeight.w600)),
                )).toList()
                  ..addAll(teams.length > 6
                      ? [Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _surfaceCard2,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text('+${teams.length - 6} more',
                              style: GoogleFonts.rajdhani(
                                  fontSize: 11, color: _textSecondary)),
                        )]
                      : []),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.group_outlined, size: 13, color: _textSecondary),
                  const SizedBox(width: 4),
                  Text('${teams.length} teams',
                      style: GoogleFonts.rajdhani(
                          fontSize: 12, color: _textSecondary, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text('View Dashboard',
                      style: GoogleFonts.rajdhani(
                          fontSize: 12, fontWeight: FontWeight.w700, color: _trophyGold)),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward_ios, size: 12, color: _trophyGold),
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
    final border = accentColor ?? _accentGreen;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _surfaceCard.withAlpha(230),
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
    return Row(
      children: [
        Expanded(
          child: Text(teamA,
              style: GoogleFonts.rajdhani(
                  fontSize: 18, fontWeight: FontWeight.w800, color: _textPrimary),
              overflow: TextOverflow.ellipsis),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text('VS',
              style: GoogleFonts.rajdhani(
                  fontSize: 13, fontWeight: FontWeight.w900,
                  color: _accentGreen, letterSpacing: 2)),
        ),
        Expanded(
          child: Text(teamB,
              textAlign: TextAlign.right,
              style: GoogleFonts.rajdhani(
                  fontSize: 18, fontWeight: FontWeight.w800, color: _textPrimary),
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
                color: _liveRed, shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: _liveRed.withAlpha(140), blurRadius: 4)],
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
