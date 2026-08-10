class OlympusMemoryCache {
  OlympusMemoryCache._();

  static const int _maxEntries = 48;
  static final Map<String, _OlympusCacheEntry> _entries = {};

  static T? read<T>(
    String key, {
    Duration maxAge = const Duration(minutes: 2),
  }) {
    final entry = _entries[key];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.savedAt) > maxAge) {
      _entries.remove(key);
      return null;
    }
    final value = entry.value;
    if (value is! T) return null;

    // Mantém os itens acessados recentemente no fim do mapa. Assim, quando
    // o limite é atingido, somente o cache mais antigo é descartado.
    _entries.remove(key);
    _entries[key] = entry;
    return value;
  }

  static void write<T>(String key, T value) {
    _entries.remove(key);
    while (_entries.length >= _maxEntries && _entries.isNotEmpty) {
      _entries.remove(_entries.keys.first);
    }
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
