import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';

/// Opens a detached sub-window showing the image at [imagePath] with zoom,
/// rotate, and flip controls.
Future<void> openImageViewerWindow(String imagePath) async {
  final args = jsonEncode({
    'windowType': 'imageViewer',
    'imagePath': imagePath,
    'title': 'WinX 图片预览',
  });

  final window = await WindowController.create(
    WindowConfiguration(
      arguments: args,
      hiddenAtLaunch: false,
    ),
  );
  await window.show();
}

/// Open an image editor window and notify [callerWindowId] when editing is done.
Future<void> openImageEditorWindow(String imagePath, {String callerWindowId = '0'}) async {
  final file = File(imagePath);
  final fileName = file.uri.pathSegments.isEmpty
      ? imagePath
      : file.uri.pathSegments.last;

  final args = jsonEncode({
    'windowType': 'imageViewer',
    'imagePath': imagePath,
    'callerWindowId': callerWindowId,
    'title': fileName,
  });

  final window = await WindowController.create(
    WindowConfiguration(
      arguments: args,
      hiddenAtLaunch: false,
    ),
  );
  await window.show();
}
