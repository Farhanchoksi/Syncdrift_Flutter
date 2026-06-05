# Changelog — syncdrift_annotations

All notable changes to this package are documented here.
See the [root CHANGELOG](https://github.com/Farhanchoksi/Syncdrift_Flutter/blob/main/CHANGELOG.md) for the full framework release history.

## [0.1.1] - 2026-06-05

### Changed
- Minor updates.

## [0.1.0] - 2026-06-05

### Added
- `@Repository()` — marks a Drift table for repository class generation
- `@Cached(ttlSeconds: n)` — enables SWR query caching with configurable TTL
- `@SyncTable()` — marks a table for offline outbound sync queue interception
- `@HasMany(T, foreignKey)` — declares a one-to-many relationship
- `@BelongsTo(T, foreignKey)` — declares a many-to-one relationship
