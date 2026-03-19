import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../errors/errors.dart';
import '../models/verification_result.dart';
import '../services/supabase_service.dart';

const _tag = 'OfflineCheckInService';

/// Local SQLite door list manager with O(1) HashMap lookups.
///
/// Manages the `checkin_cache.db` database with `door_list` and `sync_queue`
/// tables. Builds an in-memory HashMap keyed by both ticket_id and
/// ticket_number for instant lookups during scanning.
class OfflineCheckInService {
  Database? _db;

  /// In-memory index: ticket_id AND ticket_number → DoorListEntry.
  /// Two keys per entry for O(1) lookup by either.
  final Map<String, DoorListEntry> _index = {};

  DateTime? _doorListDownloadedAt;
  DateTime? _lastSyncTime;
  String? _currentEventId;

  DateTime? get doorListDownloadedAt => _doorListDownloadedAt;
  DateTime? get lastSyncTime => _lastSyncTime;
  String? get currentEventId => _currentEventId;
  bool get isDoorListLoaded => _index.isNotEmpty || _currentEventId != null;

  /// Initialize with an existing database (for testing).
  OfflineCheckInService({Database? database}) : _db = database;

  /// Get or open the SQLite database.
  Future<Database> _getDb() async {
    if (_db != null) return _db!;

    // Use FFI for desktop platforms
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'checkin_cache.db');

    _db = await openDatabase(
      path,
      version: 5,
      onCreate: _createTables,
      onUpgrade: _upgradeTables,
    );

