# Open Design Nix package

An option-free flake packaging [Open Design](https://github.com/nexu-io/open-design)
from a pinned stable release. It exposes `packages.<system>.open-design` and
`packages.<system>.default` for `x86_64-linux` and `aarch64-linux`.

This builds the upstream browser UI and `od` daemon/CLI from source. Running
`open-design` starts the local server and opens your browser. The Electron desktop
shell is not included: upstream currently publishes stable installers only for
macOS and Windows.

```sh
nix run github:lasse-herzog/opendesign-flake
# From a local checkout, build / install:
nix build .#open-design
nix profile add .#open-design
# Start without opening a browser:
od --no-open
```

The package defaults `OD_DATA_DIR` to `$XDG_DATA_HOME/open-design` (or
`$HOME/.local/share/open-design`); an explicit `OD_DATA_DIR` takes precedence.
Install and authenticate your preferred agent CLI separately; the app inherits
your PATH. No NixOS or Home Manager module is needed.

To consume this flake from another flake, add
`inputs.open-design.url = "github:lasse-herzog/opendesign-flake";` and use
`inputs.open-design.packages.${pkgs.stdenv.hostPlatform.system}.default`.
Keep its own nixpkgs pin; it uses the current pnpm fetcher.

## Release updates

The GitHub Actions workflow checks the upstream latest stable release every six
hours and can also be started manually. Upstream release events cannot directly
trigger workflows in a separate packaging repository, so this uses polling.

For each new version it regenerates the source and pnpm dependency hashes, builds
the package, and commits `nix/release.json` to the default branch only after the
build succeeds. Failed updates restore the previous release file and fail the
job. It uses the built-in `GITHUB_TOKEN`; no personal token is needed. Repository
rules must allow Actions to write to the default branch. A protected branch may
require adapting the final step to open a pull request instead.

Scheduled workflows run on this repository's default branch; updates can also be
started from the Actions tab.

To update locally (Python 3 and Nix required):

```sh
python3 scripts/update.py
```

`flake.lock` pins nixpkgs independently; refresh it with `nix flake update nixpkgs`.
The check workflow evaluates both systems and builds on x86_64 Linux. ARM builds
require an ARM builder and are not exercised by that workflow.
