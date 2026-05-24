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
  TextColumn get groupName => text().withDefault(const Constant(''))();
  TextColumn get customModelId => text()();
  TextColumn get targetModelId => text()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  TextColumn get thinkingMode => text().withDefault(const Constant(''))();
  TextColumn get reasoningEffort =>
      text().withDefault(const Constant(''))();
  BoolColumn get convertThinkingToContent =>
      boolean().withDefault(const Constant(false))();
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

/// 毫秒精度 DateTime <-> int 转换器
class MillisDateTimeConverter extends TypeConverter<DateTime, int> {
  const MillisDateTimeConverter();

  @override
  DateTime fromSql(int fromDb) {
    return DateTime.fromMillisecondsSinceEpoch(fromDb);
  }

  @override
  int toSql(DateTime value) {
    return value.millisecondsSinceEpoch;
  }
}

/// 代理请求/响应日志（统一存储实时日志与历史分析所需的所有字段）
@TableIndex(name: 'idx_proxy_logs_time', columns: {#time})
@TableIndex(name: 'idx_proxy_logs_model', columns: {#model})
@TableIndex(name: 'idx_proxy_logs_endpoint', columns: {#targetEndpoint})
@TableIndex(name: 'idx_proxy_logs_status', columns: {#status})
class ProxyLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get method => text()();
  TextColumn get path => text()();
  IntColumn get time =>
      integer().map(const MillisDateTimeConverter())();
  TextColumn get model => text().nullable()();
  TextColumn get targetEndpoint => text().nullable()();
  IntColumn get statusCode => integer().nullable()();
  TextColumn get error => text().nullable()();
  IntColumn get requestDurationMs => integer().nullable()();
  IntColumn get firstByteMs => integer().nullable()();
  IntColumn get status => integer()();

  // 原始 body（用于导出 .log 文件）
  TextColumn get requestBody => text().nullable()();
  TextColumn get responseBody => text().nullable()();

  // 预解析的请求字段
  TextColumn get requestModel => text().nullable()();
  IntColumn get requestStream => integer().nullable()();
  TextColumn get requestMessagesJson => text().nullable()();
  TextColumn get requestSystemPrompt => text().nullable()();
  TextColumn get requestToolsJson => text().nullable()();
  TextColumn get requestOtherParamsJson => text().nullable()();

  // 预解析的响应字段
  TextColumn get responseModel => text().nullable()();
  TextColumn get responseType => text().nullable()();
  TextColumn get stopReason => text().nullable()();
  TextColumn get responseUsageJson => text().nullable()();
  TextColumn get responseContentJson => text().nullable()();
  TextColumn get responseId => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// ──────────────────────────── 数据库 ────────────────────────────

@DriftDatabase(tables: [Endpoints, Rules, RuleEndpoints, ProxyLogs])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.e);

  String get databaseFilePath => _dbFilePath;

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (migrator, from, to) async {
          if (from < 2) {
            await customStatement(
              "ALTER TABLE rules ADD COLUMN group_name TEXT NOT NULL DEFAULT ''",
            );
          }
          if (from < 3) {
            await customStatement(
              "ALTER TABLE rules ADD COLUMN convert_thinking_to_content "
              'INTEGER NOT NULL DEFAULT 0',
            );
          }
          if (from < 4) {
            await customStatement('''
              CREATE TABLE IF NOT EXISTS proxy_logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                method TEXT NOT NULL,
                path TEXT NOT NULL,
                time INTEGER NOT NULL,
                model TEXT,
                target_endpoint TEXT,
                status_code INTEGER,
                error TEXT,
                request_duration_ms INTEGER,
                first_byte_ms INTEGER,
                status INTEGER NOT NULL,
                request_body TEXT,
                response_body TEXT,
                request_model TEXT,
                request_stream INTEGER,
                request_messages_json TEXT,
                request_system_prompt TEXT,
                request_tools_json TEXT,
                request_other_params_json TEXT,
                response_model TEXT,
                response_type TEXT,
                stop_reason TEXT,
                response_usage_json TEXT,
                response_content_json TEXT,
                response_id TEXT,
                created_at INTEGER NOT NULL DEFAULT (strftime('%s','now') * 1000)
              )
            ''');
          }
          if (from < 5) {
            await customStatement('''
              CREATE TABLE proxy_logs_v5 (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                method TEXT NOT NULL,
                path TEXT NOT NULL,
                time INTEGER NOT NULL,
                model TEXT,
                target_endpoint TEXT,
                status_code INTEGER,
                error TEXT,
                request_duration_ms INTEGER,
                first_byte_ms INTEGER,
                status INTEGER NOT NULL,
                request_body TEXT,
                response_body TEXT,
                request_model TEXT,
                request_stream INTEGER,
                request_messages_json TEXT,
                request_system_prompt TEXT,
                request_tools_json TEXT,
                request_other_params_json TEXT,
                response_model TEXT,
                response_type TEXT,
                stop_reason TEXT,
                response_usage_json TEXT,
                response_content_json TEXT,
                response_id TEXT,
                created_at INTEGER NOT NULL DEFAULT (strftime('%s','now') * 1000)
              )
            ''');
            await customStatement('''
              INSERT INTO proxy_logs_v5 (
                id, method, path, time, model, target_endpoint, status_code,
                error, request_duration_ms, first_byte_ms, status,
                request_body, response_body, request_model, request_stream,
                request_messages_json, request_system_prompt, request_tools_json,
                request_other_params_json, response_model, response_type,
                stop_reason, response_usage_json, response_content_json,
                response_id, created_at
              )
              SELECT
                id, method, path, time, model, target_endpoint, status_code,
                error, request_duration_ms, first_byte_ms, status,
                request_body, response_body, request_model, request_stream,
                request_messages_json, request_system_prompt, request_tools_json,
                request_other_params_json, response_model, response_type,
                stop_reason, response_usage_json, response_content_json,
                response_id, created_at
              FROM proxy_logs
            ''');
            await customStatement('DROP TABLE proxy_logs');
            await customStatement(
              'ALTER TABLE proxy_logs_v5 RENAME TO proxy_logs',
            );
          }
          if (from < 6) {
            // 将 time 列从秒级时间戳转为毫秒级
            await customStatement(
              'UPDATE proxy_logs SET time = time * 1000 WHERE time < 100000000000',
            );
          }
        },
      );
}

String _dbFilePath = '';

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationSupportDirectory();
    final file = File(p.join(dbFolder.path, 'llm_proxy.sqlite'));
    _dbFilePath = file.path;

    if (Platform.isMacOS || Platform.isIOS) {
      final cacheDir = await getTemporaryDirectory();
      sqlite3.tempDirectory = cacheDir.path;
    }

    return NativeDatabase.createInBackground(
      file,
      setup: (database) {
        database.execute('PRAGMA journal_mode = WAL;');
      },
    );
  });
}
