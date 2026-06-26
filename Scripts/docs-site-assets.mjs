export function css() {
  return `
:root[data-theme="dark"]{
  color-scheme:dark;
  --bg:#10130f;
  --paper:#171c16;
  --paper-2:#20271f;
  --ink:#f7faf5;
  --text:#d9e2d4;
  --muted:#a4b29d;
  --subtle:#7f8d78;
  --line:#30392f;
  --line-soft:#222a21;
  --accent:#9fd356;
  --blue:#7fb7ff;
  --warn:#f0b35a;
  --soft:rgba(159,211,86,.15);
  --code:#0b0f0a;
  --code-border:#333d31;
  --shadow:0 20px 46px rgba(0,0,0,.36);
}
:root,:root[data-theme="light"]{
  color-scheme:light;
  --bg:#f6f5ef;
  --paper:#ffffff;
  --paper-2:#edf1e9;
  --ink:#182018;
  --text:#344135;
  --muted:#687766;
  --subtle:#8d9b88;
  --line:#d9dfd2;
  --line-soft:#eef2ea;
  --accent:#4d7d13;
  --blue:#276a9f;
  --warn:#a26000;
  --soft:rgba(77,125,19,.12);
  --code:#141a13;
  --code-border:#2d372b;
  --shadow:0 18px 38px rgba(36,45,30,.12);
}
*{box-sizing:border-box}
html{scroll-behavior:smooth;scroll-padding-top:24px}
@media(prefers-reduced-motion:reduce){html{scroll-behavior:auto}*,*::before,*::after{animation:none!important;transition:none!important}}
body{margin:0;background:var(--bg);color:var(--text);font-family:Inter,ui-sans-serif,system-ui,-apple-system,Segoe UI,sans-serif;line-height:1.65;-webkit-font-smoothing:antialiased}
a{color:var(--accent);text-decoration:none}
a:hover{text-decoration:underline;text-underline-offset:.22em}
.shell{display:grid;grid-template-columns:270px minmax(0,1fr);min-height:100vh}
.sidebar{position:sticky;top:0;height:100vh;overflow:auto;padding:26px 22px;background:color-mix(in srgb,var(--paper) 96%,var(--paper-2));border-right:1px solid var(--line);scrollbar-width:thin;scrollbar-color:var(--line) transparent}
.sidebar-head{display:flex;align-items:center;gap:10px;margin-bottom:22px}
.brand{display:flex;gap:11px;align-items:center;min-width:0;flex:1;color:var(--ink);text-decoration:none}
.brand:hover{text-decoration:none}
.mark{width:28px;height:28px;flex:0 0 28px;border-radius:7px;display:grid;place-items:center;background:var(--paper);color:var(--accent);border:1px solid var(--line)}
:root[data-theme="dark"] .mark{background:linear-gradient(135deg,#1a2118,#0c110b)}
.mark svg{width:18px;height:18px;display:block}.brand strong{display:block;font-size:1.08rem;line-height:1.05;color:var(--ink)}.brand small{display:block;color:var(--muted);font-size:.68rem;text-transform:uppercase;letter-spacing:.08em;margin-top:3px}
.sidebar-actions{display:flex;gap:8px}.icon-button,.lang-button{height:34px;display:inline-grid;place-items:center;border:1px solid var(--line);border-radius:8px;background:transparent;color:var(--muted);cursor:pointer;font-weight:800}
.icon-button{width:34px}.lang-button{padding:0 10px;font-size:.78rem}.icon-button:hover,.lang-button:hover{border-color:var(--accent);color:var(--accent);background:var(--soft);text-decoration:none}
.icon-button svg{width:16px;height:16px}.icon-button .sun{display:none}:root[data-theme="dark"] .icon-button .sun{display:block}:root[data-theme="dark"] .icon-button .moon{display:none}
.search{display:block;margin:0 0 22px}.search span{display:block;margin-bottom:7px;color:var(--muted);font-size:.67rem;font-weight:750;text-transform:uppercase;letter-spacing:.09em}.search input{width:100%;height:38px;border:1px solid var(--line);border-radius:8px;background:var(--paper);color:var(--text);font:inherit;font-size:.88rem;padding:0 11px;outline:none}.search input:focus{border-color:var(--accent);box-shadow:0 0 0 3px var(--soft)}.search input::placeholder{color:var(--subtle)}
nav section{margin:0 0 19px}nav h2{margin:0 0 7px;color:var(--subtle);font-size:.67rem;text-transform:uppercase;letter-spacing:.11em}
.nav-link{display:block;border-radius:7px;padding:5px 10px;color:var(--text);font-size:.9rem;line-height:1.42}.nav-link:hover{background:var(--line-soft);color:var(--ink);text-decoration:none}.nav-link.active{background:var(--soft);color:var(--accent);font-weight:750}
.no-results{display:none;color:var(--muted);font-size:.86rem;margin-top:-4px}
main{max-width:1160px;width:100%;padding:42px clamp(20px,5vw,68px) 80px;margin:0 auto}
.doc-grid{display:grid;grid-template-columns:minmax(0,72ch) 220px;gap:48px}.doc{min-width:0;overflow-wrap:break-word}.doc h1:first-child{font-size:clamp(2.7rem,6vw,5rem);line-height:1;margin:.08em 0 .26em;max-width:11ch}.doc :is(h2,h3,h4){position:relative}.doc :is(h2,h3,h4) .anchor{position:absolute;left:-1.05em;color:var(--subtle);opacity:0;text-decoration:none}.doc :is(h2,h3,h4):hover .anchor{opacity:.75}
.lede{font-size:1.18rem;max-width:66ch;color:var(--ink)}
h1,h2,h3,h4{color:var(--ink);line-height:1.18;letter-spacing:0}h2{font-size:1.48rem;margin:2em 0 .55em}h3{font-size:1.12rem;margin:1.55em 0 .35em}h4{font-size:1rem;margin:1.35em 0 .25em}
.doc p{margin:0 0 1.08em}.doc ul,.doc ol{padding-left:1.35rem;margin:0 0 1.18em}.doc li{margin:.28em 0}.doc strong{color:var(--ink)}
.doc img{display:block;width:100%;height:auto;border:1px solid color-mix(in srgb,var(--ink) 18%,var(--line));border-radius:8px;box-shadow:var(--shadow);background:var(--paper);margin:24px 0 30px}
.doc code{font-family:"JetBrains Mono",ui-monospace,SFMono-Regular,Menlo,monospace;background:var(--line-soft);border:1px solid var(--line);border-radius:5px;padding:.08em .35em;color:var(--blue)}.doc pre{position:relative;overflow:auto;background:var(--code);color:#e8f0e5;border-radius:8px;padding:14px 17px;margin:1.35em 0;border:1px solid var(--code-border)}.doc pre code{display:block;background:transparent;border:0;color:inherit;padding:0;font-size:.88rem;white-space:pre}.copy{position:absolute;top:8px;right:8px;border:1px solid rgba(255,255,255,.18);border-radius:6px;background:rgba(255,255,255,.07);color:#e8f0e5;font:700 .7rem/1 Inter,sans-serif;padding:4px 9px;cursor:pointer;opacity:0}.doc pre:hover .copy,.copy:focus{opacity:1}.copy.copied{background:var(--accent);border-color:var(--accent);color:#fff;opacity:1}
.doc table{border-collapse:collapse;width:100%;font-size:.93rem;margin:1.25em 0}.doc th,.doc td{border-bottom:1px solid var(--line);padding:8px;text-align:left;vertical-align:top}.doc th{background:var(--line-soft);color:var(--ink)}
.toc{position:sticky;top:28px;align-self:start;border-left:1px solid var(--line);padding-left:14px;font-size:.85rem;max-height:calc(100vh - 56px);overflow:auto}.toc h2{font-size:.67rem;text-transform:uppercase;letter-spacing:.1em;color:var(--subtle);margin:0 0 8px}.toc a{display:block;color:var(--muted);padding:3px 0}.toc a:hover{color:var(--accent);text-decoration:none}.toc-l3{padding-left:14px!important}
.nav-toggle{display:none;position:fixed;top:14px;right:14px;z-index:20;width:40px;height:40px;border:1px solid var(--line);border-radius:8px;background:var(--paper);color:var(--ink);box-shadow:var(--shadow);padding:9px;cursor:pointer}.nav-toggle span{display:block;height:2px;background:currentColor;border-radius:2px;margin:5px 0}
@media(max-width:960px){.shell{display:block}.sidebar{position:fixed;inset:0 28% 0 0;max-width:330px;z-index:15;transform:translateX(-102%);transition:transform .2s ease;box-shadow:var(--shadow);pointer-events:none}.sidebar.open{transform:translateX(0);pointer-events:auto}.nav-toggle{display:block}main{padding:62px 18px 56px}.doc-grid{display:block}.toc{display:none}.doc h1:first-child{font-size:3rem}.doc :is(h2,h3,h4) .anchor{display:none}.doc pre code{white-space:pre-wrap;word-break:break-word}}
`;
}

