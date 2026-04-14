import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'history_store.dart';
import 'post_history_store.dart';

/// SQLite数据库管理器
final class DatabaseHelper {
  static const _databaseName = 'xdnmb.db';
  static const _databaseVersion = 1;

  // 表名
  static const _tableHistory = 'history';
  static const _tablePostHistory = 'post_history';

  // 单例模式
  static final DatabaseHelper _instance = DatabaseHelper._internal();

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  Database? _database;

  /// 获取数据库实例
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// 初始化数据库
  Future<Database> _initDatabase() async {
    String baseDir;
    try {
      final documentsDirectory = await getApplicationDocumentsDirectory();
      baseDir = documentsDirectory.path;

      if (kDebugMode) {
        debugPrint('Database dir (documents): $baseDir');
        try {
          final dirExists = await documentsDirectory.exists();
          debugPrint('Database dir exists: $dirExists ($baseDir)');
        } catch (e) {
          debugPrint('Database dir exists check failed: $e');
        }
      }
    } on MissingPluginException {
      // Unit tests on VM don't have platform plugins.
      baseDir = await getDatabasesPath();
      if (kDebugMode) debugPrint('Database dir (fallback getDatabasesPath): $baseDir');
    }

    final dbPath = path.join(baseDir, _databaseName);
    if (kDebugMode) debugPrint('Database path: $dbPath');
  // NOTE: Don't call `databaseExists()` here.
  // On Windows, `databaseExists()` may require a databaseFactory to be
  // initialized (sqflite_common_ffi). We rely on `openDatabase()` below to
  // create the db file when needed.

    return await openDatabase(
      dbPath,
      version: _databaseVersion,
      onCreate: (db, version) async {
  if (kDebugMode) debugPrint('Creating database tables...');
        await _onCreate(db, version);
  if (kDebugMode) debugPrint('Database tables created successfully');
      },
      onUpgrade: _onUpgrade,
    );
  }

  /// 创建数据库表
  Future<void> _onCreate(Database db, int version) async {
    // 创建历史记录表
    await db.execute('''
      CREATE TABLE $_tableHistory (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        thread_id INTEGER NOT NULL,
        title TEXT,
        user_hash TEXT,
        is_admin INTEGER,
        post_time TEXT,
        reply_count INTEGER,
        thumb_image_url TEXT,
        content TEXT,
        visited_at TEXT NOT NULL
      )
    ''');

    // 创建发串记录表
    await db.execute('''
      CREATE TABLE $_tablePostHistory (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        main_post_id INTEGER,
        reply_post_id INTEGER,
        forum_id INTEGER,
        is_reply INTEGER NOT NULL,
        title TEXT,
        content TEXT NOT NULL,
        posted_at TEXT NOT NULL,
        thread_user_hash TEXT,
        thread_is_admin INTEGER,
        thread_post_time TEXT,
        thread_reply_count INTEGER,
        thread_thumb_image_url TEXT,
        thread_content TEXT
      )
    ''');

    // 创建索引以提高查询性能
    await db.execute('CREATE INDEX idx_history_thread_id ON $_tableHistory (thread_id)');
    await db.execute('CREATE INDEX idx_history_visited_at ON $_tableHistory (visited_at)');
    await db.execute('CREATE INDEX idx_post_history_posted_at ON $_tablePostHistory (posted_at)');
  }

