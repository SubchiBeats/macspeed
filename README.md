# MacSpeed

A safe, friendly performance scanner & cleaner for your Mac. Built around a
2-core / 8GB Intel MacBook Pro, but works on any Mac.

## How to run it

**Easiest:** double-click **`MacSpeed.command`** in Finder. It opens in Terminal.
- First time only, macOS may say it "can't be opened because it is from an
  unidentified developer." Right-click the file → **Open** → **Open**. After that
  it just works.

**Or from Terminal:**

```bash
bash ~/Desktop/macspeed/macspeed.sh
```

## What it does (menu options)

| # | Option | Touches your files? |
|---|--------|---------------------|
| 1 | System overview — specs, disk, RAM, load, swap | No |
| 2 | Startup & background launchers | No (tells you where to disable) |
| 3 | Biggest space hogs (folders & files) | No (report + opens Finder) |
| 4 | Duplicate file finder | No (report only) |
| 5 | Junk scan (caches, logs, trash sizes) | No |
| 6 | Clean junk | Moves junk to a **recoverable Trash quarantine** |
| 7 | Empty Trash | **Permanent** — asks you to type `yes` |
| 8 | App leftovers to review | No (report + opens Finder) |
| 9 | Serato & gaming tune-up tips | No |
| 10 | What's eating my Mac right now | No |

## Safety guarantees

- **Nothing is deleted without you typing `yes`.**
- **Cleanup is reversible.** Option 6 *moves* junk into a quarantine folder
  inside your Trash. You can drag anything back out. Disk space is reclaimed
  only when you choose to empty the Trash (option 7).
- It only ever touches well-known **regenerated junk** — caches, logs, saved
  app state, trash. It never touches your documents, photos, music, or app
  data, and never touches system files.
- Duplicate and large-file tools **only report** and open Finder. You decide.

## Biggest free wins on this Mac

1. **Restart regularly.** Limited RAM + long uptime = slowdowns.
2. **Quit apps you aren't using** — especially browsers with many tabs and
   Electron apps. See option 10.
3. **Trim login items** (option 2).
4. **For Serato:** plug in power, disable Low Power Mode, quit everything else.
   See option 9.
