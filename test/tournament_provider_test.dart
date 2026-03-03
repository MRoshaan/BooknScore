// Unit tests for the TournamentProvider NRR engine and points-table logic.
//
// These tests exercise the static helper methods (_legalBallsToOvers,
// _calculateNrr) and the full buildPointsTable() pipeline via a thin
// in-memory stub — no SQLite or Supabase required.

import 'package:flutter_test/flutter_test.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Pure helpers mirroring tournament_provider.dart
// ──────────────────────────────────────────────────────────────────────────────

/// Mirrors TournamentProvider._legalBallsToOvers()
double _legalBallsToOvers(int legalBalls, int maxOvers, int wickets) {
  if (wickets >= 10) {
    final completeOvers = legalBalls ~/ 6;
    final extra = legalBalls % 6;
    return completeOvers + extra / 6.0;
  }
  return maxOvers.toDouble();
}

/// Mirrors TournamentProvider._calculateNrr()
double _calculateNrr({
  required int runsScored,
  required double oversFaced,
  required int runsConceded,
  required double oversBowled,
}) {
  final attackRate = oversFaced > 0 ? runsScored / oversFaced : 0.0;
  final defendRate = oversBowled > 0 ? runsConceded / oversBowled : 0.0;
  return attackRate - defendRate;
}

// ──────────────────────────────────────────────────────────────────────────────
// Minimal accumulator to drive an in-memory points-table calculation
// ──────────────────────────────────────────────────────────────────────────────

class _TeamAcc {
  _TeamAcc(this.teamName);
  final String teamName;
  int played = 0;
  int won = 0;
  int lost = 0;
  int tied = 0;
  int noResult = 0;
  int points = 0;
  int runsScored = 0;
  double oversFaced = 0;
  int runsConceded = 0;
  double oversBowled = 0;
}

class _Standing {
  _Standing({
    required this.teamName,
    required this.played,
    required this.won,
    required this.lost,
    required this.tied,
    required this.noResult,
    required this.points,
    required this.nrr,
  });
  final String teamName;
  final int played, won, lost, tied, noResult, points;
  final double nrr;
  String get nrrDisplay => '${nrr >= 0 ? '+' : ''}${nrr.toStringAsFixed(3)}';
}

/// Runs a minimal in-memory points-table build identical to
/// TournamentProvider.buildPointsTable() but without the DB layer.
List<_Standing> _buildTable({
  required List<String> teams,
  required List<Map<String, dynamic>> completedMatches,
  required int maxOvers,
}) {
  final Map<String, _TeamAcc> acc = {for (final t in teams) t: _TeamAcc(t)};

  for (final match in completedMatches) {
    final teamA = match['teamA'] as String;
    final teamB = match['teamB'] as String;
    final winner = match['winner'] as String?;
    final runsA = match['runsA'] as int;
    final wicketsA = match['wicketsA'] as int;
    final legalBallsA = match['legalBallsA'] as int;
    final runsB = match['runsB'] as int;
    final wicketsB = match['wicketsB'] as int;
    final legalBallsB = match['legalBallsB'] as int;

    final oversA = _legalBallsToOvers(legalBallsA, maxOvers, wicketsA);
    final oversB = _legalBallsToOvers(legalBallsB, maxOvers, wicketsB);

    acc.putIfAbsent(teamA, () => _TeamAcc(teamA));
    acc.putIfAbsent(teamB, () => _TeamAcc(teamB));
    final accA = acc[teamA]!;
    final accB = acc[teamB]!;

    accA.played++;
    accB.played++;

    accA.runsScored += runsA;
    accA.oversFaced += oversA;
    accA.runsConceded += runsB;
    accA.oversBowled += oversB;

    accB.runsScored += runsB;
    accB.oversFaced += oversB;
    accB.runsConceded += runsA;
    accB.oversBowled += oversA;

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
        accA.noResult++;
        accB.noResult++;
        accA.points += 1;
        accB.points += 1;
      }
    }
  }

  final standings = acc.values.map((a) {
    final nrr = _calculateNrr(
      runsScored: a.runsScored,
      oversFaced: a.oversFaced,
      runsConceded: a.runsConceded,
      oversBowled: a.oversBowled,
    );
    return _Standing(
      teamName: a.teamName,
      played: a.played,
      won: a.won,
      lost: a.lost,
      tied: a.tied,
      noResult: a.noResult,
      points: a.points,
      nrr: nrr,
    );
  }).toList();

  standings.sort((a, b) {
    final pCmp = b.points.compareTo(a.points);
    if (pCmp != 0) return pCmp;
    final nCmp = b.nrr.compareTo(a.nrr);
    if (nCmp != 0) return nCmp;
    return a.teamName.compareTo(b.teamName);
  });

  return standings;
}

