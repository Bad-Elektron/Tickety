# Tickety Development Roadmap

> Last updated: January 25, 2026

## Current State Summary

**Database Connectivity: ~85%**

| Feature | Status | Notes |
|---------|--------|-------|
| Events (CRUD) | ✅ Connected | Full Supabase integration |
| Tickets (Sales/Check-in) | ✅ Connected | Real database operations |
| Staff Management | ✅ Connected | User search, roles work |
| Authentication | ✅ Connected | Supabase Auth |
| Event Statistics | ✅ Connected | Real revenue/tickets sold |
| Search | ✅ Connected | Supabase ILIKE queries with input escaping |
| **Payments** | ✅ Connected | Stripe integration with full checkout flow |
| **My Tickets** | ✅ Connected | Users see purchased tickets |
| Wallet | ❌ UI Only | Shows "0" balance, no backend |
| Profile Editing | ❌ Not Built | "Coming soon" buttons |
| Vendor Ticket Sales | ✅ Connected | Real ticket sales to database |
| Usher Check-In | ✅ Connected | Triple method: QR, NFC, Manual |
| Notifications | ❌ Not Built | No feature exists |
| Settings | ❌ Not Built | No feature exists |

**Security & Error Handling: ~80%**

| Feature | Status | Notes |
|---------|--------|-------|
| RLS Policies | ✅ Complete | All tables secured in `supabase_setup.sql` |
| Input Validation | ✅ Complete | `validators.dart` - email, password, names, URLs |
| API Keys | ✅ Complete | `env_config.dart` uses `flutter_dotenv` |
| Rate Limiting | ✅ Complete | `rate_limiter.dart` - 5 attempts/15 min |
| Input Sanitization | ✅ Complete | Character filtering + SQL escape for search |
| Error Boundary | ✅ Complete | `error_handler.dart` - global handlers |
| User-Friendly Errors | ✅ Complete | `app_exception.dart` - full exception hierarchy |
| Error Logging | ✅ Complete | `app_logger.dart` - ready for Sentry/Crashlytics |
| Secure Token Storage | ⚠️ Partial | Relies on Supabase SDK platform defaults |
| Offline Detection | ❌ Missing | No `connectivity_plus` package |
| Auto-Retry Logic | ⚠️ Partial | Manual retry via UI; no exponential backoff |

---

## Phase 1: Fix Critical Bugs

**Priority: URGENT**
**Estimated effort: 1-2 days**

These are broken features that appear to work but don't actually persist data:

### 1.1 Fix Vendor Ticket Selling
- **File:** `lib/features/events/presentation/vendor_event_screen.dart`
- **Problem:** Generates fake ticket numbers locally instead of calling database
- **Solution:** Call `TicketRepository.sellTicket()` instead of local simulation
- **Status:** [x] COMPLETED (Jan 2026)

### 1.2 Fix Usher QR Scanning
- **File:** `lib/features/events/presentation/usher_event_screen.dart`
- **Problem:** Uses `PlaceholderTickets` instead of real ticket validation
- **Solution:**
  - Integrate QR scanner package (`mobile_scanner` or `qr_code_scanner`)
  - Parse ticket ID from QR code
  - Call `TicketRepository.getTicket()` to validate
  - Call `TicketRepository.checkInTicket()` on valid scan
- **Status:** [x] COMPLETED (Jan 2026)
- **Implementation:** Triple method check-in (QR, NFC tap, Manual entry)
  - Added `mobile_scanner` and `nfc_manager` packages
  - Created `QrScannerView` with camera viewfinder
  - Created `NfcTapView` for phone-to-phone tap check-in
  - Added NFC broadcast to `TicketScreen` for attendees
  - Real ticket validation via `ticketProvider`
  - Real check-in via database

### 1.3 Connect Search to Database
- **File:** `lib/features/search/data/event_search_repository.dart`
- **Problem:** `LocalEventSearchRepository` uses hardcoded 8 events
- **Solution:** Create `SupabaseEventSearchRepository` that queries events table
- **Status:** [x] COMPLETED (Jan 2026)

---

## Phase 2: Security & Error Handling

