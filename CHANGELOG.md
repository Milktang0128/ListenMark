# Changelog

## v0.3.7 - 2026-06-23

### 新功能

- Add PopClip extension support
  - Added a local `dob://run` URL scheme and a bundled PopClip extension with Dob Panel, Read, Explain, Translate, Summarize, and Save actions.
  - Release packaging now emits `Dob-PopClip-0.3.7.popclipextz` and includes it in checksums.

- Add search and link toolbar action
  - Added a toolbar action that opens selected URLs directly, or searches selected plain text.

### 其他

- Prepare Dob 0.3.7 release
  - Updated release script defaults to `0.3.7` / build `37`.

- Retire International references from the READMEs
  - Clarified that Dob now ships as one app whose UI language follows system or in-app language settings.
