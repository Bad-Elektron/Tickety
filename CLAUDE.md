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

## Common Gotchas

- **Bottom sheet context after pop:** When a method in a bottom sheet's State calls `Navigator.pop()`, the sheet's `context` and `ref` become invalid. Capture `Navigator.of(context)`, `ScaffoldMessenger.of(context)`, and any `ref.read()` values *before* popping.
- **Immutable widget state after DB writes:** `widget.event` doesn't update after `linkVenue()` or similar writes. Use local state (e.g., `_linkedVenueId`) and a getter like `_effectiveVenueId` to reflect changes immediately.
- **Canvas coordinate spaces:** In `InteractiveViewer`/`Transform`-wrapped canvases, hit-test coordinates must be inverse-transformed (`_screenToCanvas()`) — raw `details.localPosition` is screen space, not canvas space.
- **Edge function variable scoping:** `let` declarations inside `if/else` blocks are block-scoped in TypeScript. Variables referenced later (e.g., `validatedPromoId`) must be hoisted to the outer scope.
- **Android emulator storage:** If the emulator data partition is >85% full, `flutter run` may force-uninstall → reinstall, wiping auth sessions. Increase AVD internal storage in Device Manager and wipe data to apply.
- **Edge function deployment:** After modifying edge functions, they must be deployed with `npx supabase functions deploy <name> --no-verify-jwt`. Code changes are not live until deployed.
- **Supabase Storage Content-Type:** Storage serves all files as `text/plain` regardless of upload headers. For HTML that must render in browsers, serve via an edge function with explicit `Content-Type: text/html` header, or use `iframe.srcdoc` injection.
- **Edge function template literals:** When embedding HTML/JS in a TypeScript template literal (`const html = \`...\``), `$` followed by `{` triggers interpolation. Use string concatenation for inner JS instead of template literals.

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
│   ├── config/            # Environment config (EnvConfig)
│   ├── errors/            # App exceptions (CardanoException, etc.)
│   ├── graphics/          # Perlin noise generation & canvas painting
│   ├── models/            # Shared models (PaginatedResult, VerificationResult)
│   ├── providers/         # Shared providers (cardano, favor ticket, waitlist, wallet pass, etc.)
│   ├── services/          # Core services (Blockfrost, CardanoWallet, GooglePlaces, OfflineCheckIn, CheckInSync)
│   └── input/             # Input handling utilities
├── features/              # Feature modules (vertical slices)
│   ├── events/            # Events (models, data, presentation, widgets)
│   ├── tickets/           # Ticket viewing & management
│   ├── payments/          # Payments, resale, promo codes
│   ├── favor_tickets/     # Comp/gift ticket system
│   ├── venues/            # Venue builder, seat picker
│   ├── wallet/            # Crypto wallet, bank accounts, wallet passes
│   ├── waitlist/          # Waitlist system
│   ├── notifications/     # Notification models & screens
│   └── profile/           # User profile & verification
└── shared/                # Reusable widgets (NoiseBackground, PlacesAutocompleteField, VerifiedBadge)
```

### Theme Configuration

- Material 3 with color seed `#6366F1` (Indigo)
- Light: white background / Dark: `#121212` background
- System-aware dark/light mode switching

### Library Exports

Each module uses a library file (e.g., `events.dart`, `widgets.dart`) for clean exports. Import the library file rather than individual files.

## Key Technical Notes

### Pagination

All list-fetching repository methods use `PaginatedResult<T>` with Supabase `.range()`. Fetch `pageSize + 1` to determine `hasMore`. Providers have `loadMore()` + `isLoadingMore` + `hasMore` + `currentPage` for infinite scroll.

### Stripe Integration

- **Edge functions** use `https://esm.sh/stripe@14.21.0` (not `@13.10.0?target=deno`) for Supabase Edge Runtime compatibility
- **Webhook endpoint:** `https://hnouslchigcmbiovdbfz.supabase.co/functions/v1/stripe-webhook`
- **Webhook events:** `customer.subscription.*`, `identity.verification_session.*`, `payment_intent.*`
- **Fee structure:** 5% platform + 2.9%+$0.30 Stripe (card) or 5% + 0.8% capped $5 (ACH)
- **Test values:** Verification `000000`, SSN `000-00-0000`, Bank routing `110000000`, Account `000123456789` (success) / `000222222227` (fail)

