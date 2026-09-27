import 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart';

final codeMobileToolbarItem = MobileToolbarItem.action(
  itemIconBuilder: (context, __, ___) => AFMobileIcon(
    afMobileIcons: AFMobileIcons.code,
    color: MobileToolbarTheme.of(context).iconColor,
  ),
  actionHandler: (_, editorState) => editorState.toggleAttribute(
    AppFlowyRichTextKeys.code,
  ),
);
