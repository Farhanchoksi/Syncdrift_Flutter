import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncdrift_flutter/syncdrift_flutter.dart';
import 'database.dart';
import 'database.syncdrift.dart';

// Riverpod Provider for our Drift AppDatabase
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

// Provider that adapts AppDatabase to the Syncdrift DatabaseDriver
final appDriverProvider = Provider<DatabaseDriver>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return DriftDatabaseDriver(db);
});

void main() {
  runApp(
    ProviderScope(
      overrides: [
        // Map global syncdriftDriverProvider to our adapted AppDatabase driver
        syncdriftDriverProvider
            .overrideWith((ref) => ref.watch(appDriverProvider)),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Syncdrift Demo',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0F1A),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.dark,
          primary: const Color(0xFF6366F1),
          secondary: const Color(0xFFEC4899),
        ),
        cardTheme: const CardTheme(
          color: Color(0xFF1E1E2F),
          elevation: 4,
          margin: EdgeInsets.symmetric(vertical: 6),
        ),
      ),
      home: const DashboardPage(),
    );
  }
}

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  int? _selectedUserId;
  int _currentPage = 1;
  static const int _pageSize = 3;

  final TextEditingController _userNameController = TextEditingController();
  final TextEditingController _postTitleController = TextEditingController();
  final TextEditingController _postContentController = TextEditingController();

  @override
  void dispose() {
    _userNameController.dispose();
    _postTitleController.dispose();
    _postContentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userRepo = ref.watch(userRepositoryProvider);
    final postRepo = ref.watch(postRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('⚡ Syncdrift Foundation Dashboard'),
        backgroundColor: const Color(0xFF14142B),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // User section
            _buildSectionTitle('Users'),
            _buildAddUserCard(userRepo),
            const SizedBox(height: 12),
            _buildUserListStream(userRepo),

            const SizedBox(height: 24),

            // Posts section
            if (_selectedUserId != null) ...[
              _buildSectionTitle('Posts for Selected User'),
              _buildAddPostCard(postRepo, _selectedUserId!),
              const SizedBox(height: 12),
              _buildPostsPaginatedList(postRepo, _selectedUserId!),
            ] else
              const Card(
                color: Color(0xFF1B1B30),
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Center(
                    child: Text(
                      'Select a user to view and manage posts.',
                      style: TextStyle(
                          color: Colors.white60, fontStyle: FontStyle.italic),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Color(0xFFEC4899),
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildAddUserCard(UserRepository userRepo) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _userNameController,
                decoration: const InputDecoration(
                  hintText: 'Enter new user name...',
                  border: InputBorder.none,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = _userNameController.text.trim();
                if (name.isNotEmpty) {
                  await userRepo
                      .insertCompanion(UsersCompanion.insert(name: name));
                  _userNameController.clear();
                  setState(() {});
                }
              },
              child: const Text('Add User'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserListStream(UserRepository userRepo) {
    // Watch users reactively with .obs
    return StreamBuilder<List<User>>(
      stream: userRepo.watchAll().obs, // Demonstrate .obs extension
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final users = snapshot.data!;
        if (users.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('No users in database.',
                style: TextStyle(color: Colors.white38)),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: users.length,
          itemBuilder: (context, index) {
            final user = users[index];
            final isSelected = _selectedUserId == user.id;

            return Card(
              color: isSelected
                  ? const Color(0xFF2A2B4D)
                  : const Color(0xFF1E1E2F),
              shape: RoundedRectangleBorder(
                side: BorderSide(
                  color:
                      isSelected ? const Color(0xFF6366F1) : Colors.transparent,
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListTile(
                title: Text(user.name,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('ID: ${user.id}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.redAccent),
                      onPressed: () async {
                        await userRepo
                            .delete(where: 'id = ?', whereArgs: [user.id]);
                        if (_selectedUserId == user.id) {
                          setState(() {
                            _selectedUserId = null;
                          });
                        }
                      },
                    ),
                  ],
                ),
                onTap: () {
                  setState(() {
                    _selectedUserId = user.id;
                    _currentPage = 1; // reset page
                  });
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAddPostCard(PostRepository postRepo, int userId) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            TextField(
              controller: _postTitleController,
              decoration: const InputDecoration(
                hintText: 'Post Title',
                contentPadding: EdgeInsets.symmetric(vertical: 4),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _postContentController,
              decoration: const InputDecoration(
                hintText: 'Post Content',
                contentPadding: EdgeInsets.symmetric(vertical: 4),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () async {
                final title = _postTitleController.text.trim();
                final content = _postContentController.text.trim();
                if (title.isNotEmpty && content.isNotEmpty) {
                  await postRepo.insertCompanion(
                    PostsCompanion.insert(
                      userId: userId,
                      title: title,
                      content: content,
                    ),
                  );
                  _postTitleController.clear();
                  _postContentController.clear();
                  setState(() {});
                }
              },
              child: const Text('Publish Post'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostsPaginatedList(PostRepository postRepo, int userId) {
    return FutureBuilder<PaginatedResult<Post>>(
      // Paginate posts for target user
      future: postRepo.paginate(
        page: _currentPage,
        pageSize: _pageSize,
        where: 'user_id = ?',
        whereArgs: [userId],
        orderBy: 'id DESC',
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final result = snapshot.data!;
        final posts = result.items;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (posts.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Center(
                  child: Text('No posts found for this user.',
                      style: TextStyle(color: Colors.white38)),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: posts.length,
                itemBuilder: (context, index) {
                  final post = posts[index];
                  return Card(
                    color: const Color(0xFF14142B),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            post.title,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            post.content,
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total: ${result.totalCount} (Page $_currentPage)',
                  style: const TextStyle(color: Colors.white54),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios),
                      onPressed: result.hasPreviousPage
                          ? () {
                              setState(() {
                                _currentPage--;
                              });
                            }
                          : null,
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward_ios),
                      onPressed: result.hasNextPage
                          ? () {
                              setState(() {
                                _currentPage++;
                              });
                            }
                          : null,
                    ),
                  ],
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
