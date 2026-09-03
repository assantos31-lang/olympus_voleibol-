typedef EventRowsPageFetcher = Future<List<Map<String, dynamic>>> Function(
  List<String> eventIds,
  int from,
  int to,
);

Future<List<Map<String, dynamic>>> fetchAllEventRows({
  required List<String> eventIds,
  required EventRowsPageFetcher fetchPage,
  int batchSize = 100,
  int pageSize = 1000,
}) async {
  if (eventIds.isEmpty) return <Map<String, dynamic>>[];
  if (batchSize <= 0 || pageSize <= 0) {
    throw ArgumentError('batchSize e pageSize devem ser maiores que zero.');
  }

  final rows = <Map<String, dynamic>>[];
  for (var start = 0; start < eventIds.length; start += batchSize) {
    final end = (start + batchSize < eventIds.length)
        ? start + batchSize
        : eventIds.length;
    final batch = eventIds.sublist(start, end);
    var offset = 0;

    while (true) {
      final page = await fetchPage(
        batch,
        offset,
        offset + pageSize - 1,
      );
      rows.addAll(page);
      if (page.length < pageSize) break;
      offset += pageSize;
    }
  }
  return rows;
}
