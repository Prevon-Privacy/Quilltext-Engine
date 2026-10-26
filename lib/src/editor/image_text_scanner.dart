// Reading the words in a picture — injected by the host app.
//
// Same decoupling as [ImageActions]: the fork owns the hold-menu choice and the document edit
// (it inserts what comes back), the host owns everything with a model, a download, a result
// sheet and the person's words. With no provider the picture menu has no "Scan text" row.

import 'package:flutter/widgets.dart';

abstract interface class ImageTextScanner {
  /// Reads the text in the picture [src] (the block's `url`) and lets the person choose what to
  /// do with it. Returns the text to add under the picture, or null (cancelled, nothing found,
  /// the picture could not be read, the model is not installed).
  Future<String?> scanText(BuildContext context, String src);
}
