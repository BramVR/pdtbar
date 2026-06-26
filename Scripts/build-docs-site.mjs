#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { brandMarkSvg, css, faviconSvg, js, preThemeScript, socialCardSvg, themeToggleHtml } from "./docs-site-assets.mjs";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const defaultRoot = path.resolve(scriptDir, "..");
const root = path.resolve(process.env.PDTBAR_DOCS_SITE_ROOT || defaultRoot);
const docsDir = path.join(root, "docs");
const outDir = path.resolve(process.env.PDTBAR_DOCS_SITE_OUT || path.join(root, "dist", "docs-site"));
const repoBase = "https://github.com/BramVR/pdtbar";
const repoSourceBase = `${repoBase}/blob/main/docs`;
const repoEditBase = `${repoBase}/edit/main/docs`;
const siteBase = "https://bramvr.github.io/pdtbar";
const productName = "PDTBar";
const productTagline = "Quiet pulse.";
const productDescription =
  "PDTBar is a quiet macOS menu bar companion for Portfolio Dividend Tracker portfolios, using Claude CLI and PDT MCP to surface only the attention items that matter now.";
const installHint = "Source build: git clone https://github.com/BramVR/pdtbar.git && cd pdtbar && make start";

const manifest = readManifest();
const sections = manifest.sections.map((section) => [section.name, section.pages]);
const allowlist = new Set(sections.flatMap(([, rels]) => rels));

const pages = loadPages().filter((page) => allowlist.has(page.rel));
const pageMap = new Map(pages.map((page) => [page.rel, page]));
assertManifestPagesExist();

const nav = sections
  .map(([name, rels]) => ({ name, pages: rels.map((rel) => pageMap.get(rel)).filter(Boolean) }))
  .filter((section) => section.pages.length);
const orderedPages = nav.flatMap((section) => section.pages);
const sectionByRel = new Map(nav.flatMap((section) => section.pages.map((page) => [page.rel, section.name])));

assertSafeOutDir();
fs.rmSync(outDir, { recursive: true, force: true });
fs.mkdirSync(outDir, { recursive: true });

for (const page of pages) {
  assertSafePageOutRel(page.outRel);
  const html = markdownToHtml(page.markdown, page.rel);
  const toc = tocFromHtml(html);
  const idx = orderedPages.findIndex((candidate) => candidate.rel === page.rel);
  const prev = idx > 0 ? orderedPages[idx - 1] : null;
  const next = idx >= 0 && idx < orderedPages.length - 1 ? orderedPages[idx + 1] : null;
  const target = path.join(outDir, page.outRel);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, layout({ page, html, toc, prev, next, sectionName: sectionByRel.get(page.rel) || "Start" }), "utf8");
}

copyManifestAssets();
fs.writeFileSync(path.join(outDir, "favicon.svg"), faviconSvg(), "utf8");
fs.writeFileSync(path.join(outDir, "social-card.svg"), socialCardSvg(), "utf8");
fs.writeFileSync(path.join(outDir, ".nojekyll"), "", "utf8");
fs.writeFileSync(path.join(outDir, "llms.txt"), llmsTxt(), "utf8");
fs.writeFileSync(path.join(outDir, "llms-full.txt"), llmsFullTxt(), "utf8");
fs.writeFileSync(path.join(outDir, "sitemap.xml"), sitemapXml(), "utf8");
fs.writeFileSync(path.join(outDir, "robots.txt"), robotsTxt(), "utf8");
validateLinks(outDir);

console.log(`built docs site: ${path.relative(root, outDir)}`);

function readManifest() {
  return JSON.parse(fs.readFileSync(path.join(docsDir, "public-docs.json"), "utf8"));
}

function assertSafeOutDir() {
  const relative = path.relative(root, outDir);
  const dedicated = relative === path.join("dist", "docs-site") || relative.startsWith(`${path.join("dist", "docs-site")}${path.sep}`);
  const inRoot = relative && !relative.startsWith("..") && !path.isAbsolute(relative);
  if (!inRoot || !dedicated) throw new Error(`unsafe docs-site output directory: ${outDir}`);
}

