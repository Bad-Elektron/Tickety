import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/events/data/supabase_event_repository.dart';
import '../../features/events/models/event_series.dart';
import 'events_provider.dart';

/// Provider for series occurrences (list of dates).
final seriesOccurrencesProvider =
    FutureProvider.autoDispose.family<List<SeriesOccurrence>, String>(
  (ref, seriesId) async {
    final repository = ref.watch(eventRepositoryProvider) as SupabaseEventRepository;
    return repository.getSeriesOccurrences(seriesId);
  },
);

/// Provider for series details.
final seriesDetailProvider =
    FutureProvider.autoDispose.family<EventSeries?, String>(
  (ref, seriesId) async {
    final repository = ref.watch(eventRepositoryProvider) as SupabaseEventRepository;
    return repository.getEventSeries(seriesId);
  },
);
