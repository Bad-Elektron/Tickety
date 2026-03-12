import 'package:flutter/foundation.dart';

import '../../../core/errors/errors.dart';
import '../../../core/models/models.dart';
import '../../../core/services/services.dart';
import '../models/event_model.dart';
import '../models/event_series.dart';
import '../models/ticket_availability.dart';
import '../models/ticket_type.dart';
import 'event_mapper.dart';
import 'event_repository.dart';

/// Data class for creating ticket types (used in event creation).
class TicketTypeInput {
  final String name;
  final String? description;
  final int priceCents;
  final int? maxQuantity;
  final String? venueSectionId;

  const TicketTypeInput({
    required this.name,
    required this.priceCents,
    this.description,
    this.maxQuantity,
    this.venueSectionId,
  });
}

const _tag = 'EventRepository';

/// Supabase implementation of [EventRepository].
///
/// Fetches and manages events from the Supabase PostgreSQL database.
class SupabaseEventRepository implements EventRepository {
  static const _tableName = 'events';

  final _client = SupabaseService.instance.client;

  @override
  Future<PaginatedResult<EventModel>> getUpcomingEvents({
    String? category,
    String? city,
    int page = 0,
    int pageSize = 20,
  }) async {
    AppLogger.debug(
      'Fetching upcoming events (category: $category, city: $city, page: $page, pageSize: $pageSize)',
      tag: _tag,
    );

    // Calculate range for pagination (fetch one extra to detect hasMore)
    final from = page * pageSize;
    final to = from + pageSize;

    List<dynamic> response;
    try {
      // Build query with privacy and status filters
      var query = _client
          .from(_tableName)
          .select()
          .isFilter('deleted_at', null)
          .eq('is_private', false)
          .eq('status', 'active')
          .gte('date', DateTime.now().toUtc().toIso8601String());

      if (category != null) {
        query = query.eq('category', category);
      }
      if (city != null) {
        query = query.eq('city', city);
      }

      response = await query.order('date', ascending: true).range(from, to);
    } catch (_) {
      // Fallback: is_private column may not exist yet
      var query = _client
          .from(_tableName)
          .select()
          .isFilter('deleted_at', null)
          .gte('date', DateTime.now().toUtc().toIso8601String());

      if (category != null) {
        query = query.eq('category', category);
      }
      if (city != null) {
        query = query.eq('city', city);
      }

      response = await query.order('date', ascending: true).range(from, to);
    }

    final allItems = (response as List<dynamic>)
        .map((json) => EventMapper.fromJson(json as Map<String, dynamic>))
        .toList();

    // Check if we got more than pageSize (meaning there are more pages)
    final hasMore = allItems.length > pageSize;
    final events = hasMore ? allItems.take(pageSize).toList() : allItems;

    AppLogger.debug(
      'Fetched ${events.length} upcoming events (hasMore: $hasMore)',
      tag: _tag,
    );

    return PaginatedResult(
      items: events,
      page: page,
      pageSize: pageSize,
      hasMore: hasMore,
    );
  }

  /// Fetches upcoming events filtered by a specific tag ID.
  Future<PaginatedResult<EventModel>> getUpcomingEventsByTag(
    String tagId, {
    int page = 0,
    int pageSize = 20,
  }) async {
    AppLogger.debug(
      'Fetching upcoming events by tag: $tagId (page: $page)',
      tag: _tag,
    );

    final from = page * pageSize;
    final to = from + pageSize;

    List<dynamic> response;
    try {
      response = await _client
          .from(_tableName)
          .select()
          .isFilter('deleted_at', null)
          .eq('is_private', false)
          .eq('status', 'active')
          .gte('date', DateTime.now().toUtc().toIso8601String())
          .contains('tags', [tagId])
          .order('date', ascending: true)
          .range(from, to);
    } catch (_) {
      response = await _client
          .from(_tableName)
          .select()
          .isFilter('deleted_at', null)
          .gte('date', DateTime.now().toUtc().toIso8601String())
          .contains('tags', [tagId])
          .order('date', ascending: true)
          .range(from, to);
    }

    final allItems = response
        .map((json) => EventMapper.fromJson(json as Map<String, dynamic>))
        .toList();

    final hasMore = allItems.length > pageSize;
    final events = hasMore ? allItems.take(pageSize).toList() : allItems;

    return PaginatedResult(
      items: events,
      page: page,
      pageSize: pageSize,
      hasMore: hasMore,
    );
  }

