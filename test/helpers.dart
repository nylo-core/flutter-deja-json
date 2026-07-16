/// Deep structural equality for decoded JSON data.
bool deepEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    final bKeys = b.keys.toList();
    var i = 0;
    for (final key in a.keys) {
      // Key order matters: DejaJson guarantees it survives the round trip.
      if (key != bKeys[i++]) return false;
      if (!deepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

/// A payload large and repetitive enough for every mode to engage.
List<Map<String, Object?>> users([int count = 50]) => [
      for (var i = 1; i <= count; i++)
        {
          'id': i,
          'name': 'User $i',
          'email': 'user$i@example.com',
          'email_verified_at':
              i % 3 == 0 ? null : '2026-01-0${i % 9 + 1}T10:00:00Z',
          'active': i % 2 == 0,
          'balance': i * 3.25,
          'address': {
            'line1': '$i Sample Street',
            'city': 'London',
            'country': 'GB',
          },
        },
    ];
