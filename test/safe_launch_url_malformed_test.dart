import 'package:flutter_test/flutter_test.dart';
import 'package:prevon_quilltext_engine/src/extensions/url_launcher_extension.dart';

void main() {
  test('malformed href fails closed without throwing', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    expect(await safeLaunchUrl('http://[bad'), isFalse);
    expect(await safeLaunchUrl('http://%zz:xx/'), isFalse);
  });
}
