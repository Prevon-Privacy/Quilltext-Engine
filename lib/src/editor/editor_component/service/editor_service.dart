import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:flutter/material.dart' hide Overlay, OverlayEntry, OverlayState;

class EditorService {
  // selection service
  final selectionServiceKey = GlobalKey(
    debugLabel: 'prevon_quilltext_engine_selection_service',
  );
  AppFlowySelectionService get selectionService {
    assert(
      selectionServiceKey.currentState != null &&
          selectionServiceKey.currentState is AppFlowySelectionService,
    );
    return selectionServiceKey.currentState! as AppFlowySelectionService;
  }

  // keyboard service
  final keyboardServiceKey = GlobalKey(
    debugLabel: 'prevon_quilltext_engine_keyboard_service',
  );
  AppFlowyKeyboardService? get keyboardService {
    if (keyboardServiceKey.currentState != null &&
        keyboardServiceKey.currentState is AppFlowyKeyboardService) {
      return keyboardServiceKey.currentState! as AppFlowyKeyboardService;
    }
    return null;
  }

  // render plugin service
  // late AppFlowyRenderPlugin renderPluginService;
  late BlockComponentRendererService rendererService;

  // scroll service
  final scrollServiceKey = GlobalKey(
    debugLabel: 'prevon_quilltext_engine_scroll_service',
  );
  AppFlowyScrollService? get scrollService {
    if (scrollServiceKey.currentState != null &&
        scrollServiceKey.currentState is AppFlowyScrollService) {
      return scrollServiceKey.currentState! as AppFlowyScrollService;
    }
    return null;
  }
}
