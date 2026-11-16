import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const sdkVersion = "26.4";

// A fake toolchain: the linker stamps the SDK it is handed with -platform_version, otherwise the
// deployment target, as SwiftBuild does. Nothing here builds, signs, or touches the keychain.
const fakeTools = {
  xcrun: `#!/bin/sh
case "$*" in
  *--show-sdk-path*) echo /fixture/MacOSX.sdk ;;
  *--show-sdk-version*) echo ${sdkVersion} ;;
  *) exit 1 ;;
esac
`,
  swift: `#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");
const args = process.argv.slice(2);
const conf = args[args.indexOf("-c") + 1];
const arch = args.includes("--arch") ? args[args.indexOf("--arch") + 1] : null;
const binDir = arch ? path.join(".build", arch + "-apple-macosx", conf) : path.join(".build", conf);
if (args.includes("--show-bin-path")) {
  console.log(path.resolve(binDir));
  process.exit(0);
}
const linker = args.flatMap((arg, i) => (args[i - 1] === "-Xlinker" ? [arg] : []));
const platform = linker.indexOf("-platform_version");
const honored = platform >= 0 && process.env.FAKE_LINKER_IGNORES_PLATFORM_VERSION !== "1";
fs.mkdirSync(binDir, { recursive: true });
fs.writeFileSync(path.join(binDir, "pdtbar"), "sdk " + (honored ? linker[platform + 3] : "14.0") + "\\n", { mode: 0o755 });
`,
  otool: `#!/bin/sh
for last; do :; done
printf ' cmd LC_BUILD_VERSION\\n minos 14.0\\n %s\\n' "$(cat "$last")"
`,
  codesign: "#!/bin/sh\nexit 0\n",
};

function packageApp(t, { arches = "", linkerIgnoresPlatformVersion = false } = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "pdtbar-package-"));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  for (const directory of ["Scripts", "bin"]) fs.mkdirSync(path.join(root, directory));
  fs.copyFileSync(path.join(scriptDir, "package_app.sh"), path.join(root, "Scripts", "package_app.sh"));
  for (const [name, source] of Object.entries(fakeTools)) {
    fs.writeFileSync(path.join(root, "bin", name), source, { mode: 0o755 });
  }
  const result = spawnSync("/bin/bash", [path.join(root, "Scripts", "package_app.sh"), "debug"], {
    encoding: "utf8",
    env: {
      ...process.env,
      PATH: `${path.join(root, "bin")}:${process.env.PATH}`,
      ARCHES: arches,
      PDTBAR_APP_IDENTITY: "",
      PDTBAR_PROVISIONING_PROFILE: "",
      FAKE_LINKER_IGNORES_PLATFORM_VERSION: linkerIgnoresPlatformVersion ? "1" : "0",
    },
  });
  const binary = path.join(root, "PDTBar.app", "Contents", "MacOS", "PDTBar");
  return { result, packaged: fs.existsSync(binary) ? fs.readFileSync(binary, "utf8").trim() : null };
}

for (const arches of ["", "arm64"]) {
  const label = arches || "default arch";

  test(`package_app records the selected SDK, not the deployment target (${label})`, (t) => {
    const { result, packaged } = packageApp(t, { arches });
    assert.equal(result.status, 0, result.stdout + result.stderr);
    assert.equal(packaged, `sdk ${sdkVersion}`);
  });

  test(`package_app rejects a binary stamped with the deployment target as its SDK (${label})`, (t) => {
    const { result, packaged } = packageApp(t, { arches, linkerIgnoresPlatformVersion: true });
    assert.notEqual(result.status, 0, result.stdout + result.stderr);
    assert.match(result.stderr, new RegExp(`SDK ${sdkVersion.replace(".", "\\.")}`));
    assert.equal(packaged, null);
  });
}
