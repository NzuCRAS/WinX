import 'package:shared_preferences/shared_preferences.dart';

/// Stores the user-provided feed id (uuid) for subscription APIs.
///
/// 官方设计允许任意字符串作为订阅ID，所以我们在用户未指定时使用一个默认值。
final class SubscriptionStore {
  static const _kFeedId = 'xdnmb.subscription.feedId';
  static const String defaultFeedId = 'WinX';

  const SubscriptionStore();

  Future<String> readFeedId() async {
    final sp = await SharedPreferences.getInstance();
    final v = sp.getString(_kFeedId);
    if (v == null || v.trim().isEmpty) return defaultFeedId;
    return v.trim();
  }

  Future<void> writeFeedId(String feedId) async {
    final sp = await SharedPreferences.getInstance();
    final v = feedId.trim();
    await sp.setString(_kFeedId, v.isEmpty ? defaultFeedId : v);
  }
}
