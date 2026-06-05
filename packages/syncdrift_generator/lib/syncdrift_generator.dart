import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';
import 'package:syncdrift_annotations/syncdrift_annotations.dart';

/// Builder factory function registered in build.yaml.
Builder syncdriftBuilder(BuilderOptions options) {
  return SyncdriftBuilder();
}

/// Standalone builder for generating `.syncdrift.dart` files.
class SyncdriftBuilder implements Builder {
  @override
  final Map<String, List<String>> buildExtensions = const {
    '.dart': ['.syncdrift.dart']
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    final resolver = buildStep.resolver;
    if (!await resolver.isLibrary(buildStep.inputId)) return;

    final library = await buildStep.inputLibrary;
    final libraryReader = LibraryReader(library);

    // Find all classes annotated with @Repository
    final repositoryClasses = libraryReader.annotatedWith(
      const TypeChecker.fromRuntime(Repository),
    );

    if (repositoryClasses.isEmpty) return;

    final buffer = StringBuffer();
    buffer.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
    buffer.writeln();
    buffer
        .writeln("import 'package:syncdrift_flutter/syncdrift_flutter.dart';");
    buffer.writeln("import 'package:riverpod/riverpod.dart';");
    buffer.writeln("import '${buildStep.inputId.pathSegments.last}';");
    buffer.writeln("import 'package:drift/drift.dart' as drift;");
    buffer.writeln();

    for (final annotated in repositoryClasses) {
      final element = annotated.element;
      if (element is! ClassElement) continue;

      final tableName = element.name;
      final dataClassName = _getDataClassName(element);
      final companionName = '${tableName}Companion';
      final repositoryName = '${dataClassName}Repository';
      final sqlTableName = _toSnakeCase(tableName);

      buffer.writeln('/// Repository for [$tableName] table.');
      buffer.writeln(
          'class $repositoryName extends SyncdriftRepository<$dataClassName, $companionName> {');
      buffer.writeln(
          '  $repositoryName(DatabaseDriver driver) : super(driver, \'$sqlTableName\');');
      buffer.writeln();
      buffer.writeln('  @override');
      buffer.writeln(
          '  $dataClassName mapRow(Map<String, dynamic> row) => $dataClassName.fromJson(row);');
      buffer.writeln();
      buffer.writeln('  @override');
      buffer.writeln(
          '  Map<String, dynamic> entityToMap($dataClassName entity) => entity.toJson();');
      buffer.writeln();
      buffer.writeln(
          '  /// Helper to insert a record using a Drift companion class.');
      buffer.writeln(
          '  Future<int> insertCompanion($companionName companion) async {');
      buffer.writeln('    final map = companion.toColumns(true);');
      buffer.writeln('    final data = map.map((key, value) {');
      buffer.writeln('      if (value is drift.Variable) {');
      buffer.writeln('        return MapEntry(key, value.value);');
      buffer.writeln('      }');
      buffer.writeln('      return MapEntry(key, null);');
      buffer.writeln('    });');
      buffer.writeln('    return insertMap(data);');
      buffer.writeln('  }');
      buffer.writeln('}');
      buffer.writeln();

      final providerName = '${_toCamelCase(dataClassName)}RepositoryProvider';
      buffer.writeln('/// Riverpod provider for [$repositoryName].');
      buffer.writeln('final $providerName = Provider<$repositoryName>((ref) {');
      buffer.writeln('  final driver = ref.watch(syncdriftDriverProvider);');
      buffer.writeln('  return $repositoryName(driver);');
      buffer.writeln('});');
      buffer.writeln();

      _processRelations(element, buffer, dataClassName);
    }

    // Collect and generate static cache configurations from @Cached annotations
    final cacheConfigs = <String, int>{};
    for (final annotated in repositoryClasses) {
      final element = annotated.element;
      if (element is! ClassElement) continue;

      final tableName = element.name;
      final sqlTableName = _toSnakeCase(tableName);

      for (final meta in element.metadata) {
        final val = meta.computeConstantValue();
        if (val != null && val.type?.element?.name == 'Cached') {
          final ttl = val.getField('ttlSeconds')?.toIntValue();
          if (ttl != null) {
            cacheConfigs[sqlTableName] = ttl;
          }
        }
      }
    }

    buffer.writeln(
        '/// Static cache configurations generated from @Cached annotations.');
    buffer.writeln('final syncdriftCacheConfigurations = <String, Duration>{');
    cacheConfigs.forEach((table, ttl) {
      buffer.writeln('  \'$table\': Duration(seconds: $ttl),');
    });
    buffer.writeln('};');
    buffer.writeln();

    // Collect and generate static sync tables from @SyncTable annotations
    final syncTables = <String>{};
    for (final annotated in repositoryClasses) {
      final element = annotated.element;
      if (element is! ClassElement) continue;

      final tableName = element.name;
      final sqlTableName = _toSnakeCase(tableName);

      for (final meta in element.metadata) {
        final val = meta.computeConstantValue();
        if (val != null && val.type?.element?.name == 'SyncTable') {
          syncTables.add(sqlTableName);
        }
      }
    }

    buffer.writeln(
        '/// Static set of sync tables generated from @SyncTable annotations.');
    buffer.writeln('final syncdriftSyncTables = <String>{');
    for (final table in syncTables) {
      buffer.writeln('  \'$table\',');
    }
    buffer.writeln('};');
    buffer.writeln();

    await buildStep.writeAsString(
      buildStep.inputId.changeExtension('.syncdrift.dart'),
      buffer.toString(),
    );
  }

