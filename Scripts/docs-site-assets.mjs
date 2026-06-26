export function css() {
  return `
:root,:root[data-theme="light"]{
  color-scheme:light;
  --bg:#f7f8f4;
  --paper:#ffffff;
  --paper-2:#eef5ee;
  --ink:#17211c;
  --text:#36453d;
  --muted:#65756b;
  --subtle:#8a988f;
  --line:#dce5dc;
  --line-soft:#eef3ee;
  --accent:#0f766e;
  --accent-strong:#115e59;
  --gold:#b7791f;
  --soft:rgba(15,118,110,.11);
  --code:#111c19;
  --code-border:#29423d;
  --shadow:0 16px 42px rgba(23,33,28,.10);
}
:root[data-theme="dark"]{
  color-scheme:dark;
  --bg:#0b1110;
  --paper:#121b19;
  --paper-2:#17231f;
  --ink:#f4f8f5;
  --text:#cfdbd4;
  --muted:#9aaca2;
  --subtle:#718278;
  --line:#263832;
  --line-soft:#1a2824;
  --accent:#5eead4;
  --accent-strong:#99f6e4;
  --gold:#f2c66d;
  --soft:rgba(94,234,212,.13);
  --code:#07100e;
  --code-border:#29423d;
  --shadow:0 18px 50px rgba(0,0,0,.35);
}
*{box-sizing:border-box}
html{scroll-behavior:smooth;scroll-padding-top:26px}
@media(prefers-reduced-motion:reduce){html{scroll-behavior:auto}*,*::before,*::after{animation:none!important;transition:none!important}}
body{margin:0;background:linear-gradient(135deg,var(--paper-2),transparent 34rem),var(--bg);color:var(--text);font-family:Inter,ui-sans-serif,system-ui,-apple-system,Segoe UI,sans-serif;line-height:1.65;-webkit-font-smoothing:antialiased}
a{color:var(--accent);text-decoration:none}
a:hover{text-decoration:underline;text-underline-offset:.22em}
.shell{display:grid;grid-template-columns:268px minmax(0,1fr);min-height:100vh}
.sidebar{position:sticky;top:0;height:100vh;overflow:auto;padding:28px 22px;background:color-mix(in srgb,var(--paper) 94%,transparent);border-right:1px solid var(--line);scrollbar-width:thin;scrollbar-color:var(--line) transparent}
.sidebar-head{display:flex;align-items:center;gap:10px;margin-bottom:22px}
.brand{display:flex;gap:11px;align-items:center;min-width:0;flex:1;color:var(--ink)}
.brand:hover{text-decoration:none}
.mark{width:34px;height:34px;flex:0 0 34px;border-radius:8px;display:grid;place-items:center;background:linear-gradient(135deg,var(--soft),var(--paper-2));color:var(--accent);border:1px solid color-mix(in srgb,var(--accent) 24%,var(--line));box-shadow:var(--shadow)}
.mark svg{width:22px;height:22px}.brand strong{display:block;color:var(--ink);font-size:1.06rem;line-height:1.05}.brand small{display:block;color:var(--muted);font-size:.68rem;text-transform:uppercase;letter-spacing:.08em;margin-top:3px}
.theme-toggle{width:34px;height:34px;display:inline-grid;place-items:center;border:1px solid var(--line);border-radius:8px;background:transparent;color:var(--muted);cursor:pointer}
.theme-toggle:hover{border-color:var(--accent);color:var(--accent);background:var(--soft)}
.theme-toggle svg{width:16px;height:16px}.theme-toggle .sun{display:none}:root[data-theme="dark"] .theme-toggle .sun{display:block}:root[data-theme="dark"] .theme-toggle .moon{display:none}
.theme-float{display:none}
.lang-switch{display:flex;gap:6px;margin:0 0 18px}.lang-switch a{border:1px solid var(--line);border-radius:8px;padding:4px 9px;color:var(--muted);font-size:.78rem;font-weight:750}.lang-switch a.active,.lang-switch a:hover{background:var(--soft);border-color:var(--accent);color:var(--accent);text-decoration:none}
.search{display:block;margin:0 0 22px}.search span{display:block;margin-bottom:7px;color:var(--muted);font-size:.67rem;font-weight:800;text-transform:uppercase;letter-spacing:.09em}.search input{width:100%;height:38px;border:1px solid var(--line);border-radius:8px;background:var(--paper);color:var(--text);font:inherit;font-size:.88rem;padding:0 11px;outline:none}.search input:focus{border-color:var(--accent);box-shadow:0 0 0 3px var(--soft)}.search input::placeholder{color:var(--subtle)}
nav section{margin:0 0 19px}nav h2{margin:0 0 7px;color:var(--subtle);font-size:.67rem;text-transform:uppercase;letter-spacing:.11em}
.nav-link{display:block;border-radius:7px;padding:5px 10px;color:var(--text);font-size:.9rem;line-height:1.42}.nav-link:hover{background:var(--line-soft);color:var(--ink);text-decoration:none}.nav-link.active{background:var(--soft);color:var(--accent);font-weight:750}
.no-results{display:none;color:var(--muted);font-size:.86rem;margin-top:-4px}
main{max-width:1180px;width:100%;padding:46px clamp(20px,5vw,72px) 84px;margin:0 auto}
.home-hero{display:grid;grid-template-columns:minmax(0,.9fr) minmax(320px,1fr);gap:34px;align-items:center;border-bottom:1px solid var(--line);padding:18px 0 34px;margin-bottom:30px}.home-hero h1{font-size:clamp(2.45rem,5vw,4.2rem);line-height:1.02;margin:0 0 18px;max-width:10ch}.lede{font-size:1.17rem;max-width:66ch}.eyebrow{margin:0 0 10px;color:var(--accent);font-size:.72rem;text-transform:uppercase;letter-spacing:.11em;font-weight:800}
.actions{display:flex;gap:10px;flex-wrap:wrap;margin-top:22px}.btn{display:inline-flex;align-items:center;gap:7px;border:1px solid var(--line);border-radius:8px;padding:10px 15px;font-weight:750;color:var(--ink);background:var(--paper)}.btn.primary{background:var(--ink);border-color:var(--ink);color:var(--bg)}.btn:hover{border-color:var(--accent);color:var(--accent);background:var(--soft);text-decoration:none}.btn.primary:hover{background:var(--accent-strong);border-color:var(--accent-strong);color:#08110f}
.hero-art{position:relative;display:flex;align-items:center;justify-content:center;min-height:330px;isolation:isolate}.hero-art svg{display:block;width:100%;max-width:540px;height:auto;filter:drop-shadow(0 24px 48px rgba(0,0,0,.28))}:root[data-theme="light"] .hero-art svg{filter:drop-shadow(0 18px 34px rgba(23,33,28,.14))}
.pulse-glow{animation:pulse-glow 2.6s ease-in-out infinite}.pulse-bar{transform-origin:bottom;transform-box:fill-box;animation:pulse-rise 3.8s ease-in-out infinite}.pulse-bar:nth-of-type(2){animation-delay:.25s}.pulse-bar:nth-of-type(3){animation-delay:.5s}@keyframes pulse-glow{0%,100%{opacity:.55}50%{opacity:1}}@keyframes pulse-rise{0%,100%{transform:scaleY(.82)}50%{transform:scaleY(1)}}
.feature-row{grid-column:1/-1;display:flex;gap:8px;flex-wrap:wrap;margin-top:0}.feature-pill{display:inline-flex;align-items:center;gap:7px;border:1px solid var(--line);border-radius:999px;padding:6px 11px;background:var(--paper);color:var(--text);font-size:.82rem;font-weight:650}.feature-pill:hover{border-color:var(--accent);color:var(--accent);background:var(--soft);text-decoration:none}
.doc-grid{display:grid;grid-template-columns:minmax(0,72ch) 212px;gap:46px}.doc{min-width:0;overflow-wrap:break-word}.doc h1:first-child{display:none}.doc :is(h2,h3,h4){position:relative}.doc :is(h2,h3,h4) .anchor{position:absolute;left:-1.05em;color:var(--subtle);opacity:0}.doc :is(h2,h3,h4):hover .anchor{opacity:.75}
h1,h2,h3,h4{color:var(--ink);line-height:1.18;letter-spacing:0}h1{font-size:2.42rem;margin:.1em 0 .34em}h2{font-size:1.52rem;margin:2em 0 .55em}h3{font-size:1.12rem;margin:1.55em 0 .35em}
.doc p{margin:0 0 1.08em}.doc ul,.doc ol{padding-left:1.35rem;margin:0 0 1.18em}.doc li{margin:.28em 0}.doc strong{color:var(--ink)}
.doc code{font-family:"JetBrains Mono",ui-monospace,SFMono-Regular,Menlo,monospace;background:var(--line-soft);border:1px solid var(--line);border-radius:5px;padding:.08em .35em;color:var(--accent)}.doc pre{position:relative;overflow:auto;background:var(--code);color:#e2e8f0;border-radius:8px;padding:14px 17px;margin:1.35em 0;border:1px solid var(--code-border)}.doc pre code{display:block;background:transparent;border:0;color:inherit;padding:0;font-size:.88rem;white-space:pre}.copy{position:absolute;top:8px;right:8px;border:1px solid rgba(255,255,255,.18);border-radius:6px;background:rgba(255,255,255,.07);color:#e2e8f0;font:700 .7rem/1 Inter,sans-serif;padding:4px 9px;cursor:pointer;opacity:0}.doc pre:hover .copy,.copy:focus{opacity:1}.copy.copied{background:var(--accent);border-color:var(--accent);opacity:1}
.toc{position:sticky;top:28px;align-self:start;border-left:1px solid var(--line);padding-left:14px;font-size:.85rem;max-height:calc(100vh - 56px);overflow:auto}.toc h2{font-size:.67rem;text-transform:uppercase;letter-spacing:.1em;color:var(--subtle);margin:0 0 8px}.toc a{display:block;color:var(--muted);padding:3px 0}.toc a:hover{color:var(--accent);text-decoration:none}.toc-l3{padding-left:14px!important}
.nav-toggle{display:none;position:fixed;top:14px;right:14px;z-index:20;width:40px;height:40px;border:1px solid var(--line);border-radius:8px;background:var(--paper);color:var(--ink);box-shadow:var(--shadow);padding:9px;cursor:pointer}.nav-toggle span{display:block;height:2px;background:currentColor;border-radius:2px;margin:5px 0}
@media(prefers-reduced-motion:reduce){.pulse-glow,.pulse-bar{animation:none}}
@media(max-width:960px){.shell{display:block}.sidebar{position:fixed;inset:0 28% 0 0;max-width:330px;z-index:15;transform:translateX(-102%);transition:transform .2s ease;box-shadow:var(--shadow);pointer-events:none}.sidebar.open{transform:translateX(0);pointer-events:auto}.nav-toggle{display:block}.theme-float{display:inline-grid;position:fixed;top:14px;right:62px;z-index:20;width:40px;height:40px;background:var(--paper);color:var(--ink);box-shadow:var(--shadow)}main{padding:62px 18px 56px}.home-hero{display:block}.hero-art{margin-top:24px;min-height:260px}.hero-art svg{max-width:380px}.doc-grid{display:block}.toc{display:none}h1{font-size:2rem}.home-hero h1{font-size:2.7rem}.doc :is(h2,h3,h4) .anchor{display:none}}
`;
}

