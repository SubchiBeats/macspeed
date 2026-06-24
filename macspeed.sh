#!/bin/bash
#
# MacSpeed — a safe, friendly performance scanner & cleaner for macOS
# Built for a 2-core / 8GB Intel MacBook Pro, but works on any Mac.
#
# SAFETY PHILOSOPHY:
#   * Scans and REPORTS by default. Nothing is deleted without you typing "yes".
#   * Cleanup MOVES files to a recoverable quarantine inside the Trash —
#     it does NOT permanently erase them. You empty the Trash yourself when ready.
#   * It only ever touches well-known, regenerated junk (caches, logs, trash).
#     It never touches system files, your documents, photos, or app data.
#   * Duplicate & large-file tools only REPORT and open Finder. You decide.
#
# Run it:  bash ~/Desktop/macspeed/macspeed.sh
#   or double-click MacSpeed.command in Finder.

set -u

# ---------- pretty output ----------
BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; BLU=$'\033[34m'; CYN=$'\033[36m'

hr()    { printf '%s\n' "────────────────────────────────────────────────────────"; }
title() { printf '\n%s%s%s\n' "$BOLD$CYN" "$1" "$RESET"; hr; }
ok()    { printf '%s✓%s %s\n' "$GRN" "$RESET" "$1"; }
warn()  { printf '%s!%s %s\n' "$YEL" "$RESET" "$1"; }
info()  { printf '%s•%s %s\n' "$BLU" "$RESET" "$1"; }

# human-readable size of a path. Returns "0B" if missing, "n/a*" if macOS
# blocks Terminal from reading it (e.g. ~/.Trash without Full Disk Access).
dirsize() {
  [ -e "$1" ] || { echo "0B"; return; }
  local out; out=$(du -sh "$1" 2>/dev/null | awk '{print $1}')
  [ -n "$out" ] && echo "$out" || echo "n/a*"
}

pause() { printf '\n%sPress Return to go back to the menu…%s' "$DIM" "$RESET"; read -r _; }

confirm() {
  # $1 = prompt. Returns 0 only if user types exactly: yes
  printf '%s%s%s ' "$YEL" "$1 (type 'yes' to confirm): " "$RESET"
  read -r ans
  [ "$ans" = "yes" ]
}

# Set when a cleanup run starts (see junk_clean).
QUARANTINE=""

# Move a path into the recoverable quarantine folder. Uses plain mv, which works
# on user caches/logs without special permissions (macOS blocks the ~/.Trash and
# Finder-automation routes from Terminal). $1 = path, $2 = label
quarantine() {
  local src="$1" label="$2"
  [ -e "$src" ] || return 0
  local dest="$QUARANTINE/$(basename "$src")"
  [ -e "$dest" ] && dest="$dest-$RANDOM"
  if mv "$src" "$dest" 2>/dev/null; then
    ok "Quarantined: $label  ($(basename "$src"))"
  else
    warn "Skipped (in use or protected): $label  ($(basename "$src"))"
  fi
}

# =====================================================================
# 1. SYSTEM OVERVIEW
# =====================================================================
overview() {
  title "1 · System Overview"
  local model cores ram macos
  model=$(sysctl -n hw.model 2>/dev/null)
  cores=$(sysctl -n hw.physicalcpu 2>/dev/null)
  ram=$(( $(sysctl -n hw.memsize 2>/dev/null) / 1073741824 ))
  macos=$(sw_vers -productVersion 2>/dev/null)
  info "Model:    $model  ($cores cores, ${ram}GB RAM)"
  info "macOS:    $macos"

  # disk
  local line; line=$(df -h /System/Volumes/Data 2>/dev/null | tail -1)
  info "Disk:     $(echo "$line" | awk '{print $4" free of "$2" ("$5" used)"}')"

  # uptime / load
  local up load
  up=$(uptime | sed -E 's/.*up ([^,]*(,[^,]*day[^,]*)?),.*users.*/\1/' )
  load=$(uptime | awk -F'load averages:' '{print $2}' | xargs)
  info "Uptime:   $(uptime | sed -E 's/^.*up //; s/, [0-9]+ user.*//')"
  info "Load avg: $load   ${DIM}(numbers above your core count = CPU is overloaded)${RESET}"

  # swap
  local swap; swap=$(sysctl -n vm.swapusage 2>/dev/null | sed -E 's/total = //; s/  used.*used = / | in use: /; s/  free.*//')
  info "Swap:     $swap   ${DIM}(heavy swap use = you're out of RAM)${RESET}"

  echo
  # smart nudges
  local up_days; up_days=$(uptime | grep -oE '[0-9]+ days?' | grep -oE '[0-9]+' | head -1)
  if [ -n "${up_days:-}" ] && [ "$up_days" -ge 3 ]; then
    warn "You haven't restarted in $up_days days. A simple restart is the single"
    warn "  biggest free speedup on a machine with limited RAM. Save your work & reboot."
  fi
  local load1; load1=$(uptime | awk -F'load averages:' '{print $2}' | awk '{print $1}')
  if [ -n "${load1:-}" ] && [ "${load1%.*}" -ge "$cores" ] 2>/dev/null; then
    warn "Current load ($load1) exceeds your $cores cores — something is pinning the CPU."
    warn "  Use option 8 to see what, and quit heavy apps you're not using."
  fi
  pause
}