**Priority: HIGH**
**Status: ~80% COMPLETE (Jan 2026)**

### 2.1 Security Checklist
- [x] Verify Row Level Security (RLS) policies in Supabase
  - Implemented in `supabase_setup.sql` and `supabase_setup_fixed.sql`
  - Profiles, event_staff, tickets tables all secured
- [x] Input validation on all forms (email, price, dates)
  - `lib/core/utils/validators.dart` - comprehensive validators
  - Email, password complexity, display names, URLs, wallet addresses
- [ ] Secure token storage with `flutter_secure_storage`
  - **Deferred:** Supabase SDK uses platform-secure storage (Keychain/Keystore)
  - Can add explicit `flutter_secure_storage` later if needed
- [x] Remove any hardcoded API keys from client code
  - `lib/core/config/env_config.dart` uses `flutter_dotenv`
  - `.env` file in `.gitignore`, `.env.example` provided
- [x] Add rate limiting awareness for auth endpoints
  - `lib/core/utils/rate_limiter.dart` - 5 attempts per 15 minutes
  - Integrated in `AuthNotifier` for sign-in and sign-up
- [x] Sanitize user-generated content (event descriptions, names)
  - `Validators.sanitize()` removes control chars, normalizes whitespace
  - Search queries escape PostgreSQL special characters

### 2.2 Error Handling
- [x] Global error boundary widget
  - `lib/core/errors/error_handler.dart` - catches Flutter and platform errors
  - `lib/shared/widgets/error_display.dart` - reusable error UI components
  - `ErrorSnackBar` and `ErrorDialog` for consistent error presentation
- [ ] Graceful offline mode detection
  - **Not implemented:** No `connectivity_plus` package
  - Network errors are caught but no proactive offline UI
- [x] Retry logic for failed network requests
  - Manual retry via `ErrorDisplay` with `onRetry` callbacks
  - `ErrorHandler.tryAsync()` and `Future.tryOrNull()` extensions
  - **Note:** No automatic retry with exponential backoff yet
- [x] User-friendly error messages (replace technical errors)
  - `lib/core/errors/app_exception.dart` - full exception hierarchy
  - `NetworkException`, `AuthException`, `ValidationException`, etc.
  - Each has `userMessage` for UI and `technicalDetails` for logging
- [x] Add error logging service (Sentry or Crashlytics)
  - `lib/core/errors/app_logger.dart` - centralized logging
  - Log levels, tags, timestamps, stack traces
  - `setRemoteLogger()` hook ready for Sentry/Crashlytics integration

### 2.3 Database Security
**Status: IMPLEMENTED** - See `supabase_setup.sql`

RLS policies implemented:
- Profiles: viewable by everyone, update own only
- Event_staff: organizers manage, users view own assignments
- Tickets: organizers/staff view, sellers create, staff update for check-in

### 2.4 Remaining Items (Optional)
These can be addressed later or during Phase 5 polish:
- [ ] Add `connectivity_plus` for proactive offline detection
- [ ] Implement automatic retry with exponential backoff
- [ ] Configure Sentry/Crashlytics using existing `AppLogger` hooks
- [ ] Add offline data caching layer

---

## Phase 3: Payment Integration

**Priority: HIGH (Required for launch)**
**Status: ✅ COMPLETE (January 25, 2026)**

### 3.1 Stripe Setup
- [x] Create Stripe account and get API keys
- [x] Add `flutter_stripe` package (v11.5.0)
- [x] Set up Supabase Edge Functions for server-side operations
- [x] Create webhook endpoint for payment confirmations
- [x] Configure Stripe webhook secret

### 3.2 Database Schema
- [x] Created `payments` table via migration
- [x] Created `resale_listings` table for secondary market (future)
- [x] Added `stripe_customer_id` to profiles
- [x] Added `stripe_connect_account_id` for seller payouts (future)
- [x] Fixed RLS policies for ticket visibility (buyers can see purchased tickets)