export function js() {
  return `
const root=document.documentElement;
function readTheme(){try{return localStorage.getItem("theme")}catch{return null}}
function writeTheme(value){try{localStorage.setItem("theme",value)}catch{}}
function setTheme(value){root.dataset.theme=value;document.querySelectorAll("[data-theme-toggle]").forEach((button)=>button.setAttribute("aria-pressed",value==="dark"?"true":"false"))}
setTheme(root.dataset.theme==="dark"?"dark":"light");
document.querySelectorAll("[data-theme-toggle]").forEach((button)=>button.addEventListener("click",()=>{const next=root.dataset.theme==="dark"?"light":"dark";setTheme(next);writeTheme(next)}));
const sidebar=document.querySelector(".sidebar");
const toggle=document.querySelector(".nav-toggle");
const mobileNav=window.matchMedia("(max-width:960px)");
function syncNavA11y(open=sidebar?.classList.contains("open")){if(!sidebar)return;const hidden=mobileNav.matches&&!open;sidebar.toggleAttribute("inert",hidden);sidebar.setAttribute("aria-hidden",hidden?"true":"false")}
function setNav(open){if(!sidebar||!toggle)return;sidebar.classList.toggle("open",open);toggle.setAttribute("aria-expanded",open?"true":"false");syncNavA11y(open)}
toggle?.addEventListener("click",()=>setNav(!sidebar?.classList.contains("open")));
document.addEventListener("keydown",(event)=>{if(event.key==="Escape")setNav(false)});
document.addEventListener("click",(event)=>{if(!sidebar?.classList.contains("open"))return;if(sidebar.contains(event.target)||toggle?.contains(event.target))return;setNav(false)});
document.querySelectorAll(".nav-link").forEach((link)=>link.addEventListener("click",()=>setNav(false)));
mobileNav.addEventListener("change",()=>syncNavA11y());
syncNavA11y(false);
const search=document.getElementById("doc-search");
const empty=document.querySelector(".no-results");
search?.addEventListener("input",()=>{const query=search.value.trim().toLowerCase();let anySection=false;document.querySelectorAll(".sidebar nav section").forEach((section)=>{let anyLink=false;section.querySelectorAll(".nav-link").forEach((link)=>{const match=!query||link.textContent.toLowerCase().includes(query);link.style.display=match?"block":"none";if(match)anyLink=true});section.style.display=anyLink?"block":"none";if(anyLink)anySection=true});if(empty)empty.style.display=anySection?"none":"block"});
document.querySelectorAll(".doc pre").forEach((pre)=>{const button=document.createElement("button");button.type="button";button.className="copy";button.textContent="Copy";button.addEventListener("click",async()=>{try{await navigator.clipboard.writeText(pre.querySelector("code")?.textContent??"");button.textContent="Copied";button.classList.add("copied");setTimeout(()=>{button.textContent="Copy";button.classList.remove("copied")},1300)}catch{button.textContent="Failed";setTimeout(()=>{button.textContent="Copy"},1300)}});pre.appendChild(button)});
`;
}

