import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../errors/errors.dart';
import '../models/verification_result.dart';
import '../services/supabase_service.dart';
import 'offline_checkin_service.dart';

const _tag = 'CheckInSyncService';

/// Background sync engine for offline check-ins.
///
/// Timer-based sync every 7 seconds when online. Reads from the sync queue,
/// batch-updates Supabase, and marks entries as synced. Handles conflict
/// resolution: local check-in wins over server for "already used" conflicts;
/// server "cancelled" status is respected and propagated locally.
class CheckInSyncService {
  final OfflineCheckInService _offlineService;
  final Connectivity _connectivity;

  Timer? _syncTimer;
  Timer? _refreshTimer;
  bool _isSyncing = false;
  bool _isOnline = true;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  /// Stream controller for connectivity status changes.
  final _connectivityController = StreamController<bool>.broadcast();

  /// Stream controller emitted after sync or door list refresh completes.
  final _statsChangedController = StreamController<void>.broadcast();

  /// Stream of connectivity status (true = online).
  Stream<bool> get connectivityStream => _connectivityController.stream;

  /// Emitted after sync queue drain or door list refresh so UI can update stats.
  Stream<void> get statsChangedStream => _statsChangedController.stream;

  bool get isOnline => _isOnline;
  bool get isSyncing => _isSyncing;

  CheckInSyncService({
    required OfflineCheckInService offlineService,
    Connectivity? connectivity,
  })  : _offlineService = offlineService,
        _connectivity = connectivity ?? Connectivity();

  /// Start listening to connectivity changes and begin sync loop.
  Future<void> startSyncLoop() async {
    AppLogger.info('Starting sync loop', tag: _tag);

    // Check initial connectivity
    final result = await _connectivity.checkConnectivity();
    _updateConnectivity(result);

    // Listen for changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _updateConnectivity,
    );

    // Start periodic sync (every 7 seconds)
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(
      const Duration(seconds: 7),
      (_) => _onSyncTick(),
    );

