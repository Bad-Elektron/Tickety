import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/venue_provider.dart';
import '../models/venue.dart';
import 'venue_builder_screen.dart';

/// Screen listing the organizer's venues with FAB to create new ones.
class VenuesScreen extends ConsumerWidget {
  const VenuesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final venuesAsync = ref.watch(myVenuesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Venues'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createVenue(context, ref),
        child: const Icon(Icons.add),
      ),
      body: venuesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: colorScheme.error),
              const SizedBox(height: 12),
              Text('Error loading venues', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => ref.read(myVenuesProvider.notifier).refresh(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (venues) {
          if (venues.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.map_outlined,
                    size: 64,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No venues yet',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create a venue layout to use\nwith your events',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => _createVenue(context, ref),
                    icon: const Icon(Icons.add),
                    label: const Text('Create Venue'),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => ref.read(myVenuesProvider.notifier).refresh(),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: venues.length,
              itemBuilder: (context, index) {
                final venue = venues[index];
                return _VenueCard(
                  venue: venue,
                  onTap: () => _openBuilder(context, venue.id),
                  onDelete: () => _deleteVenue(context, ref, venue),
                  onDuplicate: () => _duplicateVenue(context, ref, venue),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _createVenue(BuildContext context, WidgetRef ref) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('New Venue'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Venue Name',
              hintText: 'e.g., Main Arena',
            ),
            textCapitalization: TextCapitalization.words,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );

    if (name != null && name.isNotEmpty && context.mounted) {
      final venue = await ref.read(myVenuesProvider.notifier).create(name);
      if (context.mounted) {
        _openBuilder(context, venue.id);
      }
    }
  }

  void _openBuilder(BuildContext context, String venueId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VenueBuilderScreen(venueId: venueId),
      ),
    );
  }

  Future<void> _deleteVenue(BuildContext context, WidgetRef ref, Venue venue) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Venue'),
        content: Text('Are you sure you want to delete "${venue.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(myVenuesProvider.notifier).delete(venue.id);
    }
  }

  Future<void> _duplicateVenue(BuildContext context, WidgetRef ref, Venue venue) async {
    await ref.read(venueRepositoryProvider).duplicateVenue(
      venue.id,
      '${venue.name} (Copy)',
    );
    ref.read(myVenuesProvider.notifier).refresh();
  }
}

class _VenueCard extends StatelessWidget {
  final Venue venue;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onDuplicate;

  const _VenueCard({
    required this.venue,
    required this.onTap,
    required this.onDelete,
    required this.onDuplicate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Venue icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.map_outlined,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 14),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      venue.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${venue.layout.totalCapacity} capacity'
                      ' \u2022 ${venue.layout.sections.length} sections'
                      ' \u2022 ${venue.layout.elements.length} elements',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              // Menu
              PopupMenuButton<String>(
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'duplicate',
                    child: Row(
                      children: [
                        Icon(Icons.copy_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('Duplicate'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, size: 18, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Delete', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
                onSelected: (value) {
                  if (value == 'delete') onDelete();
                  if (value == 'duplicate') onDuplicate();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
