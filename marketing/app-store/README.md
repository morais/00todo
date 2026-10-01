# 00Todo App Store 1.0 preparation

The editable English (US) listing copy is in `metadata.json`. The live
marketing, support, and privacy URLs are `https://00todo.com/`,
`https://00todo.com/support`, and `https://00todo.com/privacy`.

The six uploaded App Store screenshots are generated from simulator captures,
not mock app screens. Reproduce them with `marketing/screenshots/capture-ios.sh
iphone-6.9` and `marketing/screenshots/capture-ios.sh ipad`, then run:

```
ASC_KEY_PATH=/path/to/AppStoreConnect-key.p8 \
  python3 marketing/app-store/upload-screenshots.py --app-id APP_STORE_APP_ID
```

The uploader verifies the capture/composition checksums and image dimensions,
then skips screenshots already uploaded with the same filename and MD5. It
never submits the app for review. The iPhone set uses `APP_IPHONE_67` (Apple's
API name for the 6.9-inch display); iPad uses `APP_IPAD_PRO_3GEN_129` for the
13-inch display.

## Suggested App Review notes

00Todo is a personal task and project manager. On launch, tap Sign in with
Apple. An Apple account gets its own empty workspace; no invitation or paid
account is required. Create a task with a future start date to see it under
Upcoming rather than Available. Create a project to add subtasks and use it as
a shopping list. Settings contains account deletion and MCP connection
management. The Home Screen widget shows available tasks. To test the share
extension, share a web link or text from another app and choose 00Todo. After
sign-in, edits are saved locally when offline and sync after reconnecting.
Apple Intelligence-assisted Quick Add and share-title suggestions are optional
and only run on supported devices with the model available; manual entry works
without them. Voice input needs microphone and speech recognition permission.

Do not put a review account password, API token, or private task contents in
this repository. Supply any requested test login details only through App
Store Connect's secure review fields.

## Before Submit for Review

- Refresh the share-extension distribution profile with the App Group, upload
  a release archive containing the share extension and privacy manifests,
  and select that processed build for version 1.0.
- Complete and publish the App Privacy questionnaire in App Store Connect.
  The source audit indicates email address (when Apple supplies one), account
  ID, and task/project content are collected, linked to the user, for app
  functionality, with no tracking. Verify this against production operations
  before publishing the answers.
- Add an App Review contact phone and verify the reviewer sign-in path.
- Choose price and distribution regions; verify the current agreements and
  availability in App Store Connect.
- Confirm the legal content-rights declaration with the account holder.
- The version is configured for **manual release after approval**. Submitting
  it for review must still be a separate, explicit step.
