import 'package:flutter/material.dart';

import 'post_history_page.dart';

final class MyPostsPage extends StatelessWidget {
  const MyPostsPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Keep backward compatible route name used by HomePage (sectionIndex=4).
    return const PostHistoryPage();
  }
}
