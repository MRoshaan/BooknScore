import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';

import '../services/database_helper.dart';
import '../theme.dart';
import 'tournament_champions_screen.dart';

// Per-innings colours (fixed, not theme-adaptive)
const Color _inn1Color = Color(0xFF4CAF50); // green
const Color _inn2Color = Color(0xFF1E88E5); // blue

// ── MOTM data model ───────────────────────────────────────────────────────────

class _MotmData {
  final String name;
  final String? avatarPath;
  final double impactPoints;
  final int runs;
  final int wickets;
  final int fours;
  final int sixes;

  const _MotmData({
    required this.name,
    this.avatarPath,
    required this.impactPoints,
    required this.runs,
    required this.wickets,
    required this.fours,
    required this.sixes,
  });
}

/// Match Summary screen with:
///  • Manhattan Chart – runs per over (bar chart)
///  • Worm Chart – cumulative runs per over (line chart)
///
/// Both charts support two innings displayed simultaneously.
class MatchSummaryScreen extends StatefulWidget {
  final int matchId;
  final String teamA;
  final String teamB;

  const MatchSummaryScreen({
    super.key,
    required this.matchId,
    required this.teamA,
    required this.teamB,
  });

  @override
  State<MatchSummaryScreen> createState() => _MatchSummaryScreenState();
}

