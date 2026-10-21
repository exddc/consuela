# consuela

<p align="center">
  <img src="https://static.wikia.nocookie.net/familyguyfanon/images/1/15/Consuela.png/revision/latest/scale-to-width-down/260?cb=20161215031734" alt="Consuela" width="80">
</p>

consuela is a macOS cleanup script that removes leftover Xcode data and developer caches. It scans the groups you selected, prints how much this run will remove, and asks before it deletes anything. `consuela --report` prints a read-only storage report instead.

The script permanently deletes the data it lists. It asks for confirmation unless you pass `-y`. Do not run it if you need to keep any listed data.

## What it cleans

**Xcode (`--xcode`)**

- Throwaway test clones in `~/Library/Developer/XCTestDevices`
- Simulator devices whose runtime is gone (`xcrun simctl delete unavailable`), skipped when consuela finds more than one Xcode
- Unavailable simulator runtimes (`xcrun simctl runtime delete`), skipped when consuela finds more than one Xcode
- Contents of DerivedData, CoreSimulator caches, simulator logs, xcodebuild cache
- SwiftPM cache and CocoaPods cache

consuela keeps available simulators, source code, and runtimes that a found Xcode still uses.

`simctl` decides what is unavailable for the selected Xcode only. Another Xcode, such as Xcode-beta, may still need those simulators and runtimes. When there are unavailable simulators or runtimes and consuela finds more than one Xcode, it skips `xcrun simctl delete unavailable` and `xcrun simctl runtime delete`, lists the Xcodes it found, and still cleans the other Xcode items. To remove an old runtime yourself, run `xcrun simctl runtime list`, check that no Xcode still needs it, then run `xcrun simctl runtime delete <id>`.

consuela finds Xcode with Spotlight, in `/Applications` and `~/Applications`, and at the `xcode-select` path. It ignores Xcodes in the Trash. An Xcode on another mounted volume counts only if Spotlight reports it or it is the selected Xcode. If Spotlight reports no Xcode and there are unavailable simulators or runtimes to delete, consuela warns that it checked only those folders and the selected Xcode.

Without Xcode, consuela skips XCTestDevices, unavailable simulators, and unavailable runtimes, and cleans the rest of the group.

When the plan includes Xcode data, consuela checks for your Xcode, Simulator, booted simulators, and `xcodebuild`. If any are running, it lists them and asks for confirmation even when you passed `-y`. It also asks when the check fails. So `-y` does not make an Xcode cleanup unattended while these tools run. Do not start Xcode builds or tests until cleanup finishes.

**Caches (`--cache`)**

Package-manager caches only: npm, npx, Yarn, pnpm, Bun, pip, uv, Poetry, and Homebrew downloads. See Cleanup policy for the exact command on each plan line.

Poetry: consuela empties `cache` and `artifacts` inside Poetry's cache directory (`poetry config cache-dir`, default `~/Library/Caches/pypoetry`). It keeps `virtualenvs`. If `poetry config virtualenvs.path` points inside `cache` or `artifacts`, consuela skips that folder.

**Docker (`--docker` / `--docker-all`)**

- Unused images, including tagged images that no container uses
- Stopped containers and build cache (`docker system prune -af`)

**Docker dangling (`--docker-dangling`)**

- Dangling images, stopped containers, and build cache (`docker system prune -f`)

The Docker line is an estimate (`~`). consuela adds the Images, Containers, and Build Cache rows of the reclaimable column in `docker system df`. Those rows count images that no container uses, tagged or dangling, stopped containers, and build cache that is not in use. The real amount can be higher or lower. For example, df counts an image as in use while a stopped container refers to it, but prune removes that container first and can then remove the image.

`--docker` removes all of those. `--docker-dangling` keeps tagged images and some build cache, so it usually frees less than the estimate.

Build cache and images can share layers, so consuela adds the reclaimable column only. It never adds the image total to the build cache total.

After the plan, `--docker` lists every Docker volume with its size and how many containers use it. Volumes are never part of `--docker`, and their sizes are not in "This run".

consuela resolves the Docker context once, the same way the `docker` command does. The lookup follows `DOCKER_HOST`, `DOCKER_CONTEXT`, and `docker context use`. The scan and the prune both use that context, and the plan shows its endpoint. Any `unix://` socket counts as local. With `-y`, consuela skips Docker cleanup when the endpoint is not a `unix://` socket or cannot be read. Run consuela without `-y` to confirm a remote cleanup at the prompt.

## Opt-in targets

These flags are never part of a run without flags. Name them to include them. A run with only opt-in flags scans only those targets.

