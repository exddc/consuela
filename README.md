# consuela

<p align="center">
  <img src="https://static.wikia.nocookie.net/familyguyfanon/images/1/15/Consuela.png/revision/latest/scale-to-width-down/260?cb=20161215031734" alt="Consuela" width="80">
</p>

consuela is a macOS cleanup script that removes leftover Xcode data and developer caches. It scans the groups you selected, prints how much this run will remove, and asks before it deletes anything.

The script permanently deletes the data it lists. It asks for confirmation unless you pass `-y`. Do not run it if you need to keep any listed data.

Do not run the Xcode group while Xcode is testing or building.

## What it cleans

**Xcode (`--xcode`)**

- Throwaway test clones in `~/Library/Developer/XCTestDevices`
- Simulator devices whose runtime is gone (`xcrun simctl delete unavailable`)
- Unavailable simulator runtimes (`xcrun simctl runtime delete`, one runtime at a time)
- Contents of DerivedData, CoreSimulator caches, simulator logs, xcodebuild cache
- SwiftPM cache and CocoaPods cache

**Caches (`--cache`)**

Package-manager caches only. See Cleanup policy for the exact command on each plan line.

**Docker (`--docker` / `--docker-all`)**

- Unused images, including tagged images that no container uses
- Stopped containers and build cache (`docker system prune -af`)
- Volumes are left in place

**Docker dangling (`--docker-dangling`)**

- Dangling images, stopped containers, and build cache (`docker system prune -f`)
- Volumes are left in place

Available simulators, source code, and installed runtimes that Xcode still uses stay in place.

Reclaimable size for Docker comes from `docker system df`. `prune -a` can free more than that figure because unused tagged images are included in the delete but not always in the df reclaimable column.

If `DOCKER_HOST` is set, consuela prints it and asks for confirmation even when you passed `-y`, because the prune runs against that daemon (which may be remote).

## Cleanup policy

Each plan line names the operation that will run.

- **Wipe directory contents** (`clear_dir`): delete everything inside a cache directory, keep the directory. Used for DerivedData, CoreSimulator caches, simulator logs, xcodebuild, SwiftPM, Bun's install cache, Homebrew's download cache, and for npm/Yarn/pip/uv/CocoaPods when that tool is not on PATH. The path must resolve under an allowlist (`~/Library/Caches`, `~/Library/Developer`, `~/Library/Logs`, `~/Library/pnpm`, `~/.npm`, `~/.local`, `~/.cache`, `~/.bun`, `~/.yarn`, or `brew --cache`). `/` and `$HOME` are refused.
- **npm / Yarn / pip / uv / CocoaPods**: when the tool is installed, run its own cache command (`npm cache clean --force`, `yarn cache clean`, `pip cache purge`, `uv cache clean`, `pod cache clean --all`).
- **pnpm**: `pnpm store prune` only. That removes packages no project references. It does not delete the store directory. If pnpm is not installed, consuela leaves the store alone.
- **Homebrew**: delete the contents of `brew --cache` (downloaded bottles and source archives). This is not `brew cleanup --prune=all`; old installed formula versions stay.
- **Docker**: `docker system prune -af` for `--docker` / `--docker-all`, or `docker system prune -f` for `--docker-dangling`. Neither command removes volumes.

## Install

Clone the repository and run the installer. consuela lives at [github.com/exddc/consuela](https://github.com/exddc/consuela).

```sh
git clone https://github.com/exddc/consuela.git
cd consuela
./install.sh
```

The installer copies `consuela` into `CONSUELA_BIN` (default `~/.local/bin`) after checking that the file has a shebang and is not empty HTML. You can pass a script URL as the first argument, or set `CONSUELA_URL`. Set `CONSUELA_SHA256` to require a SHA-256 match.

Do not pipe `install.sh` from the network into `sh`. That path cannot copy the local file and is harder to inspect.

## Usage

Run the full cleanup:

```sh
consuela
```

`-y` skips the confirmation prompt (except when `DOCKER_HOST` is set). `--dry-run` prints the plan and exits without deleting.

```sh
consuela --xcode
consuela --cache
consuela --docker
consuela --docker-dangling
consuela --xcode --cache
consuela --dry-run --cache
```

With group flags, consuela scans only those groups.

Disk Utility may still report the old free space until Time Machine local snapshots expire. The delay is not a failed cleanup.

## Tests

From a clone:

```sh
./tests/run.sh
```

The suite runs [shellcheck](https://www.shellcheck.net/), checks `fmt_kb` and plan records, refuses `clear_dir` of `$HOME` and `/`, and runs the simulator JSON fixtures.

## Contributing

Pull requests are welcome if you have a command that you think would be useful to add.

These are commands used with this development setup, so tools for other setups may be missing. Include a description of the command and why it is useful in the pull request.

## License

MIT. This is a collection of scripts; do what you want with it.
