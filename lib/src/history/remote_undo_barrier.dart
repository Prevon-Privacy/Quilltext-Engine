import 'package:prevon_quilltext_engine/src/core/document/path.dart';
import 'package:prevon_quilltext_engine/src/editor/block_component/base_component_keys.dart';
import 'package:prevon_quilltext_engine/src/core/transform/operation.dart';
import 'package:prevon_quilltext_engine/src/history/undo_manager.dart';

/// The undo barrier for edits made by ANOTHER device (the Yjs `trackedOrigins` pattern).
///
/// Undo here is path based and has no notion of who wrote what, so a local Undo that reaches back over a
/// remote edit would rewind the other person's typing, or aim at a block that moved. The rule this file
/// enforces: the history only ever holds LOCAL edits, and every remote edit first removes or re-aims the
/// history items it could disturb. Remote edits are applied with no undo record at all (see
/// `EditorState.apply(isRemote: true)` and `EditorState.applyRemoteBlockText`); the barrier is what keeps
/// the existing items honest.
///
/// What it does, in terms of the paths an item's operations name:
///  * [remoteTextEdited]: a remote text edit of the block now at `path`. Every history operation that
///    changed that block's text is removed (the walk runs newest to oldest and follows the block back
///    through earlier inserts and deletes to find the path it had then). An item whose operations are all
///    text edits loses only the offending operations; an item that also inserted or deleted blocks is
///    removed together with every older item (their paths assumed the removed item's structure). The redo
///    stack is filtered the same way when it holds text edits only, else cleared.
///  * [remoteStructural]: a remote insert or delete of whole blocks. When every history operation is a
///    text or attribute edit the paths all live in one coordinate frame, so they are shifted exactly
///    (operations inside deleted blocks are removed). When the history holds local structural operations
///    the frames differ per item and are not re-derived here: both stacks are cleared (always valid,
///    never wrong; a full tree transform is a later refinement).
extension RemoteUndoBarrier on UndoManager {
  /// One operation of a remote transaction, in order (the entry point `EditorState.apply(isRemote: true)` uses).
  void remoteOperation(Operation op) {
    if (op is InsertOperation || op is DeleteOperation) {
      remoteStructural(op);
    } else if (RemoteUndoBarrier._editsText(op)) {
      remoteTextEdited(op.path);
    }
  }

  /// A remote edit changed the text of the block now at [path].
  void remoteTextEdited(Path path) {
    var cur = List<int>.of(path);
    final items = undoStack.toList();
    var cutBelow =
        false; // an older item must go when a newer structural item went
    for (var i = items.length - 1; i >= 0; i--) {
      final item = items[i];
      if (cutBelow) {
        undoStack.removeItem(item);
        continue;
      }
      var structural = false;
      var touches = false;
      Path? at = cur;
      final doomed = <Operation>[];
      for (final op in item.operations.reversed) {
        if (op is InsertOperation) {
          structural = true;
          if (at != null) {
            final level = op.path.length - 1;
            if (_underSiblings(at, op.path)) {
              final n = op.nodes.length;
              final index = at[level];
              if (index >= op.path.last + n) {
                at = List<int>.of(at)..[level] = index - n;
              } else if (index >= op.path.last) {
                touches = true; // the block was created by this item
                at = null;
              }
            }
          }
        } else if (op is DeleteOperation) {
          structural = true;
          if (at != null && _underSiblings(at, op.path)) {
            final level = op.path.length - 1;
            if (at[level] >= op.path.last) {
              at = List<int>.of(at)..[level] = at[level] + op.nodes.length;
            }
          }
        } else if (_editsText(op)) {
          if (at != null && op.path.equals(at)) {
            touches = true;
            doomed.add(op);
          }
        }
      }
      if (touches) {
        if (structural) {
          undoStack.removeItem(item);
          cutBelow = true;
        } else {
          _dropText(item, doomed.contains);
          if (item.operations.isEmpty) undoStack.removeItem(item);
        }
      }
      if (at == null) {
        cutBelow = true;
      } else {
        cur = at;
      }
    }
    _filterRedoText(path);
  }

  /// A remote insert or delete of whole blocks ([op]).
  void remoteStructural(Operation op) {
    if (_hasStructural(undoStack.toList()) ||
        _hasStructural(redoStack.toList())) {
      undoStack.clear();
      redoStack.clear();
      return;
    }
    final level = op.path.length - 1;
    if (level < 0) return;
    final n = op is InsertOperation
        ? op.nodes.length
        : (op is DeleteOperation ? op.nodes.length : 0);
    if (n == 0) return;
    for (final stack in [undoStack, redoStack]) {
      for (final item in stack.toList()) {
        final kept = <Operation>[];
        for (final h in item.operations) {
          if (!_underSiblings(h.path, op.path)) {
            kept.add(h);
            continue;
          }
          final index = h.path[level];
          if (op is InsertOperation) {
            kept.add(index >= op.path.last
                ? h.copyWith(path: List<int>.of(h.path)..[level] = index + n)
                : h);
          } else if (index >= op.path.last + n) {
            kept.add(
                h.copyWith(path: List<int>.of(h.path)..[level] = index - n));
          } else if (index >= op.path.last) {
            // inside a deleted block: nothing left to undo
          } else {
            kept.add(h);
          }
        }
        item.operations
          ..clear()
          ..addAll(kept);
        if (item.operations.isEmpty) stack.removeItem(item);
      }
    }
  }

  void _filterRedoText(Path path) {
    final items = redoStack.toList();
    if (_hasStructural(items)) {
      redoStack.clear();
      return;
    }
    for (final item in items) {
      _dropText(item, (o) => _editsText(o) && o.path.equals(path));
      if (item.operations.isEmpty) redoStack.removeItem(item);
    }
  }

  /// Typing is recorded as an [UpdateOperation] that sets the whole `delta` attribute (see `Transaction.compose`); a text-delta
  /// operation is the other form. Both are "an edit of this block's text".
  static bool _editsText(Operation o) =>
      o is UpdateTextOperation ||
      (o is UpdateOperation && o.attributes.containsKey(blockComponentDelta));

  /// Removes the text part of every operation of [item] that [test] picks. An update that also set other attributes (a ticked
  /// box) keeps those, so the rest of the edit stays undoable.
  static void _dropText(HistoryItem item, bool Function(Operation) test) {
    final kept = <Operation>[];
    for (final o in item.operations) {
      if (!test(o)) {
        kept.add(o);
      } else if (o is UpdateOperation) {
        final a = {...o.attributes}..remove(blockComponentDelta);
        final old = {...o.oldAttributes}..remove(blockComponentDelta);
        if (a.isNotEmpty || old.isNotEmpty) {
          kept.add(UpdateOperation(o.path, a, old));
        }
      }
    }
    item.operations
      ..clear()
      ..addAll(kept);
  }

  static bool _hasStructural(Iterable<HistoryItem> items) => items.any((i) =>
      i.operations.any((o) => o is InsertOperation || o is DeleteOperation));

  /// True when [p] sits at or below the sibling run that [at] indexes into (same parent, deep enough).
  static bool _underSiblings(Path p, Path at) {
    if (at.isEmpty || p.length < at.length) return false;
    for (var i = 0; i < at.length - 1; i++) {
      if (p[i] != at[i]) return false;
    }
    return true;
  }
}