export function preThemeScript() {
  return `(function(){var t;try{t=localStorage.getItem("theme")}catch(e){}document.documentElement.dataset.theme=t==="dark"?"dark":"light"})();`;
}

export function themeToggleHtml(extraClass = "") {
  const className = extraClass ? `theme-toggle ${extraClass}` : "theme-toggle";
  return `<button class="${className}" type="button" aria-label="Toggle dark mode" aria-pressed="false" data-theme-toggle>
    <svg class="moon" viewBox="0 0 20 20" aria-hidden="true"><path d="M14.6 12.1A6.5 6.5 0 0 1 7.4 2.7a6.5 6.5 0 1 0 7.2 9.4z" fill="currentColor"/></svg>
    <svg class="sun" viewBox="0 0 20 20" aria-hidden="true"><circle cx="10" cy="10" r="3.4" fill="currentColor"/><g stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><path d="M10 2v2M10 16v2M2 10h2M16 10h2M4.3 4.3l1.4 1.4M14.3 14.3l1.4 1.4M4.3 15.7l1.4-1.4M14.3 5.7l1.4-1.4"/></g></svg>
  </button>`;
}

export function brandMarkSvg() {
  return `<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><rect x="4" y="5" width="16" height="14" rx="4" stroke="currentColor" stroke-width="1.7"/><path d="M8 15V9M12 15V7M16 15v-4" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>`;
}

