import 'dart:math';

/// The stable name of one block in a stored note (docs/design/block-ids-spec-2026-11-05.md).
///
/// 12 characters of `[0-9a-z]` (about 60 bits). A block keeps its id when it moves inside a note, when its text is edited, and when a
/// line is split (the head keeps it); a copy, a paste, a template and a new block get a fresh one. The id is written to the stored body
/// only by `toJson(withIds: true)`; every other `toJson` is unchanged.
const int kBlockIdLength = 12;

/// The root `"v"` of a stored body that carries block ids. A body with no `"v"` is the first form (no ids).
const int kStoredBodyVersion = 2;
const String _alphabet = '0123456789abcdefghijklmnopqrstuvwxyz';
final RegExp _blockIdPattern = RegExp(r'^[0-9a-z]{12}$');

/// True when [value] is a well-formed block id.
bool isBlockId(Object? value) =>
    value is String && _blockIdPattern.hasMatch(value);

/// Makes new ids. Replaceable in tests (a deterministic generator); the default reads secure random bytes.
typedef BlockIdGenerator = String Function();

final Random _secure = Random.secure();

String _secureBlockId() {
  final out = StringBuffer();
  for (var i = 0; i < kBlockIdLength; i++) {
    out.write(_alphabet[_secure.nextInt(_alphabet.length)]);
  }
  return out.toString();
}

BlockIdGenerator _generator = _secureBlockId;

/// A fresh block id.
String newBlockId() => _generator();

/// Test hook: replace the generator (pass null to restore the secure one).
void debugSetBlockIdGenerator(BlockIdGenerator? generator) =>
    _generator = generator ?? _secureBlockId;

/// An id derived from [seed] alone: the same seed gives the same id on every device. Used to name the blocks of an old note that has no
/// ids yet, so two devices that open the same unedited note agree. Not a secret and not a hash for security; only for naming.
String blockIdFromSeed(String seed) {
  // Two independent 32-bit FNV-1a runs, joined into 64 bits and written in base 36.
  var a = 0x811c9dc5;
  var b = 0x01000193 ^ 0x9e3779b9;
  for (final unit in seed.codeUnits) {
    a = ((a ^ unit) * 0x01000193) & 0xffffffff;
    b = ((b ^ (unit + 0x9e)) * 0x85ebca6b) & 0xffffffff;
  }
  var n = (a << 32 | b) & 0x7fffffffffffffff;
  final out = List<String>.filled(kBlockIdLength, '0');
  for (var i = kBlockIdLength - 1; i >= 0; i--) {
    out[i] = _alphabet[n % 36];
    n ~/= 36;
  }
  return out.join();
}
