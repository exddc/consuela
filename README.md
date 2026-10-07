# consuela

<p align="center">
  <img src="https://static.wikia.nocookie.net/familyguyfanon/images/1/15/Consuela.png/revision/latest/scale-to-width-down/260?cb=20161215031734" alt="Consuela" width="80">
</p>

consuela is a macOS cleanup script that removes leftover Xcode data and developer caches. It scans the groups you selected, prints how much this run will remove, and asks before it deletes anything.

The script permanently deletes the data it lists. It asks for confirmation unless you pass `-y`. Do not run it if you need to keep any listed data.

## What it cleans

**Xcode (`--xcode`)**

- Throwaway test clones in `~/Library/Developer/XCTestDevices`
- Simulator devices whose runtime is gone (`xcrun simctl delete unavailable`)
- Unavailable simulator runtimes (`xcrun simctl runtime delete`)
- Contents of DerivedData, CoreSimulator caches, simulator logs, xcodebuild cache
- SwiftPM cache and CocoaPods cache

Available simulators, source code, and installed runtimes that Xcode still uses stay in place.

Without Xcode, consuela skips XCTestDevices, unavailable simulators, and unavailable runtimes, and cleans the rest of the group.

When the plan includes Xcode data, consuela checks for your Xcode, Simulator, booted simulators, and `xcodebuild`. If any are running, it lists them and asks for confirmation even when you passed `-y`. It also asks when the check fails. So `-y` does not make an Xcode cleanup unattended while these tools run. Do not start Xcode builds or tests until cleanup finishes.

**Caches (`--cache`)**

Package-manager caches only. See Cleanup policy for the exact command on each plan line.

**Docker (`--docker` / `--docker-all`)**

- Unused images, including tagged images that no container uses
- Stopped containers and build cache (`docker system prune -af`)

**Docker dangling (`--docker-dangling`)**

- Dangling images, stopped containers, and build cache (`docker system prune -f`)

Reclaimable size for Docker comes from `docker system df`. `prune -a` can free more than that figure because unused tagged images are included in the delete but not always in the df reclaimable column.

consuela resolves the Docker context once, the same way the `docker` command does. The lookup follows `DOCKER_HOST`, `DOCKER_CONTEXT`, and `docker context use`. The scan and the prune both use that context, and the plan shows its endpoint. Any `unix://` socket counts as local. With `-y`, consuela skips Docker cleanup when the endpoint is not a `unix://` socket or cannot be read. Run consuela without `-y` to confirm a remote cleanup at the prompt.

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

`-y` skips the confirmation prompt, except in the Xcode and Docker cases described above. `--dry-run` prints the plan and exits without deleting.

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

- **Wipe directory contents** (`clear_dir`): delete everything inside a cache directory, keep the directory. Used for DerivedData, CoreSimulator caches, simulator logs, xcodebuild, SwiftPM, Bun's install cache, Homebrew's download cache, and for npm/Yarn/pip/uv/CocoaPods when the tool is not on PATH.
- **Allowlist**: consuela resolves symlinks before it wipes a directory or deletes XCTestDevices. The resolved path must match one of these entries:
  - Inside only: `~/Library/Caches`, `~/.cache`
  - The directory itself or inside: `~/Library/Developer/Xcode/DerivedData`, `~/Library/Developer/CoreSimulator/Caches`, `~/Library/Developer/XCTestDevices`, `~/Library/Logs/CoreSimulator`, `~/.npm`, `~/.bun/install/cache`, `~/.yarn/cache`
  - Any other path is skipped with a warning during the scan. `/` and `$HOME` are never allowed.
- **npm / Yarn / pip / uv / CocoaPods**: when the tool is installed, run its own cache command (`npm cache clean --force`, `yarn cache clean`, `pip cache purge`, `uv cache clean`, `pod cache clean --all`).
- **pnpm**: `pnpm store prune` only. That removes packages no project references. It does not delete the store directory. If pnpm is not installed, consuela leaves the store alone.
- **Homebrew**: delete the contents of `brew --cache` (downloaded bottles and source archives). This is not `brew cleanup --prune=all`; old installed formula versions stay. A custom `brew --cache` outside the allowlist is skipped.
- **Docker**: `docker system prune -af` for `--docker` / `--docker-all`, or `docker system prune -f` for `--docker-dangling`. Neither command removes volumes.

npm, Yarn, pnpm, pip, and uv commands run from your home directory. Config files in the current directory, such as `.npmrc` or `.yarnrc.yml`, do not change what gets cleaned. Config in your home directory and environment variables such as `UV_CACHE_DIR` still apply. These commands use your global tool versions.

## Contributing

Pull requests are welcome if you have a command that you think would be useful to add to the collection.

These are commands that I use with my development setup, so commands for other setups, languages, and tools may be missing. You are welcome to add them, but please include a description of the command and why it is useful in the pull request.

## License

MIT. This is a collection of scripts, so do what you want with it.
