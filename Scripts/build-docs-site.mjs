#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { brandMarkSvg, faviconSvg, menuBarStripHtml, socialCardSvg, statusIconSvg, themeToggleHtml } from "./docs-site/graphics.mjs";
import { menuCapture } from "./docs-site/menu-capture.mjs";
import { strings } from "./docs-site/strings.mjs";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const defaultRoot = path.resolve(scriptDir, "..");
const root = path.resolve(process.env.PDTBAR_DOCS_SITE_ROOT || defaultRoot);
const docsDir = path.join(root, "docs");
const outDir = path.resolve(process.env.PDTBAR_DOCS_SITE_OUT || path.join(root, "dist", "docs-site"));
const repoBase = "https://github.com/BramVR/pdtbar";
const repoSourceBase = `${repoBase}/blob/main/docs`;
const siteBase = "https://bramvr.github.io/pdtbar";
const productName = "PDTBar";
const pdtName = "Portfolio Dividend Tracker";
const imagesCheckedByPagesWorkflow = ["pdtbar-hero.png"];
const productTagline = "Quiet portfolio pulse.";
const installHint = "Homebrew is not supported yet. Use a shared PDTBar.app.zip build for now; public app downloads will be listed on GitHub releases once ready.";

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
const siteCss = readSiteAsset("site.css");
const siteJs = readSiteAsset("site.js");
const themePrepaintJs = readSiteAsset("theme-prepaint.js");
const mainHtmlByKind = { home: homeMainHtml, doc: docMainHtml };
const templateStrings = Object.fromEntries(
  Object.entries(strings).map(([lang, table]) => [lang, Object.fromEntries(Object.entries(table).map(([key, value]) => [key, escapeAttr(value)]))]),
);

assertSafeOutDir();
fs.rmSync(outDir, { recursive: true, force: true });
fs.mkdirSync(outDir, { recursive: true });

for (const page of pages) {
  assertSafePageOutRel(page.outRel);
  const html = markdownToHtml(page.markdown, page.rel);
  const target = path.join(outDir, page.outRel);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, layout(page, html), "utf8");
}

fs.writeFileSync(path.join(outDir, "favicon.svg"), faviconSvg(), "utf8");
fs.writeFileSync(path.join(outDir, "social-card.svg"), socialCardSvg(), "utf8");
for (const image of [menuCapture.file, ...imagesCheckedByPagesWorkflow]) {
  fs.copyFileSync(path.join(docsDir, "public", image), path.join(outDir, image));
}
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

function readSiteAsset(name) {
  return fs.readFileSync(path.join(scriptDir, "docs-site", name), "utf8").trim();
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
  const untranslated = pages.filter((page) => !strings[page.lang]);
  if (untranslated.length) {
    throw new Error(`docs-site pages use a language without template strings: ${untranslated.map((page) => page.rel).join(", ")}`);
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
  return [...html.matchAll(/<h2 id="([^"]+)">(?:<a[^>]+>[^<]+<\/a>)?([\s\S]*?)<\/h2>/g)].map((match) => ({
    id: match[1],
    title: stripTags(match[2]),
  }));
}

