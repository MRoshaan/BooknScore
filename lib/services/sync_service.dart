import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'database_helper.dart';
import 'auth_service.dart';

/// Sync status enum for tracking sync state
enum SyncState {
  idle,
  syncing,
  synced,
  error,
  offline,
}

/// Result of a sync operation
class SyncResult {
  final int matchesSynced;
  final int playersSynced;
  final int ballEventsSynced;
  final List<String> errors;

  SyncResult({
    this.matchesSynced = 0,
    this.playersSynced = 0,
    this.ballEventsSynced = 0,
    this.errors = const [],
  });

  int get totalSynced =>
      matchesSynced + playersSynced + ballEventsSynced;

  bool get hasErrors => errors.isNotEmpty;
}

/// Supabase sync service for offline-first data synchronization.
///
/// Design decisions for battery & data efficiency:
/// - [scheduleDebouncedSync]: debounces rapid consecutive calls (e.g., every
///   ball bowled) into a single network round-trip after a 5-second quiet
///   period.  This replaces the previous pattern of calling [syncAll] on every
///   ball, which caused a network request for every delivery.
/// - [syncAll]: uses Supabase `upsert` so a record that was partially synced
///   before (e.g., due to a timeout) is safely updated rather than causing a
///   duplicate-key error.
/// - Connectivity failures are handled gracefully: the service transitions to
///   [SyncState.offline] and queues a single auto-sync when connectivity
///   returns. There are no retry loops.
class SyncService extends ChangeNotifier {
  SyncService._();
  static final SyncService instance = SyncService._();

  // Factory constructor to return singleton (for Provider compatibility)
  factory SyncService() => instance;

  final _db = DatabaseHelper.instance;
  final _connectivity = Connectivity();

  // Supabase client
  SupabaseClient get _supabase => Supabase.instance.client;

  // Sync state
  SyncState _state = SyncState.idle;
  SyncState get state => _state;

  String? _lastError;
  String? get lastError => _lastError;

  DateTime? _lastSyncTime;
  DateTime? get lastSyncTime => _lastSyncTime;

  // Connectivity stream subscription
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  // Sync status broadcast stream
  final _syncStatusController = StreamController<SyncState>.broadcast();
  Stream<SyncState> get syncStatusStream => _syncStatusController.stream;

  // ── Debounce ────────────────────────────────────────────────────────────
  // Prevents a sync call on every single ball bowled.
  // Instead, multiple rapid calls are collapsed into one sync after a quiet
  // period of [_debounceDuration].
  static const _debounceDuration = Duration(seconds: 5);
  Timer? _debounceTimer;

  // Guard against overlapping sync runs
  bool _isSyncing = false;

  // ══════════════════════════════════════════════════════════════════════════
  // INITIALIZATION
  // ══════════════════════════════════════════════════════════════════════════

