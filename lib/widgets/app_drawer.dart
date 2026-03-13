import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../screens/team_history_screen.dart';
import '../screens/analytics_screen.dart';
import '../screens/my_matches_screen.dart';
import '../screens/teams_list_screen.dart';
import '../screens/global_match_viewer_screen.dart';
import '../screens/tournament_dashboard_screen.dart';
import '../screens/settings_screen.dart';
import '../theme.dart';

class WicketAppDrawer extends StatelessWidget {
  const WicketAppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).appColors;
    final user = AuthService.instance.currentUser;
    final email = user?.email ?? 'Guest';

    return Drawer(
      backgroundColor: c.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Profile Header ──────────────────────────────────────────────
            _DrawerHeader(email: email),
            Divider(color: c.glassBorder, height: 1),
            const SizedBox(height: 8),

            // ── Navigation items ─────────────────────────────────────────────
            _DrawerItem(
              icon: Icons.history,
              label: 'My Matches',
              subtitle: 'Full match history',
              accent: c.neon,
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MyMatchesScreen()),
                );
              },
            ),
            _DrawerItem(
              icon: Icons.public,
              label: 'Global Live Matches',
              subtitle: 'Community scorecards',
              accent: c.liveRed,
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const _GlobalMatchesScreen()),
                );
              },
            ),
            _DrawerItem(
              icon: Icons.group_work_outlined,
              label: 'My Teams',
              subtitle: 'Squad history & stats',
              accent: c.accentGreen,
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TeamsListScreen()),
                );
              },
            ),
            _DrawerItem(
              icon: Icons.analytics_outlined,
              label: 'Global Analytics',
              subtitle: 'All-player stats & charts',
              accent: c.completedBlue,
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const _GlobalAnalyticsScreen(),
                  ),
                );
              },
            ),
            _DrawerItem(
              icon: Icons.emoji_events_outlined,
              label: 'My Tournaments',
              subtitle: 'Your created tournaments',
              accent: c.trophyGold,
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const _MyTournamentsScreen()),
                );
              },
            ),
            _DrawerItem(
              icon: Icons.public,
              label: 'Global Tournaments',
              subtitle: 'Community tournaments',
              accent: c.accentGreen,
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const _GlobalTournamentsScreen()),
                );
              },
            ),

            _DrawerItem(
              icon: Icons.settings_outlined,
              label: 'Settings',
              subtitle: 'Theme & preferences',
              accent: c.accentGreen,
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
            ),

            const Spacer(),
            Divider(color: c.glassBorder, height: 1),

            // ── Sign Out ─────────────────────────────────────────────────────
            _DrawerItem(
              icon: Icons.logout,
              label: 'Sign Out',
              subtitle: '',
              accent: Colors.redAccent,
              onTap: () async {
                Navigator.pop(context);
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) {
                    final dc = Theme.of(ctx).appColors;
                    return AlertDialog(
                      backgroundColor: dc.card,
                      title: Text(
                        'Sign Out?',
                        style: GoogleFonts.rajdhani(
                          color: dc.textPrimary, fontWeight: FontWeight.w700,
                        ),
                      ),
                      content: Text(
                        'You will be returned to the login screen.',
                        style: GoogleFonts.rajdhani(color: dc.textSecondary),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text('Cancel',
                              style: GoogleFonts.rajdhani(color: dc.textSecondary)),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text('Sign Out',
                              style: GoogleFonts.rajdhani(
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                    );
                  },
                );
                if (confirmed == true) {
                  await AuthService.instance.signOut();
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Drawer Header ─────────────────────────────────────────────────────────────

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader({required this.email});
  final String email;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).appColors;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F1F0F), Color(0xFF0A0A0A)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.neon.withAlpha(20),
              border: Border.all(color: c.neon.withAlpha(100), width: 2),
            ),
            child: Icon(Icons.person, color: c.neon, size: 28),
          ),
          const SizedBox(height: 14),
          Text(
            'BooknScore',
            style: GoogleFonts.rajdhani(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: c.textPrimary,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            email,
            style: GoogleFonts.rajdhani(fontSize: 13, color: c.textSecondary),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ── Drawer Item ───────────────────────────────────────────────────────────────

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).appColors;
    return InkWell(
      onTap: onTap,
      splashColor: accent.withAlpha(20),
      highlightColor: accent.withAlpha(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: accent.withAlpha(20),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: accent.withAlpha(50), width: 1),
              ),
              child: Icon(icon, color: accent, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.rajdhani(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: c.textPrimary,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: GoogleFonts.rajdhani(
                        fontSize: 12,
                        color: c.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: c.textSecondary, size: 18),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// GLOBAL ANALYTICS SCREEN — All-player stats (no user filter)
// ══════════════════════════════════════════════════════════════════════════════

class _GlobalAnalyticsScreen extends StatelessWidget {
  const _GlobalAnalyticsScreen();

  @override
  Widget build(BuildContext context) =>
      const AnalyticsScreen(userOnly: false);
}

// ══════════════════════════════════════════════════════════════════════════════
// GLOBAL MATCHES SCREEN — Community live / recent matches feed
// ══════════════════════════════════════════════════════════════════════════════

class _GlobalMatchesScreen extends StatefulWidget {
  const _GlobalMatchesScreen();

  @override
  State<_GlobalMatchesScreen> createState() => _GlobalMatchesScreenState();
}

class _GlobalMatchesScreenState extends State<_GlobalMatchesScreen> {
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  bool _refreshing = false;
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), _runSearch);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final raw = await DatabaseHelper.instance.fetchRecentGlobalMatches(limit: 15);
      final rows = _sortedMatchesNewestFirst(raw);
      if (mounted) {
        setState(() {
          _filtered = rows;
          _loading = false;
        });
      }
    } catch (e, st) {
      debugPrint('GlobalMatchesScreen._load error: $e\n$st');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _runSearch() async {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty) {
      await _load();
      return;
    }
    setState(() => _loading = true);
    try {
      final raw = await DatabaseHelper.instance.searchGlobalMatches(query);
      final rows = _sortedMatchesNewestFirst(raw);
      if (mounted) {
        setState(() {
          _filtered = rows;
          _loading = false;
        });
      }
    } catch (e, st) {
      debugPrint('GlobalMatchesScreen._runSearch error: $e\n$st');
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Pull-to-refresh: trigger a downward sync from Supabase, then reload local DB.
  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await SyncService.instance.syncDownInitialData(force: true);
    } catch (_) {
      // Non-fatal — show whatever is cached locally.
    }
    await _load();
    if (mounted) setState(() => _refreshing = false);
  }

  void _openMatch(Map<String, dynamic> match) {
    final id    = match[DatabaseHelper.colId]    as int;
    final teamA = match[DatabaseHelper.colTeamA] as String;
    final teamB = match[DatabaseHelper.colTeamB] as String;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GlobalMatchViewerScreen(
          matchId: id,
          teamA:   teamA,
          teamB:   teamB,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).appColors;
    return Scaffold(
      backgroundColor: c.surface,
      body: RefreshIndicator(
        color: c.liveRed,
        backgroundColor: c.card,
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── App Bar ───────────────────────────────────────────────────────
            SliverAppBar(
            expandedHeight: 110,
            floating: false,
            pinned: true,
            backgroundColor: c.surface,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new, color: c.textPrimary, size: 18),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              centerTitle: true,
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1A0A0A), Color(0xFF0A0A0A)],
                  ),
                ),
              ),
              title: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Global Matches',
                    style: GoogleFonts.rajdhani(
                      fontSize: 20, fontWeight: FontWeight.w900, color: c.textPrimary,
                    ),
                  ),
                  Text(
                    'COMMUNITY SCORECARDS',
                    style: GoogleFonts.rajdhani(
                      fontSize: 8, fontWeight: FontWeight.w700,
                      color: c.liveRed, letterSpacing: 3,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Sticky Search Bar ─────────────────────────────────────────────
          SliverPersistentHeader(
            pinned: true,
            delegate: _SearchBarDelegate(
              child: Container(
                color: c.surface,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  controller: _searchCtrl,
                  style: GoogleFonts.rajdhani(color: c.textPrimary, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'Search by team name…',
                    hintStyle: GoogleFonts.rajdhani(color: c.textSecondary, fontSize: 15),
                    prefixIcon: Icon(Icons.search, color: c.textSecondary, size: 20),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear, color: c.textSecondary, size: 18),
                            onPressed: () => _searchCtrl.clear(),
                          )
                        : null,
                    filled: true,
                    fillColor: c.card,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF242424)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: c.liveRed.withAlpha(120), width: 1.5),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Body ──────────────────────────────────────────────────────────
          if (_loading)
            SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: c.neon)),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              sliver: _filtered.isEmpty
                  ? SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.public_off, size: 64,
                                color: c.liveRed.withAlpha(60)),
                            const SizedBox(height: 16),
                            Text(
                              _searchCtrl.text.isNotEmpty
                                  ? 'No matches found'
                                  : 'No Community Matches',
                              style: GoogleFonts.rajdhani(
                                fontSize: 20, fontWeight: FontWeight.w700,
                                color: c.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _searchCtrl.text.isNotEmpty
                                  ? 'Try a different team name.'
                                  : 'Pull down to sync the latest matches.',
                              style: GoogleFonts.rajdhani(
                                  fontSize: 13, color: c.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    )
                  : SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (ctx, i) => _GlobalMatchCard(
                          match: _filtered[i],
                          onTap: () => _openMatch(_filtered[i]),
                        ),
                        childCount: _filtered.length,
                      ),
                    ),
            ),
        ],
        ),  // CustomScrollView
      ),    // RefreshIndicator
    );
  }
}