### Cardano Integration

- **Preview testnet** — all addresses `addr_test1...`. Mainnet = change Blockfrost URL + project ID
- **Platform minting wallet** — mnemonic as `PLATFORM_CARDANO_MNEMONIC` Supabase secret
- **CIP-68 NFT** — dual-token pattern: Reference NFT (`000643b0`) + User Token (`000de140`)
- **Key derivation** — BIP32-Ed25519 via CIP-1852 path `m/1852'/1815'/0'/0/0`
- **Auto-burn** — 60-day grace period after event ends, pg_cron daily at 1am UTC
- **Blockfrost test:** Get tADA from Cardano Preview Faucet

### Google Places

- HTTP API directly (no native SDK) — works on all platforms
- `GOOGLE_PLACES_API_KEY` in `tickety_app/.env`
- `displayLocation` fallback chain: venue+city → venue → city → formattedAddress → location

### RLS Notes

- Recipient policies use `auth.jwt() ->> 'email'` (not `SELECT FROM auth.users`) — `authenticated` role cannot query `auth.users`
- Trigger functions use `profiles` table for email lookups. `SECURITY DEFINER` alone is not enough for `auth.users` in Supabase hosted.

## Completed Features

### Seller Wallet System
Stripe Express accounts for resale sellers. Funds held in seller's Stripe account (avoids Money Transmitter License). Minimal account on first listing, bank details only for withdrawal. Tables: `seller_balances`. Edge functions: `create-seller-account`, `get-seller-balance`, `initiate-withdrawal`, `create-resale-intent`.

### Favor Ticket System
Organizers send comp/gift tickets by email. Ticket modes: `private` (off-chain, no resale), `public` (on-chain NFT), `standard`. Two-phase lifecycle: offer → accept/pay. Tables: `ticket_offers`, `ticket_mode` on tickets. Triggers for notification on offer creation and new user signup matching.

### Organizer Verification & Event Security
Stripe Identity verification for 250+ capacity events. Auto-hold unverified large events. Event reporting system. Tables: `identity_verification_status` on profiles, `status` on events, `event_reports`. `find_similar_events()` pg_trgm function. Feature flags in DB.

### Google Places Location
Events use Google Places Autocomplete with lat/lng/formatted_address. Location card opens Google Maps. Legacy `location` column auto-populated for backward compat.

### Analytics Consolidation
Unified `get_event_dashboard(event_id)` RPC. Single `refresh-analytics` edge function chains all cache refreshes. Admin dashboard with Overview + Engagement tabs.

### ACH Direct Bank Payment
Bank transfer at checkout via Stripe Financial Connections. Tickets issued immediately, ACH settles 4-5 days. Failure = tickets revoked. Replaced old wallet top-up system. Tables: `linked_bank_accounts`.

### Cardano Wallet (Phase 1)
Auto-created HD wallet on Preview testnet. Mnemonic synced to `user_wallets` table, cached in `flutter_secure_storage`. Send/receive ADA, transaction history via Blockfrost.

### CIP-68 NFT Tickets (Phase 2A-2D)
- **2A Minting:** Purchase → stripe-webhook enqueues → `mint-ticket-nft` builds/signs/submits CIP-68 tx. All events NFT-enabled by default.
- **2B Transfer:** Resale triggers NFT transfer to new buyer via `transfer-ticket-nft`.
- **2C Admin:** NFT Wallet dashboard, per-event mint stats, retry controls.
- **2D Burn:** Auto-burn 60 days after event. Reclaims ~1.5 ADA per NFT to platform. Dual-witness (platform + buyer keys). `burn-expired-nfts` edge function.

### Offline Check-in (Priority 1)
SQLite door list with O(1) HashMap index. **4-layer verification:** NFC Signature → Offline Cache → Blockchain → Database. Background sync every 7s. Conflict resolution. 34-test suite. `OfflineCheckInService`, `CheckInSyncService`, `BlockchainVerifyService`.

