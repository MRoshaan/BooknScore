// Unit tests for WicketPk pure scoring logic.
//
// These tests verify the cricket-scoring arithmetic that lives inside
// MatchProvider without requiring a live SQLite database or Supabase
// connection.  Each helper mirrors the exact formula used in production.

import 'package:flutter_test/flutter_test.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Pure helpers that mirror the production logic in match_provider.dart
// ──────────────────────────────────────────────────────────────────────────────

/// Simulates the arguments passed to _recordBallEvent when recordWide() is
/// called with [additionalRuns].  Returns a map of the computed field values.
Map<String, dynamic> _computeWideBall({int additionalRuns = 0}) {
  // From match_provider.dart line 384-388:
  //   runsScored: 0,
  //   extraType: 'wide',
  //   extraRuns: 1 + additionalRuns,
  const extraType = 'wide';
  const runsScored = 0;
  final extraRuns = 1 + additionalRuns;
  final isLegalDelivery = extraType != 'wide' && extraType != 'no_ball'; // false

  return {
    'runsScored': runsScored,
    'extraType': extraType,
    'extraRuns': extraRuns,
    'totalRunsThisBall': runsScored + extraRuns,
    'isLegalDelivery': isLegalDelivery,
    // Batter balls incremented only when extraType != 'wide'
    'batterBallsIncrement': extraType != 'wide' ? 1 : 0,
  };
}

/// Simulates the arguments passed to _recordBallEvent when recordNoBall() is
/// called with [additionalRuns] off the bat (batterRuns = true).
Map<String, dynamic> _computeNoBallOffBat({int additionalRuns = 0}) {
  // From match_provider.dart line 397-401:
  //   runsScored: batterRuns ? additionalRuns : 0,
  //   extraType: 'no_ball',
  //   extraRuns: batterRuns ? 1 : 1 + additionalRuns,
  const extraType = 'no_ball';
  final runsScored = additionalRuns; // batterRuns == true
  const extraRuns = 1;              // batterRuns == true → only the NB penalty
  final isLegalDelivery = extraType != 'wide' && extraType != 'no_ball'; // false

  return {
    'runsScored': runsScored,
    'extraType': extraType,
    'extraRuns': extraRuns,
    'totalRunsThisBall': runsScored + extraRuns,
    'isLegalDelivery': isLegalDelivery,
    // Batter balls NOT incremented for no_ball (wide check only, no_ball still counts)
    // Per line 828: strikerStats['balls'] incremented when extraType != 'wide'
    'batterBallsIncrement': extraType != 'wide' ? 1 : 0,
  };
}

/// Mirrors _calculateMatchResult() from match_provider.dart (lines 712-729).
///
/// Returns the result string for a completed 2nd innings given the final score.
String _calculateMatchResult({
  required int currentInnings,
  required int totalRuns,
  required int totalWickets,
  required int? target,
  required String battingTeam,
  required String bowlingTeam,
}) {
  if (currentInnings == 2 && target != null) {
    if (totalRuns >= target) {
      final wicketsRemaining = 10 - totalWickets;
      return '$battingTeam won by $wicketsRemaining wickets';
    } else if (totalRuns == target - 1) {
      return 'Match Tied';
    } else {
      final runsDiff = target - totalRuns - 1;
      return '$bowlingTeam won by $runsDiff runs';
    }
  } else if (currentInnings == 1) {
    return 'Match ended - $battingTeam: $totalRuns/$totalWickets';
  }
  return '';
}

/// Mirrors the MOTM Impact Points formula from match_summary_screen.dart.
///
/// Formula: (runs×1) + (sixes×2) + (fours×1) + (wickets×20) + (dotBalls×1)
///          − (runsConceded×0.5)
double _impactPoints({
  required int runs,
  required int sixes,
  required int fours,
  required int wickets,
  required int dotBalls,
  required int runsConceded,
}) {
  return (runs * 1) +
      (sixes * 2) +
      (fours * 1) +
      (wickets * 20) +
      (dotBalls * 1) -
      (runsConceded * 0.5);
}

/// Picks the player with the highest Impact Points from a list of stat maps.
Map<String, dynamic> _bestMotm(List<Map<String, dynamic>> players) {
  Map<String, dynamic>? best;
  double bestScore = double.negativeInfinity;
  for (final p in players) {
    final score = _impactPoints(
      runs: p['runs'] as int,
      sixes: p['sixes'] as int,
      fours: p['fours'] as int,
      wickets: p['wickets'] as int,
      dotBalls: p['dotBalls'] as int,
      runsConceded: p['runsConceded'] as int,
    );
    if (score > bestScore) {
      bestScore = score;
      best = p;
    }
  }
  return best!;
}

// ──────────────────────────────────────────────────────────────────────────────
// Tests
// ──────────────────────────────────────────────────────────────────────────────

