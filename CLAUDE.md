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
