/// A wrapper for paginated data results.
///
/// Generic class that wraps a list of items with pagination metadata.
class PaginatedResult<T> {
  /// The items for the current page.
  final List<T> items;

  /// Current page number (0-indexed).
  final int page;

  /// Number of items per page.
  final int pageSize;

  /// Whether there are more pages available.
  final bool hasMore;

  const PaginatedResult({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.hasMore,
  });

  /// Creates an empty result.
  const PaginatedResult.empty({
    this.page = 0,
    this.pageSize = 20,
  })  : items = const [],
        hasMore = false;

  /// Whether this is the first page.
  bool get isFirstPage => page == 0;

  /// Whether this page has any items.
  bool get isEmpty => items.isEmpty;

  /// Whether this page has items.
  bool get isNotEmpty => items.isNotEmpty;

  /// Number of items in this page.
  int get length => items.length;

  /// Creates a copy with modified values.
  PaginatedResult<T> copyWith({
    List<T>? items,
    int? page,
    int? pageSize,
    bool? hasMore,
  }) {
    return PaginatedResult<T>(
      items: items ?? this.items,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      hasMore: hasMore ?? this.hasMore,
    );
  }

  @override
  String toString() {
    return 'PaginatedResult(page: $page, pageSize: $pageSize, '
        'items: ${items.length}, hasMore: $hasMore)';
  }
}