### 3.3 Features Implemented
- [x] **Stripe Payment Sheet** - Cards, Apple Pay, Google Pay
- [x] **Checkout flow** - Full purchase flow with quantity selection
- [x] **Payment confirmation screen** - Success state with ticket details
- [x] **Webhook ticket creation** - Tickets auto-created on payment success
- [x] **My Tickets screen** - Users see all purchased tickets
- [x] **Price validation** - Server-side validation prevents tampering
- [x] **Multi-ticket purchase** - Buy multiple tickets in one transaction
- [ ] Receipt/confirmation email (future)
- [ ] Wallet top-up via Stripe (future)
- [ ] Refund flow - Edge Function ready, UI not built

### 3.4 Supabase Edge Functions Created
```
supabase/functions/
├── create-payment-intent/    # Creates Stripe PaymentIntent with validation
├── stripe-webhook/           # Handles payment success, creates tickets
├── process-refund/           # Processes refund requests
├── create-connect-account/   # Stripe Connect for sellers (future)
├── create-resale-intent/     # Resale marketplace (future)
└── connect-webhook/          # Connect account updates (future)
```

### 3.5 Flutter Files Created
```
lib/features/payments/
├── data/
│   ├── i_payment_repository.dart
│   ├── payment_repository.dart
│   ├── i_resale_repository.dart
│   └── resale_repository.dart
├── models/
│   ├── payment.dart
│   └── resale_listing.dart
├── presentation/
│   ├── checkout_screen.dart
│   ├── payment_success_screen.dart
│   ├── payment_test_screen.dart
│   ├── resale_browse_screen.dart
│   └── seller_onboarding_screen.dart
└── payments.dart

lib/core/
├── providers/payment_provider.dart
└── services/stripe_service.dart
```

### 3.6 Test Coverage
- [x] 24 unit tests for Payment models
- [x] 29 unit tests for PaymentProvider
- [x] All 413 tests passing

---

## Phase 4: Crypto Integration

**Priority: MEDIUM (Post-launch feature)**
**Estimated effort: 3-4 weeks**

### 4.1 Wallet Connection
- [ ] Choose SDK: WalletConnect v2 or Phantom (for Solana)
- [ ] Add wallet connect button to profile
- [ ] Store wallet address in profiles table
- [ ] Display connected wallet status

### 4.2 Blockchain Selection
**Recommended: Polygon (Ethereum L2)**
- Lower gas fees than Ethereum mainnet
- Good Flutter/Dart SDK support
- Wide wallet compatibility

**Alternative: Solana**
- Even lower fees
- Faster transactions
- Phantom wallet integration

### 4.3 NFT Ticket Minting
- [ ] Design NFT metadata schema
- [ ] Create/deploy smart contract for ticket NFTs
- [ ] Mint NFT on ticket purchase (optional feature)
- [ ] Display NFT artwork in ticket view
- [ ] Add NFT transfer capability

### 4.4 $TIK Token (Future)
- [ ] Design tokenomics
- [ ] Deploy token contract
- [ ] Reward tokens for event attendance
- [ ] Accept tokens as payment
- [ ] Token staking for benefits

### 4.5 Database Changes
```sql
-- Already exists in tickets table:
-- nft_minted BOOLEAN DEFAULT FALSE
-- nft_asset_id TEXT
-- nft_minted_at TIMESTAMPTZ

-- Add to profiles:
ALTER TABLE profiles ADD COLUMN wallet_address TEXT;
ALTER TABLE profiles ADD COLUMN wallet_chain TEXT; -- 'polygon', 'solana', etc.
ALTER TABLE profiles ADD COLUMN tik_balance DECIMAL DEFAULT 0;
```

---

## Phase 5: Polish & Production Readiness

**Priority: HIGH (Before launch)**
**Estimated effort: 1-2 weeks**

### 5.1 User Experience
- [ ] Loading states on all screens
- [ ] Skeleton loaders instead of spinners
- [ ] Pull-to-refresh everywhere
- [ ] Empty states with helpful messages
- [ ] Haptic feedback on key actions
- [ ] Onboarding flow for new users

### 5.2 Performance
- [ ] Image caching with `cached_network_image`
- [ ] Pagination for event lists (currently loads all)
- [ ] Lazy loading for ticket lists
- [ ] Memory profiling and leak fixes
- [ ] App size optimization

