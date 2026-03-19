import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env_config.dart';
import '../errors/errors.dart';
import '../models/verification_result.dart';
import '../services/blockchain_verify_service.dart';
import '../services/checkin_sync_service.dart';
import '../services/nfc_service.dart';
import '../services/offline_checkin_service.dart';
import '../services/supabase_service.dart';

const _tag = 'OfflineCheckInProvider';

/// State for the offline check-in system.
class OfflineCheckInState {
  final bool isDoorListLoaded;
  final bool isDownloading;
  final int totalTickets;
  final int checkedInCount;
  final int pendingSyncCount;
  final int totalRedeemable;
  final int redeemedCount;
  final bool isOnline;
  final DateTime? lastSyncTime;
  final DateTime? doorListDownloadedAt;
  final VerificationResult? currentVerification;
  final bool isVerifying;
  final String? error;

  const OfflineCheckInState({
    this.isDoorListLoaded = false,
    this.isDownloading = false,
    this.totalTickets = 0,
    this.checkedInCount = 0,
    this.pendingSyncCount = 0,
    this.totalRedeemable = 0,
    this.redeemedCount = 0,
    this.isOnline = true,
    this.lastSyncTime,
    this.doorListDownloadedAt,
    this.currentVerification,
    this.isVerifying = false,
    this.error,
  });

