import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../services/auth_service.dart';

/// ChangeNotifier that manages cricket match state and scoring logic.
///
/// Handles:
/// - Total score, wickets, overs calculation
/// - Current run rate (CRR) and required run rate (RRR)
/// - Active batters (striker, non-striker) with live stats
/// - Current bowler with figures
/// - Strike rotation on odd runs and end of over
/// - End of over / end of innings logic
/// - Wicket -> new batter modal trigger
/// - Robust undo last ball functionality
class MatchProvider extends ChangeNotifier {
  // ── Current Match State ───────────────────────────────────────────────────
  int? _matchId;
  Map<String, dynamic>? _match;
  int _currentInnings = 1;
  
  // ── Innings State ─────────────────────────────────────────────────────────
  int _totalRuns = 0;
  int _totalWickets = 0;
  int _completedOvers = 0;
  int _ballsInCurrentOver = 0;
  int _extras = 0;
  int _fours = 0;
  int _sixes = 0;
  int? _target; // Target score for 2nd innings
  int? _firstInningsScore; // For reference in 2nd innings
  
  // ── Active Players ────────────────────────────────────────────────────────
  // For named player tracking, we store player IDs from database
  int? _strikerId;
  int? _nonStrikerId;
  int? _currentBowlerId;
  int? _previousBowlerId; // Can't bowl consecutive overs
  String? _previousBowlerName; // Name of the bowler who just finished, for UI rule enforcement

  // Player names (for display)
  String _strikerName = 'Batter 1';
  String _nonStrikerName = 'Batter 2';
  String _bowlerName = 'Bowler';
  
  // Batter stats (computed)
  Map<String, int> _strikerStats = {'runs': 0, 'balls': 0, 'fours': 0, 'sixes': 0};
  Map<String, int> _nonStrikerStats = {'runs': 0, 'balls': 0, 'fours': 0, 'sixes': 0};
  
  // Bowler stats (computed)
  Map<String, dynamic> _bowlerStats = {
    'overs': 0, 'balls': 0, 'maidens': 0, 'runs': 0, 'wickets': 0, 'economy': 0.0
  };
  
  // ── Current Over Balls ────────────────────────────────────────────────────
  List<BallEvent> _currentOverBalls = [];
  List<BallEvent> _allBallsThisInnings = [];
  
  // ── UI State Triggers ─────────────────────────────────────────────────────
  bool _needsOpeningPlayers = false;  // Trigger for initial batters + bowler
  bool _needsNewBatter = false;  // Trigger after wicket
  bool _needsNewBowler = false;  // Trigger at end of over
  bool _needsInningsChange = false; // Trigger when innings complete
  bool _matchEnded = false; // Match is complete
  String? _matchResult; // e.g., "Team A won by 5 wickets"
  
  // ── Processing State ──────────────────────────────────────────────────────
  bool _isLoading = false;
  bool _isProcessing = false;
  String? _error;
  
  // ── ICC Caught Rule flag ──────────────────────────────────────────────────
  // Set to true when a caught wicket falls on a ball that is NOT the last ball
  // of the over.  Consumed by setNewBatterWithName() to ensure the incoming
  // batter takes the strike (new batter always faces next ball on a catch,
  // unless the over just ended).
  bool _caughtNotLastBallOfOver = false;

  // ── Batting lineup tracking ───────────────────────────────────────────────
  int _nextBatterNumber = 3; // After opening pair (for unnamed fallback)

  // ══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ══════════════════════════════════════════════════════════════════════════

  int? get matchId => _matchId;
  Map<String, dynamic>? get match => _match;
  int get currentInnings => _currentInnings;
  
  // Score
  int get totalRuns => _totalRuns;
  int get totalWickets => _totalWickets;
  int get completedOvers => _completedOvers;
  int get ballsInCurrentOver => _ballsInCurrentOver;
  int get extras => _extras;
  int get fours => _fours;
  int get sixes => _sixes;
  int? get target => _target;
  int? get firstInningsScore => _firstInningsScore;
  
  // Formatted displays
  String get scoreDisplay => '$_totalRuns/$_totalWickets';
  
  String get oversDisplay {
    if (_ballsInCurrentOver == 0) return '$_completedOvers.0';
    return '$_completedOvers.$_ballsInCurrentOver';
  }
  
  int get totalOvers => _match?[DatabaseHelper.colTotalOvers] ?? 0;
  
  /// Number of players per side.  The wicket limit is [squadSize] - 1.
  int get squadSize => (_match?[DatabaseHelper.colSquadSize] as int?) ?? 11;
  
  String get teamA => _match?[DatabaseHelper.colTeamA] ?? 'Team A';
  String get teamB => _match?[DatabaseHelper.colTeamB] ?? 'Team B';
  String? get tournamentName => _match?[DatabaseHelper.colTournamentName];
  
  String get battingTeam {
    final tossWinner = _match?[DatabaseHelper.colTossWinner];
    final optTo = _match?[DatabaseHelper.colOptTo];
    
    if (tossWinner == null || optTo == null) {
      return _currentInnings == 1 ? teamA : teamB;
    }
    
    final tossWinnerBats = optTo == 'bat';
    if (_currentInnings == 1) {
      return tossWinnerBats ? tossWinner : (tossWinner == teamA ? teamB : teamA);
    } else {
      return tossWinnerBats ? (tossWinner == teamA ? teamB : teamA) : tossWinner;
    }
  }
  
  String get bowlingTeam => battingTeam == teamA ? teamB : teamA;
  
  /// Current run rate (runs per over)
  double get currentRunRate {
    final totalBalls = _completedOvers * 6 + _ballsInCurrentOver;
    if (totalBalls == 0) return 0.0;
    return (_totalRuns / totalBalls) * 6;
  }
  
  String get currentRunRateDisplay => currentRunRate.toStringAsFixed(2);
  
  /// Required run rate (only for 2nd innings)
  double get requiredRunRate {
    if (_currentInnings != 2 || _target == null) return 0.0;
    final runsNeeded = _target! - _totalRuns;
    if (runsNeeded <= 0) return 0.0;
    
    final totalBallsRemaining = (totalOvers * 6) - (_completedOvers * 6 + _ballsInCurrentOver);
    if (totalBallsRemaining <= 0) return double.infinity;
    
    return (runsNeeded / totalBallsRemaining) * 6;
  }
  
  String get requiredRunRateDisplay => requiredRunRate.toStringAsFixed(2);
  
  int get runsNeeded => (_target ?? 0) - _totalRuns;
  
  int get ballsRemaining {
    return (totalOvers * 6) - (_completedOvers * 6 + _ballsInCurrentOver);
  }
  
