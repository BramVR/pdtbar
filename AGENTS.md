# AGENTS.md

- Commits: use `committer` script for every commit.
- Docs: keep `docs/` up to date with behavior changes. Run `make docs-list` before non-trivial work, read matching `Read when` hints, and add `summary`/`read_when` frontmatter to new docs.
- README: human/product-facing only. Agent/development/architecture workflow belongs in `docs/`.
- Shape: `Sources/PDTBarCore` computes/normalizes; `Sources/PDTBarApp` renders/launches; `Sources/PDTBarSmoke` proves runtime flows. Keep engine/bar separation clean.
- Gates: docs-only => `make docs-list` + `git diff --check`. Code changes => `swift build` + `swift run pdtbar-checks`; run focused smokes when launch/login/fetch/menu behavior changes.
- Validation: prefer core/scripted smokes before live Claude/PDT/AppKit/AX checks. Live/auth/permission checks must be explicit or cleanly skipped; no surprise prompts.
- Auth v1: prefer existing signed-in host apps. Claude/Codex login reuse is OK only when narrow, read-only, prompt-safe, redacted, and explicit about storage ownership. No broad browser-cookie import or generic credential store without ADR.
- Dependencies/tooling: SwiftPM/repo tools only. No new deps, release machinery, widgets, provider registry, or credential platform without approval/ADR.
- PR visual proof: images must be inline-viewable after merge. Prefer uploading a PNG directly to the PR body/comment so GitHub creates a `user-attachments` URL. Do not use `raw.githubusercontent.com` links for private-repo proof images, do not rely on branch URLs that may be deleted after merge, and do not use SVG as the only inline proof image.
