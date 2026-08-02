class OlympusMemoryCache {
  OlympusMemoryCache._();

  static final Map<String, _OlympusCacheEntry> _entries = {};

  static T? read<T>(String key,
      {Duration maxAge = const Duration(minutes: 2)}) {
    final entry = _entries[key];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.savedAt) > maxAge) {
      _entries.remove(key);
      return null;
    }
    final value = entry.value;
    return value is T ? value : null;
  }

  static void write<T>(String key, T value) {
    _entries[key] = _OlympusCacheEntry(value, DateTime.now());
  }

  static void remove(String key) => _entries.remove(key);

  static void clear() => _entries.clear();
}

class _OlympusCacheEntry {
  const _OlympusCacheEntry(this.value, this.savedAt);

  final Object? value;
  final DateTime savedAt;
}
