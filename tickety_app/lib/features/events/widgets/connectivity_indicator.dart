import 'package:flutter/material.dart';

/// Connection status widget with two display modes.
///
/// - Green: "Online" with optional sync count
/// - Amber: "Syncing..." with pending count
/// - Red: "Offline" with pending count
///
/// Set [expanded] to true for a full-width banner style.
class ConnectivityIndicator extends StatelessWidget {
  const ConnectivityIndicator({
    super.key,
    required this.isOnline,
    this.pendingSyncCount = 0,
    this.isSyncing = false,
    this.expanded = false,
  });

  final bool isOnline;
  final int pendingSyncCount;
  final bool isSyncing;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final (color, label, icon) = _getConfig();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: EdgeInsets.symmetric(
        horizontal: expanded ? 16 : 10,
        vertical: expanded ? 10 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(expanded ? 14 : 12),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment:
            expanded ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          if (isSyncing)
            SizedBox(
              width: expanded ? 16 : 12,
              height: expanded ? 16 : 12,
              child: CircularProgressIndicator(
                strokeWidth: expanded ? 2 : 1.5,
                color: color,
              ),
            )
          else
            Container(
              width: expanded ? 10 : 8,
              height: expanded ? 10 : 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
          SizedBox(width: expanded ? 10 : 6),
          Icon(icon, size: expanded ? 18 : 14, color: color),
          SizedBox(width: expanded ? 6 : 4),
          Text(
            label,
            style: TextStyle(
              fontSize: expanded ? 13 : 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  (Color, String, IconData) _getConfig() {
    if (!isOnline) {
      final suffix = pendingSyncCount > 0 ? ' ($pendingSyncCount pending)' : '';
      return (
        const Color(0xFFF44336),
        'Offline$suffix',
        Icons.cloud_off,
      );
    }

    if (isSyncing || pendingSyncCount > 0) {
      return (
        Colors.amber.shade700,
        'Syncing $pendingSyncCount',
        Icons.sync,
      );
    }

    return (
      const Color(0xFF4CAF50),
      'Online — Door list cached',
      Icons.cloud_done_outlined,
    );
  }
}
