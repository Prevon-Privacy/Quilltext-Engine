# Third-Party Notices

This package is a modified copy of [AppFlowy Editor](https://github.com/AppFlowy-IO/appflowy-editor).
The dual AGPL-3.0 / MPL-2.0 terms that cover AppFlowy Editor are in the root
[`LICENSE`](LICENSE) file. This fork elects the **MPL-2.0** half of that dual license; the
basis for that election — AppFlowy's official licensing FAQ confirming MPL-licensed use in
commercial/closed-source applications is permitted — is documented in `README.md`
("Basis for MPL-2.0 election"), confirmed as of 2026-09-25.

Some files under `lib/src/flutter/` are copied from the Flutter SDK / Fuchsia
projects and carry their own copyright headers. Those files are **not** covered
by the AppFlowy dual license; they remain under the BSD-3-Clause license
reproduced below.

## Files carrying third-party BSD headers

The following files carry a `Copyright 2014 The Flutter Authors` header:

- `lib/src/flutter/scrollable_helpers.dart`
- `lib/src/flutter/overlay.dart`

The following files carry a `Copyright 2019 The Fuchsia Authors` header:

- `lib/src/flutter/scrollable_positioned_list/scrollable_positioned_list.dart`
- `lib/src/flutter/scrollable_positioned_list/src/element_registry.dart`
- `lib/src/flutter/scrollable_positioned_list/src/scrollable_positioned_list.dart`
- `lib/src/flutter/scrollable_positioned_list/src/positioned_list.dart`
- `lib/src/flutter/scrollable_positioned_list/src/item_positions_listener.dart`
- `lib/src/flutter/scrollable_positioned_list/src/viewport.dart`
- `lib/src/flutter/scrollable_positioned_list/src/post_mount_callback.dart`
- `lib/src/flutter/scrollable_positioned_list/src/item_positions_notifier.dart`
- `lib/src/flutter/scrollable_positioned_list/src/scroll_view.dart`

## BSD-3-Clause license text

The BSD-3-Clause text below is reproduced verbatim from the Flutter SDK's
`LICENSE` file (the license the Flutter Authors apply to Flutter-authored code),
and it is the same license the Fuchsia Authors apply to the
`scrollable_positioned_list` sources above.

```
Copyright 2014 The Flutter Authors. All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.
    * Neither the name of Google Inc. nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```
