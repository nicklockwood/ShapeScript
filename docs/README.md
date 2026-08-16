# ShapeScript Docs

Edit documentation in `docs/src` only. The `docs/mac`, `docs/ios`, and `docs/<version>` outputs are generated from the source docs during the release process, and the iOS Viewer bundles offline HTML generated into `Viewer/iOS/Documentation` by the iOS app build. These outputs should not be updated manually for ordinary documentation changes.

Images in `docs/images` are shared by current and older documentation releases, so do not delete or replace an existing image file. Add obsolete image filenames to the `obsoleteImages` array in `ShapeScriptTests/MetadataTests.swift`, and use a version-number suffix for updated images instead of reusing the old filename.

## Patching the Current Release Docs

If you need to retrospectively patch the docs for the current released version, edit `docs/src` first, then regenerate the public docs and current versioned folder from the updated source:

```bash
SHAPESCRIPT_UPDATE_RELEASE_DOCS=1 swift test --filter MetadataTests/testExportHelp
```

This updates `docs/mac`, `docs/ios`, and `docs/<current-version>` without running the full release script. Use this only when you intentionally want the already-published release docs to change.

Before committing, check that the generated public docs do not contain unresolved version placeholders:

```bash
rg "{{SHAPESCRIPT_DOCS_VERSION}}" docs/mac docs/ios docs/<current-version>
```

The command should print no matches. Then run the metadata tests:

```bash
swift test --filter MetadataTests
```

The iOS Viewer bundles offline HTML generated from `docs/ios`. It is regenerated automatically by the iOS app build, or manually with:

```bash
swift run helpbuilder
```
