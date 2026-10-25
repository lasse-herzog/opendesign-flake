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
  ];
  buildInputs = [ stdenv.cc.cc.lib ];
  env = {
    ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
    OPEN_DESIGN_POSTINSTALL_TARGETS = ''["apps/daemon","packages/components","packages/host"]'';
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
    pnpm --filter @open-design/web build
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
    rm "$out/lib/open-design/node_modules/.pnpm/node_modules/@open-design/"{terminal,desktop,e2e,packaged,closure}
    mkdir -p "$out/lib/open-design/apps/daemon" "$out/lib/open-design/apps/web"
    cp -a apps/daemon/{bin,dist,node_modules,package.json} "$out/lib/open-design/apps/daemon/"
    cp -a apps/web/out "$out/lib/open-design/apps/web/"
    cp -a package.json skills design-systems design-templates craft prompt-templates data assets plugins \
      "$out/lib/open-design/"
    makeWrapper ${nodejs_24}/bin/node "$out/bin/open-design" \
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
    ln -s open-design "$out/bin/od"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
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

  meta = {
    description = "Local-first AI design workspace (browser UI and od CLI)";
    homepage = "https://github.com/nexu-io/open-design";
    license = lib.licenses.asl20;
    mainProgram = "open-design";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
})
