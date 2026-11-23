---
name: offload-to-drive
description: Move a project's big build caches off a full internal disk onto an external drive behind links, safely and only what can move - check the drive's real speed first, copy and compare before an original goes, rebuild copied caches from scratch, find out what a simulator or emulator can't read from the drive, add a check that stops runs when the drive is unplugged, and record what moved. Use when the user says "move the build caches to the SSD", "offload to the external drive", "the disk keeps filling, can we use my SSD?", after they plug in or replace a drive's cable, or when they run /offload-to-drive. Argument - the drive's mount point or name, or nothing to look for one.
---

<!-- claude-playbook skill v1.14.2 -->

# Offload to an external drive

Moves what grows back (build caches, derived data) to an external drive and
leaves a link in its place, so builds keep using the same paths. It changes
tracked tooling, so work from an issue as the project's rules say. The
"One simulator at a time" rule applies throughout: move nothing a running
job uses, and take the simulator lock (`{{simulator_wrapper}}`) for anything
that touches a simulator.

Never get past a step by destroying something: an original is removed only
after a build or test has run through its link, and a stopped step is put
back by hand before going on.

## 1. The drive

- Find it (`diskutil list external`, `ls /Volumes`, or the argument). It
  should be APFS on a Mac (or the platform's native format), with Spotlight
  off for it if it's only for caches (a `.metadata_never_index` file at its
  top).
- **Check its real speed before moving anything.** The link speed
  (`ioreg -r -c IOUSBHostDevice -l -w0 | grep UsbLinkSpeed`, or
  `system_profiler SPUSBHostDataType SPThunderboltDataType`) and a 2 GB
  write and read (`dd if=/dev/zero of=<drive>/.speedtest bs=8m count=256`,
  then read it back to `/dev/null`, then delete it). 480 Mb/s (about
  40 MB/s) means a USB 2 cable, whatever the port says: say so and stop,
  since builds there would be slower than the full disk. Several hundred
  MB/s or more is worth it.
- If the drive doesn't show up at all after a cable swap, ask the user to
  replug both ends before anything else: a new cable often needs it.

## 2. What can move

List the build folders and their sizes (`du -sh`), and sort each into one of
three kinds. Ask the user before touching a folder that may be another
session's work in progress.

| Kind | Examples | Move it? |
| --- | --- | --- |
| Only the build tool reads and writes it | derived data used only for builds and device installs, a lint or "does it compile" build, a release build | Yes |
| A process **inside a simulator or emulator** opens it | the derived data tests run from, test fixtures, folders tests write into | Only after step 4 passes |
| The simulators themselves | `~/Library/Developer/CoreSimulator/Devices` | No: the simulator service lists no simulators from a linked folder, with no dialog. Android emulators: not checked |

Grep the tests for paths under the build folder: a test that writes there
from inside the simulator makes that folder the second kind.

## 3. Move one folder

For each folder, with nothing building (`pgrep -f 'xcodebuild|gradle|cargo'`
or the project's build command):

1. Copy it to the drive under a folder named for the project:
   `rsync -a <folder>/ <drive>/<project>/<folder>/`. On macOS, use `ditto`
   when extended attributes matter (simulator data): macOS's own `rsync`
   (openrsync) doesn't keep them.
2. Compare: `diff -rq` the two. Where the data holds folder links that loop
   (simulator data does), `diff -r` gives up with "Directory loop
   detected": compare with `rsync -rlnc --delete --out-format='%n' a/ b/`
   instead (no output means identical).
3. Re-sync right before the swap, then move the original aside
   (`<folder>.internal-old`) and link: `ln -s <drive>/<project>/<folder> <folder>`.
4. Build through the link. **Copied derived data often breaks on its first
   build** (a missing temporary file, compile steps "failing with exit code
   0"): empty the drive's copy and build from scratch there; it's a cache.
5. Once a build (and, for the second kind, the tests) has passed through the
   link, remove `<folder>.internal-old`.

If a step is stopped part-way (a timeout, a stopped task), check the folder
by hand and put the original back: a shell `trap` doesn't run when the shell
is killed.

## 4. Can a simulator read the drive? (macOS)

macOS asks before an app reads a removable volume, and a process inside a
simulator just waits in `open()` until someone answers, so a test hangs
("The test runner hung before establishing connection" when the test bundle
itself is on the drive).

1. Copy the test fixtures to the drive, link them in place of the originals
   (keep those), and run one small test class that reads them.
2. If it hangs, sample the test process (`sample <pid> 3`): blocked in
   `open` on a drive path is this. The user has to be at the machine for it:
   ask them (they're often remote), have them allow the "would like to
   access files on a removable volume" dialog, and name the app it shows.
   If no dialog shows, it's under System Settings → Privacy & Security →
   Files & Folders, Removable Volumes.
3. Run the class again: it should pass at full speed with no dialog. Each
   simulator platform (an iPhone simulator, an Apple TV one) may ask once.
4. Only then move the second kind of folder (step 3), and run the full
   tests and the UI tests through the links.

**A link to a folder can't be listed by Foundation**
(`FileManager.contentsOfDirectory(at:)` fails with "Not a directory"). A
test that hands an app a linked folder to list should resolve it first
(`resolvingSymlinksInPath()`, `os.path.realpath`). Opening files inside it
works.

## 5. When the drive is unplugged

A link to a missing drive makes builds fail part-way with odd errors.
Install `scripts/check-links.sh` (next to this file) into the project's
scripts folder, set its `BUILD_DIR`, `EXTRA_LINKS` and `DRIVE_NAME` lines,
and call it first from the scripts that build or run tests
(`{{simulator_wrapper}}`, the device install script, any build check).
It also lists and writes to each linked folder under a time limit
(`CHECK_LINKS_TIMEOUT`, 5 s), because a drive can stay mounted while every
read on it hangs, and the links still look fine. Test both ways: it's silent
with the drive in, and with a made-up dangling link in the build folder it
names it and exits 1.

If the project has a cleanup script that clears caches, make it treat a
link as "on the drive": count it as 0 bytes here, and skip it when clearing.
Deleting through a link frees nothing on the internal disk, and Python's
`shutil.rmtree` refuses a link (an `ignore_errors=True` hides that and
reports "cleared").

## 6. Space, and cleanup

- Freed space can take a day to show: Time Machine's local snapshots
  (`tmutil listlocalsnapshots /`) still hold what was removed, and macOS
  releases them on its own. Removing a snapshot removes a backup, so leave
  them unless the user asks.
- Removing a folder at the top level of a drive (`/Volumes/<drive>/<x>`) is
  refused by Claude Code's safety check: tell the user the path and let them
  delete it.

## 7. Record it

- The project's disk rule in `CLAUDE.md`: which folders are links to which
  drive, what stays internal and why, and the check script. Add when it was
  decided.
- A dated section on the project's disk-space decision page: the speeds, what
  moved, what couldn't and the evidence, the permission step.
- A memory: the drive's name, what lives there, and that a simulator test
  needs the permission granted once per platform.