function assertSafePageOutRel(outRel) {
  const normalized = path.posix.normalize(outRel);
  const safeUrlPath = /^[A-Za-z0-9._~/-]+$/.test(outRel);
  if (!safeUrlPath || outRel.includes("\\") || /^[A-Za-z]:/.test(outRel) || normalized !== outRel || normalized.startsWith("../") || normalized === ".." || path.posix.isAbsolute(outRel)) {
    throw new Error(`unsafe docs-site output path: ${outRel}`);
  }
}

function assertManifestPagesExist() {
  const missing = [...allowlist].filter((rel) => !pageMap.has(rel));
  if (missing.length) throw new Error(`docs-site manifest references missing pages: ${missing.join(", ")}`);
}

function loadPages() {
  return allMarkdown(docsDir).map((file) => {
    const rel = path.relative(docsDir, file).replaceAll(path.sep, "/");
    const raw = fs.readFileSync(file, "utf8");
    const { frontmatter, body } = parseFrontmatter(raw);
    const markdown = sanitizeMarkdownBody(body);
    return {
      file,
      rel,
      markdown,
      frontmatter,
      lang: frontmatter.lang || "nl",
      title: frontmatter.title || firstHeading(markdown) || titleize(path.basename(rel, ".md")),
      description: frontmatter.description || productDescription,
      outRel: outPath(rel, frontmatter),
    };
  });
}

function allMarkdown(dir) {
  return fs
    .readdirSync(dir, { withFileTypes: true })
    .flatMap((entry) => {
      const full = path.join(dir, entry.name);
      if (entry.isSymbolicLink()) {
        if (entry.name.endsWith(".md")) throw new Error(`unsafe docs-site markdown symlink: ${path.relative(root, full)}`);
        return [];
      }
      if (entry.isDirectory()) return allMarkdown(full);
      if (!entry.name.endsWith(".md")) return [];
      assertPublicSourceFile(full, docsDir, "markdown");
      return [full];
    })
    .sort();
}

function assertPublicSourceFile(file, baseDir, kind) {
  const stat = fs.lstatSync(file);
  if (!stat.isFile()) throw new Error(`unsafe docs-site ${kind} source is not a regular file: ${path.relative(root, file)}`);
  const baseReal = fs.realpathSync(baseDir);
  const fileReal = fs.realpathSync(file);
  const relative = path.relative(baseReal, fileReal);
  if (!relative || relative.startsWith("..") || path.isAbsolute(relative)) {
    throw new Error(`unsafe docs-site ${kind} source outside public tree: ${path.relative(root, file)}`);
  }
}

function parseFrontmatter(raw) {
  const match = raw.match(/^---\n([\s\S]*?)\n---\n?/);
  if (!match) return { frontmatter: {}, body: raw };
  const frontmatter = {};
  for (const line of match[1].split("\n")) {
    const parsed = line.match(/^([A-Za-z0-9_-]+):\s*(.*?)\s*$/);
    if (!parsed) continue;
    let value = parsed[2].trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) value = value.slice(1, -1);
    frontmatter[parsed[1]] = value;
  }
  return { frontmatter, body: raw.slice(match[0].length) };
}

function sanitizeMarkdownBody(body) {
  const lines = body.replace(/\r\n/g, "\n").split("\n");
  let inFence = false;
  const cleaned = [];
  for (const line of lines) {
    if (parseFenceLine(line)) {
      inFence = !inFence;
      cleaned.push(line);
      continue;
    }
    if (inFence) {
      cleaned.push(line);
      continue;
    }
    const withoutDirective = stripDirectiveLine(line);
    if (withoutDirective !== null) cleaned.push(sanitizeUnsafeMarkdownLinks(withoutDirective));
  }
  return cleaned.join("\n");
}

function stripDirectiveLine(line) {
  if (/^\s*\{:\s*[^}]*\}\s*$/.test(line)) return null;
  return line.replace(/\s*\{:\s*[^}]*\}\s*$/, "");
}

