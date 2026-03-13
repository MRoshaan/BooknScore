import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../services/database_helper.dart';
import '../theme.dart';
import 'scorecard_screen.dart';
import 'scoring_screen.dart';
import 'match_summary_screen.dart';

class MyMatchesScreen extends StatefulWidget {
  const MyMatchesScreen({super.key});

  @override
  State<MyMatchesScreen> createState() => _MyMatchesScreenState();
}

class _MyMatchesScreenState extends State<MyMatchesScreen> {
  List<Map<String, dynamic>> _allMatches = [];
  List<Map<String, dynamic>> _filtered   = [];
  bool _loading = true;

  final TextEditingController _search = TextEditingController();
  String _query = '';
  Timer? _searchDebounce;

  /// Status filter: null = all, 'live', 'completed', 'pending'
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 200), () {
      if (mounted) {
        setState(() {
          _query = _search.text.trim().toLowerCase();
          _applyFilter();
        });
      }
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final userId = AuthService.instance.userId;
      List<Map<String, dynamic>> raw;
      if (userId != null) {
        raw = await DatabaseHelper.instance.fetchMyMatches(userId);
      } else {
        raw = await DatabaseHelper.instance.fetchQuickMatches();
      }
      final all = _sortedNewestFirst(raw);
      if (mounted) {
        setState(() {
          _allMatches = all;
          _loading = false;
          _applyFilter();
        });
      }
    } catch (e, st) {
      debugPrint('MyMatchesScreen._load error: $e\n$st');
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Returns a new list sorted newest-first by [created_at].
  /// Always creates a fresh mutable copy — never sorts the raw DB result in-place.
  List<Map<String, dynamic>> _sortedNewestFirst(List<Map<String, dynamic>> source) {
    final list = List<Map<String, dynamic>>.from(source);
    list.sort((a, b) {
      final ca = a[DatabaseHelper.colCreatedAt] as String?;
      final cb = b[DatabaseHelper.colCreatedAt] as String?;
      final da = ca != null ? (DateTime.tryParse(ca) ?? DateTime.fromMillisecondsSinceEpoch(0)) : DateTime.fromMillisecondsSinceEpoch(0);
      final db = cb != null ? (DateTime.tryParse(cb) ?? DateTime.fromMillisecondsSinceEpoch(0)) : DateTime.fromMillisecondsSinceEpoch(0);
      return db.compareTo(da);
    });
    return list;
  }

  void _applyFilter() {
    var list = List<Map<String, dynamic>>.from(_allMatches);
    if (_statusFilter != null) {
      list = list.where((m) {
        final s = m[DatabaseHelper.colStatus] as String;
        if (_statusFilter == 'live') return s == 'live' || s == 'ongoing';
        return s == _statusFilter;
      }).toList();
    }
    if (_query.isNotEmpty) {
      list = list.where((m) {
        final a = (m[DatabaseHelper.colTeamA] as String).toLowerCase();
        final b = (m[DatabaseHelper.colTeamB] as String).toLowerCase();
        return a.contains(_query) || b.contains(_query);
      }).toList();
    }
    _filtered = _sortedNewestFirst(list);
  }

  void _openMatch(Map<String, dynamic> match) {
    final id      = match[DatabaseHelper.colId]        as int;
    final teamA   = match[DatabaseHelper.colTeamA]     as String;
    final teamB   = match[DatabaseHelper.colTeamB]     as String;
    final status  = match[DatabaseHelper.colStatus]    as String;
    final creator = match[DatabaseHelper.colCreatedBy] as String?;
    final userId  = AuthService.instance.userId;

    if (status == 'completed') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ScorecardScreen(matchId: id, teamA: teamA, teamB: teamB),
        ),
      ).then((_) { if (mounted) _load(); });
    } else if (creator != null && creator == userId) {
      // Do NOT call loadMatch() here — ScoringScreen.initState() owns that call.
      // Calling it here AND in initState() causes a double-load race condition
      // that doubles the score on resume.
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ScoringScreen(matchId: id)),
      ).then((_) { if (mounted) _load(); });
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ScorecardScreen(matchId: id, teamA: teamA, teamB: teamB),
        ),
      ).then((_) { if (mounted) _load(); });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).appColors;
    return Scaffold(
      backgroundColor: c.surface,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(c),
          _buildSearchBar(c),
          _buildFilterChips(c),
          if (_loading)
            SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: c.accentGreen)),
            )
          else if (_filtered.isEmpty)
            _buildEmptyState(c)
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _matchCard(_filtered[i], c),
                  childCount: _filtered.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAppBar(AppColors c) {
    return SliverAppBar(
      expandedHeight: 120,
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
              'My Matches',
              style: GoogleFonts.rajdhani(
                fontSize: 22, fontWeight: FontWeight.w900,
                color: c.textPrimary, letterSpacing: 1.5,
              ),
            ),
            Text(
              'FULL MATCH HISTORY',
              style: GoogleFonts.rajdhani(
                fontSize: 8, fontWeight: FontWeight.w700,
                color: c.accentGreen, letterSpacing: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(AppColors c) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: TextField(
              controller: _search,
              style: GoogleFonts.rajdhani(
                fontSize: 15, color: c.textPrimary, fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: 'Search team name…',
                hintStyle: GoogleFonts.rajdhani(fontSize: 15, color: c.textSecondary),
                prefixIcon: Icon(Icons.search, color: c.accentGreen, size: 20),
                suffixIcon: _query.isNotEmpty
                    ? GestureDetector(
                        onTap: () => _search.clear(),
                        child: Icon(Icons.close, color: c.textSecondary, size: 18),
                      )
                    : null,
                filled: true,
                fillColor: c.card.withAlpha(200),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: c.glassBorder, width: 1),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: c.glassBorder, width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: c.accentGreen, width: 1.5),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChips(AppColors c) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _FilterChip(label: 'All',       value: null,        current: _statusFilter, onTap: _setFilter),
              const SizedBox(width: 8),
              _FilterChip(label: 'Live',      value: 'live',      current: _statusFilter, onTap: _setFilter, accent: c.liveRed),
              const SizedBox(width: 8),
              _FilterChip(label: 'Completed', value: 'completed', current: _statusFilter, onTap: _setFilter, accent: c.completedBlue),
              const SizedBox(width: 8),
              _FilterChip(label: 'Pending',   value: 'pending',   current: _statusFilter, onTap: _setFilter, accent: c.accentGreen),
            ],
          ),
        ),
      ),
    );
  }

  void _setFilter(String? value) {
    setState(() {
      _statusFilter = value;
      _applyFilter();
    });
  }

  Widget _buildEmptyState(AppColors c) {
    return SliverFillRemaining(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sports_cricket, size: 72,
                color: c.accentGreen.withAlpha(50)),
            const SizedBox(height: 20),
            Text(
              _query.isNotEmpty || _statusFilter != null
                  ? 'No matches found'
                  : 'No Matches Yet',
              style: GoogleFonts.rajdhani(
                fontSize: 22, fontWeight: FontWeight.w700, color: c.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _query.isNotEmpty || _statusFilter != null
                  ? 'Try adjusting your search or filter.'
                  : 'Start a Quick Match to see your history here.',
              style: GoogleFonts.rajdhani(fontSize: 14, color: c.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _matchCard(Map<String, dynamic> match, AppColors c) {
    final id      = match[DatabaseHelper.colId]         as int;
    final teamA   = match[DatabaseHelper.colTeamA]      as String;
    final teamB   = match[DatabaseHelper.colTeamB]      as String;
    final overs   = match[DatabaseHelper.colTotalOvers] as int;
    final status  = match[DatabaseHelper.colStatus]     as String;
    final created = match[DatabaseHelper.colCreatedAt]  as String?;

    Color statusColor;
    String statusLabel;
    switch (status) {
      case 'live':
      case 'ongoing':
        statusColor = c.liveRed;       statusLabel = 'LIVE';      break;
      case 'completed':
        statusColor = c.completedBlue; statusLabel = 'COMPLETED'; break;
      default:
        statusColor = c.accentGreen;   statusLabel = 'PENDING';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => _openMatch(match),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: c.card.withAlpha(220),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.glassBorder, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Status badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor.withAlpha(30),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: statusColor.withAlpha(70)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (status == 'live' || status == 'ongoing')
                              Container(
                                width: 5, height: 5,
                                margin: const EdgeInsets.only(right: 5),
                                decoration: BoxDecoration(
                                  color: c.liveRed, shape: BoxShape.circle,
                                  boxShadow: [BoxShadow(
                                    color: c.liveRed.withAlpha(140), blurRadius: 4,
                                  )],
                                ),
                              ),
                            Text(
                              statusLabel,
                              style: GoogleFonts.rajdhani(
                                fontSize: 10, fontWeight: FontWeight.w700,
                                color: statusColor, letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      if (created != null)
                        Text(
                          _relDate(created),
                          style: GoogleFonts.rajdhani(
                            fontSize: 11, color: c.textSecondary,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(teamA,
                            style: GoogleFonts.rajdhani(
                              fontSize: 18, fontWeight: FontWeight.w800,
                              color: c.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('VS',
                            style: GoogleFonts.rajdhani(
                              fontSize: 13, fontWeight: FontWeight.w900,
                              color: c.accentGreen, letterSpacing: 2,
                            )),
                      ),
                      Expanded(
                        child: Text(teamB,
                            textAlign: TextAlign.right,
                            style: GoogleFonts.rajdhani(
                              fontSize: 18, fontWeight: FontWeight.w800,
                              color: c.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.timer_outlined, size: 13, color: c.textSecondary),
                      const SizedBox(width: 5),
                      Text('$overs overs',
                          style: GoogleFonts.rajdhani(
                            fontSize: 13, color: c.textSecondary,
                            fontWeight: FontWeight.w600,
                          )),
                      const Spacer(),
                      if (status == 'completed')
                        GestureDetector(
                          onTap: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => MatchSummaryScreen(
                              matchId: id, teamA: teamA, teamB: teamB,
                            ),
                          )),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: c.completedBlue.withAlpha(25),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: c.completedBlue.withAlpha(70)),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.bar_chart, size: 13,
                                  color: c.completedBlue),
                              const SizedBox(width: 4),
                              Text('Summary',
                                  style: GoogleFonts.rajdhani(
                                    fontSize: 11, fontWeight: FontWeight.w700,
                                    color: c.completedBlue,
                                  )),
                            ]),
                          ),
                        ),
                      const SizedBox(width: 8),
                      Icon(Icons.arrow_forward_ios, size: 13,
                          color: c.accentGreen),
                    ],
                  ),
                ],
              ),
            ),
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
      if (diff.inDays < 7)  return '${diff.inDays}d ago';
      return '${d.day}/${d.month}/${d.year}';
    } catch (_) { return ''; }
  }
}

// ── Filter Chip Widget ────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.value,
    required this.current,
    required this.onTap,
    this.accent = const Color(0xFF39FF14),
  });

  final String label;
  final String? value;
  final String? current;
  final ValueChanged<String?> onTap;
  final Color accent;

  bool get _selected => current == value;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).appColors;
    return GestureDetector(
      onTap: () => onTap(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: _selected ? accent.withAlpha(30) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _selected ? accent : c.glassBorder,
            width: _selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.rajdhani(
            fontSize: 13, fontWeight: FontWeight.w700,
            color: _selected ? accent : c.textSecondary,
          ),
        ),
      ),
    );
  }
}
