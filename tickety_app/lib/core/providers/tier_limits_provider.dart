import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/staff/models/staff_role.dart';
import '../../features/subscriptions/models/tier_limits.dart';
import 'staff_provider.dart';
import 'subscription_provider.dart';

/// Result of checking whether an action is within tier limits.
class LimitCheckResult {
  final bool allowed;
  final int currentCount;
  final int maxAllowed;
  final String? message;

  const LimitCheckResult({
    required this.allowed,
    required this.currentCount,
    required this.maxAllowed,
    this.message,
  });

  int get remaining => (maxAllowed - currentCount).clamp(0, maxAllowed);
  bool get isAtLimit => currentCount >= maxAllowed;
  String get limitText => '$currentCount/$maxAllowed';
}

/// Check whether adding a staff member with [role] is allowed.
///
/// Usage: `ref.watch(canAddStaffProvider(StaffRole.usher))`
final canAddStaffProvider = Provider.family<LimitCheckResult, StaffRole>((ref, role) {
  final tier = ref.watch(currentTierProvider);
  final staffState = ref.watch(staffProvider);
  final currentCount = staffState.getByRole(role).length;
  final max = TierLimits.getMaxForRole(tier, role.value);

  return LimitCheckResult(
    allowed: currentCount < max,
    currentCount: currentCount,
    maxAllowed: max,
    message: currentCount >= max
        ? '${role.label} limit reached ($currentCount/$max). Upgrade your plan for more.'
        : null,
  );
});

/// Check whether adding another ticket type is allowed.
///
/// Pass the current count of ticket types.
/// Usage: `ref.watch(canAddTicketTypeProvider(currentCount))`
final canAddTicketTypeProvider = Provider.family<LimitCheckResult, int>((ref, currentCount) {
  final tier = ref.watch(currentTierProvider);
  final max = TierLimits.getMaxTicketTypes(tier);

  return LimitCheckResult(
    allowed: currentCount < max,
    currentCount: currentCount,
    maxAllowed: max,
    message: currentCount >= max
        ? 'Ticket type limit reached ($currentCount/$max). Upgrade your plan for more.'
        : null,
  );
});

/// Check whether an analytics section is viewable at the current tier.
///
/// Usage: `ref.watch(canViewAnalyticsSectionProvider(AnalyticsSection.hourlyCheckins))`
final canViewAnalyticsSectionProvider =
    Provider.family<bool, AnalyticsSection>((ref, section) {
  final tier = ref.watch(currentTierProvider);
  return TierLimits.canViewAnalytics(tier, section);
});