    // Start periodic door list refresh (every 60 seconds)
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _onRefreshTick(),
    );
  }

  /// Stop the sync loop and connectivity listener.
  void stopSyncLoop() {
    AppLogger.info('Stopping sync loop', tag: _tag);
    _syncTimer?.cancel();
    _syncTimer = null;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
  }

  void _updateConnectivity(List<ConnectivityResult> results) {
    final wasOnline = _isOnline;
    _isOnline = results.isNotEmpty &&
        !results.every((r) => r == ConnectivityResult.none);

    if (_isOnline != wasOnline) {
      AppLogger.info(
        'Connectivity changed: ${_isOnline ? "online" : "offline"}',
        tag: _tag,
      );
      _connectivityController.add(_isOnline);

      // Trigger immediate sync when coming back online
      if (_isOnline && !_isSyncing) {
        unawaited(syncPendingCheckIns());
      }
    }
  }

  void _onSyncTick() {
    if (_isOnline && !_isSyncing) {
      unawaited(syncPendingCheckIns());
    }
  }

  void _onRefreshTick() {
    if (_isOnline && _offlineService.currentEventId != null) {
      unawaited(refreshDoorList(_offlineService.currentEventId!));
    }
  }

  /// Sync pending check-ins to Supabase.
  ///
  /// Processes up to 50 entries per batch. Handles conflicts:
  /// - "already used" → mark synced (no conflict, both agree)
  /// - "cancelled" → update local status, mark synced with note
  /// - Network error → don't increment retry (will retry next cycle)
  /// - Server error → increment retry count
  Future<int> syncPendingCheckIns() async {
    if (_isSyncing || !_isOnline) return 0;
    _isSyncing = true;

    try {
      final queue = await _offlineService.getSyncQueue(limit: 50);
      if (queue.isEmpty) return 0;

      AppLogger.debug('Syncing ${queue.length} pending check-ins', tag: _tag);

      final client = SupabaseService.instance.client;
      final syncedIds = <int>[];
      int syncedCount = 0;

      for (final entry in queue) {
        try {
          if (entry.action == 'check_in') {
            await client.from('tickets').update({
              'checked_in_at': entry.timestamp,
              'checked_in_by': entry.usherId,
              'status': 'used',
            }).eq('id', entry.ticketId);
          } else if (entry.action == 'undo_check_in') {
            await client.from('tickets').update({
              'checked_in_at': null,
              'checked_in_by': null,
              'status': 'valid',
            }).eq('id', entry.ticketId);
          }

          syncedIds.add(entry.id!);
          syncedCount++;
        } catch (e) {
          final errorStr = e.toString().toLowerCase();

          // Network errors — don't count as retry, will try again next cycle
          if (errorStr.contains('network') ||
              errorStr.contains('socket') ||
              errorStr.contains('connection')) {
            AppLogger.debug(
              'Network error during sync, will retry: ${entry.ticketId}',
              tag: _tag,
            );
            break; // Stop processing remaining — likely all will fail
          }

          // "Already used" — server agrees, no conflict
          if (errorStr.contains('already') && errorStr.contains('used')) {
            syncedIds.add(entry.id!);
            syncedCount++;
            continue;
          }

          // "Cancelled" — server wins, update local
          if (errorStr.contains('cancelled') || errorStr.contains('canceled')) {
            await _offlineService.updateLocalStatus(
              entry.ticketId,
              'cancelled',
            );
            syncedIds.add(entry.id!);
            continue;
          }

          // Server error — increment retry
          AppLogger.error(
            'Sync failed for ticket ${entry.ticketId}: $e',
            tag: _tag,
          );
          if (entry.retryCount >= 4) {
            await _offlineService.markFailed(entry.id!, e.toString());
          } else {
            await _offlineService.markRetry(entry.id!, e.toString());
          }
        }
      }

      if (syncedIds.isNotEmpty) {
        await _offlineService.markSynced(syncedIds);
      }

      if (syncedCount > 0) {
        AppLogger.info('Synced $syncedCount check-ins', tag: _tag);
        _statsChangedController.add(null);
      }

      // Also sync verification flags
      await _syncVerificationFlags();

      return syncedCount;
    } catch (e) {
      AppLogger.error('Sync batch failed: $e', tag: _tag);
      return 0;
    } finally {
      _isSyncing = false;
    }
  }

  /// Sync verification discrepancy flags to Supabase.
  ///
  /// These are tickets that passed offline check but failed blockchain
  /// or database verification. Stored in `checkin_flags` table for
  /// admin review and investigation.
  Future<void> _syncVerificationFlags() async {
    try {
      final flags = await _offlineService.getUnsyncedFlags();
      if (flags.isEmpty) return;

      final client = SupabaseService.instance.client;

      for (final flag in flags) {
        try {
          await client.from('checkin_flags').insert({
            'ticket_id': flag['ticket_id'],
            'event_id': flag['event_id'],
            'flag_type': flag['flag_type'],
            'tier': flag['tier'],
            'message': flag['message'],
            'flagged_by': flag['usher_id'],
            'flagged_at': flag['timestamp'],
          });
          await _offlineService.markFlagSynced(flag['id'] as int);
        } catch (e) {
          // Non-critical — will retry next cycle
          AppLogger.debug(
            'Failed to sync verification flag: $e',
            tag: _tag,
          );
        }
      }
    } catch (e) {
      AppLogger.debug('Flag sync failed: $e', tag: _tag);
    }
  }

  /// Refresh the door list from the server, merging with local state.
  ///
  /// Preserves unsynced local check-ins (local wins over server for those).
  Future<void> refreshDoorList(String eventId) async {
    if (!_isOnline) return;

    try {
      // downloadDoorList already preserves unsynced local check-ins
      await _offlineService.downloadDoorList(eventId);
      AppLogger.debug('Door list refreshed for event: $eventId', tag: _tag);
      _statsChangedController.add(null);
    } catch (e) {
      AppLogger.error('Door list refresh failed: $e', tag: _tag);
    }
  }

  /// Verify a ticket's status against the live database.
  ///
  /// Returns the server-side status, or null if offline/error.
  Future<String?> verifyWithDatabase(String eventId, String ticketId) async {
    if (!_isOnline) return null;

    try {
      final client = SupabaseService.instance.client;
      final response = await client
          .from('tickets')
          .select('status')
          .eq('id', ticketId)
          .eq('event_id', eventId)
          .maybeSingle();

      if (response == null) return null;
      return response['status'] as String?;
    } catch (e) {
      AppLogger.debug('DB verification failed: $e', tag: _tag);
      return null;
    }
  }

  /// Look up a ticket from the database when not found in local cache.
  Future<DoorListEntry?> lookupFromDatabase(
    String eventId,
    String ticketIdOrNumber,
  ) async {
    if (!_isOnline) return null;

    try {
      final client = SupabaseService.instance.client;

      // Try by ID first
      var response = await client
          .from('tickets')
          .select(
            'id, ticket_number, event_id, status, owner_name, owner_email, '
            'nft_asset_id, nft_policy_id, nft_tx_hash, checked_in_at, checked_in_by',
          )
          .eq('event_id', eventId)
          .eq('id', ticketIdOrNumber)
          .maybeSingle();

      // Try by ticket number
      response ??= await client
          .from('tickets')
          .select(
            'id, ticket_number, event_id, status, owner_name, owner_email, '
            'nft_asset_id, nft_policy_id, nft_tx_hash, checked_in_at, checked_in_by',
          )
          .eq('event_id', eventId)
          .eq('ticket_number', ticketIdOrNumber)
          .maybeSingle();

      if (response == null) return null;

      final entry = DoorListEntry(
        ticketId: response['id'] as String,
        ticketNumber: response['ticket_number'] as String,
        eventId: eventId,
        status: response['status'] as String? ?? 'valid',
        ownerName: response['owner_name'] as String?,
        ownerEmail: response['owner_email'] as String?,
        nftAssetId: response['nft_asset_id'] as String?,
        nftPolicyId: response['nft_policy_id'] as String?,
        nftTxHash: response['nft_tx_hash'] as String?,
        checkedInAt: response['checked_in_at'] as String?,
        checkedInBy: response['checked_in_by'] as String?,
        updatedAt: DateTime.now().toUtc().toIso8601String(),
      );

      // Add to local cache for future offline lookups
      await _offlineService.addToCache(entry);

      return entry;
    } catch (e) {
      AppLogger.debug('DB lookup failed: $e', tag: _tag);
      return null;
    }
  }

  void dispose() {
    stopSyncLoop();
    _connectivityController.close();
    _statsChangedController.close();
  }
}