export function pulseArtSvg() {
  return `<svg class="pulse-art" viewBox="0 0 360 220" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="PDTBar quiet portfolio pulse" focusable="false">
<defs>
<linearGradient id="pulse-card" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stop-color="#17231f"/><stop offset="100%" stop-color="#07100e"/></linearGradient>
<linearGradient id="pulse-accent" x1="80" y1="40" x2="280" y2="170"><stop offset="0%" stop-color="#99f6e4"/><stop offset="100%" stop-color="#f2c66d"/></linearGradient>
<filter id="pulse-shadow" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="3" result="glow"/><feMerge><feMergeNode in="glow"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
</defs>
<rect width="360" height="220" rx="18" fill="url(#pulse-card)" stroke="#263832"/>
<g transform="translate(22 24)"><circle cx="0" cy="0" r="4.5" fill="#ef5350" opacity=".86"/><circle cx="14" cy="0" r="4.5" fill="#f2c66d" opacity=".86"/><circle cx="28" cy="0" r="4.5" fill="#5eead4" opacity=".86"/></g>
<text x="336" y="30" fill="#718278" font-family="JetBrains Mono, Menlo, monospace" font-size="9" letter-spacing="1.4" text-anchor="end">LOCAL PDT PULSE</text>
<g transform="translate(78 58)" filter="url(#pulse-shadow)">
  <rect x="0" y="72" width="52" height="72" rx="14" fill="#11231f" stroke="#29423d"/>
  <rect x="74" y="38" width="52" height="106" rx="14" fill="#11231f" stroke="#29423d"/>
  <rect x="148" y="92" width="52" height="52" rx="14" fill="#11231f" stroke="#29423d"/>
  <rect class="pulse-bar" x="15" y="92" width="22" height="42" rx="8" fill="#5eead4"/>
  <rect class="pulse-bar" x="89" y="58" width="22" height="76" rx="8" fill="#f2c66d"/>
  <rect class="pulse-bar" x="163" y="107" width="22" height="27" rx="8" fill="#99f6e4"/>
</g>
<circle class="pulse-glow" cx="276" cy="68" r="8" fill="url(#pulse-accent)"/>
<path d="M98 181h164" stroke="#29423d" stroke-width="1"/>
<text x="180" y="198" fill="#9aaca2" font-family="JetBrains Mono, Menlo, monospace" font-size="10" letter-spacing="1" text-anchor="middle">concentration | income | freshness</text>
</svg>`;
}

export function faviconSvg() {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" role="img" aria-label="PDTBar"><rect width="64" height="64" rx="14" fill="#17231f"/><rect x="14" y="28" width="8" height="20" rx="4" fill="#5eead4"/><rect x="28" y="16" width="8" height="32" rx="4" fill="#f2c66d"/><rect x="42" y="34" width="8" height="14" rx="4" fill="#99f6e4"/></svg>`;
}

export function socialCardSvg() {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 630" role="img" aria-label="PDTBar social card"><rect width="1200" height="630" fill="#f7f8f4"/><rect x="70" y="70" width="1060" height="490" rx="26" fill="#ffffff" stroke="#dce5dc"/><g transform="translate(110 122) scale(4)" color="#0f766e">${brandMarkSvg()}</g><text x="110" y="306" font-family="Inter, Arial, sans-serif" font-size="92" font-weight="800" fill="#17211c">PDTBar</text><text x="114" y="382" font-family="Inter, Arial, sans-serif" font-size="38" fill="#36453d">A quiet portfolio pulse in the macOS menu bar.</text><text x="114" y="462" font-family="JetBrains Mono, Menlo, monospace" font-size="30" fill="#0f766e">quiet portfolio pulse | local | read-only | PDT + Claude</text></svg>`;
}