  // Active players
  int? get strikerId => _strikerId;
  int? get nonStrikerId => _nonStrikerId;
  int? get currentBowlerId => _currentBowlerId;
  int? get previousBowlerId => _previousBowlerId;
  /// The name of the bowler who bowled the immediately preceding over.
  /// Used to enforce the consecutive-over rule in the UI.
  String? get previousBowlerName => _previousBowlerName;
  
  String get strikerName => _strikerName;
  String get nonStrikerName => _nonStrikerName;
  String get bowlerName => _bowlerName;
  
  Map<String, int> get strikerStats => Map.unmodifiable(_strikerStats);
  Map<String, int> get nonStrikerStats => Map.unmodifiable(_nonStrikerStats);
  Map<String, dynamic> get bowlerStats => Map.unmodifiable(_bowlerStats);
  
  // Striker strike rate
  double get strikerStrikeRate {
    final balls = _strikerStats['balls'] ?? 0;
    if (balls == 0) return 0.0;
    return ((_strikerStats['runs'] ?? 0) / balls) * 100;
  }
  
  double get nonStrikerStrikeRate {
    final balls = _nonStrikerStats['balls'] ?? 0;
    if (balls == 0) return 0.0;
    return ((_nonStrikerStats['runs'] ?? 0) / balls) * 100;
  }
  
  // Current over display
  List<BallEvent> get currentOverBalls => List.unmodifiable(_currentOverBalls);
  List<BallEvent> get allBallsThisInnings => List.unmodifiable(_allBallsThisInnings);
  
  // UI State triggers
  bool get needsOpeningPlayers => _needsOpeningPlayers;
  bool get needsNewBatter => _needsNewBatter;
  bool get needsNewBowler => _needsNewBowler;
  bool get needsInningsChange => _needsInningsChange;
  bool get matchEnded => _matchEnded;
  String? get matchResult => _matchResult;
  
  // State
  bool get isLoading => _isLoading;
  bool get isProcessing => _isProcessing;
  String? get error => _error;
  
  /// True when the most recent wicket was a caught dismissal that did NOT fall
  /// on the last ball of the over.  The UI (new-batter modal) reads this so it
  /// can ensure the incoming batter takes the strike per the ICC rule.
  bool get caughtNotLastBallOfOver => _caughtNotLastBallOfOver;
  
  // Match status helpers
  bool get isInningsComplete {
    // All out (squadSize - 1 wickets) or all overs bowled
    if (_totalWickets >= squadSize - 1) return true;
    if (_completedOvers >= totalOvers && _ballsInCurrentOver == 0 && totalOvers > 0) return true;
    // 2nd innings: target achieved
    if (_currentInnings == 2 && _target != null && _totalRuns >= _target!) return true;
    return false;
  }
  
  bool get isMatchComplete {
    if (_currentInnings == 2 && isInningsComplete) return true;
    // Target achieved
    if (_currentInnings == 2 && _target != null && _totalRuns >= _target!) return true;
    return false;
  }
  
  String get matchStatus => _match?[DatabaseHelper.colStatus] ?? 'pending';

  // ══════════════════════════════════════════════════════════════════════════
  // PUBLIC METHODS
  // ══════════════════════════════════════════════════════════════════════════

  /// Update total_overs and/or squad_size mid-match (Tapeball Dynamics).
  /// Persists changes to SQLite and refreshes the in-memory match map so that
  /// all getters ([totalOvers], [squadSize]) reflect the new values immediately.
  Future<void> updateMatchSettings({int? newOvers, int? newSquadSize}) async {
    if (_matchId == null) return;
    final db = DatabaseHelper.instance;
    if (newOvers != null) {
      await db.updateMatchOvers(_matchId!, newOvers);
    }
    if (newSquadSize != null) {
      await db.updateMatchSquadSize(_matchId!, newSquadSize);
    }
    // Reload match row so getters pick up the new values
    _match = await db.fetchMatch(_matchId!);
    notifyListeners();
  }

