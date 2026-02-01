import '../../../core/models/models.dart';
import '../models/resale_listing.dart';
import '../models/seller_balance.dart';

/// Interface for resale listing data operations.
abstract class IResaleRepository {
  /// Get the count of active resale listings for an event.
  ///
  /// Use this for displaying availability counts without fetching all records.
  Future<int> getResaleListingCount(String eventId);

  /// Get active resale listings for a specific event (paginated).
  ///
  /// Returns listings sorted by price (lowest first).
  Future<PaginatedResult<ResaleListing>> getEventListings(
    String eventId, {
    int page = 0,
    int pageSize = 20,
  });

  /// Get a specific listing by ID.
  Future<ResaleListing?> getListing(String listingId);

  /// Get the current user's listings (paginated).
  ///
  /// [page] - Page number (0-indexed).
  /// [pageSize] - Number of items per page.
  Future<PaginatedResult<ResaleListing>> getMyListings({
    int page = 0,
    int pageSize = 20,
  });

  /// Create a new resale listing.
  ///
  /// Requires the user to have a Stripe seller account (not full onboarding).
  Future<ResaleListing> createListing({
    required String ticketId,
    required int priceCents,
    String currency = 'usd',
  });

  /// Update a listing's price.
  Future<ResaleListing> updateListingPrice(String listingId, int priceCents);

  /// Cancel a listing.
  Future<void> cancelListing(String listingId);

  // ============================================================
  // LEGACY METHODS (for backwards compatibility)
  // ============================================================

  /// Check if the current user has completed full Stripe Connect onboarding.
  ///
  /// NOTE: This is no longer required to create listings. Use [hasSellerAccount]
  /// to check if the user can list tickets.
  Future<bool> isSellerOnboarded();

  /// Create a Stripe Connect account for the current user (legacy flow).
  ///
  /// Returns the onboarding URL to redirect the user to.
  /// Prefer [createSellerAccount] for the new wallet flow.
  Future<String> createConnectAccount();

  /// Check the Stripe Connect onboarding status.
  Future<bool> checkOnboardingStatus();

  // ============================================================
  // NEW WALLET METHODS
  // ============================================================

  /// Check if the current user has a seller account (can list tickets).
  ///
  /// This does NOT require full onboarding - just a Stripe account creation.
  Future<bool> hasSellerAccount();

  /// Create a minimal Stripe seller account for the current user.
  ///
  /// This allows the user to list tickets immediately. Funds from sales
  /// will be held in their Stripe balance until they add bank details.
  ///
  /// Returns the Stripe account ID.
  Future<String> createSellerAccount();

  /// Get the seller's current balance from Stripe.
  ///
  /// Returns balance info including whether they can withdraw (have bank details).
  Future<SellerBalance> getSellerBalance();

  /// Initiate a withdrawal from the seller's Stripe balance.
  ///
  /// If the seller hasn't added bank details, returns a URL to complete setup.
  /// If withdrawal is successful, returns the payout details.
  Future<WithdrawalResult> initiateWithdrawal({int? amountCents});
}