| Flag | Removes | Keeps |
| --- | --- | --- |
| `--xcode-previews` | Xcode Previews simulators, with `xcrun simctl --set "~/Library/Developer/Xcode/UserData/Previews/Simulator Devices" delete all` | the rest of `Xcode/UserData`, and `Simulator%20Devices` |
| `--xcodebuildmcp` | in `~/Library/Developer/XcodeBuildMCP/workspaces/*`: the contents of `DerivedData`, and finished `test-products/*.xctestproducts` with their completion markers | `state`, `locks`, `logs`, `result-bundles`, other files, and whole workspaces that hold a lock |
| `--docker-volume NAME` | one named Docker volume, with `docker volume rm NAME` | every volume you did not name |

**Xcode Previews.** simctl deletes only registered devices, the folders with a `device.plist`. Folders without one stay. consuela never deletes `Xcode/UserData` itself. The Xcode check described above also covers this flag.

**XcodeBuildMCP.** For test products, consuela uses the same protection rule as XcodeBuildMCP's own `purge` command. The other rules are stricter:

- A `DerivedData` folder qualifies only when every entry is a project folder with an `info.plist` or a `*.noindex` folder. One unknown entry or symlink skips the whole folder.
- A test products folder qualifies only when its name matches `<tool>_<time>_pid<n>_<hex>.xctestproducts`, and either its `.xcodebuildmcp-completed` marker exists or the owning process has exited.
- A workspace with anything in `locks`, or an unreadable `locks` folder, is skipped.

consuela checks these rules again right before it deletes. When `XcodeBuildMCP` runs, consuela lists it with the Xcode tools and asks even with `-y`.

**ShipIt folders are never deleted.** Electron apps stage updates in `~/Library/Caches/<id>.ShipIt`. `ShipItState.plist` is JSON, and its `updateBundleURL` names the pending update. Cursor, for example, can hold a pending update that it installs on the next quit. `--report` lists these folders with the pending update and whether the updater runs.

**Docker volumes.** `--docker-volume NAME` deletes only the volumes you name. Repeat the flag for more. consuela never picks a volume from its name, age, size, or link count. It refuses a volume when:

- the volume does not exist,
- any container uses it, running or stopped,
- Docker cannot tell whether a container uses it,
- the endpoint is not a local `unix://` socket.

Each volume asks you to type its name at a terminal. This happens even with `-y`, and the run fails without a terminal. Right before `docker volume rm`, consuela checks again that the pinned context points to the same endpoint and that no container uses the volume. `--docker-volume` does not run `--docker` or any other group. consuela never runs `docker volume prune` or `docker system prune --volumes`.

## Storage report

```sh
consuela --report
```

`--report` scans every group and every opt-in target, prints sizes, and exits. It never deletes, with or without `-y`, and takes no group flags. It takes about a minute on a large disk. The report has three parts:

- **Cleanup targets**: each plan line with the flag that selects it. Sizes are measured on disk. `~` marks an estimate of what the command frees, and `?` an unknown size. Totals show the run without flags and the opt-in flags separately.
- **Docker volumes**: name, size, and how many containers use each one.
- **Review only**: data consuela never deletes. It includes `/Library/Developer/CoreSimulator/Caches/dyld`, simulator devices, iOS DeviceSupport, ShipIt updates, Playwright browsers, Fusion webdeploy folders (the active one is marked), Notion, Spotify, Linear, and BambuStudio data, Poetry virtualenvs, the Docker Desktop disk image, and `docker system df`. Each line says how to clean that data safely, if there is a way. A `>` before a size means part of the folder was unreadable.

The report checks fixed paths only. It does not search the whole disk.

## Install

Install with Homebrew:

```sh
brew install exddc/tap/consuela
```

Or run the installer:

```sh
curl -fsSL https://raw.githubusercontent.com/exddc/consuela/main/install.sh | sh
```

Homebrew installs the latest release. The installer installs the latest commit on `main`, which can be newer than the version `consuela --version` prints.

## Update

If you installed with Homebrew, update with Homebrew:

```sh
brew upgrade consuela
```

On a Homebrew install, `consuela --update` prints that command and changes nothing.

If you used the installer, replace your installed consuela with the latest version from GitHub:

```sh
consuela --update
```

`--update` downloads the latest `install.sh` from `main` and runs it with `CONSUELA_BIN` set to the directory of the consuela file you ran. It must be the only argument. If the file has not changed, the installer leaves it alone and says so.

`CONSUELA_URL` and `CONSUELA_SHA256` apply to the consuela download, as with the installer. Nothing checks the installer itself, so you trust it the same way as with `curl | sh`.

consuela refuses to update a symlink or a copy named anything other than `consuela`. If a symlink points into a git clone, run `git pull` in the clone.