// ──────────────────────────────────────────────────────────────────────────────
// Tests
// ──────────────────────────────────────────────────────────────────────────────

void main() {
  // ── _legalBallsToOvers ──────────────────────────────────────────────────────
  group('_legalBallsToOvers', () {
    test('All-out: 18 overs 4 balls → 18.667', () {
      final result = _legalBallsToOvers(112, 20, 10); // 18*6+4 = 112 balls
      expect(result, closeTo(18.667, 0.001));
    });

    test('All-out: exactly 20 overs (120 balls) → 20.0', () {
      final result = _legalBallsToOvers(120, 20, 10);
      expect(result, equals(20.0));
    });

    test('All-out: 3 overs exactly → 3.0', () {
      final result = _legalBallsToOvers(18, 20, 10);
      expect(result, equals(3.0));
    });

    test('Not all-out → returns maxOvers regardless of balls bowled', () {
      // Only 60 balls bowled but not all out → full 20 overs used
      final result = _legalBallsToOvers(60, 20, 4);
      expect(result, equals(20.0));
    });

    test('9 wickets is NOT all-out → returns maxOvers', () {
      final result = _legalBallsToOvers(119, 20, 9);
      expect(result, equals(20.0));
    });

    test('Exactly 10 wickets IS all-out', () {
      final result = _legalBallsToOvers(60, 20, 10);
      expect(result, equals(10.0)); // 60 balls = 10 overs
    });
  });

  // ── _calculateNrr ──────────────────────────────────────────────────────────
  group('_calculateNrr', () {
    test('Positive NRR: scored faster than conceded', () {
      // Attack: 200/20 = 10.0, Defend: 150/20 = 7.5 → NRR = 2.5
      final nrr = _calculateNrr(
        runsScored: 200,
        oversFaced: 20.0,
        runsConceded: 150,
        oversBowled: 20.0,
      );
      expect(nrr, closeTo(2.5, 0.001));
    });

    test('Negative NRR: scored slower than conceded', () {
      // Attack: 150/20 = 7.5, Defend: 200/20 = 10.0 → NRR = -2.5
      final nrr = _calculateNrr(
        runsScored: 150,
        oversFaced: 20.0,
        runsConceded: 200,
        oversBowled: 20.0,
      );
      expect(nrr, closeTo(-2.5, 0.001));
    });

    test('Zero NRR: equal run rates', () {
      final nrr = _calculateNrr(
        runsScored: 180,
        oversFaced: 20.0,
        runsConceded: 180,
        oversBowled: 20.0,
      );
      expect(nrr, closeTo(0.0, 0.001));
    });

    test('Zero overs faced/bowled → returns 0 (no divide-by-zero crash)', () {
      final nrr = _calculateNrr(
        runsScored: 0,
        oversFaced: 0.0,
        runsConceded: 0,
        oversBowled: 0.0,
      );
      expect(nrr, equals(0.0));
    });

    test('NRR display: positive has + prefix', () {
      // Attack: 160/20=8, Defend: 140/20=7 → NRR = 1.0
      final nrr = _calculateNrr(
        runsScored: 160,
        oversFaced: 20.0,
        runsConceded: 140,
        oversBowled: 20.0,
      );
      final display = '${nrr >= 0 ? '+' : ''}${nrr.toStringAsFixed(3)}';
      expect(display, equals('+1.000'));
    });
  });

  // ── Points table: basic 2-team tournament ──────────────────────────────────
  group('Points table (2 teams, 1 match)', () {
    test('Winner gets 2 pts, loser gets 0', () {
      final table = _buildTable(
        teams: ['Alpha', 'Beta'],
        completedMatches: [
          {
            'teamA': 'Alpha',
            'teamB': 'Beta',
            'winner': 'Alpha',
            'runsA': 180, 'wicketsA': 5, 'legalBallsA': 120,
            'runsB': 150, 'wicketsB': 10, 'legalBallsB': 108,
          },
        ],
        maxOvers: 20,
      );
      expect(table[0].teamName, equals('Alpha'));
      expect(table[0].points, equals(2));
      expect(table[0].won, equals(1));
      expect(table[1].teamName, equals('Beta'));
      expect(table[1].points, equals(0));
      expect(table[1].lost, equals(1));
    });

    test('Tie: both teams get 1 pt', () {
      final table = _buildTable(
        teams: ['Alpha', 'Beta'],
        completedMatches: [
          {
            'teamA': 'Alpha',
            'teamB': 'Beta',
            'winner': 'tie',
            'runsA': 160, 'wicketsA': 10, 'legalBallsA': 120,
            'runsB': 160, 'wicketsB': 10, 'legalBallsB': 120,
          },
        ],
        maxOvers: 20,
      );
      expect(table[0].points, equals(1));
      expect(table[1].points, equals(1));
      expect(table[0].tied, equals(1));
      expect(table[1].tied, equals(1));
    });

    test('No result: both teams get 1 pt', () {
      final table = _buildTable(
        teams: ['Alpha', 'Beta'],
        completedMatches: [
          {
            'teamA': 'Alpha',
            'teamB': 'Beta',
            'winner': 'no result',
            'runsA': 100, 'wicketsA': 2, 'legalBallsA': 60,
            'runsB': 0, 'wicketsB': 0, 'legalBallsB': 0,
          },
        ],
        maxOvers: 20,
      );
      expect(table[0].noResult, equals(1));
      expect(table[0].points, equals(1));
      expect(table[1].noResult, equals(1));
      expect(table[1].points, equals(1));
    });

    test('NRR is non-zero when run rates differ', () {
      // Alpha: 180/20=9.0 attack, 150/18=8.333 defend → NRR ≈ 0.667
      // Beta:  150/18=8.333 attack, 180/20=9.0 defend → NRR ≈ -0.667
      final table = _buildTable(
        teams: ['Alpha', 'Beta'],
        completedMatches: [
          {
            'teamA': 'Alpha',
            'teamB': 'Beta',
            'winner': 'Alpha',
            'runsA': 180, 'wicketsA': 4, 'legalBallsA': 120, // full 20 overs
            'runsB': 150, 'wicketsB': 10, 'legalBallsB': 108, // all out in 18
          },
        ],
        maxOvers: 20,
      );
      expect(table[0].nrr, greaterThan(0));
      expect(table[1].nrr, lessThan(0));
    });
  });

  // ── Points table: 3-team round-robin ──────────────────────────────────────
  group('Points table (3 teams, 3 matches)', () {
    // Alpha beats Beta, Alpha beats Gamma, Beta beats Gamma
    // Expected: Alpha 4pts, Beta 2pts, Gamma 0pts

    late List<_Standing> table;

    setUp(() {
      table = _buildTable(
        teams: ['Alpha', 'Beta', 'Gamma'],
        completedMatches: [
          {
            'teamA': 'Alpha', 'teamB': 'Beta', 'winner': 'Alpha',
            'runsA': 180, 'wicketsA': 5, 'legalBallsA': 120,
            'runsB': 150, 'wicketsB': 10, 'legalBallsB': 108,
          },
          {
            'teamA': 'Alpha', 'teamB': 'Gamma', 'winner': 'Alpha',
            'runsA': 200, 'wicketsA': 3, 'legalBallsA': 120,
            'runsB': 120, 'wicketsB': 10, 'legalBallsB': 90,
          },
          {
            'teamA': 'Beta', 'teamB': 'Gamma', 'winner': 'Beta',
            'runsA': 160, 'wicketsA': 6, 'legalBallsA': 120,
            'runsB': 140, 'wicketsB': 10, 'legalBallsB': 102,
          },
        ],
        maxOvers: 20,
      );
    });

    test('Rankings are Alpha > Beta > Gamma', () {
      expect(table[0].teamName, equals('Alpha'));
      expect(table[1].teamName, equals('Beta'));
      expect(table[2].teamName, equals('Gamma'));
    });

    test('Alpha has 4 points (2 wins)', () {
      final alpha = table.firstWhere((s) => s.teamName == 'Alpha');
      expect(alpha.points, equals(4));
      expect(alpha.won, equals(2));
      expect(alpha.played, equals(2));
    });

    test('Beta has 2 points (1 win, 1 loss)', () {
      final beta = table.firstWhere((s) => s.teamName == 'Beta');
      expect(beta.points, equals(2));
      expect(beta.won, equals(1));
      expect(beta.lost, equals(1));
    });

    test('Gamma has 0 points (2 losses)', () {
      final gamma = table.firstWhere((s) => s.teamName == 'Gamma');
      expect(gamma.points, equals(0));
      expect(gamma.won, equals(0));
      expect(gamma.lost, equals(2));
    });

    test('Alpha NRR is positive and highest', () {
      expect(table[0].nrr, greaterThan(0));
    });
  });

  // ── Descriptive winner string fallback ────────────────────────────────────
  group('Descriptive winner string fallback', () {
    test('Winner string "Alpha won by 5 runs" → Alpha gets 2 pts', () {
      final table = _buildTable(
        teams: ['Alpha', 'Beta'],
        completedMatches: [
          {
            'teamA': 'Alpha', 'teamB': 'Beta',
            'winner': 'Alpha won by 5 runs',
            'runsA': 160, 'wicketsA': 5, 'legalBallsA': 120,
            'runsB': 155, 'wicketsB': 10, 'legalBallsB': 115,
          },
        ],
        maxOvers: 20,
      );
      final alpha = table.firstWhere((s) => s.teamName == 'Alpha');
      final beta  = table.firstWhere((s) => s.teamName == 'Beta');
      expect(alpha.points, equals(2));
      expect(beta.points, equals(0));
    });

    test('Unrecognisable winner string → both teams get 1 pt (no result)', () {
      final table = _buildTable(
        teams: ['Alpha', 'Beta'],
        completedMatches: [
          {
            'teamA': 'Alpha', 'teamB': 'Beta',
            'winner': 'Unknown result',
            'runsA': 160, 'wicketsA': 5, 'legalBallsA': 120,
            'runsB': 155, 'wicketsB': 10, 'legalBallsB': 115,
          },
        ],
        maxOvers: 20,
      );
      expect(table[0].points, equals(1));
      expect(table[1].points, equals(1));
    });

    test('Null winner → both teams get 1 pt (no result)', () {
      final table = _buildTable(
        teams: ['Alpha', 'Beta'],
        completedMatches: [
          {
            'teamA': 'Alpha', 'teamB': 'Beta',
            'winner': null,
            'runsA': 160, 'wicketsA': 5, 'legalBallsA': 120,
            'runsB': 0, 'wicketsB': 0, 'legalBallsB': 0,
          },
        ],
        maxOvers: 20,
      );
      expect(table[0].noResult, equals(1));
      expect(table[1].noResult, equals(1));
    });
  });

  // ── NRR with all-out innings vs full-allocation innings ───────────────────
  group('NRR: all-out vs full-allocation overs', () {
    test('All-out team uses actual balls for NRR denominator', () {
      // Team scored fast (not all out) = full 20 overs
      // Opponent was all out in 15 overs (90 balls)
      final oversAllOut  = _legalBallsToOvers(90, 20, 10); // → 15.0
      final oversNotOut  = _legalBallsToOvers(80, 20, 4);  // → 20.0 (not all out)

      expect(oversAllOut, equals(15.0));
      expect(oversNotOut, equals(20.0));

      // NRR for the winning team:
      //   attack: 180/20 = 9.0
      //   defend: 140/15 ≈ 9.333
      //   NRR ≈ -0.333 (they bowled the opponent out cheaply but
      //            conceded a higher rate in fewer overs)
      final nrr = _calculateNrr(
        runsScored: 180,
        oversFaced: 20.0,
        runsConceded: 140,
        oversBowled: 15.0,
      );
      expect(nrr, closeTo(-0.333, 0.001));
    });

    test('5-over match: all-out in 3.4 overs = 22 balls', () {
      final overs = _legalBallsToOvers(22, 5, 10);
      expect(overs, closeTo(3.667, 0.001));
    });
  });

  // ── Sorting: equal points → NRR tiebreak ──────────────────────────────────
  group('Table sorting', () {
    test('Teams level on points: higher NRR ranked first', () {
      // Both Alpha and Beta each win one match.
      // Alpha wins big (+high NRR), Beta scrapes through (+low NRR).
      final table = _buildTable(
        teams: ['Alpha', 'Beta', 'Gamma', 'Delta'],
        completedMatches: [
          // Alpha crushes Gamma → high NRR for Alpha
          {
            'teamA': 'Alpha', 'teamB': 'Gamma', 'winner': 'Alpha',
            'runsA': 200, 'wicketsA': 3, 'legalBallsA': 120,
            'runsB': 80, 'wicketsB': 10, 'legalBallsB': 72,
          },
          // Beta narrowly beats Delta → low NRR for Beta
          {
            'teamA': 'Beta', 'teamB': 'Delta', 'winner': 'Beta',
            'runsA': 101, 'wicketsA': 6, 'legalBallsA': 120,
            'runsB': 100, 'wicketsB': 10, 'legalBallsB': 120,
          },
        ],
        maxOvers: 20,
      );
      // Both Alpha and Beta have 2 points.
      // Alpha should rank above Beta by NRR.
      final alphaIdx = table.indexWhere((s) => s.teamName == 'Alpha');
      final betaIdx  = table.indexWhere((s) => s.teamName == 'Beta');
      expect(alphaIdx, lessThan(betaIdx));
      expect(table[alphaIdx].nrr, greaterThan(table[betaIdx].nrr));
    });
  });
}
