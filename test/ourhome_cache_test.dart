import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/ourhome/ourhome_cache.dart';

void main() {
  group('OurHomeCache in-memory behavior', () {
    // put() updates the in-memory index synchronously (independent of disk),
    // so peek() can serve a room's last-seen content instantly. The on-disk
    // persistence (init/file writes) needs path_provider and is covered by the
    // app at runtime, not here.

    test('put then peek returns the cached body (happy path)', () {
      const path = '/api/home/board';
      const body = '[{"id":1,"text":"hi"}]';
      OurHomeCache.put(path, body);
      expect(OurHomeCache.peek(path), body);
    });

    test('peek returns null for an unknown path (boundary)', () {
      expect(OurHomeCache.peek('/api/home/never_fetched'), isNull);
    });

    test('oversized bodies are rejected to keep the cache lean (boundary)', () {
      const path = '/api/home/huge';
      final tooBig = 'a' * 600001;
      OurHomeCache.put(path, tooBig);
      expect(OurHomeCache.peek(path), isNull);
    });

    test('a later put overwrites the previous body (state transition)', () {
      const path = '/api/home/diary';
      OurHomeCache.put(path, '[1]');
      OurHomeCache.put(path, '[1,2]');
      expect(OurHomeCache.peek(path), '[1,2]');
    });
  });
}
