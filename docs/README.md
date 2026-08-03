# ShapeScript Docs

Edit documentation in `docs/src` only. The `docs/mac`, `docs/ios`, and versioned `docs/<version>` outputs are generated from the source docs during the release process, so they should not be updated manually for ordinary documentation changes.

Images in `docs/images` are shared by current and older documentation releases, so do not delete or replace an existing image file. Add obsolete image filenames to the `obsoleteImages` array in `ShapeScriptTests/MetadataTests.swift`, and use a version-number suffix for updated images instead of reusing the old filename.
