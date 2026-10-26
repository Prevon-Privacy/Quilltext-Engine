// In-app note/folder link navigation — injected by the host app
// so the editor can open a note or folder on link tap without depending
// on app-layer code.
//
// MANDATE: prevon_quilltext_engine sits below the host app. The fork code
// MAY NOT import anything from the host app.
// Instead, the host app implements this abstract and supplies it via
// Provider<NoteLinkNavigator> above the AppFlowyEditor so the fork's
// tap recognizer can request navigation without an upward dependency
// in either direction.

import 'package:flutter/widgets.dart';

abstract class NoteLinkNavigator {
  void openNote(BuildContext context, String noteId);
  void openFolder(BuildContext context, String folderId);
}
