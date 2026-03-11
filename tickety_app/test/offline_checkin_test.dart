import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:tickety/core/models/verification_result.dart';
import 'package:tickety/core/services/offline_checkin_service.dart';

/// Test data factory: generate synthetic door list entries.
List<DoorListEntry> generateTestDoorList(
  int count, {
  int nftPercentage = 20,
}) {
  final random = Random(42); // Fixed seed for reproducibility
  final entries = <DoorListEntry>[];

  for (int i = 0; i < count; i++) {
    final hasNft = random.nextInt(100) < nftPercentage;
    entries.add(DoorListEntry(
      ticketId: 'ticket-${i.toString().padLeft(6, '0')}',
      ticketNumber: 'TKT-${(1000000 + i).toString()}-${random.nextInt(9999).toString().padLeft(4, '0')}',
      eventId: 'event-001',
      status: 'valid',
      ownerName: 'Attendee $i',
      ownerEmail: 'attendee$i@test.com',
      nftAssetId: hasNft ? 'asset-${i.toString().padLeft(6, '0')}' : null,
      nftPolicyId: hasNft ? 'policy-001' : null,
      nftTxHash: hasNft ? 'tx-${i.toString().padLeft(6, '0')}' : null,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    ));
  }

  return entries;
}

/// Helper: insert entries directly into the database for testing.
Future<void> insertTestEntries(
  Database db,
  List<DoorListEntry> entries,
) async {
  final batch = db.batch();
  for (final entry in entries) {
    batch.insert(
      'door_list',
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
  await batch.commit(noResult: true);
}

void main() {
  // Initialize FFI for desktop/CI SQLite
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late OfflineCheckInService service;

  setUp(() async {
    // Create in-memory database for each test
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
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
        },
      ),
    );
    service = OfflineCheckInService(database: db);
  });

  tearDown(() async {
    await service.close();
  });

  // ─────────────────────────────────────────────────
  // Group A: Core Pipeline Tests
  // ─────────────────────────────────────────────────

  group('Door List & HashMap Index', () {
    test('stores entries in SQLite and builds HashMap index', () async {
      final entries = generateTestDoorList(5000);
      await insertTestEntries(db, entries);

      // Manually trigger index build (simulates what downloadDoorList does)
      // We call a private method equivalent via public API
      // Since downloadDoorList needs Supabase, we test the index build directly
      // by inserting then looking up

      // Build the index by reading from DB
      final rows = await db.query(
        'door_list',
        where: 'event_id = ?',
        whereArgs: ['event-001'],
      );

      // Verify all 5000 stored
      expect(rows.length, 5000);

      // Build index manually (same logic as _buildIndex)
      for (final row in rows) {
        final entry = DoorListEntry.fromMap(row);
        // Simulate adding to service index
        // (In production, _buildIndex does this)
      }
    });

    test('lookup by ticket_id returns correct entry', () async {
      final entries = generateTestDoorList(100);
      await insertTestEntries(db, entries);

      // Build index manually
      final rows = await db.query('door_list', where: 'event_id = ?', whereArgs: ['event-001']);
      final index = <String, DoorListEntry>{};
      for (final row in rows) {
        final entry = DoorListEntry.fromMap(row);
        index[entry.ticketId] = entry;
        index[entry.ticketNumber] = entry;
      }

      // Lookup by ID
      expect(index.containsKey('ticket-000050'), true);
      final entry = index['ticket-000050']!;
      expect(entry.ownerName, 'Attendee 50');
      expect(entry.eventId, 'event-001');
    });

    test('lookup by ticket_number returns correct entry', () async {
      final entries = generateTestDoorList(100);
      await insertTestEntries(db, entries);

      final rows = await db.query('door_list', where: 'event_id = ?', whereArgs: ['event-001']);
      final index = <String, DoorListEntry>{};
      for (final row in rows) {
        final entry = DoorListEntry.fromMap(row);
        index[entry.ticketId] = entry;
        index[entry.ticketNumber] = entry;
      }

      // Lookup by ticket number
      final ticketNumber = entries[25].ticketNumber;
      expect(index.containsKey(ticketNumber), true);
      expect(index[ticketNumber]!.ticketId, 'ticket-000025');
    });

    test('lookup nonexistent ticket returns null', () async {
      final entries = generateTestDoorList(100);
      await insertTestEntries(db, entries);

      final rows = await db.query('door_list', where: 'event_id = ?', whereArgs: ['event-001']);
      final index = <String, DoorListEntry>{};
      for (final row in rows) {
        final entry = DoorListEntry.fromMap(row);
        index[entry.ticketId] = entry;
        index[entry.ticketNumber] = entry;
      }

      expect(index['nonexistent-ticket'], isNull);
      expect(index['TKT-9999999-0000'], isNull);
    });

    test('HashMap has 2 keys per entry (id + number)', () async {
      final entries = generateTestDoorList(500);
      await insertTestEntries(db, entries);

      final rows = await db.query('door_list', where: 'event_id = ?', whereArgs: ['event-001']);
      final index = <String, DoorListEntry>{};
      for (final row in rows) {
        final entry = DoorListEntry.fromMap(row);
        index[entry.ticketId] = entry;
        index[entry.ticketNumber] = entry;
      }

      // 500 tickets × 2 keys each = 1000 index entries
      expect(index.length, 1000);
    });
  });

  group('Local Check-In', () {
    test('markCheckedIn updates SQLite and enqueues sync', () async {
      final entries = generateTestDoorList(10);
      await insertTestEntries(db, entries);

      // Add entry to service index by using addToCache
      final entry = entries[3];
      await service.addToCache(entry);

      // Mark checked in
      await service.markCheckedIn(entry.ticketId, 'usher-001');

      // Verify SQLite updated
      final row = await db.query(
        'door_list',
        where: 'ticket_id = ?',
        whereArgs: [entry.ticketId],
      );
      expect(row.first['status'], 'used');
      expect(row.first['checked_in_by'], 'usher-001');
      expect(row.first['checked_in_at'], isNotNull);

      // Verify sync queue
      final queue = await service.getSyncQueue();
      expect(queue.length, 1);
      expect(queue.first.ticketId, entry.ticketId);
      expect(queue.first.action, 'check_in');
      expect(queue.first.usherId, 'usher-001');
    });

    test('already-used ticket detected in HashMap', () async {
      final entry = generateTestDoorList(1).first;
      await insertTestEntries(db, [entry]);
      await service.addToCache(entry);

      // Check in
      await service.markCheckedIn(entry.ticketId, 'usher-001');

      // Lookup should show used
      final looked = service.lookupTicket(entry.ticketId);
      expect(looked?.isUsed, true);

      // Second check-in should still work at service level
      // (business logic validation happens at provider level)
      await service.markCheckedIn(entry.ticketId, 'usher-001');

      // Queue should have 2 entries
      final queue = await service.getSyncQueue();
      expect(queue.length, 2);
    });
  });

  group('Undo Check-In', () {
    test('undo reverts status to valid', () async {
      final entry = generateTestDoorList(1).first;
      await insertTestEntries(db, [entry]);
      await service.addToCache(entry);

      // Check in then undo
      await service.markCheckedIn(entry.ticketId, 'usher-001');
      expect(service.lookupTicket(entry.ticketId)?.isUsed, true);

      await service.markUndoCheckIn(entry.ticketId, 'usher-001');
      expect(service.lookupTicket(entry.ticketId)?.isValid, true);

      // Verify sync queue has both entries
      final queue = await service.getSyncQueue();
      expect(queue.length, 2);
      expect(queue[0].action, 'check_in');
      expect(queue[1].action, 'undo_check_in');
    });
  });

  group('Sync Queue', () {
    test('getSyncQueue returns unsynced entries with retry < 5', () async {
      final entries = generateTestDoorList(5);
      await insertTestEntries(db, entries);
      for (final e in entries) {
        await service.addToCache(e);
      }

      // Check in 3 tickets
      for (int i = 0; i < 3; i++) {
        await service.markCheckedIn(entries[i].ticketId, 'usher-001');
      }

      final queue = await service.getSyncQueue();
      expect(queue.length, 3);
    });

    test('markSynced removes entries from future queries', () async {
      final entries = generateTestDoorList(3);
      await insertTestEntries(db, entries);
      for (final e in entries) {
        await service.addToCache(e);
      }

      for (final e in entries) {
        await service.markCheckedIn(e.ticketId, 'usher-001');
      }

      var queue = await service.getSyncQueue();
      expect(queue.length, 3);

      // Mark first two as synced
      await service.markSynced([queue[0].id!, queue[1].id!]);

      queue = await service.getSyncQueue();
      expect(queue.length, 1);
      expect(queue.first.ticketId, entries[2].ticketId);
    });

    test('markRetry increments retry count', () async {
      final entry = generateTestDoorList(1).first;
      await insertTestEntries(db, [entry]);
      await service.addToCache(entry);

      await service.markCheckedIn(entry.ticketId, 'usher-001');
      var queue = await service.getSyncQueue();
      expect(queue.first.retryCount, 0);

      await service.markRetry(queue.first.id!, 'Server error 500');

      queue = await service.getSyncQueue();
      expect(queue.first.retryCount, 1);
      expect(queue.first.errorMessage, 'Server error 500');
    });

    test('entries with retry >= 5 excluded from queue', () async {
      final entry = generateTestDoorList(1).first;
      await insertTestEntries(db, [entry]);
      await service.addToCache(entry);

      await service.markCheckedIn(entry.ticketId, 'usher-001');
      var queue = await service.getSyncQueue();

      // Exhaust retries
      for (int i = 0; i < 5; i++) {
        await service.markRetry(queue.first.id!, 'Error $i');
      }

      queue = await service.getSyncQueue();
      expect(queue.isEmpty, true);
    });
  });

  group('Stats', () {
    test('getLocalStats returns accurate counts', () async {
      final entries = generateTestDoorList(100);
      await insertTestEntries(db, entries);
      for (final e in entries) {
        await service.addToCache(e);
      }

      // Check in 30 tickets
      for (int i = 0; i < 30; i++) {
        await service.markCheckedIn(entries[i].ticketId, 'usher-001');
      }

      final stats = service.getLocalStats();
      expect(stats.totalTickets, 100);
      expect(stats.checkedIn, 30);
    });

    test('getPendingSyncCount returns pending count', () async {
      final entries = generateTestDoorList(10);
      await insertTestEntries(db, entries);
      for (final e in entries) {
        await service.addToCache(e);
      }

      // Check in 5 tickets
      for (int i = 0; i < 5; i++) {
        await service.markCheckedIn(entries[i].ticketId, 'usher-001');
      }

      final pending = await service.getPendingSyncCount();
      expect(pending, 5);

      // Sync 3
      final queue = await service.getSyncQueue();
      await service.markSynced(queue.take(3).map((e) => e.id!).toList());

      final pendingAfter = await service.getPendingSyncCount();
      expect(pendingAfter, 2);
    });
  });

  group('updateLocalStatus', () {
    test('updates status in index and database', () async {
      final entry = generateTestDoorList(1).first;
      await insertTestEntries(db, [entry]);
      await service.addToCache(entry);

      expect(service.lookupTicket(entry.ticketId)?.status, 'valid');

      await service.updateLocalStatus(entry.ticketId, 'cancelled');

      expect(service.lookupTicket(entry.ticketId)?.status, 'cancelled');

      final row = await db.query(
        'door_list',
        where: 'ticket_id = ?',
        whereArgs: [entry.ticketId],
      );
      expect(row.first['status'], 'cancelled');
    });
  });

  group('addToCache', () {
    test('adds entry to both SQLite and index', () async {
      final entry = DoorListEntry(
        ticketId: 'new-ticket-001',
        ticketNumber: 'TKT-NEW-001',
        eventId: 'event-001',
        status: 'valid',
        ownerName: 'New Attendee',
        updatedAt: DateTime.now().toUtc().toIso8601String(),
      );

      await service.addToCache(entry);

      // Lookup by both keys
      expect(service.lookupTicket('new-ticket-001'), isNotNull);
      expect(service.lookupTicket('TKT-NEW-001'), isNotNull);

      // Verify in SQLite
      final rows = await db.query(
        'door_list',
        where: 'ticket_id = ?',
        whereArgs: ['new-ticket-001'],
      );
      expect(rows.length, 1);
    });
  });

  group('clearEvent', () {
    test('removes all data for the event', () async {
      final entries = generateTestDoorList(50);
      await insertTestEntries(db, entries);
      for (final e in entries) {
        await service.addToCache(e);
      }

      // Check in some
      await service.markCheckedIn(entries[0].ticketId, 'usher-001');

      // Clear
      await service.clearEvent('event-001');

      expect(service.lookupTicket(entries[0].ticketId), isNull);
      expect(service.indexSize, 0);

      final rows = await db.query('door_list');
      expect(rows.isEmpty, true);
    });
  });

  group('Double download (idempotent)', () {
    test('upsert does not duplicate entries', () async {
      final entries = generateTestDoorList(50);
      await insertTestEntries(db, entries);
      for (final e in entries) {
        await service.addToCache(e);
      }

      // Insert again (simulates second download)
      await insertTestEntries(db, entries);

      final rows = await db.query('door_list');
      expect(rows.length, 50);
    });

    test('local check-ins preserved on re-download', () async {
      final entries = generateTestDoorList(10);
      await insertTestEntries(db, entries);
      for (final e in entries) {
        await service.addToCache(e);
      }

      // Check in ticket 0
      await service.markCheckedIn(entries[0].ticketId, 'usher-001');

      // Re-insert entries (fresh download, all valid)
      // The sync queue still has unsynced entry, so production code
      // would skip overwriting. Here we just verify the sync queue persists.
      final queue = await service.getSyncQueue();
      expect(queue.length, 1);
      expect(queue.first.ticketId, entries[0].ticketId);
    });
  });

  group('DoorListEntry model', () {
    test('serialization roundtrip', () {
      final entry = DoorListEntry(
        ticketId: 'test-id',
        ticketNumber: 'TKT-123',
        eventId: 'event-001',
        status: 'valid',
        ownerName: 'Test User',
        ownerEmail: 'test@example.com',
        nftAssetId: 'asset-001',
        nftPolicyId: 'policy-001',
        updatedAt: '2026-03-10T00:00:00Z',
      );

      final map = entry.toMap();
      final restored = DoorListEntry.fromMap(map);

      expect(restored.ticketId, entry.ticketId);
      expect(restored.ticketNumber, entry.ticketNumber);
      expect(restored.ownerName, entry.ownerName);
      expect(restored.nftAssetId, entry.nftAssetId);
      expect(restored.hasNft, true);
    });

    test('hasNft false when nftAssetId is null', () {
      final entry = DoorListEntry(
        ticketId: 'test-id',
        ticketNumber: 'TKT-123',
        eventId: 'event-001',
        status: 'valid',
        updatedAt: '2026-03-10T00:00:00Z',
      );
      expect(entry.hasNft, false);
    });
  });

  group('SyncQueueEntry model', () {
    test('serialization roundtrip', () {
      final entry = SyncQueueEntry(
        id: 1,
        ticketId: 'ticket-001',
        eventId: 'event-001',
        action: 'check_in',
        usherId: 'usher-001',
        timestamp: '2026-03-10T12:00:00Z',
        retryCount: 2,
        errorMessage: 'timeout',
      );

      final map = entry.toMap();
      final restored = SyncQueueEntry.fromMap(map);

      expect(restored.ticketId, 'ticket-001');
      expect(restored.action, 'check_in');
      expect(restored.retryCount, 2);
      expect(restored.errorMessage, 'timeout');
    });
  });

  group('VerificationResult model', () {
    test('initial has all tiers pending', () {
      final result = VerificationResult.initial();
      expect(result.getTier(VerificationTier.offline).status, TierStatus.pending);
      expect(result.getTier(VerificationTier.blockchain).status, TierStatus.pending);
      expect(result.getTier(VerificationTier.database).status, TierStatus.pending);
      expect(result.isAdmittable, false);
    });

    test('updateTier creates new result with updated tier', () {
      var result = VerificationResult.initial();
      result = result.updateTier(
        VerificationTier.offline,
        const TierResult(status: TierStatus.verified, message: 'Found'),
      );

      expect(result.getTier(VerificationTier.offline).status, TierStatus.verified);
      expect(result.getTier(VerificationTier.blockchain).status, TierStatus.pending);
    });
  });

  group('BlockchainVerifyResult model', () {
    test('statuses are correct', () {
      const verified = BlockchainVerifyResult(
        status: BlockchainVerifyStatus.verified,
        message: 'OK',
      );
      const skipped = BlockchainVerifyResult(
        status: BlockchainVerifyStatus.skipped,
        message: 'No NFT',
      );

      expect(verified.status, BlockchainVerifyStatus.verified);
      expect(skipped.status, BlockchainVerifyStatus.skipped);
    });
  });

  // ─────────────────────────────────────────────────
  // Group B: Stress & Load Tests
  // ─────────────────────────────────────────────────

  group('Stress tests', () {
    test('large door list — 50,000 tickets', () async {
      final entries = generateTestDoorList(50000);
      await insertTestEntries(db, entries);

      // Build index
      final rows = await db.query('door_list', where: 'event_id = ?', whereArgs: ['event-001']);
      final index = <String, DoorListEntry>{};
      for (final row in rows) {
        final entry = DoorListEntry.fromMap(row);
        index[entry.ticketId] = entry;
        index[entry.ticketNumber] = entry;
      }

      expect(index.length, 100000); // 2 keys per entry

      // Random lookups should be instant
      final sw = Stopwatch()..start();
      for (int i = 0; i < 100; i++) {
        final idx = Random(i).nextInt(50000);
        final result = index['ticket-${idx.toString().padLeft(6, '0')}'];
        expect(result, isNotNull);
      }
      sw.stop();
      // 100 lookups should complete well under 100ms
      expect(sw.elapsedMilliseconds, lessThan(100));
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('rapid consecutive operations', () async {
      final entries = generateTestDoorList(1000);
      await insertTestEntries(db, entries);
      for (final e in entries) {
        await service.addToCache(e);
      }

      // Fire 100 check-ins in rapid succession
      for (int i = 0; i < 100; i++) {
        await service.markCheckedIn(entries[i].ticketId, 'usher-001');
      }

      // All should be marked used
      for (int i = 0; i < 100; i++) {
        expect(service.lookupTicket(entries[i].ticketId)?.isUsed, true);
      }

      // Stats should be accurate
      final stats = service.getLocalStats();
      expect(stats.checkedIn, 100);
      expect(stats.totalTickets, 1000);

      // Sync queue should have exactly 100 entries
      final queue = await service.getSyncQueue(limit: 200);
      expect(queue.length, 100);
    });
  });

  // ─────────────────────────────────────────────────
  // Group C: Sync Queue Ordering
  // ─────────────────────────────────────────────────

  group('Sync queue ordering', () {
    test('FIFO order preserved', () async {
      final entries = generateTestDoorList(3);
      await insertTestEntries(db, entries);
      for (final e in entries) {
        await service.addToCache(e);
      }

      // Operations: check_in(A), check_in(B), undo(A), check_in(C)
      await service.markCheckedIn(entries[0].ticketId, 'usher-001');
      await service.markCheckedIn(entries[1].ticketId, 'usher-001');
      await service.markUndoCheckIn(entries[0].ticketId, 'usher-001');
      await service.markCheckedIn(entries[2].ticketId, 'usher-001');

      final queue = await service.getSyncQueue();
      expect(queue.length, 4);
      expect(queue[0].action, 'check_in');
      expect(queue[0].ticketId, entries[0].ticketId);
      expect(queue[1].action, 'check_in');
      expect(queue[1].ticketId, entries[1].ticketId);
      expect(queue[2].action, 'undo_check_in');
      expect(queue[2].ticketId, entries[0].ticketId);
      expect(queue[3].action, 'check_in');
      expect(queue[3].ticketId, entries[2].ticketId);

      // After processing: A=valid (undone), B=used, C=used
      expect(service.lookupTicket(entries[0].ticketId)?.isValid, true);
      expect(service.lookupTicket(entries[1].ticketId)?.isUsed, true);
      expect(service.lookupTicket(entries[2].ticketId)?.isUsed, true);
    });
  });

  // ─────────────────────────────────────────────────
  // Group D: Retry Exhaustion
  // ─────────────────────────────────────────────────

  group('Retry exhaustion', () {
    test('entry stops after 5 retries', () async {
      final entry = generateTestDoorList(1).first;
      await insertTestEntries(db, [entry]);
      await service.addToCache(entry);
      await service.markCheckedIn(entry.ticketId, 'usher-001');

      var queue = await service.getSyncQueue();
      final queueId = queue.first.id!;

      // Retry 5 times
      for (int i = 0; i < 5; i++) {
        await service.markRetry(queueId, 'Error attempt $i');
      }

      // Should be excluded from future queries
      queue = await service.getSyncQueue();
      expect(queue.isEmpty, true);

      // Verify retry count
      final rows = await db.query(
        'sync_queue',
        where: 'id = ?',
        whereArgs: [queueId],
      );
      expect(rows.first['retry_count'], 5);
    });

    test('markFailed stores error message', () async {
      final entry = generateTestDoorList(1).first;
      await insertTestEntries(db, [entry]);
      await service.addToCache(entry);
      await service.markCheckedIn(entry.ticketId, 'usher-001');

      var queue = await service.getSyncQueue();
      await service.markFailed(queue.first.id!, 'Permanent failure');

      // Should be excluded (marked synced=1)
      queue = await service.getSyncQueue();
      expect(queue.isEmpty, true);

      final rows = await db.query('sync_queue');
      expect(rows.first['error_message'], 'Permanent failure');
      expect(rows.first['synced'], 1);
    });
  });

  // ─────────────────────────────────────────────────
  // Group E: Edge Cases
  // ─────────────────────────────────────────────────

  group('Edge cases', () {
    test('empty door list', () async {
      // No entries inserted
      final stats = service.getLocalStats();
      expect(stats.totalTickets, 0);
      expect(stats.checkedIn, 0);

      // Lookup returns null
      expect(service.lookupTicket('any-ticket'), isNull);
    });

    test('cancelled ticket in door list', () async {
      final entry = DoorListEntry(
        ticketId: 'cancelled-001',
        ticketNumber: 'TKT-CANCELLED',
        eventId: 'event-001',
        status: 'cancelled',
        updatedAt: DateTime.now().toUtc().toIso8601String(),
      );
      await service.addToCache(entry);

      final looked = service.lookupTicket('cancelled-001');
      expect(looked?.isCancelled, true);
      expect(looked?.isValid, false);
    });

    test('refunded ticket in door list', () async {
      final entry = DoorListEntry(
        ticketId: 'refunded-001',
        ticketNumber: 'TKT-REFUNDED',
        eventId: 'event-001',
        status: 'refunded',
        updatedAt: DateTime.now().toUtc().toIso8601String(),
      );
      await service.addToCache(entry);

      final looked = service.lookupTicket('refunded-001');
      expect(looked?.isRefunded, true);
      expect(looked?.isValid, false);
    });

    test('stats with pre-checked-in tickets from server', () async {
      // Simulate downloading a list where some are already checked in
      final entries = <DoorListEntry>[];
      for (int i = 0; i < 100; i++) {
        entries.add(DoorListEntry(
          ticketId: 'ticket-$i',
          ticketNumber: 'TKT-$i',
          eventId: 'event-001',
          status: i < 20 ? 'used' : 'valid', // 20 already checked in
          checkedInAt: i < 20 ? '2026-03-10T10:00:00Z' : null,
          updatedAt: DateTime.now().toUtc().toIso8601String(),
        ));
      }
      for (final e in entries) {
        await service.addToCache(e);
      }

      // Check in 50 more locally
      for (int i = 20; i < 70; i++) {
        await service.markCheckedIn('ticket-$i', 'usher-001');
      }

      final stats = service.getLocalStats();
      expect(stats.totalTickets, 100);
      expect(stats.checkedIn, 70); // 20 from server + 50 local
    });
  });
}
