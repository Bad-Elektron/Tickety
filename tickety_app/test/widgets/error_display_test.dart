import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tickety/shared/widgets/error_display.dart';

void main() {
  group('ErrorDisplay', () {
    testWidgets('displays error message', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ErrorDisplay(message: 'Test error message'),
          ),
        ),
      );

      expect(find.text('Test error message'), findsOneWidget);
    });

    testWidgets('displays error icon by default', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ErrorDisplay(message: 'Error'),
          ),
        ),
      );

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('displays custom icon when provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ErrorDisplay(
              message: 'Error',
              icon: Icons.wifi_off,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
    });

    testWidgets('displays action button when provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ErrorDisplay(
              message: 'Error',
              actionText: 'Retry',
              onAction: () {},
            ),
          ),
        ),
      );

      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('calls onAction when action button is tapped', (tester) async {
      var actionCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ErrorDisplay(
              message: 'Error',
              actionText: 'Retry',
              onAction: () => actionCalled = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Retry'));
      expect(actionCalled, isTrue);
    });

    testWidgets('compact displays inline error', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ErrorDisplay(
              message: 'Compact error',
              compact: true,
            ),
          ),
        ),
      );

      expect(find.text('Compact error'), findsOneWidget);
    });

    testWidgets('compact shows dismiss button when onDismiss provided', (tester) async {
      var dismissed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ErrorDisplay(
              message: 'Error',
              compact: true,
              onDismiss: () => dismissed = true,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.close), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      expect(dismissed, isTrue);
    });
  });

  group('ErrorDisplay factories', () {
    testWidgets('network creates network error display', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ErrorDisplay.network(onRetry: () {}),
          ),
        ),
      );

      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('generic creates generic error display', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ErrorDisplay.generic(onRetry: () {}),
          ),
        ),
      );

      expect(find.text('Try Again'), findsOneWidget);
    });

    testWidgets('permission creates permission denied display', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ErrorDisplay.permission(),
          ),
        ),
      );

      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.textContaining('permission'), findsOneWidget);
    });
  });

  group('ErrorSnackBar', () {
    testWidgets('show displays snackbar with error message', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => ErrorSnackBar.show(context, 'Test error'),
                child: const Text('Show Error'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Error'));
      await tester.pump();

      expect(find.text('Test error'), findsOneWidget);
    });

    testWidgets('show displays action button when provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => ErrorSnackBar.show(
                  context,
                  'Error',
                  actionLabel: 'Retry',
                  onAction: () {},
                ),
                child: const Text('Show Error'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Error'));
      await tester.pump();

      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('showNetworkError displays network message', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => ErrorSnackBar.showNetworkError(context),
                child: const Text('Show Error'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Error'));
      await tester.pump();

      expect(find.textContaining('internet'), findsOneWidget);
    });

    testWidgets('showGenericError displays generic message', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => ErrorSnackBar.showGenericError(context),
                child: const Text('Show Error'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Error'));
      await tester.pump();

      expect(find.textContaining('wrong'), findsOneWidget);
    });
  });

  group('ErrorDialog', () {
    testWidgets('show displays dialog with title and message', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => ErrorDialog.show(
                  context,
                  title: 'Error Title',
                  message: 'Error message',
                ),
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Error Title'), findsOneWidget);
      expect(find.text('Error message'), findsOneWidget);
    });

    testWidgets('show displays OK button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => ErrorDialog.show(
                  context,
                  title: 'Error',
                  message: 'Message',
                ),
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('OK'), findsOneWidget);
    });

    testWidgets('show closes dialog when OK is pressed', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => ErrorDialog.show(
                  context,
                  title: 'Error',
                  message: 'Message',
                ),
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('Error'), findsNothing);
    });

    testWidgets('show displays action button when provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => ErrorDialog.show(
                  context,
                  title: 'Error',
                  message: 'Message',
                  actionLabel: 'Try Again',
                  onAction: () {},
                ),
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Try Again'), findsOneWidget);
    });

    testWidgets('showPermissionDenied displays permission dialog', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => ErrorDialog.showPermissionDenied(context),
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Permission Denied'), findsOneWidget);
    });

    testWidgets('showSessionExpired displays session dialog with sign in', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => ErrorDialog.showSessionExpired(
                  context,
                  onSignIn: () {},
                ),
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Session Expired'), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);
    });
  });
}