# =====================================================================
# 2. LOGIN ITEMS & BACKGROUND LAUNCHERS  (what starts at boot)
# =====================================================================
startup_items() {
  title "2 · Startup & Background Launchers"
  info "These start automatically and run in the background, eating CPU/RAM."
  echo

  printf '%sLogin Items (System Settings ▸ General ▸ Login Items):%s\n' "$BOLD" "$RESET"
  osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null \
    | tr ',' '\n' | sed 's/^ */   • /' | grep -v '^   • $' || echo "   (none or not accessible)"

  echo
  printf '%sUser LaunchAgents (auto-start helpers in your account):%s\n' "$BOLD" "$RESET"
  if [ -d "$HOME/Library/LaunchAgents" ]; then
    ls -1 "$HOME/Library/LaunchAgents"/*.plist 2>/dev/null \
      | sed 's#.*/##; s/\.plist$//; s/^/   • /' || echo "   (none)"
  else
    echo "   (none)"
  fi

  echo
  printf '%sThird-party global agents/daemons (apps that run for all users):%s\n' "$BOLD" "$RESET"
  {
    ls -1 /Library/LaunchAgents/*.plist 2>/dev/null
    ls -1 /Library/LaunchDaemons/*.plist 2>/dev/null
  } | grep -vi 'apple' | sed 's#.*/##; s/\.plist$//; s/^/   • /' | sort -u \
    || echo "   (none)"

  echo
  info "To disable a Login Item: System Settings ▸ General ▸ Login Items ▸ select ▸ (–)."
  info "LaunchAgents are safe to disable per-app (e.g. Adobe, Google updaters, Dropbox)."
  warn "Don't delete anything with 'apple' in the name."
  pause
}

# =====================================================================
# 3. WHERE IS MY SPACE GOING  (biggest folders + files)
# =====================================================================
big_stuff() {
  title "3 · Biggest Space Hogs"
  info "Scanning your home folder… (this can take a minute on a spinning disk)"
  echo
  printf '%sTop 15 largest folders in your account:%s\n' "$BOLD" "$RESET"
  du -h -d 2 "$HOME" 2>/dev/null | sort -hr | head -15 | sed 's/^/   /'

  echo
  printf '%sTop 15 largest individual files (over 200MB):%s\n' "$BOLD" "$RESET"
  find "$HOME" -type f -size +200M 2>/dev/null \
    | xargs -I{} du -h "{}" 2>/dev/null | sort -hr | head -15 | sed 's/^/   /' \
    || echo "   (none found)"

  echo
  info "Common big offenders: old iPhone backups (~/Library/Application Support/MobileSync),"
  info "  Downloads, Mail downloads, video projects, leftover .dmg installers."
  printf '\n%sOpen Downloads in Finder to triage? %s' "$YEL" "$RESET"
  read -r yn; [ "$yn" = "y" ] && open "$HOME/Downloads"
  pause
}

# =====================================================================
# 4. DUPLICATE FINDER  (report only)
# =====================================================================
duplicates() {
  title "4 · Duplicate File Finder (report only — deletes nothing)"
  printf 'Which folder to scan? [default: %s/Downloads]: ' "$HOME"
  read -r target
  target="${target:-$HOME/Downloads}"
  [ -d "$target" ] || { warn "Not a folder: $target"; pause; return; }

  info "Scanning $target for duplicates by content (size + checksum)…"
  info "This compares files >1MB. Larger folders take longer."
  echo

  # group by size first (fast), then md5 within same-size groups (accurate)
  find "$target" -type f -size +1M 2>/dev/null -print0 \
   | xargs -0 stat -f '%z %N' 2>/dev/null \
   | sort -n \
   | awk '{size=$1; $1=""; sub(/^ /,""); a[size]=a[size]"\n"$0} END{for(s in a){n=gsub(/\n/,"\n",a[s]); if(n>1) print a[s]}}' \
   | while IFS= read -r f; do [ -f "$f" ] && md5 -q "$f" 2>/dev/null | tr -d '\n'; [ -f "$f" ] && echo "  $f"; done \
   | sort \
   | awk 'NF>=2{h=$1; $1=""; if(h==prev){if(!shown){print "\n"BOLD prevline RESET; shown=1} print "   ↳"$0} else {shown=0}; prev=h; prevline=$0}' \
   | sed "s/$/$RESET/" 2>/dev/null

  echo
  warn "Review duplicates yourself before deleting. Keep one copy of each."
  printf '%sOpen this folder in Finder? %s' "$YEL" "$RESET"
  read -r yn; [ "$yn" = "y" ] && open "$target"
  pause
}

# =====================================================================
# 5. JUNK SCAN + CLEAN  (caches, logs, trash) — reversible
# =====================================================================
junk_report() {
  title "5 · Junk Scan (caches, logs, trash)"
  info "Sizes of safe-to-clear junk. These regenerate automatically — clearing"
  info "them is safe; they just take a moment to rebuild the first time."
  echo
  printf '   %-34s %s\n' "User caches"            "$(dirsize "$HOME/Library/Caches")"
  printf '   %-34s %s\n' "User logs"              "$(dirsize "$HOME/Library/Logs")"
  printf '   %-34s %s\n' "Saved app states"       "$(dirsize "$HOME/Library/Saved Application State")"
  printf '   %-34s %s\n' "Chrome cache"           "$(dirsize "$HOME/Library/Caches/Google/Chrome")"
  printf '   %-34s %s\n' "Trash"                  "$(dirsize "$HOME/.Trash")"
  echo
  printf '%s   n/a* = macOS blocks Terminal from reading it. To see the size, grant\n' "$DIM"
  printf '          Terminal Full Disk Access in System Settings ▸ Privacy & Security.%s\n' "$RESET"
  echo
}

junk_clean() {
  junk_report
  QUARANTINE="$HOME/MacSpeed-Quarantine-$(date +%Y%m%d-%H%M%S)"
  warn "Cleanup MOVES this junk into a recoverable folder (nothing is erased):"
  warn "  $QUARANTINE"
  warn "Restore anything by dragging it back. When you're happy everything still"
  warn "  works, delete that folder to reclaim the disk space."
  echo
  if confirm "Clean caches, logs & saved states now?"; then
    echo
    mkdir -p "$QUARANTINE"
    # move CONTENTS, not the parent dirs themselves
    for d in "$HOME/Library/Caches"/* "$HOME/Library/Logs"/* "$HOME/Library/Saved Application State"/*; do
      [ -e "$d" ] && quarantine "$d" "junk"
    done
    echo
    local freed; freed=$(dirsize "$QUARANTINE")
    ok "Done. $freed of junk is now in:"
    ok "  $QUARANTINE"
    info "Use your apps for a bit; if all is well, drag that folder to the Trash."
  else
    info "Skipped. Nothing changed."
  fi
  pause
}

empty_trash() {
  title "Empty Trash"
  info "Trash currently holds: $(dirsize "$HOME/.Trash")"
  warn "Emptying the Trash is PERMANENT and cannot be undone."
  echo
  if confirm "Permanently empty the Trash?"; then
    osascript -e 'tell application "Finder" to empty the trash' 2>/dev/null \
      && ok "Trash emptied." || warn "Could not empty via Finder."
  else
    info "Skipped."
  fi
  pause
}

# =====================================================================
# 6. APP LEFTOVERS  (orphaned support files from uninstalled apps)
# =====================================================================
app_leftovers() {
  title "6 · App Support Folders (review for uninstalled apps)"
  info "Largest folders in Application Support. If you've deleted an app but"
  info "  its folder is still here, it's safe to remove that app's leftovers."
  echo
  du -h -d 1 "$HOME/Library/Application Support" 2>/dev/null \
    | sort -hr | head -20 | sed 's/^/   /'
  echo
  info "Cross-check against installed apps in /Applications before removing."
  printf '%sOpen Application Support in Finder? %s' "$YEL" "$RESET"
  read -r yn; [ "$yn" = "y" ] && open "$HOME/Library/Application Support"
  pause
}

# =====================================================================
# 7. SERATO / DJ + GAMING TUNE-UP TIPS
# =====================================================================
serato_tips() {
  title "7 · Serato & Gaming Performance Tips (for THIS Mac)"
  cat <<'EOF'
This is a dual-core, 8GB, Intel-integrated-graphics Mac. Honest guidance:

  SERATO DJ PRO  — realistic, this is your best creative use of the machine.
   Serato leans on CPU + disk, not the GPU, so a clean machine matters most:
   1. Before a gig: restart, then open ONLY Serato. Quit Chrome, Claude, etc.
   2. Plug in power — battery mode throttles the CPU (huge for dropouts).
   3. System Settings ▸ Battery ▸ disable "Low Power Mode" while DJing.
   4. Turn OFF Wi-Fi/Bluetooth scanning if not needed (fewer interrupts).
   5. In Serato: raise the audio buffer size (Setup ▸ Audio) to ~512 if you
      hear crackles — trades a little latency for stability on older CPUs.
   6. Keep your library/music on the internal SSD, not a slow USB drive.
   7. Disable Spotlight indexing of your music drive during sets.

  STEAM GAMING  — set expectations: Intel Iris 6100 + 2 cores is entry-level.
   WILL run well (2D / indie / older):
     Stardew Valley · Hollow Knight · Celeste · Dead Cells · Terraria ·
     Into the Breach · Slay the Spire · Undertale · Papers Please ·
     Half-Life 2 / Portal / Portal 2 (older Source engine) · Bastion
   MIGHT run on lowest settings: Don't Starve, Disco Elysium, FTL.
   WILL NOT run acceptably: Baldur's Gate 3, Elden Ring, Cyberpunk, most
     modern 3D AAA — they need a discrete/Apple-Silicon GPU and 16GB+ RAM.

  BALDUR'S GATE 3 specifically: its Mac minimum is roughly an Apple Silicon
   chip or a modern discrete GPU. On Iris 6100 it's below minimum spec and
   would be a slideshow even on low. For that game you'd want a newer Mac
   (any M1+) or a gaming PC — sorry to be blunt, but it'll save you a refund.

  GENERAL SPEEDUPS for an 8GB Intel Mac:
   • Restart regularly (you were at 19 days — that alone helps).
   • Keep Chrome tabs minimal; each tab is its own RAM-hungry process.
   • Reduce login items (menu option 2).
   • System Settings ▸ Accessibility ▸ Display ▸ "Reduce Motion" +
     "Reduce Transparency" — noticeably lighter on the integrated GPU.
EOF
  pause
}

# =====================================================================
# 8. WHAT'S EATING MY MAC RIGHT NOW (live snapshot)
# =====================================================================
live_hogs() {
  title "8 · What's Eating Your Mac Right Now"
  printf '%sTop CPU users:%s\n' "$BOLD" "$RESET"
  ps -Ao %cpu,comm -r 2>/dev/null | head -9 | awk 'NR==1{print "   "$0; next}{c=$1;$1="";print "   "c"%\t"$0}'
  echo
  printf '%sTop memory users:%s\n' "$BOLD" "$RESET"
  ps -Ao rss,comm -m 2>/dev/null | head -9 \
    | awk 'NR==1{print "   MB\tCOMMAND"; next}{mb=int($1/1024);$1="";print "   "mb"\t"$0}'
  echo
  info "Quit apps you're not actively using (⌘Q) — especially browsers with"
  info "  many tabs and Electron apps (Claude, Slack, Discord, VS Code)."
  pause
}

# =====================================================================
# MAIN MENU
# =====================================================================
menu() {
  clear
  printf '%s\n' "$BOLD$CYN"
  cat <<'EOF'
   __  __            ____                      _
  |  \/  | __ _  ___/ ___| _ __   ___  ___  __| |
  | |\/| |/ _` |/ __\___ \| '_ \ / _ \/ _ \/ _` |
  | |  | | (_| | (__ ___) | |_) |  __/  __/ (_| |
  |_|  |_|\__,_|\___|____/| .__/ \___|\___|\__,_|
                          |_|
EOF
  printf '%s' "$RESET"
  printf '   %sSafe Mac performance scanner & cleaner%s\n' "$DIM" "$RESET"
  hr
  echo "  1)  System overview (specs, disk, RAM, load)"
  echo "  2)  Startup & background launchers"
  echo "  3)  Biggest space hogs (folders & files)"
  echo "  4)  Find duplicate files (report only)"
  echo "  5)  Scan junk (caches, logs, trash)"
  echo "  6)  Clean junk  →  recoverable quarantine"
  echo "  7)  Empty Trash (permanent)"
  echo "  8)  App leftovers to review"
  echo "  9)  Serato & gaming tune-up tips"
  echo " 10)  What's eating my Mac right now"
  hr
  echo "  q)  Quit"
  printf '\n%sChoose an option: %s' "$BOLD" "$RESET"
}

main() {
  while true; do
    menu
    read -r choice
    case "$choice" in
      1) overview ;;
      2) startup_items ;;
      3) big_stuff ;;
      4) duplicates ;;
      5) junk_report; pause ;;
      6) junk_clean ;;
      7) empty_trash ;;
      8) app_leftovers ;;
      9) serato_tips ;;
      10) live_hogs ;;
      q|Q) clear; printf '%sStay fast. 👋%s\n' "$GRN" "$RESET"; exit 0 ;;
      *) ;;
    esac
  done
}

main
