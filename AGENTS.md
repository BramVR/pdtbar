# AGENTS.md

- Commits: use `committer` script for every commit.
- Docs: keep `docs/` up to date with behavior changes. Run `make docs-list` before non-trivial work, read matching `Read when` hints, and add `summary`/`read_when` frontmatter to new docs.
- README: human/product-facing only. Agent/development/architecture workflow belongs in `docs/`.
- PR visual proof: images must be inline-viewable after merge. Prefer uploading a PNG directly to the PR body/comment so GitHub creates a `user-attachments` URL. Do not use `raw.githubusercontent.com` links for private-repo proof images, do not rely on branch URLs that may be deleted after merge, and do not use SVG as the only inline proof image.
