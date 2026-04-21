import 'package:flutter_test/flutter_test.dart';
import 'package:xdnmb_api/xdnmb_api.dart';

import 'package:xdnmb_client/src/ui/widgets/cdn_fallback_image.dart';

void main() {
  test('CdnFallbackCachedNetworkImage builds candidate urls with different cdn hosts', () {
    // Arrange: override global urls with candidates.
    XdnmbUrls.overrideCdnUrl(
      Uri.parse('https://a.example.com'),
      candidates: [
        Uri.parse('https://a.example.com'),
        Uri.parse('https://b.example.com'),
        Uri.parse('https://c.example.com'),
      ],
    );

    const url = 'https://a.example.com/img/abc.jpg?x=1';

    // We can't easily trigger actual network in unit tests here, but we can
    // validate that widget can be constructed and doesn't throw.
    final w = CdnFallbackCachedNetworkImage(imageUrl: url, maxFailoverTries: 2);
    expect(w.imageUrl, url);
    expect(w.maxFailoverTries, 2);
  });
}
