import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../theme.dart';
import 'player_profile_screen.dart';
import 'team_detail_screen.dart';

// ── Fixed-role colours (not theme-dependent) ──────────────────────────────────
const Color _wicketRed    = Color(0xFFEF5350);
const Color _boundaryBlue = Color(0xFF1E88E5);
const Color _sixPurple    = Color(0xFFAB47BC);
const Color _inn1Color    = Color(0xFF4CAF50);
const Color _inn2Color    = Color(0xFF1E88E5);
const Color _dividerColor = Color(0xFF2A2A2A);
// ─────────────────────────────────────────────────────────────────────────────

// ── Data models (private to this file) ───────────────────────────────────────

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

class _BatterRow {
  final int playerId;
  final String name;
  final String dismissalText;
  final int runs;
  final int balls;
  final int fours;
  final int sixes;
  final bool isNotOut;

  const _BatterRow({
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
  final int ballsExtra;
  final int maidens;
  final int runs;
  final int wickets;

  const _BowlerRow({
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

  const _ExtrasRow({
    required this.wides,
    required this.noBalls,
    required this.byes,
    required this.legByes,
    required this.penalty,
  });

  int get total => wides + noBalls + byes + legByes + penalty;

  String get detail {
    final parts = <String>[];
    if (wides   > 0) parts.add('w $wides');
    if (noBalls > 0) parts.add('nb $noBalls');
    if (byes    > 0) parts.add('b $byes');
    if (legByes > 0) parts.add('lb $legByes');
    if (penalty > 0) parts.add('p $penalty');
    return parts.isEmpty ? '0' : parts.join(', ');
  }
}

class _FowEntry {
  final int score;
  final int wicketNum;
  final String batter;
  final int overNum;
  final int ballNum;

  const _FowEntry({
    required this.score,
    required this.wicketNum,
    required this.batter,
    required this.overNum,
    required this.ballNum,
  });
}

class _CommentaryEntry {
  final int innings;
  final int overNum;
  final int ballNum;
  final String bowlerName;
  final String strikerName;
  final int runsScored;
  final int extraRuns;
  final String? extraType;
  final bool isBoundary;
  final bool isWicket;
  final String? wicketType;
  final String? outPlayerName;

  const _CommentaryEntry({
    required this.innings,
    required this.overNum,
    required this.ballNum,
    required this.bowlerName,
    required this.strikerName,
    required this.runsScored,
    required this.extraRuns,
    this.extraType,
    required this.isBoundary,
    required this.isWicket,
    this.wicketType,
    this.outPlayerName,
  });

  String get outcomeText {
    if (isWicket) {
      final who = outPlayerName ?? strikerName;
      final how = wicketType != null
          ? wicketType!.replaceAll('_', ' ').toUpperCase()
          : 'OUT';
      return '$who $how!';
    }
    if (extraType == 'wide')    return extraRuns > 1 ? '$extraRuns wide' : 'Wide';
    if (extraType == 'no_ball') return runsScored > 0 ? '$runsScored+NB' : 'No Ball';
    if (extraType == 'bye' || extraType == 'leg_bye') {
      final label = extraType == 'bye' ? 'Bye' : 'Leg Bye';
      return extraRuns > 1 ? '$extraRuns $label' : label;
    }
    if (isBoundary && runsScored == 6) return 'SIX!';
    if (isBoundary && runsScored == 4) return 'FOUR!';
    if (runsScored == 0) return 'Dot';
    return '$runsScored run${runsScored > 1 ? 's' : ''}';
  }
}

class _InningsData {
  final List<_BatterRow> batters;
  final List<_BowlerRow> bowlers;
  final _ExtrasRow extras;
  final int totalRuns;
  final int totalWickets;
  final int legalBalls;
  final List<_FowEntry> fow;

  const _InningsData({
    required this.batters,
    required this.bowlers,
    required this.extras,
    required this.totalRuns,
    required this.totalWickets,
    required this.legalBalls,
    required this.fow,
  });

  String get oversString {
    final o = legalBalls ~/ 6;
    final b = legalBalls % 6;
    return b == 0 ? '$o' : '$o.$b';
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

/// Read-only global match viewer with Summary and Scorecard tabs.
///
/// Does NOT depend on [MatchProvider] — all data is loaded directly from
/// the local SQLite database, making it safe to open any match regardless
/// of whether a live scoring session is active.
class GlobalMatchViewerScreen extends StatefulWidget {
  final int matchId;
  final String teamA;
  final String teamB;

  const GlobalMatchViewerScreen({
    super.key,
    required this.matchId,
    required this.teamA,
    required this.teamB,
  });

  @override
  State<GlobalMatchViewerScreen> createState() =>
      _GlobalMatchViewerScreenState();
}

class _GlobalMatchViewerScreenState extends State<GlobalMatchViewerScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  String? _error;

  late TabController _tabController;

  // ── Summary tab data ──────────────────────────────────────────────────────
  String _resultText = '';
  String _matchStatus = '';
  _MotmData? _motm;

  // Top 2 batters/bowlers per innings (index 0 = inn1, index 1 = inn2)
  final List<List<_BatterRow>> _topBatters = [[], []];
  final List<List<_BowlerRow>> _topBowlers = [[], []];

  // ── Scorecard tab data ────────────────────────────────────────────────────
  final List<_InningsData?> _innings = [null, null];
  final List<String> _battingTeams   = ['', ''];
  List<_CommentaryEntry> _commentary = [];

  // ── Shared state ──────────────────────────────────────────────────────────
  // Player name cache shared between summary and scorecard loading
  final Map<int, String> _nameCache = {};

  @override
  void initState() {
    super.initState();
    // 3 tabs: Summary | 1st Innings | 2nd Innings
    // (Commentary is included as a 4th tab via Scorecard sub-tabs)
    _tabController = TabController(length: 2, vsync: this);
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── Data Loading ──────────────────────────────────────────────────────────

  Future<void> _loadAllData() async {
    setState(() { _loading = true; _error = null; });

    try {
      final db = DatabaseHelper.instance;

      // ── Fetch match row ──────────────────────────────────────────────────
      final matchRow = await db.fetchMatch(widget.matchId);
      if (matchRow == null) {
        _error = 'Match not found.';
        if (mounted) setState(() => _loading = false);
        return;
      }

      _matchStatus = (matchRow[DatabaseHelper.colStatus] as String?) ?? '';
      _resultText  = (matchRow[DatabaseHelper.colWinner] as String?) ?? '';

      // ── Sync ball events for remote (global) matches ──────────────────
      final matchUuid = matchRow[DatabaseHelper.colUuid] as String?;
      if (matchUuid != null && matchUuid.isNotEmpty) {
        await SyncService.instance.syncDownBallEvents(matchUuid);
      }

      // ── Determine batting teams from toss ─────────────────────────────
      final tossWinner = matchRow[DatabaseHelper.colTossWinner] as String?;
      final optTo      = matchRow[DatabaseHelper.colOptTo]      as String?;
      final teamA      = matchRow[DatabaseHelper.colTeamA]      as String;
      final teamB      = matchRow[DatabaseHelper.colTeamB]      as String;

      String inn1Batting;
      if (tossWinner != null && optTo == 'bat') {
        inn1Batting = tossWinner;
      } else if (tossWinner != null && optTo == 'bowl') {
        inn1Batting = (tossWinner == teamA) ? teamB : teamA;
      } else {
        inn1Batting = teamA;
      }
      _battingTeams[0] = inn1Batting;
      _battingTeams[1] = (inn1Batting == teamA) ? teamB : teamA;

      // ── Load innings data (used by both Summary & Scorecard tabs) ─────
      for (int inn = 1; inn <= 2; inn++) {
        _innings[inn - 1] = await _buildInningsData(db, inn);
      }

      // ── Compute Top 2 batters per innings ─────────────────────────────
      for (int i = 0; i < 2; i++) {
        final data = _innings[i];
        if (data != null && data.batters.isNotEmpty) {
          final sorted = [...data.batters]
            ..sort((a, b) => b.runs.compareTo(a.runs));
          _topBatters[i] = sorted.take(2).toList();
        }
      }

      // ── Compute Top 2 bowlers per innings ─────────────────────────────
      for (int i = 0; i < 2; i++) {
        final data = _innings[i];
        if (data != null && data.bowlers.isNotEmpty) {
          final sorted = [...data.bowlers]
            ..sort((a, b) {
              // Primary: wickets desc; secondary: economy asc
              if (b.wickets != a.wickets) return b.wickets.compareTo(a.wickets);
              return a.economy.compareTo(b.economy);
            });
          _topBowlers[i] = sorted.take(2).toList();
        }
      }

      // ── Compute MOTM ─────────────────────────────────────────────────
      final allEvents = await db.fetchBallEvents(widget.matchId);
      final Map<int, Map<String, num>> batting  = {};
      final Map<int, Map<String, num>> bowling  = {};

      for (final e in allEvents) {
        final strikerId  = e[DatabaseHelper.colStrikerId]  as int?;
        final bowlerId   = e[DatabaseHelper.colBowlerId]   as int?;
        final runsScored = (e[DatabaseHelper.colRunsScored] as int?) ?? 0;
        final extraRuns  = (e[DatabaseHelper.colExtraRuns]  as int?) ?? 0;
        final extraType  = e[DatabaseHelper.colExtraType]  as String?;
        final isBoundary = ((e[DatabaseHelper.colIsBoundary] as int?) ?? 0) == 1;
        final isWicket   = ((e[DatabaseHelper.colIsWicket]   as int?) ?? 0) == 1;
        final wicketType = e[DatabaseHelper.colWicketType] as String?;

        if (strikerId != null) {
          batting.putIfAbsent(strikerId, () =>
              {'runs': 0, 'fours': 0, 'sixes': 0, 'dotBalls': 0});
          final b = batting[strikerId]!;
          if (extraType != 'bye' && extraType != 'leg_bye') {
            b['runs'] = b['runs']! + runsScored;
          }
          if (isBoundary && runsScored == 4) b['fours'] = b['fours']! + 1;
          if (isBoundary && runsScored == 6) b['sixes'] = b['sixes']! + 1;
          final isLegal = extraType != 'wide' && extraType != 'no_ball';
          if (isLegal && runsScored == 0 && extraRuns == 0) {
            b['dotBalls'] = b['dotBalls']! + 1;
          }
        }

        if (bowlerId != null) {
          bowling.putIfAbsent(bowlerId, () => {'wickets': 0, 'runsConceded': 0});
          final bw = bowling[bowlerId]!;
          if (isWicket && wicketType != 'run_out') {
            bw['wickets'] = bw['wickets']! + 1;
          }
          if (extraType != 'bye' && extraType != 'leg_bye') {
            bw['runsConceded'] = bw['runsConceded']! + runsScored + extraRuns;
          } else {
            bw['runsConceded'] = bw['runsConceded']! + extraRuns;
          }
        }
      }

      final allPlayerIds = <int>{...batting.keys, ...bowling.keys};
      double bestImpact = -double.infinity;
      int? motmId;

      for (final pid in allPlayerIds) {
        final b  = batting[pid]  ?? {'runs': 0, 'fours': 0, 'sixes': 0, 'dotBalls': 0};
        final bw = bowling[pid]  ?? {'wickets': 0, 'runsConceded': 0};
        final double impact =
            (b['runs']!          * 1.0)  +
            (b['sixes']!         * 2.0)  +
            (b['fours']!         * 1.0)  +
            (bw['wickets']!      * 20.0) +
            (b['dotBalls']!      * 1.0)  -
            (bw['runsConceded']! * 0.5);
        if (impact > bestImpact) {
          bestImpact = impact;
          motmId = pid;
        }
      }

      if (motmId != null) {
        final playerRow = await db.fetchPlayer(motmId);
        final motmBat   = batting[motmId]  ?? {'runs': 0, 'fours': 0, 'sixes': 0, 'dotBalls': 0};
        final motmBowl  = bowling[motmId]  ?? {'wickets': 0, 'runsConceded': 0};
        _motm = _MotmData(
          name:         (playerRow?[DatabaseHelper.colName] as String?) ?? 'Player $motmId',
          avatarPath:   playerRow?[DatabaseHelper.colLocalAvatarPath] as String?,
          impactPoints: bestImpact,
          runs:         (motmBat['runs']     as num).toInt(),
          wickets:      (motmBowl['wickets'] as num).toInt(),
          fours:        (motmBat['fours']    as num).toInt(),
          sixes:        (motmBat['sixes']    as num).toInt(),
        );
      }

      // ── Commentary ────────────────────────────────────────────────────
      _commentary = await _buildCommentary(db);

    } catch (e) {
      _error = e.toString();
    }

    if (mounted) setState(() => _loading = false);
  }

  // ── Innings data builder (mirrors ScorecardScreen logic) ─────────────────

  Future<String> _playerName(DatabaseHelper db, int? id) async {
    if (id == null) return 'Unknown';
    if (_nameCache.containsKey(id)) return _nameCache[id]!;
    final row = await db.fetchPlayer(id);
    final n = (row?[DatabaseHelper.colName] as String?) ?? 'Player $id';
    _nameCache[id] = n;
    return n;
  }

  Future<_InningsData> _buildInningsData(DatabaseHelper db, int innings) async {
    final events = await db.fetchBallEvents(widget.matchId, innings: innings);

    final List<int>                        batterOrder  = [];
    final Map<int, Map<String, dynamic>>   batterStats  = {};
    final List<int>                        bowlerOrder  = [];
    final Map<int, Map<String, dynamic>>   bowlerStats  = {};
    final Map<int, Map<String, dynamic>>   dismissalRaw = {};

    int wides = 0, noBalls = 0, byes = 0, legByes = 0, penalty = 0;
    int totalRuns = 0, totalWickets = 0, legalBalls = 0;
    int fowRunning = 0;
    final List<Map<String, dynamic>> fowRaw = [];

    for (final e in events) {
      final strikerId   = e[DatabaseHelper.colStrikerId]   as int?;
      final bowlerId    = e[DatabaseHelper.colBowlerId]    as int?;
      final outPlayerId = e[DatabaseHelper.colOutPlayerId] as int?;
      final runsScored  = (e[DatabaseHelper.colRunsScored] as int?) ?? 0;
      final extraRuns   = (e[DatabaseHelper.colExtraRuns]  as int?) ?? 0;
      final extraType   = e[DatabaseHelper.colExtraType]   as String?;
      final isBoundary  = ((e[DatabaseHelper.colIsBoundary] as int?) ?? 0) == 1;
      final isWicket    = ((e[DatabaseHelper.colIsWicket]   as int?) ?? 0) == 1;
      final wicketType  = e[DatabaseHelper.colWicketType]  as String?;
      final isLegal     = extraType != 'wide' && extraType != 'no_ball';

      totalRuns   += runsScored + extraRuns;
      fowRunning  += runsScored + extraRuns;
      if (isLegal) legalBalls++;
      if (isWicket) totalWickets++;

      if (isWicket && outPlayerId != null) {
        fowRaw.add({
          'score':     fowRunning,
          'wicketNum': totalWickets,
          'outPlayer': outPlayerId,
          'overNum':   (e[DatabaseHelper.colOverNum] as int?) ?? 1,
          'ballNum':   (e[DatabaseHelper.colBallNum] as int?) ?? 0,
        });
      }

      if (extraType != null && extraRuns > 0) {
        switch (extraType) {
          case 'wide':    wides   += extraRuns; break;
          case 'no_ball': noBalls += extraRuns; break;
          case 'bye':     byes    += extraRuns; break;
          case 'leg_bye': legByes += extraRuns; break;
          case 'penalty': penalty += extraRuns; break;
        }
      }

      // Batting stats
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
        if (extraType != 'wide') b['balls'] = (b['balls'] as int) + 1;
        if (isBoundary && runsScored == 4) b['fours'] = (b['fours'] as int) + 1;
        if (isBoundary && runsScored == 6) b['sixes'] = (b['sixes'] as int) + 1;
      }

      // Bowling stats
      if (bowlerId != null) {
        if (!bowlerStats.containsKey(bowlerId)) {
          bowlerOrder.add(bowlerId);
          bowlerStats[bowlerId] = {
            'legalBalls': 0, 'runs': 0, 'wickets': 0,
            'overBalls': <int, int>{},
            'overRuns':  <int, int>{},
          };
        }
        final bw = bowlerStats[bowlerId]!;
        final ov = (e[DatabaseHelper.colOverNum] as int?) ?? 0;
        if (extraType != 'bye' && extraType != 'leg_bye') {
          bw['runs'] = (bw['runs'] as int) + runsScored + extraRuns;
          (bw['overRuns'] as Map<int, int>)[ov] =
              ((bw['overRuns'] as Map<int, int>)[ov] ?? 0) + runsScored + extraRuns;
        } else {
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

      // Dismissal info
      if (isWicket && outPlayerId != null) {
        batterStats.putIfAbsent(outPlayerId, () {
          if (!batterOrder.contains(outPlayerId)) batterOrder.add(outPlayerId);
          return {'runs': 0, 'balls': 0, 'fours': 0, 'sixes': 0, 'isOut': false};
        });
        batterStats[outPlayerId]!['isOut'] = true;
        dismissalRaw[outPlayerId] = {
          'wicketType': wicketType,
          'bowlerId':   bowlerId,
        };
      }
    }

    // Pre-fetch all unique player IDs
    final allIds = <int>{
      ...batterOrder,
      ...bowlerOrder,
      ...dismissalRaw.keys,
      ...dismissalRaw.values
          .map((d) => d['bowlerId'] as int?)
          .whereType<int>(),
    };
    await Future.wait(allIds.map((id) => _playerName(db, id)));

    // Build dismissal strings
    final Map<int, String> dismissalText = {};
    for (final pid in batterStats.keys) {
      final isOut = batterStats[pid]!['isOut'] as bool;
      if (!isOut) { dismissalText[pid] = 'not out'; continue; }
      if (!dismissalRaw.containsKey(pid)) { dismissalText[pid] = 'out'; continue; }
      final raw    = dismissalRaw[pid]!;
      final wt     = raw['wicketType'] as String?;
      final bwId   = raw['bowlerId']   as int?;
      final bwName = bwId != null ? await _playerName(db, bwId) : '';
      switch (wt) {
        case 'bowled':      dismissalText[pid] = 'b $bwName'; break;
        case 'caught':      dismissalText[pid] = 'c & b $bwName'; break;
        case 'lbw':         dismissalText[pid] = 'lbw b $bwName'; break;
        case 'stumped':     dismissalText[pid] = 'st b $bwName'; break;
        case 'hit_wicket':  dismissalText[pid] = 'hit wkt b $bwName'; break;
        case 'run_out':     dismissalText[pid] = 'run out'; break;
        default:            dismissalText[pid] = bwName.isNotEmpty ? 'b $bwName' : 'out';
      }
    }

    // Build batter rows
    final List<_BatterRow> batterRows = [];
    for (final pid in batterOrder) {
      final st   = batterStats[pid]!;
      final name = await _playerName(db, pid);
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

    // Build bowler rows
    final List<_BowlerRow> bowlerRows = [];
    for (final pid in bowlerOrder) {
      final bw        = bowlerStats[pid]!;
      final name      = await _playerName(db, pid);
      final lb        = bw['legalBalls'] as int;
      final overBalls = bw['overBalls']  as Map<int, int>;
      final overRunsM = bw['overRuns']   as Map<int, int>;
      int maidens = 0;
      for (final ov in overBalls.keys) {
        if ((overBalls[ov] ?? 0) >= 6 && (overRunsM[ov] ?? 0) == 0) maidens++;
      }
      bowlerRows.add(_BowlerRow(
        playerId:   pid,
        name:       name,
        overs:      lb ~/ 6,
        ballsExtra: lb % 6,
        maidens:    maidens,
        runs:       bw['runs']    as int,
        wickets:    bw['wickets'] as int,
      ));
    }

    // Build FOW entries
    final List<_FowEntry> fowEntries = [];
    for (final f in fowRaw) {
      final pid  = f['outPlayer'] as int;
      final name = _nameCache[pid] ?? await _playerName(db, pid);
      fowEntries.add(_FowEntry(
        score:     f['score']     as int,
        wicketNum: f['wicketNum'] as int,
        batter:    name,
        overNum:   f['overNum']   as int,
        ballNum:   f['ballNum']   as int,
      ));
    }

    return _InningsData(
      batters:      batterRows,
      bowlers:      bowlerRows,
      extras:       _ExtrasRow(
        wides:   wides, noBalls: noBalls,
        byes:    byes,  legByes: legByes, penalty: penalty,
      ),
      totalRuns:    totalRuns,
      totalWickets: totalWickets,
      legalBalls:   legalBalls,
      fow:          fowEntries,
    );
  }

  Future<List<_CommentaryEntry>> _buildCommentary(DatabaseHelper db) async {
    final rows = await db.getBallEventsWithPlayerNames(widget.matchId);
    return rows.map((r) => _CommentaryEntry(
      innings:      (r[DatabaseHelper.colInnings]    as int?) ?? 1,
      overNum:      (r[DatabaseHelper.colOverNum]    as int?) ?? 0,
      ballNum:      (r[DatabaseHelper.colBallNum]    as int?) ?? 0,
      bowlerName:   (r['bowler_name']                as String?) ?? 'Unknown',
      strikerName:  (r['striker_name']               as String?) ?? 'Unknown',
      runsScored:   (r[DatabaseHelper.colRunsScored] as int?) ?? 0,
      extraRuns:    (r[DatabaseHelper.colExtraRuns]  as int?) ?? 0,
      extraType:    r[DatabaseHelper.colExtraType]   as String?,
      isBoundary:   ((r[DatabaseHelper.colIsBoundary] as int?) ?? 0) == 1,
      isWicket:     ((r[DatabaseHelper.colIsWicket]   as int?) ?? 0) == 1,
      wicketType:   r[DatabaseHelper.colWicketType]  as String?,
      outPlayerName: r['out_player_name']            as String?,
    )).toList();
  }

  // ── Share helper ──────────────────────────────────────────────────────────

  void _shareScorecard() {
    final c = Theme.of(context).appColors;
    final buf = StringBuffer();
    buf.writeln('BooknScore - ${widget.teamA} vs ${widget.teamB}');
    buf.writeln('─' * 32);
    for (int i = 0; i < 2; i++) {
      final data = _innings[i];
      final team = _battingTeams[i];
      if (data == null) continue;
      buf.writeln('\n${i == 0 ? '1st' : '2nd'} Innings: $team');
      buf.writeln('${data.totalRuns}/${data.totalWickets} (${data.oversString} ov)');
      for (final b in data.batters.where((b) => b.runs > 0 || b.balls > 0)) {
        buf.writeln('  ${b.name}: ${b.runs} (${b.balls})');
      }
      for (final b in data.bowlers.where((b) => b.overs > 0 || b.ballsExtra > 0)) {
        buf.writeln('  ${b.name}: ${b.wickets}/${b.runs} (${b.oversString} ov)');
      }
    }
    if (_resultText.isNotEmpty) {
      buf.writeln('\nResult: $_resultText');
    }
    buf.writeln('\nScored with BooknScore');
    Clipboard.setData(ClipboardData(text: buf.toString()));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        'Scorecard copied to clipboard',
        style: GoogleFonts.rajdhani(fontWeight: FontWeight.w600),
      ),
      backgroundColor: c.accentGreen.withAlpha(200),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).appColors;
    return Scaffold(
      backgroundColor: c.surface,
      appBar: _buildAppBar(c),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: c.neon))
          : _error != null
              ? _buildError(c)
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildSummaryTab(c),
                    _buildScorecardTab(c),
                  ],
                ),
    );
  }

  PreferredSizeWidget _buildAppBar(AppColors c) {
    return AppBar(
      backgroundColor: c.surface,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new, color: c.neon, size: 18),
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
              color: c.textPrimary,
            ),
          ),
          Text(
            _matchStatus.toUpperCase(),
            style: GoogleFonts.rajdhani(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: _matchStatus == 'completed' ? c.neon : c.liveRed,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
      actions: [
        if (!_loading && _error == null)
          IconButton(
            icon: Icon(Icons.share_outlined, color: c.neon),
            tooltip: 'Share scorecard',
            onPressed: _shareScorecard,
          ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(44),
        child: Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.glassBorder, width: 1)),
          ),
          child: TabBar(
            controller: _tabController,
            indicatorColor: c.neon,
            indicatorWeight: 3,
            labelColor: c.neon,
            unselectedLabelColor: c.textSecondary,
            labelStyle: GoogleFonts.rajdhani(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
            tabs: const [
              Tab(text: 'Summary'),
              Tab(text: 'Scorecard'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildError(AppColors c) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'Could not load match data.\n$_error',
          style: GoogleFonts.rajdhani(color: c.textSecondary, fontSize: 16),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SUMMARY TAB
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildSummaryTab(AppColors c) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Result banner ──────────────────────────────────────────────
          if (_resultText.isNotEmpty) _buildResultBanner(c),

          // ── MOTM card ──────────────────────────────────────────────────
          if (_motm != null) _buildMotmCard(_motm!),

          const SizedBox(height: 4),

          // ── Top performers, per innings ────────────────────────────────
          for (int i = 0; i < 2; i++) ...[
            if (_topBatters[i].isNotEmpty || _topBowlers[i].isNotEmpty) ...[
              _buildSummaryInningsHeader(c, i),
              if (_topBatters[i].isNotEmpty) ...[
                _buildSectionLabel(c, 'TOP BATTERS'),
                _buildTopBatterCards(c, _topBatters[i]),
              ],
              if (_topBowlers[i].isNotEmpty) ...[
                _buildSectionLabel(c, 'TOP BOWLERS'),
                _buildTopBowlerCards(c, _topBowlers[i]),
              ],
              const SizedBox(height: 8),
            ],
          ],

          // Fallback if no data at all
          if (_innings[0] == null && _innings[1] == null)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'No ball data available yet.',
                  style: GoogleFonts.rajdhani(
                    fontSize: 16, color: c.textSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildResultBanner(AppColors c) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: c.neon.withAlpha(15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.neon.withAlpha(80), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4, height: 14,
                decoration: BoxDecoration(
                  color: c.neon,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'RESULT',
                style: GoogleFonts.rajdhani(
                  fontSize: 11, fontWeight: FontWeight.w700,
                  color: c.neon, letterSpacing: 3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _resultText,
            style: GoogleFonts.rajdhani(
              fontSize: 17, fontWeight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryInningsHeader(AppColors c, int idx) {
    final data     = _innings[idx];
    final teamName = _battingTeams[idx];
    final color    = idx == 0 ? _inn1Color : _inn2Color;
    final label    = idx == 0 ? '1st Innings' : '2nd Innings';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(70), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 4, height: 30,
            decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TeamDetailScreen(teamName: teamName),
                    ),
                  ),
                  child: Text(
                    teamName.toUpperCase(),
                    style: GoogleFonts.rajdhani(
                      fontSize: 12, fontWeight: FontWeight.w800,
                      color: color, letterSpacing: 2,
                      decoration: TextDecoration.underline,
                      decorationColor: color,
                    ),
                  ),
                ),
                Text(
                  label,
                  style: GoogleFonts.rajdhani(
                    fontSize: 11, color: c.textSecondary, letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          if (data != null)
            Text(
              '${data.totalRuns}/${data.totalWickets} (${data.oversString})',
              style: GoogleFonts.rajdhani(
                fontSize: 18, fontWeight: FontWeight.w900, color: c.textPrimary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(AppColors c, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        label,
        style: GoogleFonts.rajdhani(
          fontSize: 11, fontWeight: FontWeight.w700,
          color: c.accentGreen, letterSpacing: 2.5,
        ),
      ),
    );
  }

  Widget _buildTopBatterCards(AppColors c, List<_BatterRow> batters) {
    return Column(
      children: batters.map((b) => _buildBatterSummaryCard(c, b)).toList(),
    );
  }

  Widget _buildBatterSummaryCard(AppColors c, _BatterRow b) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.glassBorder, width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PlayerProfileScreen(
                        playerId: b.playerId,
                        playerName: b.name,
                      ),
                    ),
                  ),
                  child: Text(
                    b.name,
                    style: GoogleFonts.rajdhani(
                      fontSize: 14, fontWeight: FontWeight.w700,
                      color: c.neon,
                      decoration: TextDecoration.underline,
                      decorationColor: c.neon,
                    ),
                  ),
                ),
                Text(
                  b.dismissalText,
                  style: GoogleFonts.rajdhani(fontSize: 12, color: c.textSecondary),
                ),
              ],
            ),
          ),
          _summaryStatCol(c, '${b.runs}', 'R'),
          const SizedBox(width: 14),
          _summaryStatCol(c, '${b.balls}', 'B'),
          const SizedBox(width: 14),
          _summaryStatCol(c, '${b.fours}', '4s'),
          const SizedBox(width: 14),
          _summaryStatCol(c, '${b.sixes}', '6s'),
          const SizedBox(width: 14),
          _summaryStatCol(c, b.strikeRate.toStringAsFixed(1), 'SR'),
        ],
      ),
    );
  }

  Widget _buildTopBowlerCards(AppColors c, List<_BowlerRow> bowlers) {
    return Column(
      children: bowlers.map((b) => _buildBowlerSummaryCard(c, b)).toList(),
    );
  }

  Widget _buildBowlerSummaryCard(AppColors c, _BowlerRow b) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.glassBorder, width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PlayerProfileScreen(
                    playerId: b.playerId,
                    playerName: b.name,
                  ),
                ),
              ),
              child: Text(
                b.name,
                style: GoogleFonts.rajdhani(
                  fontSize: 14, fontWeight: FontWeight.w700,
                  color: c.neon,
                  decoration: TextDecoration.underline,
                  decorationColor: c.neon,
                ),
              ),
            ),
          ),
          _summaryStatCol(c, b.oversString, 'OV'),
          const SizedBox(width: 14),
          _summaryStatCol(c, '${b.maidens}', 'M'),
          const SizedBox(width: 14),
          _summaryStatCol(c, '${b.runs}', 'R'),
          const SizedBox(width: 14),
          _summaryStatCol(c, '${b.wickets}', 'W'),
          const SizedBox(width: 14),
          _summaryStatCol(c, b.economy.toStringAsFixed(2), 'ECO'),
        ],
      ),
    );
  }

  Widget _summaryStatCol(AppColors c, String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: GoogleFonts.rajdhani(
            fontSize: 14, fontWeight: FontWeight.w700, color: c.textPrimary,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.rajdhani(fontSize: 10, color: c.textSecondary, letterSpacing: 1),
        ),
      ],
    );
  }

  // ── MOTM FIFA Card ────────────────────────────────────────────────────────

  Widget _buildMotmCard(_MotmData motm) {
    const Color goldLight = Color(0xFFFFD700);
    const Color goldMid   = Color(0xFFFF8F00);
    const Color goldDark  = Color(0xFFE65100);
    const Color cardBg    = Color(0xFF1A1200);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: cardBg,
        border: Border(bottom: BorderSide(color: Color(0x33FFD700), width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4, height: 16,
                decoration: BoxDecoration(
                  color: goldLight, borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'MAN OF THE MATCH',
                style: GoogleFonts.rajdhani(
                  fontSize: 11, fontWeight: FontWeight.w700,
                  color: goldLight, letterSpacing: 3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 200, height: 260,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [goldLight, goldMid, goldDark, goldMid, goldLight],
                  stops: [0.0, 0.25, 0.5, 0.75, 1.0],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: goldLight.withAlpha(120),
                    blurRadius: 24, spreadRadius: 2,
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withAlpha(40),
                          Colors.transparent,
                          Colors.white.withAlpha(20),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  motm.impactPoints.toStringAsFixed(0),
                                  style: GoogleFonts.rajdhani(
                                    fontSize: 36, fontWeight: FontWeight.w900,
                                    color: const Color(0xFF1A1200), height: 1,
                                  ),
                                ),
                                Text(
                                  'IP',
                                  style: GoogleFonts.rajdhani(
                                    fontSize: 10, fontWeight: FontWeight.w800,
                                    color: const Color(0xFF3E2800), letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0x551A1200),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: const Color(0x881A1200), width: 1),
                              ),
                              child: Text(
                                'MOTM',
                                style: GoogleFonts.rajdhani(
                                  fontSize: 9, fontWeight: FontWeight.w900,
                                  color: const Color(0xFF1A1200), letterSpacing: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: 90, height: 90,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0x881A1200), width: 2),
                            color: const Color(0x441A1200),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: _buildMotmAvatar(motm),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          motm.name.toUpperCase(),
                          style: GoogleFonts.rajdhani(
                            fontSize: 16, fontWeight: FontWeight.w900,
                            color: const Color(0xFF1A1200), letterSpacing: 1.5,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 10),
                        Container(height: 1, color: const Color(0x441A1200)),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _motmStat('${motm.runs}',    'RUNS'),
                            _motmStat('${motm.wickets}', 'WKT'),
                            _motmStat('${motm.fours}',   '4s'),
                            _motmStat('${motm.sixes}',   '6s'),
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

  Widget _buildMotmAvatar(_MotmData motm) {
    final path = motm.avatarPath;
    if (path != null && path.isNotEmpty) {
      if (path.startsWith('http://') || path.startsWith('https://')) {
        return CachedNetworkImage(
          imageUrl: path,
          fit: BoxFit.cover,
          errorWidget: (ctx, url, e) => _motmPlaceholder(),
        );
      }
      final file = File(path);
      if (file.existsSync()) {
        return Image.file(file, fit: BoxFit.cover,
            errorBuilder: (ctx, e, st) => _motmPlaceholder());
      }
    }
    return _motmPlaceholder();
  }

  Widget _motmPlaceholder() => const Icon(
    Icons.person, size: 56, color: Color(0x881A1200),
  );

  Widget _motmStat(String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: GoogleFonts.rajdhani(
            fontSize: 16, fontWeight: FontWeight.w900,
            color: const Color(0xFF1A1200),
          ),
        ),
        Text(
          label,
          style: GoogleFonts.rajdhani(
            fontSize: 9, fontWeight: FontWeight.w700,
            color: const Color(0xFF3E2800), letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SCORECARD TAB  (nested TabController: 1st Inn | 2nd Inn | Commentary)
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildScorecardTab(AppColors c) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Container(
            color: c.card,
            child: TabBar(
              indicatorColor: c.accentGreen,
              indicatorWeight: 2,
              labelColor: c.accentGreen,
              unselectedLabelColor: c.textSecondary,
              labelStyle: GoogleFonts.rajdhani(
                fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.5,
              ),
              tabs: [
                Tab(text: _battingTeams[0].isEmpty ? '1st Inn' : _battingTeams[0]),
                Tab(text: _battingTeams[1].isEmpty ? '2nd Inn' : _battingTeams[1]),
                const Tab(text: 'Commentary'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildInningsTab(c, 0),
                _buildInningsTab(c, 1),
                _buildCommentaryTab(c),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInningsTab(AppColors c, int idx) {
    final data  = _innings[idx];
    final team  = _battingTeams[idx];
    final color = idx == 0 ? _inn1Color : _inn2Color;

    if (data == null || (data.batters.isEmpty && data.bowlers.isEmpty)) {
      return Center(
        child: Text(
          'No data for this innings yet.',
          style: GoogleFonts.rajdhani(color: c.textSecondary, fontSize: 16),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInningsHeader(c, team, data, color),
          const SizedBox(height: 12),
          _buildScLabel(c, 'BATTING'),
          _buildBattingTable(c, data.batters),
          _buildExtrasAndTotal(c, data),
          const SizedBox(height: 20),
          _buildScLabel(c, 'BOWLING'),
          _buildBowlingTable(c, data.bowlers),
          _buildScLabel(c, 'FALL OF WICKETS'),
          _buildFowSection(c, data.fow),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildScLabel(AppColors c, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Text(
        label,
        style: GoogleFonts.rajdhani(
          fontSize: 11, fontWeight: FontWeight.w700,
          color: c.accentGreen, letterSpacing: 2.5,
        ),
      ),
    );
  }

  Widget _buildInningsHeader(AppColors c, String team, _InningsData data, Color color) {
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
            width: 4, height: 36,
            decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(2),
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
                      builder: (_) => TeamDetailScreen(teamName: team),
                    ),
                  ),
                  child: Text(
                    team.toUpperCase(),
                    style: GoogleFonts.rajdhani(
                      fontSize: 13, fontWeight: FontWeight.w700,
                      color: color, letterSpacing: 2,
                      decoration: TextDecoration.underline,
                      decorationColor: color,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${data.totalRuns}/${data.totalWickets}',
                  style: GoogleFonts.rajdhani(
                    fontSize: 32, fontWeight: FontWeight.w900,
                    color: c.textPrimary, height: 1,
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
                style: GoogleFonts.rajdhani(fontSize: 11, color: c.textSecondary),
              ),
              Text(
                data.oversString,
                style: GoogleFonts.rajdhani(
                  fontSize: 22, fontWeight: FontWeight.w700, color: c.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Batting table ─────────────────────────────────────────────────────────

  Widget _buildBattingTable(AppColors c, List<_BatterRow> rows) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.glassBorder, width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: [
            _battingHeaderRow(c),
            const Divider(height: 1, thickness: 1, color: _dividerColor),
            ...rows.asMap().entries.map((entry) {
              final isLast = entry.key == rows.length - 1;
              return Column(
                children: [
                  _battingDataRow(c, entry.value),
                  if (!isLast) const Divider(height: 1, thickness: 1, color: _dividerColor),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _battingHeaderRow(AppColors c) {
    return Container(
      color: c.glassBg,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          _headerCell(c, 'BATTER', flex: 5, align: TextAlign.left,
              padding: const EdgeInsets.only(left: 14)),
          _headerCell(c, 'R',  flex: 2),
          _headerCell(c, 'B',  flex: 2),
          _headerCell(c, '4s', flex: 2),
          _headerCell(c, '6s', flex: 2),
          _headerCell(c, 'SR', flex: 3),
        ],
      ),
    );
  }

  Widget _battingDataRow(AppColors c, _BatterRow row) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Padding(
              padding: const EdgeInsets.only(left: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PlayerProfileScreen(
                          playerId: row.playerId,
                          playerName: row.name,
                        ),
                      ),
                    ),
                    child: Text(
                      row.name,
                      style: GoogleFonts.rajdhani(
                        fontSize: 14, fontWeight: FontWeight.w600,
                        color: row.isNotOut ? c.accentGreen : c.neon,
                        decoration: TextDecoration.underline,
                        decorationColor: row.isNotOut ? c.accentGreen : c.neon,
                      ),
                    ),
                  ),
                  Text(
                    row.dismissalText,
                    style: GoogleFonts.rajdhani(
                      fontSize: 11, color: c.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          _dataCell(c, '${row.runs}', flex: 2,
              style: GoogleFonts.rajdhani(
                fontSize: 14, fontWeight: FontWeight.w700, color: c.textPrimary,
              )),
          _dataCell(c, '${row.balls}', flex: 2),
          _dataCell(c, '${row.fours}',  flex: 2),
          _dataCell(c, '${row.sixes}',  flex: 2),
          _dataCell(c, row.strikeRate.toStringAsFixed(1), flex: 3),
        ],
      ),
    );
  }

  // ── Bowling table ─────────────────────────────────────────────────────────

  Widget _buildBowlingTable(AppColors c, List<_BowlerRow> rows) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.glassBorder, width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: [
            _bowlingHeaderRow(c),
            const Divider(height: 1, thickness: 1, color: _dividerColor),
            ...rows.asMap().entries.map((entry) {
              final isLast = entry.key == rows.length - 1;
              return Column(
                children: [
                  _bowlingDataRow(c, entry.value),
                  if (!isLast) const Divider(height: 1, thickness: 1, color: _dividerColor),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _bowlingHeaderRow(AppColors c) {
    return Container(
      color: c.glassBg,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          _headerCell(c, 'BOWLER', flex: 5, align: TextAlign.left,
              padding: const EdgeInsets.only(left: 14)),
          _headerCell(c, 'O',  flex: 2),
          _headerCell(c, 'M',  flex: 2),
          _headerCell(c, 'R',  flex: 2),
          _headerCell(c, 'W',  flex: 2),
          _headerCell(c, 'ECO', flex: 3),
        ],
      ),
    );
  }

  Widget _bowlingDataRow(AppColors c, _BowlerRow row) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Padding(
              padding: const EdgeInsets.only(left: 14),
              child: GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PlayerProfileScreen(
                      playerId: row.playerId,
                      playerName: row.name,
                    ),
                  ),
                ),
                child: Text(
                  row.name,
                  style: GoogleFonts.rajdhani(
                    fontSize: 14, fontWeight: FontWeight.w600,
                    color: c.neon,
                    decoration: TextDecoration.underline,
                    decorationColor: c.neon,
                  ),
                ),
              ),
            ),
          ),
          _dataCell(c, row.oversString, flex: 2),
          _dataCell(c, '${row.maidens}', flex: 2),
          _dataCell(c, '${row.runs}',    flex: 2),
          _dataCell(c, '${row.wickets}', flex: 2,
              style: GoogleFonts.rajdhani(
                fontSize: 14, fontWeight: FontWeight.w700,
                color: row.wickets > 0 ? _wicketRed : c.textSecondary,
              )),
          _dataCell(c, row.economy.toStringAsFixed(2), flex: 3),
        ],
      ),
    );
  }

  // ── Extras & Total ────────────────────────────────────────────────────────

  Widget _buildExtrasAndTotal(AppColors c, _InningsData data) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      decoration: BoxDecoration(
        color: c.card,
        border: Border(
          left: BorderSide(color: c.glassBorder, width: 1),
          right: BorderSide(color: c.glassBorder, width: 1),
          bottom: BorderSide(color: c.glassBorder, width: 1),
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Column(
        children: [
          const Divider(height: 1, thickness: 1, color: _dividerColor),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                          fontSize: 13, color: c.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        data.extras.detail,
                        style: GoogleFonts.rajdhani(
                          fontSize: 11, color: c.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${data.extras.total}',
                  style: GoogleFonts.rajdhani(
                    fontSize: 14, color: c.textSecondary, fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: _dividerColor),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Text(
                    'Total',
                    style: GoogleFonts.rajdhani(
                      fontSize: 14, color: c.textPrimary, fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '${data.totalRuns}/${data.totalWickets} (${data.oversString} ov)',
                  style: GoogleFonts.rajdhani(
                    fontSize: 14, color: c.textPrimary, fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Fall of Wickets ───────────────────────────────────────────────────────

  Widget _buildFowSection(AppColors c, List<_FowEntry> fow) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.glassBorder, width: 1),
      ),
      child: fow.isEmpty
          ? Text(
              'No wickets',
              style: GoogleFonts.rajdhani(fontSize: 13, color: c.textSecondary),
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (int i = 0; i < fow.length; i++) ...[
                    _buildFowChip(c, fow[i]),
                    if (i < fow.length - 1)
                      Container(
                        width: 1, height: 28,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        color: _dividerColor,
                      ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildFowChip(AppColors c, _FowEntry f) {
    final overDisplay = '${f.overNum - 1}.${f.ballNum}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _wicketRed.withAlpha(25),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _wicketRed.withAlpha(80), width: 1),
      ),
      child: RichText(
        text: TextSpan(
          style: GoogleFonts.robotoMono(fontSize: 12),
          children: [
            const TextSpan(
              text: '',
              style: TextStyle(color: _wicketRed, fontWeight: FontWeight.w700),
            ),
            TextSpan(
              text: '${f.score}-${f.wicketNum}',
              style: const TextStyle(
                color: _wicketRed, fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: ' (${f.batter}, $overDisplay)',
              style: TextStyle(color: c.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  // ── Commentary tab ────────────────────────────────────────────────────────

  Widget _buildCommentaryTab(AppColors c) {
    if (_commentary.isEmpty) {
      return Center(
        child: Text(
          'No ball-by-ball data available yet.',
          style: GoogleFonts.rajdhani(color: c.textSecondary, fontSize: 16),
        ),
      );
    }
    final entries = _commentary.reversed.toList();
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: entries.length,
      itemBuilder: (_, i) => _buildCommentaryRow(c, entries[i]),
    );
  }

  Widget _buildCommentaryRow(AppColors c, _CommentaryEntry entry) {
    final outcome    = entry.outcomeText;
    final isWicket   = entry.isWicket;
    final isSix      = outcome == 'SIX!';
    final isFour     = outcome == 'FOUR!';
    final isExtra    = entry.extraType != null;

    final Color accentColor = isWicket
        ? _wicketRed
        : isSix ? _sixPurple : isFour ? _boundaryBlue
        : isExtra ? const Color(0xFFFFB300) : c.textSecondary;

    final bool isHighlight = isWicket || isSix || isFour;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isHighlight ? accentColor.withAlpha(18) : c.card,
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: accentColor, width: isHighlight ? 3 : 2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            alignment: Alignment.center,
            child: Text(
              '${entry.overNum - 1}.${entry.ballNum}',
              style: GoogleFonts.robotoMono(
                fontSize: 12, fontWeight: FontWeight.w700, color: accentColor,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: GoogleFonts.rajdhani(fontSize: 14, color: c.textSecondary),
                    children: [
                      TextSpan(
                        text: '${entry.bowlerName} ',
                        style: TextStyle(color: c.textPrimary),
                      ),
                      const TextSpan(text: 'to '),
                      TextSpan(
                        text: entry.strikerName,
                        style: TextStyle(color: c.textPrimary),
                      ),
                      const TextSpan(text: ', '),
                      TextSpan(
                        text: outcome,
                        style: TextStyle(
                          color: accentColor,
                          fontWeight: isHighlight ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (entry.overNum == 1 && entry.ballNum == 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      'INNINGS ${entry.innings}',
                      style: GoogleFonts.rajdhani(
                        fontSize: 10,
                        color: entry.innings == 1 ? _inn1Color : _inn2Color,
                        letterSpacing: 1.2, fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            width: 32, alignment: Alignment.center,
            child: Text(
              isWicket ? 'W' : isExtra ? 'E' : '${entry.runsScored}',
              style: GoogleFonts.robotoMono(
                fontSize: 13, fontWeight: FontWeight.w700, color: accentColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared table helpers ──────────────────────────────────────────────────

  Widget _headerCell(
    AppColors c,
    String text, {
    required int flex,
    TextAlign align = TextAlign.center,
    EdgeInsets? padding,
  }) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: padding ?? EdgeInsets.zero,
        child: Text(
          text,
          textAlign: align,
          style: GoogleFonts.rajdhani(
            fontSize: 11, fontWeight: FontWeight.w700,
            color: c.textSecondary, letterSpacing: 1,
          ),
        ),
      ),
    );
  }

  Widget _dataCell(
    AppColors c,
    String text, {
    required int flex,
    TextStyle? style,
  }) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: style ?? GoogleFonts.rajdhani(
          fontSize: 13, color: c.textSecondary,
        ),
      ),
    );
  }
}
