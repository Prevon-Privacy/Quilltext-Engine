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
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(fileIconFor(file.mime, cleaned), color: tint),
          ),
          const SizedBox(width: 12),
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
                  width: 40,
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

