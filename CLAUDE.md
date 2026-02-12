# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Tickety is a Flutter-based event discovery application targeting Android, iOS, Web, Windows, Linux, and macOS. It uses Dart 3.10.7+ with Material Design 3.

## Development Principles

**UX and code quality/architecture are paramount.** The application will have several processes that need to be secure and scalable. When making changes:

- Prioritize user experience in all UI/interaction decisions
- Maintain clean architecture boundaries between layers
- Write secure code—validate inputs, handle sensitive data appropriately
- Design for scalability—avoid tight coupling, use proper state management patterns
- Keep performance in mind, especially for animations and graphics rendering

## Development Commands

All commands should be run from the `tickety_app/` directory.

```bash
# Install dependencies
flutter pub get

# Run the app
flutter run                    # Default connected device
flutter run -d chrome          # Web (Chrome)
flutter run -d windows         # Windows desktop

# Run tests
flutter test                   # All tests
flutter test test/widget_test.dart  # Single test file

# Static analysis
flutter analyze

# Build
flutter build apk              # Android APK
flutter build ios              # iOS
flutter build web              # Web
flutter build windows          # Windows
```

## Architecture

The app follows a clean architecture pattern with feature-based organization:

```
tickety_app/lib/
├── main.dart              # App entry point, theme config, root widget
├── core/                  # Core utilities shared across features
│   ├── graphics/          # Perlin noise generation & canvas painting
│   └── input/             # Input handling utilities
├── features/              # Feature modules (vertical slices)
│   └── events/            # Events feature
│       ├── models/        # Data models (EventModel)
│       ├── presentation/  # Screens (EventsHomeScreen)
│       └── widgets/       # Feature-specific widgets
└── shared/                # Reusable widgets across features
    └── widgets/           # NoiseBackground, etc.
```

### Key Components

- **NoiseGenerator** (`core/graphics/noise_generator.dart`): Perlin noise implementation with preset configurations (vibrantEvents, sunset, ocean, subtle, darkMood)
- **EventModel** (`features/events/models/event_model.dart`): Immutable event data class with placeholder data for development
- **EventBannerCarousel**: PageView-based carousel with spring physics and dot indicators
- **EventsHomeScreen**: Main screen with "Discover" header, featured carousel, and upcoming events list

### Theme Configuration

- Material 3 enabled
- Color seed: `#6366F1` (Indigo)
- Light theme: white background
- Dark theme: `#121212` background
- System-aware dark/light mode switching

### Library Exports

Each module uses a library file (e.g., `events.dart`, `widgets.dart`) for clean exports. Import the library file rather than individual files.

## TODO

### Pagination Implementation

All repository methods that fetch user-specific lists are now paginated for scalability.

**Completed (using `PaginatedResult<T>` with `.range()`):**
- `getEventPayments()` in `payment_repository.dart` - Returns `PaginatedResult<Payment>`
- `getUpcomingEvents()` in `supabase_event_repository.dart` - Returns `PaginatedResult<EventModel>`
- `getMyPayments()` in `payment_repository.dart` - Returns `PaginatedResult<Payment>` (25 per page)
- `getEventListings()` in `resale_repository.dart` - Returns `PaginatedResult<ResaleListing>` (20 per page)
- `getMyTickets()` in `ticket_repository.dart` - Returns `PaginatedResult<Ticket>` (20 per page)
- `getMyEvents()` in `supabase_event_repository.dart` - Returns `PaginatedResult<EventModel>` (20 per page)
- `getMyStaffEvents()` in `staff_repository.dart` - Returns `PaginatedResult<Map>` (20 per page)
- `getMyListings()` in `resale_repository.dart` - Returns `PaginatedResult<ResaleListing>` (20 per page)
- `EventsProvider` - Supports `loadMore()` with infinite scroll on home screen
- `PaymentHistoryProvider` - Supports `loadMore()` for user payment history
- `MyTicketsNotifier` - Supports `loadMore()` for user's purchased tickets
- `MyEventsNotifier` - Supports `loadMore()` for organizer's events

**Deleted (unused):**
- `getActiveListings()` - Removed, was never used in UI

**Optimized with SQL COUNT:**
- `getResaleListingCount(eventId)` in `resale_repository.dart` - Returns count without fetching records

**Already optimized (using SQL aggregation):**
- `getTicketStats()` - Uses `get_ticket_stats()` RPC function
- `getEventAnalytics()` - Uses `get_event_analytics()` RPC function

**Implementation approach used:**
- Supabase `.range(from, to)` for offset-based pagination
- `page` and `pageSize` parameters on repository methods
- Return `PaginatedResult<T>` from `core/models/paginated_result.dart`
- Fetch `pageSize + 1` items and check length to determine `hasMore`
- Provider state includes `isLoadingMore`, `hasMore`, `currentPage` fields
- `loadMore()` method on notifiers for infinite scroll UI pattern

### Seller Wallet System (Completed)

Sellers can now list tickets for resale without requiring full Stripe onboarding upfront. Funds are held in their Stripe Express account until they add bank details to withdraw.

**Architecture:**
- Stripe holds funds (not Tickety) - avoids Money Transmitter License requirements
- Minimal Stripe Express account created on first listing attempt
- Bank details only required when seller wants to withdraw

**Database:**
- `seller_balances` table caches Stripe balance info (available/pending cents, payouts_enabled)
- Migration: `20260131000002_create_seller_balances.sql`