  @override
  Future<EventModel?> getEventById(String id) async {
    AppLogger.debug('Fetching event by ID: $id', tag: _tag);

    final response = await _client
        .from(_tableName)
        .select()
        .eq('id', id)
        .isFilter('deleted_at', null)
        .maybeSingle();

    if (response == null) {
      AppLogger.debug('Event not found: $id', tag: _tag);
      return null;
    }
    return EventMapper.fromJson(response);
  }

  @override
  Future<List<EventModel>> getFeaturedEvents({int limit = 5}) async {
    AppLogger.debug('Fetching featured events (limit: $limit)', tag: _tag);

    // For now, just get the nearest upcoming events as featured
    // In production, you might have a "featured" flag or algorithm
    List<dynamic> response;
    try {
      response = await _client
          .from(_tableName)
          .select()
          .isFilter('deleted_at', null)
          .eq('is_private', false)
          .eq('status', 'active')
          .gte('date', DateTime.now().toUtc().toIso8601String())
          .order('date', ascending: true)
          .limit(limit);
    } catch (_) {
      // Fallback: is_private column may not exist yet
      response = await _client
          .from(_tableName)
          .select()
          .isFilter('deleted_at', null)
          .gte('date', DateTime.now().toUtc().toIso8601String())
          .order('date', ascending: true)
          .limit(limit);
    }

    final events = (response as List<dynamic>)
        .map((json) => EventMapper.fromJson(json as Map<String, dynamic>))
        .toList();

    AppLogger.debug('Fetched ${events.length} featured events', tag: _tag);
    return events;
  }

