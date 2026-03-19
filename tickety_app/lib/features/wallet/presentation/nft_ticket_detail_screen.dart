import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/localization/localization.dart';
import '../models/nft_ticket.dart';

/// Detail screen for a CIP-68 NFT ticket.
class NftTicketDetailScreen extends StatelessWidget {
  final NftTicket nft;

  const NftTicketDetailScreen({super.key, required this.nft});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(L.tr('nft_ticket_title')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // NFT Badge + Name
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    colorScheme.primary,
                    colorScheme.primary.withValues(alpha: 0.7),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.token_rounded,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    nft.displayName,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (nft.eventTitle != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      nft.eventTitle!,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.verified, color: Colors.white, size: 16),
                        SizedBox(width: 6),
                        Text(
                          'CIP-68 NFT',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Event details (if available)
            if (nft.eventTitle != null ||
                nft.ticketNumber != null ||
                nft.eventDate != null ||
                nft.venue != null)
              _Section(
                title: L.tr('nft_ticket_event_details'),
                children: [
                  if (nft.ticketNumber != null)
                    _DetailRow(label: L.tr('nft_ticket_ticket'), value: nft.ticketNumber!),
                  if (nft.eventDate != null)
                    _DetailRow(label: L.tr('nft_ticket_date'), value: nft.eventDate!),
                  if (nft.venue != null)
                    _DetailRow(label: L.tr('nft_ticket_venue'), value: nft.venue!),
                ],
              ),

            const SizedBox(height: 16),

            // On-chain details
            _Section(
              title: L.tr('nft_ticket_onchain_details'),
              children: [
                _CopyableRow(
                  label: L.tr('nft_ticket_policy_id'),
                  value: nft.policyId,
                ),
                _CopyableRow(
                  label: L.tr('nft_ticket_asset_name'),
                  value: nft.assetName,
                ),
                if (nft.initialMintTxHash != null)
                  _CopyableRow(
                    label: L.tr('nft_ticket_mint_tx'),
                    value: nft.initialMintTxHash!,
                  ),
              ],
            ),

            const SizedBox(height: 24),

            // Action buttons
            FilledButton.icon(
              onPressed: () => _openUrl(nft.cardanoScanUrl),
              icon: const Icon(Icons.open_in_new),
              label: Text(L.tr('wallet_view_on_cardanoscan')),
            ),
            if (nft.mintTxUrl != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _openUrl(nft.mintTxUrl!),
                icon: const Icon(Icons.receipt_long),
                label: Text(L.tr('nft_ticket_view_mint_tx')),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _CopyableRow extends StatelessWidget {
  final String label;
  final String value;

  const _CopyableRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final truncated = value.length > 24
        ? '${value.substring(0, 12)}...${value.substring(value.length - 12)}'
        : value;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              truncated,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$label copied'),
                  duration: const Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: Icon(
              Icons.copy_rounded,
              size: 16,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