**Layer 0 — NFC Payload Verification (instant, zero dependencies):** The NFC payload carries an HMAC-SHA256 signature (`nfc_signature` column on tickets) generated at ticket creation in the stripe-webhook. The usher app verifies the signature against `TICKET_SIGNING_SECRET` (in `.env` + Supabase secrets). Works with zero network, zero SQLite cache, zero blockchain. If signature valid + event matches → admit. Layer 1 cache-hit upgrades confidence; cache showing "used" overrides Layer 0. QR scans skip Layer 0 (no signature in QR payload). Payload format: `{t, n, e, c, s, sig}` where `sig = HMAC-SHA256(ticketId + eventId + category, secret)`.

### Promo Codes (Priority 2)
Percentage or fixed discount codes per event. Server-side re-validation. One use per user per code. `validate_promo_code()` / `redeem_promo_code()` SQL functions. Works with both card and ACH checkout.

### Waitlists (Priority 3)
"Notify Me" or "Auto-Buy" modes. FIFO queue processed on resale listings. Off-session Stripe payment for auto-buy. pg_cron expires past-event waitlists. `process-waitlist` edge function.

### Apple/Google Wallet Passes (Priority 4)
PKPass generation + Google Wallet JWT. QR code for check-in. Pass updates on event changes. **Secrets not configured** — code ready, needs Apple/Google signing credentials.

### Seating Charts (Priority 5)
Phase 1: Drag-and-drop venue builder (sections, elements, seat generation). Phase 2: Seat selection at checkout with normalized grid, replace-selection UX, 10-min seat holds, seat labels on tickets.

### Recurring Events (Priority 6)
Daily/weekly/biweekly/monthly. Materialized occurrences (real `events` rows). Template snapshot JSONB. Rolling window via pg_cron. `event_series` table. Dart weekday → PG DOW: `date.weekday % 7`.

### Virtual Events (Priority 7)
In-Person/Virtual/Hybrid format. Meeting URL + password hidden until 1h before event. pg_cron lockdown every 5min: locks event, cancels resale listings, reveals link, notifies holders. `_VirtualEventCard` with "Join Event" button and countdown.

### Merch & Products (Priority 9)
Two systems: **Part A — Redeemable Tickets** (add-ons using existing ticket infrastructure) and **Part B — Physical Merch Store** (Enterprise-gated Shopify/Stripe integration).

**Part A:** `category` field on ticket types (`'entry'` or `'redeemable'`). Redeemable items (drink tokens, merch pickups, glow sticks) use same QR/check-in/resale/NFT infrastructure. Add-ons section in buy sheet below entry tickets. Webhook copies category from `ticket_items` metadata. SQLite offline schema v4 with category + item_icon.

**Part B:** Tables: `organizer_merch_config`, `merch_products`, `merch_variants`, `merch_orders` with full RLS. Edge functions: `sync-shopify-products`, `create-merch-payment`, `shopify-webhook`. Stripe webhook extended for `merch_purchase`. Flutter: `features/merch/` with models, repository, providers, 4 screens (ProductDetailScreen, OrganizerProductsScreen, OrganizerOrdersScreen, MyMerchOrdersScreen). Profile "My Orders" menu. EventDetailsScreen "Shop" section. AdminEventScreen "Merch Store" card. `MerchFeeCalculator` (5% platform + Stripe). Enterprise-only via `canUseMerchStore(tier)`.

### Embeddable Checkout Widget (Priority 8)
JavaScript widget organizers embed on their own website. iframe-based checkout modal with 3-step flow (select tickets → enter email → pay via Stripe Elements). Guest checkout creates lightweight Supabase auth users so existing ticket/webhook flow works unchanged.

**Architecture:** Widget JS (`tickety-widget.js`) fetches checkout HTML from `widget-checkout-page` edge function, injects into iframe via `srcdoc` (bypasses Supabase Storage Content-Type issues). Stripe Elements runs inside iframe for PCI compliance.