  /// Load match and innings data from database.
  Future<void> loadMatch(int matchId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _matchId = matchId;
      _match = await DatabaseHelper.instance.fetchMatch(matchId);
      
      if (_match == null) {
        _error = 'Match not found';
        _isLoading = false;
        notifyListeners();
        return;
      }
      
      _currentInnings = _match![DatabaseHelper.colCurrentInnings] as int;
      _target = _match![DatabaseHelper.colTarget] as int?;
      
      // Load first innings score if in 2nd innings
      if (_currentInnings == 2 && _target == null) {
        final firstInningsSummary = await DatabaseHelper.instance.getInningsSummary(matchId, 1);
        _firstInningsScore = firstInningsSummary['totalRuns'];
        _target = _firstInningsScore! + 1;
      }
      
      await _refreshInningsState();

      // If the match was already completed, restore ended state
      if (_match![DatabaseHelper.colStatus] == 'completed') {
        _matchEnded = true;
        _calculateMatchResult();
      }
      
      // Check if we need opening players (no balls bowled yet in this innings)
      if (_allBallsThisInnings.isEmpty && !_matchEnded) {
        _needsOpeningPlayers = true;
        _strikerId = null;
        _nonStrikerId = null;
        _currentBowlerId = null;
      } else if (_allBallsThisInnings.isNotEmpty && !_matchEnded) {
        // Reconstruct active player state from the most recent ball in the DB.
        // This ensures that when an in-progress match is reopened, the UI shows
        // the correct current striker, non-striker, and bowler rather than
        // defaulting to the initial/opening players.
        final lastBall = _allBallsThisInnings.last;

        if (lastBall.strikerId != null) {
          _strikerId = lastBall.strikerId;
          final player = await DatabaseHelper.instance.fetchPlayer(lastBall.strikerId!);
          _strikerName = player?['name'] ?? 'Batter ${lastBall.strikerId}';
        }

        if (lastBall.nonStrikerId != null) {
          _nonStrikerId = lastBall.nonStrikerId;
          final player = await DatabaseHelper.instance.fetchPlayer(lastBall.nonStrikerId!);
          _nonStrikerName = player?['name'] ?? 'Batter ${lastBall.nonStrikerId}';
        }

        if (lastBall.bowlerId != null) {
          _currentBowlerId = lastBall.bowlerId;
          final player = await DatabaseHelper.instance.fetchPlayer(lastBall.bowlerId!);
          _bowlerName = player?['name'] ?? 'Bowler ${lastBall.bowlerId}';
        }

        // Restore the previous bowler (the one who bowled the over immediately
        // before the current one) so the consecutive-over restriction works
        // correctly after a match is reopened.
        //
        // Determine which over number was the last *completed* over:
        //   - If balls are in progress (_ballsInCurrentOver > 0), the current
        //     over is _completedOvers + 1, so the previous completed over is
        //     _completedOvers.
        //   - If we are between overs (_ballsInCurrentOver == 0 and
        //     _completedOvers > 0), the last completed over is _completedOvers
        //     and the new-bowler modal should be (or will be) shown for over
        //     _completedOvers + 1.
        //
        // In both cases, the "previous" bowler is whoever bowled over
        // _completedOvers (when _completedOvers > 0).
        if (_completedOvers > 0) {
          final prevOverBalls = await DatabaseHelper.instance.fetchCurrentOverBalls(
            _matchId!,
            _currentInnings,
            _completedOvers, // the last fully-completed over number
          );
          if (prevOverBalls.isNotEmpty) {
            final prevBowlerId = prevOverBalls.last[DatabaseHelper.colBowlerId] as int?;
            if (prevBowlerId != null) {
              _previousBowlerId = prevBowlerId;
              final prevPlayer = await DatabaseHelper.instance.fetchPlayer(prevBowlerId);
              _previousBowlerName = prevPlayer?['name'] ?? 'Bowler $prevBowlerId';
            }
          }
        }

        // FIX: Re-run stat calculations now that player IDs are populated.
        // _refreshInningsState() was called before the IDs were set above, so
        // _recalculateBatterStats / _recalculateBowlerStats silently returned
        // early (guarded by `_strikerId == null`).  Running them again here
        // populates the scoreboard immediately on match load instead of waiting
        // for the next ball to trigger a refresh.
        await _recalculateBatterStats();
        await _recalculateBowlerStats();
      }
      
      _isLoading = false;
      notifyListeners();
    } catch (e, st) {
      developer.log(
        'loadMatch failed for matchId=$matchId',
        name: 'MatchProvider',
        error: e,
        stackTrace: st,
        level: 1000,
      );
      _error = 'Failed to load match. Please try again.';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Set the opening players for an innings (striker, non-striker, bowler)
  /// Called from UI after getting player names
  Future<void> setOpeningPlayers({
    required String strikerName,
    required String nonStrikerName,
    required String bowlerName,
  }) async {
    if (_matchId == null) return;
    
    final userId = AuthService.instance.currentUser?.id;
    final db = DatabaseHelper.instance;
    
    try {
      // Reuse existing player records where possible so that a player who
      // appeared in a previous match (or was set as the opening bowler and
      // later recalled for a non-consecutive over) always gets the same DB id.
      // Without this, a second insertPlayer call creates a new row with a
      // different id, causing the scorecard to show duplicate bowling rows.
      final strikerId =
          await db.findPlayerIdByNameAndTeam(strikerName, battingTeam) ??
          await db.insertPlayer(
            name: strikerName,
            team: battingTeam,
            role: 'batter',
            createdBy: userId,
          );

      final nonStrikerId =
          await db.findPlayerIdByNameAndTeam(nonStrikerName, battingTeam) ??
          await db.insertPlayer(
            name: nonStrikerName,
            team: battingTeam,
            role: 'batter',
            createdBy: userId,
          );

      final bowlerId =
          await db.findPlayerIdByNameAndTeam(bowlerName, bowlingTeam) ??
          await db.insertPlayer(
            name: bowlerName,
            team: bowlingTeam,
            role: 'bowler',
            createdBy: userId,
          );
      
      // Add players to match
      await db.addPlayerToMatch(
        matchId: _matchId!,
        playerId: strikerId,
        team: battingTeam == teamA ? 'team_a' : 'team_b',
        battingOrder: 1,
        createdBy: userId,
      );
      
      await db.addPlayerToMatch(
        matchId: _matchId!,
        playerId: nonStrikerId,
        team: battingTeam == teamA ? 'team_a' : 'team_b',
        battingOrder: 2,
        createdBy: userId,
      );
      
      await db.addPlayerToMatch(
        matchId: _matchId!,
        playerId: bowlerId,
        team: bowlingTeam == teamA ? 'team_a' : 'team_b',
        createdBy: userId,
      );
      
      // Set local state
      _strikerId = strikerId;
      _nonStrikerId = nonStrikerId;
      _currentBowlerId = bowlerId;
      _strikerName = strikerName;
      _nonStrikerName = nonStrikerName;
      _bowlerName = bowlerName;
      _strikerStats = {'runs': 0, 'balls': 0, 'fours': 0, 'sixes': 0};
      _nonStrikerStats = {'runs': 0, 'balls': 0, 'fours': 0, 'sixes': 0};
      _bowlerStats = {'overs': 0, 'balls': 0, 'maidens': 0, 'runs': 0, 'wickets': 0, 'economy': 0.0};
      _nextBatterNumber = 3;
      
      _needsOpeningPlayers = false;
      notifyListeners();
    } catch (e, st) {
      developer.log(
        'setOpeningPlayers failed',
        name: 'MatchProvider',
        error: e,
        stackTrace: st,
        level: 1000,
      );
      _error = 'Failed to set opening players. Please try again.';
      notifyListeners();
    }
  }

  /// Record a run scoring event (0-6 runs).
  Future<void> recordRuns(int runs, {bool isBoundary = false}) async {
    if (_isProcessing || _matchId == null) return;
    if (_needsNewBatter || _needsNewBowler || _needsOpeningPlayers) return;
    
    // Auto-detect boundaries
    if (runs == 4 || runs == 6) isBoundary = true;
    
    await _recordBallEvent(
      runsScored: runs,
      isBoundary: isBoundary,
    );
  }

  /// Record a wicket.
  ///
  /// For run-outs, [extraType] may be 'bye' or 'leg_bye' and [extraRuns] > 0
  /// to record any runs completed before the wicket.  For off-bat run-outs,
  /// pass [runsScored] instead.
  Future<void> recordWicket({
    String wicketType = 'bowled',
    int runsScored = 0,
    String? extraType,
    int extraRuns = 0,
  }) async {
    if (_isProcessing || _matchId == null) return;
    if (_needsNewBatter || _needsNewBowler || _needsOpeningPlayers) return;

    await _recordBallEvent(
      runsScored: runsScored,
      isWicket: true,
      wicketType: wicketType,
      extraType: extraType,
      extraRuns: extraRuns,
    );
  }

  /// Record a wide (1 run + additional, doesn't count as legal delivery).
  Future<void> recordWide({int additionalRuns = 0}) async {
    if (_isProcessing || _matchId == null) return;
    if (_needsNewBatter || _needsNewBowler || _needsOpeningPlayers) return;
    
    await _recordBallEvent(
      runsScored: 0,
      extraType: 'wide',
      extraRuns: 1 + additionalRuns,
    );
  }

  /// Record a no ball (1 run + additional, doesn't count as legal delivery).
  Future<void> recordNoBall({int additionalRuns = 0, bool batterRuns = false}) async {
    if (_isProcessing || _matchId == null) return;
    if (_needsNewBatter || _needsNewBowler || _needsOpeningPlayers) return;
    
    // If batter hits it, runs go to batter, otherwise extras
    await _recordBallEvent(
      runsScored: batterRuns ? additionalRuns : 0,
      extraType: 'no_ball',
      extraRuns: batterRuns ? 1 : 1 + additionalRuns,
    );
  }

  /// Record a bye (runs don't count to batsman, but ball is legal).
  Future<void> recordBye(int runs) async {
    if (_isProcessing || _matchId == null) return;
    if (_needsNewBatter || _needsNewBowler || _needsOpeningPlayers) return;
    
    await _recordBallEvent(
      runsScored: 0,
      extraType: 'bye',
      extraRuns: runs,
    );
  }

  /// Record a leg bye (runs don't count to batsman, but ball is legal).
  Future<void> recordLegBye(int runs) async {
    if (_isProcessing || _matchId == null) return;
    if (_needsNewBatter || _needsNewBowler || _needsOpeningPlayers) return;
    
    await _recordBallEvent(
      runsScored: 0,
      extraType: 'leg_bye',
      extraRuns: runs,
    );
  }

  /// Swap striker and non-striker.
  void swapStrike() {
    final tempId = _strikerId;
    final tempName = _strikerName;
    final tempStats = Map<String, int>.from(_strikerStats);
    
    _strikerId = _nonStrikerId;
    _strikerName = _nonStrikerName;
    _strikerStats = Map<String, int>.from(_nonStrikerStats);
    
    _nonStrikerId = tempId;
    _nonStrikerName = tempName;
    _nonStrikerStats = tempStats;
    
    notifyListeners();
  }

  /// Set new bowler with name (called from end-of-over modal).
  Future<void> setNewBowlerWithName(String bowlerName) async {
    if (_matchId == null) return;
    
    final userId = AuthService.instance.currentUser?.id;
    final db = DatabaseHelper.instance;
    
    try {
      // Reuse the existing player record if this bowler has already been
      // registered under the same name and team in this match (or any prior
      // match). This prevents duplicate scorecard rows when the same bowler
      // comes back to bowl a non-consecutive over.
      int bowlerId =
          await db.findPlayerIdByNameAndTeam(bowlerName, bowlingTeam) ??
          await db.insertPlayer(
            name: bowlerName,
            team: bowlingTeam,
            role: 'bowler',
            createdBy: userId,
          );
      
      // Add to match if not already there
      await db.addPlayerToMatch(
        matchId: _matchId!,
        playerId: bowlerId,
        team: bowlingTeam == teamA ? 'team_a' : 'team_b',
        createdBy: userId,
      );
      
      // _previousBowlerId/_previousBowlerName were already snapshotted at
      // over-end time (inside _recordBallEvent), so we only update the current
      // bowler here.
      _currentBowlerId = bowlerId;
      _bowlerName = bowlerName;
      _needsNewBowler = false;
      _bowlerStats = {'overs': 0, 'balls': 0, 'maidens': 0, 'runs': 0, 'wickets': 0, 'economy': 0.0};
      
      notifyListeners();
    } catch (e, st) {
      developer.log(
        'setNewBowlerWithName failed',
        name: 'MatchProvider',
        error: e,
        stackTrace: st,
        level: 1000,
      );
      _error = 'Failed to set bowler. Please try again.';
      notifyListeners();
    }
  }

  /// Set new batter with name (called from wicket modal).
  Future<void> setNewBatterWithName(String batterName) async {
    if (_matchId == null) return;
    
    final userId = AuthService.instance.currentUser?.id;
    final db = DatabaseHelper.instance;
    
    try {
      // Reuse existing player record if the same batter re-enters (e.g. retired
      // hurt scenario or data-entry correction) to prevent duplicate batting rows.
      final batterId =
          await db.findPlayerIdByNameAndTeam(batterName, battingTeam) ??
          await db.insertPlayer(
            name: batterName,
            team: battingTeam,
            role: 'batter',
            createdBy: userId,
          );
      
      // Add to match
      await db.addPlayerToMatch(
        matchId: _matchId!,
        playerId: batterId,
        team: battingTeam == teamA ? 'team_a' : 'team_b',
        battingOrder: _nextBatterNumber,
        createdBy: userId,
      );
      
      // New batter comes in as striker (replacing the out batter).
      // ICC Caught Rule: the incoming batter always takes the strike, regardless
      // of whether the batters had crossed before the catch.  The flag
      // _caughtNotLastBallOfOver was set by _recordBallEvent; if it is true the
      // non-striker is the surviving batter who crossed and is currently sitting
      // at _strikerId's end — we need to swap before placing the new batter so
      // the survivor moves to non-striker and the new batter faces next ball.
      if (_caughtNotLastBallOfOver) {
        // Survivor is currently stored as _nonStrikerId (they were non-striker
        // when the ball was bowled).  Strike rotation from the catch delivery
        // may have swapped them already.  The new batter must be the next striker.
        // Simply placing batterId into _strikerId is enough since _strikerId is
        // who faces the next ball.
      }
      _caughtNotLastBallOfOver = false; // consume the flag

      _strikerId = batterId;
      _strikerName = batterName;
      _strikerStats = {'runs': 0, 'balls': 0, 'fours': 0, 'sixes': 0};
      _nextBatterNumber++;
      _needsNewBatter = false;
      
      notifyListeners();
    } catch (e, st) {
      developer.log(
        'setNewBatterWithName failed',
        name: 'MatchProvider',
        error: e,
        stackTrace: st,
        level: 1000,
      );
      _error = 'Failed to set batter. Please try again.';
      notifyListeners();
    }
  }

  /// Legacy: Set new bowler by ID (for backwards compatibility)
  void setNewBowler(int bowlerId, String bowlerName) {
    // _previousBowlerId/_previousBowlerName were already snapshotted at
    // over-end time (inside _recordBallEvent), so we only update the current
    // bowler here.
    _currentBowlerId = bowlerId;
    _bowlerName = bowlerName;
    _needsNewBowler = false;
    _bowlerStats = {'overs': 0, 'balls': 0, 'maidens': 0, 'runs': 0, 'wickets': 0, 'economy': 0.0};
    notifyListeners();
  }

  /// Legacy: Set new batter by ID (for backwards compatibility)
  void setNewBatter(int batterId, String batterName) {
    _strikerId = batterId;
    _strikerName = batterName;
    _strikerStats = {'runs': 0, 'balls': 0, 'fours': 0, 'sixes': 0};
    _needsNewBatter = false;
    notifyListeners();
  }

  /// Bring in next unnamed batter automatically.
  void bringNextBatter() {
    _strikerId = _nextBatterNumber;
    _strikerName = 'Batter $_nextBatterNumber';
    _strikerStats = {'runs': 0, 'balls': 0, 'fours': 0, 'sixes': 0};
    _nextBatterNumber++;
    _needsNewBatter = false;
    notifyListeners();
  }

  /// Select bowler for new over (unnamed).
  void selectBowlerForOver(int bowlerNum) {
    if (bowlerNum == _previousBowlerId) return; // Can't bowl consecutive overs
    // _previousBowlerId/_previousBowlerName were already snapshotted at
    // over-end time (inside _recordBallEvent), so we only update the current
    // bowler here.
    _currentBowlerId = bowlerNum;
    _bowlerName = 'Bowler $bowlerNum';
    _needsNewBowler = false;
    notifyListeners();
  }

  /// Robust undo of the last ball event.
  /// This properly reverses:
  /// - Team score (runs + extras)
  /// - Individual batter stats
  /// - Bowler stats
  /// - Wicket count
  /// - Ball/over count
  /// - Strike rotation (if needed)
  Future<void> undoLastBall() async {
    if (_isProcessing || _matchId == null) return;
    if (_allBallsThisInnings.isEmpty) return;
    
    _isProcessing = true;
    notifyListeners();

    try {
      // Get the last ball event before deleting
      final lastBall = _allBallsThisInnings.last;
      
      // Delete from database
      await DatabaseHelper.instance.deleteLastBallEvent(_matchId!, _currentInnings);
      
      // Reset any pending modals since we're undoing
      _needsNewBatter = false;
      _needsNewBowler = false;
      _needsInningsChange = false;
      
      // Reload state from database (clean slate)
      await _refreshInningsState();
      
      // Restore player context after undo
      // If we undid a wicket, the out batter is back
      if (lastBall.isWicket && lastBall.strikerId != null) {
        // Find if we still have that batter in events (was already batting)
        final stillExists = _allBallsThisInnings.any((b) => 
          b.strikerId == lastBall.strikerId && !b.isWicket
        );
        
        if (stillExists || _allBallsThisInnings.isEmpty) {
          // Restore the out batter as striker
          _strikerId = lastBall.strikerId;
          final player = await DatabaseHelper.instance.fetchPlayer(lastBall.strikerId!);
          _strikerName = player?['name'] ?? 'Batter ${lastBall.strikerId}';
        }
      }
      
      // Restore non-striker if needed
      if (lastBall.nonStrikerId != null && _nonStrikerId == null) {
        _nonStrikerId = lastBall.nonStrikerId;
        final player = await DatabaseHelper.instance.fetchPlayer(lastBall.nonStrikerId!);
        _nonStrikerName = player?['name'] ?? 'Batter ${lastBall.nonStrikerId}';
      }
      
      // Restore bowler if needed
      if (lastBall.bowlerId != null && _currentBowlerId == null) {
        _currentBowlerId = lastBall.bowlerId;
        final player = await DatabaseHelper.instance.fetchPlayer(lastBall.bowlerId!);
        _bowlerName = player?['name'] ?? 'Bowler ${lastBall.bowlerId}';
      }
      
      // Handle strike rotation reversal
      // Use the same physical-runs logic as _recordBallEvent.
      final int runsForStrikeRotation;
      if (lastBall.extraType == 'no_ball') {
        runsForStrikeRotation = lastBall.runsScored; // ignore NB penalty
      } else if (lastBall.extraType == 'wide') {
        runsForStrikeRotation = lastBall.extraRuns - 1; // physical runs only
      } else {
        runsForStrikeRotation = lastBall.runsScored + lastBall.extraRuns;
      }
      final wasLegalDelivery = lastBall.extraType != 'wide' && lastBall.extraType != 'no_ball';

      // Detect whether the undone ball was the last delivery of its over.
      // Use lastBall.ballNum (the DB-stored legal-ball-in-over count, 1–6)
      // rather than re-counting from the already-rebuilt _allBallsThisInnings,
      // which no longer contains the deleted ball.
      final wasLastBallOfOver = wasLegalDelivery && lastBall.ballNum == 6;

      // Determine whether a run-based rotation occurred on that ball.
      final shouldHaveRotated = runsForStrikeRotation % 2 == 1;

      // Each independent rotation flips the strike once; XOR the two triggers
      // so that a 1-run end-of-over (two flips → net zero) does NOT swap,
      // while a 0-run end-of-over (one flip) or a mid-over odd-run (one flip)
      // each produce exactly one swap.
      final needsSwap = shouldHaveRotated ^ wasLastBallOfOver;

      if (needsSwap) {
        swapStrike();
      }
      
      // Recalculate stats
      await _recalculateBatterStats();
      await _recalculateBowlerStats();
      
    } catch (e, st) {
      developer.log(
        'undoLastBall failed',
        name: 'MatchProvider',
        error: e,
        stackTrace: st,
        level: 1000,
      );
      _error = 'Failed to undo. Please try again.';
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// End current innings and start second innings.
  Future<void> endInnings() async {
    if (_currentInnings >= 2 || _matchId == null) return;
    
    _isProcessing = true;
    notifyListeners();

    try {
      // Save first innings score as target
      _firstInningsScore = _totalRuns;
      _target = _totalRuns + 1;
      await DatabaseHelper.instance.setTarget(_matchId!, _target!);
      
      _currentInnings = 2;
      await DatabaseHelper.instance.updateCurrentInnings(_matchId!, 2);
      
      // Reset state for new innings
      _needsInningsChange = false;
      _needsNewBatter = false;
      _needsNewBowler = false;
      _strikerId = null;
      _nonStrikerId = null;
      _currentBowlerId = null;
      _previousBowlerId = null;
      _previousBowlerName = null;
      
      await _refreshInningsState();
      
      // Need to set opening players for 2nd innings
      _needsOpeningPlayers = true;
      
    } catch (e, st) {
      developer.log(
        'endInnings failed',
        name: 'MatchProvider',
        error: e,
        stackTrace: st,
        level: 1000,
      );
      _error = 'Failed to end innings. Please try again.';
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// Complete the match.
  Future<void> completeMatch() async {
    if (_matchId == null) return;
    
    _isProcessing = true;
    notifyListeners();

    try {
      await DatabaseHelper.instance.updateMatchStatus(_matchId!, 'completed');
      _match = await DatabaseHelper.instance.fetchMatch(_matchId!);
      _matchEnded = true;
      _calculateMatchResult();

      // Persist the winner string to SQLite so it is included in the next
      // sync payload.  _matchResult is guaranteed non-null after
      // _calculateMatchResult() when the match has ended.
      if (_matchResult != null) {
        await DatabaseHelper.instance.updateMatchWinner(_matchId!, _matchResult!);
        // Re-fetch so _match reflects the persisted winner.
        _match = await DatabaseHelper.instance.fetchMatch(_matchId!);
      }

      // ── Compute and persist MOTM ──────────────────────────────────────────
      // This must happen before syncAll() so that the sync payload includes
      // the motm_player_id.  We use the same impact-point formula as the
      // match summary screen to keep results consistent.
      await _computeAndPersistMotm();

      // ── Knockout elimination + tournament completion ───────────────────────
      // Only process if this match belongs to a tournament and has a stage.
      await _handleKnockoutCompletion();

      // Sync immediately — match completion is a critical event, so we bypass
      // the debounce and push straight away.
      SyncService.instance.syncAll();
    } catch (e, st) {
      developer.log(
        'completeMatch failed',
        name: 'MatchProvider',
        error: e,
        stackTrace: st,
        level: 1000,
      );
      _error = 'Failed to complete match. Please try again.';
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// Compute the Man of the Match using the same impact-point formula as the
  /// match summary screen, then persist the winning player's id to SQLite.
  Future<void> _computeAndPersistMotm() async {
    if (_matchId == null) return;

    try {
      // Fetch all ball events for the entire match (both innings).
      final allEvents = await DatabaseHelper.instance.fetchBallEvents(_matchId!);

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

        if (strikerId != null) {
          batting.putIfAbsent(strikerId, () =>
              {'runs': 0, 'fours': 0, 'sixes': 0});
          final b = batting[strikerId]!;
          if (extraType != 'bye' && extraType != 'leg_bye') {
            b['runs'] = b['runs']! + runsScored;
          }
          if (isBoundary && runsScored == 4) b['fours'] = b['fours']! + 1;
          if (isBoundary && runsScored == 6) b['sixes'] = b['sixes']! + 1;
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
        final b  = batting[pid]  ?? {'runs': 0, 'fours': 0, 'sixes': 0};
        final bw = bowling[pid]  ?? {'wickets': 0, 'runsConceded': 0};

        final double impact =
            (b['runs']!          * 1.0)  +
            (b['sixes']!         * 2.0)  +
            (b['fours']!         * 1.0)  +
            (bw['wickets']!      * 20.0) -
            (bw['runsConceded']! * 0.5);

        if (impact > bestImpact) {
          bestImpact = impact;
          motmId = pid;
        }
      }

      if (motmId != null) {
        await DatabaseHelper.instance.updateMatchMotm(_matchId!, motmId);
        // Re-fetch match so _match always reflects the latest persisted state.
        _match = await DatabaseHelper.instance.fetchMatch(_matchId!);
      }
    } catch (e, st) {
      // MOTM persistence is non-critical; log and continue.
      developer.log(
        '_computeAndPersistMotm failed',
        name: 'MatchProvider',
        error: e,
        stackTrace: st,
        level: 800,
      );
    }
  }

  /// Handle knockout elimination and tournament completion when a match ends.
  ///
  /// Knockout stages: 'Quarter-Final', 'Semi-Final' → eliminate the loser.
  /// 'Final' → eliminate the loser AND complete the tournament with the winner.
  ///
  /// No-ops if:
  ///  - the match has no tournament_id
  ///  - match_stage is null or not a knockout stage
  ///  - _matchResult could not be determined
  Future<void> _handleKnockoutCompletion() async {
    if (_matchId == null || _match == null) return;

    final tournamentId = _match![DatabaseHelper.colTournamentId] as int?;
    final stage        = _match![DatabaseHelper.colMatchStage]   as String?;

    if (tournamentId == null || stage == null) return;

    const knockoutStages = {'Quarter-Final', 'Semi-Final', 'Final'};
    if (!knockoutStages.contains(stage)) return;

    // Determine winner and loser from _matchResult.
    // _matchResult is a string like "TeamA won by X runs" or "TeamA won by X wickets".
    final teamA = _match![DatabaseHelper.colTeamA] as String? ?? '';
    final teamB = _match![DatabaseHelper.colTeamB] as String? ?? '';

    String? winner;
    String? loser;

    if (_matchResult != null) {
      final resultLower = _matchResult!.toLowerCase();
      final aLower = teamA.toLowerCase();
      final bLower = teamB.toLowerCase();

      if (resultLower.contains(aLower) &&
          !resultLower.toLowerCase().startsWith('draw') &&
          !resultLower.toLowerCase().startsWith('match ended')) {
        winner = teamA;
        loser  = teamB;
      } else if (resultLower.contains(bLower) &&
          !resultLower.toLowerCase().startsWith('draw') &&
          !resultLower.toLowerCase().startsWith('match ended')) {
        winner = teamB;
        loser  = teamA;
      }
    }

    try {
      if (loser != null) {
        await DatabaseHelper.instance.eliminateTeam(tournamentId, loser);
      }

      if (stage == 'Final' && winner != null) {
        await DatabaseHelper.instance
            .completeTournamentWithWinner(tournamentId, winner);
      }
    } catch (e, st) {
      developer.log(
        '_handleKnockoutCompletion failed',
        name: 'MatchProvider',
        error: e,
        stackTrace: st,
        level: 800,
      );
    }
  }

  void _calculateMatchResult() {
    if (_currentInnings == 2 && _target != null) {
      if (_totalRuns >= _target!) {
        // Batting team won by chasing the target
        final wicketsRemaining = (squadSize - 1) - _totalWickets;
        _matchResult = '$battingTeam won by $wicketsRemaining wickets';
      } else if (_totalRuns == _target! - 1) {
        // Scores level — match is a draw
        _matchResult = 'Draw';
      } else {
        // Bowling team (1st innings team) won
        final runsDiff = _target! - _totalRuns - 1;
        _matchResult = '$bowlingTeam won by $runsDiff runs';
      }
    } else if (_currentInnings == 1) {
      _matchResult = 'Match ended - $battingTeam: $_totalRuns/$_totalWickets';
    }
  }

  /// Clear provider state (call when leaving scoring screen).
  void clearMatch() {
    _matchId = null;
    _match = null;
    _currentInnings = 1;
    _totalRuns = 0;
    _totalWickets = 0;
    _completedOvers = 0;
    _ballsInCurrentOver = 0;
    _extras = 0;
    _fours = 0;
    _sixes = 0;
    _target = null;
    _firstInningsScore = null;
    _strikerId = null;
    _nonStrikerId = null;
    _currentBowlerId = null;
    _previousBowlerId = null;
    _previousBowlerName = null;
    _strikerName = 'Batter 1';
    _nonStrikerName = 'Batter 2';
    _bowlerName = 'Bowler';
    _strikerStats = {'runs': 0, 'balls': 0, 'fours': 0, 'sixes': 0};
    _nonStrikerStats = {'runs': 0, 'balls': 0, 'fours': 0, 'sixes': 0};
    _bowlerStats = {'overs': 0, 'balls': 0, 'maidens': 0, 'runs': 0, 'wickets': 0, 'economy': 0.0};
    _currentOverBalls = [];
    _allBallsThisInnings = [];
    _needsOpeningPlayers = false;
    _needsNewBatter = false;
    _needsNewBowler = false;
    _needsInningsChange = false;
    _matchEnded = false;
    _matchResult = null;
    _nextBatterNumber = 3;
    _caughtNotLastBallOfOver = false;
    _isLoading = false;
    _isProcessing = false;
    _error = null;
    notifyListeners();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PRIVATE METHODS
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _recordBallEvent({
    required int runsScored,
    bool isBoundary = false,
    bool isWicket = false,
    String? wicketType,
    String? extraType,
    int extraRuns = 0,
  }) async {
    _isProcessing = true;
    notifyListeners();

    try {
      // Calculate over/ball number
      // For extras (wide/no_ball), ball doesn't increment
      final isLegalDelivery = extraType != 'wide' && extraType != 'no_ball';
      
      final overNum = _completedOvers + 1;
      final ballNum = isLegalDelivery 
          ? _ballsInCurrentOver + 1 
          : _ballsInCurrentOver; // Extras don't count

      final userId = AuthService.instance.currentUser?.id;
      
      await DatabaseHelper.instance.insertBallEvent(
        matchId:      _matchId!,
        innings:      _currentInnings,
        overNum:      overNum,
        ballNum:      ballNum,
        runsScored:   runsScored,
        isBoundary:   isBoundary,
        isWicket:     isWicket,
        wicketType:   wicketType,
        extraType:    extraType,
        extraRuns:    extraRuns,
        strikerId:    _strikerId,
        nonStrikerId: _nonStrikerId,
        bowlerId:     _currentBowlerId,
        outPlayerId:  isWicket ? _strikerId : null,
        createdBy:    userId,
      );

      // Update match status to live on first ball
      if (_completedOvers == 0 && _ballsInCurrentOver == 0 && matchStatus == 'pending') {
        await DatabaseHelper.instance.updateMatchStatus(_matchId!, 'live');
        _match = await DatabaseHelper.instance.fetchMatch(_matchId!);
      }

      // Calculate runs that physically count for strike rotation.
      //
      // No Ball: the mandatory +1 penalty run (always in extraRuns) is awarded
      //   to the batting side without the batters running — exclude it.
      //   Only runsScored (off-bat runs) and any additional byes/legbyes
      //   encoded in extraRuns beyond the NB penalty contribute.
      //   Simplification: treat NB runs-for-rotation as runsScored only.
      //
      // Wide: batters CAN physically run on a wide (e.g. Wide + 3).
      //   The total extra_runs for a wide = 1 (penalty) + additional runs.
      //   Physical runs taken = extraRuns - 1 (subtracting the penalty).
      //   If that is odd, strike rotates.
      //
      // Bye / Leg Bye / normal: every run is a physical run; count all.
      final int runsForStrikeRotation;
      if (extraType == 'no_ball') {
        runsForStrikeRotation = runsScored; // ignore the NB penalty in extraRuns
      } else if (extraType == 'wide') {
        // extraRuns includes 1 penalty + any additional run(s) batters actually ran
        runsForStrikeRotation = extraRuns - 1; // physical runs only
      } else {
        runsForStrikeRotation = runsScored + extraRuns;
      }

      // Check if this ball ends the over
      final newBallsInOver = isLegalDelivery ? _ballsInCurrentOver + 1 : _ballsInCurrentOver;
      final overComplete = newBallsInOver >= 6 && isLegalDelivery;

      // ICC Caught rule: new batter always takes strike, regardless of whether
      // the batters had crossed.  The only exception is if the catch occurs on
      // the last ball of an over — in that case the new-batter-takes-strike rule
      // is moot because end-of-over rotation happens anyway and the new bowler
      // comes from the other end.  We signal this via a flag so that
      // setNewBatterWithName knows NOT to swap strike after placing the new batter.
      final isCaughtWicket = isWicket && wicketType == 'caught';
      // Store whether this wicket happened on the last ball of the over, so the
      // new-batter-takes-strike ICC rule can be applied correctly in the UI.
      // We expose this as _caughtOnLastBall for the next setNewBatterWithName call.
      if (isCaughtWicket) {
        _caughtNotLastBallOfOver = !overComplete;
      } else {
        _caughtNotLastBallOfOver = false;
      }

      // Handle strike rotation
      // Rotate on: odd physical runs (wides now included if odd physical runs).
      // Also rotate at end of over.
      // Net effect: odd runs at end of over = no net rotation.
      final shouldRotate = runsForStrikeRotation % 2 == 1;

      if (shouldRotate && !overComplete) {
        swapStrike();
      } else if (overComplete && !shouldRotate) {
        swapStrike();
      }
      // If both shouldRotate AND overComplete, they cancel out

      await _refreshInningsState();
      
      // ── Handle post-ball events ──────────────────────────────────────────
      
      // Wicket: need new batter (unless all out)
      if (isWicket && _totalWickets < squadSize - 1) {
        _needsNewBatter = true;
      }
      
      // End of over: need new bowler.
      // Snapshot the just-finished bowler as "previous" NOW, while we still
      // know who bowled this over.  The modal validator reads previousBowlerName
      // to enforce the consecutive-over rule, so it must reflect the bowler who
      // just completed the over — not whoever was "previous" before this over.
      if (overComplete && _completedOvers < totalOvers) {
        _previousBowlerId = _currentBowlerId;
        _previousBowlerName = _bowlerName;
        _needsNewBowler = true;
      }
      
      // Check for innings completion
      if (isInningsComplete) {
        if (_currentInnings == 1) {
          _needsInningsChange = true;
        } else {
          // Match complete
          await completeMatch();
        }
      }

      // Schedule a debounced background sync after each ball.
      // Multiple rapid calls (e.g., fast scoring) are collapsed into a single
      // network request after a 5-second quiet period — battery efficient.
      SyncService.instance.scheduleDebouncedSync();
    } catch (e, st) {
      developer.log(
        '_recordBallEvent failed',
        name: 'MatchProvider',
        error: e,
        stackTrace: st,
        level: 1000,
      );
      _error = 'Failed to record ball. Please try again.';
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  Future<void> _refreshInningsState() async {
    if (_matchId == null) return;

    final summary = await DatabaseHelper.instance.getInningsSummary(
      _matchId!,
      _currentInnings,
    );

    _totalRuns = summary['totalRuns'] ?? 0;
    _totalWickets = summary['totalWickets'] ?? 0;
    _completedOvers = summary['completedOvers'] ?? 0;
    _ballsInCurrentOver = summary['ballsInOver'] ?? 0;
    _extras = summary['extras'] ?? 0;
    _fours = summary['fours'] ?? 0;
    _sixes = summary['sixes'] ?? 0;

    // Fetch current over balls for display
    await _loadCurrentOverBalls();
    await _loadAllBallsThisInnings();
    
    // Recalculate batter stats from events if we have player IDs
    await _recalculateBatterStats();
    await _recalculateBowlerStats();
  }

  Future<void> _loadCurrentOverBalls() async {
    if (_matchId == null) return;

    final currentOverNum = _completedOvers + 1;
    final events = await DatabaseHelper.instance.fetchCurrentOverBalls(
      _matchId!,
      _currentInnings,
      currentOverNum,
    );

    _currentOverBalls = events.map((e) => BallEvent.fromMap(e)).toList();
  }

  Future<void> _loadAllBallsThisInnings() async {
    if (_matchId == null) return;

    final events = await DatabaseHelper.instance.fetchBallEvents(
      _matchId!,
      innings: _currentInnings,
    );

    _allBallsThisInnings = events.map((e) => BallEvent.fromMap(e)).toList();
  }

  Future<void> _recalculateBatterStats() async {
    if (_matchId == null || _strikerId == null) return;
    
    // For unnamed tracking, we compute stats from all balls
    final events = _allBallsThisInnings;
    
    // Reset stats
    _strikerStats = {'runs': 0, 'balls': 0, 'fours': 0, 'sixes': 0};
    _nonStrikerStats = {'runs': 0, 'balls': 0, 'fours': 0, 'sixes': 0};
    
    for (final e in events) {
      final strikerId = e.strikerId;
      final extraType = e.extraType;
      
      Map<String, int> stats;
      if (strikerId == _strikerId) {
        stats = _strikerStats;
      } else if (strikerId == _nonStrikerId) {
        stats = _nonStrikerStats;
      } else {
        continue;
      }
      
      // Count runs (not byes/leg byes)
      if (extraType != 'bye' && extraType != 'leg_bye') {
        stats['runs'] = (stats['runs'] ?? 0) + e.runsScored;
      }
      
      // Count balls faced (not wides)
      if (extraType != 'wide') {
        stats['balls'] = (stats['balls'] ?? 0) + 1;
      }
      
      if (e.isBoundary) {
        if (e.runsScored == 4) stats['fours'] = (stats['fours'] ?? 0) + 1;
        if (e.runsScored == 6) stats['sixes'] = (stats['sixes'] ?? 0) + 1;
      }
    }
  }

  Future<void> _recalculateBowlerStats() async {
    if (_matchId == null || _currentBowlerId == null) return;
    
    final events = _allBallsThisInnings.where((e) => e.bowlerId == _currentBowlerId).toList();
    
    int legalBalls = 0;
    int runsConceded = 0;
    int wickets = 0;
    
    for (final e in events) {
      final extraType = e.extraType;
      
      // Count runs conceded
      if (extraType != 'bye' && extraType != 'leg_bye') {
        runsConceded += e.runsScored + e.extraRuns;
      } else {
        runsConceded += e.extraRuns;
      }
      
      // Count legal deliveries
      if (extraType != 'wide' && extraType != 'no_ball') {
        legalBalls++;
      }
      
      // Count wickets (not run outs)
      if (e.isWicket && e.wicketType != 'run_out') {
        wickets++;
      }
    }
    
    final overs = legalBalls ~/ 6;
    final balls = legalBalls % 6;
    final economy = legalBalls > 0 ? (runsConceded / legalBalls) * 6 : 0.0;
    
    _bowlerStats = {
      'overs': overs,
      'balls': balls,
      'maidens': 0, // Simplified for now
      'runs': runsConceded,
      'wickets': wickets,
      'economy': economy,
    };
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// BALL EVENT MODEL
// ══════════════════════════════════════════════════════════════════════════════

class BallEvent {
  final int id;
  final int matchId;
  final int innings;
  final int overNum;
  final int ballNum;
  final int runsScored;
  final bool isBoundary;
  final bool isWicket;
  final String? wicketType;
  final String? extraType;
  final int extraRuns;
  final int? strikerId;
  final int? nonStrikerId;
  final int? bowlerId;
  final int? outPlayerId;

  BallEvent({
    required this.id,
    required this.matchId,
    required this.innings,
    required this.overNum,
    required this.ballNum,
    required this.runsScored,
    required this.isBoundary,
    required this.isWicket,
    this.wicketType,
    this.extraType,
    required this.extraRuns,
    this.strikerId,
    this.nonStrikerId,
    this.bowlerId,
    this.outPlayerId,
  });

  factory BallEvent.fromMap(Map<String, dynamic> map) {
    return BallEvent(
      id:           map[DatabaseHelper.colId] as int,
      matchId:      map[DatabaseHelper.colMatchId] as int,
      innings:      map[DatabaseHelper.colInnings] as int,
      overNum:      map[DatabaseHelper.colOverNum] as int,
      ballNum:      map[DatabaseHelper.colBallNum] as int,
      runsScored:   map[DatabaseHelper.colRunsScored] as int,
      isBoundary:   (map[DatabaseHelper.colIsBoundary] as int) == 1,
      isWicket:     (map[DatabaseHelper.colIsWicket] as int) == 1,
      wicketType:   map[DatabaseHelper.colWicketType] as String?,
      extraType:    map[DatabaseHelper.colExtraType] as String?,
      extraRuns:    map[DatabaseHelper.colExtraRuns] as int,
      strikerId:    map[DatabaseHelper.colStrikerId] as int?,
      nonStrikerId: map[DatabaseHelper.colNonStrikerId] as int?,
      bowlerId:     map[DatabaseHelper.colBowlerId] as int?,
      outPlayerId:  map[DatabaseHelper.colOutPlayerId] as int?,
    );
  }

  /// Display label for UI (e.g., '4', 'W', 'Wd', 'Nb')
  String get displayLabel {
    if (isWicket) return 'W';
    if (extraType == 'wide') return extraRuns > 1 ? 'Wd+${extraRuns - 1}' : 'Wd';
    if (extraType == 'no_ball') return extraRuns > 1 ? 'Nb+${extraRuns - 1}' : 'Nb';
    if (extraType == 'bye') return '${extraRuns}b';
    if (extraType == 'leg_bye') return '${extraRuns}lb';
    return '$runsScored';
  }

  /// Total runs from this ball (batting runs + extras)
  int get totalRuns => runsScored + extraRuns;

  /// Whether this counts as a legal delivery
  bool get isLegalDelivery => extraType != 'wide' && extraType != 'no_ball';
}