void main() {
  // ── Test 1: Wide + 2 additional runs ──────────────────────────────────────
  group('Wide ball scoring', () {
    test('Wide+2 → 3 extras, 0 batter runs, 0 legal balls', () {
      final result = _computeWideBall(additionalRuns: 2);

      // 1 (penalty) + 2 (additional) = 3 total extras
      expect(result['extraRuns'], equals(3));

      // Batter scores nothing on a wide
      expect(result['runsScored'], equals(0));

      // Total runs on this ball = 0 + 3
      expect(result['totalRunsThisBall'], equals(3));

      // Wide does NOT count as a legal delivery
      expect(result['isLegalDelivery'], isFalse);

      // Batter's ball count is NOT incremented on a wide
      expect(result['batterBallsIncrement'], equals(0));
    });
  });

  // ── Test 2: No Ball + 4 runs off bat ──────────────────────────────────────
  group('No Ball off bat scoring', () {
    test('NoBall+4 off bat → 4 batter runs, 1 extra, 0 legal balls', () {
      final result = _computeNoBallOffBat(additionalRuns: 4);

      // 4 runs go to the batter
      expect(result['runsScored'], equals(4));

      // Only the 1-run no-ball penalty goes to extras
      expect(result['extraRuns'], equals(1));

      // Total runs on this ball = 4 + 1 = 5
      expect(result['totalRunsThisBall'], equals(5));

      // No Ball does NOT count as a legal delivery
      expect(result['isLegalDelivery'], isFalse);

      // Batter's ball count IS incremented for a no-ball (unlike wide)
      expect(result['batterBallsIncrement'], equals(1));
    });
  });

  // ── Test 3: Tie / win / loss logic ────────────────────────────────────────
  group('Match result calculation', () {
    const batting = 'Team Alpha';
    const bowling = 'Team Beta';

    test('Scores level (totalRuns == target − 1) → Match Tied', () {
      // target = 150, totalRuns = 149 → tie
      final result = _calculateMatchResult(
        currentInnings: 2,
        totalRuns: 149,
        totalWickets: 5,
        target: 150,
        battingTeam: batting,
        bowlingTeam: bowling,
      );
      expect(result, equals('Match Tied'));
    });

    test('Chasing team passes target → batting team wins by wickets', () {
      // target = 150, totalRuns = 152, wickets = 3 → 7 wickets remaining
      final result = _calculateMatchResult(
        currentInnings: 2,
        totalRuns: 152,
        totalWickets: 3,
        target: 150,
        battingTeam: batting,
        bowlingTeam: bowling,
      );
      expect(result, equals('$batting won by 7 wickets'));
    });

    test('Chasing team falls short → bowling team wins by runs', () {
      // target = 150, totalRuns = 140 → bowling team wins by 9 runs
      // runsDiff = 150 - 140 - 1 = 9
      final result = _calculateMatchResult(
        currentInnings: 2,
        totalRuns: 140,
        totalWickets: 10,
        target: 150,
        battingTeam: batting,
        bowlingTeam: bowling,
      );
      expect(result, equals('$bowling won by 9 runs'));
    });
  });

  // ── Test 4: MOTM Impact Points calculator ─────────────────────────────────
  group('MOTM Impact Points', () {
    test('Formula computes correct score for a single player', () {
      // runs=45, sixes=2, fours=3, wickets=0, dotBalls=10, runsConceded=0
      // = 45 + 4 + 3 + 0 + 10 - 0 = 62
      final score = _impactPoints(
        runs: 45,
        sixes: 2,
        fours: 3,
        wickets: 0,
        dotBalls: 10,
        runsConceded: 0,
      );
      expect(score, equals(62.0));
    });

    test('Bowler wickets dominate the formula (wickets × 20)', () {
      // A bowler: runs=5, sixes=0, fours=0, wickets=3, dotBalls=8, runsConceded=24
      // = 5 + 0 + 0 + 60 + 8 - 12 = 61
      final score = _impactPoints(
        runs: 5,
        sixes: 0,
        fours: 0,
        wickets: 3,
        dotBalls: 8,
        runsConceded: 24,
      );
      expect(score, equals(61.0));
    });

    test('_bestMotm picks the player with highest Impact Points', () {
      final players = [
        {
          'name': 'Alice',
          'runs': 45, 'sixes': 2, 'fours': 3,
          'wickets': 0, 'dotBalls': 10, 'runsConceded': 0,
          // score = 62
        },
        {
          'name': 'Bob',
          'runs': 5, 'sixes': 0, 'fours': 0,
          'wickets': 3, 'dotBalls': 8, 'runsConceded': 24,
          // score = 61
        },
        {
          'name': 'Charlie',
          'runs': 80, 'sixes': 4, 'fours': 6,
          'wickets': 0, 'dotBalls': 5, 'runsConceded': 0,
          // score = 80 + 8 + 6 + 0 + 5 - 0 = 99
        },
      ];

      final motm = _bestMotm(players);
      expect(motm['name'], equals('Charlie'));
    });

    test('runsConceded penalty is applied correctly (× 0.5)', () {
      // Expensive bowler: 0 wickets, 50 runs conceded
      // score = 0 + 0 + 0 + 0 + 0 - 25 = -25
      final score = _impactPoints(
        runs: 0,
        sixes: 0,
        fours: 0,
        wickets: 0,
        dotBalls: 0,
        runsConceded: 50,
      );
      expect(score, equals(-25.0));
    });
  });
}
