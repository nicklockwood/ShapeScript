# macOS release signing

The release workflow uses manual Developer ID signing. In addition to the
certificate and notarization secrets, configure these repository Actions secrets:

| Secret | Profile App ID |
| --- | --- |
| `VIEWER_PROVISIONING_PROFILE_BASE64` | `com.charcoaldesign.ShapeScriptMacViewer` |
| `PREVIEW_PROVISIONING_PROFILE_BASE64` | `com.charcoaldesign.ShapeScriptMacViewer.Preview` |

Each secret must contain a base64-encoded Developer ID provisioning profile for
team `8VQKF583ED`, using the Developer ID Application certificate supplied in
`DEVELOPER_ID_CERTIFICATE_BASE64`. Both App IDs and profiles must authorize the
App Group `group.8VQKF583ED.com.charcoaldesign.ShapeScript`. Development and
Mac App Store profiles are not suitable for this workflow.

Create or regenerate both profiles in the Apple Developer account, download
them, then encode each file with `base64 -i /path/to/profile.provisionprofile`.
Update the secrets when the profiles expire or the signing certificate changes.

The workflow validates the team, App ID, expiration and App Groups, installs the
profiles, and assigns their UUIDs to the Viewer and Preview Release configurations
in the checked-out project before archiving. Framework targets are left unchanged.
Normal local builds continue to use automatic signing.

This assignment also supports release tags created before the target-specific
profile settings were added. Run the updated workflow using **Run workflow** on
`main`, supplying the existing release tag as the `tag` input. The app source
still comes from that tag; only its signing configuration is adjusted on the runner.
