import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/services.dart';
import '../data/widget_repository.dart';
import '../models/widget_api_key.dart';
import '../models/widget_config.dart';

final _widgetRepoProvider = Provider((ref) => WidgetRepository());

final _apiKeysProvider = FutureProvider.autoDispose<List<WidgetApiKey>>((ref) async {
  return ref.read(_widgetRepoProvider).getApiKeys();
});

final _widgetConfigProvider = FutureProvider.autoDispose<WidgetConfig?>((ref) async {
  return ref.read(_widgetRepoProvider).getConfig();
});

class WidgetSettingsScreen extends ConsumerStatefulWidget {
  final String? eventId;
  final String? eventTitle;

  const WidgetSettingsScreen({super.key, this.eventId, this.eventTitle});

  @override
  ConsumerState<WidgetSettingsScreen> createState() => _WidgetSettingsScreenState();
}

class _WidgetSettingsScreenState extends ConsumerState<WidgetSettingsScreen> {
  String? _newKeyRaw;
  bool _creatingKey = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final keysAsync = ref.watch(_apiKeysProvider);
    final configAsync = ref.watch(_widgetConfigProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Embed Widget'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Info card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.code, color: colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Add a checkout widget to your website so fans can buy tickets without leaving your site.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // API Keys section
          Text('API Keys', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'Generate a key to authenticate your widget. Keep it secret — it controls access to your events.',
            style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),

          keysAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
            data: (keys) => Column(
              children: [
                ...keys.map((key) => _ApiKeyCard(
                  apiKey: key,
                  onToggle: () => _toggleKey(key),
                  onDelete: () => _deleteKey(key),
                )),
                if (keys.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'No API keys yet. Create one to get started.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),

          // Newly created key (one-time display)
          if (_newKeyRaw != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.key, color: Colors.green.shade700, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'New Key Created',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Copy this key now — it won\'t be shown again.',
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.green.shade700),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            _newKeyRaw!,
                            style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 18),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _newKeyRaw!));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Key copied to clipboard')),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _creatingKey ? null : _createKey,
            icon: _creatingKey
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.add),
            label: Text(_creatingKey ? 'Creating...' : 'Create API Key'),
          ),

          const SizedBox(height: 32),

          // Embed Code section
          Text('Embed Code', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'Copy this snippet and paste it into your website HTML.',
            style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),

          keysAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (keys) {
              final activeKey = keys.where((k) => k.isActive).firstOrNull;
              if (activeKey == null) {
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Create an API key first to see the embed code.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                );
              }

              final keyDisplay = _newKeyRaw ?? '${activeKey.keyPrefix}••••••••••••';
              final eventIdStr = widget.eventId ?? 'YOUR_EVENT_ID';
              final snippet = '''<div id="tickety-checkout"></div>
<script src="https://hnouslchigcmbiovdbfz.supabase.co/storage/v1/object/public/widget/v1/tickety-widget.js"></script>
<script>
  Tickety.init({
    key: '$keyDisplay',
    eventId: '$eventIdStr',
    container: '#tickety-checkout',
  });
</script>''';

              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SelectableText(
                      snippet,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: snippet));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Embed code copied!')),
                          );
                        },
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text('Copy'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: 32),

          // Widget Appearance section
          Text('Appearance', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),

          configAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
            data: (config) => _AppearanceSection(
              config: config,
              onSave: (updated) async {
                final repo = ref.read(_widgetRepoProvider);
                await repo.upsertConfig(updated);
                ref.invalidate(_widgetConfigProvider);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Widget appearance saved')),
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createKey() async {
    setState(() => _creatingKey = true);
    try {
      final repo = ref.read(_widgetRepoProvider);
      final key = await repo.createApiKey(
        label: widget.eventTitle != null ? 'Key for ${widget.eventTitle}' : null,
        allowedEventIds: widget.eventId != null ? [widget.eventId!] : null,
      );
      setState(() {
        _newKeyRaw = key.rawKey;
        _creatingKey = false;
      });
      ref.invalidate(_apiKeysProvider);
    } catch (e) {
      setState(() => _creatingKey = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create key: $e')),
        );
      }
    }
  }

  Future<void> _toggleKey(WidgetApiKey key) async {
    final repo = ref.read(_widgetRepoProvider);
    await repo.updateApiKey(key.id, isActive: !key.isActive);
    ref.invalidate(_apiKeysProvider);
  }

  Future<void> _deleteKey(WidgetApiKey key) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete API Key'),
        content: const Text('This will immediately revoke access for any widget using this key.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final repo = ref.read(_widgetRepoProvider);
    await repo.deleteApiKey(key.id);
    ref.invalidate(_apiKeysProvider);
  }
}

