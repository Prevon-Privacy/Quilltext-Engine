# prevon_quilltext_engine

This is a modified copy of [AppFlowy Editor](https://github.com/AppFlowy-IO/appflowy-editor), a
highly customizable rich-text editor for Flutter, independently maintained as the QuillText
engine for the Sovereign Stack / PIE OS project.

## Why This Fork Exists

This fork applies patches to resolve incompatibilities between AppFlowy Editor's published
dependencies and the Flutter SDK / package versions used by this project. See
`VENDOR_NOTES.md` for the full list of patches and their rationale.

## License

All code in this package is made available under the **Mozilla Public License Version 2.0
(MPL-2.0)**. This satisfies AppFlowy Editor's dual-licensing requirement (MPL-2.0 or
AGPL-3.0): distributing modified MPL-covered files obligates you to make the modified source
of those files available under MPL-2.0, but does not require disclosing any other code,
architecture, or business logic.

The full license text is in `LICENSE`. The AGPL-3.0 text is included alongside the MPL-2.0
text as part of AppFlowy Editor's dual-licensing arrangement.

### Basis for MPL-2.0 election

This election is **confirmed** (as of 2026-09-25) by AppFlowy's own official licensing
FAQ at <https://docs.appflowy.io/docs/documentation/appflowy-editor/licenses>. That page
states directly that AppFlowy Editor — referred to there simply as available under "the
MPL" — may be included in software that is sold commercially, including closed-source
applications, without that use triggering AGPL-3.0 obligations. (An earlier, unanswered
upstream issue had left this ambiguous; the official FAQ is the stronger and now-controlling
source.)

This is documentation of the basis for the decision, not a permanent guarantee: the FAQ is
a live page a maintainer could revise, so re-check the link if the licensing posture is ever
revisited.

Third-party notices for embedded Flutter/Fuchsia code: see `THIRD_PARTY_NOTICES.md`.

## Upstream

- **Upstream:** [AppFlowy-IO/appflowy-editor](https://github.com/AppFlowy-IO/appflowy-editor)
- **Original package:** `appflowy_editor` on [pub.dev](https://pub.dev/packages/appflowy_editor)
- **Upstream issue tracking these patches:**
  https://github.com/AppFlowy-IO/appflowy-editor/issues/1180

## Contributing

This fork is not open to external contributions. If an upstream release of AppFlowy Editor
incorporates the fixes from `VENDOR_NOTES.md`, this vendored copy should be replaced with a
normal pub.dev dependency.