#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { brandMarkSvg, css, faviconSvg, js, preThemeScript, pulseArtSvg, socialCardSvg, themeToggleHtml } from "./docs-site-assets.mjs";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const defaultRoot = path.resolve(scriptDir, "..");
const root = path.resolve(process.env.PDTBAR_DOCS_SITE_ROOT || defaultRoot);
const docsDir = path.join(root, "docs");
const outDir = path.resolve(process.env.PDTBAR_DOCS_SITE_OUT || path.join(root, "dist", "docs-site"));
const repoBase = "https://github.com/BramVR/pdtbar";
const repoSourceBase = `${repoBase}/blob/main/docs`;
const siteBase = "https://bramvr.github.io/pdtbar";
const productName = "PDTBar";
const productTagline = "Quiet portfolio pulse.";
const installHint = "Source build: git clone https://github.com/BramVR/pdtbar.git && cd pdtbar && make build";

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
  const target = path.join(outDir, page.outRel);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, layout({ page, html, toc, sectionName: sectionByRel.get(page.rel) || productName }), "utf8");
}

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
  const manifestPath = path.join(docsDir, "public-docs.json");
  return JSON.parse(fs.readFileSync(manifestPath, "utf8"));
}

function assertSafeOutDir() {
  const relative = path.relative(root, outDir);
  const dedicated = path.join("dist", "docs-site");
  const inRoot = relative && !relative.startsWith("..") && !path.isAbsolute(relative);
  const inDedicatedDocsSiteDir = relative === dedicated || relative.startsWith(`${dedicated}${path.sep}`);
  if (!inRoot || !inDedicatedDocsSiteDir) {
    throw new Error(`unsafe docs-site output directory: ${path.relative(process.cwd(), outDir) || outDir}`);
  }
  assertNoSymlinkedExistingParents(path.dirname(outDir));
}

function assertNoSymlinkedExistingParents(targetDir) {
  const relative = path.relative(root, targetDir);
  let current = root;
  for (const part of relative.split(path.sep).filter(Boolean)) {
    current = path.join(current, part);
    if (!fs.existsSync(current)) return;
    if (fs.lstatSync(current).isSymbolicLink()) {
      throw new Error(`unsafe docs-site output parent symlink: ${path.relative(root, current)}`);
    }
  }
}

function assertManifestPagesExist() {
  const missing = [...allowlist].filter((rel) => !pageMap.has(rel));
  if (missing.length) {
    throw new Error(`docs-site manifest references missing pages: ${missing.join(", ")}`);
  }
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
      lang: frontmatter.lang || "en",
      title: frontmatter.title || firstHeading(markdown) || titleize(path.basename(rel, ".md")),
      description: frontmatter.description || "",
      outRel: outPath(rel, frontmatter),
    };
  });
}

