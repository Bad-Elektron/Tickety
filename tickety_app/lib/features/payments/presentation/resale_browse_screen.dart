import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/errors.dart';
import '../../../core/services/services.dart';
import '../../events/models/event_model.dart';
import '../data/resale_repository.dart';
import '../models/payment.dart';
import '../models/resale_listing.dart';
import 'checkout_screen.dart';
import 'seller_onboarding_screen.dart';

const _tag = 'ResaleBrowse';
const int _kPageSize = 20;

// ============================================================
// STATE
// ============================================================

class ResaleListingsState {
  final List<ResaleListing> listings;
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;
  final int currentPage;
  final bool hasMore;

  const ResaleListingsState({
    this.listings = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
    this.currentPage = 0,
    this.hasMore = true,
  });

  bool get canLoadMore => hasMore && !isLoading && !isLoadingMore;

  ResaleListingsState copyWith({
    List<ResaleListing>? listings,
    bool? isLoading,
    bool? isLoadingMore,
    String? error,
    int? currentPage,
    bool? hasMore,
    bool clearError = false,
  }) {
    return ResaleListingsState(
      listings: listings ?? this.listings,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: clearError ? null : (error ?? this.error),
      currentPage: currentPage ?? this.currentPage,
      hasMore: hasMore ?? this.hasMore,
    );
  }
}

// ============================================================
// NOTIFIER
// ============================================================

class ResaleListingsNotifier extends StateNotifier<ResaleListingsState> {
  final ResaleRepository _repository;
  final String _eventId;

  ResaleListingsNotifier(this._repository, this._eventId)
      : super(const ResaleListingsState());

  Future<void> load() async {
    if (state.isLoading) return;

    AppLogger.debug('Loading resale listings for event: $_eventId', tag: _tag);

    state = state.copyWith(
      isLoading: true,
      clearError: true,
      currentPage: 0,
      hasMore: true,
    );

    try {
      final result = await _repository.getEventListings(
        _eventId,
        page: 0,
        pageSize: _kPageSize,
      );
      AppLogger.info(
        'Loaded ${result.items.length} resale listings (hasMore: ${result.hasMore})',
        tag: _tag,
      );
      state = state.copyWith(
        listings: result.items,
        isLoading: false,
        currentPage: 0,
        hasMore: result.hasMore,
      );
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Failed to load resale listings',
        error: appError.technicalDetails ?? e,
        stackTrace: s,
        tag: _tag,
      );
      state = state.copyWith(
        isLoading: false,
        error: appError.userMessage,
        hasMore: false,
      );
    }
  }

  Future<void> loadMore() async {
    if (!state.canLoadMore) return;

    final nextPage = state.currentPage + 1;
    AppLogger.debug('Loading more resale listings (page: $nextPage)', tag: _tag);
    state = state.copyWith(isLoadingMore: true);

    try {
      final result = await _repository.getEventListings(
        _eventId,
        page: nextPage,
        pageSize: _kPageSize,
      );

      AppLogger.info(
        'Loaded ${result.items.length} more resale listings (hasMore: ${result.hasMore})',
        tag: _tag,
      );

      state = state.copyWith(
        listings: [...state.listings, ...result.items],
        isLoadingMore: false,
        currentPage: nextPage,
        hasMore: result.hasMore,
      );
    } catch (e, s) {
      final appError = ErrorHandler.normalize(e, s);
      AppLogger.error(
        'Failed to load more resale listings',
        error: appError.technicalDetails ?? e,
        stackTrace: s,
        tag: _tag,
      );
      state = state.copyWith(
        isLoadingMore: false,
        error: appError.userMessage,
      );
    }
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: false);
    await load();
  }
}

// ============================================================
// PROVIDERS
// ============================================================

final resaleListingsProvider = StateNotifierProvider.autoDispose
    .family<ResaleListingsNotifier, ResaleListingsState, String>(
  (ref, eventId) {
    final repository = ref.watch(resaleRepositoryProvider);
    final notifier = ResaleListingsNotifier(repository, eventId);
    notifier.load();
    return notifier;
  },
);

// ============================================================
// SCREEN
// ============================================================

