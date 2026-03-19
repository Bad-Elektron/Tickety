import 'package:flutter/material.dart';

import '../../core/localization/localization.dart';

/// Standard error display widget for consistent error presentation.
///
/// Use this widget to display errors in a consistent manner across the app.
class ErrorDisplay extends StatelessWidget {
  /// The error message to display.
  final String message;

  /// Optional action button text.
  final String? actionText;

  /// Optional callback when action button is pressed.
  final VoidCallback? onAction;

  /// Optional callback when dismiss is pressed.
  final VoidCallback? onDismiss;

  /// Whether to show as a compact inline error.
  final bool compact;

  /// Icon to display. Defaults to error icon.
  final IconData icon;

  const ErrorDisplay({
    super.key,
    required this.message,
    this.actionText,
    this.onAction,
    this.onDismiss,
    this.compact = false,
    this.icon = Icons.error_outline,
  });

  /// Creates a network error display with retry action.
  factory ErrorDisplay.network({
    Key? key,
    String? message,
    VoidCallback? onRetry,
  }) {
    return ErrorDisplay(
      key: key,
      message: message ?? L.tr('error_network_message'),
      actionText: L.tr('retry'),
      onAction: onRetry,
      icon: Icons.wifi_off,
    );
  }

  /// Creates a generic error display with retry action.
  factory ErrorDisplay.generic({
    Key? key,
    String? message,
    VoidCallback? onRetry,
  }) {
    return ErrorDisplay(
      key: key,
      message: message ?? L.tr('error_generic_message'),
      actionText: L.tr('try_again'),
      onAction: onRetry,
    );
  }

  /// Creates a permission denied error display.
  factory ErrorDisplay.permission({
    Key? key,
    String? message,
    VoidCallback? onDismiss,
  }) {
    return ErrorDisplay(
      key: key,
      message: message ?? L.tr('error_permission_message'),
      icon: Icons.lock_outline,
      onDismiss: onDismiss,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (compact) {
      return _buildCompact(context, colorScheme);
    }

    return _buildFull(context, colorScheme);
  }

  Widget _buildCompact(BuildContext context, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.error.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: colorScheme.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.error,
              ),
            ),
          ),
          if (onDismiss != null)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: onDismiss,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              color: colorScheme.error,
            ),
        ],
      ),
    );
  }

  Widget _buildFull(BuildContext context, ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 48,
                color: colorScheme.error,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.8),
                  ),
            ),
            if (actionText != null && onAction != null) ...[
              const SizedBox(height: 24),
              FilledButton.tonal(
                onPressed: onAction,
                child: Text(actionText!),
              ),
            ],
            if (onDismiss != null && actionText == null) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: onDismiss,
                child: Text(L.tr('dismiss')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Snackbar helper for showing error messages.
class ErrorSnackBar {
  ErrorSnackBar._();

  /// Show an error snackbar with consistent styling.
  static void show(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 4),
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              Icons.error_outline,
              color: colorScheme.onError,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: colorScheme.onError),
              ),
            ),
          ],
        ),
        backgroundColor: colorScheme.error,
        behavior: SnackBarBehavior.floating,
        duration: duration,
        action: actionLabel != null && onAction != null
            ? SnackBarAction(
                label: actionLabel,
                textColor: colorScheme.onError,
                onPressed: onAction,
              )
            : null,
      ),
    );
  }

  /// Show a network error snackbar with retry action.
  static void showNetworkError(
    BuildContext context, {
    VoidCallback? onRetry,
  }) {
    show(
      context,
      L.tr('no_internet_connection'),
      actionLabel: onRetry != null ? L.tr('retry') : null,
      onAction: onRetry,
    );
  }

  /// Show a generic error snackbar.
  static void showGenericError(
    BuildContext context, {
    String? message,
    VoidCallback? onRetry,
  }) {
    show(
      context,
      message ?? L.tr('something_went_wrong'),
      actionLabel: onRetry != null ? L.tr('retry') : null,
      onAction: onRetry,
    );
  }
}

/// Dialog helper for showing error dialogs.
class ErrorDialog {
  ErrorDialog._();

  /// Show an error dialog with consistent styling.
  static Future<void> show(
    BuildContext context, {
    required String title,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
  }) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          Icons.error_outline,
          color: Theme.of(context).colorScheme.error,
          size: 48,
        ),
        title: Text(title),
        content: Text(message),
        actions: [
          if (onAction != null && actionLabel != null)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                onAction();
              },
              child: Text(actionLabel),
            ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(L.tr('ok')),
          ),
        ],
      ),
    );
  }

  /// Show a permission denied dialog.
  static Future<void> showPermissionDenied(
    BuildContext context, {
    String? message,
  }) {
    return show(
      context,
      title: L.tr('permission_denied'),
      message: message ?? L.tr('error_permission_message'),
    );
  }

  /// Show a session expired dialog with sign in action.
  static Future<void> showSessionExpired(
    BuildContext context, {
    VoidCallback? onSignIn,
  }) {
    return show(
      context,
      title: L.tr('session_expired'),
      message: L.tr('session_expired_message'),
      actionLabel: L.tr('sign_in'),
      onAction: onSignIn,
    );
  }
}
