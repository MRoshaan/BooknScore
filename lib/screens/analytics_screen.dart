import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';

import '../services/database_helper.dart';

// ── Brand Palette ────────────────────────────────────────────────────────────
const Color _primaryGreen   = Color(0xFF1B5E20);
const Color _accentGreen    = Color(0xFF4CAF50);
const Color _surfaceDark    = Color(0xFF0A0A0A);
const Color _glassBg        = Color(0x1A4CAF50);
const Color _glassBorder    = Color(0x334CAF50);
const Color _textPrimary    = Colors.white;
const Color _textSecondary  = Color(0xFFB0B0B0);

/// Player Analytics Screen
/// Displays:
///  • Top Scorers Manhattan chart (BarChart)
///  • Bowlers Economy chart (BarChart)
///  • Career stats cards for all players
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final _db = DatabaseHelper.instance;
  List<Map<String, dynamic>> _playerStats = [];
  List<Map<String, dynamic>> _filteredStats = [];
  bool _loading = true;
  String _sortBy = 'runs'; // 'runs', 'average', 'strike_rate', 'wickets', 'economy'
  bool _ascending = false;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadPlayerStats();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final q = _searchController.text.trim().toLowerCase();
    setState(() {
      _searchQuery = q;
      _applyFilter();
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
      
      // Get all unique players
      final players = await db.query(DatabaseHelper.tablePlayers);
      
      final stats = <Map<String, dynamic>>[];
      
      for (final player in players) {
        final playerId    = player[DatabaseHelper.colId]   as int;
        final playerName  = player[DatabaseHelper.colName] as String;
        final team        = player[DatabaseHelper.colTeam] as String;
        
        // Calculate batting stats across all matches
        final battingStats = await _calculateCareerBattingStats(playerId);
        
        // Calculate bowling stats across all matches
        final bowlingStats = await _calculateCareerBowlingStats(playerId);
        
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

  Future<Map<String, dynamic>> _calculateCareerBattingStats(int playerId) async {
    final db = await _db.database;
    
    final events = await db.query(
      DatabaseHelper.tableBallEvents,
      where: '${DatabaseHelper.colStrikerId} = ?',
      whereArgs: [playerId],
    );
    
    int totalRuns  = 0;
    int ballsFaced = 0;
    int fours      = 0;
    int sixes      = 0;
    
    final inningsPlayed = <String>{};
    
    for (final e in events) {
      final matchId   = e[DatabaseHelper.colMatchId]   as int;
      final inningsNum= e[DatabaseHelper.colInnings]   as int;
      final extraType = e[DatabaseHelper.colExtraType] as String?;
      final runsScored= e[DatabaseHelper.colRunsScored]as int;
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
    
    final innings = inningsPlayed.length;
    
    final outs = await db.query(
      DatabaseHelper.tableBallEvents,
      where:
          '${DatabaseHelper.colOutPlayerId} = ? AND ${DatabaseHelper.colIsWicket} = 1',
      whereArgs: [playerId],
    );
    
    final dismissals  = outs.length;
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

  Future<Map<String, dynamic>> _calculateCareerBowlingStats(int playerId) async {
    final db = await _db.database;
    
    final events = await db.query(
      DatabaseHelper.tableBallEvents,
      where: '${DatabaseHelper.colBowlerId} = ?',
      whereArgs: [playerId],
    );
    
    int legalBalls    = 0;
    int runsConceded  = 0;
    int wickets       = 0;
    int maidens       = 0;
    int bowlingInnings= 0;
    
    final overRuns    = <String, int>{};
    final overBalls   = <String, int>{};
    final inningsBowled = <String>{};
    
    for (final e in events) {
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
    
    bowlingInnings = inningsBowled.length;
    
    for (final overKey in overBalls.keys) {
      if (overBalls[overKey] == 6 && (overRuns[overKey] ?? 0) == 0) {
        maidens++;
      }
    }
    
    final overs    = legalBalls ~/ 6;
    final balls    = legalBalls % 6;
    final economy  = legalBalls > 0 ? (runsConceded / legalBalls) * 6 : 0.0;
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
    return Scaffold(
      backgroundColor: _surfaceDark,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(),
          if (_loading)
            const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(color: _accentGreen),
              ),
            )
          else if (_playerStats.isEmpty)
            _buildEmptyState()
          else ...[
            // ── Charts ──────────────────────────────────────────────────
            if (_topScorers.isNotEmpty)
              SliverToBoxAdapter(
                child: _buildManhattanChart(),
              ),
            if (_topBowlers.isNotEmpty)
              SliverToBoxAdapter(
                child: _buildBowlersChart(),
              ),
            // ── Search bar ──────────────────────────────────────────────
            _buildSearchBar(),
            // ── Sort chips + player cards ───────────────────────────────
            _buildSortChips(),
            _buildStatsList(),
          ],
        ],
      ),
    );
  }

  // ── App Bar ──────────────────────────────────────────────────────────────

  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 100,
      floating: false,
      pinned: true,
      backgroundColor: _primaryGreen,
      automaticallyImplyLeading: false,
      flexibleSpace: FlexibleSpaceBar(
        centerTitle: true,
        title: Text(
          'Player Analytics',
          style: GoogleFonts.rajdhani(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: _textPrimary,
            letterSpacing: 1,
          ),
        ),
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_primaryGreen, Color(0xFF0D3318)],
            ),
          ),
        ),
      ),
    );
  }

  // ── Empty state ──────────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return SliverFillRemaining(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.analytics_outlined,
              size: 80,
              color: _accentGreen.withAlpha(120),
            ),
            const SizedBox(height: 24),
            Text(
              'No Player Data Yet',
              style: GoogleFonts.rajdhani(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: _textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Start scoring matches to see analytics!',
              style: GoogleFonts.rajdhani(
                fontSize: 16,
                color: _textSecondary,
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

  Widget _buildManhattanChart() {
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
            gradient: const LinearGradient(
              colors: [_accentGreen, _primaryGreen],
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
                color: _glassBorder,
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
                      color: _textSecondary,
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
                          color: _textSecondary,
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
                      color: _textPrimary,
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

  Widget _buildBowlersChart() {
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
                color: _glassBorder,
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
                        color: _textSecondary,
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
                          color: _textSecondary,
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
                      color: _textPrimary,
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
              color: _glassBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _glassBorder, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.rajdhani(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _accentGreen,
                    letterSpacing: 2,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.rajdhani(
                    fontSize: 14,
                    color: _textSecondary,
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

  Widget _buildSearchBar() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: TextField(
            controller: _searchController,
            style: GoogleFonts.rajdhani(
              fontSize: 15,
              color: _textPrimary,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              hintText: 'Search player or team…',
              hintStyle: GoogleFonts.rajdhani(
                fontSize: 15,
                color: _textSecondary,
              ),
              prefixIcon: const Icon(Icons.search, color: _accentGreen, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? GestureDetector(
                      onTap: () {
                        _searchController.clear();
                      },
                      child: const Icon(Icons.close, color: _textSecondary, size: 18),
                    )
                  : null,
              filled: true,
              fillColor: _glassBg,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _glassBorder, width: 1),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _glassBorder, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _accentGreen, width: 1.5),
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

  Widget _buildSortChips() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildSortChip('Runs', 'runs'),
              const SizedBox(width: 8),
              _buildSortChip('Average', 'average'),
              const SizedBox(width: 8),
              _buildSortChip('Strike Rate', 'strike_rate'),
              const SizedBox(width: 8),
              _buildSortChip('Wickets', 'wickets'),
              const SizedBox(width: 8),
              _buildSortChip('Economy', 'economy'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSortChip(String label, String sortKey) {
    final isSelected = _sortBy == sortKey;
    
    return GestureDetector(
      onTap: () => _onSortChanged(sortKey),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? _accentGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? _accentGreen : _glassBorder,
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
                color: isSelected ? Colors.white : _textSecondary,
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

  Widget _buildStatsList() {
    final list = _filteredStats;
    if (list.isEmpty && _searchQuery.isNotEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Text(
              'No players match "$_searchQuery"',
              style: GoogleFonts.rajdhani(fontSize: 15, color: _textSecondary),
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
          (context, index) => _buildPlayerCard(list[index]),
          childCount: list.length,
        ),
      ),
    );
  }

  Widget _buildPlayerCard(Map<String, dynamic> stats) {
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
              color: _glassBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _glassBorder, width: 1),
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
                        color: _accentGreen.withAlpha(40),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: GoogleFonts.rajdhani(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: _accentGreen,
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
                              color: _textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            team,
                            style: GoogleFonts.rajdhani(
                              fontSize: 12,
                              color: _textSecondary,
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
                  _buildSectionLabel('BATTING'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildStatItem('Runs', totalRuns.toString()),
                      _buildStatItem('Avg', battingAverage.toStringAsFixed(1)),
                      _buildStatItem('SR', strikeRate.toStringAsFixed(1)),
                      _buildStatItem('4s', fours.toString()),
                      _buildStatItem('6s', sixes.toString()),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                
                // Bowling Stats
                if (bowlingInnings > 0) ...[
                  _buildSectionLabel('BOWLING'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildStatItem('Wkts', wickets.toString()),
                      _buildStatItem('Econ', economy.toStringAsFixed(2)),
                      _buildStatItem(
                          'Overs', '${stats['overs']}.${stats['oversBalls']}'),
                      _buildStatItem('Runs', stats['runsConceded'].toString()),
                      _buildStatItem('Mdns', stats['maidens'].toString()),
                    ],
                  ),
                ],
                
                // No stats message
                if (battingInnings == 0 && bowlingInnings == 0)
                  Text(
                    'No match data yet',
                    style: GoogleFonts.rajdhani(
                      fontSize: 14,
                      color: _textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: GoogleFonts.rajdhani(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: _accentGreen,
        letterSpacing: 2,
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.rajdhani(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: _textPrimary,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.rajdhani(
              fontSize: 10,
              color: _textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