function sanitizeUnsafeMarkdownLinks(markdown) {
  return markdown.replace(/\]\(([^)]*)\)/g, (match, rawTarget) => (isSafeMarkdownLinkTarget(rawTarget) ? match : "](#)"));
}

function isSafeMarkdownLinkTarget(rawTarget) {
  const target = rawTarget.trim();
  if (!target) return true;
  if (/[\u0000-\u001F\u007F]/.test(target)) return false;
  if (target.startsWith("//")) return false;
  const scheme = target.match(/^([A-Za-z][A-Za-z0-9+.-]*):/);
  if (!scheme) return true;
  return /^(https?|mailto|tel)$/i.test(scheme[1]);
}

function outPath(rel, frontmatter = {}) {
  if (frontmatter.permalink) {
    const permalink = normalizePermalink(frontmatter.permalink);
    return permalink === "/" ? "index.html" : `${permalink.slice(1)}/index.html`;
  }
  if (rel === "index.md") return "index.html";
  if (rel.endsWith("/index.md")) return rel.replace(/index\.md$/, "index.html");
  return rel.replace(/\.md$/, ".html");
}

function normalizePermalink(value) {
  let permalink = String(value || "").trim();
  if (!permalink.startsWith("/")) permalink = `/${permalink}`;
  return permalink.length > 1 && permalink.endsWith("/") ? permalink.slice(0, -1) : permalink;
}

