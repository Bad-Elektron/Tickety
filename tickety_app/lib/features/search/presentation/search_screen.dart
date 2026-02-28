import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/utils/utils.dart';
import '../../events/models/event_model.dart';
import '../../events/presentation/event_details_screen.dart';
import '../data/event_search_repository.dart';

/// Screen for searching events.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  final _repository = SupabaseEventSearchRepository();

  List<EventModel> _results = [];
  List<EventModel> _trending = [];
  List<String> _recentSearches = [];
  EventModel? _inviteCodeResult;
  bool _isLoading = false;
  bool _hasSearched = false;
  Timer? _debounce;
  int _searchVersion = 0;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    final trending = await _repository.getTrending();
    final recent = await _repository.getRecentSearches();
    if (mounted) {
      setState(() {
        _trending = trending;
        _recentSearches = recent;
      });
    }
  }

  void _performSearch(String query) {
    _debounce?.cancel();

    final sanitizedQuery = Validators.sanitize(query);

    if (sanitizedQuery.isEmpty) {
      setState(() {
        _results = [];
        _inviteCodeResult = null;
        _hasSearched = false;
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);

    _debounce = Timer(const Duration(milliseconds: 300), () {
      _executeSearch(sanitizedQuery);
    });
  }

  Future<void> _executeSearch(String query) async {
    final version = ++_searchVersion;
    debugPrint('[Search] Executing search v$version: "$query"');

    // Run normal search and invite code lookup in parallel
    final futures = await Future.wait([
      _repository.search(query),
      _repository.searchByInviteCode(query),
    ]);
    await _repository.saveSearch(query);

    final results = futures[0] as List<EventModel>;
    final inviteResult = futures[1] as EventModel?;
    debugPrint('[Search] v$version results: ${results.length} events, invite=${inviteResult?.title}');

    // Only update state if this is still the latest search
    if (mounted && version == _searchVersion) {
      setState(() {
        _results = results;
        _inviteCodeResult = inviteResult;
        _isLoading = false;
        _hasSearched = true;
      });
    } else {
      debugPrint('[Search] v$version discarded (current=$_searchVersion)');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: _SearchBar(
          controller: _searchController,
          focusNode: _focusNode,
          onChanged: _performSearch,
          onSubmitted: (query) {
            _debounce?.cancel();
            final sanitized = Validators.sanitize(query);
            if (sanitized.isNotEmpty) {
              setState(() => _isLoading = true);
              _executeSearch(sanitized);
            }
          },
        ),
        actions: [
          if (_searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _searchController.clear();
                _performSearch('');
              },
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _hasSearched
              ? _buildSearchResults()
              : _buildInitialContent(),
    );
  }

  Widget _buildInitialContent() {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Recent searches
          if (_recentSearches.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Searches',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() => _recentSearches = []);
                  },
                  child: const Text('Clear'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _recentSearches.map((search) {
                return _SearchChip(
                  label: search,
                  onTap: () {
                    _searchController.text = search;
                    _performSearch(search);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 32),
          ],
          // Trending events
          Text(
            'Trending Events',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          ..._trending.map((event) => _EventSearchTile(
                event: event,
                onTap: () => _navigateToEvent(event),
              )),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_results.isEmpty && _inviteCodeResult == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.search_off,
                size: 64,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 16),
              Text(
                'No events found',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Try a different search term',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _results.length + (_inviteCodeResult != null ? 1 : 0),
      itemBuilder: (context, index) {
        // Show invite code result card at the top
        if (_inviteCodeResult != null && index == 0) {
          return _InviteCodeResultCard(
            event: _inviteCodeResult!,
            onTap: () => _navigateToEvent(_inviteCodeResult!),
          );
        }
        final eventIndex = _inviteCodeResult != null ? index - 1 : index;
        final event = _results[eventIndex];
        return _EventSearchTile(
          event: event,
          onTap: () => _navigateToEvent(event),
        );
      },
    );
  }

  void _navigateToEvent(EventModel event) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EventDetailsScreen(event: event),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search events...',
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        prefixIcon: Icon(
          Icons.search,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _SearchChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SearchChip({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.history,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventSearchTile extends StatelessWidget {
  final EventModel event;
  final VoidCallback onTap;

  const _EventSearchTile({
    required this.event,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final config = event.getNoiseConfig();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              // Thumbnail
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: config.colors,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (event.category != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              event.category!,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            event.getDisplayLocation(hasTicket: false) ?? '',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Price
              Text(
                event.formattedPrice,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: event.isFree ? Colors.green : colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InviteCodeResultCard extends StatelessWidget {
  final EventModel event;
  final VoidCallback onTap;

  const _InviteCodeResultCard({
    required this.event,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final config = event.getNoiseConfig();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Material(
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.3),
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                // Gradient header
                Container(
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: config.colors,
                    ),
                  ),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.lock_outline,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Private Event Found',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Event info
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              event.title,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              event.subtitle,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
