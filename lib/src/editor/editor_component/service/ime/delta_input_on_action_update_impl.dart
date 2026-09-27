import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:flutter/material.dart';

Future<void> onPerformAction(
  TextInputAction action,
  EditorState editorState,
) async {
  AppFlowyEditorLog.input.debug('onPerformAction: $action');
}
