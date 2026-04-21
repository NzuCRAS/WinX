import 'package:flutter/material.dart';

/// Shows a dialog for inputting advanced dice range [n,m].
/// Returns the formatted string "[n,m]" or null if cancelled.
Future<String?> showAdvancedDiceDialog(BuildContext context) async {
  final nCtrl = TextEditingController(text: '1');
  final mCtrl = TextEditingController(text: '6');

  final result = await showDialog<String>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('高级骰子'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '起始值 (n)',
                hintText: '1',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: mCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '结束值 (m)',
                hintText: '6',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final n = int.tryParse(nCtrl.text.trim()) ?? 1;
              final m = int.tryParse(mCtrl.text.trim()) ?? 6;
              final minV = n < m ? n : m;
              final maxV = n < m ? m : n;
              Navigator.pop(ctx, '[$minV,$maxV]');
            },
            child: const Text('确定'),
          ),
        ],
      );
    },
  );

  nCtrl.dispose();
  mCtrl.dispose();
  return result;
}

