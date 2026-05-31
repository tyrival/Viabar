# Viabar Local Sparkle Release Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a repeatable local command that packages Viabar as a DMG, signs the update with Sparkle EdDSA, uploads it to GitHub Releases, updates the public appcast, and stops tracking local build artifacts.

**Architecture:** Keep release orchestration in `scripts/release.sh`, XML editing in a small Python standard-library tool, and one-time key setup in `scripts/bootstrap-sparkle.sh`. Configure Sparkle statically through the generated app Info.plist and migrate away from the deprecated runtime feed override.

**Tech Stack:** Swift, Xcode build settings, Sparkle 2.9.2 tools, Bash, Python 3 standard library, GitHub CLI.

---

### Task 1: Test and implement structured appcast updates

**Files:**
- Create: `scripts/update_appcast.py`
- Create: `scripts/tests/test_update_appcast.py`

- [ ] **Step 1: Add fixture-based unittest coverage**

Cover successful insertion, duplicate marketing version rejection, non-increasing build rejection, and malformed XML rejection.

- [ ] **Step 2: Run the tests and confirm the implementation is absent**

Run:

```bash
python3 -m unittest scripts.tests.test_update_appcast -v
```

Expected: import failure because `scripts/update_appcast.py` does not exist.

- [ ] **Step 3: Implement the XML updater**

Use `xml.etree.ElementTree`, preserve historical items, insert the new item before the first existing item, and return actionable errors through a non-zero exit code.

- [ ] **Step 4: Run updater tests**

Run:

```bash
python3 -m unittest scripts.tests.test_update_appcast -v
```

Expected: all tests pass.

### Task 2: Add Sparkle bootstrap and local release orchestration

**Files:**
- Create: `scripts/sparkle_tools.sh`
- Create: `scripts/bootstrap-sparkle.sh`
- Create: `scripts/release.sh`
- Create: `scripts/tests/test_release_preflight.sh`

- [ ] **Step 1: Add shell preflight coverage**

Verify that release fails with clear messages for an invalid semantic version, missing `gh`, and a dirty public release repository.

- [ ] **Step 2: Add shared Sparkle tool lookup**

Search Xcode DerivedData for `generate_keys` and `sign_update`, fail with a message telling the developer to resolve the Sparkle Swift package in Xcode when unavailable.

- [ ] **Step 3: Add one-time key bootstrap**

Run Sparkle `generate_keys`, retain the private key in Keychain, print the public key and the Xcode build-setting key that must receive it.

- [ ] **Step 4: Add the local release command**

Validate tools and repositories, derive the next build number from appcast, read the minimum system version from Xcode Release settings, archive with version overrides only, create the DMG, sign it, create a GitHub Release, call `update_appcast.py`, then commit and push only `appcast.xml`.

- [ ] **Step 5: Run shell preflight coverage**

Run:

```bash
bash scripts/tests/test_release_preflight.sh
```

Expected: all preflight assertions pass without compiling the app.

### Task 3: Configure sandboxed Sparkle installation

**Files:**
- Modify: `Viabar.xcodeproj/project.pbxproj`
- Modify: `Viabar/Services/UpdateService.swift`
- Modify: `Viabar/Viabar.entitlements`

- [ ] **Step 1: Point generated Info.plist settings at the public appcast**

Set `INFOPLIST_KEY_SUFeedURL`, `INFOPLIST_KEY_SUEnableAutomaticChecks`, and `INFOPLIST_KEY_SUEnableInstallerLauncherService` for both app configurations. Add `INFOPLIST_KEY_SUPublicEDKey` after running bootstrap.

- [ ] **Step 2: Migrate the deprecated runtime feed override**

Replace `setFeedURL` with `clearFeedURLFromUserDefaults()` so existing installations stop using the persisted override and read the static Info.plist feed.

- [ ] **Step 3: Add sandbox installer mach lookup exceptions**

Add `$(PRODUCT_BUNDLE_IDENTIFIER)-spks` and `$(PRODUCT_BUNDLE_IDENTIFIER)-spki` to `Viabar.entitlements`.

- [ ] **Step 4: Perform static verification**

Run:

```bash
rg -n "SUFeedURL|SUPublicEDKey|SUEnableInstallerLauncherService|clearFeedURLFromUserDefaults|spks|spki" Viabar.xcodeproj Viabar
```

Expected: static feed, public key, installer launcher opt-in, migration call, and both entitlements are visible.

### Task 4: Stop tracking local artifacts

**Files:**
- Modify: `.gitignore`
- Remove from Git index only: `build/`
- Remove from Git index only: `.superpowers/brainstorm/`
- Remove from Git index only: `.claude/settings.local.json`

- [ ] **Step 1: Narrow ignore rules**

Ignore `build/`, `DerivedData/`, `dist/`, `*.dmg`, `*.xcarchive/`, `.superpowers/brainstorm/`, `.claude/settings.local.json`, and `.worktrees/`. Remove the broad `superpowers/` rule so `docs/superpowers/` remains trackable.

- [ ] **Step 2: Remove already-tracked local files from the index**

Run:

```bash
git rm -r --cached build .superpowers/brainstorm
git rm --cached .claude/settings.local.json
```

Expected: local files remain on disk but are staged for removal from GitHub after the next push.

- [ ] **Step 3: Verify tracked local files are gone**

Run:

```bash
git ls-files build .superpowers/brainstorm .claude/settings.local.json
```

Expected: no output.

### Task 5: Verify without compiling

**Files:**
- Verify: all changed files

- [ ] **Step 1: Run script tests**

Run:

```bash
python3 -m unittest scripts.tests.test_update_appcast -v
bash scripts/tests/test_release_preflight.sh
```

Expected: all tests pass.

- [ ] **Step 2: Run shell syntax checks**

Run:

```bash
bash -n scripts/sparkle_tools.sh scripts/bootstrap-sparkle.sh scripts/release.sh scripts/tests/test_release_preflight.sh
```

Expected: no output.

- [ ] **Step 3: Review source repository status**

Run:

```bash
git status --short
```

Expected: only intentional implementation changes, staged artifact removals, pre-existing brainstorm directories now ignored, and the pre-existing untracked `Viabar/Info.plist`.

- [ ] **Step 4: Leave end-to-end packaging for explicit user testing**

Do not compile or publish automatically. Provide the bootstrap command, `brew install gh`, `gh auth login`, the public repository dirty-state warning, and the release command for the developer to run after reviewing changes.