function layout(page, html) {
  const t = templateStrings[page.lang];
  const canonical = canonicalUrl(page);
  const alternate = alternatePage(page);
  const kind = page.rel === homePageForLang(page.lang).rel ? "home" : "doc";
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
<html lang="${escapeAttr(page.lang)}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${escapeHtml(page.title)} - ${productTagline}</title>
  <meta name="description" content="${escapeAttr(page.description)}">
  <meta name="theme-color" content="#f5f1e8" media="(prefers-color-scheme: light)">
  <meta name="theme-color" content="#0c1311" media="(prefers-color-scheme: dark)">
  <meta name="application-name" content="${productName}">
  <link rel="canonical" href="${canonical}">
  <link rel="alternate" hreflang="${escapeAttr(page.lang)}" href="${canonical}">
  <link rel="alternate" hreflang="${escapeAttr(alternate.lang)}" href="${canonicalUrl(alternate)}">
  <link rel="icon" href="${assetHref(page, "favicon.svg")}" type="image/svg+xml">
  <meta property="og:title" content="${escapeAttr(page.title)}">
  <meta property="og:description" content="${escapeAttr(page.description)}">
  <meta property="og:type" content="website">
  <meta property="og:url" content="${canonical}">
  <meta property="og:image" content="${siteBase}/social-card.svg">
  <script>${themePrepaintJs}</script>
  <style>${siteCss}</style>
  <noscript><style>.theme{display:none}</style></noscript>
  <script type="application/ld+json">${jsonForHtmlScript(jsonLd)}</script>
</head>
<body>
  <a class="skip" href="#main">${t.skipLink}</a>
  ${headerHtml(page, t)}
  <main id="main" class="wrap ${kind}">
    ${mainHtmlByKind[kind](page, html, t)}
  </main>
  ${footerHtml(page, t)}
  <script>${siteJs}</script>
</body>
</html>`;
}

function headerHtml(page, t) {
  const home = homePageForLang(page.lang);
  return `<header class="wrap">
    <div class="top">
      <a class="brand" href="${escapeAttr(hrefBetween(page, home))}"${currentAttr(page, home)}>${brandMarkSvg()}${productName}</a>
      <nav aria-label="${t.siteNav}">
        ${pageLinksHtml(page)}
        <a href="${repoBase}">GitHub</a>
      </nav>
      <div class="lang" role="group" aria-label="${t.languageSwitch}">${languageSwitchHtml(page)}</div>
      ${themeToggleHtml(t.themeToggle)}
    </div>
  </header>`;
}

function footerHtml(page, t) {
  const alternate = alternatePage(page);
  return `<footer class="wrap">
    <div class="foot">
      <a class="brand" href="${escapeAttr(hrefBetween(page, homePageForLang(page.lang)))}">${brandMarkSvg()}${productName}</a>
      <p>${t.footerLine}</p>
      <nav aria-label="${t.footerNav}">
        ${pageLinksHtml(page)}
        <a href="${repoBase}">GitHub</a>
        <a href="${escapeAttr(hrefBetween(page, alternate))}" lang="${alternate.lang}" hreflang="${alternate.lang}">${templateStrings[alternate.lang].languageName}</a>
      </nav>
    </div>
  </footer>`;
}

function pageLinksHtml(currentPage) {
  const home = homePageForLang(currentPage.lang);
  return orderedPages
    .filter((page) => page.lang === currentPage.lang && page.rel !== home.rel)
    .map((page) => `<a href="${escapeAttr(hrefBetween(currentPage, page))}"${currentAttr(currentPage, page)}>${escapeHtml(page.title)}</a>`)
    .join("\n        ");
}

function currentAttr(currentPage, page) {
  return page.rel === currentPage.rel ? ' aria-current="page"' : "";
}

function languageSwitchHtml(page) {
  const alternateHref = escapeAttr(hrefBetween(page, alternatePage(page)));
  return Object.keys(templateStrings)
    .map((lang) => {
      const code = lang.toUpperCase();
      if (lang === page.lang) return `<span lang="${lang}" aria-current="true">${code}</span>`;
      return `<a href="${alternateHref}" lang="${lang}" hreflang="${lang}" aria-label="${templateStrings[lang].viewInLanguage}">${code}</a>`;
    })
    .join('<span aria-hidden="true">/</span>');
}

function homeMainHtml(page, html, t) {
  const bodyWithoutTitle = html.replace(/^<h1[^>]*>[\s\S]*?<\/h1>\n?/, "");
  return `${heroHtml(page, t)}
    <article class="prose">
${bodyWithoutTitle}
    </article>`;
}

function docMainHtml(page, html, t) {
  return `${tocHtml(page, tocFromHtml(html), t)}
    <article class="prose">
${html}
    </article>`;
}

function heroHtml(page, t) {
  const { file, width, height, displayWidth, captionY, callouts } = menuCapture;
  const spec = [
    [t.specAccess, t.specAccessValue],
    [t.specRequires, t.specRequiresValue],
    [t.specStatus, t.specStatusValue],
    [t.specSource, `<a href="${repoBase}">GitHub</a>`],
  ];
  return `<section class="hero" aria-labelledby="product">
      <div class="hero-copy">
        <p class="eyebrow mono">${t.eyebrowFor} <b>${pdtName}</b></p>
        <div class="title">
          <h1 id="product">${productName}</h1>
          <p class="lede">${t.lede}</p>
          <div class="cta">
            <a class="btn" href="${escapeAttr(hrefBetween(page, installPageForLang(page.lang)))}">${t.install}</a>
            <a class="more" href="#${t.pulseAnchor}">${t.viewPulse}<span aria-hidden="true">&darr;</span></a>
          </div>
        </div>
        <dl class="spec">
          ${spec.map(([term, value]) => `<div><dt class="mono">${term}</dt><dd>${value}</dd></div>`).join("\n          ")}
        </dl>
      </div>
      <figure class="stage" style="--capture-w:${width};--capture-h:${height};--capture-max:${displayWidth}px;--caption-y:${captionY}">
        ${menuBarStripHtml()}
        <div class="hang">
          <span class="bar-item" aria-hidden="true">${statusIconSvg()}</span>
          <div class="menu"><img src="${escapeAttr(assetHref(page, file))}" width="${width}" height="${height}" alt="${t.captureAlt}" fetchpriority="high"></div>
        </div>
        <ul class="callouts mono">
          ${callouts.map((callout) => `<li class="${callout.tone}" style="--y:${callout.y}"><span>${t[callout.label]}</span></li>`).join("\n          ")}
        </ul>
        <figcaption class="fig"><b class="mono">${t.figureLabel}</b>${t.figureCaption}</figcaption>
      </figure>
    </section>`;
}

function tocHtml(page, toc, t) {
  if (!toc.length) return "";
  const list = `<ol>${toc.map((item) => `<li><a href="#${item.id}">${escapeHtml(item.title)}</a></li>`).join("")}</ol>`;
  const installPage = installPageForLang(page.lang);
  const installLink =
    installPage.rel === page.rel ? "" : `<a class="next" href="${escapeAttr(hrefBetween(page, installPage))}">${t.install}<span aria-hidden="true">&rarr;</span></a>`;
  return `<nav class="toc" aria-label="${t.onThisPage}">
      <div class="rail">
        <p class="rail-title mono">${t.onThisPage}</p>
        ${list}
        ${installLink}
      </div>
      <details class="contents">
        <summary class="mono">${t.onThisPage}</summary>
        ${list}
      </details>
    </nav>`;
}

function homePageForLang(lang) {
  const homeOutRel = lang === "nl" ? "index.html" : `${lang}/index.html`;
  return pages.find((page) => page.lang === lang && page.outRel === homeOutRel) || pages.find((page) => page.lang === lang) || pages[0];
}

function installPageForLang(lang) {
  const installOutRel = lang === "nl" ? "install/index.html" : `${lang}/install/index.html`;
  return pages.find((page) => page.lang === lang && page.outRel === installOutRel) || homePageForLang(lang);
}

function alternatePage(page) {
  const nextLang = page.lang === "nl" ? "en" : "nl";
  const alternateRel = page.rel.replace(new RegExp(`\\.${page.lang}\\.md$`), `.${nextLang}.md`);
  return pageMap.get(alternateRel) || pages.find((candidate) => candidate.lang === nextLang && candidate.title === page.title) || homePageForLang(nextLang);
}

function assetHref(page, rel) {
  return hrefFromOutRel(page.outRel, rel, { targetIsDirectory: false });
}

function hrefBetween(fromPage, toPage) {
  return hrefFromOutRel(fromPage.outRel, outputUrlPath(toPage.outRel), {
    targetIsDirectory: isDirectoryIndexOutRel(toPage.outRel),
  });
}

function hrefFromOutRel(fromOutRel, targetUrlPath, { targetIsDirectory }) {
  const fromDir = outputUrlDirectory(fromOutRel);
  const relative = path.posix.relative(fromDir, targetUrlPath);
  if (!relative) return "./";
  return targetIsDirectory && !relative.endsWith("/") ? `${relative}/` : relative;
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

function outputUrlPath(outRel) {
  if (outRel === "index.html") return "";
  if (isDirectoryIndexOutRel(outRel)) return outRel.slice(0, -"index.html".length);
  return outRel;
}

function outputUrlDirectory(outRel) {
  const urlPath = outputUrlPath(outRel);
  if (!urlPath) return "";
  if (urlPath.endsWith("/")) return urlPath.slice(0, -1);
  const dir = path.posix.dirname(urlPath);
  return dir === "." ? "" : dir;
}

function isDirectoryIndexOutRel(outRel) {
  return outRel === "index.html" || outRel.endsWith("/index.html");
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
