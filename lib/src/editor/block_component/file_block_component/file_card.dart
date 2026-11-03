import 'package:flutter/material.dart';
import 'package:prevon_quilltext_engine/src/editor/block_component/file_block_component/file_block_component.dart'
    show fileDetailLine, fileIconFor, fileTintFor, FileStatusChip;
import 'package:prevon_quilltext_engine/src/editor/block_component/file_block_component/file_card_status.dart';
import 'package:prevon_quilltext_engine/src/editor/file_actions.dart'
    show FileViewRequest;

/// The drawn file card: a tinted type tile, the name (shortened in the middle so the extension
/// stays), "TYPE · size", a status chip and a "more" button. Gestures belong to the block.
class FileCard extends StatelessWidget {
  const FileCard({
    super.key,
    required this.file,
    this.status = const FileCardStatus.ready(),
    this.words = const FileCardWords(),
    this.pressed = false,
    this.onMore,
  });

  final FileViewRequest file;
  final FileCardStatus status;
  final FileCardWords words;
  final bool pressed;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final family = fileFamilyOf(file.mime, file.name);
    final tint = fileTintFor(family, scheme);
    final cleaned = words.cleanName(file.name);
    final name = cleaned.isEmpty ? '—' : cleaned;
    final shown = middleEllipsis(name, 44);
    final detail = fileDetailLine(file);
    // In a narrow slot (a card inside a folded block on a small screen) the tile, the gap and the
    // "more" button shrink so the row still fits; the text column takes whatever is left.
    return LayoutBuilder(builder: (context, c) {
      final narrow = c.maxWidth < 190;
      final tile = narrow ? 32.0 : 44.0;
      final gap = narrow ? 8.0 : 12.0;
      final moreWidth = narrow ? 28.0 : 40.0;
      return _card(context, scheme, theme, tint, shown, detail, cleaned,
          tile: tile, gap: gap, moreWidth: moreWidth);
    });
  }

  Widget _card(
    BuildContext context,
    ColorScheme scheme,
    ThemeData theme,
    Color tint,
    String shown,
    String detail,
    String cleaned, {
    required double tile,
    required double gap,
    required double moreWidth,
  }) {
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest
            .withValues(alpha: pressed ? 0.8 : 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: tile,
            height: tile,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(fileIconFor(file.mime, cleaned), color: tint),
          ),
          SizedBox(width: gap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  shown,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge,
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // A link to a file that lives in Files wears a small link mark so it never looks like a second copy.
                    if (file.via != null)
                      Icon(Icons.link_rounded,
                          size: 14, color: scheme.onSurfaceVariant),
                    if (detail.isNotEmpty)
                      Text(
                        detail,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    if (status.phase != FileCardPhase.ready ||
                        status.label.isNotEmpty)
                      FileStatusChip(status: status, words: words),
                  ],
                ),
              ],
            ),
          ),
          if (onMore != null)
            Semantics(
              button: true,
              label: words.moreActions,
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onMore,
                child: SizedBox(
                  width: moreWidth,
                  height: 44,
                  child: Icon(Icons.more_horiz,
                      size: 20, color: scheme.onSurfaceVariant),
                ),
              ),
            )
          else
            const SizedBox(width: 8),
        ],
      ),
    );
  }
}