  /// 升级数据库
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // 在这里处理数据库版本升级
    if (oldVersion < newVersion) {
      // 示例：添加新列
      // await db.execute('ALTER TABLE $_tableHistory ADD COLUMN new_column TEXT');
    }
  }

  /// 插入历史记录
  Future<void> insertHistory(HistoryEntry entry) async {
    if (kDebugMode) {
      debugPrint(
        'Inserting history entry: threadId=${entry.threadId}, title=${entry.title}',
      );
    }
    final db = await database;
    
    // 先删除相同threadId的记录
    final deleteCount = await db.delete(
      _tableHistory,
      where: 'thread_id = ?',
      whereArgs: [entry.threadId],
    );
    if (kDebugMode) {
      debugPrint(
        'Deleted $deleteCount existing records for threadId=${entry.threadId}',
      );
    }

    // 插入新记录
    final insertId = await db.insert(
      _tableHistory,
      {
        'thread_id': entry.threadId,
        'title': entry.title,
        'user_hash': entry.userHash,
        'is_admin': entry.isAdmin == true ? 1 : (entry.isAdmin == false ? 0 : null),
        'post_time': entry.postTime?.toIso8601String(),
        'reply_count': entry.replyCount,
        'thumb_image_url': entry.thumbImageUrl,
        'content': entry.content,
        'visited_at': entry.visitedAt.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  if (kDebugMode) debugPrint('Inserted history entry with id=$insertId');

    // 限制记录数量为500
    await _limitRecords(db, _tableHistory, 500, 'visited_at DESC');
  }

  /// 获取所有历史记录
  Future<List<HistoryEntry>> getAllHistory() async {
  if (kDebugMode) debugPrint('Getting all history records...');
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _tableHistory,
      orderBy: 'visited_at DESC',
    );
  if (kDebugMode) debugPrint('Found ${maps.length} history records');

    final entries = List.generate(maps.length, (i) {
      return HistoryEntry(
        threadId: maps[i]['thread_id'],
        title: maps[i]['title'],
        userHash: maps[i]['user_hash'],
        isAdmin: maps[i]['is_admin'] == 1 ? true : (maps[i]['is_admin'] == 0 ? false : null),
        postTime: maps[i]['post_time'] != null 
            ? DateTime.tryParse(maps[i]['post_time']) 
            : null,
        replyCount: maps[i]['reply_count'],
        thumbImageUrl: maps[i]['thumb_image_url'],
        content: maps[i]['content'],
        visitedAt: DateTime.parse(maps[i]['visited_at']),
      );
    });
    return entries;
  }

  /// 删除历史记录
  Future<void> deleteHistory(int threadId) async {
    final db = await database;
    await db.delete(
      _tableHistory,
      where: 'thread_id = ?',
      whereArgs: [threadId],
    );
  }

  /// 清空历史记录
  Future<void> clearHistory() async {
    final db = await database;
    await db.delete(_tableHistory);
  }

  /// 插入发串记录
  Future<void> insertPostHistory(PostHistoryEntry entry) async {
    if (kDebugMode) {
      debugPrint(
        'Inserting post history entry: isReply=${entry.isReply}, mainPostId=${entry.mainPostId}',
      );
    }
    final db = await database;
    
    final insertId = await db.insert(
      _tablePostHistory,
      {
        'main_post_id': entry.mainPostId,
        'reply_post_id': entry.replyPostId,
        'forum_id': entry.forumId,
        'is_reply': entry.isReply ? 1 : 0,
        'title': entry.title,
        'content': entry.content,
        'posted_at': entry.postedAt.toIso8601String(),
        'thread_user_hash': entry.threadUserHash,
        'thread_is_admin': entry.threadIsAdmin == true ? 1 : (entry.threadIsAdmin == false ? 0 : null),
        'thread_post_time': entry.threadPostTime?.toIso8601String(),
        'thread_reply_count': entry.threadReplyCount,
        'thread_thumb_image_url': entry.threadThumbImageUrl,
        'thread_content': entry.threadContent,
      },
  conflictAlgorithm: ConflictAlgorithm.abort,
    );
  if (kDebugMode) debugPrint('Inserted post history entry with id=$insertId');

    // 限制记录数量为500
    await _limitRecords(db, _tablePostHistory, 500, 'posted_at DESC');
  }

  /// 获取所有发串记录
  Future<List<PostHistoryEntry>> getAllPostHistory() async {
  if (kDebugMode) debugPrint('Getting all post history records...');
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _tablePostHistory,
      orderBy: 'posted_at DESC',
    );
  if (kDebugMode) debugPrint('Found ${maps.length} post history records');

    final entries = List.generate(maps.length, (i) {
      return PostHistoryEntry(
        id: maps[i]['id'],
        mainPostId: maps[i]['main_post_id'],
        replyPostId: maps[i]['reply_post_id'],
        forumId: maps[i]['forum_id'],
        isReply: maps[i]['is_reply'] == 1,
        title: maps[i]['title'],
        content: maps[i]['content'],
        postedAt: DateTime.parse(maps[i]['posted_at']),
        threadUserHash: maps[i]['thread_user_hash'],
        threadIsAdmin: maps[i]['thread_is_admin'] == 1 ? true : (maps[i]['thread_is_admin'] == 0 ? false : null),
        threadPostTime: maps[i]['thread_post_time'] != null
            ? DateTime.tryParse(maps[i]['thread_post_time'])
            : null,
        threadReplyCount: maps[i]['thread_reply_count'],
        threadThumbImageUrl: maps[i]['thread_thumb_image_url'],
        threadContent: maps[i]['thread_content'],
      );
    });
    return entries;
  }

  /// 删除发串记录
  Future<void> deletePostHistory(int id) async {
    final db = await database;
    await db.delete(
      _tablePostHistory,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 根据内容和发布时间删除发串记录
  Future<void> deletePostHistoryByContent(String content, DateTime postedAt) async {
    final db = await database;
    await db.delete(
      _tablePostHistory,
      where: 'content = ? AND posted_at = ?',
      whereArgs: [content, postedAt.toIso8601String()],
    );
  }

  /// 清空发串记录
  Future<void> clearPostHistory() async {
    final db = await database;
    await db.delete(_tablePostHistory);
  }

  /// 限制记录数量
  Future<void> _limitRecords(Database db, String table, int limit, String orderBy) async {
    final result = await db.rawQuery(
      'SELECT id FROM $table ORDER BY $orderBy LIMIT -1 OFFSET ?',
      [limit],
    );

    if (result.isNotEmpty) {
      final ids = result.map((row) => row['id']).toList();
      await db.delete(
        table,
        where: 'id IN (${List.filled(ids.length, '?').join(',')})',
        whereArgs: ids,
      );
    }
  }

  /// 关闭数据库
  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}