class _MatchSummaryScreenState extends State<MatchSummaryScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = true;

  // per-innings data: index 0 = innings 1, index 1 = innings 2
  // each entry: { overNum(1-based) → runs }
  final List<Map<int, int>> _runsPerOver = [{}, {}];

  // MOTM
  _MotmData? _motm;

  // Champions screen trigger (set to true when this is a completed Final)
  bool   _triggerChampions   = false;
  int?   _championsTournamentId;
  String _championsWinnerName = '';

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadChartData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadChartData() async {
    setState(() => _loading = true);
    try {
      final db = DatabaseHelper.instance;

      // ── Chart data ───────────────────────────────────────────────────────
      for (int inn = 1; inn <= 2; inn++) {
        final events = await db.fetchBallEvents(widget.matchId, innings: inn);
        final Map<int, int> perOver = {};

        for (final e in events) {
          final over = (e[DatabaseHelper.colOverNum] as int?) ?? 0;
          final runs = (e[DatabaseHelper.colRunsScored] as int?) ?? 0;
          final extras = (e[DatabaseHelper.colExtraRuns] as int?) ?? 0;
          perOver[over] = (perOver[over] ?? 0) + runs + extras;
        }

        _runsPerOver[inn - 1] = perOver;
      }

      // ── MOTM computation ─────────────────────────────────────────────────
      // Fetch ALL ball events for the match (both innings)
      final allEvents = await db.fetchBallEvents(widget.matchId);

      // Per-player accumulators
      // batting: strikerId → { runs, fours, sixes, dotBalls }
      // bowling: bowlerId  → { wickets, runsConceded }
      final Map<int, Map<String, num>> batting  = {};
      final Map<int, Map<String, num>> bowling  = {};

      for (final e in allEvents) {
        final strikerId  = e[DatabaseHelper.colStrikerId]  as int?;
        final bowlerId   = e[DatabaseHelper.colBowlerId]   as int?;
        final runsScored = (e[DatabaseHelper.colRunsScored]  as int?) ?? 0;
        final extraRuns  = (e[DatabaseHelper.colExtraRuns]   as int?) ?? 0;
        final extraType  = e[DatabaseHelper.colExtraType]   as String?;
        final isBoundary = ((e[DatabaseHelper.colIsBoundary] as int?) ?? 0) == 1;
        final isWicket   = ((e[DatabaseHelper.colIsWicket]   as int?) ?? 0) == 1;
        final wicketType = e[DatabaseHelper.colWicketType]  as String?;
        final isLegal    = extraType != 'wide' && extraType != 'no_ball';

        // ── Batting stats ──
        if (strikerId != null) {
          batting.putIfAbsent(strikerId, () =>
              {'runs': 0, 'fours': 0, 'sixes': 0, 'dotBalls': 0});
          final b = batting[strikerId]!;

          // Runs to batter (not byes/leg byes)
          if (extraType != 'bye' && extraType != 'leg_bye') {
            b['runs'] = b['runs']! + runsScored;
          }

          // Boundaries
          if (isBoundary && runsScored == 4) b['fours'] = b['fours']! + 1;
          if (isBoundary && runsScored == 6) b['sixes'] = b['sixes']! + 1;

          // Dot ball: legal delivery where NO runs at all (runs+extras == 0)
          if (isLegal && runsScored == 0 && extraRuns == 0) {
            b['dotBalls'] = b['dotBalls']! + 1;
          }
        }

        // ── Bowling stats ──
        if (bowlerId != null) {
          bowling.putIfAbsent(bowlerId, () => {'wickets': 0, 'runsConceded': 0});
          final bw = bowling[bowlerId]!;

          // Wickets attributed to bowler (not run outs)
          if (isWicket && wicketType != 'run_out') {
            bw['wickets'] = bw['wickets']! + 1;
          }

          // Runs conceded
          if (extraType != 'bye' && extraType != 'leg_bye') {
            bw['runsConceded'] = bw['runsConceded']! + runsScored + extraRuns;
          } else {
            bw['runsConceded'] = bw['runsConceded']! + extraRuns;
          }
        }
      }

      // Merge player IDs
      final allPlayerIds = <int>{...batting.keys, ...bowling.keys};

      double bestImpact = -double.infinity;
      int? motmId;

      for (final pid in allPlayerIds) {
        final b  = batting[pid]  ?? {'runs': 0, 'fours': 0, 'sixes': 0, 'dotBalls': 0};
        final bw = bowling[pid]  ?? {'wickets': 0, 'runsConceded': 0};

        final double impact =
            (b['runs']!        * 1.0)  +
            (b['sixes']!       * 2.0)  +
            (b['fours']!       * 1.0)  +
            (bw['wickets']!    * 20.0) +
            (b['dotBalls']!    * 1.0)  -
            (bw['runsConceded']! * 0.5);

        if (impact > bestImpact) {
          bestImpact = impact;
          motmId = pid;
        }
      }

      if (motmId != null) {
        final playerRow = await db.fetchPlayer(motmId);
        final motmBat  = batting[motmId]  ?? {'runs': 0, 'fours': 0, 'sixes': 0, 'dotBalls': 0};
        final motmBowl = bowling[motmId]  ?? {'wickets': 0, 'runsConceded': 0};

        _motm = _MotmData(
          name:          (playerRow?[DatabaseHelper.colName] as String?) ?? 'Player $motmId',
          avatarPath:    playerRow?[DatabaseHelper.colLocalAvatarPath] as String?,
          impactPoints:  bestImpact,
          runs:          (motmBat['runs']     as num).toInt(),
          wickets:       (motmBowl['wickets'] as num).toInt(),
          fours:         (motmBat['fours']    as num).toInt(),
          sixes:         (motmBat['sixes']    as num).toInt(),
        );
      }
    } catch (_) {
      // leave empty maps on error
    }

    // ── Champions screen trigger ──────────────────────────────────────────
    // If this is a completed Final match, queue navigation to the champions
    // screen so it appears on top of the summary after the first frame.
    try {
      final matchRow = await DatabaseHelper.instance.fetchMatch(widget.matchId);
      if (matchRow != null) {
        final stage        = matchRow[DatabaseHelper.colMatchStage] as String?;
        final status       = matchRow[DatabaseHelper.colStatus]     as String?;
        final tournamentId = matchRow[DatabaseHelper.colTournamentId] as int?;
        final rawWinner    = matchRow[DatabaseHelper.colWinner]     as String?;

        if (stage == 'Final' &&
            status == 'completed' &&
            tournamentId != null &&
            rawWinner != null &&
            rawWinner.isNotEmpty) {
          // Extract winner team name from result string
          final teamA   = matchRow[DatabaseHelper.colTeamA] as String? ?? '';
          final teamB   = matchRow[DatabaseHelper.colTeamB] as String? ?? '';
          String winner = '';
          final lower   = rawWinner.toLowerCase();
          if (lower.contains(teamA.toLowerCase()) &&
              !lower.startsWith('draw') &&
              !lower.startsWith('match ended')) {
            winner = teamA;
          } else if (lower.contains(teamB.toLowerCase()) &&
              !lower.startsWith('draw') &&
              !lower.startsWith('match ended')) {
            winner = teamB;
          }

          if (winner.isNotEmpty) {
            _triggerChampions       = true;
            _championsTournamentId  = tournamentId;
            _championsWinnerName    = winner;
          }
        }
      }
    } catch (_) {
      // non-critical — skip champions trigger on error
    }

    if (mounted) {
      setState(() => _loading = false);
      // Navigate to champions screen after the summary frame is rendered
      if (_triggerChampions && _championsTournamentId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TournamentChampionsScreen(
                  tournamentId:    _championsTournamentId!,
                  winnerTeamName:  _championsWinnerName,
                ),
              ),
            );
          }
        });
      }
    }
  }

  // Build cumulative list from a per-over map.
  //
  // Returns a list where index 0 = cumulative runs AFTER over 1,
  // index 1 = cumulative runs after over 2, and so on.
  //
  // The DB stores over_num as 1-based integers.  We iterate from 1 so
  // that position 0 in the returned list always corresponds to "end of
  // Over 1", matching what the Worm Chart's x-axis label "O1" should show.
  List<int> _cumulativeRuns(Map<int, int> perOver) {
    if (perOver.isEmpty) return [];
    final maxOver = perOver.keys.reduce((a, b) => a > b ? a : b);
    final cumulative = <int>[];
    int total = 0;
    for (int o = 1; o <= maxOver; o++) {
      total += perOver[o] ?? 0;
      cumulative.add(total);
    }
    return cumulative;
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).appColors;
    return Scaffold(
      backgroundColor: c.surface,
      appBar: AppBar(
        backgroundColor: c.accentDark,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Column(
          children: [
            Text(
              '${widget.teamA} vs ${widget.teamB}',
              style: GoogleFonts.rajdhani(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            Text(
              'MATCH SUMMARY',
              style: GoogleFonts.rajdhani(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: c.accentGreen,
                letterSpacing: 3,
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: c.accentGreen,
          labelColor: c.accentGreen,
          unselectedLabelColor: c.textSecondary,
          labelStyle: GoogleFonts.rajdhani(
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
          tabs: const [
            Tab(text: 'Manhattan'),
            Tab(text: 'Worm'),
          ],
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: c.accentGreen))
          : Column(
              children: [
                // ── Man of the Match FIFA card ──────────────────────────────
                if (_motm != null) _MotmCard(motm: _motm!),

                // ── Innings charts (tabbed) ────────────────────────────────
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildManhattanTab(c),
                      _buildWormTab(c),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // ── Legend ────────────────────────────────────────────────────────────────

  Widget _buildLegend(AppColors c) {
    final hasInn1 = _runsPerOver[0].isNotEmpty;
    final hasInn2 = _runsPerOver[1].isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (hasInn1) _legendItem(c, _inn1Color, '1st Inn · ${widget.teamA}'),
          if (hasInn1 && hasInn2) const SizedBox(width: 24),
          if (hasInn2) _legendItem(c, _inn2Color, '2nd Inn · ${widget.teamB}'),
        ],
      ),
    );
  }

  Widget _legendItem(AppColors c, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color.withAlpha(180),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.rajdhani(
            color: c.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ── Manhattan Chart ───────────────────────────────────────────────────────

  Widget _buildManhattanTab(AppColors c) {
    final hasData =
        _runsPerOver[0].isNotEmpty || _runsPerOver[1].isNotEmpty;

    if (!hasData) return _buildNoData(c);

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLegend(c),
          _buildSectionTitle(c, 'RUNS PER OVER'),
          const SizedBox(height: 8),
          _buildManhattanChart(c),
        ],
      ),
    );
  }

  Widget _buildManhattanChart(AppColors c) {
    final map1 = _runsPerOver[0];
    final map2 = _runsPerOver[1];

    int maxOver = 0;
    if (map1.isNotEmpty) maxOver = map1.keys.reduce((a, b) => a > b ? a : b);
    if (map2.isNotEmpty) {
      final m2max = map2.keys.reduce((a, b) => a > b ? a : b);
      if (m2max > maxOver) maxOver = m2max;
    }

    // Find max runs in a single over for Y axis
    int maxRuns = 1;
    for (final v in [...map1.values, ...map2.values]) {
      if (v > maxRuns) maxRuns = v;
    }

    final groups = <BarChartGroupData>[];
    // over_num in the DB is 1-based; iterate from 1 so that x=1 = Over 1.
    for (int o = 1; o <= maxOver; o++) {
      final runs1 = map1[o] ?? 0;
      final runs2 = map2[o] ?? 0;

      final rods = <BarChartRodData>[];
      if (map1.isNotEmpty) {
        rods.add(BarChartRodData(
          toY: runs1.toDouble(),
          color: _inn1Color.withAlpha(200),
          width: map2.isNotEmpty ? 7 : 14,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
        ));
      }
      if (map2.isNotEmpty) {
        rods.add(BarChartRodData(
          toY: runs2.toDouble(),
          color: _inn2Color.withAlpha(200),
          width: 7,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
        ));
      }

      groups.add(BarChartGroupData(x: o, barRods: rods, barsSpace: 2));
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      decoration: BoxDecoration(
        color: c.glassBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.glassBorder),
      ),
      height: 260,
      child: BarChart(
        BarChartData(
          barGroups: groups,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: (maxRuns / 4).ceilToDouble().clamp(1, double.infinity),
            getDrawingHorizontalLine: (_) => FlLine(
              color: Colors.white12,
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: (maxRuns / 4).ceilToDouble().clamp(1, double.infinity),
                getTitlesWidget: (val, _) => Text(
                  val.toInt().toString(),
                  style: GoogleFonts.rajdhani(
                    color: c.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                getTitlesWidget: (val, _) {
                  final over = val.toInt();
                  // Show every over label only when few overs, else every 2nd
                  if (maxOver > 10 && over % 2 != 0) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      // over_num is 1-based in the DB; x already equals the
                      // over number so display it directly.
                      '$over',
                      style: GoogleFonts.rajdhani(
                        color: c.textSecondary,
                        fontSize: 10,
                      ),
                    ),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => const Color(0xFF1A1A1A),
              getTooltipItem: (group, _, rod, rodIndex) {
                // group.x is the 1-based over number (matches DB over_num).
                final over = group.x;
                final innings = rodIndex == 0 ? '1st' : '2nd';
                return BarTooltipItem(
                  'Over $over\n$innings: ${rod.toY.toInt()} runs',
                  GoogleFonts.rajdhani(color: c.textPrimary, fontSize: 12),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // ── Worm Chart ────────────────────────────────────────────────────────────

  Widget _buildWormTab(AppColors c) {
    final hasData =
        _runsPerOver[0].isNotEmpty || _runsPerOver[1].isNotEmpty;

    if (!hasData) return _buildNoData(c);

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLegend(c),
          _buildSectionTitle(c, 'CUMULATIVE RUNS'),
          const SizedBox(height: 8),
          _buildWormChart(c),
        ],
      ),
    );
  }

  Widget _buildWormChart(AppColors c) {
    final cum1 = _cumulativeRuns(_runsPerOver[0]);
    final cum2 = _cumulativeRuns(_runsPerOver[1]);

    int maxRuns = 1;
    for (final v in [...cum1, ...cum2]) {
      if (v > maxRuns) maxRuns = v;
    }

    int maxOver = 0;
    if (cum1.isNotEmpty) maxOver = cum1.length;
    if (cum2.length > maxOver) maxOver = cum2.length;

    final lines = <LineChartBarData>[];

    if (cum1.isNotEmpty) {
      lines.add(LineChartBarData(
        spots: [
          const FlSpot(0, 0),
          ...List.generate(
            cum1.length,
            (i) => FlSpot((i + 1).toDouble(), cum1[i].toDouble()),
          ),
        ],
        isCurved: true,
        color: _inn1Color,
        barWidth: 2.5,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(
          show: true,
          color: _inn1Color.withAlpha(30),
        ),
      ));
    }

    if (cum2.isNotEmpty) {
      lines.add(LineChartBarData(
        spots: [
          const FlSpot(0, 0),
          ...List.generate(
            cum2.length,
            (i) => FlSpot((i + 1).toDouble(), cum2[i].toDouble()),
          ),
        ],
        isCurved: true,
        color: _inn2Color,
        barWidth: 2.5,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(
          show: true,
          color: _inn2Color.withAlpha(30),
        ),
      ));
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      decoration: BoxDecoration(
        color: c.glassBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.glassBorder),
      ),
      height: 280,
      child: LineChart(
        LineChartData(
          lineBarsData: lines,
          minX: 0,
          maxX: maxOver.toDouble(),
          minY: 0,
          maxY: (maxRuns * 1.1).ceilToDouble(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: (maxRuns / 4).ceilToDouble().clamp(1, double.infinity),
            getDrawingHorizontalLine: (_) => FlLine(
              color: Colors.white12,
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                interval: (maxRuns / 4).ceilToDouble().clamp(1, double.infinity),
                getTitlesWidget: (val, _) => Text(
                  val.toInt().toString(),
                  style: GoogleFonts.rajdhani(
                    color: c.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: maxOver > 10 ? 2 : 1,
                getTitlesWidget: (val, _) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'O${val.toInt()}',
                    style: GoogleFonts.rajdhani(
                      color: c.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
            ),
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => const Color(0xFF1A1A1A),
              getTooltipItems: (spots) => spots.map((spot) {
                final over = spot.x.toInt();
                final innings = spot.barIndex == 0 ? '1st' : '2nd';
                return LineTooltipItem(
                  'Over $over · $innings\n${spot.y.toInt()} runs',
                  GoogleFonts.rajdhani(color: c.textPrimary, fontSize: 12),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  // ── Shared helpers ────────────────────────────────────────────────────────

  Widget _buildSectionTitle(AppColors c, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: c.accentGreen,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: GoogleFonts.rajdhani(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: c.textSecondary,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoData(AppColors c) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bar_chart, size: 64, color: c.accentGreen.withAlpha(100)),
          const SizedBox(height: 16),
          Text(
            'No ball data yet',
            style: GoogleFonts.rajdhani(
              fontSize: 20,
              color: c.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// MAN OF THE MATCH — FIFA ULTIMATE TEAM STYLE CARD
// ══════════════════════════════════════════════════════════════════════════════

class _MotmCard extends StatelessWidget {
  const _MotmCard({required this.motm});

  final _MotmData motm;

  @override
  Widget build(BuildContext context) {
    const Color goldLight  = Color(0xFFFFD700);
    const Color goldMid    = Color(0xFFFF8F00);
    const Color goldDark   = Color(0xFFE65100);
    const Color cardBg     = Color(0xFF1A1200);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: cardBg,
        border: Border(
          bottom: BorderSide(color: Color(0x33FFD700), width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section label
          Row(
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: goldLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'MAN OF THE MATCH',
                style: GoogleFonts.rajdhani(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: goldLight,
                  letterSpacing: 3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // The card itself
          Center(
            child: Container(
              width: 200,
              height: 260,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [goldLight, goldMid, goldDark, goldMid, goldLight],
                  stops: [0.0, 0.25, 0.5, 0.75, 1.0],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: goldLight.withAlpha(120),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // Subtle metallic sheen overlay
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withAlpha(40),
                          Colors.transparent,
                          Colors.white.withAlpha(20),
                        ],
                      ),
                    ),
                  ),

                  // Content
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Column(
                      children: [
                        // Impact points (top left) + label (top right)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Big impact score
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  motm.impactPoints.toStringAsFixed(0),
                                  style: GoogleFonts.rajdhani(
                                    fontSize: 36,
                                    fontWeight: FontWeight.w900,
                                    color: const Color(0xFF1A1200),
                                    height: 1,
                                  ),
                                ),
                                Text(
                                  'IP',
                                  style: GoogleFonts.rajdhani(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF3E2800),
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            // MOTM badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0x551A1200),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: const Color(0x881A1200),
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                'MOTM',
                                style: GoogleFonts.rajdhani(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  color: const Color(0xFF1A1200),
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),

                        // Avatar
                        Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0x881A1200),
                              width: 2,
                            ),
                            color: const Color(0x441A1200),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: _buildAvatar(),
                        ),
                        const SizedBox(height: 8),

                        // Player name
                        Text(
                          motm.name.toUpperCase(),
                          style: GoogleFonts.rajdhani(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF1A1200),
                            letterSpacing: 1.5,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 10),

                        // Divider
                        Container(
                          height: 1,
                          color: const Color(0x441A1200),
                        ),
                        const SizedBox(height: 8),

                        // Stats row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _statChip('${motm.runs}', 'RUNS'),
                            _statChip('${motm.wickets}', 'WKT'),
                            _statChip('${motm.fours}', '4s'),
                            _statChip('${motm.sixes}', '6s'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    final path = motm.avatarPath;
    if (path != null && path.isNotEmpty) {
      if (path.startsWith('http://') || path.startsWith('https://')) {
        return CachedNetworkImage(
          imageUrl: path,
          fit: BoxFit.cover,
          errorWidget: (ctx, url, e) => _placeholderIcon(),
        );
      }
      final file = File(path);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
          errorBuilder: (ctx, e, st) => _placeholderIcon(),
        );
      }
    }
    return _placeholderIcon();
  }

  Widget _placeholderIcon() {
    return const Icon(
      Icons.person,
      size: 56,
      color: Color(0x881A1200),
    );
  }

  Widget _statChip(String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: GoogleFonts.rajdhani(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: const Color(0xFF1A1200),
          ),
        ),
        Text(
          label,
          style: GoogleFonts.rajdhani(
            fontSize: 8,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF3E2800),
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}
