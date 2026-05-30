import 'package:flutter/material.dart';

void popAfterFocusSettles<T>(BuildContext context, [T? result]) {
  FocusManager.instance.primaryFocus?.unfocus();
  Future<void>.delayed(const Duration(milliseconds: 120), () {
    if (context.mounted) {
      Navigator.of(context).pop<T>(result);
    }
  });
}
