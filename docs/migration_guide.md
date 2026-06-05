# Migration Guide: Drift to Syncdrift

This guide describes how to migrate an existing Flutter application using **Drift** directly to use the **Syncdrift** repository patterns.

---

## 1. Setup Annotations on Tables

In a standard Drift project, you write table definitions like:

```dart
class Users extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
}
```

To migrate to Syncdrift:
1. Import `package:syncdrift_flutter/syncdrift_flutter.dart`.
2. Add `@Repository()` to your tables to generate CRUD repositories.
3. Replace manually coded relationship joins with `@HasMany()` and `@BelongsTo()` annotations.

```dart
import 'package:syncdrift_flutter/syncdrift_flutter.dart';

@Repository()
@HasMany(Posts, foreignKey: 'userId')
class Users extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
}
```

---

## 2. Refactor Database Code Generation

Ensure your `pubspec.yaml` contains `syncdrift_generator` as a dev dependency. 

Run the builder to create the combined files:

```bash
dart run build_runner build --delete-conflicting-outputs
```

This will output `database.syncdrift.dart` alongside `database.g.dart`.

---

## 3. Replace Direct Database Queries with Repositories

### Select All
**Before (Drift):**
```dart
final users = await db.select(db.users).get();
```

**After (Syncdrift):**
```dart
final users = await userRepo.selectAll();
```

### Watch Updates
**Before (Drift):**
```dart
final userStream = db.select(db.users).watch();
```

**After (Syncdrift):**
```dart
final userStream = userRepo.watchAll();
```
*(You can chain `.obs` to get a `ValueStream` holding the latest state).*

### Insert / Update / Delete
**Before (Drift):**
```dart
await db.into(db.users).insert(UsersCompanion.insert(name: 'Alice'));
```

**After (Syncdrift):**
```dart
await userRepo.insertCompanion(UsersCompanion.insert(name: 'Alice'));
```

---

## 4. Relationship Queries

**Before (Drift Join Query):**
```dart
final query = db.select(db.users).join([
  leftOuterJoin(db.posts, db.posts.userId.equalsExp(db.users.id)),
]);
```

**After (Syncdrift Extension):**
```dart
final user = await userRepo.selectOne(where: 'id = ?', whereArgs: [userId]);
final posts = await user.loadPosts(driver);
```
