# Budget Guard Native App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Homebrew + SwiftBar plugin with a downloadable macOS menu bar app whose first-launch assistant takes a non-technical person from double-click to seeing their weekly Claude usage, with no terminal step.

**Architecture:** One Swift package in `app/`. `BudgetGuardCore` is pure, UI-free logic (JSON parsing, organization choice, color level, alert re-arming, French copy, menu model) and carries all unit tests. `BudgetGuardApp` is the AppKit/SwiftUI executable: a hidden `WKWebView` that holds the claude.ai session and calls the usage endpoint from inside the page, a login window derived from the successful spike, the status item, the onboarding assistant, notifications, login item and Sparkle updates. A shell script assembles, signs and packages the universal `.app` into a DMG.

**Tech Stack:** Swift 6 (Xcode 27.2), SwiftPM, AppKit + SwiftUI, WebKit, UserNotifications, ServiceManagement, Sparkle 2 (SPM), XCTest. No other dependencies.

**Spec:** `docs/superpowers/specs/2026-11-22-budget-guard-app-design.md` (approved 2026-11-24). Login reference code that worked against the real account: `docs/superpowers/spikes/2026-11-24-live-login-spike.swift`.

## Global Constraints

- macOS 13.0 minimum; universal binary (arm64 + x86_64).
- Menu bar only: `LSUIElement = true`, no Dock icon.
- Every user-facing string in French. Copy fixed by this plan is quoted verbatim in the tasks.
- Menu bar shows an icon followed by the percentage (`29 %`, with a narrow no-break space U+202F before `%`), colored by level. The `CC:` label is gone.
- Color levels, copied from the current plugin: < 70 normal (green `#7FD99A`), 70–89 warning (orange `#FFB866`), ≥ 90 critical (red `#FF8080`).
- Alerts at 80 % and 95 %: one per threshold, re-armed when the percentage drops below that threshold; state persisted across restarts.
- Refresh every 120 s. On failure keep the last known value, greyed.
- Usage source of truth: `GET https://claude.ai/api/organizations` then `GET https://claude.ai/api/organizations/{uuid}/usage`, executed inside the claude.ai page (no cookie extraction). Organization = first whose `capabilities` contains `"chat"`, else first.
- `seven_day.utilization` is already a percentage (0–100, may be fractional); `resets_at` is ISO 8601 with fractional seconds; `five_hour` is null and must not be required.
- Never send a message to the API to measure usage (the plugin's 1-token POST is dropped).
- Claude Code token fallback: read Keychain item `Claude Code-credentials` only; never refresh the token; header `anthropic-beta: oauth-2025-04-20`; endpoint `GET https://api.anthropic.com/api/oauth/usage`.
- No data leaves the Mac except to claude.ai / api.anthropic.com and the Sparkle feed. No logging of cookies, tokens, emails or org ids.
- Bundle id `com.alexisdahan.BudgetGuard`. Signing: self-signed stable identity `Budget Guard Signing` (pattern of Viji's `scripts/setup-signing.sh`), no notarization.
- Icon: an original glyph (not Anthropic's Claude logo — trademark; see Task 6). Template image so it adapts to light/dark menu bars.

## Review Focus

1. **Session expired or user logged out on claude.ai** → menu bar shows `—`, menu offers « Se reconnecter », no stale percentage presented as current. (Task 2 `testMenuModelNotLoggedIn`, Task 4 status mapping test.)
2. **No network / Mac waking from sleep / Cloudflare challenge** → last value greyed, no dialog, silent retry next cycle. (Task 2 `testMenuModelKeepsLastValueGreyedOnNetworkError`, Task 4 Cloudflare mapping test.)
3. **Free or Team/Enterprise account** (weekly window null) → onboarding shows « Budget Guard fonctionne avec les abonnements Claude Pro et Max. » instead of hanging. (Task 1 `testFreeAccountThrowsNoWeeklyLimit`.)
4. **Utilization above 100, or HTTP 429** → `100 %` in red, each alert sent once. (Task 1 `testUtilizationClampedTo100`, Task 3 `testJumpStraightTo100SendsBothAlertsOnce`, Task 4 429 mapping.)
5. **Google popup closes after sign-in / passkey failure** → no crash (the spike crashed here once), hint about « Essayer une autre méthode » visible. (Task 5 manual check M2.)

---

### Task 1: Package scaffold and usage parsing

**Files:**
- Create: `app/Package.swift`
- Create: `app/Sources/BudgetGuardCore/UsageSnapshot.swift`
- Create: `app/Sources/BudgetGuardCore/UsageParser.swift`
- Create: `app/Tests/BudgetGuardCoreTests/UsageParserTests.swift`
- Create: `app/Tests/BudgetGuardCoreTests/Fixtures/usage-max.json`, `orgs-two.json`, `usage-free.json`
- Create: `app/Sources/BudgetGuardApp/main.swift` (placeholder that prints and exits, replaced in Task 6)
- Modify: `.gitignore` (add `app/.build/`, `dist/`)

**Interfaces:**
- Produces:
  - `public struct ExtraUsage: Equatable, Codable { public let isEnabled: Bool; public let disabledReason: String? }`
  - `public struct UsageSnapshot: Equatable, Codable { public let weeklyPercent: Int; public let resetsAt: Date?; public let extraUsage: ExtraUsage?; public let fetchedAt: Date }`
  - `public enum UsageParseError: Error, Equatable { case malformed, noWeeklyLimit, noOrganization }`
  - `public enum UsageParser { static func organizationID(fromOrganizationsJSON data: Data) throws -> String; static func snapshot(fromUsageJSON data: Data, now: Date) throws -> UsageSnapshot }`

- [ ] **Step 1: Package.swift** — products: library `BudgetGuardCore`, executable `BudgetGuardApp`; test target `BudgetGuardCoreTests` with `resources: [.copy("Fixtures")]`; platform `.macOS(.v13)`; dependency `https://github.com/sparkle-project/Sparkle` from `2.6.0` used only by `BudgetGuardApp`.

- [ ] **Step 2: Fixtures** — `usage-max.json` reproduces the real response captured on 2026-11-24 (shape only, values as below); `usage-free.json` has `"seven_day": null, "five_hour": null`; `orgs-two.json` has two orgs, the first with `capabilities: ["api"]`, the second `{"uuid":"org-chat","capabilities":["chat","claude_max"]}`.

```json
{"five_hour":null,
 "seven_day":{"utilization":29,"resets_at":"2026-11-28T12:59:59.931258+00:00","limit_dollars":null,"used_dollars":null,"remaining_dollars":null,"locked_reason":null},
 "extra_usage":{"is_enabled":false,"monthly_limit":3500,"used_credits":0,"utilization":0,"currency":"EUR","disabled_reason":"out_of_credits"},
 "seven_day_opus":null,"pace":null}
```

- [ ] **Step 3: Write failing tests** in `UsageParserTests.swift`:
  - `testPicksFirstChatOrganization`: `organizationID(orgs-two.json) == "org-chat"`.
  - `testFallsBackToFirstOrganizationWithoutChat`: input `[{"uuid":"a","capabilities":[]},{"uuid":"b"}]` → `"a"`.
  - `testEmptyOrganizationsThrows`: `[]` → `UsageParseError.noOrganization`.
  - `testParsesMaxUsage`: `weeklyPercent == 29`, `resetsAt == ISO8601 2026-11-28T12:59:59.931Z` (±0.01 s), `extraUsage == ExtraUsage(isEnabled: false, disabledReason: "out_of_credits")`, `fetchedAt == now`.
  - `testFractionalUtilizationIsRounded`: `29.6` → `30`.
  - `testUtilizationClampedTo100`: `104.2` → `100`; `-1` → `0`.
  - `testFreeAccountThrowsNoWeeklyLimit`: `usage-free.json` → `.noWeeklyLimit`.
  - `testGarbageThrowsMalformed`: `"<html>Just a moment</html>"` → `.malformed`.
  - `testMissingResetsAtGivesNil`: seven_day without `resets_at` → `resetsAt == nil`.

- [ ] **Step 4: Run** `cd app && swift test --filter UsageParserTests` → FAIL (symbols missing).

- [ ] **Step 5: Implement** `UsageSnapshot.swift` and `UsageParser.swift`. Use `JSONSerialization` (the response has dozens of unstable keys; decode only what is needed). Dates: `ISO8601DateFormatter` with `[.withInternetDateTime, .withFractionalSeconds]`, falling back to `.withInternetDateTime`.

- [ ] **Step 6: Run** `cd app && swift test` → all PASS; `swift build` succeeds.

- [ ] **Step 7: Commit** `feat(app): Swift package and usage parsing`.

### Task 2: Level, French copy and menu model

**Files:**
- Create: `app/Sources/BudgetGuardCore/UsageLevel.swift`
- Create: `app/Sources/BudgetGuardCore/Copy.swift`
- Create: `app/Sources/BudgetGuardCore/MenuModel.swift`
- Create: `app/Tests/BudgetGuardCoreTests/CopyTests.swift`, `MenuModelTests.swift`

**Interfaces:**
- Consumes: `UsageSnapshot`, `ExtraUsage` (Task 1).
- Produces:
  - `public enum UsageLevel: Equatable { case normal, warning, critical; public init(percent: Int) }`
  - `public enum UsageFetchError: Error, Equatable { case notLoggedIn, network, cloudflare, rateLimited, unsupportedPlan, malformed }`
  - `public enum Copy { static func percentTitle(_ percent: Int?) -> String; static func resetLine(_ date: Date, now: Date, calendar: Calendar) -> String; static func extraUsageLine(_ extra: ExtraUsage?) -> String?; static func alertBody(threshold: Int, percent: Int) -> String }`
  - `public struct MenuModel: Equatable { public let title: String; public let level: UsageLevel?; public let isStale: Bool; public let lines: [String]; public let showsReconnect: Bool }`
  - `public func makeMenuModel(snapshot: UsageSnapshot?, error: UsageFetchError?, now: Date, calendar: Calendar) -> MenuModel`

- [ ] **Step 1: Write failing tests.** `CopyTests` uses `Calendar(identifier: .gregorian)` with `timeZone = Europe/Paris`, `locale = fr_FR`:
  - `testPercentTitle`: `29` → `"29\u{202F}%"`; `nil` → `"—"`.
  - `testResetLineOtherDay`: reset `2026-11-28T12:59:59.93Z`, now `2026-11-24T10:00Z` → `"Remise à zéro vendredi à 14 h"` (rounded to nearest minute, Paris time).
  - `testResetLineTomorrowWithMinutes`: reset `2026-11-25T13:30Z`, now `2026-11-24T10:00Z` → `"Remise à zéro demain à 14 h 30"`.
  - `testResetLineToday`: reset `2026-11-24T16:00Z`, now `2026-11-24T10:00Z` → `"Remise à zéro aujourd’hui à 17 h"`.
  - `testExtraUsageLines`: enabled → `"Dépassement du forfait : activé"`; disabled → `"Dépassement du forfait : désactivé"`; nil → `nil`.
  - `testAlertBody`: `(80, 82)` → `"Vous avez utilisé 82 % de votre limite de la semaine."` (U+202F before `%`).
  - `testLevels`: 69 → normal, 70 → warning, 89 → warning, 90 → critical.
  - `MenuModelTests.testMenuModelFresh`: snapshot 29 %, no error → title `"29 %"`, level normal, not stale, lines = [`"Vous avez utilisé 29 % de votre limite de la semaine"`, reset line, extra-usage line], `showsReconnect == false`.
  - `testMenuModelKeepsLastValueGreyedOnNetworkError`: snapshot + `.network` → same title, `isStale == true`, lines end with `"Dernière mise à jour à 10 h 02 — connexion impossible"`.
  - `testMenuModelNotLoggedIn`: snapshot + `.notLoggedIn` → title `"—"`, level nil, `showsReconnect == true`, lines == [`"Vous n’êtes plus connecté à Claude."`].
  - `testMenuModelRateLimited`: `.rateLimited` with no snapshot → title `"100 %"`, level critical.
  - `testMenuModelUnsupportedPlan`: lines == [`"Budget Guard fonctionne avec les abonnements Claude Pro et Max."`].

- [ ] **Step 2: Run** `swift test --filter "CopyTests|MenuModelTests"` → FAIL.

- [ ] **Step 3: Implement** the three files. Weekday names from `calendar` with `fr_FR` (`EEEE`, lowercased). `.cloudflare` and `.malformed` behave like `.network` in the menu model.

- [ ] **Step 4: Run** `swift test` → PASS.

- [ ] **Step 5: Commit** `feat(app): levels, French copy and menu model`.

### Task 3: Alert re-arming

**Files:**
- Create: `app/Sources/BudgetGuardCore/AlertTracker.swift`
- Create: `app/Tests/BudgetGuardCoreTests/AlertTrackerTests.swift`

**Interfaces:**
- Produces:
  - `public protocol AlertStateStore: AnyObject { func isNotified(_ threshold: Int) -> Bool; func setNotified(_ threshold: Int, _ value: Bool) }`
  - `public final class UserDefaultsAlertStateStore: AlertStateStore { public init(defaults: UserDefaults) }` — keys `alert.notified.80`, `alert.notified.95`.
  - `public struct AlertTracker { public init(store: AlertStateStore, thresholds: [Int] = [80, 95]); public func thresholdsToAlert(for percent: Int) -> [Int] }` — returns newly crossed thresholds and updates the store (sets on cross, clears when `percent < threshold`).

- [ ] **Step 1: Write failing tests** (in-memory store): `testBelowAllNoAlert` (50 → []); `testCross80Once` (82 → [80], then 85 → []); `testRearmAfterDrop` (82 → [80], 40 → [], 81 → [80]); `testJumpStraightTo100SendsBothAlertsOnce` (100 → [80, 95], 100 → []); `testPersistsAcrossInstances` (two trackers on the same `UserDefaults(suiteName:)` store: 82 then 83 → second returns []).
- [ ] **Step 2: Run** `swift test --filter AlertTrackerTests` → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `swift test` → PASS.
- [ ] **Step 5: Commit** `feat(app): alert thresholds with re-arming`.

### Task 4: Usage sources (claude.ai session and Claude Code fallback)

**Files:**
- Create: `app/Sources/BudgetGuardCore/ResponseClassifier.swift`
- Create: `app/Tests/BudgetGuardCoreTests/ResponseClassifierTests.swift`
- Create: `app/Sources/BudgetGuardApp/Usage/UsageSource.swift`
- Create: `app/Sources/BudgetGuardApp/Usage/WebSessionSource.swift`
- Create: `app/Sources/BudgetGuardApp/Usage/ClaudeCodeSource.swift`

**Interfaces:**
- Consumes: `UsageParser`, `UsageFetchError`, `UsageParseError`.
- Produces:
  - `public enum ResponseClassifier { static func error(status: Int, body: String) -> UsageFetchError? }` — 401/403 without challenge → `.notLoggedIn`; 403/503 whose body contains `Just a moment` or `cf-` challenge markers → `.cloudflare`; 429 → `.rateLimited`; other non-2xx → `.network`; 2xx → nil.
  - `protocol UsageSource: AnyObject { @MainActor func fetchSnapshot() async throws -> UsageSnapshot }` (throws `UsageFetchError`).
  - `@MainActor final class WebSessionSource: UsageSource { init(dataStore: WKWebsiteDataStore = .default()); var webView: WKWebView { get }; func hasSession() async -> Bool }` — owns a hidden `WKWebView` (not in any window) on `https://claude.ai/`; reloads the page if it is not on claude.ai or older than 30 min.
  - `final class ClaudeCodeSource: UsageSource { static func isAvailable() -> Bool }` — reads `Claude Code-credentials` (`claudeAiOauth.accessToken`), GETs `/api/oauth/usage`, parses with `UsageParser.snapshot`. Expired token → `.notLoggedIn`; never refreshes.
  - `enum SourceKind: String { case web, claudeCode }` stored in `UserDefaults` key `usage.source`, default `.web`.

- [ ] **Step 1: Write failing tests** `ResponseClassifierTests`: `(200,"{}") → nil`; `(401,"") → .notLoggedIn`; `(403,"{\"error\":\"permission\"}") → .notLoggedIn`; `(403,"<title>Just a moment...</title>") → .cloudflare`; `(429,"") → .rateLimited`; `(500,"") → .network`.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement** `ResponseClassifier`. **Step 4: Run** `swift test` → PASS.
- [ ] **Step 5: Implement `WebSessionSource`.** Runs one `callAsyncJavaScript` in `.page` that fetches the two endpoints with `accept: application/json` and returns `{orgsStatus, orgsBody, usageStatus, usageBody}` as raw strings; all classification and parsing happens in Swift (`ResponseClassifier`, then `UsageParser`; `.noWeeklyLimit` → `.unsupportedPlan`, other parse errors → `.malformed`). JS errors (offline) → `.network`. Base the JS on the spike's `probe()`.
- [ ] **Step 6: Implement `ClaudeCodeSource`** with `URLSession`, 15 s timeout, headers `Authorization: Bearer …`, `anthropic-beta: oauth-2025-04-20`, `Accept: application/json`.
- [ ] **Step 7: Add a debug entry point**: `BudgetGuardApp --probe web|claude-code` prints `Copy.percentTitle` + reset line, or the error case, and exits. No identifiers printed.
- [ ] **Step 8: Verify** on Alexis's Mac: `swift run BudgetGuardApp --probe claude-code` → prints a percentage (Claude Code is logged in there). `--probe web` → prints `notLoggedIn` until Task 5's login has run once (expected).
- [ ] **Step 9: Commit** `feat(app): claude.ai session and Claude Code usage sources`.

### Task 5: Login window

**Files:**
- Create: `app/Sources/BudgetGuardApp/Login/LoginWebView.swift`

**Interfaces:**
- Consumes: `WebSessionSource` (same `WKWebsiteDataStore.default()`, so the session it creates is the one the source reads).
- Produces: `@MainActor final class LoginWebView: NSObject, WKNavigationDelegate, WKUIDelegate { init(dataStore: WKWebsiteDataStore = .default()); let view: NSView; var onLoggedIn: (() -> Void)?; func start() }` — embeddable `NSView` (hint banner + web view) used by the onboarding (Task 7) and by « Se reconnecter ».

- [ ] **Step 1: Implement** from the spike: loads `https://claude.ai/login`; popups get their own `NSWindow` with `isReleasedWhenClosed = false`, hidden with `orderOut` asynchronously in `webViewDidClose` (the spike crashed when closing synchronously); every 3 s while the main frame is on `claude.ai` outside `/login`, call `WebSessionSource.fetchSnapshot()`; the first success calls `onLoggedIn` once. Hint banner above the page, verbatim:
  « Connectez-vous comme d’habitude. Si Google vous parle de Bluetooth, cliquez sur « Essayer une autre méthode », ou choisissez « Continuer avec l’e-mail » et entrez votre adresse : vous recevrez un code. »
- [ ] **Step 2: Manual check M1** (needs Alexis): temporary `--login-test` flag opens the view in a window; log in by e-mail code → `onLoggedIn` fires; then `swift run BudgetGuardApp --probe web` prints the percentage.
- [ ] **Step 3: Manual check M2** (needs Alexis): `--login-test` after clearing site data (`WKWebsiteDataStore.default().removeData(ofTypes: allWebsiteDataTypes, modifiedSince: .distantPast)` behind a `--logout` flag); log in with Google, using « Essayer une autre méthode » → no crash when the Google window closes, `onLoggedIn` fires.
- [ ] **Step 4: Commit** `feat(app): embedded claude.ai login`.

### Task 6: Menu bar item, refresh loop and alerts

**Files:**
- Create: `app/Sources/BudgetGuardApp/AppDelegate.swift`
- Replace: `app/Sources/BudgetGuardApp/main.swift`
- Create: `app/Sources/BudgetGuardApp/StatusItemController.swift`
- Create: `app/Sources/BudgetGuardApp/RefreshLoop.swift`
- Create: `app/Sources/BudgetGuardApp/Notifier.swift`
- Create: `app/Resources/MenuBarIcon.pdf` (template image, ~16 pt) and `app/scripts/make-menubar-icon.swift` that draws it

**Interfaces:**
- Consumes: `makeMenuModel`, `AlertTracker`, `UserDefaultsAlertStateStore`, `Copy.alertBody`, `UsageSource`s, `SourceKind`.
- Produces: `RefreshLoop { init(sourceProvider: @escaping () -> UsageSource, interval: TimeInterval = 120); var onUpdate: ((UsageSnapshot?, UsageFetchError?) -> Void)?; func start(); func refreshNow() }`; `StatusItemController { func render(_ model: MenuModel) ; var onReconnect: (() -> Void)?; var onRefresh: (() -> Void)? }`; `Notifier { func requestAuthorization() async -> Bool; func post(threshold: Int, percent: Int) }`.

- [ ] **Step 1: Icon.** Original glyph drawn by the script (an eight-branch spark inside a thin gauge arc), exported as a template PDF. Do not use Anthropic's Claude logo or wordmark.
- [ ] **Step 2: Status item.** Image + attributed title colored by `UsageLevel` (Global Constraints colors; grey `#9A9A9A` when `isStale`). Menu: model `lines` (disabled items), separator, « Actualiser maintenant », « Se reconnecter à Claude… » (only when `showsReconnect`), « Utiliser ma connexion Claude Code » (only when `showsReconnect` and `ClaudeCodeSource.isAvailable()`; before switching show an `NSAlert`: « macOS va vous demander l’autorisation de lire votre connexion Claude Code. Cliquez sur « Toujours autoriser ». »), « Activer les alertes » (only when notifications are not authorized), « Lancer au démarrage du Mac » (checkmark), « Rechercher des mises à jour… », « Quitter Budget Guard ».
- [ ] **Step 3: Refresh loop.** Timer 120 s plus refresh on `NSWorkspace.didWakeNotification`; keeps the last snapshot; feeds `AlertTracker` on each fresh snapshot and posts via `Notifier` (title « Budget Guard », body `Copy.alertBody`). `.rateLimited` counts as 100 for alerts.
- [ ] **Step 4: Verify** with `SourceKind.claudeCode` on Alexis's Mac: `swift run BudgetGuardApp` → icon + `NN %` appears within 5 s, color matches level, menu lines match the menu model; turn Wi-Fi off and use « Actualiser maintenant » → value greys out, menu shows the « connexion impossible » line; Wi-Fi on → back to color.
- [ ] **Step 5: Commit** `feat(app): menu bar item, refresh loop and alerts`.

### Task 7: Onboarding assistant and login item

**Files:**
- Create: `app/Sources/BudgetGuardApp/Onboarding/OnboardingWindowController.swift`
- Create: `app/Sources/BudgetGuardApp/Onboarding/OnboardingView.swift` (SwiftUI, 5 steps)
- Create: `app/Sources/BudgetGuardApp/LoginItem.swift`

**Interfaces:**
- Consumes: `LoginWebView` (Task 5), `WebSessionSource`, `Notifier`, `Copy`, `UsageFetchError`.
- Produces: `OnboardingWindowController { func show(startAt step: OnboardingStep = .welcome, completion: @escaping () -> Void) }`, `enum OnboardingStep { case welcome, login, check, settings, done }`; `LoginItem { static var isEnabled: Bool; static func setEnabled(_ on: Bool) throws }` (SMAppService.mainApp). UserDefaults key `onboarding.completed`.

- [ ] **Step 1: Implement the five steps**, window 560×760, one primary button per step, copy verbatim:
  1. Bienvenue — « Budget Guard affiche en permanence, en haut de votre écran, la part de votre limite Claude de la semaine que vous avez déjà utilisée. » Button « Commencer ».
  2. Connexion — embeds `LoginWebView`; advances automatically on `onLoggedIn`.
  3. Vérification — big `Copy.percentTitle`, then « Vous avez utilisé 29 % de votre limite de la semaine. » and `Copy.resetLine`. On `.unsupportedPlan`: « Budget Guard fonctionne avec les abonnements Claude Pro et Max. » with button « Quitter ». Button « Continuer ».
  4. Réglages — toggles « Lancer Budget Guard au démarrage du Mac » (on) and « M’alerter à 80 % et à 95 % » (on); line above the button: « macOS va vous demander si Budget Guard peut vous envoyer des notifications : répondez « Autoriser ». » Button « Continuer » applies `LoginItem.setEnabled` and `Notifier.requestAuthorization()` (alerts toggle on only).
  5. Terminé — « C’est prêt ! Votre pourcentage s’affiche en haut à droite de l’écran, à côté de l’heure. » Button « Fermer ».
- [ ] **Step 2: Wire** `AppDelegate`: if `onboarding.completed` is false, show the assistant; « Se reconnecter à Claude… » opens it at `.login` and closes after step 3.
- [ ] **Step 3: Verify** on Alexis's Mac with clean state (`defaults delete com.alexisdahan.BudgetGuard` + `--logout`): run the app, go through all five steps with an e-mail login → percentage in menu bar; quit and relaunch → no assistant, percentage back within 5 s.
- [ ] **Step 4: Commit** `feat(app): first-launch assistant and login item`.

### Task 8: Packaging, signing and updates

**Files:**
- Create: `app/Resources/Info.plist`
- Create: `scripts/setup-signing.sh` (copy of Viji's, name `Budget Guard Signing`)
- Create: `scripts/build-app.sh`
- Create: `app/Sources/BudgetGuardApp/Updater.swift`
- Modify: `.gitignore`

**Interfaces:**
- Produces: `dist/Budget Guard.app` and `dist/BudgetGuard-<version>.dmg`; `Updater { static let shared; func checkForUpdates() }` (Sparkle `SPUStandardUpdaterController`).

- [ ] **Step 1: Info.plist**: `CFBundleIdentifier com.alexisdahan.BudgetGuard`, `CFBundleName "Budget Guard"`, `CFBundleShortVersionString 2.0.0`, `LSMinimumSystemVersion 13.0`, `LSUIElement true`, `SUFeedURL https://dalex160.github.io/claude-budget-watch/appcast.xml`, `SUPublicEDKey` (from Step 3), `SUEnableAutomaticChecks true`, `CFBundleDevelopmentRegion fr`.
- [ ] **Step 2: build-app.sh**: `swift build -c release --arch arm64 --arch x86_64`; assemble `Contents/MacOS`, `Contents/Resources` (icon PDF, app icon), `Contents/Frameworks/Sparkle.framework` (from `.build`), rpath `@executable_path/../Frameworks`; `codesign --force --deep --options runtime --sign "Budget Guard Signing"` (fallback `-` if the identity is missing, with a warning); DMG via `hdiutil create -volname "Budget Guard" -srcfolder … -format UDZO` with an `/Applications` symlink.
- [ ] **Step 3: Sparkle key** — run Sparkle's `generate_keys` once; private key stays in Alexis's login Keychain, an exported copy goes to `~/Secrets-hors-OneDrive/budget-guard-sparkle-key` (ask Alexis before writing there). Never commit it.
- [ ] **Step 4: Verify**: `scripts/build-app.sh` → `lipo -archs "dist/Budget Guard.app/Contents/MacOS/BudgetGuardApp"` prints `x86_64 arm64`; `codesign -dv` shows `Authority=Budget Guard Signing`; copying the DMG's app to `/Applications` and opening it shows the assistant.
- [ ] **Step 5: Commit** `build: universal signed app bundle, DMG and Sparkle updates`.

### Task 9: Download page, release and README

**Files:**
- Create: `site/index.html`, `site/img/ouvrir-1.png`, `ouvrir-2.png`, `ouvrir-3.png`
- Create: `scripts/release.sh`
- Modify: `README.md`

**Interfaces:**
- Consumes: `dist/BudgetGuard-<version>.dmg` (Task 8).

- [ ] **Step 1: Screenshots** taken in a brand-new macOS user account on Alexis's Mac (ask him to create it): (1) the « non ouverte » alert after double-click, (2) Réglages Système > Confidentialité et sécurité with « Ouvrir quand même » highlighted, (3) the confirmation dialog.
- [ ] **Step 2: Page** (French, one screen on a laptop): title « Budget Guard », one sentence of purpose, the three screenshots captioned « 1. Double-cliquez sur Budget Guard. macOS refuse de l’ouvrir la première fois : c’est normal. », « 2. Ouvrez Réglages Système > Confidentialité et sécurité, descendez et cliquez sur « Ouvrir quand même ». », « 3. Confirmez. Budget Guard vous guide ensuite. », then the download button pointing at the latest release DMG. Published with GitHub Pages from `site/` (also hosts `appcast.xml`).
- [ ] **Step 3: release.sh**: builds, creates GitHub Release `v<version>` with the DMG, runs Sparkle `generate_appcast` into `site/appcast.xml`, commits and pushes. Runs only after Alexis's go.
- [ ] **Step 4: README**: lead with the download page link; move the SwiftBar plugin instructions under « Ancienne version (SwiftBar) ».
- [ ] **Step 5: End-to-end verification** in the fresh macOS account: open the page, download, follow the three steps, complete the assistant with an e-mail login, see the percentage. Then publish v2.0.1 and confirm the first install updates itself via « Rechercher des mises à jour… » without any « Ouvrir quand même ».
- [ ] **Step 6: Commit** `docs: download page and README for the native app`.
