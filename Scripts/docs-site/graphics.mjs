const appIconShapes = `<rect x="0.125" y="0.125" width="27.75" height="27.75" rx="6" fill="#142522" stroke="#36514a" stroke-width="0.25"/><rect x="6" y="12" width="4" height="9" rx="2" fill="#5eead4"/><rect x="12" y="10" width="4" height="11" rx="2" fill="#f2c66d"/><circle cx="14" cy="6.5" r="2" fill="#f2c66d"/><rect x="18" y="15" width="4" height="6" rx="2" fill="#99f6e4"/>`;

export function brandMarkSvg() {
  return `<svg class="brand-mark" viewBox="0 0 28 28" aria-hidden="true">${appIconShapes}</svg>`;
}

export function faviconSvg() {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 28 28" role="img" aria-label="PDTBar">${appIconShapes}</svg>`;
}

export function socialCardSvg() {
  const sans = `font-family="-apple-system, 'Helvetica Neue', Arial, sans-serif"`;
  const mono = `font-family="ui-monospace, Menlo, Consolas, monospace"`;
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 630" role="img" aria-label="PDTBar social card"><rect width="1200" height="630" fill="#f5f1e8"/><path d="M90 150H1110M90 520H1110" stroke="#16211e" stroke-opacity=".15" stroke-width="2"/><g transform="translate(90 62) scale(2)">${appIconShapes}</g><text x="166" y="102" ${mono} font-size="22" letter-spacing="2" fill="#56605b">FOR <tspan fill="#0b6a61">PORTFOLIO DIVIDEND TRACKER</tspan></text><text x="82" y="350" ${sans} font-size="168" font-weight="700" letter-spacing="-7" fill="#16211e">PDTBar</text><text x="90" y="440" ${sans} font-size="44" fill="#16211e">A quiet portfolio pulse in the macOS menu bar.</text><text x="90" y="574" ${mono} font-size="24" letter-spacing="2" fill="#56605b">LOCAL  /  READ-ONLY BY DEFAULT  /  MACOS 14 OR NEWER</text></svg>`;
}

export function themeToggleHtml(label) {
  return `<button class="theme" type="button" aria-label="${label}" aria-pressed="false" data-theme-toggle>
        <svg class="moon" viewBox="0 0 20 20" aria-hidden="true"><path d="M14.6 12.1A6.5 6.5 0 0 1 7.4 2.7a6.5 6.5 0 1 0 7.2 9.4z" fill="currentColor"/></svg>
        <svg class="sun" viewBox="0 0 20 20" aria-hidden="true"><circle cx="10" cy="10" r="3.4" fill="currentColor"/><g stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><path d="M10 2v2M10 16v2M2 10h2M16 10h2M4.3 4.3l1.4 1.4M14.3 14.3l1.4 1.4M4.3 15.7l1.4-1.4M14.3 5.7l1.4-1.4"/></g></svg>
      </button>`;
}

// Same geometry as makeConcentrationStackStatusImage in Sources/PDTBarApp/main.swift,
// at the default bar heights with no unread items.
export function statusIconSvg() {
  return `<svg viewBox="0 0 24 19" width="24" height="19"><g fill="none" stroke="currentColor" stroke-width="1.2" stroke-opacity=".86"><rect x="2.5" y="9.7" width="5" height="8.1" rx="2.5"/><rect x="9.5" y="1.6" width="5" height="16.2" rx="2.5"/><rect x="16.5" y="7" width="5" height="10.8" rx="2.5"/></g></svg>`;
}

// The strip depicts the English macOS session the capture was taken in, so it is not translated.
export function menuBarStripHtml() {
  return `<div class="bar" aria-hidden="true">
          <div class="bar-left"><span>View</span><span>Window</span><span>Help</span></div>
          <div class="bar-right">
            <svg viewBox="0 0 18 14" width="17" height="13"><path d="M1.5 5.2a10.6 10.6 0 0 1 15 0M4.1 7.9a6.9 6.9 0 0 1 9.8 0M6.7 10.5a3.2 3.2 0 0 1 4.6 0" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>
            <svg viewBox="0 0 27 13" width="25" height="12"><rect x=".6" y=".6" width="22.8" height="11.8" rx="3.4" fill="none" stroke="currentColor" opacity=".5" stroke-width="1.1"/><rect x="2.2" y="2.2" width="16" height="8.6" rx="2" fill="currentColor"/><path d="M25 4.4v4.2c.9-.3 1.5-1.1 1.5-2.1s-.6-1.8-1.5-2.1z" fill="currentColor" opacity=".5"/></svg>
            <svg viewBox="0 0 16 14" width="15" height="13"><rect x=".7" y=".7" width="14.6" height="5.2" rx="2.6" fill="none" stroke="currentColor" stroke-width="1.3"/><circle cx="3.4" cy="3.3" r="1.5" fill="currentColor"/><rect x=".7" y="8.1" width="14.6" height="5.2" rx="2.6" fill="currentColor"/></svg>
            <span class="bar-clock">Mon 22 Jun&ensp;09:41</span>
          </div>
        </div>`;
}
