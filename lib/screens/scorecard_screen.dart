import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/database_helper.dart';
import 'player_profile_screen.dart';
import 'team_history_screen.dart';

// ── Brand Palette ─────────────────────────────────────────────────────────────
const Color _accentGreen   = Color(0xFF4CAF50);
const Color _surfaceDark   = Color(0xFF0A0A0A);
const Color _surfaceCard   = Color(0xFF1A1A1A);
const Color _glassBg       = Color(0x1A4CAF50);
const Color _glassBorder   = Color(0x334CAF50);
const Color _textPrimary   = Colors.white;
const Color _textSecondary = Color(0xFFB0B0B0);
const Color _textMuted     = Color(0xFF666666);
const Color _wicketRed     = Color(0xFFEF5350);
const Color _boundaryBlue  = Color(0xFF1E88E5);
const Color _sixPurple     = Color(0xFFAB47BC);
const Color _inn1Color     = Color(0xFF4CAF50);
const Color _inn2Color     = Color(0xFF1E88E5);
const Color _dividerColor  = Color(0xFF2A2A2A);

// ── Data models ───────────────────────────────────────────────────────────────

class _BatterRow {
  final int playerId;
  final String name;
  final String dismissalText; // e.g. "c Smith b Jones" or "not out"
  final int runs;
  final int balls;
  final int fours;
  final int sixes;
  bool isNotOut;

  _BatterRow({
    required this.playerId,
    required this.name,
    required this.dismissalText,
    required this.runs,
    required this.balls,
    required this.fours,
    required this.sixes,
    required this.isNotOut,
  });

  double get strikeRate => balls == 0 ? 0.0 : (runs / balls) * 100;
}

class _BowlerRow {
  final int playerId;
  final String name;
  final int overs;
  final int ballsExtra; // partial over balls
  final int maidens;
  final int runs;
  final int wickets;

  _BowlerRow({
    required this.playerId,
    required this.name,
    required this.overs,
    required this.ballsExtra,
    required this.maidens,
    required this.runs,
    required this.wickets,
  });

  double get economy =>
      (overs * 6 + ballsExtra) == 0 ? 0.0 : (runs / (overs * 6 + ballsExtra)) * 6;

  String get oversString =>
      ballsExtra == 0 ? '$overs' : '$overs.$ballsExtra';
}

class _ExtrasRow {
  final int wides;
  final int noBalls;
  final int byes;
  final int legByes;
  final int penalty;

  _ExtrasRow({
    required this.wides,
    required this.noBalls,
    required this.byes,
    required this.legByes,
    required this.penalty,
  });

  int get total => wides + noBalls + byes + legByes + penalty;

  String get detail {
    final parts = <String>[];
    if (wides  > 0) parts.add('w $wides');
    if (noBalls > 0) parts.add('nb $noBalls');
    if (byes    > 0) parts.add('b $byes');
    if (legByes > 0) parts.add('lb $legByes');
    if (penalty > 0) parts.add('p $penalty');
    return parts.isEmpty ? '0' : parts.join(', ');
  }
}

class _InningsData {
  final List<_BatterRow> batters;
  final List<_BowlerRow> bowlers;
  final _ExtrasRow extras;
  final int totalRuns;
  final int totalWickets;
  final int legalBalls;

  _InningsData({
    required this.batters,
    required this.bowlers,
    required this.extras,
    required this.totalRuns,
    required this.totalWickets,
    required this.legalBalls,
  });