  @override
  Future<EventModel> createEvent(EventModel event) async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) {
      AppLogger.warning('Attempted to create event without authentication', tag: _tag);
      throw StateError('Must be authenticated to create events');
    }

    AppLogger.debug('Creating event: ${event.title}', tag: _tag);

    final data = EventMapper.toJson(event);
    data['organizer_id'] = userId;

    final response =
        await _client.from(_tableName).insert(data).select().single();

    final created = EventMapper.fromJson(response);
    AppLogger.info('Event created: ${created.id} - ${created.title}', tag: _tag);
    return created;
  }

  /// Convenience method to create an event from individual parameters.
  Future<EventModel> createEventFromParams({
    required String title,
    required String subtitle,
    required DateTime date,
    String? description,
    String? venue,
    String? city,
    String? country,
    String? imageUrl,
    int? priceInCents,
    String? currency,
    String? category,
    List<String>? tags,
    int? noiseSeed,
    bool hideLocation = false,
    bool isPrivate = false,
    bool nftEnabled = false,
    double? latitude,
    double? longitude,
    String? formattedAddress,
    String? venueId,
    String? eventFormat,
    String? virtualEventUrl,
    String? virtualEventPassword,
  }) async {
    final event = EventModel(
      id: '', // Will be generated by database
      title: title,
      subtitle: subtitle,
      description: description,
      date: date,
      venue: venue,
      city: city,
      country: country,
      imageUrl: imageUrl,
      priceInCents: priceInCents,
      currency: currency ?? 'USD',
      category: category,
      tags: tags ?? const [],
      noiseSeed: noiseSeed ?? DateTime.now().millisecondsSinceEpoch % 10000,
      hideLocation: hideLocation,
      isPrivate: isPrivate,
      nftEnabled: nftEnabled,
      latitude: latitude,
      longitude: longitude,
      formattedAddress: formattedAddress,
      venueId: venueId,
      eventFormat: eventFormat ?? 'in_person',
      virtualEventUrl: virtualEventUrl,
      virtualEventPassword: virtualEventPassword,
    );
    return createEvent(event);
  }

  @override
  Future<EventModel> updateEvent(EventModel event) async {
    AppLogger.debug('Updating event: ${event.id}', tag: _tag);

    final data = EventMapper.toJson(event);
    data['updated_at'] = DateTime.now().toUtc().toIso8601String();

    final response = await _client
        .from(_tableName)
        .update(data)
        .eq('id', event.id)
        .select()
        .single();

    final updated = EventMapper.fromJson(response);
    AppLogger.info('Event updated: ${updated.id} - ${updated.title}', tag: _tag);
    return updated;
  }

  @override
  Future<void> deleteEvent(String id) async {
    AppLogger.debug('Soft-deleting event: $id', tag: _tag);

    await _client.from(_tableName).update({
      'deleted_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);

    AppLogger.info('Event deleted: $id', tag: _tag);
  }

  /// Link or unlink a venue to an event.
  Future<void> linkVenue(String eventId, String? venueId) async {
    await _client.from(_tableName).update({
      'venue_id': venueId,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', eventId);
  }

  @override
  Future<PaginatedResult<EventModel>> getMyEvents({
    MyEventsDateFilter dateFilter = MyEventsDateFilter.recent,
    String? searchQuery,
    int page = 0,
    int pageSize = 20,
  }) async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) {
      AppLogger.warning('Attempted to get my events without authentication', tag: _tag);
      throw StateError('Must be authenticated to view your events');
    }

    // Convert enum to string for RPC
    final dateFilterStr = switch (dateFilter) {
      MyEventsDateFilter.recent => 'recent',
      MyEventsDateFilter.upcoming => 'upcoming',
      MyEventsDateFilter.all => 'all',
      MyEventsDateFilter.past => 'past',
    };

    // Trim and normalize search query
    final normalizedSearch = searchQuery?.trim().isNotEmpty == true
        ? searchQuery!.trim()
        : null;

    AppLogger.debug(
      'Fetching events for user: $userId (filter: $dateFilterStr, search: $normalizedSearch, page: $page, pageSize: $pageSize)',
      tag: _tag,
    );

    final offset = page * pageSize;

    // Use RPC function for server-side filtering and sorting
    final response = await _client.rpc(
      'get_my_events',
      params: {
        'p_user_id': userId,
        'p_date_filter': dateFilterStr,
        'p_search_query': normalizedSearch,
        'p_limit': pageSize + 1, // Fetch one extra to check hasMore
        'p_offset': offset,
      },
    );

    final allItems = (response as List<dynamic>)
        .map((json) => EventMapper.fromJson(json as Map<String, dynamic>))
        .toList()
      // Sort by creation date descending (newest first)
      ..sort((a, b) {
        final aDate = a.createdAt ?? DateTime(2000);
        final bDate = b.createdAt ?? DateTime(2000);
        return bDate.compareTo(aDate);
      });

    final hasMore = allItems.length > pageSize;
    final events = hasMore ? allItems.take(pageSize).toList() : allItems;

    AppLogger.debug(
      'Fetched ${events.length} user events (hasMore: $hasMore)',
      tag: _tag,
    );

    return PaginatedResult(
      items: events,
      page: page,
      pageSize: pageSize,
      hasMore: hasMore,
    );
  }

  @override
  Future<TicketAvailability> getTicketAvailability(String eventId) async {
    AppLogger.debug('Fetching ticket availability for event: $eventId', tag: _tag);

    // Call the RPC function for SQL aggregation
    final response = await _client.rpc(
      'get_ticket_availability',
      params: {'p_event_id': eventId},
    );

    if (response == null) {
      AppLogger.debug('No availability data for event: $eventId', tag: _tag);
      return const TicketAvailability(soldCount: 0);
    }

    final data = response as Map<String, dynamic>;
    AppLogger.debug(
      'Ticket availability: max=${data['max_tickets']}, sold=${data['sold_count']}, available=${data['available']}',
      tag: _tag,
    );

    return TicketAvailability.fromJson(data);
  }

  /// Get all ticket types for an event.
  Future<List<TicketType>> getEventTicketTypes(String eventId) async {
    AppLogger.debug('Fetching ticket types for event: $eventId', tag: _tag);

    // Use direct query instead of RPC for debugging
    final response = await _client
        .from('event_ticket_types')
        .select()
        .eq('event_id', eventId)
        .eq('is_active', true)
        .order('sort_order')
        .order('price_cents');

    AppLogger.debug('Raw response: $response', tag: _tag);

    final ticketTypes = (response as List<dynamic>)
        .map((json) => TicketType.fromJson(json as Map<String, dynamic>))
        .toList();

    AppLogger.debug('Fetched ${ticketTypes.length} ticket types', tag: _tag);
    return ticketTypes;
  }

  /// Create ticket types for an event.
  Future<List<TicketType>> createTicketTypes(
    String eventId,
    List<TicketTypeInput> ticketTypes,
  ) async {
    if (ticketTypes.isEmpty) {
      debugPrint('No ticket types to create for event: $eventId');
      return [];
    }

    debugPrint('Creating ${ticketTypes.length} ticket types for event: $eventId');

    final data = ticketTypes.asMap().entries.map((entry) {
      final index = entry.key;
      final tt = entry.value;
      final item = {
        'event_id': eventId,
        'name': tt.name,
        'description': tt.description,
        'price_cents': tt.priceCents,
        'max_quantity': tt.maxQuantity,
        'sort_order': index,
        'is_active': true,
        if (tt.venueSectionId != null) 'venue_section_id': tt.venueSectionId,
      };
      debugPrint('Ticket type data: $item');
      return item;
    }).toList();

    try {
      debugPrint('Inserting ticket types into database...');
      final response = await _client
          .from('event_ticket_types')
          .insert(data)
          .select();

      debugPrint('Insert response: $response');

      final created = (response as List<dynamic>)
          .map((json) => TicketType.fromJson(json as Map<String, dynamic>))
          .toList();

      debugPrint('Successfully created ${created.length} ticket types');
      return created;
    } catch (e, stack) {
      debugPrint('ERROR creating ticket types: $e');
      debugPrint('Stack: $stack');
      rethrow;
    }
  }

  /// Delete existing ticket types for an event and re-insert new ones.
  Future<List<TicketType>> updateEventTicketTypes(
    String eventId,
    List<TicketTypeInput> ticketTypes,
  ) async {
    AppLogger.debug('Updating ticket types for event: $eventId', tag: _tag);

    // Delete existing active ticket types
    await _client
        .from('event_ticket_types')
        .delete()
        .eq('event_id', eventId);

    // Re-insert with the new list
    return createTicketTypes(eventId, ticketTypes);
  }

  /// Find events with similar titles (for duplicate/impersonation detection).
  @override
  Future<List<Map<String, dynamic>>> findSimilarEvents({
    required String title,
    String? venue,
    DateTime? date,
  }) async {
    AppLogger.debug('Searching for similar events: "$title"', tag: _tag);

    final response = await _client.rpc(
      'find_similar_events',
      params: {
        'p_title': title,
        'p_venue': venue,
        'p_date': date?.toIso8601String().split('T').first,
      },
    );

    final results = (response as List<dynamic>)
        .map((json) => json as Map<String, dynamic>)
        .toList();

    AppLogger.debug('Found ${results.length} similar events', tag: _tag);
    return results;
  }

  /// Report an event for review.
  @override
  Future<void> reportEvent({
    required String eventId,
    required String reason,
    String? description,
  }) async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) {
      throw StateError('Must be authenticated to report events');
    }

    AppLogger.debug('Reporting event: $eventId (reason: $reason)', tag: _tag);

    await _client.from('event_reports').insert({
      'event_id': eventId,
      'reporter_id': userId,
      'reason': reason,
      'description': description,
    });

    AppLogger.info('Event reported: $eventId', tag: _tag);
  }

  /// Create an event with ticket types in a single operation.
  Future<EventModel> createEventWithTicketTypes({
    required String title,
    required String subtitle,
    required DateTime date,
    required List<TicketTypeInput> ticketTypes,
    String? description,
    String? venue,
    String? city,
    String? country,
    String? imageUrl,
    String? currency,
    String? category,
    List<String>? tags,
    int? noiseSeed,
    bool hideLocation = false,
    bool isPrivate = false,
    bool nftEnabled = false,
    double? latitude,
    double? longitude,
    String? formattedAddress,
    String? venueId,
    String? eventFormat,
    String? virtualEventUrl,
    String? virtualEventPassword,
  }) async {
    debugPrint('createEventWithTicketTypes called with ${ticketTypes.length} ticket types');

    // Use the lowest NON-ZERO ticket price as the event's display price
    // If all tickets are free, use 0
    final nonZeroPrices = ticketTypes.where((t) => t.priceCents > 0).map((t) => t.priceCents);
    final lowestPrice = ticketTypes.isEmpty
        ? null
        : nonZeroPrices.isEmpty
            ? 0
            : nonZeroPrices.reduce((a, b) => a < b ? a : b);

    debugPrint('Lowest non-zero price: $lowestPrice cents');

    // Create the event first
    final event = await createEventFromParams(
      title: title,
      subtitle: subtitle,
      date: date,
      description: description,
      venue: venue,
      city: city,
      country: country,
      imageUrl: imageUrl,
      priceInCents: lowestPrice,
      currency: currency,
      category: category,
      tags: tags,
      noiseSeed: noiseSeed,
      hideLocation: hideLocation,
      isPrivate: isPrivate,
      nftEnabled: nftEnabled,
      latitude: latitude,
      longitude: longitude,
      formattedAddress: formattedAddress,
      venueId: venueId,
      eventFormat: eventFormat,
      virtualEventUrl: virtualEventUrl,
      virtualEventPassword: virtualEventPassword,
    );

    debugPrint('Event created with id: ${event.id}');

    // Then create the ticket types
    if (ticketTypes.isNotEmpty) {
      debugPrint('About to create ticket types...');
      final createdTypes = await createTicketTypes(event.id, ticketTypes);
      debugPrint('Finished creating ticket types: ${createdTypes.length} created');
    } else {
      debugPrint('No ticket types to create');
    }

    return event;
  }

  @override
  Future<void> logEventView(String eventId, {String source = 'direct'}) async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) return;

    try {
      await _client.from('event_views').insert({
        'event_id': eventId,
        'viewer_id': userId,
        'source': source,
      });
    } catch (_) {
      // Silently ignore dedup violations / missing table
    }
  }

  @override
  Future<EventModel?> getEventByInviteCode(String code) async {
    AppLogger.debug('Looking up event by invite code: $code', tag: _tag);

    final response = await _client
        .from(_tableName)
        .select()
        .eq('invite_code', code.toUpperCase())
        .isFilter('deleted_at', null)
        .maybeSingle();

    if (response == null) {
      AppLogger.debug('No event found for invite code: $code', tag: _tag);
      return null;
    }
    return EventMapper.fromJson(response);
  }

  // ============================================================
  // RECURRING EVENT SERIES
  // ============================================================

  /// Creates a recurring event series with the first batch of occurrences.
  /// The first occurrence is created as a normal event, then the series
  /// generates future occurrences via the SQL function.
  Future<EventSeries> createEventSeries({
    required RecurrenceType recurrenceType,
    required int recurrenceDay,
    required String recurrenceTime,
    required DateTime startsAt,
    DateTime? endsAt,
    required Map<String, dynamic> templateSnapshot,
    List<Map<String, dynamic>>? ticketTypesSnapshot,
  }) async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) throw AuthException.notAuthenticated();

    AppLogger.info('Creating event series: $recurrenceType', tag: _tag);

    // Insert the series record
    final response = await _client
        .from('event_series')
        .insert({
          'organizer_id': userId,
          'recurrence_type': recurrenceType.value,
          'recurrence_day': recurrenceDay,
          'recurrence_time': recurrenceTime,
          'starts_at': startsAt.toUtc().toIso8601String(),
          if (endsAt != null) 'ends_at': endsAt.toUtc().toIso8601String(),
          'template_snapshot': templateSnapshot,
          'ticket_types_snapshot': ticketTypesSnapshot,
        })
        .select()
        .single();

    final series = EventSeries.fromJson(response);
    AppLogger.info('Series created: ${series.id}', tag: _tag);

    // Generate the first batch of occurrences (8 future events)
    await _client.rpc('generate_series_occurrences', params: {
      'p_series_id': series.id,
      'p_min_future': 8,
    });

    AppLogger.info('Initial occurrences generated for series ${series.id}', tag: _tag);
    return series;
  }

  /// Gets a series by ID.
  Future<EventSeries?> getEventSeries(String seriesId) async {
    final response = await _client
        .from('event_series')
        .select()
        .eq('id', seriesId)
        .maybeSingle();

    if (response == null) return null;
    return EventSeries.fromJson(response);
  }

  /// Gets all occurrences for a series.
  Future<List<SeriesOccurrence>> getSeriesOccurrences(String seriesId) async {
    final response = await _client.rpc(
      'get_series_occurrences',
      params: {'p_series_id': seriesId},
    );

    return (response as List<dynamic>)
        .map((json) => SeriesOccurrence.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Updates the template for a series and optionally propagates to future events.
  Future<void> updateSeriesTemplate({
    required String seriesId,
    required Map<String, dynamic> templateSnapshot,
    List<Map<String, dynamic>>? ticketTypesSnapshot,
    required String scope, // 'this_only', 'this_and_future', 'all'
    String? currentEventId,
  }) async {
    if (scope == 'this_only' && currentEventId != null) {
      // Just mark this event as individually edited
      await _client
          .from('events')
          .update({'series_edited': true})
          .eq('id', currentEventId);
      return;
    }

    // Update the series template
    final updates = <String, dynamic>{
      'template_snapshot': templateSnapshot,
    };
    if (ticketTypesSnapshot != null) {
      updates['ticket_types_snapshot'] = ticketTypesSnapshot;
    }
    await _client.from('event_series').update(updates).eq('id', seriesId);

    // Propagate to occurrence rows
    final eventUpdates = <String, dynamic>{
      'title': templateSnapshot['title'],
      'subtitle': templateSnapshot['subtitle'],
      'description': templateSnapshot['description'],
      'venue': templateSnapshot['venue'],
      'city': templateSnapshot['city'],
      'country': templateSnapshot['country'],
      'price_in_cents': templateSnapshot['price_in_cents'],
      'hide_location': templateSnapshot['hide_location'],
      'tags': templateSnapshot['tags'],
      'category': templateSnapshot['category'],
    };

    var query = _client
        .from('events')
        .update(eventUpdates)
        .eq('series_id', seriesId)
        .eq('series_edited', false)
        .isFilter('deleted_at', null);

    if (scope == 'this_and_future') {
      query = query.gte('date', DateTime.now().toUtc().toIso8601String());
    }

    await query;
  }

  /// Cancels a series: deactivates and soft-deletes all future occurrences.
  Future<void> cancelSeries(String seriesId) async {
    // Deactivate the series
    await _client
        .from('event_series')
        .update({'is_active': false})
        .eq('id', seriesId);

    // Soft-delete all future occurrences
    await _client
        .from('events')
        .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
        .eq('series_id', seriesId)
        .gte('date', DateTime.now().toUtc().toIso8601String())
        .isFilter('deleted_at', null);

    AppLogger.info('Series cancelled: $seriesId', tag: _tag);
  }
}
