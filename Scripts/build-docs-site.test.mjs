import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(scriptDir, "..");

test("docs-site builds bilingual public artifact from allowlisted pages", () => {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "pdtbar-docs-site-"));
  const outDir = path.join(tempRoot, "dist", "docs-site");
  fs.cpSync(path.join(root, "docs"), path.join(tempRoot, "docs"), { recursive: true });
  const dutchPage = path.join(tempRoot, "docs", "public", "index.nl.md");
  fs.writeFileSync(
    dutchPage,
    fs
      .readFileSync(dutchPage, "utf8")
      .replace(
        'description: "PDTBar toont de belangrijkste signalen uit je Portfolio Dividend Tracker-portefeuille in de macOS-menubalk."',
        'description: "PDTBar JSON-LD escape </script><script>alert(1)</script> sentinel."',
      ),
    "utf8",
  );
  fs.writeFileSync(
    path.join(tempRoot, "docs", "private-agent-notes.md"),
    ["# Private Agent Notes", "", "INTERNAL_ONLY_SENTINEL_PDT_PORTFOLIO_PATH", ""].join("\n"),
    "utf8",
  );
  fs.appendFileSync(
    path.join(tempRoot, "docs", "public", "index.nl.md"),
    "\n\n[Onveilige link](javascript:alert(1))\n[Veilige link](https://example.com?a=1&b=2)\n",
    "utf8",
  );
  fs.appendFileSync(
    path.join(tempRoot, "docs", "public", "index.en.md"),
    "\n\n[Unsafe control link](java\tscript:alert(1))\n",
    "utf8",
  );
  fs.writeFileSync(
    path.join(tempRoot, "docs", "public", "guide.nl.md"),
    [
      "---",
      'summary: "Nested Dutch docs-site page."',
      'title: "Gids"',
      'lang: "nl"',
      'permalink: "/gids/"',
      'description: "Nested Dutch page."',
      "---",
      "",
      "# Gids",
      "",
      "Nederlandse nested page.",
      "",
    ].join("\n"),
    "utf8",
  );
  fs.writeFileSync(
    path.join(tempRoot, "docs", "public", "guide.en.md"),
    [
      "---",
      'summary: "Nested English docs-site page."',
      'title: "Guide"',
      'lang: "en"',
      'permalink: "/en/guide/"',
      'description: "Nested English page."',
      "---",
      "",
      "# Guide",
      "",
      "English nested page.",
      "",
    ].join("\n"),
    "utf8",
  );
  fs.writeFileSync(
    path.join(tempRoot, "docs", "public-docs.json"),
    JSON.stringify(
      {
        sections: [
          {
            name: "PDTBar",
            pages: ["public/index.nl.md", "public/index.en.md", "public/guide.nl.md", "public/guide.en.md"],
          },
        ],
      },
      null,
      2,
    ),
    "utf8",
  );

  try {
    execFileSync("make", ["docs-site"], {
      cwd: root,
      env: {
        ...process.env,
        PDTBAR_DOCS_SITE_ROOT: tempRoot,
        PDTBAR_DOCS_SITE_OUT: outDir,
        TMPDIR: os.tmpdir(),
      },
      encoding: "utf8",
      stdio: "pipe",
    });

    const index = fs.readFileSync(path.join(outDir, "index.html"), "utf8");
    const english = fs.readFileSync(path.join(outDir, "en", "index.html"), "utf8");
    const nestedDutch = fs.readFileSync(path.join(outDir, "gids", "index.html"), "utf8");
    const nestedEnglish = fs.readFileSync(path.join(outDir, "en", "guide", "index.html"), "utf8");
    const llms = fs.readFileSync(path.join(outDir, "llms.txt"), "utf8");
    const llmsFull = fs.readFileSync(path.join(outDir, "llms-full.txt"), "utf8");
    const sitemap = fs.readFileSync(path.join(outDir, "sitemap.xml"), "utf8");
    const robots = fs.readFileSync(path.join(outDir, "robots.txt"), "utf8");
    const social = fs.readFileSync(path.join(outDir, "social-card.svg"), "utf8");

    for (const rel of [
      "index.html",
      "en/index.html",
      "gids/index.html",
      "en/guide/index.html",
      "favicon.svg",
      "social-card.svg",
      "sitemap.xml",
      "robots.txt",
      "llms.txt",
      "llms-full.txt",
      ".nojekyll",
    ]) {
      assert.ok(fs.existsSync(path.join(outDir, rel)), `${rel} should exist`);
    }

    assert.match(index, /<html lang="nl"/);
    assert.match(index, /PDTBar/);
    assert.match(index, /laat de belangrijkste signalen uit je Portfolio Dividend Tracker-portefeuille zien/);
    assert.match(index, /Portfolio Dividend Tracker/);
    assert.match(index, /Claude CLI/);
    assert.match(index, /PDT MCP/);
    assert.match(index, /draait lokaal en wijzigt niets/);
    assert.match(index, /Concentratie/);
    assert.match(index, /Inkomsten/);
    assert.match(index, /Grote bewegingen/);
    assert.match(index, /hoe vers je PDT-gegevens zijn/);
    assert.match(index, /niets bijzonders speelt/);
    assert.match(index, /href="en\/"/);
    assert.match(index, /aria-label="View this page in English"/);
    assert.match(index, /id="doc-search"/);
    assert.match(index, /data-theme-toggle/);
    assert.match(index, /class="nav-toggle"/);
    assert.match(index, /class="home-hero"/);
    assert.match(index, /class="pulse-art"/);
    assert.match(index, /application\/ld\+json/);
    assert.match(index, /"@type":"SoftwareApplication"/);
    assert.match(index, /"applicationCategory":"FinanceApplication"/);
    assert.match(index, /"operatingSystem":"macOS"/);
    assert.match(index, /PDTBar JSON-LD escape \\u003C\/script\\u003E\\u003Cscript\\u003Ealert\(1\)\\u003C\/script\\u003E sentinel/);
    assert.doesNotMatch(index, /<\/script><script>alert\(1\)<\/script>/);
    assert.match(index, /<link rel="canonical" href="https:\/\/bramvr\.github\.io\/pdtbar\/">/);
    assert.match(index, /href="https:\/\/example\.com\?a=1&amp;b=2"/);
    assert.doesNotMatch(index, /javascript:alert/);

    assert.match(english, /<html lang="en"/);
    assert.match(english, /quiet macOS menu bar/);
    assert.match(english, /local and read-only by default/);
    assert.match(english, /href="\.\.\/"/);
    assert.match(english, /aria-label="Bekijk deze pagina in het Nederlands"/);
    assert.match(english, /<link rel="canonical" href="https:\/\/bramvr\.github\.io\/pdtbar\/en\/">/);
    assert.doesNotMatch(english, /java\tscript:alert/);

    assert.match(nestedDutch, /<link rel="icon" href="\.\.\/favicon\.svg"/);
    assert.match(nestedDutch, /<a class="brand" href="\.\.\/">/);
    assert.match(nestedDutch, /<a class="btn" href="\.\.\/en\/guide\/" aria-label="View this page in English">English<\/a>/);
    assert.match(nestedDutch, /<a class="nav-link" href="\.\.\/">Nederlands<\/a>/);
    assert.match(nestedDutch, /<a class="nav-link" href="\.\.\/en\/">English<\/a>/);

    assert.match(nestedEnglish, /<link rel="icon" href="\.\.\/\.\.\/favicon\.svg"/);
    assert.match(nestedEnglish, /<a class="brand" href="\.\.\/\.\.\/">/);
    assert.match(nestedEnglish, /<a class="btn" href="\.\.\/\.\.\/gids\/" aria-label="Bekijk deze pagina in het Nederlands">Nederlands<\/a>/);
    assert.match(nestedEnglish, /<a class="nav-link" href="\.\.\/\.\.\/">Nederlands<\/a>/);
    assert.match(nestedEnglish, /<a class="nav-link" href="\.\.\/">English<\/a>/);

    const combined = `${index}\n${english}\n${llms}\n${llmsFull}`;
    assert.doesNotMatch(combined, /INTERNAL_ONLY_SENTINEL_PDT_PORTFOLIO_PATH/);
    assert.doesNotMatch(combined, /manual-first-run|agent-facing|AGENTS|CLAUDE|\/Users\/bram|private-agent-notes/);
    assert.ok(!fs.existsSync(path.join(outDir, "private-agent-notes.html")));
    assert.ok(!fs.existsSync(path.join(outDir, "DEVELOPMENT.html")));
    assert.ok(!fs.existsSync(path.join(outDir, "adr", "0001-core-architecture-and-stack.html")));

    assert.match(llms, /Canonical public documentation URLs:/);
    assert.match(llms, /- PDTBar \(Dutch\): https:\/\/bramvr\.github\.io\/pdtbar\//);
    assert.match(llms, /- PDTBar \(English\): https:\/\/bramvr\.github\.io\/pdtbar\/en\//);
    assert.match(llmsFull, /Source: https:\/\/github\.com\/BramVR\/pdtbar\/blob\/main\/docs\/public\/index\.nl\.md/);
    assert.match(sitemap, /<loc>https:\/\/bramvr\.github\.io\/pdtbar\/<\/loc>/);
    assert.match(sitemap, /<loc>https:\/\/bramvr\.github\.io\/pdtbar\/en\/<\/loc>/);
    assert.match(robots, /Sitemap: https:\/\/bramvr\.github\.io\/pdtbar\/sitemap\.xml/);
    assert.match(social, /PDTBar/);
    assert.match(social, /quiet portfolio pulse/i);
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});

test("pages workflow builds, tests, smoke-checks, and skips disabled Pages safely", () => {
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
    "dist/docs-site/sitemap.xml",
    "dist/docs-site/robots.txt",
    "dist/docs-site/llms.txt",
    "dist/docs-site/llms-full.txt",
    "dist/docs-site/favicon.svg",
    "dist/docs-site/social-card.svg",
    "dist/docs-site/.nojekyll",
    'grep -q "PDTBar" dist/docs-site/index.html',
    'grep -q "https://bramvr.github.io/pdtbar/" dist/docs-site/index.html',
    "gh api \"repos/${GITHUB_REPOSITORY}/pages\"",
    "Pages is not enabled; built and smoke-tested docs-site artifact without deploying.",
    "actions/upload-pages-artifact",
    "path: dist/docs-site",
    "actions/deploy-pages",
  ]) {
    assert.match(workflow, new RegExp(escapeRegExp(expected)));
  }

  assert.match(workflow, /if: github\.event_name != 'pull_request' && github\.ref == 'refs\/heads\/main'/);
});

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