function parseFrontmatter(raw) {
  const match = raw.match(/^---\n([\s\S]*?)\n---\n?/);
  if (!match) return { frontmatter: {}, body: raw };
  const frontmatter = {};
  for (const line of match[1].split("\n")) {
    const parsed = line.match(/^([A-Za-z0-9_-]+):\s*(.*?)\s*$/);
    if (!parsed) continue;
    let value = parsed[2].trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }
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

function outPath(rel, frontmatter = {}) {
  if (frontmatter.permalink) {
    const permalink = normalizePermalink(frontmatter.permalink);
    return permalink === "/" ? "index.html" : `${permalink.slice(1)}/index.html`;
  }
  return rel === "index.md" ? "index.html" : rel.replace(/\.md$/, ".html");
}

function assertSafePageOutRel(outRel) {
  const normalized = path.posix.normalize(outRel);
  const safeUrlPath = /^[A-Za-z0-9._~/-]+$/.test(outRel);
  if (!safeUrlPath || outRel.includes("\\") || /^[A-Za-z]:/.test(outRel) || normalized !== outRel || normalized.startsWith("../") || normalized === ".." || path.posix.isAbsolute(outRel)) {
    throw new Error(`unsafe docs-site page output path: ${outRel}`);
  }
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

  const flushParagraph = () => {
    if (!paragraph.length) return;
    html.push(`<p>${inline(paragraph.join(" "), currentRel)}</p>`);
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
      const id = slug(text);
      if (level === 1) {
        html.push(`<h1 id="${id}">${inline(text, currentRel)}</h1>`);
      } else {
        html.push(`<h${level} id="${id}"><a class="anchor" href="#${id}" aria-label="Anchor link">#</a>${inline(text, currentRel)}</h${level}>`);
      }
      continue;
    }
    const bullet = line.match(/^\s*-\s+(.+)$/);
    const numbered = line.match(/^\s*\d+\.\s+(.+)$/);
    if (bullet || numbered) {
      flushParagraph();
      const tag = bullet ? "ul" : "ol";
      if (list && list !== tag) closeList();
      if (!list) {
        list = tag;
        html.push(`<${tag}>`);
      }
      html.push(`<li>${inline((bullet || numbered)[1], currentRel)}</li>`);
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
  const tokens = [];
  let text = escapeHtml(value);
  text = text.replace(/`([^`]+)`/g, (_, code) => {
    const token = `@@CODE${tokens.length}@@`;
    tokens.push(`<code>${escapeHtml(code)}</code>`);
    return token;
  });
  text = text.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
  text = text.replace(/\[([^\]]+)\]\(([^)]+)\)/g, (_, label, target) => {
    const href = resolveHref(unescapeHtml(target), currentRel);
    return `<a href="${escapeAttr(href)}">${label}</a>`;
  });
  for (const [idx, token] of tokens.entries()) text = text.replace(`@@CODE${idx}@@`, token);
  return text;
}

function resolveHref(target, currentRel) {
  const trimmed = target.trim();
  if (/^(https?:|mailto:|tel:)/i.test(trimmed) || trimmed.startsWith("#")) return trimmed;
  if (!trimmed || trimmed === "#") return "#";
  const [withoutHash, hash = ""] = trimmed.split("#");
  const base = path.posix.dirname(currentRel);
  const normalized = path.posix.normalize(path.posix.join(base === "." ? "" : base, withoutHash));
  const targetPage = pageMap.get(normalized);
  if (!targetPage) return "#";
  const fromDir = path.posix.dirname(pageMap.get(currentRel)?.outRel || "index.html");
  const relative = path.posix.relative(fromDir === "." ? "" : fromDir, targetPage.outRel);
  return `${relative || path.posix.basename(targetPage.outRel)}${hash ? `#${hash}` : ""}`;
}

function tocFromHtml(html) {
  return [...html.matchAll(/<h([23]) id="([^"]+)">(?:<a[^>]+>[^<]+<\/a>)?([\s\S]*?)<\/h\1>/g)].map((match) => ({
    level: Number(match[1]),
    id: match[2],
    title: stripTags(match[3]),
  }));
}

function layout({ page, html, toc, sectionName }) {
  const canonical = canonicalUrl(page);
  const alternate = alternatePage(page);
  const isDutch = page.lang === "nl";
  const lede = isDutch
    ? "Een rustig portefeuilleoverzicht in de macOS-menubalk, via je bestaande Claude CLI en PDT MCP-koppeling."
    : "A quiet portfolio pulse in the macOS menu bar, powered by your existing Claude CLI + PDT MCP setup.";
  const searchLabel = isDutch ? "Zoek in de site" : "Search";
  const searchPlaceholder = isDutch ? "Filter onderwerpen" : "Filter navigation";
  const noResults = isDutch ? "Niets gevonden." : "No results.";
  const langHref = hrefBetween(page, alternate);
  const langLabel = isDutch ? "English" : "Nederlands";
  const langAria = isDutch ? "View this page in English" : "Bekijk deze pagina in het Nederlands";
  const pulseAnchor = isDutch ? "in-een-oogopslag" : "what-you-see";
  const jsonLd = {
    "@context": "https://schema.org",
    "@type": "SoftwareApplication",
    name: productName,
    applicationCategory: "FinanceApplication",
    operatingSystem: "macOS",
    description: page.description,
    url: canonical,
    codeRepository: repoBase,
    isAccessibleForFree: true,
  };

  return `<!doctype html>
<html lang="${escapeAttr(page.lang)}" data-theme="light">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${escapeHtml(page.title)} - ${productTagline}</title>
  <meta name="description" content="${escapeAttr(page.description)}">
  <meta name="theme-color" content="#f7f8f4">
  <meta name="application-name" content="${productName}">
  <link rel="canonical" href="${canonical}">
  <link rel="alternate" hreflang="nl" href="${siteBase}/">
  <link rel="alternate" hreflang="en" href="${siteBase}/en/">
  <link rel="icon" href="${assetHref(page, "favicon.svg")}" type="image/svg+xml">
  <meta property="og:title" content="${escapeAttr(page.title)}">
  <meta property="og:description" content="${escapeAttr(page.description)}">
  <meta property="og:type" content="website">
  <meta property="og:url" content="${canonical}">
  <meta property="og:image" content="${siteBase}/social-card.svg">
  <script>${preThemeScript()}</script>
  <style>${css()}</style>
  <script type="application/ld+json">${jsonForHtmlScript(jsonLd)}</script>
</head>
<body>
  <button class="nav-toggle" type="button" aria-label="Toggle navigation" aria-expanded="false"><span></span><span></span><span></span></button>
  ${themeToggleHtml("theme-float")}
  <div class="shell">
    <aside class="sidebar">
      <div class="sidebar-head">
        <a class="brand" href="${homeHref(page)}">
          <span class="mark">${brandMarkSvg()}</span>
          <span><strong>PDTBar</strong><small>${productTagline}</small></span>
        </a>
        ${themeToggleHtml()}
      </div>
      <div class="lang-switch" aria-label="Language">
        <a class="${isDutch ? "active" : ""}" href="${hrefBetween(page, pageForLang("nl"))}">NL</a>
        <a class="${isDutch ? "" : "active"}" href="${hrefBetween(page, pageForLang("en"))}">EN</a>
      </div>
      <label class="search"><span>${searchLabel}</span><input id="doc-search" type="search" placeholder="${searchPlaceholder}" autocomplete="off"></label>
      <nav aria-label="Documentation">
        ${navHtml(page, sectionName)}
      </nav>
      <p class="no-results">${noResults}</p>
    </aside>
    <main>
      <header class="home-hero">
        <div>
          <p class="eyebrow">${escapeHtml(sectionName)}</p>
          <h1>PDTBar</h1>
          <p class="lede">${lede}</p>
          <div class="actions">
            <a class="btn primary" href="#${pulseAnchor}">${isDutch ? "Bekijk het overzicht" : "View the pulse"}</a>
            <a class="btn" href="${escapeAttr(langHref)}" aria-label="${langAria}">${langLabel}</a>
            <a class="btn" href="${repoBase}">GitHub</a>
          </div>
        </div>
        <div class="hero-art">${pulseArtSvg()}</div>
        <div class="feature-row" aria-label="Product focus">
          ${(isDutch ? ["Concentratie", "Inkomensmomenten", "Opvallende bewegingen", "Actuele gegevens", "Rustig beeld"] : ["Concentration", "Income events", "Big movers", "Freshness", "All quiet"]).map((label) => `<a class="feature-pill" href="#${pulseAnchor}">${label}</a>`).join("")}
        </div>
      </header>
      <div class="doc-grid">
        <article class="doc">${html}</article>
        ${tocHtml(toc, isDutch)}
      </div>
    </main>
  </div>
  <script>${js()}</script>
</body>
</html>`;
}

function navHtml(currentPage, sectionName) {
  return nav
    .map((section) => `<section><h2>${escapeHtml(section.name)}</h2>${section.pages.map((page) => {
      const active = page.rel === currentPage.rel ? " active" : "";
      return `<a class="nav-link${active}" href="${escapeAttr(hrefBetween(currentPage, page))}">${escapeHtml(page.lang === "nl" ? "Nederlands" : "English")}</a>`;
    }).join("")}</section>`)
    .join("");
}

function tocHtml(toc, isDutch) {
  if (!toc.length) return "";
  const heading = isDutch ? "Op deze pagina" : "On this page";
  return `<aside class="toc"><h2>${heading}</h2>${toc.map((item) => `<a class="toc-l${item.level}" href="#${item.id}">${escapeHtml(item.title)}</a>`).join("")}</aside>`;
}

function pageForLang(lang) {
  return pages.find((page) => page.lang === lang) || pages[0];
}

function alternatePage(page) {
  return pageForLang(page.lang === "nl" ? "en" : "nl");
}

function homeHref(page) {
  return page.lang === "en" ? "../" : "./";
}

function assetHref(page, rel) {
  return page.lang === "en" ? `../${rel}` : rel;
}

function hrefBetween(fromPage, toPage) {
  const fromDir = path.posix.dirname(fromPage.outRel);
  const fromBase = fromDir === "." ? "" : fromDir;
  const relative = path.posix.relative(fromBase, toPage.outRel);
  if (toPage.outRel === "index.html") return fromPage.outRel === "index.html" ? "./" : "../";
  if (toPage.outRel === "en/index.html") return fromPage.outRel === "index.html" ? "en/" : "./";
  return relative || "./";
}

function canonicalUrl(page) {
  return `${siteBase}${urlPathFor(page)}`;
}

function sourceUrl(page) {
  return `${repoSourceBase}/${page.rel}`;
}

function urlPathFor(page) {
  if (page.outRel === "index.html") return "/";
  if (page.outRel.endsWith("/index.html")) return `/${page.outRel.slice(0, -"index.html".length)}`;
  return `/${page.outRel}`;
}

function llmsTxt() {
  return [
    "# PDTBar Public Docs",
    "",
    "Canonical public documentation URLs:",
    ...orderedPages.map((page) => `- PDTBar (${page.lang === "nl" ? "Dutch" : "English"}): ${canonicalUrl(page)}`),
    "",
    "Public Markdown source URLs:",
    ...orderedPages.map((page) => `- ${page.title} (${page.lang}): ${sourceUrl(page)}`),
    "",
    `Install/build hint: ${installHint}`,
    `Source repository: ${repoBase}`,
    "",
  ].join("\n");
}

function llmsFullTxt() {
  return orderedPages
    .map((page) => [`# ${page.title} (${page.lang})`, "", `Canonical: ${canonicalUrl(page)}`, `Source: ${sourceUrl(page)}`, "", page.markdown.trim(), ""].join("\n"))
    .join("\n");
}

function sitemapXml() {
  const urls = orderedPages
    .map((page) => `  <url><loc>${canonicalUrl(page)}</loc></url>`)
    .join("\n");
  return `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls}\n</urlset>\n`;
}

function robotsTxt() {
  return [`User-agent: *`, `Allow: /`, `Sitemap: ${siteBase}/sitemap.xml`, ""].join("\n");
}

function validateLinks(dir) {
  for (const file of allOutputHtml(dir)) {
    const html = fs.readFileSync(file, "utf8");
    for (const match of html.matchAll(/\s(?:href|src)="([^"]+)"/g)) {
      const target = match[1];
      if (/^(https?:|mailto:|tel:|#)/i.test(target) || target.startsWith("data:")) continue;
      const resolved = path.resolve(path.dirname(file), target.split("#")[0]);
      if (!resolved.startsWith(dir) || !fs.existsSync(resolved)) {
        throw new Error(`broken docs-site link in ${path.relative(dir, file)}: ${target}`);
      }
    }
  }
}

function allOutputHtml(dir) {
  return fs
    .readdirSync(dir, { withFileTypes: true })
    .flatMap((entry) => {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) return allOutputHtml(full);
      return entry.name.endsWith(".html") ? [full] : [];
    })
    .sort();
}

function slug(input) {
  return stripTags(input)
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[^\w\s-]/g, "")
    .trim()
    .replace(/\s+/g, "-")
    .replace(/_+/g, "-");
}

function stripTags(value) {
  return value.replace(/<[^>]+>/g, "").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&");
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function escapeAttr(value) {
  return escapeHtml(value).replaceAll("'", "&#39;");
}

function unescapeHtml(value) {
  return String(value)
    .replaceAll("&amp;", "&")
    .replaceAll("&lt;", "<")
    .replaceAll("&gt;", ">")
    .replaceAll("&quot;", '"');
}

function jsonForHtmlScript(value) {
  return JSON.stringify(value)
    .replaceAll("&", "\\u0026")
    .replaceAll("<", "\\u003C")
    .replaceAll(">", "\\u003E")
    .replaceAll("\u2028", "\\u2028")
    .replaceAll("\u2029", "\\u2029");
}
