import 'package:flutter_test/flutter_test.dart';
import 'package:syncdrift_flutter/syncdrift_flutter.dart';
import 'package:example_app/database.dart';
import 'package:example_app/database.syncdrift.dart';

void main() {
  late AppDatabase db;
  late DriftDatabaseDriver driver;
  late UserRepository userRepo;
  late PostRepository postRepo;

  setUp(() {
    db = AppDatabase();
    driver = DriftDatabaseDriver(db);
    userRepo = UserRepository(driver);
    postRepo = PostRepository(driver);
  });

  tearDown(() async {
    await driver.close();
  });

  group('Syncdrift Core & Repositories', () {
    test('Can insert and retrieve users', () async {
      final id =
          await userRepo.insertCompanion(UsersCompanion.insert(name: 'Alice'));
      expect(id, 1);

      final users = await userRepo.selectAll();
      expect(users.length, 1);
      expect(users.first.name, 'Alice');
      expect(users.first.id, 1);
    });

    test('Can update and delete users', () async {
      final id =
          await userRepo.insertCompanion(UsersCompanion.insert(name: 'Alice'));

      final updatedRows = await userRepo.updateMap({'name': 'Bob'},
          where: 'id = ?', whereArgs: [id]);
      expect(updatedRows, 1);

      final user = await userRepo.selectOne(where: 'id = ?', whereArgs: [id]);
      expect(user?.name, 'Bob');

      final deletedRows =
          await userRepo.delete(where: 'id = ?', whereArgs: [id]);
      expect(deletedRows, 1);

      final usersAfterDelete = await userRepo.selectAll();
      expect(usersAfterDelete, isEmpty);
    });
  });

  group('Pagination', () {
    test('Paginates results correctly', () async {
      // Create user first
      final userId =
          await userRepo.insertCompanion(UsersCompanion.insert(name: 'User 1'));

      await postRepo.insertCompanion(PostsCompanion.insert(
          userId: userId, title: 'Post 1', content: 'C1'));
      await postRepo.insertCompanion(PostsCompanion.insert(
          userId: userId, title: 'Post 2', content: 'C2'));
      await postRepo.insertCompanion(PostsCompanion.insert(
          userId: userId, title: 'Post 3', content: 'C3'));
      await postRepo.insertCompanion(PostsCompanion.insert(
          userId: userId, title: 'Post 4', content: 'C4'));

      // Page 1, Size 2
      final page1 =
          await postRepo.paginate(page: 1, pageSize: 2, orderBy: 'id ASC');
      expect(page1.items.length, 2);
      expect(page1.totalCount, 4);
      expect(page1.items[0].title, 'Post 1');
      expect(page1.items[1].title, 'Post 2');
      expect(page1.hasNextPage, isTrue);
      expect(page1.hasPreviousPage, isFalse);

      // Page 2, Size 2
      final page2 =
          await postRepo.paginate(page: 2, pageSize: 2, orderBy: 'id ASC');
      expect(page2.items.length, 2);
      expect(page2.items[0].title, 'Post 3');
      expect(page2.items[1].title, 'Post 4');
      expect(page2.hasNextPage, isFalse);
      expect(page2.hasPreviousPage, isTrue);
    });
  });

  group('Relationships', () {
    test('HasMany and BelongsTo extensions load related data correctly',
        () async {
      final userId =
          await userRepo.insertCompanion(UsersCompanion.insert(name: 'Alice'));

      final post1Id = await postRepo.insertCompanion(
        PostsCompanion.insert(
            userId: userId, title: 'P1', content: 'Content 1'),
      );
      final post2Id = await postRepo.insertCompanion(
        PostsCompanion.insert(
            userId: userId, title: 'P2', content: 'Content 2'),
      );

      final user =
          (await userRepo.selectOne(where: 'id = ?', whereArgs: [userId]))!;

      // Load HasMany posts
      final posts = await user.loadPosts(driver);
      expect(posts.length, 2);
      expect(posts.any((p) => p.id == post1Id), isTrue);
      expect(posts.any((p) => p.id == post2Id), isTrue);

      // Load BelongsTo user from post
      final post = posts.first;
      final parentUser = await post.loadUsers(driver);
      expect(parentUser, isNotNull);
      expect(parentUser?.id, userId);
      expect(parentUser?.name, 'Alice');
    });
  });

  group('Reactive Streams (.obs)', () {
    test('Stream emits new values when database changes', () async {
      final stream = userRepo.watchAll().obs;

      // Insert user
      await userRepo.insertCompanion(UsersCompanion.insert(name: 'Alice'));

      // Wait for stream to emit the new user list containing Alice
      final list = await stream
          .firstWhere((users) => users.any((u) => u.name == 'Alice'));
      expect(list.length, 1);
      expect(list.first.name, 'Alice');
      expect(stream.value.first.name, 'Alice');
    });
  });
}
