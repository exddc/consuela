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
- Simulator devices whose runtime is gone (`xcrun simctl delete unavailable`), skipped when consuela finds more than one Xcode
- Unavailable simulator runtimes (`xcrun simctl runtime delete`), skipped when consuela finds more than one Xcode
- Contents of DerivedData, CoreSimulator caches, simulator logs, xcodebuild cache
- SwiftPM cache and CocoaPods cache

consuela keeps available simulators, source code, and runtimes that a found Xcode still uses.

`simctl` decides what is unavailable for the selected Xcode only. Another Xcode, such as Xcode-beta, may still need those simulators and runtimes. When consuela finds more than one Xcode, it skips `xcrun simctl delete unavailable` and `xcrun simctl runtime delete`, lists the Xcodes it found, and still cleans the other Xcode items. To remove an old runtime yourself, run `xcrun simctl runtime list`, check that no Xcode still needs it, then run `xcrun simctl runtime delete <id>`.

consuela finds Xcode with Spotlight, in `/Applications` and `~/Applications`, and at the `xcode-select` path. It ignores Xcodes in the Trash. An Xcode on another mounted volume counts only if Spotlight reports it or it is the selected Xcode. If Spotlight reports no Xcode, consuela warns that it checked only those folders and the selected Xcode.

**Caches (`--cache`)**

Package-manager caches only. See Cleanup policy for the exact command on each plan line.

**Docker (`--docker` / `--docker-all`)**

- Unused images, including tagged images that no container uses
- Stopped containers and build cache (`docker system prune -af`)

**Docker dangling (`--docker-dangling`)**

- Dangling images, stopped containers, and build cache (`docker system prune -f`)

Reclaimable size for Docker comes from `docker system df`. `prune -a` can free more than that figure because unused tagged images are included in the delete but not always in the df reclaimable column.

If `DOCKER_HOST` is set, consuela prints it and asks for confirmation even when you passed `-y`.

## Install

Run the installer:

```sh
curl -fsSL https://raw.githubusercontent.com/exddc/consuela/main/install.sh | sh
```

## Usage

Run the full cleanup:

```sh
consuela
```

`-y` skips the confirmation prompt. `--dry-run` prints the plan and exits without deleting.

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

## Cleanup policy

Each plan line names the operation that will run.

- **Wipe directory contents** (`clear_dir`): delete everything inside a cache directory, keep the directory. Used for DerivedData, CoreSimulator caches, simulator logs, xcodebuild, SwiftPM, Bun's install cache, Homebrew's download cache, and for npm/Yarn/pip/uv/CocoaPods when that tool is not on PATH. The path must resolve under an allowlist (`~/Library/Caches`, `~/Library/Developer`, `~/Library/Logs`, `~/Library/pnpm`, `~/.npm`, `~/.local`, `~/.cache`, `~/.bun`, `~/.yarn`, or `brew --cache`). `/` and `$HOME` are refused.
- **npm / Yarn / pip / uv / CocoaPods**: when the tool is installed, run its own cache command (`npm cache clean --force`, `yarn cache clean`, `pip cache purge`, `uv cache clean`, `pod cache clean --all`).
- **pnpm**: `pnpm store prune` only. That removes packages no project references. It does not delete the store directory. If pnpm is not installed, consuela leaves the store alone.
- **Homebrew**: delete the contents of `brew --cache` (downloaded bottles and source archives). This is not `brew cleanup --prune=all`; old installed formula versions stay.
- **Docker**: `docker system prune -af` for `--docker` / `--docker-all`, or `docker system prune -f` for `--docker-dangling`. Neither command removes volumes.


## Contributing

Pull requests are welcome if you have a command that you think would be useful to add to the collection.

These are commands that I use with my development setup, so commands for other setups, languages, and tools may be missing. You are welcome to add them, but please include a description of the command and why it is useful in the pull request.

## License

MIT. This is a collection of scripts, so do what you want with it.
