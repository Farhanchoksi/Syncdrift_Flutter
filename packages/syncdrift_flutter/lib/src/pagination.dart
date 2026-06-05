import 'driver.dart';

/// Represents a single page of results fetched from the database.
class PaginatedResult<T> {
  /// The list of items on the current page.
  final List<T> items;

  /// The total number of items matching the query.
  final int totalCount;

  /// The current page number (1-based).
  final int page;

  /// The number of items per page.
  final int pageSize;

  /// Returns true if there is a next page of items.
  bool get hasNextPage => (page * pageSize) < totalCount;

  /// Returns true if there is a previous page of items.
  bool get hasPreviousPage => page > 1;

  const PaginatedResult({
    required this.items,
    required this.totalCount,
    required this.page,
    required this.pageSize,
  });

  /// Maps the paginated results of type [T] to type [R].
  PaginatedResult<R> map<R>(R Function(T item) mapper) {
    return PaginatedResult<R>(
      items: items.map(mapper).toList(),
      totalCount: totalCount,
      page: page,
      pageSize: pageSize,
    );
  }

  /// Converts this paginated result to JSON format.
  Map<String, dynamic> toJson(Object? Function(T) toJsonT) => {
        'items': items.map(toJsonT).toList(),
        'totalCount': totalCount,
        'page': page,
        'pageSize': pageSize,
      };
}

/// Extension on [DatabaseDriver] to support high-performance SQL pagination.
extension DriverPagination on DatabaseDriver {
  /// Query a page of records from [table].
  Future<PaginatedResult<Map<String, dynamic>>> paginate(
    String table, {
    required int page,
    required int pageSize,
    List<String>? columns,
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
  }) async {
    final offset = (page - 1) * pageSize;

    // Fetch the total count using COUNT(*)
    final countResult = await select(
      table,
      columns: ['COUNT(*) as total_count'],
      where: where,
      whereArgs: whereArgs,
    );

    final totalCount =
        (countResult.firstOrNull?['total_count'] as num?)?.toInt() ?? 0;

    // Fetch the items for the current page
    final items = await select(
      table,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: pageSize,
      offset: offset,
    );

    return PaginatedResult(
      items: items,
      totalCount: totalCount,
      page: page,
      pageSize: pageSize,
    );
  }
}
