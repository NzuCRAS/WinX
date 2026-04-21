import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:xdnmb_api/xdnmb_api.dart';

import '../../data/perf_log.dart';

/// CachedNetworkImage with CDN failover.
///
/// Contract:
/// - Input [imageUrl] is expected to be an absolute URL string.
/// - When loading fails, we will try other CDN candidates from [XdnmbUrls].
/// - We only failover when the URL's host matches current cdnUrl host.
///   This avoids messing with non-CDN URLs.
///
/// Notes:
/// - This widget keeps the same cache key semantics as CachedNetworkImage.
///   When we switch to a different CDN host, it becomes a different cache key,
///   which is acceptable because it's a different origin.
final class CdnFallbackCachedNetworkImage extends StatefulWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final PlaceholderWidgetBuilder? placeholder;
  final LoadingErrorWidgetBuilder? errorWidget;

  /// Max number of CDN alternatives to try (excluding the initial URL).
  final int maxFailoverTries;

  const CdnFallbackCachedNetworkImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit,
    this.placeholder,
    this.errorWidget,
    this.maxFailoverTries = 2,
  });

  @override
  State<CdnFallbackCachedNetworkImage> createState() => _CdnFallbackCachedNetworkImageState();
}

final class _CdnFallbackCachedNetworkImageState extends State<CdnFallbackCachedNetworkImage> {
  late String _effectiveUrl;
  late List<String> _candidateUrls;
  var _cursor = 0;

  StageTimer? _perf;
  bool _firstFrameLogged = false;

  @override
  void initState() {
    super.initState();
    _rebuildCandidates();
  }

  @override
  void didUpdateWidget(covariant CdnFallbackCachedNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _rebuildCandidates();
    }
  }

  void _rebuildCandidates() {
    final base = widget.imageUrl;
    final baseUri = Uri.tryParse(base);
    final cdnHost = XdnmbUrls().cdnUrl.host;

    // Default: no failover, just use the original URL.
    final urls = <String>[base];

    if (baseUri != null && baseUri.hasAuthority && baseUri.host == cdnHost) {
      final candidates = XdnmbUrls().cdnCandidates;
      // Prefer candidates before current cdnUrl? Not necessary.
      // We'll just iterate in listed order and skip duplicates.
      for (final c in candidates) {
        if (!c.hasAuthority) continue;
        if (c.host == baseUri.host && c.port == baseUri.port) continue;

        final swapped = baseUri.replace(
          scheme: c.scheme,
          host: c.host,
          port: c.hasPort ? c.port : null,
        );
        urls.add(swapped.toString());
        if (urls.length >= 1 + widget.maxFailoverTries) break;
      }
    }

    _candidateUrls = urls;
    _cursor = 0;
    _effectiveUrl = _candidateUrls[_cursor];

    // New URL means a new image load lifecycle.
    _firstFrameLogged = false;
    _perf = PerfLog.enabled ? PerfLog.stage('img') : null;
    _perf?.check(
      'start',
      fields: {
        'tries': _candidateUrls.length,
      },
    );
  }

  void _tryNext(Object error) {
    if (!mounted) return;
    if (_cursor + 1 >= _candidateUrls.length) return;

    _perf?.check(
      'failover',
      fields: {
        'from': _cursor,
        'err': error.toString(),
      },
    );
    setState(() {
      _cursor++;
      _effectiveUrl = _candidateUrls[_cursor];
    });

    _perf?.check('retry', fields: {'to': _cursor});
  }

  @override
  Widget build(BuildContext context) {
    // Data -> first frame (image widget built & painted) is a useful proxy for
    // decode/render jank. This doesn't guarantee bytes are loaded, but it helps
    // identify heavy image workloads on cold start.
    if (!_firstFrameLogged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_firstFrameLogged) return;
        _firstFrameLogged = true;
        _perf?.end(
          'firstFrame',
          {
            'try': _cursor,
          },
        );
      });
    }

    return CachedNetworkImage(
      imageUrl: _effectiveUrl,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      placeholder: widget.placeholder,
      errorWidget: (context, url, error) {
        // Failover first; if exhausted, render caller's error widget.
        final isLast = _cursor + 1 >= _candidateUrls.length;
        if (!isLast) {
          // schedule after build
          WidgetsBinding.instance.addPostFrameCallback((_) => _tryNext(error));
          // while switching, keep showing placeholder if provided.
          if (widget.placeholder != null) return widget.placeholder!(context, url);
          return const SizedBox.shrink();
        }

        _perf?.end(
          'error',
          {
            'try': _cursor,
            'err': error.toString(),
          },
        );
        if (widget.errorWidget != null) return widget.errorWidget!(context, url, error);
        return const SizedBox.shrink();
      },
    );
  }
}
