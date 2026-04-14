import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:xdnmb_client/src/data/post_history_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('PostHistoryStore sqlite backend: record/read/clear', () async {
    final store = PostHistoryStore();
    await store.clear();

    await store.record(
      PostHistoryEntry(
        isReply: true,
        content: 'hello',
        postedAt: DateTime.now(),
        mainPostId: 123,
      ),
    );

    final all = await store.readAll();
    expect(all, isNotEmpty);
    expect(all.first.content, 'hello');

    await store.clear();
    final empty = await store.readAll();
    expect(empty, isEmpty);
  });
}