/// Screen for browsing and purchasing resale tickets.
class ResaleBrowseScreen extends ConsumerWidget {
  const ResaleBrowseScreen({
    super.key,
    required this.event,
  });

  final EventModel event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(resaleListingsProvider(event.id));
    final notifier = ref.read(resaleListingsProvider(event.id).notifier);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Resale Tickets'),
      ),
      body: _buildBody(context, ref, state, notifier, theme, colorScheme),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    ResaleListingsState state,
    ResaleListingsNotifier notifier,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    if (state.isLoading && state.listings.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null && state.listings.isEmpty) {
      return _ErrorView(
        error: state.error!,
        onRetry: () => notifier.refresh(),
      );
    }

    if (state.listings.isEmpty) {
      return _EmptyView(event: event);
    }

    final listings = state.listings;
    final currentUserId = SupabaseService.instance.currentUser?.id;

    return Column(
      children: [
        // Event header
        Container(
          padding: const EdgeInsets.all(16),
          color: colorScheme.surfaceContainerLow,
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [colorScheme.primary, colorScheme.secondary],
                  ),
                ),
                child: const Icon(
                  Icons.event,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${listings.length}${state.hasMore ? "+" : ""} ${listings.length == 1 ? "ticket" : "tickets"} available',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Listings with infinite scroll
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => notifier.refresh(),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: listings.length + (state.hasMore ? 1 : 0),
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                // Load more trigger
                if (index == listings.length) {
                  if (state.canLoadMore) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      notifier.loadMore();
                    });
                  }
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }

                final listing = listings[index];
                final isOwnListing =
                    currentUserId != null && listing.sellerId == currentUserId;
                return _ResaleListingCard(
                  listing: listing,
                  event: event,
                  isOwnListing: isOwnListing,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _ResaleListingCard extends StatelessWidget {
  const _ResaleListingCard({
    required this.listing,
    required this.event,
    this.isOwnListing = false,
  });

  final ResaleListing listing;
  final EventModel event;
  final bool isOwnListing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Calculate original price from ticket if available
    final originalPrice = listing.ticket?.pricePaidCents;
    final hasDiscount =
        originalPrice != null && listing.priceCents < originalPrice;
    final hasPremium =
        originalPrice != null && listing.priceCents > originalPrice;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isOwnListing
              ? colorScheme.primary.withValues(alpha: 0.5)
              : colorScheme.outline.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Own listing badge
          if (isOwnListing) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Your Listing',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],

          // Top row: Ticket info and price
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.confirmation_number_outlined,
                          size: 16,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'General Admission',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (listing.ticket?.ticketNumber != null)
                      Text(
                        'Ticket #${listing.ticket!.ticketNumber}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              // Price column
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    listing.formattedPrice,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                  if (originalPrice != null) ...[
                    const SizedBox(height: 2),
                    if (hasDiscount)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '\$${(originalPrice / 100).toStringAsFixed(2)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${((1 - listing.priceCents / originalPrice) * 100).round()}% off',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.green,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    if (hasPremium)
                      Text(
                        'Face value: \$${(originalPrice / 100).toStringAsFixed(2)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Platform fee notice
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  'Service fee: ${listing.formattedPlatformFee}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Buy button or own listing indicator
          if (isOwnListing)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _handleOwnListing(context),
                icon: const Icon(Icons.sell_outlined, size: 18),
                label: const Text('Your Listing'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => _handleBuy(context),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                    'Buy for ${listing.formattedTotalBuyerPrice}'),
              ),
            ),
        ],
      ),
    );
  }

  void _handleBuy(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CheckoutScreen(
          event: event,
          amountCents: listing.priceCents,
          paymentType: PaymentType.resalePurchase,
          resaleListingId: listing.id,
          sellerId: listing.sellerId,
        ),
      ),
    );
  }

  void _handleOwnListing(BuildContext context) {
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.white, size: 20),
            SizedBox(width: 12),
            Expanded(
              child: Text('You can\'t buy your own listing'),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.event});

  final EventModel event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.confirmation_number_outlined,
                size: 40,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No Resale Tickets',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'There are no tickets available for resale for this event right now.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.error,
    required this.onRetry,
  });

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}
