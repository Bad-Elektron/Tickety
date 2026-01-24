import 'package:flutter/material.dart';

import '../../../core/services/services.dart';
import '../../events/models/event_model.dart';
import '../data/staff_repository.dart';
import '../models/staff_role.dart';

/// Screen for event organizers to manage their staff.
class ManageStaffScreen extends StatefulWidget {
  final EventModel event;

  const ManageStaffScreen({super.key, required this.event});

  @override
  State<ManageStaffScreen> createState() => _ManageStaffScreenState();
}

class _ManageStaffScreenState extends State<ManageStaffScreen> {
  final _repository = StaffRepository();
  List<EventStaff> _staff = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  Future<void> _loadStaff() async {
    setState(() => _isLoading = true);
    try {
      final staff = await _repository.getEventStaff(widget.event.id);
      setState(() => _staff = staff);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load staff: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addStaff() async {
    final result = await showDialog<_AddStaffResult>(
      context: context,
      builder: (context) => _AddStaffDialog(),
    );

    if (result == null) return;

    try {
      // For now, use the email as a placeholder - in production you'd
      // look up the user by email or send an invitation
      final userId = SupabaseService.instance.currentUser?.id;
      if (userId == null) return;

      await _repository.addStaff(
        eventId: widget.event.id,
        userId: userId, // TODO: Look up user by email
        role: result.role,
        email: result.email,
      );

      await _loadStaff();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Staff member added'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add staff: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _removeStaff(EventStaff staff) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Staff'),
        content: Text(
          'Remove ${staff.userName ?? staff.invitedEmail ?? 'this person'} from your event staff?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _repository.removeStaff(staff.id);
      await _loadStaff();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Staff member removed'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to remove staff: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Staff'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _staff.isEmpty
              ? _EmptyState(onAddStaff: _addStaff)
              : RefreshIndicator(
                  onRefresh: _loadStaff,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _staff.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            '${_staff.length} staff member${_staff.length == 1 ? '' : 's'}',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        );
                      }

                      final staff = _staff[index - 1];
                      return _StaffCard(
                        staff: staff,
                        onRemove: () => _removeStaff(staff),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addStaff,
        icon: const Icon(Icons.person_add),
        label: const Text('Add Staff'),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAddStaff;

  const _EmptyState({required this.onAddStaff});

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
            Icon(
              Icons.groups_outlined,
              size: 64,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No staff yet',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add staff members to help manage your event',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAddStaff,
              icon: const Icon(Icons.person_add),
              label: const Text('Add Staff'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StaffCard extends StatelessWidget {
  final EventStaff staff;
  final VoidCallback onRemove;

  const _StaffCard({
    required this.staff,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getRoleColor(staff.role).withValues(alpha: 0.2),
          child: Icon(
            _getRoleIcon(staff.role),
            color: _getRoleColor(staff.role),
          ),
        ),
        title: Text(
          staff.userName ?? staff.invitedEmail ?? 'Unknown',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _getRoleColor(staff.role).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                staff.role.label,
                style: TextStyle(
                  fontSize: 12,
                  color: _getRoleColor(staff.role),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              staff.role.description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          color: colorScheme.error,
          onPressed: onRemove,
        ),
      ),
    );
  }

  Color _getRoleColor(StaffRole role) {
    return switch (role) {
      StaffRole.usher => Colors.blue,
      StaffRole.seller => Colors.green,
      StaffRole.manager => Colors.purple,
    };
  }

  IconData _getRoleIcon(StaffRole role) {
    return switch (role) {
      StaffRole.usher => Icons.qr_code_scanner,
      StaffRole.seller => Icons.point_of_sale,
      StaffRole.manager => Icons.admin_panel_settings,
    };
  }
}

class _AddStaffDialog extends StatefulWidget {
  @override
  State<_AddStaffDialog> createState() => _AddStaffDialogState();
}

class _AddStaffDialogState extends State<_AddStaffDialog> {
  final _emailController = TextEditingController();
  StaffRole _selectedRole = StaffRole.usher;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Staff Member'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email address',
              border: OutlineInputBorder(),
            ),
          ),
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
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_emailController.text.trim().isNotEmpty) {
              Navigator.pop(
                context,
                _AddStaffResult(
                  email: _emailController.text.trim(),
                  role: _selectedRole,
                ),
              );
            }
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _AddStaffResult {
  final String email;
  final StaffRole role;

  _AddStaffResult({required this.email, required this.role});
}
