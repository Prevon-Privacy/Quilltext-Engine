import 'dart:typed_data';

import 'package:prevon_quilltext_engine/src/editor/util/file_picker/file_picker_service.dart';
import 'package:file_picker/file_picker.dart' as fp;

class FilePicker implements FilePickerService {
  @override
  Future<String?> getDirectoryPath({String? title}) {
    return fp.FilePicker.getDirectoryPath(
      dialogTitle: title,
    );
  }

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    fp.FileType type = fp.FileType.any,
    List<String>? allowedExtensions,
    Function(fp.FilePickerStatus p1)? onFileLoading,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
  }) async {
    // file_picker 12.x: `pickFiles` returns `List<PlatformFile>` directly (the
    // upstream `FilePickerResult` wrapper is gone), and byte data is fetched
    // lazily via `PlatformFile.readAsBytes()` rather than the now-deprecated
    // `withData` / `withReadStream` flags. `allowMultiple` is soft-deprecated in
    // favour of `pickFile`, but it is still the only knob on `pickFiles` and
    // remains functional — kept with an explicit ignore.
    final files = await fp.FilePicker.pickFiles(
      dialogTitle: dialogTitle,
      initialDirectory: initialDirectory,
      type: type,
      allowedExtensions: allowedExtensions,
      onFileLoading: onFileLoading,
      // ignore: deprecated_member_use
      allowMultiple: allowMultiple,
    );
     // file_picker 12.x: fp.FilePicker.pickFiles() returns List<PlatformFile> (empty
    // list on cancel, not null). Wrap the list in the vendor's FilePickerResult to
    // satisfy the FilePickerService interface contract (Future<FilePickerResult?>).
    if (files.isEmpty) return null;
    return FilePickerResult(files);
  }

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    fp.FileType type = fp.FileType.any,
    List<String>? allowedExtensions,
    bool lockParentWindow = false,
    Uint8List? bytes,
  }) async {
    // file_picker 12.0.0 saveFile requires required Uint8List bytes.
    // The FilePickerService interface does not carry bytes, so this
    // implementation is a stub. The real fp.FilePicker.saveFile() would be:
    //   return fp.FilePicker.saveFile(
    //     dialogTitle: dialogTitle,
    //     fileName: fileName ?? '',
    //     bytes: bytes ?? Uint8List(0),
    //     initialDirectory: initialDirectory,
    //     type: type,
    //     allowedExtensions: allowedExtensions,
    //     lockParentWindow: lockParentWindow,
    //   ).then((uri) => uri?.toFilePath());
    // For now, return null since no caller in the vendor lib currently
    // invokes saveFile — the method body is dead code in the current tree.
    return null;
  }
}