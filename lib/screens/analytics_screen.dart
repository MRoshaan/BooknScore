import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';

import '../services/auth_service.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../theme.dart';

/// Player Analytics Screen
/// Displays:
///  • Top Scorers Manhattan chart (BarChart)
///  • Bowlers Economy chart (BarChart)
///  • Career stats cards for all players
///
/// [userOnly] — when true (default), only shows stats for the current user's
/// players. When false, shows stats for all players in the local DB.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key, this.userOnly = true});

  final bool userOnly;

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final _db = DatabaseHelper.instance;
  List<Map<String, dynamic>> _playerStats = [];
  List<Map<String, dynamic>> _filteredStats = [];
  bool _loading = true;
  bool _syncing = false;
  StreamSubscription<SyncState>? _syncSub;
  String _sortBy = 'runs'; // 'runs', 'average', 'strike_rate', 'wickets', 'economy'
  bool _ascending = false;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    // Reload whenever a sync completes so freshly downloaded stats appear.
    _syncSub = SyncService.instance.syncStatusStream.listen((state) {
      if (state == SyncState.synced || state == SyncState.error) {
        _loadPlayerStats();
      }
    });
    // Only load local user stats — no global sync on init.
    // For global view, sync first to get all community data.
    if (widget.userOnly) {
      _loadPlayerStats();
    } else {
      _syncAndLoad();
    }
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Trigger a global downward sync then recompute stats from local SQLite.
  Future<void> _syncAndLoad() async {
    if (mounted) setState(() => _syncing = true);
    try {
      await SyncService.instance.syncDownInitialData(force: true);
    } finally {
      if (mounted) setState(() => _syncing = false);
      await _loadPlayerStats();
    }
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 200), () {
      if (mounted) {
        final q = _searchController.text.trim().toLowerCase();
        setState(() {
          _searchQuery = q;
          _applyFilter();
        });
      }
    });
  }

  void _applyFilter() {
    if (_searchQuery.isEmpty) {
      _filteredStats = List.of(_playerStats);
    } else {
      _filteredStats = _playerStats.where((p) {
        final name = (p['name'] as String).toLowerCase();
        final team = (p['team'] as String).toLowerCase();
        return name.contains(_searchQuery) || team.contains(_searchQuery);
      }).toList();
    }
  }

  Future<void> _loadPlayerStats() async {
    setState(() => _loading = true);
    
    try {
      final db = await _db.database;
      
      // Get players — filter by current user when userOnly is true
      final userId = AuthService.instance.userId;
      final players = widget.userOnly
          ? (userId != null
              ? await db.query(
                  DatabaseHelper.tablePlayers,
                  where: '${DatabaseHelper.colCreatedBy} = ?',
                  whereArgs: [userId],
                )
              : <Map<String, dynamic>>[])
          : await db.query(DatabaseHelper.tablePlayers);

      if (players.isEmpty) {
        setState(() {
          _playerStats = [];
          _loading = false;
          _applyFilter();
        });
        return;
      }

      // ── Bulk-fetch all ball events once — avoids N+1 DB queries ─────────────
      final allEvents = await db.query(DatabaseHelper.tableBallEvents);

      // Group events by striker, bowler, and out-player for O(1) lookup.
      final Map<int, List<Map<String, dynamic>>> byStriker  = {};
      final Map<int, List<Map<String, dynamic>>> byBowler   = {};
      final Map<int, List<Map<String, dynamic>>> byOutPlayer = {};

      for (final e in allEvents) {
        final strikerId   = e[DatabaseHelper.colStrikerId]   as int?;
        final bowlerId    = e[DatabaseHelper.colBowlerId]    as int?;
        final outPlayerId = e[DatabaseHelper.colOutPlayerId] as int?;
        final isWicket    = (e[DatabaseHelper.colIsWicket]   as int?) == 1;

        if (strikerId != null) {
          (byStriker[strikerId] ??= []).add(e);
        }
        if (bowlerId != null) {
          (byBowler[bowlerId] ??= []).add(e);
        }
        if (isWicket && outPlayerId != null) {
          (byOutPlayer[outPlayerId] ??= []).add(e);
        }
      }
      // ─────────────────────────────────────────────────────────────────────────

      final stats = <Map<String, dynamic>>[];
      
      for (final player in players) {
        final playerId    = player[DatabaseHelper.colId]   as int;
        final playerName  = player[DatabaseHelper.colName] as String;
        final team        = player[DatabaseHelper.colTeam] as String;
        
        // Calculate stats from pre-fetched slices — no DB I/O per player.
        final battingStats = _calculateCareerBattingStatsFromEvents(
          byStriker[playerId] ?? [],
          byOutPlayer[playerId] ?? [],
        );
        final bowlingStats = _calculateCareerBowlingStatsFromEvents(
          byBowler[playerId] ?? [],
        );
        
        stats.add({
          'id':   playerId,
          'name': playerName,
          'team': team,
          ...battingStats,
          ...bowlingStats,
        });
      }
      
      _sortStats(stats);
      
      setState(() {
        _playerStats = stats;
        _loading = false;
        _applyFilter();
      });
    } catch (e) {
      debugPrint('Error loading player stats: $e');
      setState(() => _loading = false);
    }
  }

  Map<String, dynamic> _calculateCareerBattingStatsFromEvents(
    List<Map<String, dynamic>> battingEvents,
    List<Map<String, dynamic>> dismissalEvents,
  ) {
    int totalRuns  = 0;
    int ballsFaced = 0;
    int fours      = 0;
    int sixes      = 0;

    final inningsPlayed = <String>{};

    for (final e in battingEvents) {
      final matchId   = e[DatabaseHelper.colMatchId]    as int;
      final inningsNum= e[DatabaseHelper.colInnings]    as int;
      final extraType = e[DatabaseHelper.colExtraType]  as String?;
      final runsScored= e[DatabaseHelper.colRunsScored] as int;
      final isBoundary= (e[DatabaseHelper.colIsBoundary] as int) == 1;

      inningsPlayed.add('$matchId-$inningsNum');

      if (extraType != 'bye' && extraType != 'leg_bye') {
        totalRuns += runsScored;
      }
      if (extraType != 'wide') {
        ballsFaced++;
      }
      if (isBoundary) {
        if (runsScored == 4) fours++;
        if (runsScored == 6) sixes++;
      }
    }

    final innings     = inningsPlayed.length;
    final dismissals  = dismissalEvents.length;
    final average     = dismissals > 0 ? totalRuns / dismissals : totalRuns.toDouble();
    final strikeRate  = ballsFaced > 0 ? (totalRuns / ballsFaced) * 100 : 0.0;

    return {
      'totalRuns':       totalRuns,
      'ballsFaced':      ballsFaced,
      'fours':           fours,
      'sixes':           sixes,
      'battingInnings':  innings,
      'notOuts':         (innings - dismissals).clamp(0, innings),
      'battingAverage':  average,
      'strikeRate':      strikeRate,
    };
  }

  Map<String, dynamic> _calculateCareerBowlingStatsFromEvents(
    List<Map<String, dynamic>> bowlingEvents,
  ) {
    int legalBalls    = 0;
    int runsConceded  = 0;
    int wickets       = 0;
    int maidens       = 0;

    final overRuns      = <String, int>{};
    final overBalls     = <String, int>{};
    final inningsBowled = <String>{};

    for (final e in bowlingEvents) {
      final matchId   = e[DatabaseHelper.colMatchId]   as int;
      final inningsNum= e[DatabaseHelper.colInnings]   as int;
      final overNum   = e[DatabaseHelper.colOverNum]   as int;
      final extraType = e[DatabaseHelper.colExtraType] as String?;
      final runsScored= e[DatabaseHelper.colRunsScored]as int;
      final extraRuns = e[DatabaseHelper.colExtraRuns] as int;
      final isWicket  = (e[DatabaseHelper.colIsWicket] as int) == 1;
      final wicketType= e[DatabaseHelper.colWicketType] as String?;

      inningsBowled.add('$matchId-$inningsNum');
      final overKey = '$matchId-$inningsNum-$overNum';

      if (extraType != 'bye' && extraType != 'leg_bye') {
        runsConceded += runsScored + extraRuns;
        overRuns[overKey] = (overRuns[overKey] ?? 0) + runsScored + extraRuns;
      } else {
        runsConceded += extraRuns;
        overRuns[overKey] = (overRuns[overKey] ?? 0) + extraRuns;
      }

      if (extraType != 'wide' && extraType != 'no_ball') {
        legalBalls++;
        overBalls[overKey] = (overBalls[overKey] ?? 0) + 1;
      }

      if (isWicket && wicketType != 'run_out') {
        wickets++;
      }
    }

    final bowlingInnings = inningsBowled.length;

    for (final overKey in overBalls.keys) {
      if (overBalls[overKey] == 6 && (overRuns[overKey] ?? 0) == 0) {
        maidens++;
      }
    }

    final overs          = legalBalls ~/ 6;
    final balls          = legalBalls % 6;
    final economy        = legalBalls > 0 ? (runsConceded / legalBalls) * 6 : 0.0;
    final bowlingAverage = wickets > 0 ? runsConceded / wickets : 0.0;

    return {
      'wickets':        wickets,
      'overs':          overs,
      'oversBalls':     balls,
      'runsConceded':   runsConceded,
      'maidens':        maidens,
      'bowlingInnings': bowlingInnings,
      'economy':        economy,
      'bowlingAverage': bowlingAverage,
    };
  }

  void _sortStats(List<Map<String, dynamic>> stats) {
    stats.sort((a, b) {
      dynamic aVal, bVal;
      
      switch (_sortBy) {
        case 'runs':
          aVal = a['totalRuns'] as int;
          bVal = b['totalRuns'] as int;
          break;
        case 'average':
          aVal = a['battingAverage'] as double;
          bVal = b['battingAverage'] as double;
          break;
        case 'strike_rate':
          aVal = a['strikeRate'] as double;
          bVal = b['strikeRate'] as double;
          break;
        case 'wickets':
          aVal = a['wickets'] as int;
          bVal = b['wickets'] as int;
          break;
        case 'economy':
          aVal = a['economy'] as double;
          bVal = b['economy'] as double;
          // Lower economy is better — reverse default descending sort.
          if (!_ascending) {
            return (aVal as double).compareTo(bVal as double);
          }
          return (bVal as double).compareTo(aVal as double);
        default:
          aVal = a['totalRuns'] as int;
          bVal = b['totalRuns'] as int;
      }
      
      if (_ascending) {
        return (aVal as Comparable).compareTo(bVal);
      }
      return (bVal as Comparable).compareTo(aVal);
    });
  }

  void _onSortChanged(String sortBy) {
    setState(() {
      if (_sortBy == sortBy) {
        _ascending = !_ascending;
      } else {
        _sortBy   = sortBy;
        _ascending = false;
      }
      _sortStats(_playerStats);
      _applyFilter();
    });
  }

  // ── chart data helpers ───────────────────────────────────────────────────

  /// Top-N batters by total runs, sorted descending.
  List<Map<String, dynamic>> get _topScorers {
    final withRuns = _playerStats.where((p) => (p['totalRuns'] as int) > 0).toList()
      ..sort((a, b) =>
          (b['totalRuns'] as int).compareTo(a['totalRuns'] as int));
    return withRuns.take(6).toList();
  }

  /// Bowlers who have taken ≥1 wicket or bowled ≥1 over, sorted by wickets.
  List<Map<String, dynamic>> get _topBowlers {
    final active = _playerStats.where((p) {
      final w = p['wickets'] as int;
      final o = p['overs'] as int;
      return w > 0 || o > 0;
    }).toList()
      ..sort((a, b) => (b['wickets'] as int).compareTo(a['wickets'] as int));
    return active.take(6).toList();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).appColors;
    return Scaffold(
      backgroundColor: c.surface,
      body: RefreshIndicator(
        color: c.accentGreen,
        backgroundColor: const Color(0xFF1A1A1A),
        onRefresh: _loadPlayerStats,
        child: CustomScrollView(
          slivers: [
            _buildAppBar(c),
            // Thin progress bar while the downward sync is in-flight.
            if (_syncing)
              SliverToBoxAdapter(
                child: LinearProgressIndicator(
                  color: c.accentGreen,
                  backgroundColor: c.accentGreen.withAlpha(30),
                  minHeight: 2,
                ),
              ),
            if (_loading)
              SliverFillRemaining(
                child: Center(
                  child: CircularProgressIndicator(color: c.accentGreen),
                ),
              )
            else if (_playerStats.isEmpty)
              _buildEmptyState(c)
            else ...[
              // ── Charts ──────────────────────────────────────────────────
              if (_topScorers.isNotEmpty)
                SliverToBoxAdapter(
                  child: _buildManhattanChart(c),
                ),
              if (_topBowlers.isNotEmpty)
                SliverToBoxAdapter(
                  child: _buildBowlersChart(c),
                ),
              // ── Search bar ──────────────────────────────────────────────
              _buildSearchBar(c),
              // ── Sort chips + player cards ───────────────────────────────
              _buildSortChips(c),
              _buildStatsList(c),
            ],
          ],
        ),
      ),
    );
  }

  // ── App Bar ──────────────────────────────────────────────────────────────

  Widget _buildAppBar(AppColors c) {
    return SliverAppBar(
      expandedHeight: 100,
      floating: false,
      pinned: true,
      backgroundColor: c.accentDark,
      automaticallyImplyLeading: false,
      flexibleSpace: FlexibleSpaceBar(
        centerTitle: true,
        title: Text(
          widget.userOnly ? 'My Analytics' : 'Global Analytics',
          style: GoogleFonts.rajdhani(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: c.textPrimary,
            letterSpacing: 1,
          ),
        ),
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [c.accentDark, const Color(0xFF0D3318)],
            ),
          ),
        ),
      ),
    );
  }

  // ── Empty state ──────────────────────────────────────────────────────────

  Widget _buildEmptyState(AppColors c) {
    return SliverFillRemaining(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.analytics_outlined,
              size: 80,
              color: c.accentGreen.withAlpha(120),
            ),
            const SizedBox(height: 24),
            Text(
              _syncing ? 'Loading Analytics...' : 'No Player Data Yet',              style: GoogleFonts.rajdhani(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: c.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _syncing
                  ? 'Downloading match data from cloud.'
                  : 'Start scoring matches to see analytics!',
              style: GoogleFonts.rajdhani(
                fontSize: 16,
                color: c.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MANHATTAN CHART — top scorers (bar chart)
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildManhattanChart(AppColors c) {
    final scorers = _topScorers;
    final maxRuns = scorers
        .map((p) => p['totalRuns'] as int)
        .fold(0, (a, b) => a > b ? a : b)
        .toDouble();

    final barGroups = scorers.asMap().entries.map((entry) {
      final i    = entry.key;
      final runs = (entry.value['totalRuns'] as int).toDouble();
      return BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: runs,
            gradient: LinearGradient(
              colors: [c.accentGreen, c.accentDark],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            width: 22,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
          ),
        ],
      );
    }).toList();

    return _buildChartCard(
      c: c,
      title: 'TOP SCORERS',
      subtitle: 'Career runs',
      child: SizedBox(
        height: 200,
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: (maxRuns * 1.2).ceilToDouble(),
            barGroups: barGroups,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) => FlLine(
                color: c.glassBorder,
                strokeWidth: 1,
              ),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 36,
                  getTitlesWidget: (value, meta) => Text(
                    value.toInt().toString(),
                    style: GoogleFonts.rajdhani(
                      fontSize: 10,
                      color: c.textSecondary,
                    ),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (value, meta) {
                    final idx = value.toInt();
                    if (idx < 0 || idx >= scorers.length) {
                      return const SizedBox.shrink();
                    }
                    final name = scorers[idx]['name'] as String;
                    final short = name.length > 6
                        ? '${name.substring(0, 5)}.'
                        : name;
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        short,
                        style: GoogleFonts.rajdhani(
                          fontSize: 10,
                          color: c.textSecondary,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => const Color(0xFF1A2A1A),
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  final name = scorers[group.x]['name'] as String;
                  return BarTooltipItem(
                    '$name\n${rod.toY.toInt()} runs',
                    GoogleFonts.rajdhani(
                      color: c.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BOWLERS CHART — wickets bar chart with economy worm overlay
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildBowlersChart(AppColors c) {
    final bowlers  = _topBowlers;
    final maxWkts  = bowlers
        .map((p) => p['wickets'] as int)
        .fold(0, (a, b) => a > b ? a : b)
        .toDouble();

    final barGroups = bowlers.asMap().entries.map((entry) {
      final i    = entry.key;
      final wkts = (entry.value['wickets'] as int).toDouble();
      return BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: wkts,
            gradient: const LinearGradient(
              colors: [Color(0xFF1E88E5), Color(0xFF0D47A1)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            width: 22,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
          ),
        ],
      );
    }).toList();

    return _buildChartCard(
      c: c,
      title: 'BOWLING LEADERS',
      subtitle: 'Wickets taken',
      child: SizedBox(
        height: 200,
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: (maxWkts < 1 ? 5 : maxWkts * 1.3).ceilToDouble(),
            barGroups: barGroups,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) => FlLine(
                color: c.glassBorder,
                strokeWidth: 1,
              ),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  interval: 1,
                  getTitlesWidget: (value, meta) {
                    if (value != value.roundToDouble()) {
                      return const SizedBox.shrink();
                    }
                    return Text(
                      value.toInt().toString(),
                      style: GoogleFonts.rajdhani(
                        fontSize: 10,
                        color: c.textSecondary,
                      ),
                    );
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (value, meta) {
                    final idx = value.toInt();
                    if (idx < 0 || idx >= bowlers.length) {
                      return const SizedBox.shrink();
                    }
                    final name  = bowlers[idx]['name'] as String;
                    final short = name.length > 6
                        ? '${name.substring(0, 5)}.'
                        : name;
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        short,
                        style: GoogleFonts.rajdhani(
                          fontSize: 10,
                          color: c.textSecondary,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => const Color(0xFF1A1A2A),
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  final p = bowlers[group.x];
                  final econ = (p['economy'] as double).toStringAsFixed(2);
                  return BarTooltipItem(
                    '${p['name']}\n${rod.toY.toInt()} wkts · Econ $econ',
                    GoogleFonts.rajdhani(
                      color: c.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SHARED CHART CARD SHELL
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildChartCard({
    required AppColors c,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.glassBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.glassBorder, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.rajdhani(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: c.accentGreen,
                    letterSpacing: 2,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.rajdhani(
                    fontSize: 14,
                    color: c.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SEARCH BAR
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildSearchBar(AppColors c) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: TextField(
            controller: _searchController,
            style: GoogleFonts.rajdhani(
              fontSize: 15,
              color: c.textPrimary,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              hintText: 'Search player or team…',
              hintStyle: GoogleFonts.rajdhani(
                fontSize: 15,
                color: c.textSecondary,
              ),
              prefixIcon: Icon(Icons.search, color: c.accentGreen, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? GestureDetector(
                      onTap: () {
                        _searchController.clear();
                      },
                      child: Icon(Icons.close, color: c.textSecondary, size: 18),
                    )
                  : null,
              filled: true,
              fillColor: c.glassBg,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SORT CHIPS
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildSortChips(AppColors c) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildSortChip(c, 'Runs', 'runs'),
              const SizedBox(width: 8),
              _buildSortChip(c, 'Average', 'average'),
              const SizedBox(width: 8),
              _buildSortChip(c, 'Strike Rate', 'strike_rate'),
              const SizedBox(width: 8),
              _buildSortChip(c, 'Wickets', 'wickets'),
              const SizedBox(width: 8),
              _buildSortChip(c, 'Economy', 'economy'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSortChip(AppColors c, String label, String sortKey) {
    final isSelected = _sortBy == sortKey;
    
    return GestureDetector(
      onTap: () => _onSortChanged(sortKey),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? c.accentGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? c.accentGreen : c.glassBorder,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.rajdhani(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isSelected ? Colors.white : c.textSecondary,
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: 4),
              Icon(
                _ascending ? Icons.arrow_upward : Icons.arrow_downward,
                size: 14,
                color: Colors.white,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PLAYER STATS LIST
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildStatsList(AppColors c) {
    final list = _filteredStats;
    if (list.isEmpty && _searchQuery.isNotEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Text(
              'No players match "$_searchQuery"',
              style: GoogleFonts.rajdhani(fontSize: 15, color: c.textSecondary),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildPlayerCard(c, list[index]),
          childCount: list.length,
        ),
      ),
    );
  }

  Widget _buildPlayerCard(AppColors c, Map<String, dynamic> stats) {
    final name          = stats['name']          as String;
    final team          = stats['team']          as String;
    final totalRuns     = stats['totalRuns']     as int;
    final battingAverage= stats['battingAverage']as double;
    final strikeRate    = stats['strikeRate']    as double;
    final fours         = stats['fours']         as int;
    final sixes         = stats['sixes']         as int;
    final wickets       = stats['wickets']       as int;
    final economy       = stats['economy']       as double;
    final battingInnings= stats['battingInnings']as int;
    final bowlingInnings= stats['bowlingInnings']as int;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.glassBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.glassBorder, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Player name and team
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: c.accentGreen.withAlpha(40),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: GoogleFonts.rajdhani(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: c.accentGreen,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: GoogleFonts.rajdhani(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: c.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            team,
                            style: GoogleFonts.rajdhani(
                              fontSize: 12,
                              color: c.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Batting Stats
                if (battingInnings > 0) ...[
                  _buildSectionLabel(c, 'BATTING'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildStatItem(c, 'Runs', totalRuns.toString()),
                      _buildStatItem(c, 'Avg', battingAverage.toStringAsFixed(1)),
                      _buildStatItem(c, 'SR', strikeRate.toStringAsFixed(1)),
                      _buildStatItem(c, '4s', fours.toString()),
                      _buildStatItem(c, '6s', sixes.toString()),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                
                // Bowling Stats
                if (bowlingInnings > 0) ...[
                  _buildSectionLabel(c, 'BOWLING'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildStatItem(c, 'Wkts', wickets.toString()),
                      _buildStatItem(c, 'Econ', economy.toStringAsFixed(2)),
                      _buildStatItem(
                          c, 'Overs', '${stats['overs']}.${stats['oversBalls']}'),
                      _buildStatItem(c, 'Runs', stats['runsConceded'].toString()),
                      _buildStatItem(c, 'Mdns', stats['maidens'].toString()),
                    ],
                  ),
                ],
                
                // No stats message
                if (battingInnings == 0 && bowlingInnings == 0)
                  Text(
                    'No match data yet',
                    style: GoogleFonts.rajdhani(
                      fontSize: 14,
                      color: c.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(AppColors c, String label) {
    return Text(
      label,
      style: GoogleFonts.rajdhani(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: c.accentGreen,
        letterSpacing: 2,
      ),
    );
  }

  Widget _buildStatItem(AppColors c, String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.rajdhani(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: c.textPrimary,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.rajdhani(
              fontSize: 10,
              color: c.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
