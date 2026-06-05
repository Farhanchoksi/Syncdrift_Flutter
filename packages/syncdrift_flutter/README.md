<p align="center">
  <img src="https://img.shields.io/pub/v/syncdrift_flutter.svg?label=syncdrift_flutter&color=blue" alt="pub version"/>
  <img src="https://img.shields.io/pub/v/syncdrift_generator.svg?label=syncdrift_generator&color=blue" alt="pub version"/>
  <img src="https://img.shields.io/badge/Dart-%3E%3D3.0.0-0175C2?logo=dart" alt="Dart SDK"/>
  <img src="https://img.shields.io/badge/Flutter-%3E%3D3.0.0-02569B?logo=flutter" alt="Flutter"/>
  <img src="https://img.shields.io/badge/License-MIT-green.svg" alt="MIT License"/>
  <img src="https://img.shields.io/badge/PRs-welcome-brightgreen.svg" alt="PRs Welcome"/>
</p>

<h1 align="center">SyncDrift Flutter</h1>

<p align="center">
  <strong>Production-grade offline-first reactive database framework for Flutter, built on <a href="https://drift.simonbinder.eu/">Drift</a>.</strong><br/>
  One package. Zero compromise. Full offline–online parity.
</p>

---

SyncDrift is an opinionated, decorator-based persistence layer that wraps Drift/SQLite with:

- **Stale-While-Revalidate (SWR) caching** — sub-millisecond reads, background refresh
- **Transactional offline queue** — writes survive network loss, sync when back online
- **Real-time inbound push** — Supabase Realtime / WebSocket changes applied locally with loop-prevention
- **File/media storage** — local cache + offline upload queue with exponential backoff
- **Code generation** — type-safe repositories, relationship loaders, and Riverpod providers from annotated Drift tables

All in **one `import`**. No separate sub-packages to juggle.

---

## Table of Contents

