import 'package:prevon_quilltext_engine/src/core/document/node_iterator.dart';
import 'package:prevon_quilltext_engine/src/core/document/path.dart';
import 'package:prevon_quilltext_engine/src/core/document/text_delta.dart';
import 'package:prevon_quilltext_engine/src/core/location/position.dart';
import 'package:prevon_quilltext_engine/src/core/location/selection.dart';
import 'package:prevon_quilltext_engine/src/core/document/node.dart';
import 'package:prevon_quilltext_engine/src/editor_state.dart';
import 'package:prevon_quilltext_engine/src/history/remote_undo_barrier.dart';

/// What [EditorStateRemoteBlockText.applyRemoteBlockText] did.
enum RemoteBlockResult {
  /// The block's text changed.
  applied,

  /// Refused because the block holds the caret, a selection or an active IME composition. Nothing changed; the
  /// caller queues the edit and tries again when focus leaves the block.
  held,

  /// No block with that id (or it carries no text).
  missing,

  /// The delta does not fit the block's current text, or the editor is not editable. Nothing changed.
  invalid,
}

/// Maps a selection (start, end offsets inside the block, BEFORE the edit) to its place AFTER the edit.
typedef RemoteSelectionMapper = ({int start, int end}) Function(
    int start, int end);

extension EditorStateRemoteBlockText on EditorState {
  /// The block whose stable id is [blockId] (docs/design/block-ids-spec-2026-11-05.md), or null.
  Node? nodeByBlockId(String blockId) {
    final it = NodeIterator(document: document, startNode: document.root);
    while (it.moveNext()) {
      if (it.current.id == blockId) return it.current;
    }
    return null;
  }

  /// Applies ANOTHER device's change to ONE block, found by [blockId]: [delta] (retain/insert/delete, attributes kept
  /// exactly as given; a plain retain keeps the local formatting) is composed onto the block's current text.
  ///
  /// The contract, in the order it is enforced:
  ///  1. Never moves the person's caret by surprise: when the selection touches the block (a caret, or a range that
  ///     covers it) or [imeComposing] is true and the selection touches it, nothing is applied and [RemoteBlockResult.held]
  ///     is returned, so the caller can queue the edit. [force] applies it anyway and maps the selection through the
  ///     edit with [mapSelection] (default: offsets clamped to the new length); an IME composition is never forced.
  ///  2. Never nulls the selection; a selection in another block is left untouched, byte for byte.
  ///  3. Is not a local edit: it records no undo, and it does not fire [transactionStream] (so autosave, the writing
  ///     journal and any "local edit" listener stay quiet).
  ///  4. Applies the UNDO BARRIER ([RemoteUndoBarrier], the Yjs trackedOrigins pattern): history operations that changed
  ///     this block's text are removed, so Undo can never rewind the remote edit or aim at the wrong block.
  RemoteBlockResult applyRemoteBlockText(
    String blockId,
    Delta delta, {
    bool imeComposing = false,
    bool force = false,
    RemoteSelectionMapper? mapSelection,
  }) {
    if (!editable || isDisposed) return RemoteBlockResult.invalid;
    final node = nodeByBlockId(blockId);
    final before = node?.delta;
    if (node == null || before == null) return RemoteBlockResult.missing;
    final path = node.path;

    final sel = selection;
    final touches = sel != null && _selectionTouches(sel, path);
    if (touches && (imeComposing || !force)) return RemoteBlockResult.held;
    if (imeComposing && sel == null) return RemoteBlockResult.held;

    var needed = 0;
    for (final op in delta) {
      if (op is TextRetain || op is TextDelete) needed += op.length;
    }
    if (needed > before.length) return RemoteBlockResult.invalid;

    if (!document.updateText(path, delta)) return RemoteBlockResult.invalid;
    undoManager.remoteTextEdited(path);
    undoManager.redoStack; // (the barrier filtered it)

    if (touches) {
      final newLength = node.delta?.length ?? 0;
      selection = _mappedSelection(sel, path, newLength, mapSelection);
    }
    return RemoteBlockResult.applied;
  }

  bool _selectionTouches(Selection sel, Path path) {
    final n = sel.normalized;
    return n.start.path <= path && path <= n.end.path;
  }

  Selection _mappedSelection(
      Selection sel, Path path, int newLength, RemoteSelectionMapper? mapper) {
    final n = sel.normalized;
    final inStart = n.start.path.equals(path);
    final inEnd = n.end.path.equals(path);
    int clamp(int v) => v < 0 ? 0 : (v > newLength ? newLength : v);
    var s = inStart ? n.start.offset : 0;
    var e = inEnd ? n.end.offset : 0;
    if (mapper != null) {
      if (inStart && inEnd) {
        final m = mapper(s, e);
        s = m.start;
        e = m.end;
      } else if (inStart) {
        s = mapper(s, s).start;
      } else if (inEnd) {
        e = mapper(e, e).start;
      }
    }
    final start =
        inStart ? Position(path: n.start.path, offset: clamp(s)) : n.start;
    final end = inEnd ? Position(path: n.end.path, offset: clamp(e)) : n.end;
    // `isForward` is this engine's name for a selection dragged backwards (start after end): keep its direction.
    return sel.isForward
        ? Selection(start: end, end: start)
        : Selection(start: start, end: end);
  }
}
