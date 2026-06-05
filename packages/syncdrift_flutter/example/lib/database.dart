import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:syncdrift_flutter/syncdrift_flutter.dart';

part 'database.g.dart';

@Repository()
@Cached(ttlSeconds: 2)
@SyncTable()
@HasMany(Posts, foreignKey: 'userId')
class Users extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
}

@Repository()
@Cached(ttlSeconds: 5)
@SyncTable()
@BelongsTo(Users, foreignKey: 'userId')
class Posts extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get userId => integer().references(Users, #id)();
  TextColumn get title => text()();
  TextColumn get content => text()();
}

@DriftDatabase(tables: [Users, Posts])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;
}

QueryExecutor _openConnection() {
  return NativeDatabase.memory();
}
