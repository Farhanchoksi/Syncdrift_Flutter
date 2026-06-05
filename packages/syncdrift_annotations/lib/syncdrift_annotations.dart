/// Annotations for the syncdrift_flutter database framework.
library syncdrift_annotations;

/// Annotate a Drift Table class with `@Repository()` to trigger code generation
/// of a dedicated Repository class.
class Repository {
  const Repository();
}

/// Defines a one-to-many relationship.
/// Place this on a Table class to declare that it "has many" of the [targetTable].
class HasMany {
  /// The target table class of the relationship.
  final Type targetTable;

  /// The foreign key column name in the [targetTable] that references this table.
  final String foreignKey;

  const HasMany(this.targetTable, {required this.foreignKey});
}

/// Defines a many-to-one relationship.
/// Place this on a Table class to declare that it "belongs to" the [targetTable].
class BelongsTo {
  /// The target table class of the relationship.
  final Type targetTable;

  /// The foreign key column name in this table that references [targetTable].
  final String foreignKey;

  const BelongsTo(this.targetTable, {required this.foreignKey});
}

/// Enable smart caching for a table.
class Cached {
  /// Time-to-live in seconds.
  final int ttlSeconds;

  const Cached({required this.ttlSeconds});
}

/// Enable offline-first synchronization for a table.
class SyncTable {
  const SyncTable();
}
