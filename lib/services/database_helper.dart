import 'package:sqflite/sqflite.dart';
// ignore: depend_on_referenced_packages
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';

/// Singleton wrapper around the local SQLite database.
///
/// Tables
/// ──────
/// tournaments
///   id              INTEGER PRIMARY KEY AUTOINCREMENT
///   name            TEXT    NOT NULL
///   format          TEXT    NOT NULL DEFAULT 'league'  ('league' | 'knockout' | 'mixed')
///   overs_per_match INTEGER NOT NULL DEFAULT 20
///   teams           TEXT    NOT NULL  (comma-separated team name strings, legacy field)
///   status          TEXT    NOT NULL DEFAULT 'active'  ('active' | 'completed')
///   created_at      TEXT    NOT NULL
///   created_by      TEXT
///   winner_team_id  INTEGER  → tournament_teams(id), set when tournament completes
///
/// tournament_teams  (added v14)
///   id              INTEGER PRIMARY KEY AUTOINCREMENT
///   tournament_id   INTEGER NOT NULL → tournaments(id)
///   team_name       TEXT    NOT NULL
///   is_eliminated   INTEGER NOT NULL DEFAULT 0  (0 = active, 1 = eliminated)
///
/// matches
///   id            INTEGER PRIMARY KEY AUTOINCREMENT
///   uuid          TEXT    NOT NULL UNIQUE  (UUID string used as Supabase PK)
///   team_a        TEXT    NOT NULL
///   team_b        TEXT    NOT NULL
///   total_overs   INTEGER NOT NULL
///   toss_winner   TEXT    (team_a | team_b)
///   opt_to        TEXT    (bat | bowl)
///   status        TEXT    NOT NULL DEFAULT 'pending'
///                 ('pending' | 'live' | 'completed')
///   current_innings INTEGER NOT NULL DEFAULT 1  (1 or 2)
///   target        INTEGER  (target score for 2nd innings)
///   sync_status   INTEGER NOT NULL DEFAULT 0    (0 = unsynced, 1 = synced)
///   created_at    TEXT    NOT NULL
///   created_by    TEXT    (user UID for Supabase sync)
///   tournament_id INTEGER  → tournaments(id)  NULL = quick/standalone match
///
/// NOTE: tournament_name (TEXT) was removed in DB v17.  The tournament name is
///   now derived at query time via a JOIN on tournaments.name using tournament_id.
///
/// players
///   id            INTEGER PRIMARY KEY AUTOINCREMENT
///   uuid          TEXT    NOT NULL UNIQUE  (UUID string used as Supabase PK)
///   name          TEXT    NOT NULL
///   team          TEXT    NOT NULL
///   sync_status   INTEGER NOT NULL DEFAULT 0
///   created_at    TEXT    NOT NULL
///   created_by    TEXT    (user UID for Supabase sync)
///
/// match_players
///   id            INTEGER PRIMARY KEY AUTOINCREMENT
///   match_id      INTEGER NOT NULL  → matches(id)
///   player_id     INTEGER NOT NULL  → players(id)
///   team          TEXT    NOT NULL  (team_a | team_b)
///   batting_order INTEGER  (1-11, null if not set)
///   sync_status   INTEGER NOT NULL DEFAULT 0
///   created_by    TEXT    (user UID for Supabase sync)
///
/// ball_events
///   id            INTEGER PRIMARY KEY AUTOINCREMENT
///   match_id      INTEGER NOT NULL  → matches(id)
///   innings       INTEGER NOT NULL DEFAULT 1
///   over_num      INTEGER NOT NULL
///   ball_num      INTEGER NOT NULL
///   runs_scored   INTEGER NOT NULL DEFAULT 0
///   is_boundary   INTEGER NOT NULL DEFAULT 0  (0 = false, 1 = true)
///   is_wicket     INTEGER NOT NULL DEFAULT 0  (0 = false, 1 = true)
///   wicket_type   TEXT    (bowled, caught, lbw, run_out, stumped, hit_wicket, etc.)
///   extra_type    TEXT    (wide, no_ball, bye, leg_bye, penalty)
///   extra_runs    INTEGER NOT NULL DEFAULT 0
///   striker_id    INTEGER  → players(id) or NULL for unnamed tracking
///   non_striker_id INTEGER → players(id) or NULL
///   bowler_id     INTEGER  → players(id) or NULL
///   out_player_id INTEGER  → players(id), who got out (for run outs can differ from striker)
///   sync_status   INTEGER NOT NULL DEFAULT 0  (0 = unsynced, 1 = synced)
///   created_at    TEXT    NOT NULL
///   created_by    TEXT    (user UID for Supabase sync)
class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  static Database? _db;

  static const _dbName    = 'wicket_v2.db';
  static const _dbVersion = 22;

  static final _uuid = Uuid();

  // ── Table names ─────────────────────────────────────────────────────────
  static const tableMatches           = 'matches';
  static const tableBallEvents        = 'ball_events';
  static const tablePlayers           = 'players';
  static const tableMatchPlayers      = 'match_players';
  static const tableTournaments       = 'tournaments';
  static const tableTournamentTeams   = 'tournament_teams';
  static const tableTeams             = 'teams';

  // ── shared columns ──────────────────────────────────────────────────────
  static const colId             = 'id';
  static const colUuid           = 'uuid';  // UUID string used as Supabase PK

  // ── matches columns ─────────────────────────────────────────────────────
  static const colTeamA          = 'team_a';
  static const colTeamB          = 'team_b';
  static const colTotalOvers     = 'total_overs';
  static const colTossWinner     = 'toss_winner';
  static const colOptTo          = 'opt_to';
  static const colStatus         = 'status';
  static const colCurrentInnings = 'current_innings';
  static const colTarget         = 'target';
  static const colSyncStatus     = 'sync_status';
  static const colCreatedAt      = 'created_at';
  static const colCreatedBy      = 'created_by';
  static const colWinner         = 'winner';
  /// FK → players(id).  Persisted when the match is completed.
  static const colMotmPlayerId   = 'motm_player_id';
  /// FK → tournaments(id).  NULL means this is a standalone / quick match.
  static const colTournamentId   = 'tournament_id';
  /// Match stage within a tournament: 'Group Stage' | 'Quarter-Final' |
  /// 'Semi-Final' | 'Final'.  NULL for standalone matches.
  static const colMatchStage     = 'match_stage';
  /// Squad size (number of players per side). Default 11, min 2.
  /// Determines the wicket limit: wicket limit = squad_size - 1.
  static const colSquadSize      = 'squad_size';

  // ── tournaments columns ─────────────────────────────────────────────────
  static const colFormat         = 'format';         // 'league' | 'knockout' | 'mixed'
  static const colOversPerMatch  = 'overs_per_match';
  static const colTeams          = 'teams';           // comma-separated list of team names (legacy)
  /// UUID string used as the Supabase PK for tournaments (mirrors colUuid on matches/players).
  static const colTournamentUuid = 'uuid';
  /// FK → tournament_teams(id).  Set when the tournament is completed.
  static const colWinnerTeamId   = 'winner_team_id';

  // ── tournament_teams columns ────────────────────────────────────────────
  static const colTournamentId2  = 'tournament_id';  // reuses colTournamentId; separate const for clarity
  static const colTeamName       = 'team_name';
  static const colIsEliminated   = 'is_eliminated';  // 0 = active, 1 = eliminated

  // ── players columns ─────────────────────────────────────────────────────
  static const colName             = 'name';
  static const colTeam             = 'team';
  static const colRole             = 'role';
  static const colBowlingType      = 'bowling_type';
  static const colLocalAvatarPath  = 'local_avatar_path';

  // ── teams columns ────────────────────────────────────────────────────────
  static const colTeamUuid         = 'team_uuid';

  // ── matches FK columns (v21) ─────────────────────────────────────────────
  /// FK → teams(id).  Set when the match is created via the quick-match flow.
  static const colTeamAId          = 'team_a_id';
  /// FK → teams(id).  Set when the match is created via the quick-match flow.
  static const colTeamBId          = 'team_b_id';

  // ── players FK column (v21) ──────────────────────────────────────────────
  /// FK → teams(id).  Set when a player is assigned to a team via the hub.
  static const colTeamId           = 'team_id';

  // ── match_players columns ───────────────────────────────────────────────
  static const colPlayerId       = 'player_id';
  static const colBattingOrder   = 'batting_order';

  // ── ball_events columns ─────────────────────────────────────────────────
  static const colMatchId       = 'match_id';
  static const colInnings       = 'innings';
  static const colOverNum       = 'over_num';
  static const colBallNum       = 'ball_num';
  static const colRunsScored    = 'runs_scored';
  static const colIsBoundary    = 'is_boundary';
  static const colIsWicket      = 'is_wicket';
  static const colWicketType    = 'wicket_type';
  static const colExtraType     = 'extra_type';
  static const colExtraRuns     = 'extra_runs';
  static const colStrikerId     = 'striker_id';
  static const colNonStrikerId  = 'non_striker_id';
  static const colBowlerId      = 'bowler_id';
  static const colOutPlayerId   = 'out_player_id';

  // ── Public API ──────────────────────────────────────────────────────────

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MATCHES
  // ══════════════════════════════════════════════════════════════════════════

  /// Insert a new match and return its auto-generated id.
  Future<int> insertMatch({
    required String teamA,
    required String teamB,
    required int totalOvers,
    String? tossWinner,
    String? optTo,
    String? createdBy,
    int? tournamentId,
    String? matchStage,
    int? teamAId,
    int? teamBId,
  }) async {
    final db = await database;
    return db.insert(
      tableMatches,
      {
        colUuid:           _uuid.v4(),
        colTeamA:          teamA,
        colTeamB:          teamB,
        colTotalOvers:     totalOvers,
        colTossWinner:     tossWinner,
        colOptTo:          optTo,
        colStatus:         'pending',
        colCurrentInnings: 1,
        colSyncStatus:     0,
        colCreatedAt:      DateTime.now().toIso8601String(),
        colCreatedBy:      createdBy,
        colTournamentId:   tournamentId,
        colMatchStage:     matchStage,
        colTeamAId:        teamAId,
        colTeamBId:        teamBId,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Return all matches, newest first.
  Future<List<Map<String, dynamic>>> fetchAllMatches() async {
    final db = await database;
    return db.query(tableMatches, orderBy: '$colCreatedAt DESC');
  }

  /// Return only standalone (Quick Match) matches — those with no tournament.
  ///
  /// Uses [tournament_id] IS NULL to identify quick matches.  This works for
  /// both locally-created matches and community matches synced down from
  /// Supabase (which now carry a proper tournament_id FK or NULL).
  Future<List<Map<String, dynamic>>> fetchQuickMatches() async {
    final db = await database;
    return db.query(
      tableMatches,
      where: '$colTournamentId IS NULL',
      orderBy: '$colCreatedAt DESC',
    );
  }

  /// Fetch quick matches created by a specific user (for "My Matches" tab).
  Future<List<Map<String, dynamic>>> fetchMyMatches(String userId) async {
    final db = await database;
    return db.query(
      tableMatches,
      where: '$colTournamentId IS NULL AND $colCreatedBy = ?',
      whereArgs: [userId],
      orderBy: '$colCreatedAt DESC',
    );
  }

  /// Fetch the most recent [limit] quick matches created by [userId], regardless
  /// of status (ongoing, live, pending, completed).
  /// Used by the Dashboard to show a compact "last N matches" view, including
  /// in-progress matches so they are never hidden when the app is reopened.
  Future<List<Map<String, dynamic>>> fetchRecentMatches(
    String userId, {
    int limit = 5,
  }) async {
    final db = await database;
    return db.query(
      tableMatches,
      where: '$colTournamentId IS NULL AND $colCreatedBy = ?',
      whereArgs: [userId],
      orderBy: '$colCreatedAt DESC',
      limit: limit,
    );
  }

  /// Persist toss result (winner team name + choice) for a match.
  Future<void> updateMatchToss(
    int matchId,
    String tossWinner,
    String optTo,
  ) async {
    final db = await database;
    await db.update(
      tableMatches,
      {
        colTossWinner: tossWinner,
        colOptTo: optTo,
        colSyncStatus: 0,
      },
      where: '$colId = ?',
      whereArgs: [matchId],
    );
  }

  /// Fetch a single match by id, with the tournament name resolved via a JOIN
  /// on the tournaments table.  Returns all match columns plus an additional
  /// synthetic key `tournament_name` (String?) derived from
  /// `tournaments.name`.  Returns null if no match is found.
  Future<Map<String, dynamic>?> fetchMatchWithTournamentName(int matchId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT
        m.*,
        t.$colName AS tournament_name
      FROM $tableMatches m
      LEFT JOIN $tableTournaments t ON t.$colId = m.$colTournamentId
      WHERE m.$colId = ?
      LIMIT 1
    ''', [matchId]);
    return rows.isNotEmpty ? Map<String, dynamic>.from(rows.first) : null;
  }

  /// Return all matches belonging to a specific tournament, newest first.
  Future<List<Map<String, dynamic>>> fetchMatchesByTournament(int tournamentId) async {
    final db = await database;
    return db.query(
      tableMatches,
      where: '$colTournamentId = ?',
      whereArgs: [tournamentId],
      orderBy: '$colCreatedAt DESC',
    );
  }

  /// Return all matches where [teamName] is either team_a or team_b, newest first.
  Future<List<Map<String, dynamic>>> fetchMatchesByTeam(String teamName) async {
    final db = await database;
    return db.query(
      tableMatches,
      where: '$colTeamA = ? OR $colTeamB = ?',
      whereArgs: [teamName, teamName],
      orderBy: '$colCreatedAt DESC',
    );
  }

  /// Return the [limit] most-recent standalone (quick) matches — used by the
  /// Global Matches feed to avoid loading the entire table into memory.
  Future<List<Map<String, dynamic>>> fetchRecentGlobalMatches({
    int limit = 15,
  }) async {
    final db = await database;
    return db.query(
      tableMatches,
      where: '$colTournamentId IS NULL',
      orderBy: '$colCreatedAt DESC',
      limit: limit,
    );
  }

  /// Search standalone matches whose team_a OR team_b contains [query]
  /// (case-insensitive LIKE).  Returns up to [limit] rows, newest first.
  Future<List<Map<String, dynamic>>> searchGlobalMatches(
    String query, {
    int limit = 50,
  }) async {
    final db = await database;
    final like = '%$query%';
    return db.query(
      tableMatches,
      where: '$colTournamentId IS NULL AND ($colTeamA LIKE ? OR $colTeamB LIKE ?)',
      whereArgs: [like, like],
      orderBy: '$colCreatedAt DESC',
      limit: limit,
    );
  }

  /// Returns up to [limit] distinct team names that start with [prefix]
  /// (case-insensitive). Searches team_a/team_b match columns AND the
  /// dedicated teams table (so hub-created teams appear as suggestions too).
  Future<List<String>> getDistinctTeamNames({
    String prefix = '',
    int limit = 5,
  }) async {
    final db = await database;
    final like = '${prefix.trim()}%';
    final rows = await db.rawQuery('''
      SELECT DISTINCT name FROM (
        SELECT $colTeamA AS name FROM $tableMatches WHERE $colTeamA LIKE ?
        UNION
        SELECT $colTeamB AS name FROM $tableMatches WHERE $colTeamB LIKE ?
        UNION
        SELECT $colName  AS name FROM $tableTeams   WHERE $colName  LIKE ?
      )
      ORDER BY name ASC
      LIMIT ?
    ''', [like, like, like, limit]);
    return rows.map((r) => r['name'] as String).toList();
  }

  /// Fetch a single match by id.
  Future<Map<String, dynamic>?> fetchMatch(int matchId) async {
    final db = await database;
    final results = await db.query(
      tableMatches,
      where: '$colId = ?',
      whereArgs: [matchId],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// Update the status of a match ('pending' | 'live' | 'completed').
  Future<void> updateMatchStatus(int matchId, String status) async {
    final db = await database;
    await db.update(
      tableMatches,
      {colStatus: status, colSyncStatus: 0},
      where: '$colId = ?',
      whereArgs: [matchId],
    );
  }

  /// Update the total_overs for a match mid-game (Tapeball Dynamics).
  Future<void> updateMatchOvers(int matchId, int newOvers) async {
    final db = await database;
    await db.update(
      tableMatches,
      {colTotalOvers: newOvers, colSyncStatus: 0},
      where: '$colId = ?',
      whereArgs: [matchId],
    );
  }

  /// Update the squad_size for a match mid-game (Tapeball Dynamics).
  Future<void> updateMatchSquadSize(int matchId, int squadSize) async {
    final db = await database;
    await db.update(
      tableMatches,
      {colSquadSize: squadSize, colSyncStatus: 0},
      where: '$colId = ?',
      whereArgs: [matchId],
    );
  }

  /// Persist the match winner string to SQLite and mark the row as unsynced.
  ///
  /// Pass 'Draw' when scores are equal.
  Future<void> updateMatchWinner(int matchId, String winner) async {
    final db = await database;
    await db.update(
      tableMatches,
      {colWinner: winner, colSyncStatus: 0},
      where: '$colId = ?',
      whereArgs: [matchId],
    );
  }

  /// Persist the MOTM player id to the local matches row and mark unsynced.
  ///
  /// [motmPlayerId] is the SQLite integer id of the player (players.id).
  Future<void> updateMatchMotm(int matchId, int motmPlayerId) async {
    final db = await database;
    await db.update(
      tableMatches,
      {colMotmPlayerId: motmPlayerId, colSyncStatus: 0},
      where: '$colId = ?',
      whereArgs: [matchId],
    );
  }

  /// Update current innings (1 or 2).
  Future<void> updateCurrentInnings(int matchId, int innings) async {
    final db = await database;
    await db.update(
      tableMatches,
      {colCurrentInnings: innings, colSyncStatus: 0},
      where: '$colId = ?',
      whereArgs: [matchId],
    );
  }

  /// Fetch all unsynced matches.
  Future<List<Map<String, dynamic>>> fetchUnsyncedMatches() async {
    final db = await database;
    return db.query(
      tableMatches,
      where: '$colSyncStatus = 0',
      orderBy: '$colId ASC',
    );
  }

  /// Mark a match as synced.
  Future<void> markMatchSynced(int matchId) async {
    final db = await database;
    await db.update(
      tableMatches,
      {colSyncStatus: 1},
      where: '$colId = ?',
      whereArgs: [matchId],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BALL EVENTS
  // ══════════════════════════════════════════════════════════════════════════

  /// Record a single ball delivery.
  Future<int> insertBallEvent({
    required int matchId,
    required int innings,
    required int overNum,
    required int ballNum,
    required int runsScored,
    bool isBoundary = false,
    bool isWicket = false,
    String? wicketType,
    String? extraType,
    int extraRuns = 0,
    int? strikerId,
    int? nonStrikerId,
    int? bowlerId,
    int? outPlayerId,
    String? createdBy,
  }) async {
    final db = await database;
    return db.insert(
      tableBallEvents,
      {
        colMatchId:       matchId,
        colInnings:       innings,
        colOverNum:       overNum,
        colBallNum:       ballNum,
        colRunsScored:    runsScored,
        colIsBoundary:    isBoundary ? 1 : 0,
        colIsWicket:      isWicket   ? 1 : 0,
        colWicketType:    wicketType,
        colExtraType:     extraType,
        colExtraRuns:     extraRuns,
        colStrikerId:     strikerId,
        colNonStrikerId:  nonStrikerId,
        colBowlerId:      bowlerId,
        colOutPlayerId:   outPlayerId,
        colSyncStatus:    0,
        colCreatedAt:     DateTime.now().toIso8601String(),
        colCreatedBy:     createdBy,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Fetch all ball events for a given match and innings, in delivery order.
  Future<List<Map<String, dynamic>>> fetchBallEvents(
    int matchId, {
    int? innings,
  }) async {
    final db = await database;
    String where = '$colMatchId = ?';
    List<dynamic> whereArgs = [matchId];
    
    if (innings != null) {
      where += ' AND $colInnings = ?';
      whereArgs.add(innings);
    }
    
    return db.query(
      tableBallEvents,
      where: where,
      whereArgs: whereArgs,
      orderBy: '$colInnings ASC, $colOverNum ASC, $colBallNum ASC',
    );
  }

  /// Fetch all ball events for a match with player names resolved via a single
  /// SQL JOIN — avoids N+1 lookups.
  ///
  /// Returns a list of maps with the original ball_event columns plus:
  ///   striker_name     – name of the striking batter (or 'Unknown')
  ///   non_striker_name – name of the non-striking batter (or 'Unknown')
  ///   bowler_name      – name of the bowler (or 'Unknown')
  ///   out_player_name  – name of the dismissed player, or null
  ///
  /// Results are ordered innings → over → ball (ascending).
  Future<List<Map<String, dynamic>>> getBallEventsWithPlayerNames(
    int matchId, {
    int? innings,
  }) async {
    final db = await database;

    final inningsClause = innings != null
        ? 'AND be.$colInnings = $innings'
        : '';

    // Three LEFT JOINs: one per player role.
    // Aliases: ps = striker, pn = non_striker, pb = bowler, po = out_player
    final sql = '''
      SELECT
        be.$colId,
        be.$colMatchId,
        be.$colInnings,
        be.$colOverNum,
        be.$colBallNum,
        be.$colRunsScored,
        be.$colIsBoundary,
        be.$colIsWicket,
        be.$colWicketType,
        be.$colExtraType,
        be.$colExtraRuns,
        be.$colStrikerId,
        be.$colNonStrikerId,
        be.$colBowlerId,
        be.$colOutPlayerId,
        COALESCE(ps.$colName, 'Unknown') AS striker_name,
        COALESCE(pn.$colName, 'Unknown') AS non_striker_name,
        COALESCE(pb.$colName, 'Unknown') AS bowler_name,
        po.$colName                      AS out_player_name
      FROM $tableBallEvents be
      LEFT JOIN $tablePlayers ps ON ps.$colId = be.$colStrikerId
      LEFT JOIN $tablePlayers pn ON pn.$colId = be.$colNonStrikerId
      LEFT JOIN $tablePlayers pb ON pb.$colId = be.$colBowlerId
      LEFT JOIN $tablePlayers po ON po.$colId = be.$colOutPlayerId
      WHERE be.$colMatchId = $matchId
      $inningsClause
      ORDER BY be.$colInnings ASC, be.$colOverNum ASC, be.$colBallNum ASC
    ''';

    return db.rawQuery(sql);
  }

  /// Fetch the current over's ball events.
  Future<List<Map<String, dynamic>>> fetchCurrentOverBalls(
    int matchId,
    int innings,
    int overNum,
  ) async {
    final db = await database;
    return db.query(
      tableBallEvents,
      where: '$colMatchId = ? AND $colInnings = ? AND $colOverNum = ?',
      whereArgs: [matchId, innings, overNum],
      orderBy: '$colBallNum ASC',
    );
  }

  /// Fetch all unsynced ball events.
  Future<List<Map<String, dynamic>>> fetchUnsyncedBallEvents() async {
    final db = await database;
    return db.query(
      tableBallEvents,
      where: '$colSyncStatus = 0',
      orderBy: '$colId ASC',
    );
  }

  /// Returns the set of player IDs that have been dismissed (is_wicket = 1)
  /// in the given innings of the given match.  Used by the new-batter modal to
  /// prevent re-selecting an already out player.
  Future<Set<int>> fetchDismissedPlayerIds(int matchId, int innings) async {
    final db = await database;
    final rows = await db.query(
      tableBallEvents,
      columns: [colOutPlayerId],
      where: '$colMatchId = ? AND $colInnings = ? AND $colIsWicket = 1 AND $colOutPlayerId IS NOT NULL',
      whereArgs: [matchId, innings],
    );
    return rows
        .map((r) => r[colOutPlayerId] as int)
        .toSet();
  }

  /// Mark a ball event as synced.
  Future<void> markBallEventSynced(int eventId) async {
    final db = await database;
    await db.update(
      tableBallEvents,
      {colSyncStatus: 1},
      where: '$colId = ?',
      whereArgs: [eventId],
    );
  }

  /// Delete the last ball event for undo functionality.
  Future<void> deleteLastBallEvent(int matchId, int innings) async {
    final db = await database;
    final lastEvent = await db.query(
      tableBallEvents,
      where: '$colMatchId = ? AND $colInnings = ?',
      whereArgs: [matchId, innings],
      orderBy: '$colId DESC',
      limit: 1,
    );
    
    if (lastEvent.isNotEmpty) {
      await db.delete(
        tableBallEvents,
        where: '$colId = ?',
        whereArgs: [lastEvent.first[colId]],
      );
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // AGGREGATIONS
  // ══════════════════════════════════════════════════════════════════════════

  /// Get summary statistics for an innings.
  Future<Map<String, int>> getInningsSummary(int matchId, int innings) async {
    final events = await fetchBallEvents(matchId, innings: innings);
    
    int totalRuns = 0;
    int totalWickets = 0;
    int legalBalls = 0;
    int extras = 0;
    int fours = 0;
    int sixes = 0;

    for (final e in events) {
      final runs = e[colRunsScored] as int;
      final extraRuns = e[colExtraRuns] as int;
      final isWicket = (e[colIsWicket] as int) == 1;
      final isBoundary = (e[colIsBoundary] as int) == 1;
      final extraType = e[colExtraType] as String?;
      
      totalRuns += runs + extraRuns;
      extras += extraRuns;
      
      if (isWicket) totalWickets++;
      
      if (isBoundary) {
        if (runs == 4) fours++;
        if (runs == 6) sixes++;
      }
      
      // Wide and no-ball don't count as legal deliveries
      if (extraType != 'wide' && extraType != 'no_ball') {
        legalBalls++;
      }
    }

    return {
      'totalRuns': totalRuns,
      'totalWickets': totalWickets,
      'legalBalls': legalBalls,
      'completedOvers': legalBalls ~/ 6,
      'ballsInOver': legalBalls % 6,
      'extras': extras,
      'fours': fours,
      'sixes': sixes,
    };
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PLAYERS
  // ══════════════════════════════════════════════════════════════════════════

  /// Insert a new player.
  Future<int> insertPlayer({
    required String name,
    required String team,
    String? role,
    String? bowlingType,
    String? localAvatarPath,
    String? createdBy,
  }) async {
    final db = await database;
    return db.insert(
      tablePlayers,
      {
        colUuid:            _uuid.v4(),
        colName:            name,
        colTeam:            team,
        colRole:            role,
        colBowlingType:     bowlingType,
        colLocalAvatarPath: localAvatarPath,
        colSyncStatus:      0,
        colCreatedAt:       DateTime.now().toIso8601String(),
        colCreatedBy:       createdBy,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Find an existing player by exact name and team.
  ///
  /// Returns the player's `id` if a match is found, or `null` if none exists.
  /// Used by [setNewBowlerWithName] / [setNewBatterWithName] to avoid creating
  /// duplicate player records for the same person across overs.
  Future<int?> findPlayerIdByNameAndTeam(String name, String team) async {
    final db = await database;
    final rows = await db.query(
      tablePlayers,
      columns: [colId],
      where: '$colName = ? AND $colTeam = ?',
      whereArgs: [name, team],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first[colId] as int;
  }

  /// Fetch all players for a team.
  Future<List<Map<String, dynamic>>> fetchPlayersByTeam(String team) async {
    final db = await database;
    return db.query(
      tablePlayers,
      where: '$colTeam = ?',
      whereArgs: [team],
      orderBy: '$colName ASC',
    );
  }

  /// Fetch ALL players, ordered by name.
  Future<List<Map<String, dynamic>>> fetchAllPlayers() async {
    final db = await database;
    return db.query(tablePlayers, orderBy: '$colName ASC');
  }

  /// Fetch players visible to [userId]: those they created themselves OR those
  /// belonging to a team that appears in any of their matches.
  /// Falls back to all players if [userId] is null.
  Future<List<Map<String, dynamic>>> fetchPlayersForUser(String? userId) async {
    if (userId == null) return fetchAllPlayers();
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT DISTINCT p.*
      FROM $tablePlayers p
      WHERE p.$colCreatedBy = ?
         OR p.$colTeam IN (
           SELECT $colTeamA FROM $tableMatches WHERE $colCreatedBy = ?
           UNION
           SELECT $colTeamB FROM $tableMatches WHERE $colCreatedBy = ?
         )
      ORDER BY p.$colName ASC
    ''', [userId, userId, userId]);
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// Returns all distinct team names stored in the players table, sorted
  /// alphabetically.  Used for autocomplete suggestions when creating a
  /// tournament or adding a team.
  Future<List<String>> fetchDistinctTeamNames() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT DISTINCT $colTeam FROM $tablePlayers ORDER BY $colTeam ASC',
    );
    return rows.map((r) => r[colTeam] as String).toList();
  }

  /// Update a player's name, team, role, bowling type, and optional avatar path.
  Future<void> updatePlayer(int playerId, {
    required String name,
    required String team,
    String? role,
    String? bowlingType,
    String? localAvatarPath,
  }) async {
    final db = await database;
    await db.update(
      tablePlayers,
      {
        colName:            name,
        colTeam:            team,
        colRole:            role,
        colBowlingType:     bowlingType,
        colLocalAvatarPath: localAvatarPath,
        colSyncStatus:      0,
      },
      where: '$colId = ?',
      whereArgs: [playerId],
    );
  }

  /// Delete a player by id.
  Future<void> deletePlayer(int playerId) async {
    final db = await database;
    await db.delete(tablePlayers, where: '$colId = ?', whereArgs: [playerId]);
  }

  /// Fetch a player by ID.
  Future<Map<String, dynamic>?> fetchPlayer(int playerId) async {
    final db = await database;
    final results = await db.query(
      tablePlayers,
      where: '$colId = ?',
      whereArgs: [playerId],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TEAMS
  // ══════════════════════════════════════════════════════════════════════════

  /// Insert a new team and return its auto-generated SQLite id.
  Future<int> insertTeam({
    required String name,
    String? createdBy,
  }) async {
    final db = await database;
    return db.insert(
      tableTeams,
      {
        colTeamUuid:   _uuid.v4(),
        colName:       name.trim(),
        colSyncStatus: 0,
        colCreatedAt:  DateTime.now().toIso8601String(),
        colCreatedBy:  createdBy,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Fetch all teams created by [userId].  Falls back to all teams if null.
  Future<List<Map<String, dynamic>>> fetchTeamsByUser(String? userId) async {
    final db = await database;
    if (userId == null) return fetchAllTeams();
    return db.query(
      tableTeams,
      where: '$colCreatedBy = ?',
      whereArgs: [userId],
      orderBy: '$colName ASC',
    );
  }

  /// Fetch ALL teams, ordered by name.
  Future<List<Map<String, dynamic>>> fetchAllTeams() async {
    final db = await database;
    return db.query(tableTeams, orderBy: '$colName ASC');
  }

  /// Fetch a single team row by its SQLite id.
  Future<Map<String, dynamic>?> fetchTeam(int teamId) async {
    final db = await database;
    final rows = await db.query(
      tableTeams,
      where: '$colId = ?',
      whereArgs: [teamId],
      limit: 1,
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  /// Update the team name (marks as unsynced).
  Future<void> updateTeamName(int teamId, String name) async {
    final db = await database;
    await db.update(
      tableTeams,
      {colName: name.trim(), colSyncStatus: 0},
      where: '$colId = ?',
      whereArgs: [teamId],
    );
  }

  /// Delete a team by SQLite id.
  Future<void> deleteTeam(int teamId) async {
    final db = await database;
    await db.delete(tableTeams, where: '$colId = ?', whereArgs: [teamId]);
  }

  /// Returns all teams with [colSyncStatus] == 0 (not yet pushed to Supabase).
  Future<List<Map<String, dynamic>>> fetchUnsyncedTeams() async {
    final db = await database;
    return db.query(
      tableTeams,
      where: '$colSyncStatus = 0',
    );
  }

  /// Mark a team row as synced (sets [colSyncStatus] to 1).
  Future<void> markTeamSynced(int teamId) async {
    final db = await database;
    await db.update(
      tableTeams,
      {colSyncStatus: 1},
      where: '$colId = ?',
      whereArgs: [teamId],
    );
  }

  /// Look up a team by exact name (case-sensitive). Returns null if not found.
  Future<Map<String, dynamic>?> fetchTeamByName(String name) async {
    final db = await database;
    final rows = await db.query(
      tableTeams,
      where: '$colName = ?',
      whereArgs: [name.trim()],
      limit: 1,
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  /// Find-or-create a team by name.
  ///
  /// Returns the SQLite [id] of the existing or newly-created row so callers
  /// can use it as a FK without first checking whether the row exists.
  Future<int> ensureTeamExists(String name, {String? createdBy}) async {
    final trimmed = name.trim();
    final existing = await fetchTeamByName(trimmed);
    if (existing != null) return existing[colId] as int;
    return insertTeam(name: trimmed, createdBy: createdBy);
  }

  /// Fetch all players whose [colTeamId] FK points to [teamId].
  ///
  /// Falls back gracefully if the column doesn't exist yet (returns empty list).
  Future<List<Map<String, dynamic>>> fetchPlayersByTeamId(int teamId) async {
    final db = await database;
    return db.query(
      tablePlayers,
      where: '$colTeamId = ?',
      whereArgs: [teamId],
      orderBy: '$colName ASC',
    );
  }

  /// Update a player's team FK ([colTeamId]) and the legacy TEXT column
  /// ([colTeam]) so existing queries that filter on [colTeam] keep working.
  Future<void> updatePlayerTeamId(
    int playerId,
    int teamId,
    String teamName,
  ) async {
    final db = await database;
    await db.update(
      tablePlayers,
      {
        colTeamId:     teamId,
        colTeam:       teamName,
        colSyncStatus: 0,
      },
      where: '$colId = ?',
      whereArgs: [playerId],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MATCH PLAYERS (Playing XI)
  // ══════════════════════════════════════════════════════════════════════════

  /// Add a player to a match's playing XI.
  Future<int> addPlayerToMatch({
    required int matchId,
    required int playerId,
    required String team,
    int? battingOrder,
    String? createdBy,
  }) async {
    final db = await database;
    return db.insert(
      tableMatchPlayers,
      {
        colMatchId:      matchId,
        colPlayerId:     playerId,
        colTeam:         team,
        colBattingOrder: battingOrder,
        colSyncStatus:   0,
        colCreatedBy:    createdBy,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Fetch playing XI for a match and team.
  Future<List<Map<String, dynamic>>> fetchMatchPlayers(
    int matchId,
    String team,
  ) async {
    final db = await database;
    return db.rawQuery('''
      SELECT mp.*, p.$colName as player_name
      FROM $tableMatchPlayers mp
      JOIN $tablePlayers p ON p.$colId = mp.$colPlayerId
      WHERE mp.$colMatchId = ? AND mp.$colTeam = ?
      ORDER BY mp.$colBattingOrder ASC NULLS LAST, p.$colName ASC
    ''', [matchId, team]);
  }

  /// Update batting order for a match player.
  Future<void> updateBattingOrder(int matchPlayerId, int order) async {
    final db = await database;
    await db.update(
      tableMatchPlayers,
      {colBattingOrder: order, colSyncStatus: 0},
      where: '$colId = ?',
      whereArgs: [matchPlayerId],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PLAYER STATISTICS (computed from ball_events)
  // ══════════════════════════════════════════════════════════════════════════

  /// Get batting stats for a player in a match/innings.
  Future<Map<String, int>> getBatterStats(
    int matchId,
    int innings,
    int playerId,
  ) async {
    final events = await fetchBallEvents(matchId, innings: innings);
    
    int runs = 0;
    int balls = 0;
    int fours = 0;
    int sixes = 0;

    for (final e in events) {
      final strikerId = e[colStrikerId] as int?;
      if (strikerId != playerId) continue;
      
      final extraType = e[colExtraType] as String?;
      final runsScored = e[colRunsScored] as int;
      final isBoundary = (e[colIsBoundary] as int) == 1;
      
      // Only count runs to batter's score (not byes/leg byes)
      if (extraType != 'bye' && extraType != 'leg_bye') {
        runs += runsScored;
      }
      
      // Count balls faced (not wides, but include no-balls)
      if (extraType != 'wide') {
        balls++;
      }
      
      if (isBoundary) {
        if (runsScored == 4) fours++;
        if (runsScored == 6) sixes++;
      }
    }

    return {
      'runs': runs,
      'balls': balls,
      'fours': fours,
      'sixes': sixes,
    };
  }

  /// Get bowling stats for a player in a match/innings.
  Future<Map<String, dynamic>> getBowlerStats(
    int matchId,
    int innings,
    int playerId,
  ) async {
    final events = await fetchBallEvents(matchId, innings: innings);
    
    int legalBalls = 0;
    int runsConceded = 0;
    int wickets = 0;
    int maidens = 0;
    
    // Track runs per over for maiden calculation
    Map<int, int> runsPerOver = {};
    Map<int, int> ballsPerOver = {};

    for (final e in events) {
      final bowlerId = e[colBowlerId] as int?;
      if (bowlerId != playerId) continue;
      
      final extraType = e[colExtraType] as String?;
      final runsScored = e[colRunsScored] as int;
      final extraRuns = e[colExtraRuns] as int;
      final isWicket = (e[colIsWicket] as int) == 1;
      final overNum = e[colOverNum] as int;
      
      // All runs count against bowler except byes/leg byes
      if (extraType != 'bye' && extraType != 'leg_bye') {
        runsConceded += runsScored + extraRuns;
      }
      // bye / leg_bye: add zero to runsConceded (not charged to bowler).
      
      // Count legal deliveries
      if (extraType != 'wide' && extraType != 'no_ball') {
        legalBalls++;
        ballsPerOver[overNum] = (ballsPerOver[overNum] ?? 0) + 1;
        // Byes/LBs don't cancel a maiden — only runs charged to bowler count
        if (extraType != 'bye' && extraType != 'leg_bye') {
          runsPerOver[overNum] = (runsPerOver[overNum] ?? 0) + runsScored + extraRuns;
        } else {
          runsPerOver[overNum] = (runsPerOver[overNum] ?? 0);
        }
      } else {
        // Extras add to runs in that over
        runsPerOver[overNum] = (runsPerOver[overNum] ?? 0) + extraRuns;
      }
      
      if (isWicket) {
        // Don't count run outs as bowler's wickets (unless bowled run out scenario)
        final wicketType = e[colWicketType] as String?;
        if (wicketType != 'run_out') {
          wickets++;
        }
      }
    }

    // Calculate maidens: overs with 6 balls and 0 runs
    for (final over in ballsPerOver.keys) {
      if (ballsPerOver[over] == 6 && (runsPerOver[over] ?? 0) == 0) {
        maidens++;
      }
    }

    final overs = legalBalls ~/ 6;
    final ballsRemaining = legalBalls % 6;
    final economy = legalBalls > 0 ? (runsConceded / legalBalls) * 6 : 0.0;

    return {
      'overs': overs,
      'balls': ballsRemaining,
      'maidens': maidens,
      'runs': runsConceded,
      'wickets': wickets,
      'economy': economy,
    };
  }

  /// Get all-time career statistics for a player across every match they have
  /// appeared in.
  ///
  /// Returns a map with:
  ///   batting  → totalRuns, totalBalls, totalFours, totalSixes, innings, notOuts
  ///   bowling  → totalWickets, totalLegalBalls, totalRunsConceded, bestWickets,
  ///              bestRuns (figures in same innings as bestWickets)
  Future<Map<String, dynamic>> getCareerStats(int playerId) async {
    final db = await database;

    // Pull every ball event where this player was striker or bowler.
    final rows = await db.rawQuery('''
      SELECT
        $colRunsScored,
        $colExtraRuns,
        $colIsBoundary,
        $colIsWicket,
        $colWicketType,
        $colExtraType,
        $colStrikerId,
        $colBowlerId,
        $colOutPlayerId,
        $colMatchId,
        $colInnings
      FROM $tableBallEvents
      WHERE $colStrikerId = ? OR $colBowlerId = ?
    ''', [playerId, playerId]);

    // ── Batting accumulators ────────────────────────────────────────────────
    int batRuns  = 0;
    int batBalls = 0;
    int batFours = 0;
    int batSixes = 0;
    // Track (matchId, innings) pairs to count innings and not-outs
    final Set<String> battingInnings = {};
    final Set<String> outInnings     = {};

    // ── Bowling accumulators ────────────────────────────────────────────────
    int bowlLegalBalls     = 0;
    int bowlRunsConceded   = 0;
    int bowlWickets        = 0;
    // Per-innings bowling figures for "best bowling" calculation
    final Map<String, Map<String, int>> inningsBowling = {};

    for (final r in rows) {
      final strikerId   = r[colStrikerId]   as int?;
      final bowlerId    = r[colBowlerId]    as int?;
      final outPlayerId = r[colOutPlayerId] as int?;
      final runsScored  = (r[colRunsScored]  as int?) ?? 0;
      final extraRuns   = (r[colExtraRuns]   as int?) ?? 0;
      final extraType   = r[colExtraType]   as String?;
      final isBoundary  = ((r[colIsBoundary]  as int?) ?? 0) == 1;
      final isWicket    = ((r[colIsWicket]    as int?) ?? 0) == 1;
      final wicketType  = r[colWicketType]  as String?;
      final matchId     = (r[colMatchId]     as int?)!;
      final innings     = (r[colInnings]     as int?) ?? 1;
      final innKey      = '$matchId-$innings';

      // ── Batting ────────────────────────────────────────────────────────
      if (strikerId == playerId) {
        battingInnings.add(innKey);
        // Runs: not byes/leg-byes
        if (extraType != 'bye' && extraType != 'leg_bye') {
          batRuns += runsScored;
        }
        // Balls: not wides
        if (extraType != 'wide') batBalls++;
        if (isBoundary && runsScored == 4) batFours++;
        if (isBoundary && runsScored == 6) batSixes++;
      }
      // Track when THIS player was dismissed (outPlayerId)
      if (isWicket && outPlayerId == playerId) {
        outInnings.add(innKey);
      }

      // ── Bowling ────────────────────────────────────────────────────────
      if (bowlerId == playerId) {
        final isLegal = extraType != 'wide' && extraType != 'no_ball';
        if (isLegal) bowlLegalBalls++;

        // Runs conceded
        if (extraType != 'bye' && extraType != 'leg_bye') {
          bowlRunsConceded += runsScored + extraRuns;
        } else {
          bowlRunsConceded += extraRuns;
        }

        // Wickets (not run-outs)
        if (isWicket && wicketType != 'run_out') {
          bowlWickets++;
          inningsBowling.putIfAbsent(innKey, () => {'w': 0, 'r': 0});
          inningsBowling[innKey]!['w'] = inningsBowling[innKey]!['w']! + 1;
        }
        // Track runs per innings for best-bowling figure
        inningsBowling.putIfAbsent(innKey, () => {'w': 0, 'r': 0});
        if (extraType != 'bye' && extraType != 'leg_bye') {
          inningsBowling[innKey]!['r'] =
              inningsBowling[innKey]!['r']! + runsScored + extraRuns;
        } else {
          inningsBowling[innKey]!['r'] =
              inningsBowling[innKey]!['r']! + extraRuns;
        }
      }
    }

    // ── Batting averages ────────────────────────────────────────────────────
    final dismissals   = outInnings.length;
    final notOuts      = battingInnings.length - dismissals;
    final batAverage   = dismissals == 0
        ? (batRuns > 0 ? batRuns.toDouble() : 0.0)
        : batRuns / dismissals;
    final batStrikeRate = batBalls == 0 ? 0.0 : (batRuns / batBalls) * 100;

    // ── Bowling averages ────────────────────────────────────────────────────
    final bowlEconomy  = bowlLegalBalls == 0
        ? 0.0
        : (bowlRunsConceded / bowlLegalBalls) * 6;
    final bowlOvers    = bowlLegalBalls ~/ 6;
    final bowlBalls    = bowlLegalBalls % 6;

    // Best bowling: innings with most wickets; if tie, fewest runs
    String bestBowling = '-';
    int bestW = 0;
    int bestR = 999;
    for (final fig in inningsBowling.values) {
      final w = fig['w']!;
      final r = fig['r']!;
      if (w > bestW || (w == bestW && w > 0 && r < bestR)) {
        bestW = w;
        bestR = r;
      }
    }
    if (bestW > 0) bestBowling = '$bestW/$bestR';

    return {
      // batting
      'batRuns':       batRuns,
      'batBalls':      batBalls,
      'batFours':      batFours,
      'batSixes':      batSixes,
      'batInnings':    battingInnings.length,
      'notOuts':       notOuts,
      'batAverage':    batAverage,
      'batStrikeRate': batStrikeRate,
      // bowling
      'bowlWickets':   bowlWickets,
      'bowlOvers':     bowlOvers,
      'bowlBalls':     bowlBalls,
      'bowlRunsConceded': bowlRunsConceded,
      'bowlEconomy':   bowlEconomy,
      'bestBowling':   bestBowling,
    };
  }

  /// Set target score for 2nd innings.
  Future<void> setTarget(int matchId, int target) async {
    final db = await database;
    await db.update(
      tableMatches,
      {colTarget: target, colSyncStatus: 0},
      where: '$colId = ?',
      whereArgs: [matchId],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TOURNAMENTS
  // ══════════════════════════════════════════════════════════════════════════

  /// Insert a new tournament and return its auto-generated id.
  ///
  /// Also seeds the [tournament_teams] table with one row per team in [teams].
  Future<int> insertTournament({
    required String name,
    required String format,
    required int oversPerMatch,
    required List<String> teams,
    String? createdBy,
  }) async {
    final db = await database;
    final id = await db.insert(
      tableTournaments,
      {
        colTournamentUuid: _uuid.v4(),
        colName:          name,
        colFormat:        format,
        colOversPerMatch: oversPerMatch,
        colTeams:         teams.join(','),  // kept for backwards compat
        colStatus:        'active',
        colCreatedAt:     DateTime.now().toIso8601String(),
        colCreatedBy:     createdBy,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Seed tournament_teams
    for (final team in teams) {
      if (team.trim().isEmpty) continue;
      await db.insert(
        tableTournamentTeams,
        {
          colTournamentId: id,
          colTeamName:     team.trim(),
          colIsEliminated: 0,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    return id;
  }

  /// Fetch all tournaments, newest first.
  Future<List<Map<String, dynamic>>> fetchAllTournaments() async {
    final db = await database;
    return db.query(tableTournaments, orderBy: '$colId DESC');
  }

  /// Fetch all tournaments created by [userId], newest first.
  Future<List<Map<String, dynamic>>> fetchTournamentsByCreator(String userId) async {
    final db = await database;
    return db.query(
      tableTournaments,
      where: '$colCreatedBy = ?',
      whereArgs: [userId],
      orderBy: '$colId DESC',
    );
  }

  /// Fetch a single tournament by id.
  Future<Map<String, dynamic>?> fetchTournament(int id) async {
    final db = await database;
    final rows = await db.query(
      tableTournaments,
      where: '$colId = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  /// Update tournament status ('active' | 'completed').
  Future<void> updateTournamentStatus(int id, String status) async {
    final db = await database;
    await db.update(
      tableTournaments,
      {colStatus: status},
      where: '$colId = ?',
      whereArgs: [id],
    );
  }

  /// Delete a tournament and all its associated matches.
  Future<void> deleteTournament(int id) async {
    final db = await database;
    await db.delete(tableMatches,          where: '$colTournamentId = ?', whereArgs: [id]);
    await db.delete(tableTournamentTeams,  where: '$colTournamentId = ?', whereArgs: [id]);
    await db.delete(tableTournaments,      where: '$colId = ?',           whereArgs: [id]);
  }

  /// Mark a tournament as completed.
  ///
  /// Looks for a completed match in this tournament with `match_stage = 'Final'`
  /// and returns its winner string.  If no Final match is found, still marks
  /// the tournament completed and returns null.
  Future<String?> concludeTournament(int tournamentId) async {
    final db = await database;

    // Find the Final match (if any)
    final finals = await db.query(
      tableMatches,
      where: '$colTournamentId = ? AND $colMatchStage = ? AND $colStatus = ?',
      whereArgs: [tournamentId, 'Final', 'completed'],
      orderBy: '$colId DESC',
      limit: 1,
    );

    String? winner;
    if (finals.isNotEmpty) {
      winner = finals.first[colWinner] as String?;
    }

    await db.update(
      tableTournaments,
      {colStatus: 'completed'},
      where: '$colId = ?',
      whereArgs: [tournamentId],
    );

    return winner;
  }

  // ── tournament_teams helpers ────────────────────────────────────────────────

  /// Return all active (non-eliminated) team names for a tournament.
  ///
  /// Falls back to the comma-separated [colTeams] string if the
  /// [tournament_teams] table has no rows for this tournament (e.g. created
  /// before v14).
  Future<List<String>> fetchActiveTeams(int tournamentId) async {
    final db = await database;
    final rows = await db.query(
      tableTournamentTeams,
      where: '$colTournamentId = ? AND $colIsEliminated = 0',
      whereArgs: [tournamentId],
      orderBy: '$colTeamName ASC',
    );

    if (rows.isNotEmpty) {
      return rows.map((r) => r[colTeamName] as String).toList();
    }

    // Fallback: parse the legacy comma-separated string
    final t = await fetchTournament(tournamentId);
    if (t == null) return [];
    final raw = (t[colTeams] as String?) ?? '';
    return raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }

  /// Return ALL team rows (active + eliminated) for a tournament.
  Future<List<Map<String, dynamic>>> fetchAllTournamentTeamRows(int tournamentId) async {
    final db = await database;
    return db.query(
      tableTournamentTeams,
      where: '$colTournamentId = ?',
      whereArgs: [tournamentId],
      orderBy: '$colTeamName ASC',
    );
  }

  /// Creates a brand-new team and immediately registers it in the given
  /// tournament, all within a single SQLite transaction.
  ///
  /// The new team is inserted into [tournament_teams] with [teamName].  The
  /// same name is stored in the legacy comma-separated [teams] column on the
  /// [tournaments] row so that existing code that reads the CSV column stays
  /// consistent.
  ///
  /// Returns the new [tournament_teams] row id.
  /// Throws a [StateError] if [teamName] (trimmed) is already registered in
  /// this tournament.
  Future<int> createTeamAndAddToTournament(
    int tournamentId,
    String teamName,
  ) async {
    final db = await database;
    final trimmed = teamName.trim();

    return db.transaction<int>((txn) async {
      // Guard: reject if already registered.
      final existing = await txn.query(
        tableTournamentTeams,
        columns: [colId],
        where: '$colTournamentId = ? AND $colTeamName = ?',
        whereArgs: [tournamentId, trimmed],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        throw StateError('"$trimmed" is already registered in this tournament.');
      }

      // 1) Insert into tournament_teams and capture the new row id.
      final teamRowId = await txn.insert(
        tableTournamentTeams,
        {
          colTournamentId: tournamentId,
          colTeamName:     trimmed,
          colIsEliminated: 0,
        },
      );

      // 2) Keep the legacy CSV `teams` column on the tournaments row in sync.
      final tournamentRows = await txn.query(
        tableTournaments,
        columns: [colTeams],
        where: '$colId = ?',
        whereArgs: [tournamentId],
        limit: 1,
      );
      if (tournamentRows.isNotEmpty) {
        final csv = (tournamentRows.first[colTeams] as String? ?? '').trim();
        final updated = csv.isEmpty ? trimmed : '$csv,$trimmed';
        await txn.update(
          tableTournaments,
          {colTeams: updated},
          where: '$colId = ?',
          whereArgs: [tournamentId],
        );
      }

      return teamRowId;
    });
  }

  /// Insert a late-entry team into [tournament_teams] for an ongoing tournament.
  ///
  /// Returns the new row id, or throws if the team already exists in this
  /// tournament (use [ConflictAlgorithm.ignore] to silently skip duplicates).
  Future<int> insertTeamIntoTournament(int tournamentId, String teamName) async {
    final db = await database;
    final id = await db.insert(
      tableTournamentTeams,
      {
        colTournamentId: tournamentId,
        colTeamName:     teamName.trim(),
        colIsEliminated: 0,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return id;
  }

  /// Mark a team as eliminated in [tournament_teams].
  ///
  /// [teamName] is matched case-sensitively (it should always come from the
  /// stored team name, not free-text input).
  Future<void> eliminateTeam(int tournamentId, String teamName) async {
    final db = await database;
    await db.update(
      tableTournamentTeams,
      {colIsEliminated: 1},
      where: '$colTournamentId = ? AND $colTeamName = ?',
      whereArgs: [tournamentId, teamName],
    );
  }

  /// Set [winner_team_id] on the tournament row and mark it completed.
  ///
  /// [winnerTeamName] is used to look up the team row in [tournament_teams].
  /// If no matching row is found the tournament is still marked completed and
  /// [winner_team_id] remains NULL.
  Future<void> completeTournamentWithWinner(
    int tournamentId,
    String winnerTeamName,
  ) async {
    final db = await database;

    // Resolve winner_team_id
    final teamRows = await db.query(
      tableTournamentTeams,
      columns: [colId],
      where: '$colTournamentId = ? AND $colTeamName = ?',
      whereArgs: [tournamentId, winnerTeamName],
      limit: 1,
    );
    final int? winnerTeamId =
        teamRows.isNotEmpty ? teamRows.first[colId] as int? : null;

    await db.update(
      tableTournaments,
      {
        colStatus:       'completed',
        colWinnerTeamId: winnerTeamId,
      },
      where: '$colId = ?',
      whereArgs: [tournamentId],
    );
  }

  /// Compute Player of the Tournament Series (POTS) stats across all completed
  /// matches in a tournament.
  ///
  /// Formula: score = (total_runs × 1) + (total_wickets × 20) + (caught × 10)
  ///
  /// Returns a list of maps sorted by score descending:
  ///   { 'playerId', 'playerName', 'avatarPath', 'score', 'runs', 'wickets', 'catches' }
  Future<List<Map<String, dynamic>>> computePots(int tournamentId) async {
    final db = DatabaseHelper.instance;

    final matches = await fetchMatchesByTournament(tournamentId);
    final completed = matches.where((m) => m[colStatus] == 'completed').toList();

    final Map<int, Map<String, int>> acc = {};

    for (final match in completed) {
      final matchId = match[colId] as int;
      final events  = await DatabaseHelper.instance.fetchBallEvents(matchId);

      for (final e in events) {
        final strikerId   = e[colStrikerId]  as int?;
        final bowlerId    = e[colBowlerId]   as int?;
        final runsScored  = (e[colRunsScored]  as int?) ?? 0;
        final extraType   = e[colExtraType]   as String?;
        final isWicket    = ((e[colIsWicket]   as int?) ?? 0) == 1;
        final wicketType  = e[colWicketType]  as String?;

        if (strikerId != null) {
          acc.putIfAbsent(strikerId, () => {'runs': 0, 'wickets': 0, 'catches': 0});
          if (extraType != 'bye' && extraType != 'leg_bye') {
            acc[strikerId]!['runs'] = acc[strikerId]!['runs']! + runsScored;
          }
        }

        if (bowlerId != null && isWicket && wicketType != 'run_out') {
          acc.putIfAbsent(bowlerId, () => {'runs': 0, 'wickets': 0, 'catches': 0});
          acc[bowlerId]!['wickets'] = acc[bowlerId]!['wickets']! + 1;
          if (wicketType == 'caught') {
            acc[bowlerId]!['catches'] = acc[bowlerId]!['catches']! + 1;
          }
        }
      }
    }

    // Build result list
    final List<Map<String, dynamic>> result = [];
    for (final entry in acc.entries) {
      final pid     = entry.key;
      final stats   = entry.value;
      final runs    = stats['runs']    ?? 0;
      final wickets = stats['wickets'] ?? 0;
      final catches = stats['catches'] ?? 0;
      final score   = runs * 1 + wickets * 20 + catches * 10;

      final player = await fetchPlayer(pid);
      result.add({
        'playerId':   pid,
        'playerName': (player?[colName] as String?) ?? 'Player $pid',
        'avatarPath': player?[colLocalAvatarPath] as String?,
        'score':      score,
        'runs':       runs,
        'wickets':    wickets,
        'catches':    catches,
      });
    }

    result.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));
    return result;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // DATABASE INITIALIZATION
  // ══════════════════════════════════════════════════════════════════════════

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path   = join(dbPath, _dbName);

    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // ── tournaments ────────────────────────────────────────────────────────
    await db.execute('''
       CREATE TABLE $tableTournaments (
         $colId            INTEGER PRIMARY KEY AUTOINCREMENT,
         $colTournamentUuid TEXT   NOT NULL UNIQUE DEFAULT '',
         $colName          TEXT    NOT NULL,
         $colFormat        TEXT    NOT NULL DEFAULT 'league',
         $colOversPerMatch INTEGER NOT NULL DEFAULT 20,
         $colTeams         TEXT    NOT NULL DEFAULT '',
         $colStatus        TEXT    NOT NULL DEFAULT 'active',
         $colCreatedAt     TEXT    NOT NULL,
         $colCreatedBy     TEXT,
         $colWinnerTeamId  INTEGER
       )
    ''');

    await db.execute('''
      CREATE TABLE $tableTournamentTeams (
        $colId            INTEGER PRIMARY KEY AUTOINCREMENT,
        $colTournamentId  INTEGER NOT NULL REFERENCES $tableTournaments($colId),
        $colTeamName      TEXT    NOT NULL,
        $colIsEliminated  INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableTeams (
        $colId         INTEGER PRIMARY KEY AUTOINCREMENT,
        $colTeamUuid   TEXT    NOT NULL UNIQUE DEFAULT '',
        $colName       TEXT    NOT NULL,
        $colSyncStatus INTEGER NOT NULL DEFAULT 0,
        $colCreatedAt  TEXT    NOT NULL,
        $colCreatedBy  TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableMatches (
        $colId              INTEGER PRIMARY KEY AUTOINCREMENT,
        $colUuid            TEXT    NOT NULL UNIQUE DEFAULT '',
        $colTeamA           TEXT    NOT NULL,
        $colTeamB           TEXT    NOT NULL,
        $colTeamAId         INTEGER REFERENCES $tableTeams($colId),
        $colTeamBId         INTEGER REFERENCES $tableTeams($colId),
        $colTotalOvers      INTEGER NOT NULL,
        $colTossWinner      TEXT,
        $colOptTo           TEXT,
        $colStatus          TEXT    NOT NULL DEFAULT 'pending',
        $colCurrentInnings  INTEGER NOT NULL DEFAULT 1,
        $colTarget          INTEGER,
        $colSyncStatus      INTEGER NOT NULL DEFAULT 0,
        $colCreatedAt       TEXT    NOT NULL,
        $colCreatedBy       TEXT,
        $colWinner          TEXT,
        $colMotmPlayerId    INTEGER,
        $colTournamentId    INTEGER REFERENCES $tableTournaments($colId),
        $colMatchStage      TEXT,
        $colSquadSize       INTEGER NOT NULL DEFAULT 11
      )
    ''');

    await db.execute('''
      CREATE TABLE $tablePlayers (
        $colId               INTEGER PRIMARY KEY AUTOINCREMENT,
        $colUuid             TEXT    NOT NULL UNIQUE DEFAULT '',
        $colName             TEXT    NOT NULL,
        $colTeam             TEXT    NOT NULL,
        $colTeamId           INTEGER REFERENCES $tableTeams($colId),
        $colRole             TEXT,
        $colBowlingType      TEXT,
        $colLocalAvatarPath  TEXT,
        $colSyncStatus       INTEGER NOT NULL DEFAULT 0,
        $colCreatedAt        TEXT    NOT NULL,
        $colCreatedBy        TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableMatchPlayers (
        $colId           INTEGER PRIMARY KEY AUTOINCREMENT,
        $colMatchId      INTEGER NOT NULL REFERENCES $tableMatches($colId),
        $colPlayerId     INTEGER NOT NULL REFERENCES $tablePlayers($colId),
        $colTeam         TEXT    NOT NULL,
        $colBattingOrder INTEGER,
        $colSyncStatus   INTEGER NOT NULL DEFAULT 0,
        $colCreatedBy    TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableBallEvents (
        $colId            INTEGER PRIMARY KEY AUTOINCREMENT,
        $colMatchId       INTEGER NOT NULL REFERENCES $tableMatches($colId),
        $colInnings       INTEGER NOT NULL DEFAULT 1,
        $colOverNum       INTEGER NOT NULL,
        $colBallNum       INTEGER NOT NULL,
        $colRunsScored    INTEGER NOT NULL DEFAULT 0,
        $colIsBoundary    INTEGER NOT NULL DEFAULT 0,
        $colIsWicket      INTEGER NOT NULL DEFAULT 0,
        $colWicketType    TEXT,
        $colExtraType     TEXT,
        $colExtraRuns     INTEGER NOT NULL DEFAULT 0,
        $colStrikerId     INTEGER,
        $colNonStrikerId  INTEGER,
        $colBowlerId      INTEGER,
        $colOutPlayerId   INTEGER,
        $colSyncStatus    INTEGER NOT NULL DEFAULT 0,
        $colCreatedAt     TEXT    NOT NULL,
        $colCreatedBy     TEXT
      )
    ''');

    // Create indexes for better query performance
    await db.execute('''
      CREATE INDEX idx_ball_events_match ON $tableBallEvents($colMatchId)
    ''');
    
    await db.execute('''
      CREATE INDEX idx_ball_events_match_innings
        ON $tableBallEvents($colMatchId, $colInnings)
    ''');
    
    await db.execute('''
      CREATE INDEX idx_ball_events_sync ON $tableBallEvents($colSyncStatus)
    ''');
    
    await db.execute('''
      CREATE INDEX idx_matches_sync ON $tableMatches($colSyncStatus)
    ''');

    await db.execute('''
      CREATE INDEX idx_players_team ON $tablePlayers($colTeam)
    ''');

    await db.execute('''
      CREATE INDEX idx_match_players_match ON $tableMatchPlayers($colMatchId)
    ''');

    await db.execute('''
      CREATE INDEX idx_matches_tournament ON $tableMatches($colTournamentId)
    ''');

    // Unique indexes on uuid so INSERT OR REPLACE deduplicates by UUID.
    await db.execute('''
      CREATE UNIQUE INDEX idx_matches_uuid
        ON $tableMatches($colUuid)
        WHERE $colUuid != ''
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX idx_players_uuid
        ON $tablePlayers($colUuid)
        WHERE $colUuid != ''
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Handle migrations here
    if (oldVersion < 3) {
      // Migration to v3 - add players tables and new ball_events columns
      // Drop and recreate for clean schema (development phase)
      await db.execute('DROP TABLE IF EXISTS $tableBallEvents');
      await db.execute('DROP TABLE IF EXISTS $tableMatchPlayers');
      await db.execute('DROP TABLE IF EXISTS $tablePlayers');
      await db.execute('DROP TABLE IF EXISTS $tableMatches');
      await _onCreate(db, newVersion);
    } else if (oldVersion < 4) {
      // Migration to v4 - add created_by column to all tables
      await db.execute('ALTER TABLE $tableMatches ADD COLUMN $colCreatedBy TEXT');
      await db.execute('ALTER TABLE $tablePlayers ADD COLUMN $colCreatedBy TEXT');
      await db.execute('ALTER TABLE $tableMatchPlayers ADD COLUMN $colCreatedBy TEXT');
      await db.execute('ALTER TABLE $tableBallEvents ADD COLUMN $colCreatedBy TEXT');
    }
    
    if (oldVersion < 5) {
      // Migration to v5 — tournament_name column was added here historically.
      // In v17 this column is removed; this block intentionally left empty so
      // the version-sequence is preserved for devices upgrading from v4.
    }
    
    if (oldVersion < 6) {
      // Migration to v6 - add role column to players
      await db.execute('ALTER TABLE $tablePlayers ADD COLUMN $colRole TEXT');
    }
    
    if (oldVersion < 7) {
      // Migration to v7 - add local_avatar_path column to players
      await db.execute(
        'ALTER TABLE $tablePlayers ADD COLUMN $colLocalAvatarPath TEXT',
      );
    }

    if (oldVersion < 8) {
      // Migration to v8 - add winner column to matches
      await db.execute('ALTER TABLE $tableMatches ADD COLUMN $colWinner TEXT');
    }

    if (oldVersion < 9) {
      // Migration to v9 — add uuid column to matches and players so we can
      // push proper UUID strings to Supabase instead of SQLite integer IDs.
      // Existing rows get a freshly generated UUID so they can be re-synced.
      await db.execute(
        'ALTER TABLE $tableMatches ADD COLUMN $colUuid TEXT NOT NULL DEFAULT \'\'',
      );
      await db.execute(
        'ALTER TABLE $tablePlayers ADD COLUMN $colUuid TEXT NOT NULL DEFAULT \'\'',
      );
      // Back-fill UUIDs for any rows that already exist and reset sync_status
      // to 0 so the new UUIDs are pushed to Supabase on the next sync run.
      // Without this, ball_events for these matches would be sent with a UUID
      // that Supabase has never seen, causing FK violation 23503.
      final matches = await db.query(tableMatches, columns: [colId]);
      for (final m in matches) {
        await db.update(
          tableMatches,
          {colUuid: _uuid.v4(), colSyncStatus: 0},
          where: '$colId = ?',
          whereArgs: [m[colId]],
        );
      }
      final players = await db.query(tablePlayers, columns: [colId]);
      for (final p in players) {
        await db.update(
          tablePlayers,
          {colUuid: _uuid.v4(), colSyncStatus: 0},
          where: '$colId = ?',
          whereArgs: [p[colId]],
        );
      }
    }

    if (oldVersion < 10) {
      // Migration to v10 — add tournaments table and tournament_id FK on matches.
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tableTournaments (
          $colId            INTEGER PRIMARY KEY AUTOINCREMENT,
          $colName          TEXT    NOT NULL,
          $colFormat        TEXT    NOT NULL DEFAULT 'league',
          $colOversPerMatch INTEGER NOT NULL DEFAULT 20,
          $colTeams         TEXT    NOT NULL DEFAULT '',
          $colStatus        TEXT    NOT NULL DEFAULT 'active',
          $colCreatedAt     TEXT    NOT NULL,
          $colCreatedBy     TEXT
        )
      ''');
      await db.execute(
        'ALTER TABLE $tableMatches ADD COLUMN $colTournamentId INTEGER',
      );
    }

    if (oldVersion < 11) {
      // Migration to v11 — add match_stage column to matches.
      // Stores the knockout stage: 'Group Stage', 'Quarter-Final',
      // 'Semi-Final', 'Final'.  NULL for standalone / quick matches and
      // for tournament matches that were created before this version.
      await db.execute(
        'ALTER TABLE $tableMatches ADD COLUMN $colMatchStage TEXT',
      );
    }

    if (oldVersion < 12) {
      // Migration to v12 — add motm_player_id column to matches.
      // Stores the SQLite player id of the Man of the Match.
      // NULL until the match is completed and MOTM is computed.
      await db.execute(
        'ALTER TABLE $tableMatches ADD COLUMN $colMotmPlayerId INTEGER',
      );
    }

    if (oldVersion < 13) {
      // Migration to v13 — add squad_size column to matches.
      // Determines the wicket limit (squad_size - 1).  Default 11 keeps
      // existing matches compatible with the previous hardcoded limit of 10.
      await db.execute(
        'ALTER TABLE $tableMatches ADD COLUMN $colSquadSize INTEGER NOT NULL DEFAULT 11',
      );
    }

    if (oldVersion < 14) {
      // Migration to v14 — add winner_team_id to tournaments and create the
      // new tournament_teams table.
      await db.execute(
        'ALTER TABLE $tableTournaments ADD COLUMN $colWinnerTeamId INTEGER',
      );
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tableTournamentTeams (
          $colId            INTEGER PRIMARY KEY AUTOINCREMENT,
          $colTournamentId  INTEGER NOT NULL REFERENCES $tableTournaments($colId),
          $colTeamName      TEXT    NOT NULL,
          $colIsEliminated  INTEGER NOT NULL DEFAULT 0
        )
      ''');

      // Back-fill tournament_teams for any existing tournament rows so that
      // the new fetchActiveTeams() method works on already-created tournaments.
      final existingTournaments = await db.query(
        tableTournaments,
        columns: [colId, colTeams],
      );
      for (final row in existingTournaments) {
        final tid  = row[colId] as int;
        final raw  = (row[colTeams] as String?) ?? '';
        final teams = raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty);
        for (final teamName in teams) {
          await db.insert(
            tableTournamentTeams,
            {
              colTournamentId: tid,
              colTeamName:     teamName,
              colIsEliminated: 0,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_tournament_teams_tournament
          ON $tableTournamentTeams($colTournamentId)
      ''');
    }

    if (oldVersion < 15) {
      // Migration to v15 — enforce UNIQUE on matches.uuid and players.uuid so
      // that INSERT OR REPLACE correctly replaces an existing row by its UUID
      // rather than appending a duplicate.
      //
      // SQLite does not support ADD CONSTRAINT on existing tables.  The
      // standard workaround is to create a unique index — SQLite treats a
      // unique index exactly like a UNIQUE column constraint for the purpose
      // of conflict resolution (including REPLACE semantics).
      //
      // Step 1: delete duplicate rows, keeping only the highest id per uuid.
      //   This must happen BEFORE the index is created, otherwise the CREATE
      //   UNIQUE INDEX statement itself would fail.
      await db.execute('''
        DELETE FROM $tableMatches
        WHERE $colId NOT IN (
          SELECT MAX($colId) FROM $tableMatches
          WHERE $colUuid != ''
          GROUP BY $colUuid
        ) AND $colUuid != ''
      ''');
      await db.execute('''
        DELETE FROM $tablePlayers
        WHERE $colId NOT IN (
          SELECT MAX($colId) FROM $tablePlayers
          WHERE $colUuid != ''
          GROUP BY $colUuid
        ) AND $colUuid != ''
      ''');

      // Step 2: create the unique indexes.
      await db.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS idx_matches_uuid
          ON $tableMatches($colUuid)
          WHERE $colUuid != ''
      ''');
      await db.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS idx_players_uuid
          ON $tablePlayers($colUuid)
          WHERE $colUuid != ''
      ''');
    }

    if (oldVersion < 16) {
      // Migration to v16 — add uuid column to tournaments so they can be
      // synced to / from Supabase.  Existing rows receive a freshly generated
      // UUID so they are pushed to Supabase on the next sync run.
      await db.execute(
        'ALTER TABLE $tableTournaments ADD COLUMN $colTournamentUuid TEXT NOT NULL DEFAULT \'\'',
      );
      // Back-fill UUIDs for existing tournament rows.
      final tournaments = await db.query(tableTournaments, columns: [colId]);
      for (final t in tournaments) {
        await db.update(
          tableTournaments,
          {colTournamentUuid: _uuid.v4()},
          where: '$colId = ?',
          whereArgs: [t[colId]],
        );
      }
      // Create a unique index so INSERT OR REPLACE resolves by UUID.
      await db.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS idx_tournaments_uuid
          ON $tableTournaments($colTournamentUuid)
          WHERE $colTournamentUuid != ''
      ''');
    }

    if (oldVersion < 17) {
      // Migration to v17 — retire the tournament_name TEXT column on matches.
      //
      // SQLite does not support DROP COLUMN on the versions typically bundled
      // with Android/iOS.  The column is left in place on existing installs —
      // it is simply no longer written to or read from application code.
      // New installs (created by _onCreate at v17+) never have this column.
      //
      // The colTournamentId INTEGER FK (added in v10) remains the sole link
      // between a match and its tournament.  Tournament names are now resolved
      // at query time via a JOIN on the tournaments table.
      //
      // No ALTER statements needed — the schema change is purely application-
      // level (stop reading/writing colTournamentName everywhere in Dart code).
    }

    if (oldVersion < 18) {
      // Migration to v18 — add a composite index on ball_events(match_id, innings).
      //
      // Nearly every ball-event query filters on BOTH match_id AND innings
      // (e.g. getInningsSummary, fetchBallEvents with innings filter,
      // getWicketEvents).  The existing single-column idx_ball_events_match
      // index helps for match_id-only scans but leaves the secondary innings
      // predicate to be evaluated row-by-row.  A covering composite index
      // eliminates that extra scan and also orders results by innings, which
      // matches the ORDER BY clause in fetchBallEvents.
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_ball_events_match_innings
          ON $tableBallEvents($colMatchId, $colInnings)
      ''');
    }

    if (oldVersion < 19) {
      // Migration to v19 — add bowling_type column to players table.
      // Nullable TEXT; valid values are 'Fast' and 'Spin'.
      // Only relevant when role is 'bowler' or 'all-rounder'.
      await db.execute(
        'ALTER TABLE $tablePlayers ADD COLUMN $colBowlingType TEXT',
      );
    }

    if (oldVersion < 20) {
      // Migration to v20 — add dedicated teams table for team management.
      // Previously teams were only TEXT strings in players.team / matches.team_a/b.
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tableTeams (
          $colId         INTEGER PRIMARY KEY AUTOINCREMENT,
          $colTeamUuid   TEXT    NOT NULL UNIQUE DEFAULT '',
          $colName       TEXT    NOT NULL,
          $colSyncStatus INTEGER NOT NULL DEFAULT 0,
          $colCreatedAt  TEXT    NOT NULL,
          $colCreatedBy  TEXT
        )
      ''');
    }

    if (oldVersion < 21) {
      // Migration to v21 — add relational FK columns.
      //   matches.team_a_id  → teams(id)
      //   matches.team_b_id  → teams(id)
      //   players.team_id    → teams(id)
      // SQLite does not support adding FK constraints via ALTER TABLE, so the
      // columns are added as plain INTEGER columns (FK enforcement is
      // application-level here, same as the rest of this schema).
      await db.execute(
        'ALTER TABLE $tableMatches ADD COLUMN $colTeamAId INTEGER',
      );
      await db.execute(
        'ALTER TABLE $tableMatches ADD COLUMN $colTeamBId INTEGER',
      );
      await db.execute(
        'ALTER TABLE $tablePlayers ADD COLUMN $colTeamId INTEGER',
      );
      // Add an index on players.team_id for fast roster lookups.
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_players_team_id
          ON $tablePlayers($colTeamId)
      ''');
    }

    if (oldVersion < 22) {
      // Migration to v22 — deduplicate ball_events rows created by
      // syncDownInitialData blindly inserting without deleting existing rows.
      //
      // Two rows are considered duplicates when they share the same
      // (match_id, innings, over_number, ball_number, runs_scored, extra_type,
      //  extra_runs, is_wicket, sync_status = 1).  We keep the row with the
      // highest id (most recently inserted) and delete the rest.
      //
      // Only sync_status = 1 rows (pulled from Supabase) can be duplicated by
      // the down-sync.  Locally-created rows (sync_status = 0) are untouched.
      await db.execute('''
        DELETE FROM $tableBallEvents
        WHERE $colSyncStatus = 1
          AND $colId NOT IN (
            SELECT MAX($colId)
            FROM $tableBallEvents
            WHERE $colSyncStatus = 1
            GROUP BY $colMatchId, $colInnings, $colOverNum, $colBallNum,
                     $colRunsScored, $colExtraType, $colExtraRuns, $colIsWicket
          )
      ''');
    }

    // Ensure performance indexes exist for all upgrade paths (v3–v13).
    // These were only created in _onCreate, so devices that upgraded from
    // v3–v6 never got them. Using IF NOT EXISTS is safe for fresh installs too.
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_ball_events_match
        ON $tableBallEvents($colMatchId)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_ball_events_sync
        ON $tableBallEvents($colSyncStatus)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_matches_sync
        ON $tableMatches($colSyncStatus)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_players_team
        ON $tablePlayers($colTeam)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_match_players_match
        ON $tableMatchPlayers($colMatchId)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_matches_tournament
        ON $tableMatches($colTournamentId)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_tournament_teams_tournament
        ON $tableTournamentTeams($colTournamentId)
    ''');
  }
}
