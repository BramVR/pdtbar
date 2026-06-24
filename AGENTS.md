# Repository Guidelines

## Project Structure & Modules
- `Sources/PDTBarCore`: Swift core for PDT normalization, pressure model, fixtures, and menu descriptors. Keep engine logic out of AppKit.
- `Sources/PDTBarApp`: macOS menu bar app. Keep it a renderer/launcher over core descriptors.
- `Sources/PDTBarDev`, `Sources/PDTBarSmoke`, `Sources/PDTBarChecks`: dev CLI, smoke proof, deterministic checks.
- `docs`: agent-facing workflow and architecture notes. Root `README.md` stays human/product-facing.

## Build, Test, Run
- Docs inventory: `make docs-list`; read matching `Read when` hints before non-trivial work.
- Quick build/check: `swift build`; `swift run pdtbar-checks`.
- Focused smokes: use `swift run pdtbar-smoke ...` for launch/login/fetch/menu behavior. Prefer scripted smokes before live Claude/PDT or Accessibility checks.

## Coding Style & Naming
- Use SwiftPM and repo tools; avoid adding dependencies or tooling without confirmation.
- Favor small, typed structs/enums and focused helpers. Keep changes scoped and reuse existing seams.

## Testing Guidelines
- Prefer CLI/core/scripted tests over app-bundle live tests when behavior can be verified without relaunching PDTBar.
- Do not run validation that can show macOS auth, Keychain, Accessibility, or Screen Recording prompts unless explicitly requested; otherwise use fixtures, scripted smokes, or clean skips.
- Menu behavior should be covered through stable model/descriptor seams unless AppKit wiring itself is under test.

## Commit & PR Guidelines
- Commits: use `committer` script for every commit.
- PR visual proof: images must be inline-viewable after merge. Prefer uploading a PNG directly to the PR body/comment so GitHub creates a `user-attachments` URL. Do not use `raw.githubusercontent.com` links for private-repo proof images, do not rely on branch URLs that may be deleted after merge, and do not use SVG as the only inline proof image.

## Agent Notes
- Validate UI/runtime behavior against freshly built code; avoid proving behavior against a stale app.
- Menu bar automation: verify the target status item/menu is visibly present before claiming proof.
- Keep docs current with behavior changes and add `summary`/`read_when` frontmatter to new docs.
