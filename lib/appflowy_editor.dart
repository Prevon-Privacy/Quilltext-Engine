// Compatibility shim — allows existing `package:appflowy_editor/...`
// imports in Pie Notes to keep working unchanged after this package
// was renamed to prevon_quilltext_engine. New code should import
// 'package:prevon_quilltext_engine/prevon_quilltext_engine.dart'
// directly instead. This shim exists so we didn't have to touch files
// with unrelated in-progress work during the initial cutover.
export 'prevon_quilltext_engine.dart';