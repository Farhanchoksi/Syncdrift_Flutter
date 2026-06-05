import 'package:riverpod/riverpod.dart';
import 'driver.dart';

/// Riverpod provider for the global [DatabaseDriver] instance.
///
/// In your application initialization, you should override this provider
/// to return your configured database driver:
///
/// ```dart
/// ProviderScope(
///   overrides: [
///     syncdriftDriverProvider.overrideWithValue(myDriftDriver),
///   ],
///   child: MyApp(),
/// )
/// ```
final syncdriftDriverProvider = Provider<DatabaseDriver>((ref) {
  throw UnimplementedError(
    'You must override syncdriftDriverProvider with a concrete DatabaseDriver implementation.',
  );
});
