part of 'xdnmb.dart';

/// X 岛饼干
class XdnmbCookie {
  /// 饼干的 userhash
  final String userHash;

  /// 饼干显示的名字
  final String? name;

  /// 饼干 ID
  final int? id;

  /// 饼干的 cookie 值
  String get cookie {
    // Allow passing in QR/cURL style percent-encoded userhash directly.
    // If `userHash` itself already looks like "%XX%YY...", we must NOT encode
    // again, otherwise it becomes "%25XX" and breaks auth.
    if (_looksLikePercentEncodedUserHash(userHash)) {
      return 'userhash=$userHash';
    }
    return 'userhash=${encodeCookieValue(userHash)}';
  }

  /// 构造 [XdnmbCookie]
  const XdnmbCookie(this.userHash, {this.name, this.id});

  /// 从 JSON 数据构造 [XdnmbCookie]
  factory XdnmbCookie._fromJson(String data, {int? id}) {
    final Map<String, dynamic> decoded = json.decode(data);

    return XdnmbCookie(decoded['cookie'], name: decoded['name'], id: id);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is XdnmbCookie &&
          userHash == other.userHash &&
          name == other.name &&
          id == other.id);

  @override
  int get hashCode => Object.hash(userHash, name, id);
}

bool _looksLikePercentEncodedUserHash(String s) {
  // Treat it as percent-encoded only when it's *mostly* made of %xx triplets.
  // This avoids false positives for raw-byte (latin1) strings that may contain
  // a few '%' bytes.
  final re = RegExp(r'%[0-9a-fA-F]{2}');
  final matches = re.allMatches(s).toList(growable: false);
  if (matches.length < 8) return false;
  final covered = matches.length * 3;
  return covered >= (s.length * 0.8);
}

/// 饼干列表
class CookiesList {
  /// 帐号是否能获取新饼干
  final bool canGetCookie;

  /// 帐号目前拥有的饼干数
  final int currentCookiesNum;

  /// 帐号能够拥有的最大饼干数（饼干槽）
  final int totalCookiesNum;

  /// 帐号饼干 ID 列表
  final List<int> cookiesIdList;

  /// 构造 [CookiesList]
  const CookiesList(
      {required this.canGetCookie,
      required this.currentCookiesNum,
      required this.totalCookiesNum,
      required this.cookiesIdList});
}

/// [Cookie] 的扩展
extension CookieExtension on Cookie {
  /// 将 [Cookie] 转化为 cookie 值
  String get toCookie => '$name=$value';
}
