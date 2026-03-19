import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/localization.dart';
import '../../../core/providers/venue_provider.dart';
import '../models/venue.dart';

/// Bottom sheet for selecting or creating a venue during event creation.
class VenuePickerSheet extends ConsumerWidget {
  final ValueChanged<Venue> onVenueSelected;

  const VenuePickerSheet({
    super.key,
    required this.onVenueSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final venuesAsync = ref.watch(myVenuesProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.8,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    L.tr('Select Venue'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _createVenue(context, ref),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(L.tr('New')),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: venuesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Text('Error loading venues: $e'),
                ),
                data: (venues) {
                  if (venues.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.map_outlined,
                            size: 48,
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            L.tr('No venues yet'),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            onPressed: () => _createVenue(context, ref),
                            icon: const Icon(Icons.add, size: 18),
                            label: Text(L.tr('Create Venue')),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    controller: scrollController,
                    itemCount: venues.length,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemBuilder: (context, index) {
                      final venue = venues[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Icon(
                            Icons.map_outlined,
                            color: colorScheme.primary,
                          ),
                          title: Text(venue.name),
                          subtitle: Text(
                            '${venue.layout.totalCapacity} capacity'
                            ' \u2022 ${venue.layout.sections.length} sections',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            onVenueSelected(venue);
                            Navigator.pop(context);
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _createVenue(BuildContext context, WidgetRef ref) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: Text(L.tr('New Venue')),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: L.tr('Venue Name'),
              hintText: L.tr('e.g., Madison Square Garden'),
            ),
            textCapitalization: TextCapitalization.words,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(L.tr('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: Text(L.tr('Create')),
            ),
          ],
        );
      },
    );

    if (name != null && name.isNotEmpty && context.mounted) {
      await ref.read(myVenuesProvider.notifier).create(name);
      if (context.mounted) {
        Navigator.pop(context);
      }
    }
  }
}