function firstHeading(markdown) {
  return markdown.match(/^#\s+(.+)$/m)?.[1]?.trim();
}

function titleize(input) {
  return input.replaceAll("-", " ").replace(/\b\w/g, (char) => char.toUpperCase());
}

function parseFenceLine(line) {
  const match = line.match(/^```\s*([A-Za-z0-9_+-]+)?(?:\s+.*)?$/);
  if (!match) return null;
  return { lang: match[1] || "text" };
}

function markdownToHtml(markdown, currentRel) {
  const lines = markdown.replace(/\r\n/g, "\n").split("\n");
  const html = [];
  let paragraph = [];
  let list = null;
  let fence = null;
  let ledePending = true;

  const flushParagraph = () => {
    if (!paragraph.length) return;
    const className = ledePending ? ` class="lede"` : "";
    html.push(`<p${className}>${inline(paragraph.join(" "), currentRel)}</p>`);
    ledePending = false;
    paragraph = [];
  };
  const closeList = () => {
    if (!list) return;
    html.push(`</${list}>`);
    list = null;
  };

  for (const line of lines) {
    const fenceMatch = parseFenceLine(line);
    if (fenceMatch) {
      flushParagraph();
      closeList();
      if (fence) {
        html.push(`<pre><code class="language-${escapeAttr(fence.lang)}">${escapeHtml(fence.lines.join("\n"))}</code></pre>`);
        fence = null;
      } else {
        fence = { lang: fenceMatch.lang, lines: [] };
      }
      continue;
    }
    if (fence) {
      fence.lines.push(line);
      continue;
    }
    if (!line.trim()) {
      flushParagraph();
      closeList();
      continue;
    }
    const heading = line.match(/^(#{1,4})\s+(.+)$/);
    if (heading) {
      flushParagraph();
      closeList();
      const level = heading[1].length;
      const text = heading[2].trim();
      const id = slugify(stripMarkdown(text));
      html.push(`<h${level} id="${escapeAttr(id)}">${inline(text, currentRel)}${level > 1 ? ` <a class="anchor" href="#${escapeAttr(id)}" aria-label="Link to section">#</a>` : ""}</h${level}>`);
      continue;
    }
    const image = line.match(/^!\[([^\]]*)\]\(([^)]+)\)$/);
    if (image) {
      flushParagraph();
      closeList();
      html.push(`<img src="${escapeAttr(rewriteLink(image[2], currentRel))}" alt="${escapeAttr(image[1])}" loading="lazy">`);
      continue;
    }
    const unordered = line.match(/^\s*[-*]\s+(.+)$/);
    const ordered = line.match(/^\s*\d+\.\s+(.+)$/);
    if (unordered || ordered) {
      flushParagraph();
      const wanted = unordered ? "ul" : "ol";
      if (list && list !== wanted) closeList();
      if (!list) {
        list = wanted;
        html.push(`<${list}>`);
      }
      html.push(`<li>${inline((unordered || ordered)[1], currentRel)}</li>`);
      continue;
    }
    paragraph.push(line.trim());
  }
  flushParagraph();
  closeList();
  if (fence) html.push(`<pre><code class="language-${escapeAttr(fence.lang)}">${escapeHtml(fence.lines.join("\n"))}</code></pre>`);
  return html.join("\n");
}

function inline(value, currentRel) {
  const placeholders = [];
  let text = escapeHtml(value);
  text = text.replace(/`([^`]+)`/g, (_, code) => {
    const token = `@@CODE${placeholders.length}@@`;
    placeholders.push(`<code>${escapeHtml(code)}</code>`);
    return token;
  });
  text = text.replace(/\[([^\]]+)\]\(([^)]+)\)/g, (_, label, target) => {
    const href = rewriteLink(unescapeHtml(target), currentRel);
    return `<a href="${escapeAttr(href)}">${label}</a>`;
  });
  text = text.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
  return placeholders.reduce((acc, html, index) => acc.replace(`@@CODE${index}@@`, html), text);
}

function rewriteLink(target, currentRel) {
  const trimmed = String(target || "").trim();
  if (!trimmed || trimmed === "#") return "#";
  if (/^(https?:|mailto:|tel:)/i.test(trimmed) || trimmed.startsWith("#")) return trimmed;
  const [rawPath, hash = ""] = trimmed.split("#");
  if (!rawPath.endsWith(".md")) return trimmed;
  const currentDir = path.posix.dirname(currentRel);
  const resolved = path.posix.normalize(path.posix.join(currentDir === "." ? "" : currentDir, rawPath));
  const page = pageMap.get(resolved);
  if (!page) return "#";
  const fromDir = path.posix.dirname(outPath(currentRel));
  let href = path.posix.relative(fromDir === "." ? "" : fromDir, page.outRel);
  if (!href || href === "") href = "index.html";
  return hash ? `${href}#${hash}` : href;
}

function tocFromHtml(html) {
  const matches = [...html.matchAll(/<h([23]) id="([^"]+)">([\s\S]*?)<\/h\1>/g)];
  return matches.map((match) => ({ level: Number(match[1]), id: match[2], text: stripTags(match[3]).replace(/\s+#$/, "") }));
}

function layout({ page, html, toc, sectionName }) {
  const canonical = pageUrl(page.outRel);
  const alternate = alternatePage(page);
  const alternateUrl = alternate ? pageUrl(alternate.outRel) : canonical;
  const alternateHref = alternate ? relativeFromPage(page.outRel, alternate.outRel) : "#";
  const alternateLabel = page.lang === "nl" ? "English" : "Nederlands";
  const languageName = page.lang === "nl" ? "Nederlands" : "English";
  const searchLabel = page.lang === "nl" ? "Zoeken" : "Search";
  const noResults = page.lang === "nl" ? "Geen resultaten." : "No results.";
  const tocTitle = page.lang === "nl" ? "Op deze pagina" : "On this page";
  const editLabel = page.lang === "nl" ? "Bewerk deze pagina" : "Edit this page";
  const pageTitle = page.title === productName ? productName : `${page.title} - ${productName}`;
  const navHtml = nav
    .map(
      (section) => `<section>
        <h2>${escapeHtml(section.name)}</h2>
        ${section.pages.map((navPage) => navLink(navPage, page)).join("\n")}
      </section>`,
    )
    .join("\n");
  const tocHtml = toc.length
    ? `<aside class="toc" aria-label="${escapeAttr(tocTitle)}"><h2>${escapeHtml(tocTitle)}</h2>${toc
        .map((item) => `<a class="toc-l${item.level}" href="#${escapeAttr(item.id)}">${escapeHtml(item.text)}</a>`)
        .join("")}</aside>`
    : "";
  const jsonLd = {
    "@context": "https://schema.org",
    "@type": "SoftwareApplication",
    name: productName,
    applicationCategory: "FinanceApplication",
    operatingSystem: "macOS",
    url: siteBase,
    description: productDescription,
    codeRepository: repoBase,
  };
  return `<!doctype html>
<html lang="${escapeAttr(page.lang)}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <script>${preThemeScript()}</script>
  <title>${escapeHtml(pageTitle)}</title>
  <meta name="description" content="${escapeAttr(page.description)}">
  <meta name="application-name" content="${escapeAttr(productName)}">
  <meta name="theme-color" content="#f6f5ef">
  <link rel="icon" type="image/svg+xml" href="${escapeAttr(relativeFromPage(page.outRel, "favicon.svg"))}">
  <link rel="canonical" href="${escapeAttr(canonical)}">
  <link rel="alternate" hreflang="${escapeAttr(page.lang)}" href="${escapeAttr(canonical)}">
  <link rel="alternate" hreflang="${escapeAttr(alternate?.lang || page.lang)}" href="${escapeAttr(alternateUrl)}">
  <link rel="alternate" hreflang="x-default" href="${escapeAttr(siteBase)}/">
  <meta property="og:title" content="${escapeAttr(pageTitle)}">
  <meta property="og:description" content="${escapeAttr(page.description)}">
  <meta property="og:type" content="website">
  <meta property="og:url" content="${escapeAttr(canonical)}">
  <meta property="og:image" content="${escapeAttr(siteBase)}/social-card.svg">
  <style>${css()}</style>
  <script type="application/ld+json">${escapeJsonForHtml(JSON.stringify(jsonLd))}</script>
</head>
<body>
  <button class="nav-toggle" type="button" aria-label="Open navigation" aria-expanded="false"><span></span><span></span><span></span></button>
  <div class="shell">
    <aside class="sidebar">
      <div class="sidebar-head">
        <a class="brand" href="${escapeAttr(relativeFromPage(page.outRel, "index.html"))}">
          <span class="mark">${brandMarkSvg()}</span>
          <span><strong>${escapeHtml(productName)}</strong><small>${escapeHtml(productTagline)}</small></span>
        </a>
        <div class="sidebar-actions">
          <a class="lang-button" href="${escapeAttr(alternateHref)}" hreflang="${escapeAttr(alternate?.lang || "")}">${escapeHtml(alternateLabel)}</a>
          ${themeToggleHtml()}
        </div>
      </div>
      <label class="search"><span>${escapeHtml(searchLabel)}</span><input id="doc-search" type="search" placeholder="${escapeAttr(languageName)}"></label>
      <nav aria-label="Documentation">${navHtml}</nav>
      <p class="no-results">${escapeHtml(noResults)}</p>
    </aside>
    <main>
      <div class="doc-grid">
        <article class="doc">${html}
          <p><a href="${escapeAttr(`${repoEditBase}/${page.rel}`)}">${escapeHtml(editLabel)}</a></p>
        </article>
        ${tocHtml}
      </div>
    </main>
  </div>
  <script>${js()}</script>
</body>
</html>`;
}

function navLink(navPage, currentPage) {
  const active = navPage.rel === currentPage.rel ? " active" : "";
  const label = navPage.lang === "nl" ? "Nederlands" : "English";
  return `<a class="nav-link${active}" href="${escapeAttr(relativeFromPage(currentPage.outRel, navPage.outRel))}">${escapeHtml(label)}</a>`;
}

function alternatePage(page) {
  const alternate = page.frontmatter.alternate;
  if (!alternate) return null;
  const fromDir = path.posix.dirname(page.rel);
  const rel = path.posix.normalize(path.posix.join(fromDir === "." ? "" : fromDir, alternate));
  return pageMap.get(rel) || null;
}

function relativeFromPage(fromOutRel, toOutRel) {
  const fromDir = path.posix.dirname(fromOutRel);
  let relative = path.posix.relative(fromDir === "." ? "" : fromDir, toOutRel);
  if (!relative) relative = "index.html";
  return relative;
}

function pageUrl(outRel) {
  if (outRel === "index.html") return `${siteBase}/`;
  if (outRel.endsWith("/index.html")) return `${siteBase}/${outRel.slice(0, -"index.html".length)}`;
  return `${siteBase}/${outRel}`;
}

function copyManifestAssets() {
  for (const asset of manifest.assets || []) {
    const source = path.join(root, asset.from);
    const targetRel = asset.to;
    assertSafePageOutRel(targetRel);
    assertPublicSourceFile(source, root, "asset");
    const target = path.join(outDir, targetRel);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.copyFileSync(source, target);
  }
}

function llmsTxt() {
  const lines = [
    `# ${productName}`,
    "",
    productDescription,
    "",
    "Canonical public documentation URLs:",
    ...orderedPages.map((page) => `- ${page.title} (${page.lang}): ${pageUrl(page.outRel)}`),
    "",
    "Public Markdown source URLs:",
    ...orderedPages.map((page) => `- ${page.title} (${page.lang}): ${repoSourceBase}/${page.rel}`),
    "",
    "Install/build hint:",
    `- ${installHint}`,
    "",
    "Guidance for agents:",
    "- The root page is Dutch by default.",
    "- Prefer the canonical documentation URLs above over README excerpts or package metadata.",
  ];
  return `${lines.join("\n")}\n`;
}

function llmsFullTxt() {
  const blocks = [`# ${productName}`, "", productDescription, ""];
  for (const page of orderedPages) {
    blocks.push("---", `# ${page.title} (${page.lang})`, `Canonical: ${pageUrl(page.outRel)}`, `Source: ${repoSourceBase}/${page.rel}`, "", page.markdown.trim(), "");
  }
  return `${blocks.join("\n")}\n`;
}

function sitemapXml() {
  const urls = orderedPages
    .map((page) => `  <url><loc>${escapeHtml(pageUrl(page.outRel))}</loc></url>`)
    .join("\n");
  return `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls}\n</urlset>\n`;
}

function robotsTxt() {
  return ["User-agent: *", "Allow: /", `Sitemap: ${siteBase}/sitemap.xml`, ""].join("\n");
}

function validateLinks(baseDir) {
  for (const file of allFiles(baseDir).filter((candidate) => candidate.endsWith(".html"))) {
    const html = fs.readFileSync(file, "utf8");
    const attrs = [...html.matchAll(/\s(?:href|src)="([^"]+)"/g)].map((match) => match[1]);
    for (const attr of attrs) {
      if (!attr || attr.startsWith("#") || /^(https?:|mailto:|tel:|data:)/i.test(attr)) continue;
      const [target] = attr.split("#");
      const local = path.resolve(path.dirname(file), target);
      const relative = path.relative(baseDir, local);
      if (relative.startsWith("..") || path.isAbsolute(relative)) throw new Error(`docs-site link escapes output: ${attr}`);
      if (!fs.existsSync(local)) throw new Error(`broken docs-site link in ${path.relative(baseDir, file)}: ${attr}`);
    }
  }
}

function allFiles(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) return allFiles(full);
    return [full];
  });
}

function slugify(value) {
  return value.toLowerCase().replace(/`([^`]+)`/g, "$1").replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "") || "section";
}

function stripMarkdown(value) {
  return value.replace(/!\[([^\]]*)\]\([^)]+\)/g, "$1").replace(/\[([^\]]+)\]\([^)]+\)/g, "$1").replace(/[*_`]/g, "");
}

function stripTags(value) {
  return value.replace(/<[^>]*>/g, "");
}

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char]);
}

function escapeAttr(value) {
  return escapeHtml(value);
}

function unescapeHtml(value) {
  return String(value).replace(/&amp;/g, "&").replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&lt;/g, "<").replace(/&gt;/g, ">");
}

function escapeJsonForHtml(value) {
  return value.replace(/</g, "\\u003c");
}
