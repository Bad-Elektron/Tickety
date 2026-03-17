import '../../../core/models/models.dart';
import '../../../core/services/services.dart';
import '../models/external_event.dart';

class ExternalEventRepository {
  final _client = SupabaseService.instance.client;

  Future<PaginatedResult<ExternalEvent>> getUpcomingExternalEvents({
    String? category,
    String? searchQuery,
    int page = 0,
    int pageSize = 20,
  }) async {
    var query = _client
        .from('external_events')
        .select()
        .eq('is_active', true)
        .gte('start_date', DateTime.now().toUtc().toIso8601String());

    if (category != null) {
      query = query.eq('category', category);
    }

    if (searchQuery != null && searchQuery.isNotEmpty) {
      query = query.or('title.ilike.%$searchQuery%,venue_name.ilike.%$searchQuery%');
    }

    final from = page * pageSize;
    final to = from + pageSize;

    final response = await query
        .order('start_date', ascending: true)
        .range(from, to);

    final allItems = (response as List)
        .map((json) => ExternalEvent.fromJson(json as Map<String, dynamic>))
        .toList();

    final hasMore = allItems.length > pageSize;
    final items = hasMore ? allItems.take(pageSize).toList() : allItems;

    return PaginatedResult(
      items: items,
      page: page,
      pageSize: pageSize,
      hasMore: hasMore,
    );
  }

  Future<ExternalEvent?> getById(String id) async {
    final response = await _client
        .from('external_events')
        .select()
        .eq('id', id)
        .maybeSingle();

    if (response == null) return null;
    return ExternalEvent.fromJson(response);
  }
}
