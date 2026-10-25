{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchPnpmDeps,
  nodejs_24,
  pnpm_10,
  pnpmConfigHook,
  node-gyp,
  python3,
  pkg-config,
  autoPatchelfHook,
  makeWrapper,
  git,
  bash,
  xdg-utils,
  poppler-utils,
  ffmpeg,
  electron_44,
  desktop-file-utils,
}:
let
  release = lib.importJSON ./release.json;
  pnpm = pnpm_10.override { nodejs-slim = nodejs_24; };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "open-design";
  inherit (release) version;

  src = fetchFromGitHub {
    owner = "nexu-io";
    repo = "open-design";
    tag = "open-design-v${finalAttrs.version}";
    hash = release.srcHash;
  };

  pnpmDeps = fetchPnpmDeps {
    inherit pnpm;
    inherit (finalAttrs) pname version src;
    fetcherVersion = 5;
    hash = release.pnpmDepsHash;
  };

  nativeBuildInputs = [
    nodejs_24
    pnpm
    pnpmConfigHook
    node-gyp
    python3
    pkg-config
    makeWrapper
    autoPatchelfHook
    desktop-file-utils
  ];
  buildInputs = [ stdenv.cc.cc.lib ];
  env = {
    ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
    OPEN_DESIGN_POSTINSTALL_TARGETS = ''["apps/daemon","packages/components","packages/host","packages/download"]'';
    NEXT_TELEMETRY_DISABLED = "1";
    npm_config_nodedir = "${nodejs_24}";
    npm_config_build_from_source = "true";
  };

  buildPhase = ''
    runHook preBuild
    pnpm -r rebuild esbuild
    for module in better-sqlite3 node-pty; do
      pushd "$(realpath "apps/daemon/node_modules/$module")"
      node-gyp rebuild --nodedir=${nodejs_24}
      popd
    done
    node scripts/postinstall.mjs
    pnpm --filter @open-design/desktop build
    pnpm --filter @open-design/web build:sidecar
    pnpm --filter @open-design/packaged build
    # Keep the od browser entry point as well as the desktop SSR runtime.
    pnpm --filter @open-design/web build
    OD_WEB_OUTPUT_MODE=server pnpm --filter @open-design/web build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/open-design" "$out/bin"
    # Keep the installed workspace links and native build outputs. Upstream's
    # legacy deploy command resolves dependencies again and requires network.
    cp -a node_modules packages "$out/lib/open-design/"
    # These workspace projects are build/test tools, not daemon dependencies.
    rm "$out/lib/open-design/node_modules/@open-design/"tools-{dev,pack,release,serve}
    rm "$out/lib/open-design/node_modules/.pnpm/node_modules/@open-design/"{terminal,e2e,closure}
    mkdir -p "$out/lib/open-design/apps/"{daemon,web,desktop,packaged} "$out/lib/open-design/bin"
    cp -a apps/daemon/{bin,dist,node_modules,package.json} "$out/lib/open-design/apps/daemon/"
    cp -a apps/desktop/{dist,node_modules,package.json,vendor} "$out/lib/open-design/apps/desktop/"
    cp -a apps/packaged/{dist,node_modules,package.json} "$out/lib/open-design/apps/packaged/"
    cp -a apps/web/{out,.next,dist,node_modules,package.json,public,next.config.ts,app,src} "$out/lib/open-design/apps/web/"
    rm -rf "$out/lib/open-design/apps/web/.next/cache"
    cp apps/desktop/dist/main/preload.cjs "$out/lib/open-design/preload.cjs"
    ln -s ${nodejs_24}/bin/node "$out/lib/open-design/bin/node"
    cp -a package.json skills design-systems design-templates craft prompt-templates data assets plugins \
      "$out/lib/open-design/"
    cp ${./main.cjs} "$out/lib/open-design/main.cjs"
    relativeRoot=$(node -p 'require("node:path").relative("${electron_44.dist}/resources", process.argv[1])' "$out/lib/open-design")
    substitute ${./open-design-config.json.in} "$out/lib/open-design/open-design-config.json" \
      --subst-var-by out "$out" --subst-var-by version "${finalAttrs.version}" \
      --subst-var-by relativeRoot "$relativeRoot"
    node - "$out/lib/open-design/package.json" <<'NODE'
    const fs = require("node:fs");
    const filename = process.argv[2];
    const pkg = JSON.parse(fs.readFileSync(filename, "utf8"));
    pkg.main = "main.cjs";
    pkg.version = "${finalAttrs.version}";
    fs.writeFileSync(filename, JSON.stringify(pkg, null, 2));
    NODE
    install -Dm644 ${./open-design.desktop} "$out/share/applications/open-design.desktop"
    install -Dm644 tools/pack/resources/linux/icon.png "$out/share/icons/hicolor/512x512/apps/open-design.png"
    makeWrapper ${nodejs_24}/bin/node "$out/bin/od" \
      --add-flags "$out/lib/open-design/apps/daemon/dist/cli.js" \
      --run 'export OD_DATA_DIR="''${OD_DATA_DIR:-''${XDG_DATA_HOME:-$HOME/.local/share}/open-design}"' \
      --prefix PATH : ${
        lib.makeBinPath [
          nodejs_24
          git
          bash
          xdg-utils
          poppler-utils
          ffmpeg
        ]
      }
    makeWrapper ${electron_44}/bin/electron "$out/bin/open-design" \
      --add-flags "$out/lib/open-design" \
      --add-flags "--class=open-design" \
      --set OD_PACKAGED_CONFIG_PATH "$out/lib/open-design/open-design-config.json" \
      --set OD_UPDATE_ENABLED 0 \
      --prefix PATH : ${
        lib.makeBinPath [
          nodejs_24
          git
          bash
          xdg-utils
          poppler-utils
          ffmpeg
        ]
      }
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    desktop-file-validate "$out/share/applications/open-design.desktop"
    cd "$out/lib/open-design/apps/daemon"
    node --input-type=commonjs -e '
      const Database = require("better-sqlite3");
      const db = new Database(":memory:");
      if (db.prepare("SELECT 1 AS value").get().value !== 1) process.exit(1);
      db.close();
      require("node-pty");
    '
    runHook postInstallCheck
  '';

  passthru.electron = electron_44;

  meta = {
    description = "Local-first AI design workspace with the upstream Electron desktop shell";
    homepage = "https://github.com/nexu-io/open-design";
    license = lib.licenses.asl20;
    mainProgram = "open-design";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
})
