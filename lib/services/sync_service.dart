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
  final int matchSummariesSynced;
  final List<String> errors;

  SyncResult({
    this.matchesSynced = 0,
    this.playersSynced = 0,
    this.ballEventsSynced = 0,
    this.matchSummariesSynced = 0,
    this.errors = const [],
  });

  int get totalSynced =>
      matchesSynced + playersSynced + ballEventsSynced + matchSummariesSynced;

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

  // Guard against overlapping upward sync runs
  bool _isSyncing = false;
  // Guard against overlapping downward sync runs
  bool _isSyncingDown = false;

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
    int matchSummariesSynced = 0;

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
      //   0. teams       (no FK dependencies — must land before players reference team names)
      //   1. players     (no FK dependencies)
      //   2. tournaments (no FK dependencies; must land before matches reference them)
      //   3. matches     (depends on players + tournaments; carries tournament_id UUID FK)
      //   4. ball_events (FK on matches — MUST wait for matches to land first)
      //   5. match_summaries (aggregated from ball_events; only for completed+synced matches)
      //
      // _syncMatches returns the set of match UUIDs that were confirmed written
      // to Supabase.  That set is passed directly into _syncBallEvents so it
      // can gate each event against it and avoid FK violations (code 23503).
      await _syncTeams(errors);
      playersSynced = await _syncPlayers(errors);
      await _syncTournaments(errors);
      final matchResult = await _syncMatches(errors);
      matchesSynced = matchResult.count;
      ballEventsSynced = await _syncBallEvents(errors, matchResult.syncedUuids);
      matchSummariesSynced = await _syncMatchSummaries(errors);

      _lastSyncTime = DateTime.now();

      if (errors.isEmpty) {
        developer.log(
          'syncAll: completed successfully — '
          'total=${playersSynced + matchesSynced + ballEventsSynced + matchSummariesSynced}',
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
      matchSummariesSynced: matchSummariesSynced,
      errors: errors,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SYNC INDIVIDUAL TABLES
  // ══════════════════════════════════════════════════════════════════════════

  /// Sync unsynced teams to Supabase in a single batch upsert.
  ///
  /// Only rows with [sync_status] == 0 are pushed; already-synced rows are
  /// skipped to keep the payload minimal.  After a successful upsert every
  /// pushed row is marked [sync_status] = 1 locally.
  Future<void> _syncTeams(List<String> errors) async {
    try {
      final unsynced = await _db.fetchUnsyncedTeams();
      if (unsynced.isEmpty) return;

      final payloads = <Map<String, dynamic>>[];
      final ids      = <int>[];

      for (final t in unsynced) {
        final uuid = (t[DatabaseHelper.colTeamUuid] as String? ?? '').trim();
        if (uuid.isEmpty) continue;
        payloads.add({
          'id':         uuid,
          'name':       t[DatabaseHelper.colName]       as String? ?? '',
          'created_at': t[DatabaseHelper.colCreatedAt]  as String?
              ?? DateTime.now().toIso8601String(),
          'created_by': t[DatabaseHelper.colCreatedBy]  as String?,
        });
        ids.add(t[DatabaseHelper.colId] as int);
      }

      if (payloads.isEmpty) return;

      try {
        await _supabase.from('teams').upsert(payloads, ignoreDuplicates: false);
        // Mark as synced locally.
        for (final id in ids) {
          await _db.markTeamSynced(id);
        }
        developer.log(
          '_syncTeams: upserted ${payloads.length} team(s)',
          name: 'SyncService',
        );
      } on PostgrestException catch (e, st) {
        developer.log(
          '_syncTeams: upsert failed',
          name: 'SyncService',
          error: e,
          stackTrace: st,
          level: 1000,
        );
        errors.add('Failed to sync teams: ${e.message}');
      }
    } catch (e, st) {
      developer.log(
        '_syncTeams: unexpected failure',
        name: 'SyncService',
        error: e,
        stackTrace: st,
        level: 1000,
      );
      errors.add('Failed to sync teams: $e');
    }
  }

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

        // Resolve the avatar_url to send to Supabase:
        //   • If local_avatar_path is already an https:// URL (uploaded at
        //     save-time by _submit()), use it directly — no re-upload needed.
        //   • If it is a local file path, upload it now and use the public URL.
        //   • If there is no avatar at all, omit avatar_url from the payload
        //     so the existing Supabase value is never overwritten with null.
        String? avatarUrl;
        if (localAvatarPath != null && localAvatarPath.isNotEmpty) {
          final isAlreadyUrl = localAvatarPath.startsWith('http://') ||
              localAvatarPath.startsWith('https://');

          if (isAlreadyUrl) {
            // Already a public URL — use as-is, no Storage upload needed.
            avatarUrl = localAvatarPath;
          } else {
            // Local file path — upload to Storage and get the public URL.
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

                // Persist the URL back to SQLite so future syncs skip the
                // file upload and use the URL path directly.
                final db2 = await _db.database;
                await db2.update(
                  DatabaseHelper.tablePlayers,
                  {DatabaseHelper.colLocalAvatarPath: avatarUrl},
                  where: '${DatabaseHelper.colId} = ?',
                  whereArgs: [playerId],
                );
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
        }

        // Build the upsert payload.  Include 'id' (UUID) so Supabase can
        // match on the primary key and update rather than insert duplicates.
        // Only add avatar_url when we actually have a value — sending null
        // would blank out an avatar that was set on another device.
        final payload = <String, dynamic>{
          'id':           playerUuid,
          'name':         player[DatabaseHelper.colName],
          'team':         player[DatabaseHelper.colTeam],
          'role':         player[DatabaseHelper.colRole],
          'bowling_type': player[DatabaseHelper.colBowlingType],
        };
        if (avatarUrl != null) {
          payload['avatar_url'] = avatarUrl;
        }
        payloads.add(payload);

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

  /// Sync all local tournaments to Supabase in a single batch upsert.
  ///
  /// Every tournament row is upserted (not just unsynced ones) to ensure the
  /// remote copy stays current with name / status / winner changes.
  /// The `uuid` column (added in DB v16) is used as the Supabase PK.
  Future<void> _syncTournaments(List<String> errors) async {
    try {
      final db = await _db.database;

      final rows = await db.query(DatabaseHelper.tableTournaments);
      if (rows.isEmpty) return;

      final payloads = <Map<String, dynamic>>[];

      for (final t in rows) {
        final uuid = (t[DatabaseHelper.colTournamentUuid] as String? ?? '').trim();
        if (uuid.isEmpty) continue; // skip rows without a UUID (pre-v16 edge case)

        payloads.add({
          'id':              uuid,
          'name':            t[DatabaseHelper.colName],
          'format':          t[DatabaseHelper.colFormat],
          'overs_per_match': t[DatabaseHelper.colOversPerMatch],
          'teams':           t[DatabaseHelper.colTeams],
          'status':          t[DatabaseHelper.colStatus],
          'created_at':      t[DatabaseHelper.colCreatedAt],
          'created_by':      t[DatabaseHelper.colCreatedBy],
        });
      }

      if (payloads.isEmpty) return;

      try {
        await _supabase
            .from('tournaments')
            .upsert(payloads, ignoreDuplicates: false);
        developer.log(
          '_syncTournaments: upserted ${payloads.length} tournament(s)',
          name: 'SyncService',
        );
      } on PostgrestException catch (e, st) {
        developer.log(
          '_syncTournaments: upsert failed',
          name: 'SyncService',
          error: e,
          stackTrace: st,
          level: 1000,
        );
        errors.add('Failed to sync tournaments: ${e.message}');
      }
    } catch (e, st) {
      developer.log(
        '_syncTournaments: unexpected failure',
        name: 'SyncService',
        error: e,
        stackTrace: st,
        level: 1000,
      );
      errors.add('Failed to sync tournaments: $e');
    }
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

        // Resolve tournament_id: local DB stores an INTEGER FK; Supabase
        // expects the tournament's UUID string (tournaments.uuid).
        final tournLocalId = match[DatabaseHelper.colTournamentId] as int?;
        String? tournamentUuid;
        if (tournLocalId != null) {
          final db = await _db.database;
          final tRows = await db.query(
            DatabaseHelper.tableTournaments,
            columns: [DatabaseHelper.colTournamentUuid],
            where: '${DatabaseHelper.colId} = ?',
            whereArgs: [tournLocalId],
            limit: 1,
          );
          if (tRows.isNotEmpty) {
            final u = tRows.first[DatabaseHelper.colTournamentUuid] as String? ?? '';
            tournamentUuid = u.isEmpty ? null : u;
          }
        }

        payloads.add({
          'id':             matchUuid,           // UUID string as Supabase PK
          'team_a':         match[DatabaseHelper.colTeamA],
          'team_b':         match[DatabaseHelper.colTeamB],
          'overs':          match[DatabaseHelper.colTotalOvers], // total_overs → overs
          'toss_winner':    match[DatabaseHelper.colTossWinner],
          'toss_decision':  match[DatabaseHelper.colOptTo],      // opt_to → toss_decision
          'status':         match[DatabaseHelper.colStatus],
          'tournament_id':  tournamentUuid,       // UUID FK → tournaments.id, nullable
          'winner':         match[DatabaseHelper.colWinner],
          'created_by':     match[DatabaseHelper.colCreatedBy],  // required by RLS / NOT NULL
          'motm_player_id': motmPlayerUuid,       // NULL until match completes
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
            // batter_runs = runs credited to the batter (off-bat only).
            // Do NOT subtract extraRuns — that yields negative values for
            // wides/no-balls where runsScored == 0 and extraRuns == 1.
            'batter_runs':    runsScored,
            'is_wicket':      (event[DatabaseHelper.colIsWicket]   as int? ?? 0) == 1,
            'is_boundary':    (event[DatabaseHelper.colIsBoundary] as int? ?? 0) == 1,
            'is_free_hit':    false,  // schema column; free-hit not yet tracked locally, defaults to false
            'dismissal_type': event[DatabaseHelper.colWicketType],
            'extra_type':     event[DatabaseHelper.colExtraType],
            'extra_runs':     extraRuns,
            'striker':        playerUuid(event[DatabaseHelper.colStrikerId] as int?),
            'non_striker':    playerUuid(event[DatabaseHelper.colNonStrikerId] as int?),
            'bowler':         playerUuid(event[DatabaseHelper.colBowlerId] as int?),
            'player_out':     playerUuid(event[DatabaseHelper.colOutPlayerId] as int?),
            'created_by':     event[DatabaseHelper.colCreatedBy] as String?,
            'outcome':        null,
            'crossed':        false,
          };
        }).toList();

        try {
          await _supabase.from('ball_events').upsert(
            payloads,
            ignoreDuplicates: false,
          );
          for (final event in chunk) {
            syncedIds.add(event[DatabaseHelper.colId] as int);
          }
          developer.log(
            'Batch upserted ${chunk.length} ball_event(s) (chunk ${i ~/ chunkSize + 1})',
            name: 'SyncService',
          );
        } on PostgrestException catch (e, st) {
          debugPrint('SUPABASE SYNC ERROR: ${e.message} - Details: ${e.details} - Hint: ${e.hint} - Code: ${e.code}');
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
  // MATCH SUMMARIES SYNC
  // ══════════════════════════════════════════════════════════════════════════

  /// For every completed match that has already been confirmed in Supabase
  /// (sync_status = 1 in the local matches table), compute per-player batting
  /// and bowling aggregates from local ball_events and upsert one row per
  /// player into the Supabase `match_summaries` table.
  ///
  /// Schema expected on the Supabase side:
  ///   match_id       text    (FK → matches.id, the UUID string)
  ///   player_name    text
  ///   runs           int4
  ///   wickets        int4
  ///   impact_score   float8
  ///   team_a         text
  ///   team_b         text
  ///   winner         text
  ///   tournament_id   uuid FK → tournaments.id (nullable)
  Future<int> _syncMatchSummaries(List<String> errors) async {
    int synced = 0;
    try {
      final db = await _db.database;

      // Only process completed matches that are already confirmed in Supabase.
      final completedSynced = await db.query(
        DatabaseHelper.tableMatches,
        where:
            '${DatabaseHelper.colStatus} = ? AND ${DatabaseHelper.colSyncStatus} = 1',
        whereArgs: ['completed'],
      );

      if (completedSynced.isEmpty) return 0;

      final payloads = <Map<String, dynamic>>[];

      for (final match in completedSynced) {
        final matchIntId  = match[DatabaseHelper.colId]             as int;
        final matchUuid   = match[DatabaseHelper.colUuid]           as String;
        final teamA       = match[DatabaseHelper.colTeamA]          as String;
        final teamB       = match[DatabaseHelper.colTeamB]          as String;
        final winner         = match[DatabaseHelper.colWinner]      as String?;
        final localTournId   = match[DatabaseHelper.colTournamentId] as int?;

        if (matchUuid.isEmpty) continue; // no UUID yet — skip

        // Resolve local tournament int id → Supabase UUID string (nullable).
        String? tournamentUuid;
        if (localTournId != null) {
          final tRows = await db.query(
            DatabaseHelper.tableTournaments,
            columns: [DatabaseHelper.colTournamentUuid],
            where: '${DatabaseHelper.colId} = ?',
            whereArgs: [localTournId],
            limit: 1,
          );
          if (tRows.isNotEmpty) {
            tournamentUuid = tRows.first[DatabaseHelper.colTournamentUuid] as String?;
          }
        }

        // Fetch all ball_events for this match (both innings).
        final events = await db.query(
          DatabaseHelper.tableBallEvents,
          where: '${DatabaseHelper.colMatchId} = ?',
          whereArgs: [matchIntId],
        );
        if (events.isEmpty) continue;

        // Collect all unique player int IDs referenced in this match.
        final playerIds = <int>{};
        for (final e in events) {
          for (final col in [
            DatabaseHelper.colStrikerId,
            DatabaseHelper.colNonStrikerId,
            DatabaseHelper.colBowlerId,
            DatabaseHelper.colOutPlayerId,
          ]) {
            final v = e[col];
            if (v != null) playerIds.add(v as int);
          }
        }

        // Build a map of player int id → {name, uuid}.
        final playerInfo = <int, Map<String, String?>>{};
        for (final pid in playerIds) {
          final rows = await db.query(
            DatabaseHelper.tablePlayers,
            columns: [
              DatabaseHelper.colName,
              DatabaseHelper.colUuid,
            ],
            where: '${DatabaseHelper.colId} = ?',
            whereArgs: [pid],
            limit: 1,
          );
          if (rows.isNotEmpty) {
            playerInfo[pid] = {
              'name': rows.first[DatabaseHelper.colName] as String?,
              'uuid': rows.first[DatabaseHelper.colUuid] as String?,
            };
          }
        }

        // Aggregate per-player stats across both innings.
        final batRuns    = <int, int>{};   // player id → runs scored as batter
        final bowWickets = <int, int>{};   // player id → wickets taken as bowler

        for (final e in events) {
          final strikerId = e[DatabaseHelper.colStrikerId] as int?;
          final bowlerId  = e[DatabaseHelper.colBowlerId]  as int?;
          final extraType = e[DatabaseHelper.colExtraType] as String?;
          final runs      = (e[DatabaseHelper.colRunsScored] as int?) ?? 0;
          final isWicket  = ((e[DatabaseHelper.colIsWicket] as int?) ?? 0) == 1;
          final wicketType = e[DatabaseHelper.colWicketType] as String?;

          // Batting runs (exclude byes/leg-byes credited to the batter).
          if (strikerId != null &&
              extraType != 'bye' &&
              extraType != 'leg_bye') {
            batRuns[strikerId] = (batRuns[strikerId] ?? 0) + runs;
          }

          // Bowling wickets (exclude run-outs from bowler's tally).
          if (bowlerId != null && isWicket && wicketType != 'run_out') {
            bowWickets[bowlerId] = (bowWickets[bowlerId] ?? 0) + 1;
          }
        }

        // Build one payload row per player.
        for (final pid in playerIds) {
          final info = playerInfo[pid];

          // ── Strict UUID guard ────────────────────────────────────────────
          // A blank or malformed UUID would cause a Postgres FK / type error.
          // The UUID regex requires the canonical 8-4-4-4-12 hex format.
          final uuidPattern = RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
            caseSensitive: false,
          );
          if (!uuidPattern.hasMatch(matchUuid)) {
            developer.log(
              '_syncMatchSummaries: skipping match $matchIntId — '
              'invalid UUID "$matchUuid"',
              name: 'SyncService',
              level: 800,
            );
            break; // skip every player row for this match
          }

          // ── Type-safe text fields ─────────────────────────────────────────
          final rawName    = info?['name'];
          final playerName = (rawName != null && rawName.trim().isNotEmpty)
              ? rawName
              : 'Player $pid';
          final safeTeamA   = teamA.isNotEmpty  ? teamA  : 'Unknown';
          final safeTeamB   = teamB.isNotEmpty  ? teamB  : 'Unknown';
          final safeWinner  = (winner  != null && winner.isNotEmpty)   ? winner   : null;

          // ── Explicit int4 casts ───────────────────────────────────────────
          // Supabase expects int4 for runs, wickets, impact_score.
          // All three are computed from integer arithmetic; .toInt() is a
          // safety net in case Dart ever widens them to num/double.
          final runsInt    = (batRuns[pid]    ?? 0).toInt();
          final wicketsInt = (bowWickets[pid] ?? 0).toInt();
          final impactInt  = (runsInt + wicketsInt * 20); // pure int, no double

          payloads.add({
            'match_id':        matchUuid,       // validated UUID string → FK matches.id
            'player_name':     playerName,      // text NOT NULL
            'runs':            runsInt,         // int4
            'wickets':         wicketsInt,      // int4
            'impact_score':    impactInt,       // int4 (no decimal sent)
            'team_a':          safeTeamA,       // text
            'team_b':          safeTeamB,       // text
            'winner':          safeWinner,      // text, nullable
            'tournament_id':   tournamentUuid,  // uuid FK, nullable
          });
        }
      }

      if (payloads.isEmpty) return 0;

      // Upsert in chunks of 200.
      const chunkSize = 200;
      for (int i = 0; i < payloads.length; i += chunkSize) {
        final chunk = payloads.sublist(
          i, (i + chunkSize).clamp(0, payloads.length),
        );
        try {
          await _supabase
              .from('match_summaries')
              .upsert(chunk, ignoreDuplicates: false);
          synced += chunk.length;
        } on PostgrestException catch (pgErr) {
          // Log the exact Postgres error so the precise column / constraint
          // violation is visible in the debug console.
          developer.log(
            '_syncMatchSummaries: PostgrestException on chunk '
            '${i ~/ chunkSize + 1}\n'
            '  message : ${pgErr.message}\n'
            '  details : ${pgErr.details}\n'
            '  hint    : ${pgErr.hint}\n'
            '  code    : ${pgErr.code}',
            name: 'SyncService',
            level: 900,
          );
          errors.add('match_summaries upsert failed (chunk ${i ~/ chunkSize + 1}): '
              '${pgErr.message} — ${pgErr.details}');
          // Continue trying remaining chunks rather than aborting entirely.
        }
      }

      developer.log(
        '_syncMatchSummaries: upserted $synced row(s)',
        name: 'SyncService',
      );
    } catch (e, st) {
      developer.log(
        '_syncMatchSummaries: unexpected failure',
        name: 'SyncService',
        error: e,
        stackTrace: st,
        level: 900,
      );
      errors.add('match_summaries sync failed: $e');
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

  /// Pull the full community dataset from Supabase into local SQLite.
  ///
  /// Runs automatically on every sign-in event (via [AuthService]) with
  /// [force] = true, and is called by the Dashboard on every mount so that
  /// community matches created by other users are always visible.
  ///
  /// Insertion order (FK-safe):
  ///   1. players
  ///   2. matches
  ///   3. ball_events  (requires players + matches to exist first)
  ///
  /// All inserts use [ConflictAlgorithm.replace] so that:
  ///   - A fresh install (empty DB) inserts everything normally.
  ///   - A forced re-sync updates stale rows rather than silently skipping them.
  ///   - Re-installing the app never causes UNIQUE-constraint failures on uuid.
  ///
  /// When [force] is false the sync is skipped if the local players table
  /// already has rows (cheap guard for normal app restarts).
  Future<void> syncDownInitialData({bool force = false}) async {
    // Prevent concurrent downward sync runs (auth event + dashboard both
    // calling this simultaneously caused duplicate inserts before the UNIQUE
    // index was in place; keep the guard for extra safety).
    if (_isSyncingDown) {
      developer.log(
        'syncDownInitialData: skipped — downward sync already in progress',
        name: 'SyncService',
      );
      return;
    }
    _isSyncingDown = true;
    try {
      final db = await _db.database;

      // ── Guard ────────────────────────────────────────────────────────────
      if (!force) {
        final count = Sqflite.firstIntValue(
              await db.rawQuery(
                  'SELECT COUNT(*) FROM ${DatabaseHelper.tablePlayers}'),
            ) ??
            0;
        if (count > 0) {
          developer.log(
            'syncDownInitialData: skipped — local players not empty (count=$count)',
            name: 'SyncService',
          );
          return;
        }
      }

      // ── Auth ─────────────────────────────────────────────────────────────
      final userId = AuthService.instance.currentUser?.id;
      if (userId == null) {
        developer.log(
          'syncDownInitialData: aborted — user not authenticated',
          name: 'SyncService',
          level: 800,
        );
        return;
      }

      // ── Connectivity ─────────────────────────────────────────────────────
      final isOnline = await _checkConnectivity();
      if (!isOnline) {
        developer.log(
          'syncDownInitialData: aborted — device offline',
          name: 'SyncService',
        );
        return;
      }

      developer.log(
        'syncDownInitialData: starting pull from Supabase (force=$force)',
        name: 'SyncService',
      );

      _setState(SyncState.syncing);

      // ══════════════════════════════════════════════════════════════════════
      // 0. TEAMS  (no FK deps — pull before players)
      // ══════════════════════════════════════════════════════════════════════
      int teamsInserted = 0;
      try {
        final remoteTeams =
            await _supabase.from('teams').select() as List<dynamic>;

        await db.transaction((txn) async {
          for (final t in remoteTeams) {
            final row  = t as Map<String, dynamic>;
            final uuid = row['id'] as String? ?? '';
            if (uuid.isEmpty) continue;
            final n = await txn.insert(
              DatabaseHelper.tableTeams,
              {
                DatabaseHelper.colTeamUuid:  uuid,
                DatabaseHelper.colName:      row['name']       as String? ?? '',
                DatabaseHelper.colSyncStatus: 1,
                DatabaseHelper.colCreatedAt: row['created_at'] as String?
                    ?? DateTime.now().toIso8601String(),
                DatabaseHelper.colCreatedBy: row['created_by'] as String?,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            if (n > 0) teamsInserted++;
          }
        });
        developer.log(
          'syncDownInitialData: upserted $teamsInserted/${remoteTeams.length} team(s)',
          name: 'SyncService',
        );
      } catch (e, st) {
        developer.log(
          'syncDownInitialData: failed to pull teams',
          name: 'SyncService',
          error: e,
          stackTrace: st,
          level: 900,
        );
        // Non-fatal — continue with players.
      }

      // ══════════════════════════════════════════════════════════════════════
      // 1. PLAYERS
      // ══════════════════════════════════════════════════════════════════════
      int playersInserted = 0;
      try {
        final remotePlayers =
            await _supabase.from('players').select() as List<dynamic>;

        await db.transaction((txn) async {
          for (final p in remotePlayers) {
            final row = p as Map<String, dynamic>;

            // Prefer the remote avatar_url when syncing down so that avatars
            // uploaded from any device (or set via the web dashboard) are
            // reflected locally.  ConflictAlgorithm.replace means if a row
            // already exists, its local_avatar_path is replaced with the
            // remote avatar_url value — which is fine because _submit() now
            // stores the public URL (not a local path) in local_avatar_path.
            final remoteAvatarUrl = row['avatar_url'] as String?;

            final n = await txn.insert(
              DatabaseHelper.tablePlayers,
              {
                DatabaseHelper.colUuid:            row['id']           as String? ?? '',
                DatabaseHelper.colName:            row['name']         as String? ?? '',
                DatabaseHelper.colTeam:            row['team']         as String? ?? '',
                DatabaseHelper.colRole:            row['role']         as String?,
                DatabaseHelper.colBowlingType:     row['bowling_type'] as String?,
                DatabaseHelper.colLocalAvatarPath: remoteAvatarUrl,
                DatabaseHelper.colSyncStatus:      1,
                // NOT NULL — fall back to current time if Supabase omits it.
                DatabaseHelper.colCreatedAt:
                    row['created_at'] as String? ??
                    DateTime.now().toIso8601String(),
                DatabaseHelper.colCreatedBy:       row['created_by']  as String?,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            if (n > 0) playersInserted++;
          }
        });
        developer.log(
          'syncDownInitialData: upserted $playersInserted/${remotePlayers.length} player(s)',
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
        // Bail — ball_events need players to be present first.
        _setState(SyncState.error);
        return;
      }

      // ══════════════════════════════════════════════════════════════════════
      // 2. TOURNAMENTS  (global — all communities)
      // ══════════════════════════════════════════════════════════════════════
      //
      // Must run before matches so that tournament_id FKs on matches can be
      // resolved later if we ever migrate matches to store a proper FK.
      int tournamentsInserted = 0;
      // uuid → local auto-increment id, needed to resolve tournament_teams FK.
      final Map<String, int> tournamentUuidToLocalId = {};

      try {
        final remoteTournaments =
            await _supabase.from('tournaments').select() as List<dynamic>;

        await db.transaction((txn) async {
          for (final t in remoteTournaments) {
            final row = t as Map<String, dynamic>;
            final tUuid = row['id'] as String? ?? '';
            if (tUuid.isEmpty) continue;

            final n = await txn.insert(
              DatabaseHelper.tableTournaments,
              {
                DatabaseHelper.colTournamentUuid: tUuid,
                DatabaseHelper.colName:           row['name']           as String? ?? '',
                DatabaseHelper.colFormat:         row['format']         as String? ?? 'league',
                DatabaseHelper.colOversPerMatch:  row['overs_per_match'] as int?   ?? 20,
                DatabaseHelper.colTeams:          row['teams']          as String? ?? '',
                DatabaseHelper.colStatus:         row['status']         as String? ?? 'active',
                DatabaseHelper.colCreatedAt:      row['created_at']     as String?
                    ?? DateTime.now().toIso8601String(),
                DatabaseHelper.colCreatedBy:      row['created_by']     as String?,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            if (n > 0) tournamentsInserted++;
          }
        });

        // Rebuild uuid→localId from live DB (REPLACE may change rowids).
        final freshTRows = await db.query(
          DatabaseHelper.tableTournaments,
          columns: [DatabaseHelper.colId, DatabaseHelper.colTournamentUuid],
        );
        for (final r in freshTRows) {
          final u = r[DatabaseHelper.colTournamentUuid] as String? ?? '';
          if (u.isNotEmpty) {
            tournamentUuidToLocalId[u] = r[DatabaseHelper.colId] as int;
          }
        }

        developer.log(
          'syncDownInitialData: upserted $tournamentsInserted/${remoteTournaments.length} tournament(s)',
          name: 'SyncService',
        );
      } catch (e, st) {
        developer.log(
          'syncDownInitialData: failed to pull tournaments',
          name: 'SyncService',
          error: e,
          stackTrace: st,
          level: 900,
        );
        // Non-fatal — continue with matches even if tournaments fail.
      }

      // ══════════════════════════════════════════════════════════════════════
      // 3. TOURNAMENT TEAMS
      // ══════════════════════════════════════════════════════════════════════
      //
      // Supabase tournament_teams rows: { tournament_id (uuid FK), team_name,
      // is_eliminated (bool) }
      int tournamentTeamsInserted = 0;
      try {
        final remoteTTeams =
            await _supabase.from('tournament_teams').select() as List<dynamic>;

        await db.transaction((txn) async {
          for (final t in remoteTTeams) {
            final row = t as Map<String, dynamic>;
            final tUuid = row['tournament_id'] as String? ?? '';
            final localTournamentId = tournamentUuidToLocalId[tUuid];
            if (localTournamentId == null) continue; // unknown tournament — skip

            final n = await txn.insert(
              DatabaseHelper.tableTournamentTeams,
              {
                DatabaseHelper.colTournamentId: localTournamentId,
                DatabaseHelper.colTeamName:     row['team_name']     as String? ?? '',
                DatabaseHelper.colIsEliminated: (row['is_eliminated'] as bool? ?? false) ? 1 : 0,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            if (n > 0) tournamentTeamsInserted++;
          }
        });

        developer.log(
          'syncDownInitialData: upserted $tournamentTeamsInserted/${remoteTTeams.length} tournament_team(s)',
          name: 'SyncService',
        );
      } catch (e, st) {
        developer.log(
          'syncDownInitialData: failed to pull tournament_teams',
          name: 'SyncService',
          error: e,
          stackTrace: st,
          level: 900,
        );
        // Non-fatal.
      }

      // ══════════════════════════════════════════════════════════════════════
      // 4. MATCHES  (global — no created_by filter)
      // ══════════════════════════════════════════════════════════════════════
      //
      // Quick Matches have tournament_id IS NULL.
      // Tournament matches carry a non-null tournament_id UUID FK.
      // We download ALL matches and resolve tournament UUID → local int.
      int matchesInserted = 0;
      // Also build a uuid→localId map needed for ball_events below.
      final Map<String, int> matchUuidToLocalId = {};

      try {
        // ── Scalable fetch: all live + last 50 completed ──────────────────
        // Fetching every match ever played would OOM at scale.
        // Strategy:
        //   1. All ongoing matches (never miss a live score).
        //   2. Most recent 50 completed matches (bounded history).
        // The two lists are merged and de-duplicated by UUID before upsert.
        final ongoingMatches = await _supabase
            .from('matches')
            .select()
            .eq('status', 'ongoing') as List<dynamic>;

        final completedMatches = await _supabase
            .from('matches')
            .select()
            .eq('status', 'completed')
            .order('created_at', ascending: false)
            .limit(50) as List<dynamic>;

        // Merge & de-duplicate by UUID
        final seenUuids = <String>{};
        final remoteMatches = <dynamic>[];
        for (final m in [...ongoingMatches, ...completedMatches]) {
          final uuid = (m as Map<String, dynamic>)['id'] as String? ?? '';
          if (seenUuids.add(uuid)) remoteMatches.add(m);
        }

        await db.transaction((txn) async {
          for (final m in remoteMatches) {
            final row = m as Map<String, dynamic>;
            final matchUuid = row['id'] as String? ?? '';

            final localId = await txn.insert(
              DatabaseHelper.tableMatches,
              {
                DatabaseHelper.colUuid:           matchUuid,
                DatabaseHelper.colTeamA:          row['team_a']         as String? ?? '',
                DatabaseHelper.colTeamB:          row['team_b']         as String? ?? '',
                DatabaseHelper.colTotalOvers:     row['overs']          as int?    ?? 10,
                DatabaseHelper.colTossWinner:     row['toss_winner']    as String?,
                DatabaseHelper.colOptTo:          row['toss_decision']  as String?,
                DatabaseHelper.colStatus:         row['status']         as String? ?? 'completed',
                DatabaseHelper.colTournamentId:   tournamentUuidToLocalId[row['tournament_id'] as String? ?? ''],
                DatabaseHelper.colWinner:         row['winner']         as String?,
                DatabaseHelper.colCreatedBy:      row['created_by']     as String? ?? userId,
                DatabaseHelper.colSyncStatus:     1,
                // NOT NULL — must always be supplied.
                DatabaseHelper.colCreatedAt:
                    row['created_at'] as String? ??
                    DateTime.now().toIso8601String(),
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            if (localId > 0) {
              matchesInserted++;
              if (matchUuid.isNotEmpty) matchUuidToLocalId[matchUuid] = localId;
            }
          }
        });

        // After REPLACE the auto-incremented ids may differ from any previous
        // run.  Rebuild the uuid→id map from the live DB to be safe.
        final freshRows = await db.query(
          DatabaseHelper.tableMatches,
          columns: [DatabaseHelper.colId, DatabaseHelper.colUuid],
        );
        for (final r in freshRows) {
          final u = r[DatabaseHelper.colUuid] as String? ?? '';
          if (u.isNotEmpty) {
            matchUuidToLocalId[u] = r[DatabaseHelper.colId] as int;
          }
        }

        developer.log(
          'syncDownInitialData: upserted $matchesInserted/${remoteMatches.length} match(es)',
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
        // Bail — ball_events need matches to exist first.
        _setState(SyncState.error);
        return;
      }

      // ══════════════════════════════════════════════════════════════════════
      // 5. BALL EVENTS
      // ══════════════════════════════════════════════════════════════════════
      //
      // Build a player uuid→localId cache once, reuse across all matches.
      int ballEventsInserted = 0;
      try {
        final playerRows = await db.query(
          DatabaseHelper.tablePlayers,
          columns: [DatabaseHelper.colId, DatabaseHelper.colUuid],
        );
        final Map<String, int> playerUuidToLocalId = {
          for (final r in playerRows)
            if ((r[DatabaseHelper.colUuid] as String? ?? '').isNotEmpty)
              r[DatabaseHelper.colUuid] as String: r[DatabaseHelper.colId] as int,
        };

        int? resolvePlayer(dynamic uuidVal) {
          if (uuidVal == null) return null;
          final s = uuidVal as String;
          return s.isEmpty ? null : playerUuidToLocalId[s];
        }

        final remoteBalls =
            await _supabase.from('ball_events').select() as List<dynamic>;

        await db.transaction((txn) async {
          // ── Delete existing synced ball_events before reinserting ────────
          // Without this, every call appends duplicates because ball_events
          // has no UNIQUE constraint — only an auto-increment PK.  This
          // mirrors the delete-then-insert pattern in syncDownBallEvents().
          // Only sync_status = 1 rows are removed; locally-created unsynced
          // balls (sync_status = 0) are preserved so in-flight deliveries
          // are never lost.
          for (final localMatchId in matchUuidToLocalId.values) {
            await txn.delete(
              DatabaseHelper.tableBallEvents,
              where:
                  '${DatabaseHelper.colMatchId} = ? AND ${DatabaseHelper.colSyncStatus} = 1',
              whereArgs: [localMatchId],
            );
          }

          for (final raw in remoteBalls) {
            final r   = raw as Map<String, dynamic>;
            final muuid = r['match_id'] as String? ?? '';
            final localMatchId = matchUuidToLocalId[muuid];
            if (localMatchId == null) continue; // match not synced — skip

            final n = await txn.insert(
              DatabaseHelper.tableBallEvents,
              {
                DatabaseHelper.colMatchId:      localMatchId,
                DatabaseHelper.colInnings:      r['innings']        as int?    ?? 1,
                DatabaseHelper.colOverNum:      r['over_number']    as int?    ?? 0,
                DatabaseHelper.colBallNum:      r['ball_number']    as int?    ?? 0,
                DatabaseHelper.colRunsScored:   r['runs_scored']    as int?    ?? 0,
                DatabaseHelper.colIsBoundary:   (r['is_boundary']   as bool?   ?? false) ? 1 : 0,
                DatabaseHelper.colIsWicket:     (r['is_wicket']     as bool?   ?? false) ? 1 : 0,
                DatabaseHelper.colWicketType:   r['dismissal_type'] as String?,
                DatabaseHelper.colExtraType:    r['extra_type']     as String?,
                DatabaseHelper.colExtraRuns:    r['extra_runs']     as int?    ?? 0,
                DatabaseHelper.colStrikerId:    resolvePlayer(r['striker']),
                DatabaseHelper.colNonStrikerId: resolvePlayer(r['non_striker']),
                DatabaseHelper.colBowlerId:     resolvePlayer(r['bowler']),
                DatabaseHelper.colOutPlayerId:  resolvePlayer(r['player_out']),
                DatabaseHelper.colSyncStatus:   1,
                DatabaseHelper.colCreatedAt:    r['created_at'] as String?
                    ?? DateTime.now().toIso8601String(),
                DatabaseHelper.colCreatedBy:    r['created_by'] as String?,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            if (n > 0) ballEventsInserted++;
          }
        });
        developer.log(
          'syncDownInitialData: upserted $ballEventsInserted/${remoteBalls.length} ball_event(s)',
          name: 'SyncService',
        );
      } catch (e, st) {
        developer.log(
          'syncDownInitialData: failed to pull ball_events',
          name: 'SyncService',
          error: e,
          stackTrace: st,
          level: 900,
        );
        // Non-fatal — players + matches already landed successfully.
      }

      developer.log('syncDownInitialData: pull complete', name: 'SyncService');
      _setState(SyncState.synced);
    } catch (e, st) {
      developer.log(
        'syncDownInitialData: unexpected failure',
        name: 'SyncService',
        error: e,
        stackTrace: st,
        level: 1000,
      );
      _setState(SyncState.error);
    } finally {
      _isSyncingDown = false;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // DOWNWARD SYNC — ball_events for a specific match
  // ══════════════════════════════════════════════════════════════════════════

  /// Pull all `ball_events` rows for [matchUuid] from Supabase and replace
  /// the local copy in SQLite.
  ///
  /// Player UUID references in Supabase (`striker`, `non_striker`, `bowler`,
  /// `player_out`) are resolved to local integer IDs via the `players.uuid`
  /// column.  If a player UUID cannot be resolved (e.g. the player row has not
  /// yet been synced down) the FK is stored as NULL rather than failing.
  ///
  /// The local `matches.uuid` is used to look up the local integer `match_id`.
  ///
  /// Only rows with `sync_status = 1` (already pushed to Supabase) are deleted
  /// before the fresh batch is inserted.  Locally-created unsynced rows
  /// (`sync_status = 0`) are preserved so in-flight balls are never lost.
  Future<void> syncDownBallEvents(String matchUuid) async {
    try {
      // Require connectivity.
      final isOnline = await _checkConnectivity();
      if (!isOnline) {
        developer.log(
          'syncDownBallEvents: offline — skipping',
          name: 'SyncService',
        );
        return;
      }

      final db = await _db.database;

      // ── Resolve local integer match id ───────────────────────────────────
      final matchRows = await db.query(
        DatabaseHelper.tableMatches,
        columns: [DatabaseHelper.colId],
        where: '${DatabaseHelper.colUuid} = ?',
        whereArgs: [matchUuid],
        limit: 1,
      );
      if (matchRows.isEmpty) {
        developer.log(
          'syncDownBallEvents: local match not found for uuid=$matchUuid',
          name: 'SyncService',
          level: 800,
        );
        return;
      }
      final localMatchId = matchRows.first[DatabaseHelper.colId] as int;

      // ── Build a UUID → local_int_id cache for players ────────────────────
      final playerRows = await db.query(
        DatabaseHelper.tablePlayers,
        columns: [DatabaseHelper.colId, DatabaseHelper.colUuid],
      );
      final Map<String, int> uuidToLocalId = {
        for (final r in playerRows)
          if ((r[DatabaseHelper.colUuid] as String).isNotEmpty)
            r[DatabaseHelper.colUuid] as String: r[DatabaseHelper.colId] as int,
      };

      int? resolvePlayer(dynamic uuidVal) {
        if (uuidVal == null) return null;
        return uuidToLocalId[uuidVal as String];
      }

      // ── Fetch from Supabase ───────────────────────────────────────────────
      final remoteBalls = await _supabase
          .from('ball_events')
          .select()
          .eq('match_id', matchUuid);

      if ((remoteBalls as List).isEmpty) {
        developer.log(
          'syncDownBallEvents: no remote ball_events for match $matchUuid',
          name: 'SyncService',
        );
        return;
      }

      // ── Replace local synced rows with fresh batch from Supabase ─────────
      // Delete only rows that originated from Supabase (sync_status = 1).
      // Locally-created unsynced balls (sync_status = 0) are preserved so
      // the scorer never loses in-flight deliveries.
      int inserted = 0;
      await db.transaction((txn) async {
        await txn.delete(
          DatabaseHelper.tableBallEvents,
          where:
              '${DatabaseHelper.colMatchId} = ? AND ${DatabaseHelper.colSyncStatus} = 1',
          whereArgs: [localMatchId],
        );

        for (final raw in remoteBalls) {
          final r = raw as Map<String, dynamic>;

          final n = await txn.insert(
            DatabaseHelper.tableBallEvents,
            {
              DatabaseHelper.colMatchId:      localMatchId,
              DatabaseHelper.colInnings:      r['innings']        as int? ?? 1,
              DatabaseHelper.colOverNum:      r['over_number']    as int? ?? 0,
              DatabaseHelper.colBallNum:      r['ball_number']    as int? ?? 0,
              DatabaseHelper.colRunsScored:   r['runs_scored']    as int? ?? 0,
              DatabaseHelper.colIsBoundary:   (r['is_boundary']   as bool? ?? false) ? 1 : 0,
              DatabaseHelper.colIsWicket:     (r['is_wicket']     as bool? ?? false) ? 1 : 0,
              DatabaseHelper.colWicketType:   r['dismissal_type'] as String?,
              DatabaseHelper.colExtraType:    r['extra_type']     as String?,
              DatabaseHelper.colExtraRuns:    r['extra_runs']     as int? ?? 0,
              DatabaseHelper.colStrikerId:    resolvePlayer(r['striker']),
              DatabaseHelper.colNonStrikerId: resolvePlayer(r['non_striker']),
              DatabaseHelper.colBowlerId:     resolvePlayer(r['bowler']),
              DatabaseHelper.colOutPlayerId:  resolvePlayer(r['player_out']),
              DatabaseHelper.colSyncStatus:   1, // already in Supabase
              DatabaseHelper.colCreatedAt:    r['created_at'] as String?
                  ?? DateTime.now().toIso8601String(),
              DatabaseHelper.colCreatedBy:    r['created_by'] as String?,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          if (n > 0) inserted++;
        }
      });

      developer.log(
        'syncDownBallEvents: replaced with $inserted/${remoteBalls.length} ball_event(s) for match $matchUuid',
        name: 'SyncService',
      );
    } catch (e, st) {
      developer.log(
        'syncDownBallEvents: unexpected failure for match $matchUuid',
        name: 'SyncService',
        error: e,
        stackTrace: st,
        level: 1000,
      );
    }
  }
}
