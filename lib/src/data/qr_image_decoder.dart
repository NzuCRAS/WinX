import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

/// Decode QR code content from image bytes.
///
/// Returns the raw payload string, or null if not found/decodable.
Future<String?> decodeQrFromImageBytes(Uint8List bytes) async {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  final w = decoded.width;
  final h = decoded.height;

  // Convert to luminance buffer (0..255)
  final luminances = Int32List(w * h);
  var idx = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = decoded.getPixel(x, y);
      final r = p.r.toInt();
      final g = p.g.toInt();
      final b = p.b.toInt();
      // Rec. 601 luma
      final l = (0.299 * r + 0.587 * g + 0.114 * b).round();
      luminances[idx++] = l.clamp(0, 255);
    }
  }

  final source = RGBLuminanceSource(w, h, luminances);
  final bitmap = BinaryBitmap(HybridBinarizer(source));

  try {
    final result = QRCodeReader().decode(bitmap);
    return result.text;
  } catch (_) {
    return null;
  }
}