// ── Search bar persistent header delegate ─────────────────────────────────────
class _SearchBarDelegate extends SliverPersistentHeaderDelegate {
  const _SearchBarDelegate({required this.child});
  final Widget child;

  @override
  double get minExtent => 60;
  @override
  double get maxExtent => 60;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => child;

  @override
  bool shouldRebuild(_SearchBarDelegate old) => old.child != child;
}

String _relDate(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  try {
    final d = DateTime.parse(iso);
    final diff = DateTime.now().difference(d);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${d.day}/${d.month}/${d.year}';
  } catch (_) {
    return '';
  }
}

/// Returns a new mutable list sorted newest-first by [created_at].
/// Never calls .sort() on the raw unmodifiable list returned by db.query().
List<Map<String, dynamic>> _sortedMatchesNewestFirst(
    List<Map<String, dynamic>> source) {
  final list = List<Map<String, dynamic>>.from(source);
  list.sort((a, b) {
    final ca = a[DatabaseHelper.colCreatedAt] as String?;
    final cb = b[DatabaseHelper.colCreatedAt] as String?;
    final da = ca != null
        ? (DateTime.tryParse(ca) ?? DateTime.fromMillisecondsSinceEpoch(0))
        : DateTime.fromMillisecondsSinceEpoch(0);
    final db = cb != null
        ? (DateTime.tryParse(cb) ?? DateTime.fromMillisecondsSinceEpoch(0))
        : DateTime.fromMillisecondsSinceEpoch(0);
    return db.compareTo(da);
  });
  return list;
}

