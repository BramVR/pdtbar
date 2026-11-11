import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { menuCapture } from "./docs-site/menu-capture.mjs";
import { strings } from "./docs-site/strings.mjs";

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
        'description: "PDTBar toont in de macOS-menubalk wat er nu toe doet in je Portfolio Dividend Tracker-portefeuille."',
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
      "## Eerste Stap",
      "",
      "Nederlandse sectie.",
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
      "## First Step",
      "",
      "English section.",
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
      "pdtbar-hero.png",
      "pdtbar-menu.png",
    ]) {
      assert.ok(fs.existsSync(path.join(outDir, rel)), `${rel} should exist`);
    }

    assert.match(index, /<html lang="nl"/);
    assert.match(index, /PDTBar/);
    assert.match(index, /wat er nu toe doet in je Portfolio Dividend Tracker-portefeuille/);
    assert.match(index, /href="#wat-je-ziet">Bekijk het overzicht/);
    assert.match(index, /Portfolio Dividend Tracker/);
    assert.match(index, /rechtstreeks uit PDT, met alleen leesrechten/);
    assert.match(index, /Sign in with PDT/);
    assert.doesNotMatch(index, /Claude CLI|PDT MCP/);
    assert.match(index, /draait lokaal en verandert niets aan je portefeuille/);
    assert.match(index, /Concentratie/);
    assert.match(index, /Inkomsten/);
    assert.match(index, /Grote bewegingen/);
    assert.match(index, /hoe actueel je PDT-gegevens zijn/);
    assert.match(index, /Geen bijzonderheden/);
    assert.doesNotMatch(index, /Een rustig portefeuilleoverzicht|Rustig beeld|in-een-oogopslag/);
    assert.match(index, /href="en\/"/);
    assert.match(index, /aria-label="View this page in English"/);
    assert.match(index, /data-theme-toggle/);
    assert.match(index, /Installeer PDTBar/);
    assert.match(index, /Homebrew wordt nog niet ondersteund/);
    assert.match(index, /PDTBar\.app\.zip/);
    assert.deepEqual(imageNamed(index, "pdtbar-menu.png"), { src: "pdtbar-menu.png", width: "768", height: "1518", alt: strings.nl.captureAlt });
    assert.deepEqual(imageNamed(english, "pdtbar-menu.png"), { src: "../pdtbar-menu.png", width: "768", height: "1518", alt: strings.en.captureAlt });
    assert.doesNotMatch(index, /pulse-fill/);
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
    assert.match(english, /Install PDTBar/);
    assert.match(english, /Homebrew is not supported yet/);
    assert.match(english, /PDTBar\.app\.zip/);
    assert.match(english, /href="\.\.\/"/);
    assert.match(english, /aria-label="Bekijk deze pagina in het Nederlands"/);
    assert.match(english, /<link rel="canonical" href="https:\/\/bramvr\.github\.io\/pdtbar\/en\/">/);
    assert.doesNotMatch(english, /java\tscript:alert/);

    assert.match(nestedDutch, /<link rel="icon" href="\.\.\/favicon\.svg"/);
    assert.ok(hasLink(nestedDutch, { href: "../", name: "PDTBar" }));
    assert.ok(hasLink(nestedDutch, { href: "../en/guide/", name: "View this page in English" }));
    assert.ok(hasLink(nestedDutch, { href: "../en/guide/", name: "English" }));
    assert.ok(hasLink(nestedDutch, { href: "./", name: "Gids", current: "page" }));
    assert.ok(!hasLink(nestedDutch, { href: "../en/" }));

    assert.match(nestedEnglish, /<link rel="icon" href="\.\.\/\.\.\/favicon\.svg"/);
    assert.ok(hasLink(nestedEnglish, { href: "../", name: "PDTBar" }));
    assert.ok(hasLink(nestedEnglish, { href: "../../gids/", name: "Bekijk deze pagina in het Nederlands" }));
    assert.ok(hasLink(nestedEnglish, { href: "../../gids/", name: "Nederlands" }));
    assert.ok(hasLink(nestedEnglish, { href: "./", name: "Guide", current: "page" }));
    assert.ok(!hasLink(nestedEnglish, { href: "../../" }));

    assert.ok(hasLink(index, { href: "./", name: "PDTBar", current: "page" }));
    assert.ok(hasLink(index, { href: "gids/", name: "Gids" }));
    assert.ok(!hasLink(index, { current: "page", name: "Gids" }));
    assert.ok(hasLink(english, { href: "./", name: "PDTBar", current: "page" }));

    assert.match(index, /<h1 id="pdtbar">/, "/#pdtbar should still land on the home heading");
    assert.match(english, /<h1 id="pdtbar">/, "/en/#pdtbar should still land on the home heading");

    assert.doesNotMatch(index, /<details/);
    assert.match(nestedEnglish, /<details[\s\S]*<summary[^>]*>On this page<\/summary>[\s\S]*<\/details>/);
    assert.match(nestedDutch, /<summary[^>]*>Op deze pagina<\/summary>/);
    assert.ok(hasLink(nestedEnglish, { href: "#first-step", name: "First Step" }));
    assert.ok(hasLink(nestedDutch, { href: "#eerste-stap", name: "Eerste Stap" }));

    for (const [name, html] of Object.entries({ index, english, nestedDutch, nestedEnglish })) {
      assert.equal(html.match(/<h1[\s>]/g)?.length, 1, `${name} should have exactly one h1`);
      assert.match(html, /<main id="main"/, `${name} should have a main landmark`);
      assert.ok(hasLink(html, { href: "#main" }), `${name} should have a skip link`);
      assert.doesNotMatch(html, /pdtbar-hero/, `${name} should not show the illustrated mock`);
      assert.doesNotMatch(html, /<script[^>]*\ssrc=|<link[^>]*rel="stylesheet"|@import|@font-face|url\(\s*["']?(?:https?:)?\/\//, `${name} should load no script, stylesheet, or font over the network`);

      const css = html.match(/<style>([\s\S]*?)<\/style>/)[1];
      assert.match(css, /@media \(prefers-reduced-motion: reduce\)/, `${name} should turn motion off on request`);
      assert.doesNotMatch(css, /opacity:\s*0(?:\.0*)?(?![.\d])/, `${name} should not hide content at opacity 0`);
    }

    assert.doesNotMatch(`${nestedDutch}\n${nestedEnglish}`, /Claude|MCP/i);

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

    const site = "https://bramvr.github.io/pdtbar";
    const alternates = (html) => Object.fromEntries([...html.matchAll(/<link rel="alternate" hreflang="([^"]+)" href="([^"]+)">/g)].map((match) => [match[1], match[2]]));
    for (const [name, html, dutchUrl, englishUrl] of [
      ["index", index, `${site}/`, `${site}/en/`],
      ["english", english, `${site}/`, `${site}/en/`],
      ["nestedDutch", nestedDutch, `${site}/gids/`, `${site}/en/guide/`],
      ["nestedEnglish", nestedEnglish, `${site}/gids/`, `${site}/en/guide/`],
    ]) {
      assert.deepEqual(alternates(html), { nl: dutchUrl, en: englishUrl, "x-default": dutchUrl }, `${name} should name Dutch as the default alternate`);
    }
    assert.match(index, /<meta property="og:locale" content="nl_NL">/);
    assert.match(index, /<meta property="og:locale:alternate" content="en_US">/);
    assert.match(english, /<meta property="og:locale" content="en_US">/);
    assert.match(index, /"inLanguage":"nl"/);
    assert.match(english, /"inLanguage":"en"/);
    assert.match(index, /aria-current="true">NL<\/span>[\s\S]*?<a href="en\/"[^>]*>EN<\/a>/, "the Dutch root should offer English as the option");
    assert.match(sitemap, new RegExp(`<loc>${site}/en/</loc><xhtml:link rel="alternate" hreflang="nl" href="${site}/"/>.*hreflang="x-default" href="${site}/"/>`));
    assert.ok(sitemap.indexOf(`<loc>${site}/</loc>`) < sitemap.indexOf(`<loc>${site}/en/</loc>`), "the default language should come first in the sitemap");
    assert.match(llms, /Default language: Dutch \(nl\), served from the site root\. English \(en\) pages live under \/en\/\./);
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
    "dist/docs-site/pdtbar-hero.png",
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

test("docs-site template strings exist in both languages", () => {
  assert.deepEqual(Object.keys(strings.nl).sort(), Object.keys(strings.en).sort());
  for (const [lang, table] of Object.entries(strings)) {
    for (const [key, value] of Object.entries(table)) {
      assert.ok(typeof value === "string" && value.trim(), `${lang}.${key} should be a non-empty string`);
    }
    for (const callout of menuCapture.callouts) {
      assert.ok(table[callout.label], `${lang} should label the ${callout.label} callout`);
    }
  }
});

function links(html) {
  return [...html.matchAll(/<a\s([^>]*)>([\s\S]*?)<\/a>/g)].map(([, attributes, inner]) => ({
    href: attribute(attributes, "href"),
    current: attribute(attributes, "aria-current"),
    name: attribute(attributes, "aria-label") ?? inner.replace(/<svg[\s\S]*?<\/svg>/g, "").replace(/<[^>]+>/g, "").trim(),
  }));
}

function hasLink(html, expected) {
  return links(html).some((link) => Object.entries(expected).every(([key, value]) => link[key] === value));
}

function imageNamed(html, file) {
  const attributes = html.match(new RegExp(`<img\\s([^>]*${escapeRegExp(file)}[^>]*)>`))?.[1] ?? "";
  return Object.fromEntries(["src", "width", "height", "alt"].map((name) => [name, attribute(attributes, name)]));
}

function attribute(attributes, name) {
  return attributes.match(new RegExp(`(?:^|\\s)${name}="([^"]*)"`))?.[1];
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
