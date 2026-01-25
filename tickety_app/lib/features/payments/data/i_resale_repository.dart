import '../models/resale_listing.dart';

/// Interface for resale listing data operations.
abstract class IResaleRepository {
  /// Get all active resale listings.
  Future<List<ResaleListing>> getActiveListings();

  /// Get active resale listings for a specific event.
  Future<List<ResaleListing>> getEventListings(String eventId);

  /// Get a specific listing by ID.
  Future<ResaleListing?> getListing(String listingId);

  /// Get the current user's listings.
  Future<List<ResaleListing>> getMyListings();

  /// Create a new resale listing.
  ///
  /// Requires the user to have completed Stripe Connect onboarding.
  Future<ResaleListing> createListing({
    required String ticketId,
    required int priceCents,
    String currency = 'usd',
  });

  /// Update a listing's price.
  Future<ResaleListing> updateListingPrice(String listingId, int priceCents);

  /// Cancel a listing.
  Future<void> cancelListing(String listingId);

  /// Check if the current user has completed Stripe Connect onboarding.
  Future<bool> isSellerOnboarded();

  /// Create a Stripe Connect account for the current user.
  ///
  /// Returns the onboarding URL to redirect the user to.
  Future<String> createConnectAccount();

  /// Check the Stripe Connect onboarding status.
  Future<bool> checkOnboardingStatus();
}
