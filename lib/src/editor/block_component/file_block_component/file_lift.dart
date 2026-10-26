import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

/// Hold a block that is one solid card (a file, a sketch) on a phone to pick it up. Keep the finger down and drag to
/// move it among its siblings (the same drop line, edge auto-scroll and tick as
/// the image lift and the margin hold, all from [BlockReorderSession]); let go
/// without moving and the caller's own menu opens instead, so one hold
/// covers "move" and "everything else". The drop is ONE undoable edit.
class BlockHoldLift {
  BlockHoldLift._(this._editorState, this._node, this._session, this._start,
      this._entry, this._dy);

  /// How far (dp) the finger may wander before a hold counts as a drag.
  static const double moveSlop = 14;

  final EditorState _editorState;
  final Node _node;
  final BlockReorderSession _session;
  final Offset _start;
  final OverlayEntry _entry;
  final ValueNotifier<double> _dy;
  double _farthest = 0;
  bool _done = false;

  /// Starts a lift for [node] held at global [offset]; null when it cannot
  /// move (read-only note, no overlay, no laid-out row). [glyph] is what a
  /// host-registered block shows while it is lifted.
  static BlockHoldLift? begin(
    BuildContext context,
    EditorState editorState,
    Node node,
    Offset offset, {
    IconData? glyph,
  }) {
    if (!editorState.editable) return null;
    final rowBox = node.key.currentContext?.findRenderObject();
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (rowBox is! RenderBox || !rowBox.attached || !rowBox.hasSize) {
      return null;
    }
    if (overlay == null) return null;

    HapticFeedback.mediumImpact();
    final session = BlockReorderSession(editorState, node)..start();
    final top = rowBox.localToGlobal(Offset.zero);
    final dy = ValueNotifier<double>(0);
    final entry = OverlayEntry(
      builder: (_) => ValueListenableBuilder<double>(
        valueListenable: dy,
        builder: (_, dy, __) => Positioned(
          left: top.dx,
          top: top.dy + dy,
          child: IgnorePointer(
            child: ReorderDragFeedback(
                node: node, editorState: editorState, glyph: glyph),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    return BlockHoldLift._(editorState, node, session, offset, entry, dy);
  }

  bool get moved => _farthest >= moveSlop;

  void update(Offset global) {
    if (_done) return;
    _farthest = math.max(_farthest, (global - _start).distance);
    if (!moved) return;
    _dy.value = global.dy - _start.dy;
    _session.update(global);
  }

  /// The finger lifted. Returns true when it moved (a drop was attempted).
  bool end() {
    if (_done) return false;
    final wasMoved = moved;
    _finish(dropped: wasMoved);
    return wasMoved;
  }

  /// The gesture was taken away: put the block back.
  void cancel() => _finish(dropped: false);

  void _finish({required bool dropped}) {
    if (_done) return;
    _done = true;
    _session.finish(dropped: dropped);
    _entry.remove();
    _entry.dispose();
    _dy.dispose();
    if (dropped && _node.parent != null) {
      final path = _node.path;
      _editorState.selection = Selection(
        start: Position(path: path, offset: 0),
        end: Position(path: path, offset: 1),
      );
      HapticFeedback.lightImpact();
    }
  }
}