**Auth:** Widget API keys (`twk_live_xxx`) — SHA-256 hashed in DB, scoped by event IDs and allowed origins. Rate-limited (checkout sessions per key per minute). No buyer auth required (guest checkout).

**Database:** `widget_api_keys` (organizer keys with hash, scoping, rate limits), `widget_configs` (appearance customization), `widget_guest_buyers` (guest email/Stripe customer linking), `widget_checkout_sessions` (session tracking, 30min auto-expiry via pg_cron).

**Edge Functions:** `widget-get-event` (public event data + ticket types + widget config), `widget-create-checkout` (validates availability, creates guest user, Stripe PaymentIntent, payment record with `ticket_items` metadata), `widget-validate-promo` (promo code validation for guests), `widget-checkout-page` (serves checkout HTML with correct Content-Type). `stripe-webhook` updated to mark widget sessions as completed.

**Flutter:** `features/widget/` with models (`WidgetApiKey`, `WidgetConfig`), data (`WidgetRepository` with secure key generation via `crypto` package), presentation (`WidgetSettingsScreen` — key management, embed code snippet, appearance config). AdminEventScreen "Embed Widget" card. All tiers get widget access (Base requires "Powered by Tickety" branding).

**Embed code:**
```html
<script src="https://hnouslchigcmbiovdbfz.supabase.co/storage/v1/object/public/widget/v1/tickety-widget.js"></script>
<script>Tickety.init({ key: 'twk_live_xxx', eventId: 'uuid', container: '#btn' });</script>
```

### Organizer Branding (Priority 11 Phase 1)
Pro/Enterprise organizers set custom primary + accent colors and upload a logo. Colors override event detail page theme (buttons, chips, links). Logo appears on My Tickets card headers. Inline color wheel pickers on create event screen with live preview. Server-side event search added (title `ilike`). Tables: `organizer_branding`. Storage: `organizer-logos` bucket. Flutter: `features/branding/` module, `branding_provider.dart`. Gated by `TierLimits.canCustomizeBranding()`.

### Enhanced Referral & Affiliate System (Priority 13)
Turns the basic referral system into a full affiliate program. Four enhancements:

**Earnings Payout:** Referrers can withdraw earnings to their bank account via Stripe Express (reuses seller payout pattern). 7-day hold period for refund window. FIFO payout marking. Edge function: `withdraw-referral-earnings`. `get_referral_balance()` and `mark_referral_earnings_paid()` SQL functions.

**Channel-Tracked Links:** Referral links tagged with channel (Instagram, YouTube, TikTok, Twitter/X, Email, Website). Click tracking via public `track-referral-click` edge function (IP rate-limited). Channel stored on `profiles.referral_channel` via signup metadata. Earnings attributed to channels. `referral_channels` table with click/signup counts. `increment_referral_click()` SQL function. Channel selector chips on ReferralScreen.

**Referred User Benefits:** Referred users get 50% off Pro subscription for 6 months (Stripe coupon applied in `create-subscription-checkout`). Platform fee discount set to 5% (was 0%). Coupon tracked on `profiles.referral_coupon_id`. Benefit banner on ReferralScreen and SubscriptionScreen.

**Performance Dashboard:** `ReferralDashboardScreen` with Top Referrers leaderboard and Channel Performance tabs. Bar chart (fl_chart) showing signups by channel. Funnel breakdown (clicks → signups → sales → earnings). `get_referral_leaderboard()`, `get_referral_funnel_stats()`, `get_platform_referral_stats()` SQL functions. Accessible from AdminEventScreen.

**Tables/columns added:** `referral_channels`, `profiles.referral_channel`, `profiles.referral_coupon_id`, `referral_earnings.paid_at`, `referral_earnings.channel`, `referral_config.referee_sub_discount_percent`, `referral_config.referee_sub_benefit_months`. Migration: `20260318200001_referral_enhancements.sql`.

## Dev Seed Data

Engagement seed data for dashboard development in `supabase/seeds/`. Marker: `analytics_cache_meta` where `key = 'dev_seed_marker'`. Idempotent insert, cleanup script included.