class _ApiKeyCard extends StatelessWidget {
  final WidgetApiKey apiKey;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _ApiKeyCard({
    required this.apiKey,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              Icons.vpn_key,
              size: 20,
              color: apiKey.isActive ? colorScheme.primary : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    apiKey.label ?? '${apiKey.keyPrefix}••••••',
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    apiKey.isActive ? 'Active' : 'Disabled',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: apiKey.isActive ? Colors.green : colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (apiKey.lastUsedAt != null)
                    Text(
                      'Last used ${_timeAgo(apiKey.lastUsedAt!)}',
                      style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            Switch(value: apiKey.isActive, onChanged: (_) => onToggle()),
            IconButton(
              icon: Icon(Icons.delete_outline, size: 20, color: colorScheme.error),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _AppearanceSection extends StatefulWidget {
  final WidgetConfig? config;
  final Future<void> Function(WidgetConfig) onSave;

  const _AppearanceSection({required this.config, required this.onSave});

  @override
  State<_AppearanceSection> createState() => _AppearanceSectionState();
}

class _AppearanceSectionState extends State<_AppearanceSection> {
  late TextEditingController _colorController;
  late String _buttonStyle;
  late bool _showPoweredBy;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _colorController = TextEditingController(text: widget.config?.primaryColor ?? '#6366F1');
    _buttonStyle = widget.config?.buttonStyle ?? 'rounded';
    _showPoweredBy = widget.config?.showPoweredBy ?? true;
  }

  @override
  void dispose() {
    _colorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Primary color
        _buildField(
          label: 'Primary Color',
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _parseColor(_colorController.text),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.outline),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _colorController,
                  decoration: const InputDecoration(
                    hintText: '#6366F1',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Button style
        _buildField(
          label: 'Button Style',
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'rounded', label: Text('Rounded')),
              ButtonSegment(value: 'square', label: Text('Square')),
              ButtonSegment(value: 'pill', label: Text('Pill')),
            ],
            selected: {_buttonStyle},
            onSelectionChanged: (val) => setState(() => _buttonStyle = val.first),
          ),
        ),
        const SizedBox(height: 16),

        // Powered by toggle
        SwitchListTile(
          title: const Text('Show "Powered by Tickety"'),
          subtitle: const Text('Required on Base tier'),
          value: _showPoweredBy,
          onChanged: (val) => setState(() => _showPoweredBy = val),
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 16),

        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving...' : 'Save Appearance'),
        ),
      ],
    );
  }

  Widget _buildField({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  Color _parseColor(String hex) {
    try {
      final cleaned = hex.replaceAll('#', '');
      return Color(int.parse('FF$cleaned', radix: 16));
    } catch (_) {
      return const Color(0xFF6366F1);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) return;

    final config = WidgetConfig(
      id: widget.config?.id ?? '',
      organizerId: userId,
      primaryColor: _colorController.text,
      buttonStyle: _buttonStyle,
      showPoweredBy: _showPoweredBy,
    );

    await widget.onSave(config);
    if (mounted) setState(() => _saving = false);
  }
}
