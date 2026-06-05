# Changelog — syncdrift_flutter

All notable changes to this package are documented here.
See the [root CHANGELOG](https://github.com/Farhanchoksi/Syncdrift_Flutter/blob/main/CHANGELOG.md) for the complete release history.

## [0.1.0] - 2026-06-05

### Added

- **Core:** `DatabaseDriver` abstract interface, `DriftDatabaseDriver`, `SyncdriftRepository` base class, `PaginatedResult<T>`, `.obs` RxDart stream extensions, Riverpod `syncdriftDriverProvider`
- **SWR Caching:** `CachedDatabaseDriver`, `SyncdriftCacheManager` with TTL eviction, background SWR revalidation, table-level cache invalidation on mutations, DevTools VM Service extensions
- **Offline Sync:** `SyncDatabaseDriver` queue interceptor, `SyncQueueProcessor` with connectivity-aware auto-drain and exponential backoff, `SyncAdapter` contract, `RestSyncAdapter`, `SupabaseSyncAdapter`, `TerminalSyncException`
- **Real-time Push:** `RealtimeSyncManager`, `RealtimeAdapter` contract, `SupabaseRealtimeAdapter`, `WebSocketRealtimeAdapter`, zone-bound loop prevention via `SyncDatabaseDriver.runWithoutQueue()`
- **File Storage:** `SyncdriftStorageManager`, `StorageAdapter` contract, `RestStorageAdapter`, `SupabaseStorageAdapter`, offline upload queue with exponential backoff retries
