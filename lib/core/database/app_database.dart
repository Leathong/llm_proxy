import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
// ignore: unused_import
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

part 'app_database.g.dart';

// ──────────────────────────── 表定义 ────────────────────────────

/// 全局 endpoint 池，所有历史 endpoint 都保存在这里
class Endpoints extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get url => text()();
  TextColumn get apiKey => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
}

/// 代理规则
class Rules extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get customModelId => text()();
  TextColumn get targetModelId => text()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  TextColumn get thinkingMode => text().withDefault(const Constant(''))();
  TextColumn get reasoningEffort =>
      text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
}

/// rule ↔ endpoint 多对多关联，active 表示该 endpoint 在此 rule 中是否启用
class RuleEndpoints extends Table {
  IntColumn get ruleId =>
      integer().references(Rules, #id, onDelete: KeyAction.cascade)();
  IntColumn get endpointId =>
      integer().references(Endpoints, #id, onDelete: KeyAction.cascade)();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {ruleId, endpointId};
}

// ──────────────────────────── 数据库 ────────────────────────────

@DriftDatabase(tables: [Endpoints, Rules, RuleEndpoints])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 1;
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationSupportDirectory();
    final file = File(p.join(dbFolder.path, 'llm_proxy.sqlite'));

    if (Platform.isMacOS || Platform.isIOS) {
      final cacheDir = await getTemporaryDirectory();
      sqlite3.tempDirectory = cacheDir.path;
    }

    return NativeDatabase.createInBackground(file);
  });
}