class _GlobalMatchCard extends StatelessWidget {
  const _GlobalMatchCard({required this.match, required this.onTap});
  final Map<String, dynamic> match;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).appColors;
    final teamA     = match[DatabaseHelper.colTeamA]  as String;
    final teamB     = match[DatabaseHelper.colTeamB]  as String;
    final status    = match[DatabaseHelper.colStatus] as String;
    final overs     = match[DatabaseHelper.colTotalOvers] as int;
    final createdAt = match[DatabaseHelper.colCreatedAt] as String?;

    Color statusColor;
    String statusLabel;
    switch (status) {
      case 'live':
      case 'ongoing':
        statusColor = c.liveRed; statusLabel = 'LIVE'; break;
      case 'completed':
        statusColor = c.completedBlue; statusLabel = 'COMPLETED'; break;
      default:
        statusColor = c.neon; statusLabel = 'PENDING';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF242424), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$teamA vs $teamB',
                      style: GoogleFonts.rajdhani(
                        fontSize: 16, fontWeight: FontWeight.w800, color: c.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withAlpha(25),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: statusColor.withAlpha(70)),
                    ),
                    child: Text(
                      statusLabel,
                      style: GoogleFonts.rajdhani(
                        fontSize: 10, fontWeight: FontWeight.w700,
                        color: statusColor, letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    '$overs overs',
                    style: GoogleFonts.rajdhani(fontSize: 13, color: c.textSecondary),
                  ),
                  const Spacer(),
                  if (createdAt != null && createdAt.isNotEmpty)
                    Text(
                      _relDate(createdAt),
                      style: GoogleFonts.rajdhani(fontSize: 11, color: c.textSecondary),
                    ),
                  if (createdAt == null || createdAt.isEmpty)
                    Icon(Icons.arrow_forward_ios, size: 13, color: c.textSecondary.withAlpha(100)),
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
// TEAMS HUB SCREEN — List of all distinct teams the current user has played
// ══════════════════════════════════════════════════════════════════════════════

class _TeamsHubScreen extends StatefulWidget {
  const _TeamsHubScreen();

  @override
  State<_TeamsHubScreen> createState() => _TeamsHubScreenState();
}

class _TeamsHubScreenState extends State<_TeamsHubScreen> {
  List<String> _teams = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final names = await DatabaseHelper.instance.fetchDistinctTeamNames();
      if (mounted) setState(() { _teams = names; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).appColors;
    return Scaffold(
      backgroundColor: c.surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 110,
            floating: false,
            pinned: true,
            backgroundColor: c.surface,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new, color: c.textPrimary, size: 18),
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
                      fontSize: 20, fontWeight: FontWeight.w900, color: c.textPrimary,
                    ),
                  ),
                  Text(
                    'SQUAD HISTORY',
                    style: GoogleFonts.rajdhani(
                      fontSize: 8, fontWeight: FontWeight.w700,
                      color: c.neon, letterSpacing: 3,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_loading)
            SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: c.neon)),
            )
          else if (_teams.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.group_work_outlined, size: 64,
                        color: c.neon.withAlpha(60)),
                    const SizedBox(height: 16),
                    Text(
                      'No Teams Yet',
                      style: GoogleFonts.rajdhani(
                        fontSize: 20, fontWeight: FontWeight.w700, color: c.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Add players with team names to see them here.',
                      style: GoogleFonts.rajdhani(fontSize: 13, color: c.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _TeamTile(teamName: _teams[i]),
                  childCount: _teams.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TeamTile extends StatelessWidget {
  const _TeamTile({required this.teamName});
  final String teamName;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).appColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TeamHistoryScreen(teamName: teamName),
          ),
        ),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF242424), width: 1),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: c.neon.withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.neon.withAlpha(50), width: 1),
                ),
                child: Icon(Icons.shield_outlined, color: c.accentGreen, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  teamName,
                  style: GoogleFonts.rajdhani(
                    fontSize: 17, fontWeight: FontWeight.w700, color: c.textPrimary,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: c.textSecondary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// MY TOURNAMENTS SCREEN — Tournaments created by the current user
// ══════════════════════════════════════════════════════════════════════════════

class _MyTournamentsScreen extends StatefulWidget {
  const _MyTournamentsScreen();

  @override
  State<_MyTournamentsScreen> createState() => _MyTournamentsScreenState();
}

class _MyTournamentsScreenState extends State<_MyTournamentsScreen> {
  List<Map<String, dynamic>> _all = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  bool _showAll = false;
  final TextEditingController _searchCtrl = TextEditingController();
  static const int _defaultLimit = 5;

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_applyFilter);
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final userId = AuthService.instance.currentUser?.id;
      final rows = userId != null
          ? await DatabaseHelper.instance.fetchTournamentsByCreator(userId)
          : <Map<String, dynamic>>[];
      if (mounted) {
        setState(() {
          _all = rows;
          _loading = false;
        });
        _applyFilter();
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilter() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? List.of(_all)
          : _all.where((t) {
              final name = (t[DatabaseHelper.colName] as String? ?? '').toLowerCase();
              return name.contains(q);
            }).toList();
    });
  }

  void _openTournament(Map<String, dynamic> t) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TournamentDashboardScreen(
          tournamentId: t[DatabaseHelper.colId] as int,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).appColors;
    final displayed = (_showAll || _searchCtrl.text.isNotEmpty)
        ? _filtered
        : _filtered.take(_defaultLimit).toList();

    return Scaffold(
      backgroundColor: c.surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 110,
            floating: false,
            pinned: true,
            backgroundColor: c.surface,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new, color: c.textPrimary, size: 18),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              centerTitle: true,
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1A1200), Color(0xFF0A0A0A)],
                  ),
                ),
              ),
              title: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'My Tournaments',
                    style: GoogleFonts.rajdhani(
                      fontSize: 20, fontWeight: FontWeight.w900, color: c.textPrimary,
                    ),
                  ),
                  Text(
                    'YOUR CREATED TOURNAMENTS',
                    style: GoogleFonts.rajdhani(
                      fontSize: 10, color: c.trophyGold, letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ── Sticky search bar ─────────────────────────────────────────────
          SliverPersistentHeader(
            pinned: true,
            delegate: _SearchBarDelegate(
              child: Container(
                color: c.surface,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  controller: _searchCtrl,
                  style: GoogleFonts.rajdhani(color: c.textPrimary, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'Search tournaments…',
                    hintStyle: GoogleFonts.rajdhani(color: c.textSecondary, fontSize: 15),
                    prefixIcon: Icon(Icons.search, color: c.textSecondary, size: 20),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear, color: c.textSecondary, size: 18),
                            onPressed: () => _searchCtrl.clear(),
                          )
                        : null,
                    filled: true,
                    fillColor: c.card,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF242424)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFFFC107), width: 1.5),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_loading)
            SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: c.trophyGold)),
            )
          else if (_filtered.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Text(
                  _searchCtrl.text.isNotEmpty ? 'No tournaments match.' : 'No tournaments yet.',
                  style: GoogleFonts.rajdhani(color: c.textSecondary, fontSize: 16),
                ),
              ),
            )
          else ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _TournamentTile(
                    tournament: displayed[i],
                    accent: c.trophyGold,
                    onTap: () => _openTournament(displayed[i]),
                  ),
                  childCount: displayed.length,
                ),
              ),
            ),
            if (!_showAll && _searchCtrl.text.isEmpty && _filtered.length > _defaultLimit)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: TextButton(
                    onPressed: () => setState(() => _showAll = true),
                    style: TextButton.styleFrom(
                      foregroundColor: c.trophyGold,
                      backgroundColor: c.trophyGold.withAlpha(20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(
                      'Show all ${_filtered.length} tournaments',
                      style: GoogleFonts.rajdhani(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// GLOBAL TOURNAMENTS SCREEN — All tournaments community-wide
// ══════════════════════════════════════════════════════════════════════════════

class _GlobalTournamentsScreen extends StatefulWidget {
  const _GlobalTournamentsScreen();

  @override
  State<_GlobalTournamentsScreen> createState() => _GlobalTournamentsScreenState();
}

class _GlobalTournamentsScreenState extends State<_GlobalTournamentsScreen> {
  List<Map<String, dynamic>> _all = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  bool _refreshing = false;
  bool _showAll = false;
  final TextEditingController _searchCtrl = TextEditingController();
  static const int _defaultLimit = 5;

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_applyFilter);
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await DatabaseHelper.instance.fetchAllTournaments();
      if (mounted) {
        setState(() {
          _all = rows;
          _loading = false;
        });
        _applyFilter();
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await SyncService.instance.syncDownInitialData(force: true);
      await _load();
    } catch (_) {
      // ignore sync errors on refresh
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _applyFilter() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? List.of(_all)
          : _all.where((t) {
              final name = (t[DatabaseHelper.colName] as String? ?? '').toLowerCase();
              return name.contains(q);
            }).toList();
    });
  }

  void _openTournament(Map<String, dynamic> t) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TournamentDashboardScreen(
          tournamentId: t[DatabaseHelper.colId] as int,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).appColors;
    final displayed = (_showAll || _searchCtrl.text.isNotEmpty)
        ? _filtered
        : _filtered.take(_defaultLimit).toList();

    return Scaffold(
      backgroundColor: c.surface,
      body: RefreshIndicator(
        color: c.neon,
        backgroundColor: c.card,
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              expandedHeight: 110,
              floating: false,
              pinned: true,
              backgroundColor: c.surface,
              leading: IconButton(
                icon: Icon(Icons.arrow_back_ios_new, color: c.textPrimary, size: 18),
                onPressed: () => Navigator.pop(context),
              ),
              flexibleSpace: FlexibleSpaceBar(
                centerTitle: true,
                background: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF0A1A0A), Color(0xFF0A0A0A)],
                    ),
                  ),
                ),
                title: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Global Tournaments',
                      style: GoogleFonts.rajdhani(
                        fontSize: 20, fontWeight: FontWeight.w900, color: c.textPrimary,
                      ),
                    ),
                    Text(
                      'COMMUNITY TOURNAMENTS',
                      style: GoogleFonts.rajdhani(
                        fontSize: 10, color: c.accentGreen, letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // ── Sticky search bar ─────────────────────────────────────────────
            SliverPersistentHeader(
              pinned: true,
              delegate: _SearchBarDelegate(
                child: Container(
                  color: c.surface,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: TextField(
                    controller: _searchCtrl,
                    style: GoogleFonts.rajdhani(color: c.textPrimary, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: 'Search tournaments…',
                      hintStyle: GoogleFonts.rajdhani(color: c.textSecondary, fontSize: 15),
                      prefixIcon: Icon(Icons.search, color: c.textSecondary, size: 20),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear, color: c.textSecondary, size: 18),
                              onPressed: () => _searchCtrl.clear(),
                            )
                          : null,
                      filled: true,
                      fillColor: c.card,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF242424)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: c.neon.withAlpha(150), width: 1.5),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_loading)
              SliverFillRemaining(
                child: Center(child: CircularProgressIndicator(color: c.neon)),
              )
            else if (_filtered.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Text(
                    _searchCtrl.text.isNotEmpty ? 'No tournaments match.' : 'No tournaments yet.',
                    style: GoogleFonts.rajdhani(color: c.textSecondary, fontSize: 16),
                  ),
                ),
              )
            else ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => _TournamentTile(
                      tournament: displayed[i],
                      accent: c.neon,
                      onTap: () => _openTournament(displayed[i]),
                    ),
                    childCount: displayed.length,
                  ),
                ),
              ),
              if (!_showAll && _searchCtrl.text.isEmpty && _filtered.length > _defaultLimit)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: TextButton(
                      onPressed: () => setState(() => _showAll = true),
                      style: TextButton.styleFrom(
                        foregroundColor: c.neon,
                        backgroundColor: c.neon.withAlpha(20),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        'Show all ${_filtered.length} tournaments',
                        style: GoogleFonts.rajdhani(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Tournament tile ────────────────────────────────────────────────────────────

class _TournamentTile extends StatelessWidget {
  const _TournamentTile({
    required this.tournament,
    required this.accent,
    required this.onTap,
  });
  final Map<String, dynamic> tournament;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).appColors;
    final name   = tournament[DatabaseHelper.colName]   as String? ?? 'Tournament';
    final format = tournament[DatabaseHelper.colFormat] as String? ?? '';
    final status = tournament[DatabaseHelper.colStatus] as String? ?? '';
    final isActive = status == 'active';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF242424), width: 1),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: accent.withAlpha(50), width: 1),
                ),
                child: Icon(Icons.emoji_events_outlined, color: accent, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.rajdhani(
                        fontSize: 16, fontWeight: FontWeight.w700, color: c.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (format.isNotEmpty)
                      Text(
                        format,
                        style: GoogleFonts.rajdhani(fontSize: 12, color: c.textSecondary),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isActive
                      ? const Color(0xFFFF3D3D).withAlpha(30)
                      : c.textSecondary.withAlpha(30),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isActive ? 'LIVE' : 'DONE',
                  style: GoogleFonts.rajdhani(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: isActive ? const Color(0xFFFF3D3D) : c.textSecondary,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, color: c.textSecondary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
