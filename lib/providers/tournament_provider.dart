import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

import '../services/database_helper.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MODELS
// ─────────────────────────────────────────────────────────────────────────────

/// Immutable snapshot of one team's standing in a tournament.
class TeamStanding {
  const TeamStanding({
    required this.teamName,
    required this.played,
    required this.won,
    required this.lost,
    required this.tied,
    required this.noResult,
    required this.points,
    required this.nrr,
    required this.runsScored,
    required this.oversFaced,
    required this.runsConceded,
    required this.oversBowled,
  });

  final String teamName;
  final int played;
  final int won;
  final int lost;
  final int tied;
  final int noResult;
  final int points;

  /// Net Run Rate = (Total Runs Scored / Total Overs Faced)
  ///              − (Total Runs Conceded / Total Overs Bowled)
  final double nrr;

  // Raw accumulators (kept for debugging / detailed display)
  final int runsScored;
  final double oversFaced;
  final int runsConceded;
  final double oversBowled;

  String get nrrDisplay {
    final prefix = nrr >= 0 ? '+' : '';
    return '$prefix${nrr.toStringAsFixed(3)}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PROVIDER
// ─────────────────────────────────────────────────────────────────────────────

class TournamentProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _tournaments = [];
  bool _isLoading = false;
  String? _error;

  List<Map<String, dynamic>> get tournaments => List.unmodifiable(_tournaments);
  bool get isLoading => _isLoading;
  String? get error => _error;

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<void> loadTournaments() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _tournaments = await DatabaseHelper.instance.fetchAllTournaments();
    } catch (e, st) {
      developer.log('loadTournaments failed', name: 'TournamentProvider', error: e, stackTrace: st);
      _error = 'Failed to load tournaments.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Create a new tournament and refresh the list.
  Future<int> createTournament({
    required String name,
    required String format,
    required int oversPerMatch,
    required List<String> teams,
    String? createdBy,
  }) async {
    final id = await DatabaseHelper.instance.insertTournament(
      name: name,
      format: format,
      oversPerMatch: oversPerMatch,
      teams: teams,
      createdBy: createdBy,
    );
    await loadTournaments();
    return id;
  }

  /// Mark [teamName] as eliminated in [tournament_teams] for [tournamentId].
  Future<void> eliminateTeam(int tournamentId, String teamName) async {
    try {
      await DatabaseHelper.instance.eliminateTeam(tournamentId, teamName);
    } catch (e, st) {
      developer.log('eliminateTeam failed', name: 'TournamentProvider', error: e, stackTrace: st);
    }
  }

  /// Mark the tournament as completed and record the winning team.
  ///
  /// Sets `status = 'completed'` and resolves + sets `winner_team_id`.
  Future<void> completeTournamentWithWinner(
    int tournamentId,
    String winnerTeamName,
  ) async {
    try {
      await DatabaseHelper.instance
          .completeTournamentWithWinner(tournamentId, winnerTeamName);
      await loadTournaments();
    } catch (e, st) {
      developer.log(
        'completeTournamentWithWinner failed',
        name: 'TournamentProvider',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Compute Player of the Tournament Series for [tournamentId].
  ///
  /// Returns a list of maps sorted by POTS score descending:
  ///   { playerId, playerName, avatarPath, score, runs, wickets, catches }
  Future<List<Map<String, dynamic>>> getPotsForTournament(int tournamentId) async {
    try {
      return await DatabaseHelper.instance.computePots(tournamentId);
    } catch (e, st) {
      developer.log('getPotsForTournament failed', name: 'TournamentProvider', error: e, stackTrace: st);
      return [];
    }
  }

  // ── Points Table calculation ───────────────────────────────────────────────

  /// Build the full points table for [tournamentId].
  ///
  /// Only completed matches contribute to the table.
  /// Points: Win = 2, Tie / No Result = 1, Loss = 0.
  ///
  /// NRR formula (ICC standard):
  ///   NRR = (Σ runs scored / Σ overs faced) − (Σ runs conceded / Σ overs bowled)
  ///
  /// Overs are expressed as decimal fractions: e.g. 18.4 overs = 18 + 4/6 ≈ 18.667.
  ///
  /// All-out rule (ICC): if a team loses all wickets (is bowled out) BEFORE their
  /// full quota of overs, the denominator is set to the MAXIMUM scheduled overs
  /// (not the actual overs they survived).
  Future<List<TeamStanding>> buildPointsTable(int tournamentId) async {
    final db = DatabaseHelper.instance;

    // Fetch all completed matches for this tournament
    final allMatches = await db.fetchMatchesByTournament(tournamentId);
    final completedMatches = allMatches
        .where((m) => m[DatabaseHelper.colStatus] == 'completed')
        .toList();

    // Fetch tournament to get registered team list — prefer tournament_teams
    // table over the legacy comma-separated string so late-entry teams appear.
    final tournament = await db.fetchTournament(tournamentId);
    if (tournament == null) return [];

    final teamRows = await db.fetchAllTournamentTeamRows(tournamentId);
    List<String> teamNames;
    if (teamRows.isNotEmpty) {
      teamNames = teamRows.map((r) => r[DatabaseHelper.colTeamName] as String).toList();
    } else {
      // Fallback: legacy comma-separated field
      final teamsRaw = (tournament[DatabaseHelper.colTeams] as String?) ?? '';
      teamNames = teamsRaw
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList();
    }

    // Accumulator map keyed by team name
    final Map<String, _TeamAcc> acc = {
      for (final t in teamNames) t: _TeamAcc(t),
    };

    for (final match in completedMatches) {
      final matchId  = match[DatabaseHelper.colId] as int;
      final teamA    = match[DatabaseHelper.colTeamA] as String;
      final teamB    = match[DatabaseHelper.colTeamB] as String;
      final winner   = match[DatabaseHelper.colWinner] as String?;
      final totalOversAllowed = match[DatabaseHelper.colTotalOvers] as int;

      // Fetch innings summaries for both innings
      final inn1 = await db.getInningsSummary(matchId, 1);
      final inn2 = await db.getInningsSummary(matchId, 2);

      final runsA    = inn1['totalRuns']    ?? 0;
      final wicketsA = inn1['totalWickets'] ?? 0;
      final legalBallsA = inn1['legalBalls'] ?? 0;

      final runsB    = inn2['totalRuns']    ?? 0;
      final wicketsB = inn2['totalWickets'] ?? 0;
      final legalBallsB = inn2['legalBalls'] ?? 0;

      // Squad size: use match's squad_size column to determine the all-out
      // threshold (squad_size - 1 wickets = all out).
      final squadSize = (match[DatabaseHelper.colSquadSize] as int?) ?? 11;
      final wicketLimit = squadSize - 1;

      // Convert legal balls to decimal overs per ICC rule:
      //   • All-out (wickets == wicketLimit) → use MAX overs (full quota)
      //   • Not all-out → use actual legal balls faced / bowled
      final oversA = _legalBallsToOvers(legalBallsA, totalOversAllowed, wicketsA, wicketLimit);
      final oversB = _legalBallsToOvers(legalBallsB, totalOversAllowed, wicketsB, wicketLimit);

      // Ensure both team accumulators exist (handles teams not in original list)
      acc.putIfAbsent(teamA, () => _TeamAcc(teamA));
      acc.putIfAbsent(teamB, () => _TeamAcc(teamB));

      final accA = acc[teamA]!;
      final accB = acc[teamB]!;

      accA.played++;
      accB.played++;

      // NRR accumulators
      accA.runsScored    += runsA;
      accA.oversFaced    += oversA;
      accA.runsConceded  += runsB;
      accA.oversBowled   += oversB;

      accB.runsScored    += runsB;
      accB.oversFaced    += oversB;
      accB.runsConceded  += runsA;
      accB.oversBowled   += oversA;

      // Determine result
      if (winner == null || winner.isEmpty || winner.toLowerCase() == 'no result') {
        accA.noResult++;
        accB.noResult++;
        accA.points += 1;
        accB.points += 1;
      } else if (winner.toLowerCase() == 'draw' || winner.toLowerCase() == 'tie') {
        accA.tied++;
        accB.tied++;
        accA.points += 1;
        accB.points += 1;
      } else if (winner == teamA) {
        accA.won++;
        accB.lost++;
        accA.points += 2;
      } else if (winner == teamB) {
        accB.won++;
        accA.lost++;
        accB.points += 2;
      } else {
        // winner string may be descriptive ("TeamA won by 5 runs")
        // Fall back to the raw text — try to detect which team won
        final wLower = winner.toLowerCase();
        final aLower = teamA.toLowerCase();
        final bLower = teamB.toLowerCase();
        if (wLower.contains(aLower)) {
          accA.won++;
          accB.lost++;
          accA.points += 2;
        } else if (wLower.contains(bLower)) {
          accB.won++;
          accA.lost++;
          accB.points += 2;
        } else {
          // Cannot determine winner — treat as no result
          accA.noResult++;
          accB.noResult++;
          accA.points += 1;
          accB.points += 1;
        }
      }
    }

    // Convert accumulators to standings
    final standings = acc.values.map((a) {
      final nrr = _calculateNrr(
        runsScored:   a.runsScored,
        oversFaced:   a.oversFaced,
        runsConceded: a.runsConceded,
        oversBowled:  a.oversBowled,
      );
      return TeamStanding(
        teamName:     a.teamName,
        played:       a.played,
        won:          a.won,
        lost:         a.lost,
        tied:         a.tied,
        noResult:     a.noResult,
        points:       a.points,
        nrr:          nrr,
        runsScored:   a.runsScored,
        oversFaced:   a.oversFaced,
        runsConceded: a.runsConceded,
        oversBowled:  a.oversBowled,
      );
    }).toList();

    // Sort: points desc, then NRR desc, then alphabetical
    standings.sort((a, b) {
      final pCmp = b.points.compareTo(a.points);
      if (pCmp != 0) return pCmp;
      final nCmp = b.nrr.compareTo(a.nrr);
      if (nCmp != 0) return nCmp;
      return a.teamName.compareTo(b.teamName);
    });

    return standings;
  }

  // ── NRR helpers ────────────────────────────────────────────────────────────

  /// Convert a legal-ball count to decimal overs using ICC NRR rules.
  ///
  /// ICC rule:
  ///   • If the team was **all-out** (wickets == [wicketLimit]) before their
  ///     full allocation, the denominator MUST be set to [maxOvers] — as if
  ///     they faced the full quota.
  ///   • If the team was **not** all-out (batted out their overs normally),
  ///     convert the actual legal balls to decimal overs:
  ///     e.g., 20 balls = 3.2 overs (3 + 2/6 ≈ 3.333…).
  ///
  /// Fractional over math: a "2.3" display means 2 complete overs + 3 balls,
  /// so as a decimal it is 2 + 3/6 = 2.5 (not 2.3).
  static double _legalBallsToOvers(
    int legalBalls,
    int maxOvers,
    int wickets,
    int wicketLimit,
  ) {
    if (wickets >= wicketLimit) {
      // All out — ICC rule: use the MAXIMUM scheduled overs as the denominator.
      return maxOvers.toDouble();
    }
    // Not all out — use actual balls faced/bowled converted to decimal overs.
    final completeOvers = legalBalls ~/ 6;
    final extraBalls    = legalBalls % 6;
    return completeOvers + extraBalls / 6.0;
  }

  /// Net Run Rate = (runs scored / overs faced) − (runs conceded / overs bowled).
  ///
  /// Returns 0.0 when overs are zero to avoid division by zero.
  static double _calculateNrr({
    required int    runsScored,
    required double oversFaced,
    required int    runsConceded,
    required double oversBowled,
  }) {
    final attackRate = oversFaced  > 0 ? runsScored   / oversFaced  : 0.0;
    final defendRate = oversBowled > 0 ? runsConceded / oversBowled : 0.0;
    return attackRate - defendRate;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Private accumulator (not exported)
// ─────────────────────────────────────────────────────────────────────────────
class _TeamAcc {
  _TeamAcc(this.teamName);

  final String teamName;
  int    played      = 0;
  int    won         = 0;
  int    lost        = 0;
  int    tied        = 0;
  int    noResult    = 0;
  int    points      = 0;
  int    runsScored  = 0;
  double oversFaced  = 0;
  int    runsConceded = 0;
  double oversBowled  = 0;
}