### 5.3 Testing
- [ ] Unit tests for all repositories
- [ ] Widget tests for auth flow
- [ ] Widget tests for ticket purchase flow
- [ ] Integration tests for critical paths
- [ ] Test on physical iOS device
- [ ] Test on physical Android device
- [ ] Test with slow network (3G simulation)
- [ ] Test offline behavior

### 5.4 Production Setup
- [ ] Environment configuration (dev/staging/prod)
- [ ] App icons (all sizes)
- [ ] Splash screen
- [ ] App Store screenshots and description
- [ ] Play Store listing
- [ ] Privacy Policy document
- [ ] Terms of Service document
- [ ] Set up analytics (Firebase Analytics or similar)
- [ ] Set up crash reporting (Crashlytics)
- [ ] Push notification setup (Firebase Cloud Messaging)
- [ ] Deep linking for event sharing

---

## Phase 6: Additional Features (Post-Launch)

### 6.1 Social Features
- [ ] Follow event organizers
- [ ] Share events to social media
- [ ] Invite friends to events
- [ ] Event comments/reviews

### 6.2 Organizer Tools
- [ ] Event analytics dashboard
- [ ] Attendee messaging
- [ ] Promo codes / discounts
- [ ] Multi-tier ticket pricing
- [ ] Waitlist management

### 6.3 Discovery
- [ ] Location-based event discovery
- [ ] Personalized recommendations
- [ ] Event categories/filtering
- [ ] Calendar integration

### 6.4 Notifications
- [ ] Event reminders
- [ ] Ticket purchase confirmations
- [ ] Check-in confirmations
- [ ] Organizer announcements
- [ ] Price drop alerts

---

## Priority Order Summary

```
✅ DONE:    Phase 1 - Fix Critical Bugs
✅ DONE:    Phase 2 - Security & Error Handling (~80%)
✅ DONE:    Phase 3 - Payment Integration (Stripe)
➡️ NEXT:    Phase 5 - Polish & Production
            Launch MVP
            Phase 4 - Crypto Integration
Ongoing:    Phase 6 - Additional Features
```

---

## Quick Reference: Key Files

### Repositories (Database Layer)
- `lib/features/events/data/supabase_event_repository.dart`
- `lib/features/staff/data/ticket_repository.dart`
- `lib/features/staff/data/staff_repository.dart`
- `lib/features/search/data/event_search_repository.dart`
- `lib/features/payments/data/payment_repository.dart` ✅ NEW

### Payments (Stripe Integration)
- `lib/core/services/stripe_service.dart` - Stripe SDK wrapper
- `lib/core/providers/payment_provider.dart` - Payment state management
- `lib/features/payments/presentation/checkout_screen.dart` - Checkout UI
- `lib/features/payments/presentation/payment_success_screen.dart` - Success screen
- `supabase/functions/create-payment-intent/` - Server-side payment creation
- `supabase/functions/stripe-webhook/` - Webhook handler for payment events

### Error Handling
- `lib/core/errors/error_handler.dart` - Global error boundary
- `lib/core/errors/app_exception.dart` - Exception hierarchy
- `lib/core/errors/app_logger.dart` - Logging service
- `lib/shared/widgets/error_display.dart` - Error UI components

### Security
- `lib/core/utils/validators.dart` - Input validation & sanitization
- `lib/core/utils/rate_limiter.dart` - Auth rate limiting
- `lib/core/config/env_config.dart` - Environment variables

### Providers (State Management)
- `lib/core/providers/events_provider.dart`
- `lib/core/providers/ticket_provider.dart`
- `lib/core/providers/staff_provider.dart`
- `lib/core/providers/auth_provider.dart`
- `lib/core/providers/payment_provider.dart` ✅ NEW

### Screens Needing Work
- `lib/features/wallet/presentation/wallet_screen.dart` ❌ UI only
- `lib/features/profile/presentation/profile_screen.dart` ❌ Incomplete

---

## Notes

- Always test payment flows in Stripe test mode first
- Keep crypto features behind feature flags initially
- Prioritize iOS App Store review time (can take 1-2 weeks)
- Plan for 20% buffer time on all estimates
