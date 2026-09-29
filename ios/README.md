# 00Todo for iOS

The main screen is one list of tasks and projects. A project opens to its subtasks; there is no special Inbox project. Projects can have notes and be completed, just like tasks. Available hides future-start projects and tasks; Upcoming reveals them in Next 7 days, Next 2 weeks, Next 30 days, and Future groups based on their effective start. Expand projects shows project tasks as flat rows with their project name, hiding the project row when it has visible tasks in that view; it is on by default. A project's start also controls when its tasks appear. The larger 00Todo title stays inline with Settings, Quick Add, and Add, including in landscape, where the list uses a smaller top margin. Add opens one creation form with Task selected by default in its title menu, and the title field focused. Projects can include initial subtasks, while tasks can optionally belong to a project. Projects and tasks each have optional, independent start and due dates. A start date can also have an optional local start time; an item scheduled for later today remains Upcoming until that time.

SwiftUI app for iOS and iPadOS 27+. The universal target includes both iPhone and iPad; the iPad uses the same task-list layout. Requires Xcode and XcodeGen. `project.yml.sample` is committed; real signing, bundle ID, and server URL go in ignored `project.yml`.

```sh
cp project.yml.sample project.yml
xcodegen generate
open ZeroZeroTodo.xcodeproj
```

Before a device or TestFlight build, replace `PRODUCT_BUNDLE_IDENTIFIER` with the Apple App ID, set `DEVELOPMENT_TEAM`, and set `TodoServerBaseURL` to `https://api.00todo.com`. The App ID must have Sign in with Apple enabled and its provisioning profile must carry that capability. The `.sample` intentionally retains example values.

The App Store icon, in-app mark, and light/dark wordmarks come from the 00Widget sibling identity. The chart-shaped mouth is replaced with three checked tasks. Run `python3 docs/brand/generate.py` from the repository root to regenerate the committed assets; see [brand guidance](../docs/brand/README.md). The user-visible app name is `00Todo`; the lower-case bundle ID and API hostname are stable technical identifiers.

The app uses native Sign in with Apple. It passes Apple's identity token, one-use code, and a nonce to the Worker. The resulting app session is stored in Keychain. A per-tenant snapshot is stored in Application Support, shown immediately, and refreshed on launch, foreground, and pull to refresh. Completion updates optimistically; other edits need a network connection. Settings offers sign-out, re-authenticated account deletion, and MCP Connections with per-client setup steps for Claude, ChatGPT, Manus, OpenCode, Codex, and other remote MCP clients, plus connection revocation.

Quick Add uses Apple's on-device Foundation Models to draft a task or a project with subtasks from a short request such as “Shopping list: milk, eggs, bread.” The microphone icon sits inline with the request field and transcribes speech on-device when the current language supports local recognition; microphone and speech permissions are requested on first use. A draft appears automatically after a brief pause in typing. A short pause after recognized speech ends recording and makes a draft; tapping the microphone again does the same. An unspecified start date and time stay empty, including when only a due date was requested. The draft is editable and nothing is saved until Add is tapped. The request and generated draft stay on the device during inference; only approved items are sent to the 00Todo API. The model needs an Apple Intelligence-capable device with Apple Intelligence enabled and the model downloaded. When unavailable, manual task and project creation still works. Project and subtasks are saved in one atomic server batch. The app icon's Home Screen quick actions offer Speak to 00Todo and Quick Add.

The small and medium 00Todo Quick Add Home Screen widgets provide Speak and Type links into the app. The small widget uses icons only; the medium widget shows labels. Widgets cannot host a text field or record audio themselves, so these links open the app's Quick Add sheet; Speak begins listening there. The widget is a separate extension bundle, `com.00todo.app.widgets` in the production project or `com.example.zerozerotodo.widgets` in the sample. It needs its own App ID and App Store provisioning profile for TestFlight distribution. It does not need an App Group or account tokens because it displays no private task data.

For a simulator compile without signing:

```sh
xcodegen generate --spec project.yml.sample
xcodebuild -project ZeroZeroTodo.xcodeproj -scheme ZeroZeroTodo \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

For internal TestFlight distribution, archive and upload with the configured App Store Connect API key. Once Apple's build processing is complete, `scripts/assign-testflight.py --app-id APP_ID --group-id GROUP_ID --build BUILD_NUMBER` adds that exact build to an existing internal group and verifies the relationship. Set `ASC_KEY_PATH` to the App Store Connect key when `~/.appstoreconnect/private_keys` contains more than one key; the Sign in with Apple key is not interchangeable.
