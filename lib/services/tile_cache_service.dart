import 'package:flutter_map/flutter_map.dart';
import 'package:path_provider/path_provider.dart';

/// Configures flutter_map's built-in on-disk tile cache for offline-first use.
///
/// flutter_map 8.x ships a [BuiltInMapCachingProvider] that is used
/// automatically by [NetworkTileProvider]. Its defaults are not offline-first,
/// though:
///
///  * it stores tiles in a platform *cache* directory the OS may wipe at any
///    time, and
///  * it treats tiles as "fresh" only for the age advertised in the tile
///    server's HTTP headers — once a tile goes stale, the image provider always
///    hits the network to revalidate, and when offline that revalidation fails
///    and a *blank* tile is shown instead of the cached one.
///
/// We fix both by pinning the cache to the app's persistent support directory
/// and forcing a long freshness window, so once an area has been seen it keeps
/// rendering from disk with no network at all.
class TileCacheService {
  TileCacheService._();

  /// Consider a cached tile fresh for this long. Basemap tiles change rarely,
  /// and for a riding app availability offline matters far more than catching
  /// the occasional cartography update — so we serve straight from disk within
  /// this window and never touch the network.
  static const Duration _freshFor = Duration(days: 60);

  /// Cap the on-disk cache. Dark basemap tiles are small (~10-30 KB); 512 MB
  /// holds a very large amount of covered ground.
  static const int _maxCacheBytes = 512 * 1024 * 1024;

  static bool _configured = false;

  /// Initialise the singleton cache. Safe to call more than once — the first
  /// call wins (the provider is a process-wide singleton), later calls no-op.
  ///
  /// Call this during startup, before the map first builds, so the configured
  /// singleton is the one [NetworkTileProvider] picks up.
  static Future<void> configure() async {
    if (_configured) return;

    // Application support dir is app-private and not the OS-clearable cache dir,
    // so tiles survive between rides.
    final dir = await getApplicationSupportDirectory();

    BuiltInMapCachingProvider.getOrCreateInstance(
      cacheDirectory: '${dir.path}/tile_cache',
      maxCacheSize: _maxCacheBytes,
      overrideFreshAge: _freshFor,
    );
    _configured = true;
  }
}
