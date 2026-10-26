import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'default_text_span_decorator_for_attribute.dart' show noteLinkTextStyle;

/// Support mobile platform
///   - customize the href text span
TextSpan mobileTextSpanDecoratorForAttribute(
  BuildContext context,
  Node node,
  int index,
  TextInsert text,
  TextSpan before,
  TextSpan after,
) {
  final attributes = text.attributes;
  if (attributes == null) {
    return before;
  }
  // In-note note/folder link (the [[ … ]] picker, or "Link to note" toolbar
  // action). Mirror of the desktop decorator's branch: without it, a delta
  // carrying a `noteLink`/`folderLink` attribute renders as plain,
  // non-interactive text on touch platforms — reachable because
  // `buildEditorStyle` selects `EditorStyle.mobile` on iOS/Android, so the
  // mobile decorator is the active one there. Resolved via the abstract
  // NoteLinkNavigator the host app supplies via Provider<NoteLinkNavigator>
  // above the AppFlowyEditor; degrade to plain text when it is not wired.
  final noteLinkId = attributes[AppFlowyRichTextKeys.noteLink] as String?;
  final folderLinkId = attributes[AppFlowyRichTextKeys.folderLink] as String?;
  final appLinkTarget = attributes[AppFlowyRichTextKeys.appLink] as String?;
  if (appLinkTarget != null && noteLinkId == null && folderLinkId == null) {
    NoteLinkNavigator? navigator;
    try {
      navigator = context.read<NoteLinkNavigator>();
    } on ProviderNotFoundException {
      navigator = null;
    }
    // A host whose navigator cannot open app links shows plain text.
    if (navigator is! AppLinkNavigator) return before;
    final AppLinkNavigator appNavigator = navigator as AppLinkNavigator;
    return TextSpan(
      style: noteLinkTextStyle(context, before.style),
      text: text.text,
      recognizer: TapGestureRecognizer()
        ..onTap = () => appNavigator.openApp(context, appLinkTarget),
    );
  }
  if (noteLinkId != null || folderLinkId != null) {
    NoteLinkNavigator? navigator;
    try {
      navigator = context.read<NoteLinkNavigator>();
    } on ProviderNotFoundException {
      navigator = null;
    }
    if (navigator == null) {
      return before;
    }
    final resolvedNavigator = navigator;
    final tapGestureRecognizer = TapGestureRecognizer()
      ..onTap = () => noteLinkId != null
          ? resolvedNavigator.openNote(context, noteLinkId)
          : resolvedNavigator.openFolder(context, folderLinkId!);
    return TextSpan(
      style: noteLinkTextStyle(context, before.style),
      text: text.text,
      recognizer: tapGestureRecognizer,
    );
  }

  // Web links open on tap and offer "Remove link" on long-press from the
  // selection layer (openNoteLinkAtPosition / showLinkRemoveMenuAtPosition).
  return before;
}

class LinkEditForm extends StatefulWidget {
  const LinkEditForm({
    super.key,
    required this.node,
    required this.index,
    required this.hrefText,
    required this.hrefAddress,
    required this.editorState,
    required this.selection,
  });
  final Node node;
  final int index;
  final String hrefText;
  final String hrefAddress;
  final EditorState editorState;
  final Selection selection;

  @override
  State<LinkEditForm> createState() => _LinkEditFormState();
}

class _LinkEditFormState extends State<LinkEditForm> {
  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    var hrefAddressTextEditingController =
        TextEditingController(text: widget.hrefAddress);
    var hrefTextTextEditingController =
        TextEditingController(text: widget.hrefText);

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            key: const Key('Text TextFormField'),
            enableIMEPersonalizedLearning: false,
            autofocus: true,
            controller: hrefTextTextEditingController,
            keyboardType: TextInputType.text,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return AppFlowyEditorL10n.current.linkTextHint;
              }
              return null;
            },
            decoration: InputDecoration(
              hintText: AppFlowyEditorL10n.current.linkText,
              suffixIcon: IconButton(
                icon: const Icon(
                  Icons.clear_rounded,
                  size: 16,
                ),
                onPressed: hrefTextTextEditingController.clear,
              ),
            ),
          ),
          TextFormField(
            key: const Key('Url TextFormField'),
            enableIMEPersonalizedLearning: false,
            controller: hrefAddressTextEditingController,
            keyboardType: TextInputType.url,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return AppFlowyEditorL10n.current.linkAddressHint;
              }
              return null;
            },
            decoration: InputDecoration(
              hintText: AppFlowyEditorL10n.current.urlHint,
              suffixIcon: IconButton(
                icon: const Icon(
                  Icons.clear_rounded,
                  size: 16,
                ),
                onPressed: hrefAddressTextEditingController.clear,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                child: Text(
                  AppFlowyEditorL10n.current.removeLink,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onPressed: () async {
                  final transaction = widget.editorState.transaction
                    ..formatText(
                      widget.node,
                      widget.index,
                      widget.hrefText.length,
                      {BuiltInAttributeKey.href: null},
                    );
                  await widget.editorState.apply(transaction).whenComplete(() {
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  });
                },
              ),
              TextButton(
                style: TextButton.styleFrom(
                  textStyle: Theme.of(context).textTheme.labelLarge,
                ),
                child: Text(AppFlowyEditorL10n.current.done),
                onPressed: () async {
                  if (_formKey.currentState!.validate()) {
                    final bool textChanged =
                        hrefTextTextEditingController.text != widget.hrefText;
                    final bool addressChanged =
                        hrefAddressTextEditingController.text !=
                            widget.hrefAddress;

                    if (textChanged && addressChanged) {
                      final transaction = widget.editorState.transaction
                        ..replaceText(
                          widget.node,
                          widget.index,
                          widget.hrefText.length,
                          hrefTextTextEditingController.text,
                          attributes: {
                            AppFlowyRichTextKeys.href:
                                hrefAddressTextEditingController.text,
                          },
                        );
                      await widget.editorState.apply(transaction).whenComplete(
                        () {
                          if (context.mounted) {
                            Navigator.of(context).pop();
                          }
                        },
                      );
                    } else if (textChanged && !addressChanged) {
                      final transaction = widget.editorState.transaction
                        ..replaceText(
                          widget.node,
                          widget.index,
                          widget.hrefText.length,
                          hrefTextTextEditingController.text,
                        );
                      await widget.editorState.apply(transaction).whenComplete(
                        () {
                          if (context.mounted) {
                            Navigator.of(context).pop();
                          }
                        },
                      );
                    } else if (!textChanged && addressChanged) {
                      await widget.editorState.formatDelta(widget.selection, {
                        AppFlowyRichTextKeys.href:
                            hrefAddressTextEditingController.value.text,
                      }).whenComplete(() {
                        if (context.mounted) {
                          Navigator.of(context).pop();
                        }
                      });
                    } else {
                      Navigator.of(context).pop();
                    }
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