export function js() {
  return `
const root=document.documentElement;
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

export function themeToggleHtml() {
  return `<button class="icon-button" type="button" aria-label="Toggle theme" aria-pressed="true" data-theme-toggle>
    <svg class="moon" viewBox="0 0 20 20" aria-hidden="true"><path d="M14.6 12.1A6.5 6.5 0 0 1 7.4 2.7a6.5 6.5 0 1 0 7.2 9.4z" fill="currentColor"/></svg>
    <svg class="sun" viewBox="0 0 20 20" aria-hidden="true"><circle cx="10" cy="10" r="3.4" fill="currentColor"/><g stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><path d="M10 2v2M10 16v2M2 10h2M16 10h2M4.3 4.3l1.4 1.4M14.3 14.3l1.4 1.4M4.3 15.7l1.4-1.4M14.3 5.7l1.4-1.4"/></g></svg>
  </button>`;
}

export function brandMarkSvg() {
  return `<svg class="pdtbar-mark" viewBox="0 0 24 24" aria-hidden="true">
  <style>
    .pdtbar-mark .bar{transform-box:fill-box;transform-origin:50% 100%;animation:pdtbar-bar-color 9s ease-in-out infinite}
    .pdtbar-mark .side-left{animation:pdtbar-left-height 9s ease-in-out infinite,pdtbar-bar-color 9s ease-in-out infinite}
    .pdtbar-mark .side-right{animation:pdtbar-right-height 9s ease-in-out infinite,pdtbar-bar-color 9s ease-in-out infinite;animation-delay:0s,3s}
    .pdtbar-mark .center{animation-delay:1.5s}
    @keyframes pdtbar-left-height{0%,100%{transform:scaleY(.58)}33%{transform:scaleY(1)}66%{transform:scaleY(.74)}}
    @keyframes pdtbar-right-height{0%,100%{transform:scaleY(.86)}33%{transform:scaleY(.6)}66%{transform:scaleY(1)}}
    @keyframes pdtbar-bar-color{0%,28%{fill:#9fd356}36%,61%{fill:#7fb7ff}69%,94%{fill:#f0b35a}100%{fill:#9fd356}}
  </style>
  <rect class="bar side-left" x="4" y="7" width="3.8" height="13" rx="1.9" fill="#9fd356"/>
  <rect class="bar center" x="10.1" y="3.5" width="3.8" height="16.5" rx="1.9" fill="#7fb7ff"/>
  <rect class="bar side-right" x="16.2" y="7" width="3.8" height="13" rx="1.9" fill="#f0b35a"/>
</svg>`;
}

export function faviconSvg() {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" role="img" aria-label="PDTBar"><rect width="64" height="64" rx="14" fill="#182018"/><path d="M18 48V27M32 48V15M46 48V34" stroke="#9fd356" stroke-width="6" stroke-linecap="round"/><rect x="13" y="25" width="10" height="23" rx="5" fill="none" stroke="#f7faf5" stroke-width="4"/><rect x="27" y="13" width="10" height="35" rx="5" fill="none" stroke="#f7faf5" stroke-width="4"/><rect x="41" y="32" width="10" height="16" rx="5" fill="none" stroke="#f7faf5" stroke-width="4"/></svg>`;
}

export function socialCardSvg() {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630" viewBox="0 0 1200 630" role="img" aria-label="PDTBar social card"><rect width="1200" height="630" fill="#f6f5ef"/><rect x="86" y="82" width="1028" height="466" rx="34" fill="#ffffff" stroke="#d9dfd2" stroke-width="3"/><g transform="translate(120 128)"><rect width="142" height="142" rx="30" fill="#182018"/><path d="M43 106V61M71 106V35M99 106V76" stroke="#9fd356" stroke-width="11" stroke-linecap="round"/><rect x="33" y="57" width="20" height="49" rx="10" fill="none" stroke="#f7faf5" stroke-width="7"/><rect x="61" y="31" width="20" height="75" rx="10" fill="none" stroke="#f7faf5" stroke-width="7"/><rect x="89" y="72" width="20" height="34" rx="10" fill="none" stroke="#f7faf5" stroke-width="7"/></g><text x="300" y="196" fill="#182018" font-family="Inter, system-ui, sans-serif" font-size="86" font-weight="800">PDTBar</text><text x="300" y="264" fill="#344135" font-family="Inter, system-ui, sans-serif" font-size="34">Quiet portfolio pressure in the macOS menu bar.</text><text x="122" y="422" fill="#344135" font-family="Inter, system-ui, sans-serif" font-size="30">Concentration · Income events · Big movers · All quiet</text><text x="122" y="474" fill="#687766" font-family="Inter, system-ui, sans-serif" font-size="25">Local, read-only, Claude CLI + PDT MCP.</text></svg>`;
}