Installations from before `--update` existed do not know the flag. Update them once by running the install command again. For a custom install directory, pass the same `CONSUELA_BIN`:

```sh
curl -fsSL https://raw.githubusercontent.com/exddc/consuela/main/install.sh | CONSUELA_BIN=/path/to/bin sh
```

## Usage

Run the full cleanup:

```sh
consuela
```

`-y` skips the confirmation prompt, except in the Xcode and Docker cases described above. `--dry-run` prints the plan and exits without deleting.

```sh
consuela --xcode
consuela --cache
consuela --docker
consuela --docker-dangling
consuela --xcode --cache
consuela --dry-run --cache
consuela --dry-run --xcode-previews --xcodebuildmcp
consuela --docker-volume my-volume
consuela --report
```

With group flags, consuela scans only those groups.

consuela exits 0 after a dry run or report, when nothing needs cleaning, or when every step succeeds. It exits 1 for a usage error, a declined prompt, a failed step, or when it cannot start, for example outside macOS. When a step fails, consuela runs the remaining steps and lists the failed ones on stderr. If consuela cannot scan something, such as Docker with the daemon stopped, it prints a warning and skips it. The exit status does not change.

Disk Utility may still report the old free space until Time Machine local snapshots expire. The delay is not a failed cleanup.

## Cleanup policy

Each plan line names the operation that will run. A `~` before a size marks an estimate. The command on that line can free more or less than shown. The "This run" line lists estimated sizes separately.

- **Wipe directory contents** (`clear_dir`): delete everything inside a cache directory, keep the directory. Used for DerivedData, CoreSimulator caches, simulator logs, xcodebuild, SwiftPM, Bun's install cache, Homebrew's download cache, and for npm/Yarn/pip/uv/CocoaPods when the tool is not on PATH.
- **Allowlist**: consuela resolves symlinks before it wipes a directory or deletes XCTestDevices. The resolved path must match one of these entries:
  - Inside only: `~/Library/Caches`, `~/.cache`
  - The directory itself or inside: `~/Library/Developer/Xcode/DerivedData`, `~/Library/Developer/CoreSimulator/Caches`, `~/Library/Developer/XCTestDevices`, `~/Library/Logs/CoreSimulator`, `~/.npm`, `~/.bun/install/cache`, `~/.yarn/cache`
  - Exactly this directory: `~/Library/Developer/Xcode/UserData/Previews/Simulator Devices`, and `~/Library/Developer/XcodeBuildMCP/workspaces/<one name>/DerivedData`
  - Any other path is skipped with a warning during the scan. `/` and `$HOME` are never allowed.
  - Test products are checked against their exact parent folder, and refused when they are symlinks.
- **No double counting**: when two plan lines would cover the same folder, or one inside the other, the later one skips it with a warning.
- **npm / Yarn / pip / uv / CocoaPods**: when the tool is installed, run its own cache command (`npm cache clean --force`, `yarn cache clean`, `pip cache purge`, `uv cache clean`, `pod cache clean --all`).
- **npx**: `npm cache clean --force` empties only `_cacache`, so consuela also wipes the contents of `_npx` in npm's cache directory. npx downloads a package again the next time you run it. The npm line counts `_cacache` only.
- **pnpm**: `pnpm store prune` only. That removes packages no project references. It does not delete the store directory. The size shown is the whole store, marked `~` as an estimate. If pnpm is not installed, consuela leaves the store alone.
- **Homebrew**: delete the contents of `brew --cache` (downloaded bottles and source archives). This is not `brew cleanup --prune=all`; old installed formula versions stay. A custom `brew --cache` outside the allowlist is skipped.
- **Docker**: `docker system prune -af` for `--docker` / `--docker-all`, or `docker system prune -f` for `--docker-dangling`. Neither command removes volumes.

npm, Yarn, pnpm, pip, uv, and Poetry commands run from your home directory. consuela sets `npm_config_logs_max=0`, `npm_config_update_notifier=false`, and `PYTHONDONTWRITEBYTECODE=1`, so scans leave no npm logs or Python bytecode behind. Config files in the current directory, such as `.npmrc` or `.yarnrc.yml`, do not change what gets cleaned. Config in your home directory and environment variables such as `UV_CACHE_DIR` still apply. These commands use your global tool versions.

## Contributing

Pull requests are welcome if you have a command that you think would be useful to add to the collection.

These are commands that I use with my development setup, so commands for other setups, languages, and tools may be missing. You are welcome to add them, but please include a description of the command and why it is useful in the pull request.

## License

MIT. This is a collection of scripts, so do what you want with it.
