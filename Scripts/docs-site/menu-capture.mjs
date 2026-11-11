// Each callout's `y` is the percent down this exact image where its row sits, and `captionY` is
// where the figure caption starts, below the last callout. Re-measure them when the capture is replaced.
export const menuCapture = {
  file: "pdtbar-menu.png",
  width: 768,
  height: 1518,
  displayWidth: 384,
  captionY: 85,
  callouts: [
    { label: "calloutQuiet", y: 10.1, tone: "accent" },
    { label: "calloutConcentration", y: 30.0, tone: "accent" },
    { label: "calloutIncome", y: 57.9, tone: "income" },
    { label: "calloutMovers", y: 68.6, tone: "accent" },
    { label: "calloutPrices", y: 79.3, tone: "accent" },
  ],
};