  String _toSnakeCase(String name) {
    final exp = RegExp(r'(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])');
    return name.replaceAll(exp, '_').toLowerCase();
  }

  String _toCamelCase(String name) {
    if (name.isEmpty) return '';
    return name[0].toLowerCase() + name.substring(1);
  }

  String _getDataClassName(ClassElement element) {
    for (final meta in element.metadata) {
      final value = meta.computeConstantValue();
      if (value != null && value.type?.element?.name == 'UseRowClassName') {
        final customName = value.getField('className')?.toStringValue();
        if (customName != null) return customName;
      }
    }
    final name = element.name;
    if (name.endsWith('s') && name.length > 1) {
      return name.substring(0, name.length - 1);
    }
    return name;
  }

  void _processRelations(
      ClassElement element, StringBuffer buffer, String dataClassName) {
    for (final meta in element.metadata) {
      final val = meta.computeConstantValue();
      if (val == null) continue;

      final typeName = val.type?.element?.name;
      if (typeName == 'HasMany') {
        final targetType = val.getField('targetTable')?.toTypeValue();
        final foreignKey = val.getField('foreignKey')?.toStringValue();

        if (targetType != null && foreignKey != null) {
          final targetTableName = targetType.element?.name ?? '';
          final targetDataClassName = _singularize(targetTableName);
          final targetRepoName = '${targetDataClassName}Repository';
          final sqlForeignKey = _toSnakeCase(foreignKey);

          buffer.writeln(
              '/// Extension to load related [$targetTableName] for [$dataClassName].');
          buffer.writeln(
              'extension ${dataClassName}HasMany${targetTableName}Extension on $dataClassName {');
          buffer.writeln(
              '  /// Asynchronously loads related [$targetTableName] items.');
          buffer.writeln(
              '  Future<List<$targetDataClassName>> load$targetTableName(DatabaseDriver driver) async {');
          buffer.writeln('    final repo = $targetRepoName(driver);');
          buffer.writeln(
              '    return repo.selectAll(where: \'$sqlForeignKey = ?\', whereArgs: [id]);');
          buffer.writeln('  }');
          buffer.writeln();
          buffer.writeln(
              '  /// Watches related [$targetTableName] items as a reactive stream.');
          buffer.writeln(
              '  Stream<List<$targetDataClassName>> watch$targetTableName(DatabaseDriver driver) {');
          buffer.writeln('    final repo = $targetRepoName(driver);');
          buffer.writeln(
              '    return repo.watchAll(where: \'$sqlForeignKey = ?\', whereArgs: [id]);');
          buffer.writeln('  }');
          buffer.writeln('}');
          buffer.writeln();
        }
      } else if (typeName == 'BelongsTo') {
        final targetType = val.getField('targetTable')?.toTypeValue();
        final foreignKey = val.getField('foreignKey')?.toStringValue();

        if (targetType != null && foreignKey != null) {
          final targetTableName = targetType.element?.name ?? '';
          final targetDataClassName = _singularize(targetTableName);
          final targetRepoName = '${targetDataClassName}Repository';

          buffer.writeln(
              '/// Extension to load parent [$targetTableName] for [$dataClassName].');
          buffer.writeln(
              'extension ${dataClassName}BelongsTo${targetTableName}Extension on $dataClassName {');
          buffer.writeln(
              '  /// Asynchronously loads the parent [$targetTableName] item.');
          buffer.writeln(
              '  Future<$targetDataClassName?> load$targetTableName(DatabaseDriver driver) async {');
          buffer.writeln('    final repo = $targetRepoName(driver);');
          buffer.writeln(
              '    return repo.selectOne(where: \'id = ?\', whereArgs: [$foreignKey]);');
          buffer.writeln('  }');
          buffer.writeln();
          buffer.writeln(
              '  /// Watches the parent [$targetTableName] item as a reactive stream.');
          buffer.writeln(
              '  Stream<$targetDataClassName?> watch$targetTableName(DatabaseDriver driver) {');
          buffer.writeln('    final repo = $targetRepoName(driver);');
          buffer.writeln(
              '    return repo.watchOne(where: \'id = ?\', whereArgs: [$foreignKey]);');
          buffer.writeln('  }');
          buffer.writeln('}');
          buffer.writeln();
        }
      }
    }
  }

  String _singularize(String name) {
    if (name.endsWith('s') && name.length > 1) {
      return name.substring(0, name.length - 1);
    }
    return name;
  }
}
