import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/localization/localization.dart';
import '../../../core/providers/providers.dart';
import '../data/branding_repository.dart';

final _brandingRepoProvider = Provider((ref) => BrandingRepository());

class BrandingSettingsScreen extends ConsumerStatefulWidget {
  const BrandingSettingsScreen({super.key});

  @override
  ConsumerState<BrandingSettingsScreen> createState() =>
      _BrandingSettingsScreenState();
}

class _BrandingSettingsScreenState
    extends ConsumerState<BrandingSettingsScreen> {
  final _primaryController = TextEditingController(text: '#6366F1');
  final _accentController = TextEditingController();
  String? _logoUrl;
  bool _saving = false;
  bool _uploading = false;
  bool _loaded = false;

  static const _presetColors = [
    '#6366F1', // Indigo (default)
    '#EF4444', // Red
    '#F97316', // Orange
    '#EAB308', // Yellow
    '#22C55E', // Green
    '#06B6D4', // Cyan
    '#3B82F6', // Blue
    '#8B5CF6', // Violet
    '#EC4899', // Pink
    '#64748B', // Slate
    '#000000', // Black
  ];

  @override
  void dispose() {
    _primaryController.dispose();
    _accentController.dispose();
    super.dispose();
  }

  Color _parseHex(String hex) {
    final cleaned = hex.replaceFirst('#', '');
    final value = int.tryParse(cleaned, radix: 16);
    if (value == null) return const Color(0xFF6366F1);
    return Color(0xFF000000 | value);
  }

  bool _isValidHex(String hex) {
    final cleaned = hex.replaceFirst('#', '');
    if (cleaned.length != 6) return false;
    return int.tryParse(cleaned, radix: 16) != null;
  }

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (image == null) return;

    setState(() => _uploading = true);
    try {
      final bytes = await image.readAsBytes();
      final ext = image.name.split('.').last;
      final repo = ref.read(_brandingRepoProvider);
      final url = await repo.uploadLogo(bytes, 'logo.$ext');
      setState(() => _logoUrl = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L.tr('upload_failed'))),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    final primary = _primaryController.text.trim();
    if (!_isValidHex(primary)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L.tr('invalid_primary_color_hex'))),
      );
      return;
    }

    final accent = _accentController.text.trim();
    if (accent.isNotEmpty && !_isValidHex(accent)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L.tr('invalid_accent_color_hex'))),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final repo = ref.read(_brandingRepoProvider);
      await repo.saveBranding(
        primaryColor: primary,
        accentColor: accent.isNotEmpty ? accent : null,
        logoUrl: _logoUrl,
      );
      ref.invalidate(myBrandingProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L.tr('branding_saved'))),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L.tr('save_failed'))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final brandingAsync = ref.watch(myBrandingProvider);

    // Populate fields from existing branding (once)
    if (!_loaded) {
      brandingAsync.whenData((branding) {
        if (branding != null && !_loaded) {
          _loaded = true;
          _primaryController.text = branding.primaryColor;
          _accentController.text = branding.accentColor ?? '';
          _logoUrl = branding.logoUrl;
        } else if (!_loaded) {
          _loaded = true;
        }
      });
    }

    final primaryColor = _isValidHex(_primaryController.text)
        ? _parseHex(_primaryController.text)
        : const Color(0xFF6366F1);
    final accentText = _accentController.text.trim();
    final accentColor = accentText.isNotEmpty && _isValidHex(accentText)
        ? _parseHex(accentText)
        : primaryColor;

    return Scaffold(
      appBar: AppBar(
        title: Text(L.tr('event_branding')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Colors section
          Text(
            L.tr('colors'),
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),

          // Primary color
          _ColorField(
            label: 'Primary',
            controller: _primaryController,
            color: primaryColor,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 12),

          // Accent color
          _ColorField(
            label: 'Accent',
            controller: _accentController,
            color: accentColor,
            onChanged: () => setState(() {}),
            hint: 'Optional (defaults to primary)',
          ),
          const SizedBox(height: 12),

          // Preset swatches
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _presetColors.map((hex) {
              final color = _parseHex(hex);
              final isSelected = _primaryController.text.toUpperCase() ==
                  hex.toUpperCase();
              return GestureDetector(
                onTap: () {
                  _primaryController.text = hex;
                  setState(() {});
                },
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? colorScheme.onSurface
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? Icon(Icons.check, size: 18, color: _contrastColor(color))
                      : null,
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 24),

          // Preview
          Text(
            L.tr('preview'),
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 60,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                colors: [primaryColor, accentColor],
              ),
            ),
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_logoUrl != null) ...[
                    CircleAvatar(
                      radius: 18,
                      backgroundImage: NetworkImage(_logoUrl!),
                      backgroundColor: Colors.white24,
                    ),
                    const SizedBox(width: 12),
                  ],
                  Text(
                    L.tr('your_event'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: _contrastColor(primaryColor),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Logo section
          Text(
            L.tr('logo'),
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),

          if (_logoUrl != null) ...[
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 48,
                    backgroundImage: NetworkImage(_logoUrl!),
                    backgroundColor: colorScheme.surfaceContainerHighest,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onTap: () => setState(() => _logoUrl = null),
                      child: CircleAvatar(
                        radius: 14,
                        backgroundColor: colorScheme.error,
                        child: Icon(Icons.close, size: 14, color: colorScheme.onError),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          OutlinedButton.icon(
            onPressed: _uploading ? null : _pickLogo,
            icon: _uploading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload),
            label: Text(_logoUrl != null ? L.tr('change_logo') : L.tr('upload_logo')),
          ),
          const SizedBox(height: 4),
          Text(
            L.tr('square_recommended_max_512'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 32),

          // Save button
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(L.tr('save_changes')),
          ),
        ],
      ),
    );
  }

  Color _contrastColor(Color color) {
    final luminance = color.computeLuminance();
    return luminance > 0.5 ? Colors.black : Colors.white;
  }
}

class _ColorField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final Color color;
  final VoidCallback onChanged;
  final String? hint;

  const _ColorField({
    required this.label,
    required this.controller,
    required this.color,
    required this.onChanged,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
          ),
        ),
        Expanded(
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: hint ?? '#6366F1',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: (_) => onChanged(),
          ),
        ),
      ],
    );
  }
}
