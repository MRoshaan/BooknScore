import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'database_helper.dart';

/// Offline-first sync service that pushes unsynced local data to the FastAPI backend.
///
/// Usage:
/// ```dart
/// final syncService = ApiSyncService.instance;
/// await syncService.syncAll();
/// ```
class ApiSyncService {
  ApiSyncService._();
  static final ApiSyncService instance = ApiSyncService._();

  // ── Configuration ─────────────────────────────────────────────────────────
  // TODO: Replace with your actual FastAPI backend URL
  static const String _baseUrl = 'http://10.0.2.2:8000';
  
  // Endpoints
  static const String _matchesEndpoint    = '/matches';
  static const String _ballEventsEndpoint = '/ball-events';
  
  // Timeouts
  static const Duration _timeout = Duration(seconds: 10);

  // ── State ─────────────────────────────────────────────────────────────────
  bool _isSyncing = false;
  bool _isOnline = false;
  
  final _syncStatusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get syncStatusStream => _syncStatusController.stream;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Check if device has internet connectivity.
  Future<bool> checkConnectivity() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 5));
      _isOnline = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      _isOnline = false;
    } on TimeoutException catch (_) {
      _isOnline = false;
    }
    return _isOnline;
  }

  /// Returns current online status (last known).
  bool get isOnline => _isOnline;

  /// Sync all unsynced data to the backend.
  /// Returns a [SyncResult] with success/failure counts.
  Future<SyncResult> syncAll() async {
    if (_isSyncing) {
      return SyncResult(
        matchesSynced: 0,
        ballEventsSynced: 0,
        errors: ['Sync already in progress'],
      );
    }

    _isSyncing = true;
    _syncStatusController.add(SyncStatus.syncing);

    final errors = <String>[];
    int matchesSynced = 0;
    int ballEventsSynced = 0;

    try {
      // Check connectivity first
      final hasConnection = await checkConnectivity();
      if (!hasConnection) {
        _syncStatusController.add(SyncStatus.offline);
        return SyncResult(
          matchesSynced: 0,
          ballEventsSynced: 0,
          errors: ['No internet connection'],
        );
      }

      // Sync matches first (ball events depend on match IDs)
      final matchesResult = await _syncMatches();
      matchesSynced = matchesResult.successCount;
      errors.addAll(matchesResult.errors);

      // Sync ball events
      final ballEventsResult = await _syncBallEvents();
      ballEventsSynced = ballEventsResult.successCount;
      errors.addAll(ballEventsResult.errors);

      _syncStatusController.add(
        errors.isEmpty ? SyncStatus.synced : SyncStatus.partialSync,
      );
    } catch (e) {
      errors.add('Unexpected error: $e');
      _syncStatusController.add(SyncStatus.error);
    } finally {
      _isSyncing = false;
    }

    return SyncResult(
      matchesSynced: matchesSynced,
      ballEventsSynced: ballEventsSynced,
      errors: errors,
    );
  }

  /// Sync a single match immediately (useful after match creation).
  Future<bool> syncMatch(int matchId) async {
    if (!await checkConnectivity()) return false;

    try {
      final match = await DatabaseHelper.instance.fetchMatch(matchId);
      if (match == null) return false;

      final response = await http.post(
        Uri.parse('$_baseUrl$_matchesEndpoint'),
        headers: _headers,
        body: jsonEncode(_matchToJson(match)),
      ).timeout(_timeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        await DatabaseHelper.instance.markMatchSynced(matchId);
        return true;
      }
    } catch (e) {
      // Silently fail - will be retried on next sync
    }
    return false;
  }

  /// Dispose resources.
  void dispose() {
    _syncStatusController.close();
  }

  // ── Private Helpers ───────────────────────────────────────────────────────

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    // TODO: Add auth token when implementing authentication
    // 'Authorization': 'Bearer $token',
  };

  Future<_SyncBatchResult> _syncMatches() async {
    final errors = <String>[];
    int successCount = 0;

    try {
      final unsyncedMatches = await DatabaseHelper.instance.fetchUnsyncedMatches();

      for (final match in unsyncedMatches) {
        try {
          final response = await http.post(
            Uri.parse('$_baseUrl$_matchesEndpoint'),
            headers: _headers,
            body: jsonEncode(_matchToJson(match)),
          ).timeout(_timeout);

          if (response.statusCode == 200 || response.statusCode == 201) {
            final matchId = match[DatabaseHelper.colId] as int;
            await DatabaseHelper.instance.markMatchSynced(matchId);
            successCount++;
          } else {
            errors.add('Match ${match[DatabaseHelper.colId]}: HTTP ${response.statusCode}');
          }
        } on TimeoutException {
          errors.add('Match ${match[DatabaseHelper.colId]}: Request timeout');
        } catch (e) {
          errors.add('Match ${match[DatabaseHelper.colId]}: $e');
        }
      }
    } catch (e) {
      errors.add('Failed to fetch unsynced matches: $e');
    }

    return _SyncBatchResult(successCount: successCount, errors: errors);
  }

  Future<_SyncBatchResult> _syncBallEvents() async {
    final errors = <String>[];
    int successCount = 0;

    try {
      final unsyncedEvents = await DatabaseHelper.instance.fetchUnsyncedBallEvents();

      // Batch ball events by match for efficiency
      final eventsByMatch = <int, List<Map<String, dynamic>>>{};
      for (final event in unsyncedEvents) {
        final matchId = event[DatabaseHelper.colMatchId] as int;
        eventsByMatch.putIfAbsent(matchId, () => []).add(event);
      }

      for (final entry in eventsByMatch.entries) {
        try {
          final response = await http.post(
            Uri.parse('$_baseUrl$_ballEventsEndpoint/batch'),
            headers: _headers,
            body: jsonEncode({
              'match_id': entry.key,
              'events': entry.value.map(_ballEventToJson).toList(),
            }),
          ).timeout(_timeout);

          if (response.statusCode == 200 || response.statusCode == 201) {
            for (final event in entry.value) {
              final eventId = event[DatabaseHelper.colId] as int;
              await DatabaseHelper.instance.markBallEventSynced(eventId);
              successCount++;
            }
          } else {
            errors.add('Ball events for match ${entry.key}: HTTP ${response.statusCode}');
          }
        } on TimeoutException {
          errors.add('Ball events for match ${entry.key}: Request timeout');
        } catch (e) {
          errors.add('Ball events for match ${entry.key}: $e');
        }
      }
    } catch (e) {
      errors.add('Failed to fetch unsynced ball events: $e');
    }

    return _SyncBatchResult(successCount: successCount, errors: errors);
  }

  Map<String, dynamic> _matchToJson(Map<String, dynamic> match) {
    return {
      'local_id':        match[DatabaseHelper.colId],
      'team_a':          match[DatabaseHelper.colTeamA],
      'team_b':          match[DatabaseHelper.colTeamB],
      'total_overs':     match[DatabaseHelper.colTotalOvers],
      'toss_winner':     match[DatabaseHelper.colTossWinner],
      'opt_to':          match[DatabaseHelper.colOptTo],
      'status':          match[DatabaseHelper.colStatus],
      'current_innings': match[DatabaseHelper.colCurrentInnings],
      'created_at':      match[DatabaseHelper.colCreatedAt],
    };
  }

  Map<String, dynamic> _ballEventToJson(Map<String, dynamic> event) {
    return {
      'local_id':    event[DatabaseHelper.colId],
      'match_id':    event[DatabaseHelper.colMatchId],
      'innings':     event[DatabaseHelper.colInnings],
      'over_num':    event[DatabaseHelper.colOverNum],
      'ball_num':    event[DatabaseHelper.colBallNum],
      'runs_scored': event[DatabaseHelper.colRunsScored],
      'is_boundary': event[DatabaseHelper.colIsBoundary] == 1,
      'is_wicket':   event[DatabaseHelper.colIsWicket] == 1,
      'wicket_type': event[DatabaseHelper.colWicketType],
      'extra_type':  event[DatabaseHelper.colExtraType],
      'extra_runs':  event[DatabaseHelper.colExtraRuns],
      'created_at':  event[DatabaseHelper.colCreatedAt],
    };
  }
}

// ── Data Classes ──────────────────────────────────────────────────────────────

enum SyncStatus {
  idle,
  syncing,
  synced,
  partialSync,
  offline,
  error,
}

class SyncResult {
  final int matchesSynced;
  final int ballEventsSynced;
  final List<String> errors;

  SyncResult({
    required this.matchesSynced,
    required this.ballEventsSynced,
    required this.errors,
  });

  bool get hasErrors => errors.isNotEmpty;
  bool get isSuccess => errors.isEmpty;
  int get totalSynced => matchesSynced + ballEventsSynced;
}

class _SyncBatchResult {
  final int successCount;
  final List<String> errors;

  _SyncBatchResult({required this.successCount, required this.errors});
}