Discovery algorithm seed data: `dev_discovery_seed.sql` (views, tickets, payments, tag affinity). Marker: `discovery_seed_marker`. Cleanup: `cleanup_discovery_seed.sql`.

## Roadmap

### Priority 9 — Event Aggregation & External Listings (BLOCKED — awaiting affiliate approvals)

Populate the discovery feed with events from external sources to solve the cold-start problem. **Code is built and deployed** (database, edge functions, Flutter mixed feed UI) — blocked on API keys pending affiliate program approval.

**Legal research findings (March 2026):**
- **Ticketmaster API ToS** prohibits "deriving revenue" from API data — broadly worded, risky for a competing platform. Safe path: join their **Affiliate Program via Impact.com** (explicit permission + commission per referred sale, 1,200+ partners already do this).
- **SeatGeek API ToS** explicitly prohibits using API to "create a service that directly competes with SeatGeek" and bans persistent data caching (only transient/intermediate allowed). Safe path: **Partner Program via Impact.com** (~$11 avg commission per sale).
- **Web scraping alternative:** Legal precedent supports scraping public event data (*Ticketmaster v. Tickets.com, 2000* — factual data like dates/venues not copyrightable; *hiQ v. LinkedIn, 2022* — scraping public pages doesn't violate CFAA). However, practical risks (IP blocking, legal threats) and Terms of Service breach-of-contract claims make this less attractive than affiliate programs.
- **Other sources:** Eventbrite API deprecated (2019). Bandsintown locked to single-artist keys. Songkick/JamBase require commercial licenses. Facebook Events closed since 2018. PredictHQ is enterprise-priced.

**Action items:**
1. Apply for Ticketmaster Affiliate Program (Impact.com)
2. Apply for SeatGeek Partner Program (Impact.com)
3. Once approved, set API keys + affiliate tracking IDs as Supabase secrets
4. Trigger initial sync: `curl -X POST .../sync-ticketmaster-events`

**Code ready:** `external_events` table, `sync-ticketmaster-events`, `sync-seatgeek-events`, `cleanup-external-events` edge functions, `ExternalEvent` model, `ExternalEventRepository`, mixed feed in `EventsHomeScreen` with source badges and deep links.

### Event Discovery Algorithm (Priority 10)
Two-layer weighted scoring system inspired by Steam's Discovery Queue. Replaces chronological feed with relevance-ranked results. Admin tuning dashboard for weight adjustment.

**Layer 1 — Pre-Computed Scores** (`event_scores` table, `refresh_event_scores()` via pg_cron every 15 min):
Six sub-scores (0.0–1.0): popularity (Bayesian-smoothed 7d views), velocity (48h ticket sales), engagement (view→purchase conversion), recency (creation date decay), urgency (sell-through %), organizer quality (verification status). Composite = weighted sum using `discovery_weights` config table.

**Layer 2 — Per-Request Personalization** (`get_personalized_feed()` RPC):
Proximity (Haversine distance boost), tag affinity (`user_tag_affinity` table, built from view/purchase/share interactions), price match (user avg vs event price). Time decay (`e^(-0.03 * days_until_event)`). Cold-start fallback: composite score only.

**Admin Tuning Dashboard** (`AlgorithmTuningScreen`):
Weight sliders (0.0–1.0) for all 9 signals. Preview button → `preview_feed_with_weights()` shows ranked list with rank change indicators. Apply persists weights + logs to `discovery_weight_history`. Platform-wide tag affinity bar chart (fl_chart). Accessible from AdminEventScreen.

**Featured Events:** Score-powered carousel with admin hand-pinning. `get_featured_events()` returns pinned events first, then top-scored. `toggle_featured_event()` for admin pin/unpin. `featured_at` column on events table. "Feature Event" toggle in AdminEventScreen.

**Tables:** `discovery_weights`, `discovery_weight_history`, `user_tag_affinity`, `event_scores`. **SQL functions:** `refresh_event_scores()`, `get_personalized_feed()`, `preview_feed_with_weights()`, `update_user_tag_affinity()`, `update_discovery_weight()`, `get_featured_events()`, `toggle_featured_event()`, `get_platform_tag_affinity()`.

**Flutter:** `features/discovery/` with models (`DiscoveryWeight`, `EventScore`, `FeedPreviewItem`, `WeightHistoryEntry`, `TagAffinityStat`, `FeaturedEventEntry`), repository (`DiscoveryRepository`), presentation (`AlgorithmTuningScreen` with tag affinity chart). Providers: `discoveryFeedProvider` replaces chronological feed, `discoveryFeaturedProvider` replaces chronological featured, `platformTagAffinityProvider` for admin chart, `toggleFeaturedProvider` for pin/unpin. Tag affinity tracked on event detail views.

**Seed data:** `supabase/seeds/dev_discovery_seed.sql` (views, tickets, payments, tag affinity across 3 taste clusters). Cleanup: `cleanup_discovery_seed.sql`. Marker: `discovery_seed_marker`.

**Optional future enhancement (Phase D):** Feed sections (Trending Now, Near You, Almost Sold Out, New This Week) — horizontal carousels on home screen. Diversity injection (max 3 consecutive same-category). Section toggles in admin. Not required for core functionality.

### Organizer Branding (Priority 11 — Phase 1 DONE)
Pro/Enterprise organizers customize event page colors and upload a logo. Simplified first step toward full white-labeling.

**What's built:**
- `organizer_branding` table (primary_color, accent_color, logo_url) with RLS + `organizer-logos` storage bucket
- `features/branding/` module: `OrganizerBranding` model, `BrandingRepository` (CRUD + logo upload), `BrandingSettingsScreen` (standalone settings)
- Inline branding on create event screen: color wheel pickers (`flutter_colorpicker`), logo upload, live preview showing branded chips/icons/buttons
- Event detail screen: wraps `Scaffold` in `Theme()` overriding `colorScheme.primary` and `colorScheme.secondary` with organizer colors — buttons, links, accents all pick up branding
- My Tickets screen: organizer logo displayed as 40px circle in ticket card gradient header
- Admin event screen: "Event Branding" card (Pro-gated, navigates to settings or upgrade)
- `TierLimits.canCustomizeBranding()` — Pro + Enterprise only
- `organizerId` field added to `EventModel` + `EventMapper`
- Server-side event search (`searchEvents` with `ilike` on title) — events appear in search even before discovery scoring
- Branding auto-saves when creating/editing events

**Phase 2 (future):** Custom domains (tickets.yourbrand.com), branded email notifications, branded wallet passes, full Tickety branding removal for Enterprise.

### Priority 12 — Public API

REST API for organizers to integrate with their own systems. Endpoints: events, tickets, orders, check-ins, discount codes. API key auth, rate limiting, webhook subscriptions. Developer documentation site.

### Localization / i18n (Priority 14)
CSV-based localization system modeled on the GDF Localization architecture. 77 files localized with 1,361 `L.tr()` calls across 1,173 unique string keys. 18 languages supported. Language picker in Settings.

**Architecture:**
- `core/localization/localization_service.dart`: CSV parser (quote-aware, GDF-style), lookup engine with `{0}` `{1}` variable injection, English fallback for missing translations
- Static API: `L.tr('key')` or `L.tr('key', [arg1, arg2])` — call anywhere, falls back to key itself if not in CSV
- `core/providers/locale_provider.dart`: Riverpod `localeProvider` — widgets `ref.watch(localeProvider)` to rebuild on language change
- `assets/localization.csv`: Master CSV (1,173 rows x 19 columns). Generated by `assets/gen_full_csv.py`
- `L.init()` called in `main.dart` before `runApp()`
- Language picker in Settings screen (bottom sheet with native language names)
- Preference saved to SharedPreferences (`preferred_locale`)

**18 Languages:** en, es, fr, de, pt, it, nl, ru, ja, ko, zh (Simplified), zh_TW (Traditional), ar, hi, tr, pl, th, id

**How to add a new string:**
1. Use `L.tr('your_key')` in Dart code — English text as key works as instant fallback
2. Add translations to `COMMON_TRANSLATIONS` in `assets/gen_full_csv.py`
3. Run `python3 gen_full_csv.py` in `assets/` to regenerate CSV
4. For parameterized: CSV value `"Hello {0}, you have {1} tickets"`, code `L.tr('key', [name, count])`

**How to add a new language:**
1. Add column code to LANGS array in `gen_full_csv.py`
2. Add translation for every string
3. Add entry to `L.localeNames` map in `localization_service.dart`
4. Run `python3 gen_full_csv.py`

**Translation status:** 120 keys have full 18-language translations (common UI words, auth, settings, profile, referral, events, tickets, payments, wallet, subscription, notifications, errors). Remaining keys fall back to English — add translations to `gen_full_csv.py` and regenerate.

### Priority 13 — Affiliate & Referral Tracking (DONE)

Channel-tracked referral links, earnings payout via Stripe Express, referred-user Pro subscription discount (50% off 6 months), performance dashboard with leaderboard and channel funnel charts. See "Enhanced Referral & Affiliate System" in Completed Features.

### Priority 14 — Localization / i18n (DONE)

CSV-based localization with 18 languages, 77 files, 1,361 `L.tr()` calls, 1,173 unique keys. Language picker in Settings. See "Localization / i18n" in Completed Features.

### Priority 15 — Public API

REST API for organizers to integrate with their own systems. Endpoints: events, tickets, orders, check-ins, discount codes. API key auth, rate limiting, webhook subscriptions. Developer documentation site.

## Cardano Phase 3 (Active)

**Philosophy:** Blockchain is invisible infrastructure, not a user-facing feature. Users never see "Cardano," "ADA," or "wallet." They buy tickets with card/bank, get NFT tickets automatically, and the blockchain serves as disaster recovery and trust verification.

- **Wallet UI hidden** — Crypto wallet screen removed from navigation. No send/receive ADA, no wallet balance, no mnemonic access. Fiat transaction history (purchases, receipts) remains in profile.
- **Fiat-to-ADA on-ramp** — Dropped. Users pay with card/bank via Stripe. Platform wallet covers all ADA costs.
- **External wallet connection** — Deferred. May revisit via CIP-30 (web) / CIP-45 (mobile QR) if user demand warrants it.
- **What still works silently:** NFT minting on purchase, 4-layer check-in verification (NFC signature → offline cache → blockchain → database), NFT transfer on resale, auto-burn 60 days post-event, verification discrepancy flagging (`checkin_flags` table).
- Multi-address derivation for privacy (future)
- Mainnet deployment — switch Blockfrost base URL + project ID (future)
- Organizer NFT customization — custom artwork/metadata on ticket NFTs (future)

## Competitive Landscape

**Ticket Tailor** (~73K organizers, $6.6M ARR, $0.26/ticket) — Primary ticketing for small/mid organizers. Bootstrapped via cold-calling venues. No buyer app, no resale, no NFTs.

**TicketSwap** (~11M users, ~$39M ARR, 36 countries) — Fan-to-fan resale marketplace. 20% max markup. "SecureSwap" reissues barcodes via primary ticketing API partnerships. Events appear when sellers upload tickets (seller-driven catalog). $12.2M total funding.

**DICE** — Primary ticketing with locked resale (no above-face-value). Strong in UK/US. Mobile-first.

**Twickets** — Face-value only resale. UK/Europe/US.

**Tickety advantages:**
- NFT tickets (CIP-68 on Cardano), crypto wallet (ADA), built-in resale marketplace
- ACH bank payments, native buyer app, tunable event discovery algorithm with admin dashboard
- Tap-to-pay NFC, comp/favor tickets, organizer verification
- Redeemable ticket add-ons, physical merch store (Shopify/Stripe), seating charts
- Embeddable checkout widget (iframe, guest checkout, Stripe Elements)
- Organizer branding (custom colors + logo on event pages)
- Affiliate referral program with channel tracking, payouts, and referred-user benefits
- 18-language localization with runtime language switching
- External event aggregation via affiliate programs (Ticketmaster/SeatGeek) for cold-start bootstrap + commission revenue
