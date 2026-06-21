import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:Kelivo/core/providers/mcp_provider.dart';

/// B-task acceptance: the built-in fetch server's user-visible name was renamed
/// from the legacy `@kelivo/fetch` to `@stillhere/fetch`. Old installs persist
/// the legacy name; on load it must migrate to the new name AND never produce a
/// duplicate built-in entry.
///
/// Drives the real [McpProvider] load path via mocked SharedPreferences so the
/// private migration in `_ensureBuiltinFetchServerPresent` is exercised without
/// widening the public API.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const newName = '@stillhere/fetch';
  const legacyName = '@kelivo/fetch';

  /// Wait until [provider]'s servers settle (the post-load list), then return
  /// only the in-memory (built-in) ones.
  Future<List<dynamic>> builtinServers(McpProvider provider) async {
    // _load() is async and fired in the constructor; give it microtasks/IO to
    // complete. The inmemory entry is the migration target we assert on.
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final inmem = provider.servers
          .where((s) => s.transport == McpTransportType.inmemory)
          .toList();
      if (inmem.isNotEmpty) return inmem;
    }
    return provider.servers
        .where((s) => s.transport == McpTransportType.inmemory)
        .toList();
  }

  test(
    'legacy @kelivo/fetch is migrated to @stillhere/fetch, no duplicate',
    () async {
      SharedPreferences.setMockInitialValues({
        'mcp_servers_v1':
            '[{"id":"kelivo_fetch","enabled":true,"name":"$legacyName","transport":"inmemory","tools":[]}]',
      });

      final provider = McpProvider();
      final inmem = await builtinServers(provider);

      expect(inmem.length, 1, reason: 'must stay a single built-in server');
      expect(
        inmem.single.name,
        newName,
        reason: 'legacy name must be migrated',
      );
      expect(
        inmem.single.id,
        'kelivo_fetch',
        reason: 'id is a stable identifier',
      );

      provider.dispose();
    },
  );

  test(
    'fresh install gets exactly one built-in server with the new name',
    () async {
      SharedPreferences.setMockInitialValues({});

      final provider = McpProvider();
      final inmem = await builtinServers(provider);

      expect(inmem.length, 1);
      expect(inmem.single.name, newName);

      provider.dispose();
    },
  );

  test(
    'a user-renamed inmemory entry is also normalized to the new name',
    () async {
      // Even if an old entry carried some other display name, the single built-in
      // (identified by inmemory transport) must end up on the current name and
      // never duplicate.
      SharedPreferences.setMockInitialValues({
        'mcp_servers_v1':
            '[{"id":"kelivo_fetch","enabled":true,"name":"old custom name","transport":"inmemory","tools":[]}]',
      });

      final provider = McpProvider();
      final inmem = await builtinServers(provider);

      expect(inmem.length, 1);
      expect(inmem.single.name, newName);

      provider.dispose();
    },
  );
}