  /// Initialize the sync service and start listening for connectivity changes.
  Future<void> initialize() async {
    // Check initial connectivity
    await _checkConnectivity();

    // Listen for connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      (results) async {
        final isOnline = results.any((r) => r != ConnectivityResult.none);
        if (isOnline && _state == SyncState.offline) {
          _setState(SyncState.idle);
          // Auto-sync once when connectivity is restored.
          // Use debounce so rapid reconnect events don't spam the server.
          scheduleDebouncedSync();
        } else if (!isOnline) {
          // Cancel any pending debounced sync — no point trying while offline.
          _debounceTimer?.cancel();
          _setState(SyncState.offline);
        }
      },
      onError: (Object err) {
        developer.log(
          'Connectivity stream error',
          name: 'SyncService',
          error: err,
          level: 900,
        );
      },
    );
  }

  /// Dispose resources.
  @override
  void dispose() {
    _debounceTimer?.cancel();
    _connectivitySubscription?.cancel();
    _syncStatusController.close();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // DEBOUNCED SYNC
  // ══════════════════════════════════════════════════════════════════════════

  /// Schedule a sync to run after [_debounceDuration] of inactivity.
  ///
  /// Call this instead of [syncAll] for high-frequency triggers (e.g., after
  /// every ball is bowled).  Multiple calls within the debounce window are
  /// collapsed into a single sync.
  void scheduleDebouncedSync() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () async {
      // Skip if already running (prevents queueing a second sync while one is
      // in progress when the timer fires multiple times).
      if (!_isSyncing) {
        await syncAll();
      }
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CONNECTIVITY
  // ══════════════════════════════════════════════════════════════════════════

  /// Check current connectivity status.
  Future<bool> checkConnectivity() async {
    return _checkConnectivity();
  }

  Future<bool> _checkConnectivity() async {
    try {
      final results = await _connectivity.checkConnectivity();
      final isOnline = results.any((r) => r != ConnectivityResult.none);

      if (!isOnline) {
        _setState(SyncState.offline);
      } else if (_state == SyncState.offline) {
        _setState(SyncState.idle);
      }

      return isOnline;
    } catch (e, st) {
      developer.log(
        'Connectivity check failed',
        name: 'SyncService',
        error: e,
        stackTrace: st,
        level: 900,
      );
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SYNC ALL
  // ══════════════════════════════════════════════════════════════════════════

  /// Sync all unsynced data to Supabase.
  ///
  /// This is a single-shot operation; it does NOT retry on failure.  Call
  /// [scheduleDebouncedSync] for fire-and-forget usage.
  Future<SyncResult> syncAll() async {
    // Prevent concurrent sync runs
    if (_isSyncing) {
      developer.log('syncAll: skipped — sync already in progress', name: 'SyncService');
      return SyncResult();
    }

    // Check if user is authenticated
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) {
      developer.log('syncAll: aborted — user not authenticated', name: 'SyncService', level: 800);
      _lastError = 'User not authenticated';
      _setState(SyncState.error);
      return SyncResult(errors: ['User not authenticated']);
    }

    // Check connectivity
    final isOnline = await _checkConnectivity();
    if (!isOnline) {
      developer.log('syncAll: aborted — device offline', name: 'SyncService');
      return SyncResult(errors: ['No internet connection']);
    }

    _isSyncing = true;
    developer.log('syncAll: starting — user=$userId', name: 'SyncService');
    _setState(SyncState.syncing);
    final errors = <String>[];

    int matchesSynced = 0;
    int playersSynced = 0;
    int ballEventsSynced = 0;

    try {
      // Log pending counts before syncing
      final db = await _db.database;
      final unsyncedPlayers =
          (await db.query(DatabaseHelper.tablePlayers, where: '${DatabaseHelper.colSyncStatus} = 0')).length;
      final totalPlayers =
          (await db.query(DatabaseHelper.tablePlayers)).length;
      final unsyncedMatches =
          (await db.query(DatabaseHelper.tableMatches, where: '${DatabaseHelper.colSyncStatus} = 0')).length;
      final unsyncedBallEvents =
          (await db.query(DatabaseHelper.tableBallEvents, where: '${DatabaseHelper.colSyncStatus} = 0')).length;

      developer.log(
        'syncAll: pending — matches=$unsyncedMatches '
        'players_unsynced=$unsyncedPlayers players_total=$totalPlayers '
        'ball_events=$unsyncedBallEvents',
        name: 'SyncService',
      );

      // Sync in strict dependency order:
      //   1. players  (no FK dependencies)
      //   2. matches  (depends on players only)
      //   3. ball_events  (FK on matches — MUST wait for matches to land first)
      //
      // _syncMatches returns the set of match UUIDs that were confirmed written
      // to Supabase.  That set is passed directly into _syncBallEvents so it
      // can gate each event against it and avoid FK violations (code 23503).
      playersSynced = await _syncPlayers(errors);
      final matchResult = await _syncMatches(errors);
      matchesSynced = matchResult.count;
      ballEventsSynced = await _syncBallEvents(errors, matchResult.syncedUuids);

      _lastSyncTime = DateTime.now();

      if (errors.isEmpty) {
        developer.log(
          'syncAll: completed successfully — '
          'total=${playersSynced + matchesSynced + ballEventsSynced}',
          name: 'SyncService',
        );
        _setState(SyncState.synced);
      } else {
        developer.log(
          'syncAll: completed with ${errors.length} error(s)',
          name: 'SyncService',
          level: 900,
        );
        _setState(SyncState.error);
      }
    } catch (e, st) {
      final msg = 'syncAll: unexpected failure — $e';
      print('SYNC ERROR (syncAll): $e');
      developer.log(msg, name: 'SyncService', error: e, stackTrace: st, level: 1000);
      errors.add('Sync failed: $e');
      _lastError = e.toString();
      _setState(SyncState.error);
    } finally {
      _isSyncing = false;
    }

    return SyncResult(
      matchesSynced: matchesSynced,
      playersSynced: playersSynced,
      ballEventsSynced: ballEventsSynced,
      errors: errors,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SYNC INDIVIDUAL TABLES
  // ══════════════════════════════════════════════════════════════════════════

  /// Sync ALL local players to Supabase in a single batch upsert.
  ///
  /// Why ALL players (not just sync_status = 0):
  /// The web dashboard shows "Unknown Player" when a player exists locally but
  /// is absent from the Supabase `players` table.  This can happen whenever:
  ///   - a player was created before cloud sync was set up,
  ///   - the remote row was deleted while the local flag remained sync_status=1,
  ///   - the app was reinstalled / DB migrated and sync flags were reset.
  ///
  /// By upserting every player on every sync we guarantee the cloud is always
  /// a superset of the local roster.  The `id` (UUID) is included in the
  /// payload so Supabase can match on its primary key and update existing rows
  /// rather than inserting duplicates.  `ignoreDuplicates: false` ensures that
  /// name / team / role changes are propagated to Supabase.
  ///
  /// Only players with sync_status = 0 are marked as synced locally after a
  /// successful upsert; already-synced players incur no extra DB write.
  Future<int> _syncPlayers(List<String> errors) async {
    int synced = 0;

    try {
      final db = await _db.database;

      // Fetch ALL players so that players which were created before sync was
      // enabled (or whose remote row was silently missing) are pushed to
      // Supabase.  We still track which ones need their local flag updated.
      final allPlayers = await db.query(DatabaseHelper.tablePlayers);

      if (allPlayers.isEmpty) return 0;

      // Collect all avatar uploads first, then batch-upsert player rows.
      final payloads  = <Map<String, dynamic>>[];
      final unsyncedIds = <int>[];   // only sync_status=0 rows need marking

      for (final player in allPlayers) {
        final playerId   = player[DatabaseHelper.colId]   as int;
        final playerUuid = player[DatabaseHelper.colUuid] as String;
        final localAvatarPath = player[DatabaseHelper.colLocalAvatarPath] as String?;

        // Upload avatar to Supabase Storage if a local file exists.
        String? avatarUrl;
        if (localAvatarPath != null && localAvatarPath.isNotEmpty) {
          try {
            final file = File(localAvatarPath);
            if (await file.exists()) {
              final timestamp = DateTime.now().millisecondsSinceEpoch;
              final storagePath = 'avatars/${playerId}_$timestamp.jpg';
              await _supabase.storage.from('avatars').upload(
                storagePath,
                file,
                fileOptions: const FileOptions(
                  contentType: 'image/jpeg',
                  upsert: true,
                ),
              );
              avatarUrl = _supabase.storage.from('avatars').getPublicUrl(storagePath);
            }
          } catch (e, st) {
            // Avatar upload failure is non-fatal; log and continue.
            developer.log(
              'Avatar upload failed for player id=$playerId',
              name: 'SyncService',
              error: e,
              stackTrace: st,
              level: 800,
            );
          }
        }

        // Include 'id' (UUID) so Supabase can upsert on the primary key —
        // without it every call would insert a new row and throw a duplicate.
        payloads.add(<String, dynamic>{
          'id':         playerUuid,
          'name':       player[DatabaseHelper.colName],
          'team':       player[DatabaseHelper.colTeam],
          'role':       player[DatabaseHelper.colRole],
          'avatar_url': avatarUrl,
        });

        if ((player[DatabaseHelper.colSyncStatus] as int) == 0) {
          unsyncedIds.add(playerId);
        }
      }

      // Batch upsert — one round-trip for all players.
      // ignoreDuplicates: false ensures that updates to name/team/role on rows
      // that already exist in Supabase are applied rather than silently skipped.
      try {
        await _supabase.from('players').upsert(payloads, ignoreDuplicates: false);
        developer.log(
          'Batch upserted ${payloads.length} player(s) '
          '(${unsyncedIds.length} newly synced)',
          name: 'SyncService',
        );

        // Only update local sync_status for rows that were previously unsynced.
        if (unsyncedIds.isNotEmpty) {
          final db2 = await _db.database;
          await db2.transaction((txn) async {
            for (final id in unsyncedIds) {
              await txn.update(
                DatabaseHelper.tablePlayers,
                {DatabaseHelper.colSyncStatus: 1},
                where: '${DatabaseHelper.colId} = ?',
                whereArgs: [id],
              );
            }
          });
        }
        synced = unsyncedIds.length;
      } on PostgrestException catch (e, st) {
        print('SYNC ERROR (players upsert): $e | details: ${e.details} | hint: ${e.hint} | code: ${e.code}');
        developer.log(
          'Batch upsert failed for players',
          name: 'SyncService',
          error: e,
          stackTrace: st,
          level: 1000,
        );
        errors.add('Failed to batch-sync players: ${e.message}');
      }
    } catch (e, st) {
      print('SYNC ERROR (players fetch): $e');
      developer.log(
        'Failed to fetch players for sync',
        name: 'SyncService',
        error: e,
        stackTrace: st,
        level: 1000,
      );
      errors.add('Failed to fetch players for sync: $e');
    }

    return synced;
  }

  /// Sync unsynced matches to Supabase in a single batch upsert.
  ///
  /// Returns a record with:
  /// - [count]       : number of matches successfully written to Supabase.
  /// - [syncedUuids] : the set of match UUIDs that were confirmed synced.
  ///                   Only UUIDs present in this set are safe to reference as
  ///                   foreign keys in subsequent ball_events / match_summaries
  ///                   upserts.  If the upsert throws, the set will be empty so
  ///                   dependent tables are automatically skipped.
  Future<({int count, Set<String> syncedUuids})> _syncMatches(List<String> errors) async {
    try {
      final db = await _db.database;

      // Always load the full set of UUIDs that are already confirmed in Supabase
      // (sync_status = 1).  These are included in the returned set so that
      // _syncBallEvents can safely reference them without relying on the
      // potentially-stale matchSyncedMap local flag.
      final alreadySyncedRows = await db.query(
        DatabaseHelper.tableMatches,
        columns: [DatabaseHelper.colUuid],
        where: '${DatabaseHelper.colSyncStatus} = 1',
      );
      final alreadySyncedUuids =
          alreadySyncedRows.map((r) => r[DatabaseHelper.colUuid] as String).toSet();

      final unsynced = await _db.fetchUnsyncedMatches();
      if (unsynced.isEmpty) {
        // Nothing new to push, but return the already-confirmed set so that
        // _syncBallEvents is not blocked on matches that are already in Supabase.
        return (count: 0, syncedUuids: alreadySyncedUuids);
      }

      final payloads  = <Map<String, dynamic>>[];
      final syncedIds = <int>[];
      final uuids     = <String>[];

      for (final match in unsynced) {
        final matchId   = match[DatabaseHelper.colId]   as int;
        final matchUuid = match[DatabaseHelper.colUuid] as String;

        // Resolve MOTM: local DB stores the SQLite player id; Supabase needs
        // the player's UUID string (players.uuid) so FK is satisfied.
        final motmLocalId = match[DatabaseHelper.colMotmPlayerId] as int?;
        String? motmPlayerUuid;
        if (motmLocalId != null) {
          final playerRow = await _db.fetchPlayer(motmLocalId);
          motmPlayerUuid = playerRow?[DatabaseHelper.colUuid] as String?;
          if (motmPlayerUuid != null && motmPlayerUuid.isEmpty) {
            motmPlayerUuid = null; // treat blank UUID as absent
          }
        }

        payloads.add({
          'id':              matchUuid,                               // UUID string as Supabase PK
          'team_a':          match[DatabaseHelper.colTeamA],
          'team_b':          match[DatabaseHelper.colTeamB],
          'overs':           match[DatabaseHelper.colTotalOvers], // total_overs → overs
          'toss_winner':     match[DatabaseHelper.colTossWinner],
          'toss_decision':   match[DatabaseHelper.colOptTo],       // opt_to → toss_decision
          'status':          match[DatabaseHelper.colStatus],
          'tournament_name': match[DatabaseHelper.colTournamentName],
          'winner':          match[DatabaseHelper.colWinner],
          'created_by':      match[DatabaseHelper.colCreatedBy],  // required by RLS / NOT NULL constraint
          'motm_player_id':  motmPlayerUuid,                      // NULL until match completes
        });
        syncedIds.add(matchId);
        uuids.add(matchUuid);
      }

      try {
        // ignoreDuplicates: false so updates to status/winner on rows that
        // already exist in Supabase are applied (not silently skipped).
        // IMPORTANT: await is required — ball_events must NOT be sent until
        // this call completes successfully so FK constraints are satisfied.
        await _supabase.from('matches').upsert(payloads, ignoreDuplicates: false);
        developer.log('Batch upserted ${payloads.length} match(es)', name: 'SyncService');

        await db.transaction((txn) async {
          for (final id in syncedIds) {
            await txn.update(
              DatabaseHelper.tableMatches,
              {DatabaseHelper.colSyncStatus: 1},
              where: '${DatabaseHelper.colId} = ?',
              whereArgs: [id],
            );
          }
        });

        // Return the union of newly-synced UUIDs and already-synced UUIDs so
        // _syncBallEvents has the complete set of match UUIDs confirmed present
        // in Supabase this run.
        return (count: syncedIds.length, syncedUuids: {...alreadySyncedUuids, ...uuids});
      } on PostgrestException catch (e, st) {
        print('SYNC ERROR (matches upsert): $e | details: ${e.details} | hint: ${e.hint} | code: ${e.code}');
        developer.log(
          'Batch upsert failed for matches — only previously-confirmed matches '
          'will be allowed through to ball_events sync to prevent FK violations',
          name: 'SyncService',
          error: e,
          stackTrace: st,
          level: 1000,
        );
        errors.add('Failed to batch-sync matches: ${e.message}');
        // The new upsert failed, so only previously-confirmed UUIDs are safe.
        // The failed match rows remain sync_status=0 and will be retried.
        return (count: 0, syncedUuids: alreadySyncedUuids);
      }
    } catch (e, st) {
      print('SYNC ERROR (matches fetch): $e');
      developer.log(
        'Failed to fetch unsynced matches',
        name: 'SyncService',
        error: e,
        stackTrace: st,
        level: 1000,
      );
      errors.add('Failed to fetch unsynced matches: $e');
      return (count: 0, syncedUuids: <String>{});
    }
  }

  /// Sync unsynced ball_events to Supabase in chunks of 200.
  ///
  /// [confirmedMatchUuids] must be the set of match UUIDs that were
  /// successfully upserted to Supabase in the *same* sync run (returned by
  /// [_syncMatches]).  Ball events whose parent match UUID is NOT in this set
  /// are skipped to prevent FK (23503) violations.  They remain unsynced
  /// locally and will be retried on the next sync once the parent match lands.
  ///
  /// Additionally, every match that already has `sync_status = 1` in the local
  /// DB is assumed to be present in Supabase (it was synced in a previous run),
  /// so its balls are also safe to send.
  Future<int> _syncBallEvents(
    List<String> errors,
    Set<String> confirmedMatchUuids,
  ) async {
    int synced = 0;

    try {
      final unsynced = await _db.fetchUnsyncedBallEvents();
      if (unsynced.isEmpty) return 0;

      final db = await _db.database;

      // ── Pre-load UUID look-up caches ──────────────────────────────────────
      // Build match_id (int) → uuid (String) map for all matches referenced.
      final matchIntIds = unsynced
          .map((e) => e[DatabaseHelper.colMatchId] as int)
          .toSet();
      final matchUuidMap    = <int, String>{};
      final matchSyncedMap  = <int, bool>{};   // true = already synced in a prior run
      for (final intId in matchIntIds) {
        final rows = await db.query(
          DatabaseHelper.tableMatches,
          columns: [DatabaseHelper.colUuid, DatabaseHelper.colSyncStatus],
          where: '${DatabaseHelper.colId} = ?',
          whereArgs: [intId],
          limit: 1,
        );
        if (rows.isNotEmpty) {
          matchUuidMap[intId]   = rows.first[DatabaseHelper.colUuid] as String;
          matchSyncedMap[intId] = (rows.first[DatabaseHelper.colSyncStatus] as int) == 1;
        }
      }

      // Build player_id (int) → uuid (String) map for all players referenced.
      final playerIntIds = <int>{};
      for (final e in unsynced) {
        for (final col in [
          DatabaseHelper.colStrikerId,
          DatabaseHelper.colNonStrikerId,
          DatabaseHelper.colBowlerId,
          DatabaseHelper.colOutPlayerId,
        ]) {
          final v = e[col];
          if (v != null) playerIntIds.add(v as int);
        }
      }
      final playerUuidMap = <int, String>{};
      for (final intId in playerIntIds) {
        final rows = await db.query(
          DatabaseHelper.tablePlayers,
          columns: [DatabaseHelper.colUuid],
          where: '${DatabaseHelper.colId} = ?',
          whereArgs: [intId],
          limit: 1,
        );
        if (rows.isNotEmpty) {
          playerUuidMap[intId] = rows.first[DatabaseHelper.colUuid] as String;
        }
      }

      // Helper to resolve a nullable int player id to its UUID string.
      String? playerUuid(int? id) => id == null ? null : playerUuidMap[id];

      // ── Filter: only send balls whose parent match is confirmed in Supabase ─
      // confirmedMatchUuids now contains BOTH newly-synced UUIDs (from this run)
      // and already-synced UUIDs (sync_status=1 in local DB), so a single set
      // membership check is sufficient.  The matchSyncedMap fallback is kept
      // only for the edge case where _syncMatches itself threw an exception and
      // returned an empty set — this shouldn't happen in practice but prevents
      // a complete stall if it does.
      bool matchIsSafe(int matchIntId) {
        final uuid = matchUuidMap[matchIntId];
        if (uuid == null) return false;                       // no UUID — skip
        if (confirmedMatchUuids.contains(uuid)) return true; // confirmed this run (new or already synced)
        if (matchSyncedMap[matchIntId] == true) return true; // emergency fallback
        return false;
      }

      final safeEvents   = <Map<String, dynamic>>[];
      final skippedCount = unsynced.where((e) => !matchIsSafe(e[DatabaseHelper.colMatchId] as int)).length;

      for (final event in unsynced) {
        final matchIntId = event[DatabaseHelper.colMatchId] as int;
        if (matchIsSafe(matchIntId)) {
          safeEvents.add(event);
        }
      }

      if (skippedCount > 0) {
        developer.log(
          '_syncBallEvents: skipped $skippedCount ball_event(s) — parent match '
          'not yet confirmed in Supabase; will retry on next sync',
          name: 'SyncService',
          level: 800,
        );
      }

      if (safeEvents.isEmpty) return 0;

      // Process in chunks of 200 to stay well within Supabase request-body
      // limits and keep individual payloads small for mobile data efficiency.
      const chunkSize = 200;
      final syncedIds = <int>[];

      // Tracks match int-IDs whose FK was found missing in Supabase during
      // this run; events referencing these matches are skipped in all
      // subsequent chunks so we don't repeat a doomed request.
      final fkMissingMatchIds = <int>{};

      for (int i = 0; i < safeEvents.length; i += chunkSize) {
        final rawChunk = safeEvents.sublist(i, (i + chunkSize).clamp(0, safeEvents.length));
        // Skip any events whose match was flagged as FK-missing in an earlier
        // chunk of this same run.
        final chunk = fkMissingMatchIds.isEmpty
            ? rawChunk
            : rawChunk
                .where((ev) => !fkMissingMatchIds.contains(ev[DatabaseHelper.colMatchId] as int))
                .toList();
        if (chunk.isEmpty) continue;
        final payloads = chunk.map((event) {
          final runsScored = (event[DatabaseHelper.colRunsScored] as int?) ?? 0;
          final extraRuns  = (event[DatabaseHelper.colExtraRuns]  as int?) ?? 0;
          final matchIntId = event[DatabaseHelper.colMatchId] as int;
          return <String, dynamic>{
            'match_id':       matchUuidMap[matchIntId],             // UUID string
            'innings':        event[DatabaseHelper.colInnings],
            'over_number':    event[DatabaseHelper.colOverNum],
            'ball_number':    event[DatabaseHelper.colBallNum],
            'runs_scored':    runsScored,
            'batter_runs':    runsScored - extraRuns,
            'is_wicket':      event[DatabaseHelper.colIsWicket] == 1,
            'dismissal_type': event[DatabaseHelper.colWicketType],
            'extra_type':     event[DatabaseHelper.colExtraType],
            'extra_runs':     extraRuns,
            'striker':        playerUuid(event[DatabaseHelper.colStrikerId] as int?),
            'non_striker':    playerUuid(event[DatabaseHelper.colNonStrikerId] as int?),
            'bowler':         playerUuid(event[DatabaseHelper.colBowlerId] as int?),
            'player_out':     playerUuid(event[DatabaseHelper.colOutPlayerId] as int?),
            'outcome':        null,
            'crossed':        null,
          };
        }).toList();

        try {
          await _supabase.from('ball_events').upsert(payloads, ignoreDuplicates: true);
          for (final event in chunk) {
            syncedIds.add(event[DatabaseHelper.colId] as int);
          }
          developer.log(
            'Batch upserted ${chunk.length} ball_event(s) (chunk ${i ~/ chunkSize + 1})',
            name: 'SyncService',
          );
        } on PostgrestException catch (e, st) {
          print('SYNC ERROR (ball_events upsert chunk ${i ~/ chunkSize + 1}): $e | details: ${e.details} | hint: ${e.hint} | code: ${e.code}');
          developer.log(
            'Batch upsert failed for ball_events chunk ${i ~/ chunkSize + 1}',
            name: 'SyncService',
            error: e,
            stackTrace: st,
            level: 1000,
          );
          errors.add('Failed to batch-sync ball_events chunk: ${e.message}');

          // FK violation (23503): a match referenced by this chunk does not
          // exist in Supabase — likely deleted remotely while the local row
          // still has sync_status=1.  Reset the parent match(es) to
          // sync_status=0 so the next syncAll() re-uploads them before
          // retrying these ball events.
          if (e.code == '23503') {
            final staleMatchIntIds = chunk
                .map((ev) => ev[DatabaseHelper.colMatchId] as int)
                .toSet();
            // Prevent subsequent chunks in this run from repeating the error.
            fkMissingMatchIds.addAll(staleMatchIntIds);
            try {
              final db2 = await _db.database;
              await db2.transaction((txn) async {
                for (final mid in staleMatchIntIds) {
                  await txn.update(
                    DatabaseHelper.tableMatches,
                    {DatabaseHelper.colSyncStatus: 0},
                    where: '${DatabaseHelper.colId} = ?',
                    whereArgs: [mid],
                  );
                }
              });
              developer.log(
                '_syncBallEvents: reset sync_status=0 for ${staleMatchIntIds.length} '
                'match(es) whose FK was missing in Supabase (will re-upload on next sync)',
                name: 'SyncService',
                level: 800,
              );
            } catch (resetErr, resetSt) {
              developer.log(
                '_syncBallEvents: failed to reset match sync_status after FK error',
                name: 'SyncService',
                error: resetErr,
                stackTrace: resetSt,
                level: 900,
              );
            }
          }

          // Continue with next chunk rather than aborting the whole sync
        }
      }

      // Mark all successfully synced ball events in a single transaction
      if (syncedIds.isNotEmpty) {
        final db2 = await _db.database;
        await db2.transaction((txn) async {
          for (final id in syncedIds) {
            await txn.update(
              DatabaseHelper.tableBallEvents,
              {DatabaseHelper.colSyncStatus: 1},
              where: '${DatabaseHelper.colId} = ?',
              whereArgs: [id],
            );
          }
        });
        synced = syncedIds.length;
      }
    } catch (e, st) {
      print('SYNC ERROR (ball_events fetch): $e');
      developer.log(
        'Failed to fetch unsynced ball_events',
        name: 'SyncService',
        error: e,
        stackTrace: st,
        level: 1000,
      );
      errors.add('Failed to fetch unsynced ball_events: $e');
    }

    return synced;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ══════════════════════════════════════════════════════════════════════════

  void _setState(SyncState newState) {
    _state = newState;
    if (!_syncStatusController.isClosed) {
      _syncStatusController.add(newState);
    }
    notifyListeners();
  }

  /// Get the count of unsynced records.
  Future<Map<String, int>> getUnsyncedCounts() async {
    try {
      final db = await _db.database;

      final matchesCount = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM ${DatabaseHelper.tableMatches} WHERE ${DatabaseHelper.colSyncStatus} = 0',
          )) ??
          0;

      final playersCount = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM ${DatabaseHelper.tablePlayers} WHERE ${DatabaseHelper.colSyncStatus} = 0',
          )) ??
          0;

      final ballEventsCount = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM ${DatabaseHelper.tableBallEvents} WHERE ${DatabaseHelper.colSyncStatus} = 0',
          )) ??
          0;

      return {
        'matches': matchesCount,
        'players': playersCount,
        'ball_events': ballEventsCount,
        'total': matchesCount + playersCount + ballEventsCount,
      };
    } catch (e, st) {
      developer.log(
        'getUnsyncedCounts failed',
        name: 'SyncService',
        error: e,
        stackTrace: st,
        level: 900,
      );
      return {'matches': 0, 'players': 0, 'ball_events': 0, 'total': 0};
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // DOWNWARD SYNC (Supabase → local SQLite)
  // ══════════════════════════════════════════════════════════════════════════

  /// Pull initial data from Supabase into the local SQLite database.
  ///
  /// Runs automatically after sign-in when the local `players` table is empty,
  /// or can be force-called by passing [force] = true.
  ///
  /// Uses `INSERT OR IGNORE` so existing local rows are never overwritten —
  /// local data always wins, which preserves any offline changes made before
  /// the user first signed in.
  ///
  /// Tables synced (in FK-safe order): teams → players → matches.
  /// `ball_events` are intentionally excluded from the initial pull; they are
  /// large and not needed for the roster autocomplete use-case that motivated
  /// this feature.
  Future<void> syncDownInitialData({bool force = false}) async {
    try {
      final db = await _db.database;

      // Guard: skip unless forced or local players table is empty.
      if (!force) {
        final count = Sqflite.firstIntValue(
              await db.rawQuery('SELECT COUNT(*) FROM ${DatabaseHelper.tablePlayers}'),
            ) ??
            0;
        if (count > 0) {
          developer.log(
            'syncDownInitialData: skipped — local players table not empty (count=$count)',
            name: 'SyncService',
          );
          return;
        }
      }

      // Require authentication.
      final userId = AuthService.instance.currentUser?.id;
      if (userId == null) {
        developer.log(
          'syncDownInitialData: aborted — user not authenticated',
          name: 'SyncService',
          level: 800,
        );
        return;
      }

      // Require connectivity.
      final isOnline = await _checkConnectivity();
      if (!isOnline) {
        developer.log(
          'syncDownInitialData: aborted — device offline',
          name: 'SyncService',
        );
        return;
      }

      developer.log('syncDownInitialData: starting pull from Supabase', name: 'SyncService');

      // ── 1. Players ───────────────────────────────────────────────────────
      try {
        final remotePlayers = await _supabase.from('players').select();
        int playersInserted = 0;
        await db.transaction((txn) async {
          for (final p in remotePlayers as List<dynamic>) {
            final row = p as Map<String, dynamic>;
            final inserted = await txn.insert(
              DatabaseHelper.tablePlayers,
              {
                DatabaseHelper.colUuid:   row['id']   as String? ?? '',
                DatabaseHelper.colName:   row['name'] as String? ?? '',
                DatabaseHelper.colTeam:   row['team'] as String? ?? '',
                DatabaseHelper.colRole:   row['role'] as String? ?? 'Batsman',
                DatabaseHelper.colSyncStatus: 1, // already in Supabase
              },
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
            if (inserted > 0) playersInserted++;
          }
        });
        developer.log(
          'syncDownInitialData: inserted $playersInserted/${(remotePlayers as List).length} player(s)',
          name: 'SyncService',
        );
      } catch (e, st) {
        developer.log(
          'syncDownInitialData: failed to pull players',
          name: 'SyncService',
          error: e,
          stackTrace: st,
          level: 900,
        );
      }

      // ── 2. Matches ───────────────────────────────────────────────────────
      try {
        final remoteMatches = await _supabase
            .from('matches')
            .select()
            .eq('created_by', userId);
        int matchesInserted = 0;
        await db.transaction((txn) async {
          for (final m in remoteMatches as List<dynamic>) {
            final row = m as Map<String, dynamic>;
            final inserted = await txn.insert(
              DatabaseHelper.tableMatches,
              {
                DatabaseHelper.colUuid:           row['id']             as String? ?? '',
                DatabaseHelper.colTeamA:          row['team_a']         as String? ?? '',
                DatabaseHelper.colTeamB:          row['team_b']         as String? ?? '',
                DatabaseHelper.colTotalOvers:     row['overs']          as int?    ?? 10,
                DatabaseHelper.colTossWinner:     row['toss_winner']    as String? ?? '',
                DatabaseHelper.colOptTo:          row['toss_decision']  as String? ?? '',
                DatabaseHelper.colStatus:         row['status']         as String? ?? 'completed',
                DatabaseHelper.colTournamentName: row['tournament_name'] as String?,
                DatabaseHelper.colWinner:         row['winner']         as String?,
                DatabaseHelper.colCreatedBy:      row['created_by']     as String? ?? userId,
                DatabaseHelper.colSyncStatus:     1,
              },
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
            if (inserted > 0) matchesInserted++;
          }
        });
        developer.log(
          'syncDownInitialData: inserted $matchesInserted/${(remoteMatches as List).length} match(es)',
          name: 'SyncService',
        );
      } catch (e, st) {
        developer.log(
          'syncDownInitialData: failed to pull matches',
          name: 'SyncService',
          error: e,
          stackTrace: st,
          level: 900,
        );
      }

      developer.log('syncDownInitialData: pull complete', name: 'SyncService');
    } catch (e, st) {
      developer.log(
        'syncDownInitialData: unexpected failure',
        name: 'SyncService',
        error: e,
        stackTrace: st,
        level: 1000,
      );
    }
  }
}