  OfflineCheckInState copyWith({
    bool? isDoorListLoaded,
    bool? isDownloading,
    int? totalTickets,
    int? checkedInCount,
    int? pendingSyncCount,
    int? totalRedeemable,
    int? redeemedCount,
    bool? isOnline,
    DateTime? lastSyncTime,
    DateTime? doorListDownloadedAt,
    VerificationResult? currentVerification,
    bool? isVerifying,
    String? error,
    bool clearError = false,
    bool clearVerification = false,
  }) {
    return OfflineCheckInState(
      isDoorListLoaded: isDoorListLoaded ?? this.isDoorListLoaded,
      isDownloading: isDownloading ?? this.isDownloading,
      totalTickets: totalTickets ?? this.totalTickets,
      checkedInCount: checkedInCount ?? this.checkedInCount,
      pendingSyncCount: pendingSyncCount ?? this.pendingSyncCount,
      totalRedeemable: totalRedeemable ?? this.totalRedeemable,
      redeemedCount: redeemedCount ?? this.redeemedCount,
      isOnline: isOnline ?? this.isOnline,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      doorListDownloadedAt: doorListDownloadedAt ?? this.doorListDownloadedAt,
      currentVerification:
          clearVerification ? null : (currentVerification ?? this.currentVerification),
      isVerifying: isVerifying ?? this.isVerifying,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Notifier for offline check-in state management.
class OfflineCheckInNotifier extends StateNotifier<OfflineCheckInState> {
  final OfflineCheckInService _offlineService;
  final CheckInSyncService _syncService;
  final BlockchainVerifyService _blockchainService;

  StreamSubscription<bool>? _connectivitySubscription;
  StreamSubscription<void>? _statsSubscription;

  OfflineCheckInNotifier({
    required OfflineCheckInService offlineService,
    required CheckInSyncService syncService,
    required BlockchainVerifyService blockchainService,
  })  : _offlineService = offlineService,
        _syncService = syncService,
        _blockchainService = blockchainService,
        super(const OfflineCheckInState()) {
    // Listen for connectivity changes
    _connectivitySubscription = _syncService.connectivityStream.listen(
      (isOnline) {
        if (mounted) {
          state = state.copyWith(isOnline: isOnline);
          if (isOnline) _refreshStats();
        }
      },
    );

    // Listen for background sync/refresh completions to update stats
    _statsSubscription = _syncService.statsChangedStream.listen((_) {
      if (mounted) _refreshStats();
    });
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _statsSubscription?.cancel();
    _syncService.stopSyncLoop();
    super.dispose();
  }

  /// Download the door list for an event and start sync loop.
  Future<void> downloadDoorList(String eventId) async {
    state = state.copyWith(isDownloading: true, clearError: true);

    try {
      AppLogger.info('Downloading door list for event: $eventId', tag: _tag);
      await _offlineService.downloadDoorList(eventId);

      // Start background sync
      await _syncService.startSyncLoop();

      await _refreshStats();

      state = state.copyWith(
        isDoorListLoaded: true,
        isDownloading: false,
        doorListDownloadedAt: _offlineService.doorListDownloadedAt,
        isOnline: _syncService.isOnline,
      );

      AppLogger.info(
        'Door list ready: ${state.totalTickets} tickets',
        tag: _tag,
      );
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Failed to download door list',
        error: e,
        stackTrace: s,
        tag: _tag,
      );
      state = state.copyWith(
        isDownloading: false,
        error: appError.userMessage,
      );
    }
  }

  /// Run the 4-layer verification pipeline for a scanned ticket.
  ///
  /// [nfcPayload] is optional — when provided (from NFC scan), Layer 0
  /// verifies the HMAC signature embedded in the payload. This enables
  /// admission with zero network and zero SQLite cache.
  Future<VerificationResult> verifyTicket(
    String ticketIdOrNumber,
    String eventId, {
    TicketNfcPayload? nfcPayload,
  }) async {
    state = state.copyWith(
      isVerifying: true,
      clearVerification: true,
      clearError: true,
    );

    var result = VerificationResult.initial();
    state = state.copyWith(currentVerification: result);

    bool admittable = false;

    // ── Layer 0: NFC Payload Verification (instant, no lookup needed) ──
    if (nfcPayload != null && nfcPayload.signature != null) {
      result = result.updateTier(
        VerificationTier.nfcPayload,
        const TierResult(
          status: TierStatus.verifying,
          message: 'Verifying NFC signature...',
        ),
      );
      state = state.copyWith(currentVerification: result);

      try {
        final secret = EnvConfig.ticketSigningSecret;
        final signatureValid = nfcPayload.verifySignature(secret);

        if (signatureValid && nfcPayload.eventId == eventId) {
          result = result.updateTier(
            VerificationTier.nfcPayload,
            TierResult(
              status: TierStatus.verified,
              message: 'Signature valid (${nfcPayload.category})',
            ),
          );
          admittable = true;
        } else if (!signatureValid) {
          result = result.updateTier(
            VerificationTier.nfcPayload,
            const TierResult(
              status: TierStatus.failed,
              message: 'Invalid signature — possible forgery',
            ),
          );
        } else {
          result = result.updateTier(
            VerificationTier.nfcPayload,
            const TierResult(
              status: TierStatus.failed,
              message: 'Event ID mismatch',
            ),
          );
        }
      } catch (_) {
        // Signing secret not configured — skip Layer 0
        result = result.updateTier(
          VerificationTier.nfcPayload,
          const TierResult(
            status: TierStatus.skipped,
            message: 'Signing key not configured',
          ),
        );
      }
    } else {
      // No NFC payload or no signature — skip Layer 0
      result = result.updateTier(
        VerificationTier.nfcPayload,
        TierResult(
          status: TierStatus.skipped,
          message: nfcPayload == null ? 'QR scan — no NFC data' : 'No signature on ticket',
        ),
      );
    }

    state = state.copyWith(currentVerification: result);

    // ── Layer 1: Offline Cache (instant) ──
    result = result.updateTier(
      VerificationTier.offline,
      const TierResult(status: TierStatus.verifying, message: 'Checking local cache...'),
    );
    state = state.copyWith(currentVerification: result);

    var entry = _offlineService.lookupTicket(ticketIdOrNumber);

    if (entry != null) {
      if (entry.isValid) {
        // Entry ticket that was already checked in — still admittable (re-entry)
        final alreadyCheckedIn = entry.checkedInAt != null;
        final message = alreadyCheckedIn
            ? 'Re-entry — checked in at ${_formatTime(entry.checkedInAt!)}'
            : 'Found in door list';
        result = VerificationResult(
          tiers: {
            ...result.tiers,
            VerificationTier.offline: TierResult(
              status: TierStatus.verified,
              message: message,
            ),
          },
          ticket: entry,
          isAdmittable: true,
        );
        admittable = true;
      } else if (entry.isUsed) {
        // 'used' status only applies to redeemable items (consumed)
        // Entry tickets stay 'valid' after check-in, so hitting 'used'
        // here means it's a redeemable that was already redeemed.
        result = VerificationResult(
          tiers: {
            ...result.tiers,
            VerificationTier.offline: const TierResult(
              status: TierStatus.failed,
              message: 'Already redeemed',
            ),
          },
          ticket: entry,
          isAdmittable: false,
        );
        admittable = false;
      } else {
        result = VerificationResult(
          tiers: {
            ...result.tiers,
            VerificationTier.offline: TierResult(
              status: TierStatus.failed,
              message: 'Ticket ${entry.status}',
            ),
          },
          ticket: entry,
          isAdmittable: false,
        );
        admittable = false;
      }
    } else {
      // Not found in local cache
      if (!_syncService.isOnline && !admittable) {
        // No cache, no network, and Layer 0 didn't verify — deny
        result = VerificationResult(
          tiers: {
            ...result.tiers,
            VerificationTier.offline: const TierResult(
              status: TierStatus.failed,
              message: 'Not in door list (offline)',
            ),
          },
          isAdmittable: false,
        );
        state = state.copyWith(
          currentVerification: _skipRemainingTiers(result),
          isVerifying: false,
        );
        return result;
      }

      if (!_syncService.isOnline && admittable) {
        // No cache, no network, but Layer 0 verified — admit on NFC signature alone
        result = result.updateTier(
          VerificationTier.offline,
          const TierResult(
            status: TierStatus.skipped,
            message: 'No door list (admitted via NFC signature)',
          ),
        );
        state = state.copyWith(
          currentVerification: _skipRemainingTiers(result),
          isVerifying: false,
        );
        return result;
      }

      result = result.updateTier(
        VerificationTier.offline,
        const TierResult(
          status: TierStatus.failed,
          message: 'Not in local cache',
        ),
      );
    }

    state = state.copyWith(currentVerification: result);

    // ── Tiers 2 & 3 run in parallel ──
    final blockchainFuture = _runBlockchainTier(entry);
    final databaseFuture = _runDatabaseTier(eventId, ticketIdOrNumber, entry);

    final results = await Future.wait([blockchainFuture, databaseFuture]);
    final blockchainTier = results[0] as TierResult;
    final dbResult = results[1] as (TierResult, DoorListEntry?);
    final databaseTier = dbResult.$1;
    final dbEntry = dbResult.$2;

    // If ticket was found on server but not locally, update
    if (entry == null && dbEntry != null) {
      entry = dbEntry;
      admittable = entry.isValid;
    }

    result = VerificationResult(
      tiers: {
        ...result.tiers,
        VerificationTier.blockchain: blockchainTier,
        VerificationTier.database: databaseTier,
      },
      ticket: entry ?? result.ticket,
      isAdmittable: admittable,
    );

    // Record discrepancy if admitted offline but a later tier failed
    if (admittable && entry != null) {
      final userId =
          SupabaseService.instance.currentUser?.id ?? 'unknown';

      if (blockchainTier.status == TierStatus.failed) {
        _offlineService.recordVerificationFlag(
          ticketId: entry.ticketId,
          eventId: eventId,
          flagType: 'blockchain_failed',
          tier: 'blockchain',
          message: blockchainTier.message ?? 'Blockchain verification failed',
          usherId: userId,
        );
        AppLogger.warning(
          'Verification flag: ticket ${entry.ticketNumber} admitted '
          'but blockchain failed — ${blockchainTier.message}',
          tag: _tag,
        );
      }

      if (databaseTier.status == TierStatus.failed) {
        _offlineService.recordVerificationFlag(
          ticketId: entry.ticketId,
          eventId: eventId,
          flagType: 'database_mismatch',
          tier: 'database',
          message: databaseTier.message ?? 'Database verification failed',
          usherId: userId,
        );
        AppLogger.warning(
          'Verification flag: ticket ${entry.ticketNumber} admitted '
          'but database failed — ${databaseTier.message}',
          tag: _tag,
        );
      }
    }

    state = state.copyWith(
      currentVerification: result,
      isVerifying: false,
    );

    return result;
  }

  /// Format an ISO 8601 timestamp to a short time string like "7:32 PM".
  String _formatTime(String isoTimestamp) {
    try {
      final dt = DateTime.parse(isoTimestamp).toLocal();
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final minute = dt.minute.toString().padLeft(2, '0');
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$minute $period';
    } catch (_) {
      return isoTimestamp;
    }
  }

  Future<TierResult> _runBlockchainTier(DoorListEntry? entry) async {
    if (entry == null || !entry.hasNft) {
      return const TierResult(
        status: TierStatus.skipped,
        message: 'N/A',
      );
    }

    try {
      // Update UI to show verifying
      final verifyingResult = state.currentVerification?.updateTier(
        VerificationTier.blockchain,
        const TierResult(
          status: TierStatus.verifying,
          message: 'Verifying NFT ownership...',
        ),
      );
      if (verifyingResult != null) {
        state = state.copyWith(currentVerification: verifyingResult);
      }

      final blockchainResult =
          await _blockchainService.verifyNftOwnership(entry);

      return switch (blockchainResult.status) {
        BlockchainVerifyStatus.verified => TierResult(
            status: TierStatus.verified,
            message: blockchainResult.message,
          ),
        BlockchainVerifyStatus.skipped => TierResult(
            status: TierStatus.skipped,
            message: blockchainResult.message,
          ),
        _ => TierResult(
            status: TierStatus.failed,
            message: blockchainResult.message,
          ),
      };
    } catch (e) {
      return TierResult(
        status: TierStatus.failed,
        message: 'Blockchain error: $e',
      );
    }
  }

  Future<(TierResult, DoorListEntry?)> _runDatabaseTier(
    String eventId,
    String ticketIdOrNumber,
    DoorListEntry? localEntry,
  ) async {
    if (!_syncService.isOnline) {
      return (
        const TierResult(
          status: TierStatus.skipped,
          message: 'Offline — will verify later',
        ),
        null,
      );
    }

    try {
      // Update UI to show verifying
      final verifyingResult = state.currentVerification?.updateTier(
        VerificationTier.database,
        const TierResult(
          status: TierStatus.verifying,
          message: 'Checking database...',
        ),
      );
      if (verifyingResult != null) {
        state = state.copyWith(currentVerification: verifyingResult);
      }

      if (localEntry != null) {
        // Verify against server
        final serverStatus = await _syncService.verifyWithDatabase(
          eventId,
          localEntry.ticketId,
        );

        if (serverStatus == null) {
          return (
            const TierResult(
              status: TierStatus.failed,
              message: 'Could not reach server',
            ),
            null,
          );
        }

        if (serverStatus == localEntry.status) {
          return (
            const TierResult(
              status: TierStatus.verified,
              message: 'Database confirmed',
            ),
            null,
          );
        }

        // Discrepancy — update local if server says cancelled
        if (serverStatus == 'cancelled' || serverStatus == 'refunded') {
          await _offlineService.updateLocalStatus(
            localEntry.ticketId,
            serverStatus,
          );
          return (
            TierResult(
              status: TierStatus.failed,
              message: 'Server status: $serverStatus',
            ),
            null,
          );
        }

        return (
          TierResult(
            status: TierStatus.verified,
            message: 'Status differs (local: ${localEntry.status}, server: $serverStatus)',
          ),
          null,
        );
      } else {
        // Not found locally — try server lookup
        final dbEntry = await _syncService.lookupFromDatabase(
          eventId,
          ticketIdOrNumber,
        );

        if (dbEntry == null) {
          return (
            const TierResult(
              status: TierStatus.failed,
              message: 'Not found in database',
            ),
            null,
          );
        }

        return (
          const TierResult(
            status: TierStatus.verified,
            message: 'Found on server, added to cache',
          ),
          dbEntry,
        );
      }
    } catch (e) {
      return (
        TierResult(
          status: TierStatus.failed,
          message: 'Database error: $e',
        ),
        null,
      );
    }
  }

  VerificationResult _skipRemainingTiers(VerificationResult result) {
    return VerificationResult(
      tiers: {
        ...result.tiers,
        if (result.getTier(VerificationTier.nfcPayload).status == TierStatus.pending)
          VerificationTier.nfcPayload: const TierResult(
            status: TierStatus.skipped,
            message: 'N/A',
          ),
        if (result.getTier(VerificationTier.blockchain).status == TierStatus.pending)
          VerificationTier.blockchain: const TierResult(
            status: TierStatus.skipped,
            message: 'Offline',
          ),
        if (result.getTier(VerificationTier.database).status == TierStatus.pending)
          VerificationTier.database: const TierResult(
            status: TierStatus.skipped,
            message: 'Offline',
          ),
      },
      ticket: result.ticket,
      isAdmittable: result.isAdmittable,
    );
  }

  /// Confirm check-in for a verified ticket.
  Future<bool> confirmCheckIn(String ticketId) async {
    try {
      final userId = SupabaseService.instance.currentUser?.id ?? 'unknown';
      await _offlineService.markCheckedIn(ticketId, userId);
      await _refreshStats();

      AppLogger.info('Local check-in confirmed: $ticketId', tag: _tag);
      return true;
    } catch (e) {
      AppLogger.error('Failed to confirm check-in: $e', tag: _tag);
      state = state.copyWith(error: 'Failed to check in ticket');
      return false;
    }
  }

  /// Undo a check-in.
  Future<bool> undoCheckIn(String ticketId) async {
    try {
      final userId = SupabaseService.instance.currentUser?.id ?? 'unknown';
      await _offlineService.markUndoCheckIn(ticketId, userId);
      await _refreshStats();

      AppLogger.info('Check-in undone: $ticketId', tag: _tag);
      return true;
    } catch (e) {
      AppLogger.error('Failed to undo check-in: $e', tag: _tag);
      state = state.copyWith(error: 'Failed to undo check-in');
      return false;
    }
  }

  /// Clear the current verification result.
  void clearVerification() {
    state = state.copyWith(clearVerification: true);
  }

  /// Refresh stats from the local service.
  Future<void> _refreshStats() async {
    final stats = _offlineService.getLocalStats();
    final catStats = _offlineService.getStatsByCategory();
    final pendingSync = await _offlineService.getPendingSyncCount();

    state = state.copyWith(
      totalTickets: stats.totalTickets,
      checkedInCount: stats.checkedIn,
      pendingSyncCount: pendingSync,
      totalRedeemable: catStats.totalRedeemable,
      redeemedCount: catStats.redeemedRedeemable,
      doorListDownloadedAt: _offlineService.doorListDownloadedAt,
    );
  }

  /// Force refresh stats (public).
  Future<void> refreshStats() => _refreshStats();
}

// ============================================================
// PROVIDERS
// ============================================================

/// Service providers (can be overridden for testing).
final offlineCheckInServiceProvider = Provider<OfflineCheckInService>((ref) {
  return OfflineCheckInService();
});

final checkInSyncServiceProvider = Provider<CheckInSyncService>((ref) {
  final offlineService = ref.watch(offlineCheckInServiceProvider);
  return CheckInSyncService(offlineService: offlineService);
});

final blockchainVerifyServiceProvider = Provider<BlockchainVerifyService>((ref) {
  return BlockchainVerifyService();
});

/// Door list cache info for a given event ID.
/// Returns cached status, ticket count, and data size.
/// Auto-disposes so it re-checks when navigating back to My Events.
final doorListCachedProvider = FutureProvider.autoDispose
    .family<({bool cached, int ticketCount, int sizeBytes}), String>(
        (ref, eventId) {
  final offlineService = ref.watch(offlineCheckInServiceProvider);
  return offlineService.getDoorListInfo(eventId);
});

/// Main offline check-in provider.
final offlineCheckInProvider =
    StateNotifierProvider<OfflineCheckInNotifier, OfflineCheckInState>((ref) {
  final offlineService = ref.watch(offlineCheckInServiceProvider);
  final syncService = ref.watch(checkInSyncServiceProvider);
  final blockchainService = ref.watch(blockchainVerifyServiceProvider);

  return OfflineCheckInNotifier(
    offlineService: offlineService,
    syncService: syncService,
    blockchainService: blockchainService,
  );
});
