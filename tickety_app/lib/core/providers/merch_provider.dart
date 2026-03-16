import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/merch/data/merch_repository.dart';
import '../../features/merch/models/models.dart';

/// Repository provider.
final merchRepositoryProvider = Provider<MerchRepository>((ref) {
  return MerchRepository();
});

/// Products for a specific event (buyer-facing).
final eventMerchProvider = FutureProvider.autoDispose
    .family<List<MerchProduct>, String>((ref, eventId) async {
  final repo = ref.watch(merchRepositoryProvider);
  return repo.getEventProducts(eventId);
});

/// All products for an organizer (management).
final organizerProductsProvider = FutureProvider.autoDispose
    .family<List<MerchProduct>, String>((ref, organizerId) async {
  final repo = ref.watch(merchRepositoryProvider);
  return repo.getOrganizerProducts(organizerId);
});

/// Merch config for an organizer.
final merchConfigProvider = FutureProvider.autoDispose
    .family<OrganizerMerchConfig?, String>((ref, organizerId) async {
  final repo = ref.watch(merchRepositoryProvider);
  return repo.getMerchConfig(organizerId);
});

/// Buyer's merch orders.
final myMerchOrdersProvider =
    FutureProvider.autoDispose<List<MerchOrder>>((ref) async {
  final repo = ref.watch(merchRepositoryProvider);
  return repo.getMyOrders();
});

/// Organizer's merch orders.
final organizerOrdersProvider = FutureProvider.autoDispose
    .family<List<MerchOrder>, String>((ref, organizerId) async {
  final repo = ref.watch(merchRepositoryProvider);
  return repo.getOrganizerOrders(organizerId);
});
