import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/branding/data/branding_repository.dart';
import '../../features/branding/models/organizer_branding.dart';

final brandingRepositoryProvider = Provider((ref) => BrandingRepository());

/// Current organizer's own branding (for settings screen).
final myBrandingProvider =
    FutureProvider.autoDispose<OrganizerBranding?>((ref) async {
  return ref.read(brandingRepositoryProvider).getMyBranding();
});

/// Branding for a specific organizer (used on event detail + my tickets).
/// Cached per organizer ID so same organizer = one fetch.
final organizerBrandingProvider =
    FutureProvider.autoDispose.family<OrganizerBranding?, String?>((ref, organizerId) async {
  if (organizerId == null) return null;
  return ref.read(brandingRepositoryProvider).getBranding(organizerId);
});
