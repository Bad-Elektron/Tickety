import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/services.dart';

/// Screen for organizer identity verification via Stripe Identity.
///
/// Triggered when:
/// - User creates an event with 250+ capacity and isn't verified
/// - User taps "Get Verified" from their profile
class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  bool _isLoading = false;
  String? _error;
  String _status = 'none'; // none, pending, verified, failed

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) return;

    try {
      final response = await Supabase.instance.client
          .from('profiles')
          .select('identity_verification_status')
          .eq('id', userId)
          .single();

      if (mounted) {
        setState(() {
          _status = response['identity_verification_status'] as String? ?? 'none';
        });
      }
    } catch (_) {
      // Column may not exist yet if migration hasn't been applied
      if (mounted) {
        setState(() => _status = 'none');
      }
    }
  }

  Future<void> _startVerification() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'create-identity-verification',
      );

      if (response.status != 200) {
        final error = response.data['error'] as String? ?? 'Verification failed';
        throw Exception(error);
      }

      final data = response.data as Map<String, dynamic>;

      if (data['status'] == 'already_verified') {
        setState(() {
          _status = 'verified';
          _isLoading = false;
        });
        return;
      }

      final url = data['url'] as String?;
      if (url != null) {
        setState(() => _status = 'pending');
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Identity Verification'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 24),
            // Status icon
            _buildStatusIcon(colorScheme),
            const SizedBox(height: 24),
            // Title
            Text(
              _statusTitle,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              _statusSubtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            // Info cards
            if (_status == 'none' || _status == 'failed') ...[
              _InfoTile(
                icon: Icons.shield_outlined,
                title: 'Why verify?',
                description:
                    'Events with 250+ capacity require identity verification '
                    'to protect ticket buyers from fraud.',
              ),
              const SizedBox(height: 12),
              _InfoTile(
                icon: Icons.badge_outlined,
                title: 'What\'s needed?',
                description:
                    'A government-issued photo ID and a selfie. '
                    'Powered by Stripe Identity for secure verification.',
              ),
              const SizedBox(height: 12),
              _InfoTile(
                icon: Icons.speed_outlined,
                title: 'Benefits',
                description:
                    'Verified organizers get a badge on their events, '
                    'faster payouts (2 days vs 14), and instant event approval.',
              ),
              const SizedBox(height: 32),
            ],
            // Error message
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _error!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
            // Action button
            if (_status != 'verified')
              FilledButton.icon(
                onPressed: _isLoading ? null : _startVerification,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.verified_user_outlined),
                label: Text(
                  _status == 'pending'
                      ? 'Continue Verification'
                      : _status == 'failed'
                          ? 'Try Again'
                          : 'Verify with Stripe',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            if (_status == 'pending') ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _isLoading ? null : _loadStatus,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Refresh Status'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon(ColorScheme colorScheme) {
    final (IconData icon, Color color) = switch (_status) {
      'verified' => (Icons.verified, const Color(0xFF4CAF50)),
      'pending' => (Icons.hourglass_top, Colors.amber),
      'failed' => (Icons.error_outline, colorScheme.error),
      _ => (Icons.shield_outlined, colorScheme.primary),
    };

    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 40, color: color),
    );
  }

  String get _statusTitle => switch (_status) {
        'verified' => 'You\'re Verified',
        'pending' => 'Verification Pending',
        'failed' => 'Verification Failed',
        _ => 'Get Verified',
      };

  String get _statusSubtitle => switch (_status) {
        'verified' =>
          'Your identity has been verified. You can create events of any size.',
        'pending' =>
          'Your verification is being reviewed. This usually takes a few minutes.',
        'failed' =>
          'Your verification could not be completed. Please try again with a clear photo of your ID.',
        _ =>
          'Verify your identity to create large events and earn buyer trust.',
      };
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _InfoTile({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: colorScheme.primary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
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
  }
}
