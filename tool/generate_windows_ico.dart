import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Generate Windows ICO from a PNG file.
///
/// Usage:
///   dart run tool/generate_windows_ico.dart <input.png> <output.ico>
///
/// This creates a multi-size ICO containing:
/// 16, 24, 32, 48, 64, 128, 256.
///
/// Notes:
/// - Windows runner expects an .ico referenced by `windows/runner/Runner.rc`.
/// - We embed each size as a PNG image inside the ICO (supported by Windows).
void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/generate_windows_ico.dart <input.png> <output.ico>',
    );
    exitCode = 64; // EX_USAGE
    return;
  }

  final inputPath = args[0];
  final outputPath = args[1];

  final inputFile = File(inputPath);
  if (!inputFile.existsSync()) {
    stderr.writeln('Input not found: $inputPath');
    exitCode = 66; // EX_NOINPUT
    return;
  }

  final bytes = inputFile.readAsBytesSync();
  final src = img.decodePng(bytes);
  if (src == null) {
    stderr.writeln('Failed to decode PNG: $inputPath');
    exitCode = 65;
    return;
  }

  const sizes = <int>[16, 24, 32, 48, 64, 128, 256];
  final entries = <_IcoEntry>[];

  for (final s in sizes) {
    final resized = img.copyResize(
      src,
      width: s,
      height: s,
      interpolation: img.Interpolation.average,
    );
    final png = img.encodePng(resized, level: 6);
    entries.add(_IcoEntry(size: s, pngBytes: png));
  }

  final out = _buildIco(entries);
  final outFile = File(outputPath);
  outFile.parent.createSync(recursive: true);
  outFile.writeAsBytesSync(out);
  stdout.writeln('Wrote: $outputPath');
}

final class _IcoEntry {
  final int size;
  final List<int> pngBytes;

  const _IcoEntry({required this.size, required this.pngBytes});
}

List<int> _buildIco(List<_IcoEntry> entries) {
  // ICONDIR
  // WORD idReserved = 0;
  // WORD idType = 1;
  // WORD idCount = entries.length;
  // followed by ICONDIRENTRY[idCount]
  final count = entries.length;
  final headerSize = 6;
  final dirEntrySize = 16;
  var imagesOffset = headerSize + dirEntrySize * count;

  final buffer = BytesBuilder(copy: false);

  void w16(int v) {
    buffer.addByte(v & 0xFF);
    buffer.addByte((v >> 8) & 0xFF);
  }

  void w32(int v) {
    buffer.addByte(v & 0xFF);
    buffer.addByte((v >> 8) & 0xFF);
    buffer.addByte((v >> 16) & 0xFF);
    buffer.addByte((v >> 24) & 0xFF);
  }

  // ICONDIR header.
  w16(0);
  w16(1);
  w16(count);

  // Precompute offsets.
  final offsets = <int>[];
  final sizes = <int>[];
  for (final e in entries) {
    offsets.add(imagesOffset);
    sizes.add(e.pngBytes.length);
    imagesOffset += e.pngBytes.length;
  }

  // ICONDIRENTRY for each image.
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    final s = e.size;
    final w = s >= 256 ? 0 : s; // 0 means 256 in ICO format.
    final h = s >= 256 ? 0 : s;

    buffer.addByte(w);
    buffer.addByte(h);
    buffer.addByte(0); // color count
    buffer.addByte(0); // reserved

    w16(1); // planes
    w16(32); // bit count
    w32(sizes[i]); // bytes in resource
    w32(offsets[i]); // image offset
  }

  // Image data blocks.
  for (final e in entries) {
    buffer.add(e.pngBytes);
  }

  return buffer.takeBytes();
}