**Edge Functions (all use `stripe@14.21.0`):**
- `create-seller-account` - Creates minimal Stripe Express account (email only)
- `get-seller-balance` - Fetches balance from Stripe API, caches in DB
- `initiate-withdrawal` - Returns onboarding URL if bank not set up, or creates payout
- `create-resale-intent` - Uses `on_behalf_of` pattern (funds stay in seller's Stripe balance)
- `create-payment-intent` - Primary ticket purchases
- `create-connect-account` - Full Stripe Connect Express setup (legacy)
- `verify-subscription` - Verifies subscription status with Stripe
- `create-subscription-checkout` - Creates subscription checkout sessions
- `stripe-webhook` - Handles payment and subscription events
- `connect-webhook` - Handles Connect account events
- `process-refund` - Processes refunds via Stripe

**RLS Policies:**
- `20260131000003_fix_resale_listing_rls.sql` - Fixes ticket ownership check for resale listings (uses `sold_by` instead of `owner_email`)

**Flutter:**
- `seller_balance_provider.dart` - Manages seller balance state
- `wallet_screen.dart` - Shows Stripe Balance + Crypto Balance (ADA placeholder), separate "Add Bank Details" and "Withdraw" buttons
- `resale_repository.dart` - Wallet methods (hasSellerAccount, createSellerAccount, getSellerBalance, initiateWithdrawal)

**Stripe Test Mode Values:**
- Verification codes: `000000`
- SSN: `000-00-0000`
- Bank routing: `110000000`
- Bank account: `000123456789`

**Important:** Uses `https://esm.sh/stripe@14.21.0` import (not `@13.10.0?target=deno`) for Supabase Edge Runtime compatibility.

### Favor Ticket System (Completed)

Organizers can send comp/gift tickets to anyone by email. Uses a two-phase lifecycle: offer is created (pending), then recipient accepts/pays to claim.

**Ticket Modes:**
- `private` - Off-chain, database only, cannot be resold. Best for personal comps.
- `public` - On-chain NFT (future), tradeable/resaleable on marketplace.
- `standard` - Existing tickets (unchanged, resale allowed).

**Pricing Rules:**
- Private free ($0): Recipient just accepts, no cost.
- Private paid ($X): Recipient must pay $X to claim.
- Public free ($0): Suggest ~$1 minting fee. Recipient can pay (stays public) or skip (downgraded to private).
- Public paid ($X): Recipient pays $X.

**Database:**
- `ticket_offers` table: offers with status lifecycle (pending → accepted/declined/cancelled/expired)
- `ticket_mode` column added to `tickets` table (standard/private/public)
- `offer_id` FK on `tickets` linking back to the offer
- Trigger `block_private_ticket_resale` prevents private tickets from being listed on `resale_listings`
- Trigger `notify_ticket_offer_created` creates notification for registered recipients on offer insert
- Trigger `check_pending_offers_on_signup` links pending offers and notifies when new users register
- Migrations: `20260213000001` through `20260213000006`

**RLS Notes:**
- Recipient policies use `auth.jwt() ->> 'email'` (not `SELECT FROM auth.users`) since the `authenticated` role cannot query `auth.users` directly.
- Trigger functions use `profiles` table for email lookups (same reason). `SECURITY DEFINER` alone is not enough for `auth.users` access in Supabase hosted.

**Edge Functions:**
- `claim-favor-offer` - Claims free offers, handles public→private downgrade when skipping minting fee
- `stripe-webhook` - Extended to handle `favor_ticket_purchase` payment type
- `create-payment-intent` - Extended to accept `favor_ticket_purchase` type

**Flutter:**
- `favor_tickets/models/ticket_offer.dart` - TicketOffer model, TicketOfferStatus enum, TicketMode enum
- `favor_tickets/data/favor_ticket_repository.dart` - CRUD for offers, claim/decline/cancel
- `favor_tickets/presentation/create_favor_ticket_screen.dart` - Organizer form (email, price, mode, message)
- `favor_tickets/presentation/favor_ticket_offer_screen.dart` - Recipient view with accept/pay/decline
- `core/providers/favor_ticket_provider.dart` - PendingOffersNotifier, repository provider
- `ticket.dart` - Added `ticketMode` field and `canBeResold` computed property
- `notification_model.dart` - Added `favorTicketOffer` type with `offerId` getter
- `payment.dart` - Added `favorTicketPurchase` payment type
- `admin_event_screen.dart` - Added "Favor Tickets" action card
- `resale_repository.dart` - Blocks private ticket resale listings
- `ticket_screen.dart` - Uses `canBeResold` for sell button visibility

### Stripe Webhooks Setup (Production)

Set up Stripe webhooks to handle subscription lifecycle events:

1. Go to **Stripe Dashboard → Developers → Webhooks**
2. Add endpoint: `https://hnouslchigcmbiovdbfz.supabase.co/functions/v1/stripe-webhook`
3. Select events:
   - `customer.subscription.created`
   - `customer.subscription.updated`
   - `customer.subscription.deleted`
4. Copy the webhook signing secret
5. Add to Supabase: **Project Settings → Edge Functions → Secrets** as `STRIPE_WEBHOOK_SECRET`

This enables:
- Subscription renewals
- Failed payment retries
- Cancellations from Stripe dashboard
- Plan changes from billing portal

## Future: Cardano (ADA) Integration

The wallet screen includes a placeholder for "Crypto Balance" showing ADA. This is reserved for future Cardano blockchain integration for:
- NFT-based ticket ownership
- Decentralized ticket resale
- Crypto payments
