# Changelog — syncdrift_generator

All notable changes to this package are documented here.
See the [root CHANGELOG](https://github.com/Farhanchoksi/Syncdrift_Flutter/blob/main/CHANGELOG.md) for the full framework release history.

## [0.1.0] - 2026-06-05

### Added
- `SyncdriftBuilder` — scans annotated Drift table classes and generates:
  - Typed repository classes (`UserRepository`, `PostRepository`, etc.)
  - Relationship loaders and watchers (`loadPosts()`, `watchPosts()`)
  - `syncdriftCacheConfigurations` — TTL map for `CachedDatabaseDriver`
  - `syncdriftSyncTables` — table name set for `SyncDatabaseDriver`
  - `syncdriftDriverProvider` — Riverpod `Provider<DatabaseDriver>`
  - Per-table Riverpod providers (`userRepositoryProvider`, etc.)