    return _db!;
  }

  Future<void> _createTables(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS door_list (
        ticket_id TEXT PRIMARY KEY,
        ticket_number TEXT NOT NULL,
        event_id TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'valid',
        owner_name TEXT,
        owner_email TEXT,
        nft_asset_id TEXT,
        nft_policy_id TEXT,
        nft_tx_hash TEXT,
        seat_label TEXT,
        category TEXT DEFAULT 'entry',
        item_icon TEXT,
        checked_in_at TEXT,
        checked_in_by TEXT,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_door_list_ticket_number
      ON door_list(ticket_number)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_door_list_event_id
      ON door_list(event_id)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS door_list_meta (
        event_id TEXT PRIMARY KEY,
        downloaded_at TEXT NOT NULL,
        ticket_count INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ticket_id TEXT NOT NULL,
        event_id TEXT NOT NULL,
        action TEXT NOT NULL,
        usher_id TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0,
        retry_count INTEGER NOT NULL DEFAULT 0,
        error_message TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS verification_flags (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ticket_id TEXT NOT NULL,
        event_id TEXT NOT NULL,
        flag_type TEXT NOT NULL,
        tier TEXT NOT NULL,
        message TEXT,
        usher_id TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<void> _upgradeTables(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS door_list_meta (
          event_id TEXT PRIMARY KEY,
          downloaded_at TEXT NOT NULL,
          ticket_count INTEGER NOT NULL DEFAULT 0
        )
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE door_list ADD COLUMN seat_label TEXT');
    }
    if (oldVersion < 4) {
      await db.execute("ALTER TABLE door_list ADD COLUMN category TEXT DEFAULT 'entry'");
      await db.execute('ALTER TABLE door_list ADD COLUMN item_icon TEXT');
    }
    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS verification_flags (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          ticket_id TEXT NOT NULL,
          event_id TEXT NOT NULL,
          flag_type TEXT NOT NULL,
          tier TEXT NOT NULL,
          message TEXT,
          usher_id TEXT NOT NULL,
          timestamp TEXT NOT NULL,
          synced INTEGER NOT NULL DEFAULT 0
        )
      ''');
    }
  }

  /// Get door list cache info for a given event.
  /// Returns whether downloaded, ticket count, and approximate data size.
  Future<({bool cached, int ticketCount, int sizeBytes})> getDoorListInfo(
    String eventId,
  ) async {
    try {
      final db = await _getDb();

      // Check if this event was ever downloaded (including 0-ticket downloads)
      final meta = await db.query(
        'door_list_meta',
        where: 'event_id = ?',
        whereArgs: [eventId],
        limit: 1,
      );
      if (meta.isEmpty) {
        return (cached: false, ticketCount: 0, sizeBytes: 0);
      }

      final result = await db.rawQuery(
        'SELECT COUNT(*) as cnt, COALESCE(SUM(LENGTH(ticket_id) + LENGTH(ticket_number) + '
        'LENGTH(COALESCE(owner_name, \'\')) + LENGTH(COALESCE(owner_email, \'\')) + '
        'LENGTH(COALESCE(nft_asset_id, \'\')) + LENGTH(COALESCE(nft_policy_id, \'\')) + '
        'LENGTH(COALESCE(nft_tx_hash, \'\')) + LENGTH(status) + '
        'LENGTH(event_id) + 80), 0) as size_bytes '
        'FROM door_list WHERE event_id = ?',
        [eventId],
      );
      final count = (result.first['cnt'] as int?) ?? 0;
      final sizeBytes = (result.first['size_bytes'] as int?) ?? 0;
      return (cached: true, ticketCount: count, sizeBytes: sizeBytes);
    } catch (e) {
      return (cached: false, ticketCount: 0, sizeBytes: 0);
    }
  }

  /// Download the full door list for an event from Supabase.
  Future<int> downloadDoorList(String eventId) async {
    AppLogger.info('Downloading door list for event: $eventId', tag: _tag);

    final client = SupabaseService.instance.client;
    final response = await client
        .from('tickets')
        .select(
          'id, ticket_number, event_id, status, owner_name, owner_email, '
          'nft_asset_id, nft_policy_id, nft_tx_hash, seat_label, checked_in_at, checked_in_by',
        )
        .eq('event_id', eventId)
        .inFilter('status', ['valid', 'used'])
        .order('ticket_number');

    final tickets = response as List<dynamic>;

    final db = await _getDb();

    // Get existing unsynced local check-ins to preserve
    final unsyncedIds = <String>{};
    final unsyncedEntries = await db.query(
      'sync_queue',
      columns: ['ticket_id'],
      where: 'event_id = ? AND synced = 0',
      whereArgs: [eventId],
    );
    for (final row in unsyncedEntries) {
      unsyncedIds.add(row['ticket_id'] as String);
    }

    // Upsert tickets into SQLite
    final batch = db.batch();
    for (final json in tickets) {
      final map = json as Map<String, dynamic>;
      final ticketId = map['id'] as String;

      // Skip overwriting locally-modified tickets
      if (unsyncedIds.contains(ticketId)) continue;

      batch.insert(
        'door_list',
        {
          'ticket_id': ticketId,
          'ticket_number': map['ticket_number'] as String,
          'event_id': eventId,
          'status': map['status'] as String? ?? 'valid',
          'owner_name': map['owner_name'] as String?,
          'owner_email': map['owner_email'] as String?,
          'nft_asset_id': map['nft_asset_id'] as String?,
          'nft_policy_id': map['nft_policy_id'] as String?,
          'nft_tx_hash': map['nft_tx_hash'] as String?,
          'seat_label': map['seat_label'] as String?,
          'checked_in_at': map['checked_in_at'] as String?,
          'checked_in_by': map['checked_in_by'] as String?,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);

    // Build HashMap index
    await _buildIndex(eventId);

    _currentEventId = eventId;
    _doorListDownloadedAt = DateTime.now();

    // Record that this event was downloaded (even if 0 tickets)
    await db.insert(
      'door_list_meta',
      {
        'event_id': eventId,
        'downloaded_at': _doorListDownloadedAt!.toUtc().toIso8601String(),
        'ticket_count': tickets.length,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    AppLogger.info(
      'Door list downloaded: ${tickets.length} tickets, index size: ${_index.length}',
      tag: _tag,
    );

    return tickets.length;
  }

  /// Build the in-memory HashMap index from SQLite.
  Future<void> _buildIndex(String eventId) async {
    final db = await _getDb();
    final rows = await db.query(
      'door_list',
      where: 'event_id = ?',
      whereArgs: [eventId],
    );

    _index.clear();
    for (final row in rows) {
      final entry = DoorListEntry.fromMap(row);
      _index[entry.ticketId] = entry;
      _index[entry.ticketNumber] = entry;
    }
  }

  /// O(1) lookup by ticket_id or ticket_number.
  DoorListEntry? lookupTicket(String ticketIdOrNumber) {
    return _index[ticketIdOrNumber];
  }

  /// Mark a ticket as checked in locally and enqueue for sync.
  ///
  /// For entry tickets: status stays 'valid', only checked_in_at/by are set.
  /// The ticket remains admittable on re-scan (re-entry allowed) but resale
  /// is blocked by the checked_in_at timestamp.
  ///
  /// For redeemable tickets: status changes to 'used' (consumed, deny re-scan).
  Future<void> markCheckedIn(String ticketId, String usherId) async {
    final entry = _index[ticketId];
    if (entry == null) return;

    final now = DateTime.now().toUtc().toIso8601String();

    // Redeemable items are consumed — mark 'used'. Entry tickets stay 'valid'.
    final newStatus = entry.isRedeemable ? 'used' : entry.status;

    // Update in-memory
    entry.status = newStatus;
    entry.checkedInAt = now;
    entry.checkedInBy = usherId;

    // Update SQLite
    final db = await _getDb();
    await db.update(
      'door_list',
      {
        'status': newStatus,
        'checked_in_at': now,
        'checked_in_by': usherId,
        'updated_at': now,
      },
      where: 'ticket_id = ?',
      whereArgs: [ticketId],
    );

    // Enqueue for sync
    await db.insert('sync_queue', {
      'ticket_id': ticketId,
      'event_id': entry.eventId,
      'action': 'check_in',
      'usher_id': usherId,
      'timestamp': now,
      'synced': 0,
      'retry_count': 0,
    });

    AppLogger.debug('Marked checked in locally: $ticketId', tag: _tag);
  }

  /// Undo a local check-in and enqueue for sync.
  Future<void> markUndoCheckIn(String ticketId, String usherId) async {
    final entry = _index[ticketId];
    if (entry == null) return;

    final now = DateTime.now().toUtc().toIso8601String();

    // Update in-memory
    entry.status = 'valid';
    entry.checkedInAt = null;
    entry.checkedInBy = null;

    // Update SQLite
    final db = await _getDb();
    await db.update(
      'door_list',
      {
        'status': 'valid',
        'checked_in_at': null,
        'checked_in_by': null,
        'updated_at': now,
      },
      where: 'ticket_id = ?',
      whereArgs: [ticketId],
    );

    // Enqueue for sync
    await db.insert('sync_queue', {
      'ticket_id': ticketId,
      'event_id': entry.eventId,
      'action': 'undo_check_in',
      'usher_id': usherId,
      'timestamp': now,
      'synced': 0,
      'retry_count': 0,
    });

    AppLogger.debug('Undo check-in locally: $ticketId', tag: _tag);
  }

  /// Get all unsynced queue entries.
  Future<List<SyncQueueEntry>> getSyncQueue({int limit = 50}) async {
    final db = await _getDb();
    final rows = await db.query(
      'sync_queue',
      where: 'synced = 0 AND retry_count < 5',
      orderBy: 'id ASC',
      limit: limit,
    );
    return rows.map(SyncQueueEntry.fromMap).toList();
  }

  /// Mark sync queue entries as synced.
  Future<void> markSynced(List<int> queueIds) async {
    if (queueIds.isEmpty) return;
    final db = await _getDb();
    final placeholders = List.filled(queueIds.length, '?').join(',');
    await db.rawUpdate(
      'UPDATE sync_queue SET synced = 1 WHERE id IN ($placeholders)',
      queueIds,
    );
  }

  /// Increment retry count and set error message.
  Future<void> markRetry(int queueId, String? errorMessage) async {
    final db = await _getDb();
    await db.rawUpdate(
      'UPDATE sync_queue SET retry_count = retry_count + 1, error_message = ? WHERE id = ?',
      [errorMessage, queueId],
    );
  }

  /// Mark a sync entry as failed (exhausted retries).
  Future<void> markFailed(int queueId, String errorMessage) async {
    final db = await _getDb();
    await db.rawUpdate(
      'UPDATE sync_queue SET synced = 1, error_message = ? WHERE id = ?',
      [errorMessage, queueId],
    );
  }

  /// Get local stats from the HashMap (instant).
  ///
  /// Counts checked-in by `checkedInAt != null` (not by status == 'used')
  /// because entry tickets stay 'valid' after check-in.
  ({int totalTickets, int checkedIn, int pendingSync}) getLocalStats() {
    // Count unique tickets (entries are doubled: by id and by number)
    final seen = <String>{};
    int total = 0;
    int checkedIn = 0;

    for (final entry in _index.entries) {
      if (seen.add(entry.value.ticketId)) {
        total++;
        if (entry.value.checkedInAt != null) checkedIn++;
      }
    }

    return (totalTickets: total, checkedIn: checkedIn, pendingSync: 0);
  }

  /// Get stats broken down by category (entry vs redeemable).
  ///
  /// Entry tickets: counted as checked-in by `checkedInAt != null`.
  /// Redeemable tickets: counted as redeemed by `isUsed` (status == 'used').
  ({
    int totalEntry,
    int checkedInEntry,
    int totalRedeemable,
    int redeemedRedeemable,
  }) getStatsByCategory() {
    final seen = <String>{};
    int totalEntry = 0;
    int checkedInEntry = 0;
    int totalRedeemable = 0;
    int redeemedRedeemable = 0;

    for (final entry in _index.entries) {
      if (seen.add(entry.value.ticketId)) {
        if (entry.value.isRedeemable) {
          totalRedeemable++;
          if (entry.value.isUsed) redeemedRedeemable++;
        } else {
          totalEntry++;
          if (entry.value.checkedInAt != null) checkedInEntry++;
        }
      }
    }

    return (
      totalEntry: totalEntry,
      checkedInEntry: checkedInEntry,
      totalRedeemable: totalRedeemable,
      redeemedRedeemable: redeemedRedeemable,
    );
  }

  /// Get pending sync count from database.
  Future<int> getPendingSyncCount() async {
    final db = await _getDb();
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM sync_queue WHERE synced = 0 AND retry_count < 5',
    );
    return result.first['count'] as int? ?? 0;
  }

  /// Record a verification discrepancy for later sync and admin review.
  ///
  /// Called when a ticket passes offline check but fails blockchain or
  /// database verification. The flag is stored locally and synced to the
  /// server on the next sync cycle.
  Future<void> recordVerificationFlag({
    required String ticketId,
    required String eventId,
    required String flagType, // 'blockchain_failed', 'database_mismatch'
    required String tier, // 'blockchain', 'database'
    required String message,
    required String usherId,
  }) async {
    final db = await _getDb();
    await db.insert('verification_flags', {
      'ticket_id': ticketId,
      'event_id': eventId,
      'flag_type': flagType,
      'tier': tier,
      'message': message,
      'usher_id': usherId,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'synced': 0,
    });
  }

  /// Get unsynced verification flags for background sync.
  Future<List<Map<String, dynamic>>> getUnsyncedFlags() async {
    final db = await _getDb();
    return db.query(
      'verification_flags',
      where: 'synced = 0',
      orderBy: 'timestamp ASC',
    );
  }

  /// Mark a verification flag as synced.
  Future<void> markFlagSynced(int flagId) async {
    final db = await _getDb();
    await db.update(
      'verification_flags',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [flagId],
    );
  }

  /// Get count of unsynced flags (for UI badge).
  Future<int> getUnsyncedFlagCount() async {
    final db = await _getDb();
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM verification_flags WHERE synced = 0',
    );
    return result.first['count'] as int? ?? 0;
  }

  /// Update a local entry's status (e.g., when server reports cancelled).
  Future<void> updateLocalStatus(String ticketId, String newStatus) async {
    final entry = _index[ticketId];
    if (entry == null) return;

    entry.status = newStatus;

    final db = await _getDb();
    await db.update(
      'door_list',
      {
        'status': newStatus,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'ticket_id = ?',
      whereArgs: [ticketId],
    );
  }

  /// Add a single ticket to the local cache (e.g., found on server but not in cache).
  Future<void> addToCache(DoorListEntry entry) async {
    final db = await _getDb();
    await db.insert(
      'door_list',
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    _index[entry.ticketId] = entry;
    _index[entry.ticketNumber] = entry;
  }

  /// Clear all data for a specific event.
  Future<void> clearEvent(String eventId) async {
    final db = await _getDb();
    await db.delete('door_list', where: 'event_id = ?', whereArgs: [eventId]);
    await db.delete('sync_queue', where: 'event_id = ?', whereArgs: [eventId]);

    _index.clear();
    if (_currentEventId == eventId) {
      _currentEventId = null;
      _doorListDownloadedAt = null;
    }
  }

  /// Close the database.
  Future<void> close() async {
    await _db?.close();
    _db = null;
    _index.clear();
  }

  /// Get the HashMap index size (for testing).
  int get indexSize => _index.length;
}