- [Platform Support](#platform-support)
- [Packages](#packages)
- [Installation](#installation)
- [Architecture](#architecture)
- [Quick Start](#quick-start)
  - [1. Annotate Your Tables](#1-annotate-your-tables)
  - [2. Run Code Generation](#2-run-code-generation)
  - [3. Wire Up in `main.dart`](#3-wire-up-in-maindart)
  - [4. Use in Widgets](#4-use-in-widgets)
- [Feature Deep Dive](#feature-deep-dive)
  - [SWR Caching](#swr-caching)
  - [Offline Outbound Sync](#offline-outbound-sync)
  - [Real-time Push Sync](#real-time-push-sync)
  - [Media & File Storage](#media--file-storage)
- [API Reference](#api-reference)
- [Configuration](#configuration)
- [Versioning](#versioning)
- [Contributing](#contributing)
- [Security](#security)
- [License](#license)

---

## Platform Support

| Platform | Status |
|---|---|
| Android | ✅ Supported |
| iOS | ✅ Supported |
| macOS | ✅ Supported |
| Linux | ✅ Supported |
| Windows | ✅ Supported |
| Web | ⚠️ SQLite via WASM (no `sqlite3_flutter_libs`) |

---

## Packages

This repository is a [Melos](https://melos.invertase.dev/)-managed monorepo. End-users only need the two packages below:

| Package | Version | Description |
|---|---|---|
| [`syncdrift_flutter`](./packages/syncdrift_flutter) | `^0.1.0` | Core runtime: caching, sync, realtime, storage |
| [`syncdrift_generator`](./packages/syncdrift_generator) | `^0.1.0` | Build-time code generator (dev dependency) |
| [`syncdrift_annotations`](./packages/syncdrift_annotations) | transitive | Annotations consumed by the generator (auto-resolved) |

---

## Installation

Add the following to your app's `pubspec.yaml`:

```yaml
dependencies:
  syncdrift_flutter: ^0.1.0

dev_dependencies:
  build_runner: ^2.4.9
  drift_dev: ^2.20.0
  syncdrift_generator: ^0.1.0
```

Then run:

```bash
flutter pub get
```

> **Note:** `syncdrift_annotations` is a transitive dependency of `syncdrift_flutter` and does **not** need to be added manually.

---

## Architecture

SyncDrift uses a **decorator chain** pattern. Each driver layer wraps the one below it, adding behaviour without modifying the core SQLite layer:

```
┌──────────────────────────────────────────────────────────┐
│               Your Flutter UI / Riverpod Widgets          │
└───────────────────────┬──────────────────────────────────┘
                        │ reads & writes via generated repos
            ┌───────────▼───────────┐
            │  CachedDatabaseDriver │  ← SWR cache, instant reads, TTL eviction
            └───────────┬───────────┘
            ┌───────────▼───────────┐
            │   SyncDatabaseDriver  │  ← intercepts writes → SQLite FIFO queue
            └───────────┬───────────┘
            ┌───────────▼───────────┐
            │  DriftDatabaseDriver  │  ← raw SQLite via Drift
            └───────────────────────┘
               │ outbound                  │ inbound
               ▼                          ▼
    SyncQueueProcessor            RealtimeSyncManager
    ├── RestSyncAdapter           ├── SupabaseRealtimeAdapter
    └── SupabaseSyncAdapter       └── WebSocketRealtimeAdapter
               │                          │
               ▼                          ▼
          Remote API                 Remote API
                          ▲
              SyncdriftStorageManager
              ├── RestStorageAdapter
              └── SupabaseStorageAdapter
```

**Key design principle:** The `runWithoutQueue()` zone ensures real-time inbound writes are applied locally *without* re-triggering the outbound sync queue — preventing infinite feedback loops.

---

## Quick Start

### 1. Annotate Your Tables

Use SyncDrift's annotations on your existing Drift table definitions:

```dart
import 'package:drift/drift.dart';
import 'package:syncdrift_flutter/syncdrift_flutter.dart';

@Repository()
@Cached(ttlSeconds: 60)        // Enable SWR caching with 60-second TTL
@SyncTable()                   // Intercept writes for remote sync
@HasMany(Posts, foreignKey: 'userId')
class Users extends Table {
  IntColumn get id   => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get email => text().withLength(max: 255)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@Repository()
@Cached(ttlSeconds: 30)
@SyncTable()
@BelongsTo(Users, foreignKey: 'userId')
class Posts extends Table {
  IntColumn get id      => integer().autoIncrement()();
  IntColumn get userId  => integer().references(Users, #id)();
  TextColumn get title  => text().withLength(max: 200)();
  TextColumn get body   => text()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
}
```

### 2. Run Code Generation

```bash
dart run build_runner build --delete-conflicting-outputs
```

This emits `database.syncdrift.dart` alongside your Drift-generated file, providing:

| Generated Symbol | Type | Description |
|---|---|---|
| `UserRepository` | `class` | Full CRUD + pagination + reactive `watchAll()` / `watchOne()` |
| `PostRepository` | `class` | Includes `loadUsers()` relationship loader |
| `syncdriftCacheConfigurations` | `Map<String, Duration>` | TTL map passed to `CachedDatabaseDriver` |
| `syncdriftSyncTables` | `Set<String>` | Table names passed to `SyncDatabaseDriver` |
| `syncdriftDriverProvider` | `Provider<DatabaseDriver>` | Riverpod provider for DI |
| `userRepositoryProvider` | `Provider<UserRepository>` | Auto-generated per-table provider |

**Watch mode** (during development):

```bash
dart run build_runner watch --delete-conflicting-outputs
```

### 3. Wire Up in `main.dart`

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/native.dart';
import 'package:syncdrift_flutter/syncdrift_flutter.dart';
import 'database.dart';
import 'database.syncdrift.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ─── Layer 1: Core SQLite via Drift ──────────────────────────────────────
  final db        = AppDatabase(NativeDatabase.createInBackground(File('app.db')));
  final rawDriver = DriftDatabaseDriver(db);

  // ─── Layer 2: Outbound sync (REST or Supabase) ───────────────────────────
  final syncAdapter = SupabaseSyncAdapter(supabase: Supabase.instance.client);
  final syncDriver  = SyncDatabaseDriver(
    delegate:   rawDriver,
    syncAdapter: syncAdapter,
    syncTables:  syncdriftSyncTables,   // generated
  );
  await syncDriver.init();              // creates pending_operations tables

  // ─── Layer 3: SWR caching ────────────────────────────────────────────────
  final cachedDriver = CachedDatabaseDriver(
    delegate:         syncDriver,
    cacheManager:     SyncdriftCacheManager(),
    cacheConfigurations: syncdriftCacheConfigurations,  // generated
  );

  // ─── Inbound: Real-time push sync ────────────────────────────────────────
  final realtimeManager = RealtimeSyncManager(
    dbDriver: syncDriver,   // writes bypass outbound queue (loop prevention)
    adapters: [
      SupabaseRealtimeAdapter(supabase: Supabase.instance.client),
      // WebSocketRealtimeAdapter(url: 'wss://api.example.com/ws'),
    ],
  );
  await realtimeManager.start();

  // ─── File / media storage sync ───────────────────────────────────────────
  final storageManager = SyncdriftStorageManager(
    dbDriver:       rawDriver,
    storageAdapter: SupabaseStorageAdapter(supabase: Supabase.instance.client),
    maxRetries:     5,
  );
  await storageManager.init();

  // ─── Start background sync processor ─────────────────────────────────────
  final syncProcessor = SyncQueueProcessor(
    dbDriver:    syncDriver,
    syncAdapter: syncAdapter,
  );
  syncProcessor.init();

  runApp(
    ProviderScope(
      overrides: [
        // Inject the fully decorated driver into the Riverpod graph
        syncdriftDriverProvider.overrideWith((ref) => cachedDriver),
      ],
      child: const MyApp(),
    ),
  );
}
```

### 4. Use in Widgets

```dart
// Reading data — reactive, cache-aware
class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userRepo = ref.watch(userRepositoryProvider);

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: userRepo.watchAll(orderBy: 'created_at DESC'),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const CircularProgressIndicator();
        final users = snapshot.requireData;

        return ListView.builder(
          itemCount: users.length,
          itemBuilder: (_, i) => ListTile(
            title:    Text(users[i]['name'] as String),
            subtitle: Text(users[i]['email'] as String),
          ),
        );
      },
    );
  }
}

// Writing data — auto-queued for remote sync when offline
Future<void> createUser(UserRepository repo, String name, String email) async {
  await repo.create({'name': name, 'email': email});
  // ↑ Writes to SQLite instantly. If online → syncs immediately.
  //   If offline → queued in pending_operations, drains on reconnect.
}
```

---

## Feature Deep Dive

### SWR Caching

SyncDrift implements the **Stale-While-Revalidate** caching strategy popularized by HTTP RFC 5861:

1. **Cache hit (fresh):** Returns cached data immediately. No DB round-trip.
2. **Cache hit (stale):** Returns stale data immediately *and* fires a background refresh.
3. **Cache miss:** Fetches from SQLite, populates cache, returns result.

```dart
// TTL configured per-table via @Cached annotation
@Cached(ttlSeconds: 60)  // Queries stale after 60 s
class Users extends Table { ... }

// DevTools inspection at runtime
// Register the VM Service extension and open Flutter DevTools → Extensions
// Dart: ext.syncdrift.cache.inspect  — view all cache entries
// Dart: ext.syncdrift.cache.clear    — flush cache
```

**Benchmark (500 reads on a mid-range device):**

| Mode | Time |
|---|---|
| Raw SQLite | ~350 ms |
| SyncDrift cache hit | ~50 ms |
| Speedup | **~7×** |

Cache is automatically **invalidated** on any insert/update/delete to that table.

---

### Offline Outbound Sync

Any write to a `@SyncTable`-annotated table is intercepted and enqueued atomically in SQLite before hitting the network:

```
INSERT users → SyncDatabaseDriver
  ├── delegate.insert(...)      // write to SQLite ✓
  └── pending_operations.insert // enqueue operation ✓
        └── SyncQueueProcessor (background)
              ├── [online]  → call SyncAdapter.sync() → DELETE from queue
              └── [offline] → wait for connectivity_plus event → retry
```

**Retry strategy:** Exponential backoff — `2^retries` seconds (1 s, 2 s, 4 s, 8 s, …). After `maxRetries`, the operation is moved to `failed_operations` for inspection.

```dart
// Implement your own backend by extending SyncAdapter
class MyApiSyncAdapter implements SyncAdapter {
  @override
  Future<void> sync(String table, String operation, Map<String, dynamic> payload) async {
    // Map to your REST/GraphQL/gRPC calls
  }
}
```

Built-in adapters:

| Adapter | Backend |
|---|---|
| `RestSyncAdapter` | Any HTTP REST API (multipart / JSON) |
| `SupabaseSyncAdapter` | Supabase PostgREST |

---

### Real-time Push Sync

Inbound changes from the server are applied locally *without* re-triggering the outbound queue:

```dart
// Zone-bound loop prevention — the secret sauce
await SyncDatabaseDriver.runWithoutQueue(() async {
  await dbDriver.insert(table, record);  // applied locally only
});
```

Built-in adapters:

| Adapter | Protocol |
|---|---|
| `SupabaseRealtimeAdapter` | PostgreSQL logical replication via Supabase Realtime |
| `WebSocketRealtimeAdapter` | Generic WebSocket push feed |

Custom adapters implement the `RealtimeAdapter` abstract class:

```dart
abstract class RealtimeAdapter {
  Stream<RealtimeEvent> get events;
  Future<void> connect();
  Future<void> disconnect();
}
```

---

### Media & File Storage

```dart
// Fetch file — returns local path instantly if cached, downloads if not
final avatarPath = await storageManager.getFile('avatars', 'user_42.jpg');

// Queue upload — file is copied locally immediately; uploaded when online
await storageManager.queueUpload(
  'avatars',
  'user_42.jpg',
  pickedFile.path,
  contentType: 'image/jpeg',
);

// Manually drain the upload queue
await storageManager.triggerUploadQueue();

// Reset backoff timer (e.g. after user retries manually)
storageManager.resetBackoff();
```

Built-in storage adapters:

| Adapter | Backend |
|---|---|
| `RestStorageAdapter` | Generic multipart HTTP (POST/PUT) |
| `SupabaseStorageAdapter` | Supabase Storage buckets |

---

## API Reference

> Full API documentation is available at [pub.dev/documentation/syncdrift_flutter](https://pub.dev/documentation/syncdrift_flutter/latest/).

### Core Classes

| Class | Description |
|---|---|
| `DatabaseDriver` | Abstract interface implemented by all driver layers |
| `DriftDatabaseDriver` | Adapts any `GeneratedDatabase` to `DatabaseDriver` |
| `CachedDatabaseDriver` | SWR cache decorator |
| `SyncdriftCacheManager` | In-memory TTL cache store |
| `SyncDatabaseDriver` | Outbound queue interceptor decorator |
| `SyncQueueProcessor` | Background queue worker |
| `SyncAdapter` | Abstract sync backend contract |
| `RestSyncAdapter` | HTTP REST sync adapter |
| `SupabaseSyncAdapter` | Supabase sync adapter |
| `RealtimeSyncManager` | Inbound real-time update applier |
| `RealtimeAdapter` | Abstract realtime source contract |
| `SupabaseRealtimeAdapter` | Supabase Realtime adapter |
| `WebSocketRealtimeAdapter` | WebSocket push adapter |
| `SyncdriftStorageManager` | File cache + offline upload queue |
| `StorageAdapter` | Abstract storage backend contract |
| `RestStorageAdapter` | HTTP multipart storage adapter |
| `SupabaseStorageAdapter` | Supabase Storage adapter |
| `SyncdriftRepository` | Base class for all generated repositories |
| `PaginatedResult<T>` | Offset-paginated result with metadata |
| `TerminalSyncException` | Thrown when a sync operation must not be retried |

### Annotations

| Annotation | Target | Description |
|---|---|---|
| `@Repository()` | `Table` | Generate a typed repository class |
| `@Cached(ttlSeconds: n)` | `Table` | Enable SWR caching with TTL |
| `@SyncTable()` | `Table` | Intercept mutations for outbound sync |
| `@HasMany(T, foreignKey)` | `Table` | Declare one-to-many relationship |
| `@BelongsTo(T, foreignKey)` | `Table` | Declare many-to-one relationship |

---

## Configuration

### `SyncdriftCacheManager` options

```dart
SyncdriftCacheManager(
  cleanupInterval: const Duration(minutes: 5),  // default: 5 min
  maxEntries: 500,                               // default: unlimited
)
```

### `SyncQueueProcessor` options

```dart
SyncQueueProcessor(
  dbDriver:    syncDriver,
  syncAdapter: syncAdapter,
  maxRetries:  5,           // default: 5 — after this → failed_operations
  connectivity: Connectivity(),
)
```

### `SyncdriftStorageManager` options

```dart
SyncdriftStorageManager(
  dbDriver:       rawDriver,
  storageAdapter: adapter,
  maxRetries:     5,
  customCacheDir: '/path/to/cache',   // default: getApplicationDocumentsDirectory()
)
```

---

## Versioning

This project follows [Semantic Versioning 2.0.0](https://semver.org/).

| Version | Status |
|---|---|
| `0.x.x` | **Current** — API stabilisation phase. Minor breaking changes possible between `0.x` releases. |
| `1.0.0` | Planned — stable API guarantee, full migration guide provided |

> **Pre-1.0 policy:** While in `0.x`, minor-version bumps (`0.x.0`) may introduce breaking changes. These are always documented in [CHANGELOG.md](./CHANGELOG.md) with a `BREAKING` label and a migration path. Patch bumps (`0.x.y`) are backwards-compatible bug fixes only.

See [CHANGELOG.md](./CHANGELOG.md) for the full release history.

---

## Contributing

Contributions are welcome! Please read the guidelines before opening a PR.

1. **Fork** the repository on GitHub
2. **Clone** your fork locally
3. **Install** [Melos](https://melos.invertase.dev/): `dart pub global activate melos`
4. **Bootstrap** the workspace: `dart run melos bootstrap`
5. **Create a branch**: `git checkout -b feat/your-feature`
6. **Make changes** — ensure all tests pass:
   ```bash
   dart run melos exec -- flutter test
   dart run melos exec -- flutter analyze
   ```
7. **Open a Pull Request** against the `main` branch

### Reporting Issues

Please use [GitHub Issues](https://github.com/Farhanchoksi/Syncdrift_Flutter/issues) and include:
- SyncDrift version (`syncdrift_flutter: x.y.z`)
- Flutter version (`flutter --version`)
- Minimal reproducible example
- Full stack trace if applicable

---

## Security

If you discover a security vulnerability, **do not open a public issue**. Instead, please email the maintainer directly (see GitHub profile) or use [GitHub's private vulnerability reporting](https://github.com/Farhanchoksi/Syncdrift_Flutter/security/advisories/new).

---

## License

SyncDrift Flutter is distributed under the **MIT License**.  
See [`LICENSE`](./LICENSE) for the full text.

---

<p align="center">
  Made with ❤️ by <a href="https://github.com/Farhanchoksi">Farhan Choksi</a>
</p>
