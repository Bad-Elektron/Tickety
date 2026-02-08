import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/providers.dart';
import '../../../shared/widgets/limit_reached_banner.dart';
import '../../events/models/event_model.dart';
import '../../subscriptions/presentation/subscription_screen.dart';
import '../data/staff_repository.dart';
import '../models/staff_role.dart';

/// Full-screen staff management for event organizers.
class ManageStaffScreen extends ConsumerStatefulWidget {
  final EventModel event;

  const ManageStaffScreen({super.key, required this.event});

  @override
  ConsumerState<ManageStaffScreen> createState() => _ManageStaffScreenState();
}

class _ManageStaffScreenState extends ConsumerState<ManageStaffScreen> {
  final Map<StaffRole, bool> _expanded = {
    StaffRole.usher: true,
    StaffRole.seller: true,
    StaffRole.manager: true,
  };

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(staffProvider.notifier).loadStaff(widget.event.id);
    });
  }

  Color _roleColor(StaffRole role, ColorScheme colorScheme) {
    return switch (role) {
      StaffRole.usher => Colors.blue,
      StaffRole.seller => Colors.green,
      StaffRole.manager => colorScheme.primary,
    };
  }

  IconData _roleIcon(StaffRole role) {
    return switch (role) {
      StaffRole.usher => Icons.qr_code_scanner,
      StaffRole.seller => Icons.point_of_sale,
      StaffRole.manager => Icons.admin_panel_settings,
    };
  }

  Future<void> _addStaff() async {
    final staffState = ref.read(staffProvider);
    final result = await showDialog<_AddStaffResult>(
      context: context,
      builder: (context) => _AddStaffDialog(existingStaff: staffState.staff),
    );
    if (result == null || !mounted) return;

    // Check tier limit for the target role
    final limitCheck = ref.read(canAddStaffProvider(result.role));
    // For role updates, only block if it's a *new* addition to that role
    final isNewToRole = !result.isRoleUpdate;
    if (isNewToRole && !limitCheck.allowed) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(limitCheck.message ?? 'Staff limit reached'),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Upgrade',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SubscriptionScreen(),
                ),
              ),
            ),
          ),
        );
      }
      return;
    }

    if (result.isRoleUpdate && result.staffId != null) {
      // For role changes, check if the *target* role is at limit
      if (!limitCheck.allowed) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(limitCheck.message ?? 'Role limit reached'),
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: 'Upgrade',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SubscriptionScreen(),
                  ),
                ),
              ),
            ),
          );
        }
        return;
      }

      final success = await ref.read(staffProvider.notifier).updateRole(
            result.staffId!,
            result.role,
          );
      if (mounted && success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${result.user.displayLabel} updated to ${result.role.label}',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else {
      final success = await ref.read(staffProvider.notifier).addStaff(
            userId: result.user.id,
            role: result.role,
            email: result.user.email,
          );
      if (mounted && success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${result.user.displayLabel} added as ${result.role.label}',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }

    if (mounted) {
      final error = ref.read(staffProvider).error;
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _updateRole(EventStaff staff, StaffRole newRole) async {
    if (staff.role == newRole) return;

    // Check if the target role is at its limit
    final limitCheck = ref.read(canAddStaffProvider(newRole));
    if (!limitCheck.allowed) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(limitCheck.message ?? 'Role limit reached'),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Upgrade',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SubscriptionScreen(),
                ),
              ),
            ),
          ),
        );
      }
      return;
    }

    final success =
        await ref.read(staffProvider.notifier).updateRole(staff.id, newRole);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? '${staff.userName ?? staff.userEmail ?? 'Staff member'} updated to ${newRole.label}'
                : 'Failed to update role: ${ref.read(staffProvider).error ?? "Unknown error"}',
          ),
          backgroundColor: success ? null : Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _removeStaff(EventStaff staff) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Staff'),
        content: Text(
          'Remove ${staff.userName ?? staff.userEmail ?? 'this user'} from the event staff?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final success =
        await ref.read(staffProvider.notifier).removeStaff(staff.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Staff member removed'
                : 'Failed to remove: ${ref.read(staffProvider).error ?? "Unknown error"}',
          ),
          backgroundColor: success ? null : Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showStaffDetail(EventStaff staff) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _StaffMemberDetailSheet(
        staff: staff,
        onChangeRole: (role) {
          Navigator.pop(context);
          _updateRole(staff, role);
        },
        onRemove: () {
          Navigator.pop(context);
          _removeStaff(staff);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final staffState = ref.watch(staffProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            const Text('Manage Staff'),
            Text(
              widget.event.title,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addStaff,
        icon: const Icon(Icons.person_add),
        label: const Text('Add Staff'),
      ),
      body: staffState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : staffState.error != null
              ? _ErrorView(
                  error: staffState.error!,
                  onRetry: () =>
                      ref.read(staffProvider.notifier).refresh(),
                )
              : RefreshIndicator(
                  onRefresh: () =>
                      ref.read(staffProvider.notifier).refresh(),
                  child: CustomScrollView(
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                        sliver: SliverToBoxAdapter(
                          child: _SummaryRow(staffState: staffState),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate([
                            _buildRoleCard(
                              context,
                              role: StaffRole.usher,
                              staff: staffState.ushers,
                              statsText: 'People let in: \u2014  \u00B7  Check-in rate: \u2014  \u00B7  Current rate: \u2014/hr',
                            ),
                            const SizedBox(height: 16),
                            _buildRoleCard(
                              context,
                              role: StaffRole.seller,
                              staff: staffState.sellers,
                              statsText: 'Tickets sold: \u2014  \u00B7  Revenue: \u2014  \u00B7  Cash collected: \u2014',
                            ),
                            const SizedBox(height: 16),
                            _buildRoleCard(
                              context,
                              role: StaffRole.manager,
                              staff: staffState.managers,
                              statsText: 'Can check tickets, sell, and manage staff',
                            ),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildRoleCard(
    BuildContext context, {
    required StaffRole role,
    required List<EventStaff> staff,
    required String statsText,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color = _roleColor(role, colorScheme);
    final isExpanded = _expanded[role] ?? false;
    final limitCheck = ref.watch(canAddStaffProvider(role));

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          // Header
          InkWell(
            onTap: () => setState(() => _expanded[role] = !isExpanded),
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(16),
              bottom: Radius.circular(isExpanded ? 0 : 16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(_roleIcon(role), color: color, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${role.label}s',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: limitCheck.isAtLimit
                              ? colorScheme.error.withValues(alpha: 0.1)
                              : color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          limitCheck.limitText,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: limitCheck.isAtLimit
                                ? colorScheme.error
                                : color,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        isExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    statsText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Expanded staff list
          if (isExpanded) ...[
            Divider(
              height: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
            if (limitCheck.isAtLimit)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: LimitReachedBanner(
                  message: '${role.label} limit reached (${limitCheck.limitText})',
                ),
              ),
            if (staff.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No ${role.label.toLowerCase()}s assigned yet',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: staff.length,
                separatorBuilder: (context, index) => Divider(
                  height: 1,
                  indent: 72,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
                itemBuilder: (context, index) {
                  final member = staff[index];
                  return _StaffMemberRow(
                    staff: member,
                    roleColor: color,
                    onTap: () => _showStaffDetail(member),
                    onChangeRole: (role) => _updateRole(member, role),
                    onRemove: () => _removeStaff(member),
                  );
                },
              ),
          ],
        ],
      ),
    );
  }
}

// ============================================================
// Summary Row
// ============================================================

class _SummaryRow extends StatelessWidget {
  final StaffState staffState;

  const _SummaryRow({required this.staffState});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        Expanded(
          child: _MiniStatCard(
            label: 'Total Staff',
            value: '${staffState.totalCount}',
            icon: Icons.groups,
            color: colorScheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MiniStatCard(
            label: 'Checked In',
            value: '\u2014',
            icon: Icons.login,
            color: Colors.blue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MiniStatCard(
            label: 'Revenue',
            value: '\u2014',
            icon: Icons.attach_money,
            color: Colors.green,
          ),
        ),
      ],
    );
  }
}

class _MiniStatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MiniStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Staff Member Row
// ============================================================

class _StaffMemberRow extends StatelessWidget {
  final EventStaff staff;
  final Color roleColor;
  final VoidCallback onTap;
  final void Function(StaffRole) onChangeRole;
  final VoidCallback onRemove;

  const _StaffMemberRow({
    required this.staff,
    required this.roleColor,
    required this.onTap,
    required this.onChangeRole,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dismissible(
      key: ValueKey(staff.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onRemove();
        return false; // We handle removal in onRemove with confirmation
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: colorScheme.error.withValues(alpha: 0.1),
        child: Icon(Icons.delete_outline, color: colorScheme.error),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: roleColor.withValues(alpha: 0.15),
          child: Text(
            (staff.userName ?? staff.userEmail ?? 'U')[0].toUpperCase(),
            style: TextStyle(
              color: roleColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          staff.userName ?? staff.userEmail ?? 'Unknown User',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          staff.userEmail ?? staff.invitedEmail ?? '',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: _RoleBadgeDropdown(
          currentRole: staff.role,
          roleColor: roleColor,
          onChanged: onChangeRole,
        ),
      ),
    );
  }
}

// ============================================================
// Role Badge Dropdown
// ============================================================

class _RoleBadgeDropdown extends StatelessWidget {
  final StaffRole currentRole;
  final Color roleColor;
  final void Function(StaffRole) onChanged;

  const _RoleBadgeDropdown({
    required this.currentRole,
    required this.roleColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PopupMenuButton<StaffRole>(
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      tooltip: 'Change role',
      onSelected: onChanged,
      itemBuilder: (context) => StaffRole.values.map((role) {
        final isCurrent = role == currentRole;
        return PopupMenuItem(
          value: role,
          child: Row(
            children: [
              if (isCurrent)
                Icon(Icons.check, size: 18, color: colorScheme.primary)
              else
                const SizedBox(width: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      role.label,
                      style: TextStyle(
                        fontWeight:
                            isCurrent ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    Text(
                      role.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: roleColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              currentRole.label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: roleColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, size: 16, color: roleColor),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Staff Member Detail Sheet
// ============================================================

class _StaffMemberDetailSheet extends StatelessWidget {
  final EventStaff staff;
  final void Function(StaffRole) onChangeRole;
  final VoidCallback onRemove;

  const _StaffMemberDetailSheet({
    required this.staff,
    required this.onChangeRole,
    required this.onRemove,
  });

  Color _roleColor(StaffRole role, ColorScheme colorScheme) {
    return switch (role) {
      StaffRole.usher => Colors.blue,
      StaffRole.seller => Colors.green,
      StaffRole.manager => colorScheme.primary,
    };
  }

  IconData _roleIcon(StaffRole role) {
    return switch (role) {
      StaffRole.usher => Icons.qr_code_scanner,
      StaffRole.seller => Icons.point_of_sale,
      StaffRole.manager => Icons.admin_panel_settings,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color = _roleColor(staff.role, colorScheme);

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 16,
        bottom: MediaQuery.of(context).padding.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Avatar + name
          CircleAvatar(
            radius: 32,
            backgroundColor: color.withValues(alpha: 0.15),
            child: Icon(_roleIcon(staff.role), size: 28, color: color),
          ),
          const SizedBox(height: 16),
          Text(
            staff.userName ?? staff.userEmail ?? 'Unknown User',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            staff.userEmail ?? staff.invitedEmail ?? '',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          // Role badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_roleIcon(staff.role), size: 16, color: color),
                const SizedBox(width: 6),
                Text(
                  staff.role.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Stats section
          _buildStatsSection(context),
          const SizedBox(height: 24),
          // Actions
          Row(
            children: [
              Expanded(
                child: _RoleBadgeDropdown(
                  currentRole: staff.role,
                  roleColor: color,
                  onChanged: onChangeRole,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onRemove,
                  icon: Icon(Icons.person_remove, color: colorScheme.error),
                  label: Text(
                    'Remove',
                    style: TextStyle(color: colorScheme.error),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: colorScheme.error.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSection(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final stats = switch (staff.role) {
      StaffRole.usher => [
          ('Check-ins today', '\u2014'),
          ('Total check-ins', '\u2014'),
          ('Avg check-in rate', '\u2014'),
        ],
      StaffRole.seller => [
          ('Tickets sold today', '\u2014'),
          ('Revenue today', '\u2014'),
          ('Cash collected', '\u2014'),
        ],
      StaffRole.manager => [
          ('Check-ins today', '\u2014'),
          ('Tickets sold today', '\u2014'),
          ('Revenue today', '\u2014'),
          ('Cash collected', '\u2014'),
        ],
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Performance',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          ...stats.map((stat) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      stat.$1,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      stat.$2,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

// ============================================================
// Error View
// ============================================================

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: colorScheme.error, size: 48),
            const SizedBox(height: 16),
            Text('Failed to load staff', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              error,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Add Staff Dialog
// ============================================================

class _AddStaffDialog extends StatefulWidget {
  final List<EventStaff> existingStaff;

  const _AddStaffDialog({this.existingStaff = const []});

  @override
  State<_AddStaffDialog> createState() => _AddStaffDialogState();
}

class _AddStaffDialogState extends State<_AddStaffDialog> {
  final _repository = StaffRepository();
  final _emailController = TextEditingController();
  StaffRole _selectedRole = StaffRole.usher;
  List<UserSearchResult> _searchResults = [];
  UserSearchResult? _selectedUser;
  bool _isSearching = false;
  String? _searchError;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  EventStaff? _getExistingStaff(String userId) {
    return widget.existingStaff
        .where((s) => s.userId == userId)
        .firstOrNull;
  }

  Future<void> _searchUsers(String query) async {
    if (query.trim().length < 2) {
      setState(() {
        _searchResults = [];
        _searchError = null;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _searchError = null;
    });

    try {
      final results = await _repository.searchUsersByEmail(query);
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _searchError = 'Search failed: $e';
        _isSearching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: const Text('Add Staff Member'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Search by email',
                border: const OutlineInputBorder(),
                suffixIcon: _isSearching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : const Icon(Icons.search),
              ),
              onChanged: (value) {
                _searchUsers(value);
                if (_selectedUser != null) {
                  setState(() => _selectedUser = null);
                }
              },
            ),
            if (_searchError != null) ...[
              const SizedBox(height: 8),
              Text(
                _searchError!,
                style: TextStyle(color: colorScheme.error, fontSize: 12),
              ),
            ],
            if (_selectedUser != null) ...[
              const SizedBox(height: 12),
              Card(
                color: colorScheme.primaryContainer,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: colorScheme.primary,
                    child: Text(
                      (_selectedUser!.displayName ?? _selectedUser!.email)
                          .substring(0, 1)
                          .toUpperCase(),
                      style: TextStyle(color: colorScheme.onPrimary),
                    ),
                  ),
                  title: Text(
                    _selectedUser!.displayName ?? 'No name',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(_selectedUser!.email),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      setState(() {
                        _selectedUser = null;
                        _emailController.clear();
                        _searchResults = [];
                      });
                    },
                  ),
                ),
              ),
            ] else if (_searchResults.isNotEmpty) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 150),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _searchResults.length,
                  itemBuilder: (context, index) {
                    final user = _searchResults[index];
                    final existing = _getExistingStaff(user.id);
                    final isOnStaff = existing != null;

                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 16,
                        child: Text(
                          (user.displayName ?? user.email)
                              .substring(0, 1)
                              .toUpperCase(),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      title: Text(user.displayName ?? 'No name'),
                      subtitle: isOnStaff
                          ? Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.tertiary
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    existing.role.label,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: colorScheme.tertiary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'on staff',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            )
                          : Text(
                              user.email,
                              style: const TextStyle(fontSize: 12),
                            ),
                      onTap: () {
                        setState(() {
                          _selectedUser = user;
                          _emailController.text = user.email;
                          _searchResults = [];
                        });
                      },
                    );
                  },
                ),
              ),
            ] else if (_emailController.text.length >= 2 &&
                !_isSearching) ...[
              const SizedBox(height: 8),
              Text(
                'No users found',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 16),
            DropdownButtonFormField<StaffRole>(
              initialValue: _selectedRole,
              decoration: const InputDecoration(
                labelText: 'Role',
                border: OutlineInputBorder(),
              ),
              items: StaffRole.values.map((role) {
                return DropdownMenuItem(
                  value: role,
                  child: Text(role.label),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedRole = value);
                }
              },
            ),
            const SizedBox(height: 8),
            Text(
              _selectedRole.description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selectedUser == null
              ? null
              : () {
                  final existing = _getExistingStaff(_selectedUser!.id);
                  Navigator.pop(
                    context,
                    _AddStaffResult(
                      user: _selectedUser!,
                      role: _selectedRole,
                      isRoleUpdate: existing != null,
                      staffId: existing?.id,
                    ),
                  );
                },
          child: Text(
            _selectedUser != null &&
                    _getExistingStaff(_selectedUser!.id) != null
                ? 'Update Role'
                : 'Add',
          ),
        ),
      ],
    );
  }
}

class _AddStaffResult {
  final UserSearchResult user;
  final StaffRole role;
  final bool isRoleUpdate;
  final String? staffId;

  _AddStaffResult({
    required this.user,
    required this.role,
    this.isRoleUpdate = false,
    this.staffId,
  });
}