  String get oversString {
    final o = legalBalls ~/ 6;
    final b = legalBalls % 6;
    return b == 0 ? '$o' : '$o.$b';
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class ScorecardScreen extends StatefulWidget {
  final int matchId;
  final String teamA;
  final String teamB;

  const ScorecardScreen({
    super.key,
    required this.matchId,
    required this.teamA,
    required this.teamB,
  });

  @override
  State<ScorecardScreen> createState() => _ScorecardScreenState();
}

class _ScorecardScreenState extends State<ScorecardScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  String? _error;

  late TabController _tabController;

  // innings data: index 0 = innings 1, index 1 = innings 2
  final List<_InningsData?> _innings = [null, null];

  // Which team batted in each innings (resolved from toss data)
  final List<String> _battingTeams = ['', ''];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadScorecardData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── Data loading ─────────────────────────────────────────────────────────

  Future<void> _loadScorecardData() async {
    setState(() { _loading = true; _error = null; });

    try {
      final db = DatabaseHelper.instance;

      // Fetch match row to determine which team batted in each innings
      final matchRow = await db.fetchMatch(widget.matchId);
      if (matchRow != null) {
        final tossWinner = matchRow[DatabaseHelper.colTossWinner] as String?;
        final optTo      = matchRow[DatabaseHelper.colOptTo]      as String?;
        final teamA      = matchRow[DatabaseHelper.colTeamA]      as String;
        final teamB      = matchRow[DatabaseHelper.colTeamB]      as String;

        // Determine innings-1 batting team
        String inn1Batting;
        if (tossWinner != null && optTo == 'bat') {
          inn1Batting = tossWinner;
        } else if (tossWinner != null && optTo == 'bowl') {
          inn1Batting = (tossWinner == teamA) ? teamB : teamA;
        } else {
          inn1Batting = teamA; // fallback
        }
        final inn2Batting = (inn1Batting == teamA) ? teamB : teamA;

        _battingTeams[0] = inn1Batting;
        _battingTeams[1] = inn2Batting;
      } else {
        _battingTeams[0] = widget.teamA;
        _battingTeams[1] = widget.teamB;
      }

      // Load both innings
      for (int inn = 1; inn <= 2; inn++) {
        _innings[inn - 1] = await _buildInningsData(db, widget.matchId, inn);
      }
    } catch (e) {
      _error = e.toString();
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<_InningsData> _buildInningsData(
    DatabaseHelper db,
    int matchId,
    int innings,
  ) async {
    final events = await db.fetchBallEvents(matchId, innings: innings);

    // ── Player name cache ──────────────────────────────────────────────────
    final Map<int, String> nameCache = {};
    Future<String> playerName(int? id) async {
      if (id == null) return 'Unknown';
      if (nameCache.containsKey(id)) return nameCache[id]!;
      final row = await db.fetchPlayer(id);
      final n = (row?[DatabaseHelper.colName] as String?) ?? 'Player $id';
      nameCache[id] = n;
      return n;
    }

    // ── Per-batter accumulators ───────────────────────────────────────────
    // We maintain insertion-order via a list of player IDs seen
    final List<int> batterOrder = [];
    final Map<int, Map<String, dynamic>> batterStats = {};

    // ── Per-bowler accumulators ────────────────────────────────────────────
    final List<int> bowlerOrder = [];
    final Map<int, Map<String, dynamic>> bowlerStats = {};

    // ── Extras & total ────────────────────────────────────────────────────
    int wides = 0, noBalls = 0, byes = 0, legByes = 0, penalty = 0;
    int totalRuns = 0, totalWickets = 0, legalBalls = 0;

    // ── Dismissal tracking ────────────────────────────────────────────────
    // outPlayerId → dismissal string parts (filled in pass-2 after names resolved)
    final Map<int, Map<String, dynamic>> dismissalRaw = {};

    for (final e in events) {
      final strikerId   = e[DatabaseHelper.colStrikerId]    as int?;
      final bowlerId    = e[DatabaseHelper.colBowlerId]     as int?;
      final outPlayerId = e[DatabaseHelper.colOutPlayerId]  as int?;
      final runsScored  = (e[DatabaseHelper.colRunsScored]  as int?) ?? 0;
      final extraRuns   = (e[DatabaseHelper.colExtraRuns]   as int?) ?? 0;
      final extraType   = e[DatabaseHelper.colExtraType]    as String?;
      final isBoundary  = ((e[DatabaseHelper.colIsBoundary] as int?) ?? 0) == 1;
      final isWicket    = ((e[DatabaseHelper.colIsWicket]   as int?) ?? 0) == 1;
      final wicketType  = e[DatabaseHelper.colWicketType]   as String?;

      final isLegal = extraType != 'wide' && extraType != 'no_ball';

      // ── Total running ──────────────────────────────────────────────────
      totalRuns += runsScored + extraRuns;
      if (isLegal) legalBalls++;
      if (isWicket) totalWickets++;

      // ── Extras breakdown ──────────────────────────────────────────────
      if (extraType != null && extraRuns > 0) {
        switch (extraType) {
          case 'wide':    wides   += extraRuns; break;
          case 'no_ball': noBalls += extraRuns; break;
          case 'bye':     byes    += extraRuns; break;
          case 'leg_bye': legByes += extraRuns; break;
          case 'penalty': penalty += extraRuns; break;
        }
      }

      // ── Batting stats ─────────────────────────────────────────────────
      if (strikerId != null) {
        if (!batterStats.containsKey(strikerId)) {
          batterOrder.add(strikerId);
          batterStats[strikerId] = {
            'runs': 0, 'balls': 0, 'fours': 0, 'sixes': 0, 'isOut': false,
          };
        }
        final b = batterStats[strikerId]!;
        if (extraType != 'bye' && extraType != 'leg_bye') {
          b['runs'] = (b['runs'] as int) + runsScored;
        }
        if (extraType != 'wide') {
          b['balls'] = (b['balls'] as int) + 1;
        }
        if (isBoundary && runsScored == 4) b['fours'] = (b['fours'] as int) + 1;
        if (isBoundary && runsScored == 6) b['sixes'] = (b['sixes'] as int) + 1;
      }

      // ── Bowling stats ─────────────────────────────────────────────────
      if (bowlerId != null) {
        if (!bowlerStats.containsKey(bowlerId)) {
          bowlerOrder.add(bowlerId);
          bowlerStats[bowlerId] = {
            'legalBalls': 0, 'runs': 0, 'wickets': 0,
            // per-over tracking for maidens
            'overBalls': <int, int>{},
            'overRuns':  <int, int>{},
          };
        }
        final bw  = bowlerStats[bowlerId]!;
        final ov  = (e[DatabaseHelper.colOverNum] as int?) ?? 0;

        // Runs conceded
        if (extraType != 'bye' && extraType != 'leg_bye') {
          bw['runs'] = (bw['runs'] as int) + runsScored + extraRuns;
          (bw['overRuns'] as Map<int, int>)[ov] =
              ((bw['overRuns'] as Map<int, int>)[ov] ?? 0) + runsScored + extraRuns;
        } else {
          // byes/legbyes concede extras only
          bw['runs'] = (bw['runs'] as int) + extraRuns;
          (bw['overRuns'] as Map<int, int>)[ov] =
              ((bw['overRuns'] as Map<int, int>)[ov] ?? 0) + extraRuns;
        }

        if (isLegal) {
          bw['legalBalls'] = (bw['legalBalls'] as int) + 1;
          (bw['overBalls'] as Map<int, int>)[ov] =
              ((bw['overBalls'] as Map<int, int>)[ov] ?? 0) + 1;
        }

        if (isWicket && wicketType != 'run_out') {
          bw['wickets'] = (bw['wickets'] as int) + 1;
        }
      }

      // ── Dismissal info (raw, resolved to names later) ─────────────────
      if (isWicket && outPlayerId != null) {
        batterStats.putIfAbsent(outPlayerId, () {
          if (!batterOrder.contains(outPlayerId)) batterOrder.add(outPlayerId);
          return {'runs': 0, 'balls': 0, 'fours': 0, 'sixes': 0, 'isOut': false};
        });
        batterStats[outPlayerId]!['isOut'] = true;
        dismissalRaw[outPlayerId] = {
          'wicketType': wicketType,
          'bowlerId':   bowlerId,
          'strikerId':  strikerId, // catcher not available in schema; use bowler
        };
      }
    }

    // ── Resolve names ─────────────────────────────────────────────────────
    // Pre-fetch all unique player IDs in one pass
    final allIds = <int>{
      ...batterOrder,
      ...bowlerOrder,
      ...dismissalRaw.keys,
      ...dismissalRaw.values.map((d) => d['bowlerId'] as int?).whereType<int>(),
    };
    await Future.wait(allIds.map((id) => playerName(id)));

    // ── Build dismissal strings ────────────────────────────────────────────
    final Map<int, String> dismissalText = {};
    for (final pid in batterStats.keys) {
      final isOut = batterStats[pid]!['isOut'] as bool;
      if (!isOut) {
        dismissalText[pid] = 'not out';
        continue;
      }
      if (!dismissalRaw.containsKey(pid)) {
        dismissalText[pid] = 'out';
        continue;
      }
      final raw        = dismissalRaw[pid]!;
      final wt         = raw['wicketType'] as String?;
      final bwId       = raw['bowlerId']   as int?;
      final bwName     = bwId != null ? await playerName(bwId) : '';

      switch (wt) {
        case 'bowled':
          dismissalText[pid] = 'b $bwName';
          break;
        case 'caught':
          dismissalText[pid] = 'c & b $bwName';
          break;
        case 'lbw':
          dismissalText[pid] = 'lbw b $bwName';
          break;
        case 'stumped':
          dismissalText[pid] = 'st b $bwName';
          break;
        case 'hit_wicket':
          dismissalText[pid] = 'hit wkt b $bwName';
          break;
        case 'run_out':
          dismissalText[pid] = 'run out';
          break;
        default:
          dismissalText[pid] = bwName.isNotEmpty ? 'b $bwName' : 'out';
      }
    }

    // ── Build batter rows ─────────────────────────────────────────────────
    final List<_BatterRow> batterRows = [];
    for (final pid in batterOrder) {
      final st   = batterStats[pid]!;
      final name = await playerName(pid);
      batterRows.add(_BatterRow(
        playerId:      pid,
        name:          name,
        dismissalText: dismissalText[pid] ?? 'not out',
        runs:          st['runs']   as int,
        balls:         st['balls']  as int,
        fours:         st['fours']  as int,
        sixes:         st['sixes']  as int,
        isNotOut:      !(st['isOut'] as bool),
      ));
    }

    // ── Build bowler rows ─────────────────────────────────────────────────
    final List<_BowlerRow> bowlerRows = [];
    for (final pid in bowlerOrder) {
      final bw         = bowlerStats[pid]!;
      final name       = await playerName(pid);
      final lb         = bw['legalBalls'] as int;
      final overBalls  = bw['overBalls']  as Map<int, int>;
      final overRunsM  = bw['overRuns']   as Map<int, int>;

      // Maidens: complete overs (6 legal balls) with 0 runs conceded
      int maidens = 0;
      for (final ov in overBalls.keys) {
        if ((overBalls[ov] ?? 0) >= 6 && (overRunsM[ov] ?? 0) == 0) {
          maidens++;
        }
      }

      bowlerRows.add(_BowlerRow(
        playerId:    pid,
        name:        name,
        overs:       lb ~/ 6,
        ballsExtra:  lb % 6,
        maidens:     maidens,
        runs:        bw['runs']    as int,
        wickets:     bw['wickets'] as int,
      ));
    }

    return _InningsData(
      batters:       batterRows,
      bowlers:       bowlerRows,
      extras:        _ExtrasRow(
        wides:   wides,
        noBalls: noBalls,
        byes:    byes,
        legByes: legByes,
        penalty: penalty,
      ),
      totalRuns:     totalRuns,
      totalWickets:  totalWickets,
      legalBalls:    legalBalls,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surfaceDark,
      appBar: _buildAppBar(),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: _accentGreen),
            )
          : _error != null
              ? _buildError()
              : _buildBody(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _surfaceDark,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, color: _accentGreen),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.teamA} vs ${widget.teamB}',
            style: GoogleFonts.rajdhani(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          Text(
            'Scorecard',
            style: GoogleFonts.rajdhani(
              fontSize: 12,
              color: _textSecondary,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Container(
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: _glassBorder, width: 1),
            ),
          ),
          child: TabBar(
            controller: _tabController,
            indicatorColor: _accentGreen,
            indicatorWeight: 3,
            labelColor: _accentGreen,
            unselectedLabelColor: _textSecondary,
            labelStyle: GoogleFonts.rajdhani(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
            unselectedLabelStyle: GoogleFonts.rajdhani(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            tabs: [
              Tab(text: '1ST INNINGS'),
              Tab(text: '2ND INNINGS'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'Could not load scorecard.\n$_error',
          style: GoogleFonts.rajdhani(color: _textSecondary, fontSize: 16),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildBody() {
    return TabBarView(
      controller: _tabController,
      children: [
        _buildInningsTab(0),
        _buildInningsTab(1),
      ],
    );
  }

  Widget _buildInningsTab(int idx) {
    final data = _innings[idx];
    final teamName = _battingTeams[idx];
    final color = idx == 0 ? _inn1Color : _inn2Color;

    if (data == null || (data.batters.isEmpty && data.bowlers.isEmpty)) {
      return Center(
        child: Text(
          'No data for this innings yet.',
          style: GoogleFonts.rajdhani(color: _textSecondary, fontSize: 16),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Innings header ────────────────────────────────────────────
          _buildInningsHeader(teamName, data, color),
          const SizedBox(height: 12),

          // ── Batting table ─────────────────────────────────────────────
          _buildSectionLabel('BATTING'),
          _buildBattingTable(data.batters),

          // ── Extras & Total ────────────────────────────────────────────
          _buildExtrasAndTotal(data),
          const SizedBox(height: 20),

          // ── Bowling table ─────────────────────────────────────────────
          _buildSectionLabel('BOWLING'),
          _buildBowlingTable(data.bowlers),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ── Innings header ────────────────────────────────────────────────────────

  Widget _buildInningsHeader(String team, _InningsData data, Color color) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(80), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 36,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TeamHistoryScreen(teamName: team),
                    ),
                  ),
                  child: Text(
                    team.toUpperCase(),
                    style: GoogleFonts.rajdhani(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: color,
                      letterSpacing: 2,
                      decoration: TextDecoration.underline,
                      decorationColor: color.withAlpha(80),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${data.totalRuns}/${data.totalWickets}',
                  style: GoogleFonts.rajdhani(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: _textPrimary,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Overs',
                style: GoogleFonts.rajdhani(
                  fontSize: 11,
                  color: _textMuted,
                  letterSpacing: 1,
                ),
              ),
              Text(
                data.oversString,
                style: GoogleFonts.rajdhani(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Section label ─────────────────────────────────────────────────────────

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Text(
        label,
        style: GoogleFonts.rajdhani(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: _accentGreen,
          letterSpacing: 2.5,
        ),
      ),
    );
  }

  // ── Batting table ─────────────────────────────────────────────────────────

  Widget _buildBattingTable(List<_BatterRow> rows) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      decoration: BoxDecoration(
        color: _surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _glassBorder, width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: [
            _battingHeaderRow(),
            const Divider(height: 1, thickness: 1, color: _dividerColor),
            ...rows.asMap().entries.map((entry) {
              final isLast = entry.key == rows.length - 1;
              return Column(
                children: [
                  _battingDataRow(entry.value),
                  if (!isLast)
                    const Divider(height: 1, thickness: 1, color: _dividerColor),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _battingHeaderRow() {
    return Container(
      color: _glassBg,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          _headerCell('BATTER', flex: 5, align: TextAlign.left,
              padding: const EdgeInsets.only(left: 14)),
          _headerCell('R',    flex: 2),
          _headerCell('B',    flex: 2),
          _headerCell('4s',   flex: 2),
          _headerCell('6s',   flex: 2),
          _headerCell('SR',   flex: 3),
        ],
      ),
    );
  }

  Widget _battingDataRow(_BatterRow row) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Batter name + dismissal (tappable → PlayerProfileScreen)
          Expanded(
            flex: 5,
            child: InkWell(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PlayerProfileScreen(
                  playerId:   row.playerId,
                  playerName: row.name,
                ),
              )),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.only(left: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.name,
                      style: GoogleFonts.rajdhani(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: row.isNotOut ? _accentGreen : _textPrimary,
                        decoration: TextDecoration.underline,
                        decorationColor:
                            (row.isNotOut ? _accentGreen : _textPrimary)
                                .withAlpha(100),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      row.dismissalText,
                      style: GoogleFonts.rajdhani(
                        fontSize: 11,
                        color: _textMuted,
                        fontStyle: FontStyle.italic,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Runs (bold + highlight)
          Expanded(
            flex: 2,
            child: Center(
              child: Text(
                '${row.runs}',
                style: GoogleFonts.rajdhani(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: row.runs >= 50 ? _boundaryBlue : _textPrimary,
                ),
              ),
            ),
          ),
          // Balls
          Expanded(
            flex: 2,
            child: Center(
              child: Text(
                '${row.balls}',
                style: GoogleFonts.rajdhani(fontSize: 14, color: _textSecondary),
              ),
            ),
          ),
          // Fours
          Expanded(
            flex: 2,
            child: Center(
              child: Text(
                '${row.fours}',
                style: GoogleFonts.rajdhani(
                  fontSize: 14,
                  color: row.fours > 0 ? _boundaryBlue : _textSecondary,
                  fontWeight: row.fours > 0 ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
          ),
          // Sixes
          Expanded(
            flex: 2,
            child: Center(
              child: Text(
                '${row.sixes}',
                style: GoogleFonts.rajdhani(
                  fontSize: 14,
                  color: row.sixes > 0 ? _sixPurple : _textSecondary,
                  fontWeight: row.sixes > 0 ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
          ),
          // Strike Rate
          Expanded(
            flex: 3,
            child: Center(
              child: Text(
                row.balls == 0 ? '-' : row.strikeRate.toStringAsFixed(1),
                style: GoogleFonts.rajdhani(fontSize: 13, color: _textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Extras & Total ────────────────────────────────────────────────────────

  Widget _buildExtrasAndTotal(_InningsData data) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: _glassBorder, width: 1),
          right: BorderSide(color: _glassBorder, width: 1),
          bottom: BorderSide(color: _glassBorder, width: 1),
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
        color: _surfaceCard,
      ),
      child: Column(
        children: [
          const Divider(height: 1, thickness: 1, color: _dividerColor),
          // Extras row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Extras',
                        style: GoogleFonts.rajdhani(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _textSecondary,
                        ),
                      ),
                      Text(
                        '(${data.extras.detail})',
                        style: GoogleFonts.rajdhani(
                          fontSize: 11,
                          color: _textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 9,
                  child: Text(
                    '${data.extras.total}',
                    style: GoogleFonts.rajdhani(
                      fontSize: 14,
                      color: _textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: _dividerColor),
          // Total row
          Container(
            color: _glassBg,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Text(
                    'TOTAL',
                    style: GoogleFonts.rajdhani(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: _textPrimary,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                Expanded(
                  flex: 9,
                  child: Text(
                    '${data.totalRuns}/${data.totalWickets}  (${data.oversString} Ov)',
                    style: GoogleFonts.rajdhani(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: _textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Bowling table ─────────────────────────────────────────────────────────

  Widget _buildBowlingTable(List<_BowlerRow> rows) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      decoration: BoxDecoration(
        color: _surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _glassBorder, width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: [
            _bowlingHeaderRow(),
            const Divider(height: 1, thickness: 1, color: _dividerColor),
            ...rows.asMap().entries.map((entry) {
              final isLast = entry.key == rows.length - 1;
              return Column(
                children: [
                  _bowlingDataRow(entry.value),
                  if (!isLast)
                    const Divider(height: 1, thickness: 1, color: _dividerColor),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _bowlingHeaderRow() {
    return Container(
      color: _glassBg,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          _headerCell('BOWLER', flex: 5, align: TextAlign.left,
              padding: const EdgeInsets.only(left: 14)),
          _headerCell('O',    flex: 2),
          _headerCell('M',    flex: 2),
          _headerCell('R',    flex: 2),
          _headerCell('W',    flex: 2),
          _headerCell('ECON', flex: 3),
        ],
      ),
    );
  }

  Widget _bowlingDataRow(_BowlerRow row) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          // Bowler name (tappable → PlayerProfileScreen)
          Expanded(
            flex: 5,
            child: InkWell(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PlayerProfileScreen(
                  playerId:   row.playerId,
                  playerName: row.name,
                ),
              )),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.only(left: 14),
                child: Text(
                  row.name,
                  style: GoogleFonts.rajdhani(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: row.wickets > 0 ? _wicketRed : _textPrimary,
                    decoration: TextDecoration.underline,
                    decorationColor:
                        (row.wickets > 0 ? _wicketRed : _textPrimary)
                            .withAlpha(100),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          // Overs
          Expanded(
            flex: 2,
            child: Center(
              child: Text(
                row.oversString,
                style: GoogleFonts.rajdhani(fontSize: 14, color: _textSecondary),
              ),
            ),
          ),
          // Maidens
          Expanded(
            flex: 2,
            child: Center(
              child: Text(
                '${row.maidens}',
                style: GoogleFonts.rajdhani(
                  fontSize: 14,
                  color: row.maidens > 0 ? _accentGreen : _textSecondary,
                  fontWeight: row.maidens > 0 ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
          ),
          // Runs
          Expanded(
            flex: 2,
            child: Center(
              child: Text(
                '${row.runs}',
                style: GoogleFonts.rajdhani(fontSize: 14, color: _textSecondary),
              ),
            ),
          ),
          // Wickets
          Expanded(
            flex: 2,
            child: Center(
              child: Text(
                '${row.wickets}',
                style: GoogleFonts.rajdhani(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: row.wickets >= 3
                      ? _wicketRed
                      : row.wickets > 0
                          ? const Color(0xFFFF8A65)
                          : _textSecondary,
                ),
              ),
            ),
          ),
          // Economy
          Expanded(
            flex: 3,
            child: Center(
              child: Text(
                (row.overs == 0 && row.ballsExtra == 0)
                    ? '-'
                    : row.economy.toStringAsFixed(2),
                style: GoogleFonts.rajdhani(fontSize: 13, color: _textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared helpers ────────────────────────────────────────────────────────

  Widget _headerCell(
    String label, {
    required int flex,
    TextAlign align = TextAlign.center,
    EdgeInsetsGeometry padding = EdgeInsets.zero,
  }) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: padding,
        child: Text(
          label,
          textAlign: align,
          style: GoogleFonts.rajdhani(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: _textMuted,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }
}
