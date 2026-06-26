import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(scriptDir, "..");

test("docs-site builds Dutch default and English alternate from public allowlist", () => {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "pdtbar-docs-site-"));
  const outDir = path.join(tempRoot, "dist", "docs-site");
  fs.cpSync(path.join(root, "docs"), path.join(tempRoot, "docs"), { recursive: true });
  fs.mkdirSync(path.join(tempRoot, "Scripts"), { recursive: true });
  fs.cpSync(path.join(root, "Scripts", "build-docs-site.mjs"), path.join(tempRoot, "Scripts", "build-docs-site.mjs"));
  fs.cpSync(path.join(root, "Scripts", "docs-site-assets.mjs"), path.join(tempRoot, "Scripts", "docs-site-assets.mjs"));
  fs.mkdirSync(path.join(tempRoot, "docs", "research"), { recursive: true });
  fs.writeFileSync(path.join(tempRoot, "docs", "research", "internal.md"), "# Internal\n\nINTERNAL_ONLY_SENTINEL_PDTBAR\n", "utf8");
  fs.appendFileSync(path.join(tempRoot, "docs", "index.md"), "\n[Unsafe](javascript:alert(1))\n[Safe](https://example.com?a=1&b=2)\n", "utf8");

  try {
    execFileSync("node", [path.join(tempRoot, "Scripts", "build-docs-site.mjs")], {
      cwd: tempRoot,
      env: {
        ...process.env,
        PDTBAR_DOCS_SITE_ROOT: tempRoot,
        PDTBAR_DOCS_SITE_OUT: outDir,
      },
      encoding: "utf8",
      stdio: "pipe",
    });

    for (const rel of [
      "index.html",
      "en/index.html",
      "assets/pdtbar-menu.png",
      "favicon.svg",
      "social-card.svg",
      ".nojekyll",
      "sitemap.xml",
      "robots.txt",
      "llms.txt",
      "llms-full.txt",
    ]) {
      assert.ok(fs.existsSync(path.join(outDir, rel)), `${rel} should exist`);
    }

    const nl = fs.readFileSync(path.join(outDir, "index.html"), "utf8");
    const en = fs.readFileSync(path.join(outDir, "en", "index.html"), "utf8");
    const llms = fs.readFileSync(path.join(outDir, "llms.txt"), "utf8");
    const llmsFull = fs.readFileSync(path.join(outDir, "llms-full.txt"), "utf8");

    assert.match(nl, /<html lang="nl">/);
    assert.match(nl, /PDTBar is een rustige macOS menubalk-companion/);
    assert.match(nl, /href="en\/index\.html"/);
    assert.match(nl, />English<\/a>/);
    assert.match(nl, /href="https:\/\/example\.com\?a=1&amp;b=2"/);
    assert.doesNotMatch(nl, /javascript:alert/);
    assert.match(en, /<html lang="en">/);
    assert.match(en, /PDTBar is a quiet macOS menu bar companion/);
    assert.match(en, /href="\.\.\/index\.html"/);
    assert.match(en, />Nederlands<\/a>/);
    assert.match(nl, /application\/ld\+json/);
    assert.match(nl, /SoftwareApplication/);
    assert.match(nl, /FinanceApplication/);
    assert.match(nl, /id="doc-search"/);
    assert.match(nl, /data-theme-toggle/);
    assert.match(nl, /className="copy"/);
    assert.match(nl, /assets\/pdtbar-menu\.png/);
    assert.match(nl, /https:\/\/bramvr\.github\.io\/pdtbar\/social-card\.svg/);
    assert.match(llms, /root page is Dutch by default/);
    assert.match(llms, /https:\/\/bramvr\.github\.io\/pdtbar\/en\//);
    assert.doesNotMatch(nl + en + llms + llmsFull, /INTERNAL_ONLY_SENTINEL_PDTBAR/);
    assert.ok(!fs.existsSync(path.join(outDir, "research", "internal.html")));
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});

test("pages workflow builds, tests, and deploys docs-site artifact", () => {
  const workflow = fs.readFileSync(path.join(root, ".github", "workflows", "pages.yml"), "utf8");
  for (const expected of [
    "pull_request:",
    "push:",
    "branches:",
    "- main",
    "workflow_dispatch:",
    "run: make docs-site",
    "run: make docs-site-test",
    "dist/docs-site/index.html",
    "dist/docs-site/en/index.html",
    "dist/docs-site/assets/pdtbar-menu.png",
    "dist/docs-site/sitemap.xml",
    "dist/docs-site/robots.txt",
    "dist/docs-site/llms.txt",
    "dist/docs-site/llms-full.txt",
    "dist/docs-site/.nojekyll",
    "actions/configure-pages",
    "actions/upload-pages-artifact",
    "actions/deploy-pages",
  ]) {
    assert.ok(workflow.includes(expected), `workflow should include ${expected}`);
  }
});
