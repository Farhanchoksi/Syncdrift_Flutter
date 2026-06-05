# Changelog

All notable changes to `syncdrift_flutter` will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.1.0] - 2026-06-05

### Added

**Core Framework (`syncdrift_flutter`)**

- Backend-agnostic `DatabaseDriver` abstract interface.
- `DriftDatabaseDriver` — adapts any Drift database to the standard driver interface, with explicit table-update notifications for stream watchers.
- Offset-based pagination returning structured `PaginatedResult<T>`.
- `.obs` RxDart `ValueStream` stream extension wrappers for reactive UI bindings.
- `SyncdriftRepository` base class with CRUD, pagination, and snake_case ↔ camelCase key conversions.

**Smart Caching (SWR)**

- `SyncdriftCacheManager` — in-memory query result cache with TTL eviction and background cleanup jobs.
- `CachedDatabaseDriver` — decorator wrapping any driver, implementing **Stale-While-Revalidate (SWR)**: serves stale cache instantly while revalidating asynchronously.
- Automatic query cache invalidation on inserts, updates, and deletes.
- Dart VM Service extensions (`ext.syncdrift.cache.inspect`, `ext.syncdrift.cache.clear`) for DevTools telemetry.
- Benchmarks showing **10x+ read speedups** compared to raw SQLite queries.

**Auto Offline Outbound Sync**

- `SyncDatabaseDriver` decorator — intercepts mutations on `@SyncTable`-annotated tables and enqueues them transactionally in SQLite (`pending_operations`, `failed_operations`, `sync_metadata`).
- `SyncQueueProcessor` — FIFO queue processor with connectivity-aware auto-drain, exponential backoff retries ($2^{\text{retries}}$ seconds), and terminal failure evictions.
- `SyncAdapter` abstract contract for connecting to any backend.
- `RestSyncAdapter` — maps inserts/updates/deletes to generic REST endpoints; detects terminal 4xx failures.
- `SupabaseSyncAdapter` — maps mutations to the official Supabase Dart Client, mapping `PostgrestException` to terminal failures.
- `SyncDatabaseDriver.runWithoutQueue()` — zone-bound utility to execute mutations bypassing outbound queue (used by realtime ingestion to prevent sync feedback loops).

**Real-time Push Sync**

- `RealtimeAdapter` abstract contract.
- `RealtimeSyncManager` — subscribes to remote change feeds and applies updates locally, running inside `runWithoutQueue` to prevent loops.
- `SupabaseRealtimeAdapter` — listens to PostgreSQL replication changes via Supabase Realtime channels.
- `WebSocketRealtimeAdapter` — ingests push events from any WebSocket feed.

**File & Media Storage Sync**

- `SyncdriftStorageManager` — local filesystem cache (`getFile` serves cache-hits instantly; cache-miss triggers download), offline upload queue (`pending_uploads` / `failed_uploads` SQLite tables), exponential backoff on failures, auto-drain on connectivity recovery.
- `StorageAdapter` abstract contract.
- `RestStorageAdapter` — multipart HTTP file upload/download against a generic REST API.
- `SupabaseStorageAdapter` — reads/writes to Supabase Storage buckets.

**Code Generation (`syncdrift_generator` + `syncdrift_annotations`)**

- Annotations: `@Repository`, `@Cached`, `@SyncTable`, `@HasMany`, `@BelongsTo`.
- `SyncdriftBuilder` generating typed repository classes, relationship loaders/watchers, and Riverpod providers from annotated Drift table classes.
- Generates `syncdriftCacheConfigurations` and `syncdriftSyncTables` static configurations.

**Example App & Test Suite**

- Full-featured demo Flutter app with dark-themed UI, Riverpod overrides, paginated views, and live relationship updates.
- 35 integration tests covering: CRUD lifecycle, pagination, stream subscriptions, cache SWR/invalidation/cleanup, sync FIFO ordering/retries/terminal evictions, real-time loop-prevention, and storage offline queue/backoff scenarios.
