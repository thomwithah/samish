# SAMISH (Streaming Audio Mixer Interface Sleep Helper)

Created by thomwithah

A lightweight helper that restores normal Windows sleep behavior for streaming audio hardware.

Version: 1.0.7

---

## How to Run / Install

- Run Setup.bat or Use SAMISH.exe, or run Setup.ps1 as Administrator with all the "Included Folders and Files" from below in the same folder.


## TL;DR (for BEACN users)

If BEACN is preventing your PC from sleeping properly or behaving incorrectly after sleep, run SAMISH in Hidden mode and click Install.

SAMISH will:
- Ensure your system can sleep correctly
- Reduce common sleep-related issues caused by audio interface software
- Keep your setup stable without needing ongoing interaction
- Help reduce cases where BEACN fails to recover after sleep

Most users never need to open it again after setup.

---

## Why SAMISH exists

I ran into issues where BEACN was preventing my PC from sleeping properly and sometimes didn’t behave correctly after sleep.

I also saw other users reporting similar problems, especially cases where BEACN didn’t recover cleanly after sleep or hibernation.

I built this, a small tool called SAMISH, to stabilize how Windows handles sleep around audio devices.

If you just want the simple fix:
- Run SAMISH
- Leave it on Hidden mode
- Click Install / Update
- Accept the power plan fix if prompted

That’s it.

It runs silently in the background and keeps things working.

It doesn’t modify BEACN directly, but it removes the conditions that typically cause these problems and helps prevent the “doesn’t come back after sleep” issue.

---

## Overview

Some streaming audio device software can unintentionally interfere with normal Windows power behavior.

SAMISH helps restore normal sleep behavior by coordinating how Windows transitions into and out of idle states.

SAMISH is currently tested and confirmed working with BEACN software. Support for additional audio interfaces and their software will be expanded in future releases.

If you are using BEACN and experiencing sleep-related issues, SAMISH provides a simple fix.

---

## What it does

- Reduce common sleep-related issues caused by audio interface software
- Help reduce cases where BEACN or other audio interfaces fails to recover after sleep
- Helps ensure a stable runtime environment so audio software behaves more consistently when returning from sleep
- Runs via Windows Task Scheduler so it operates silently in the background

---

## Included files

Keep these files and folders together in the same directory:
- Assets/
- GUIstuff/
- Modules/
- Profiles/
- Workspace/
- Install-SAMISH-Hidden.bat
- Install-SAMISH-Interactive.bat
- Uninstall-SAMISH.bat
- Setup.bat
- Setup.ps1
- SAMISH.ps1
- SAMISH-HiddenTask.xml
- SAMISH-InteractiveTask.xml
- README.txt
- README.md
- SAMISH.exe (compiled version of SAMISH.ps1; requires same folder structure with Assets/, Modules/, Profiles/ etc.)
- LICENSE
- COMMERCIAL-LICENSE.md

---

## Quick Start

### Option A: Setup UI
1. Run `Setup.bat` or  Use `SAMISH.exe`, or run `Setup.ps1` in PowerShell as Administrator
2. Choose Hidden or Interactive mode
3. Click Install / Update
4. If prompted, allow the Power Plan adjustment (recommended)

### Option B: No UI
Choose one:
- Hidden mode: run `Install-SAMISH-Hidden.bat`
- Interactive mode: run `Install-SAMISH-Interactive.bat`

---

## Modes

### Hidden mode (recommended)
- Runs silently in the background
- Best for "set it and forget it" use

### Interactive mode
- Supports optional tray icon features (if enabled in Setup)
- Useful when you want quick visual confirmation and control

---

## After install

The helper will run automatically at your next login.

---

## Uninstall

- Run `Uninstall-SAMISH.bat`, or use the Uninstall option in the GUI.

---

## License summary (important)

SAMISH is source-available under a fair-code style license.

You may use, modify, and share SAMISH for personal use, noncommercial use, and internal use for qualifying small organizations.

Commercial use requires a separate license.

See LICENSE for full terms.

### Small organization internal use (free)

Internal use is permitted at no cost only if your organization has:
- 10 or fewer total individuals working as employees and contractors, and
- 100,000 USD or less total revenue in the prior tax year

### Commercial use (requires a paid license)

Commercial use includes any use that supports, enables, or is distributed as part of a paid product, service, or system.

This includes software that supports hardware or devices that are sold or leased, even if the software itself is distributed at no charge.

### Free redistribution (allowed)

You may redistribute SAMISH for free (friend-to-friend, GitHub releases, or free download hosting) as long as:
- you do not charge money for it, and
- you do not bundle it inside any paid product or paid software offering

---

## Commercial licensing contact

https://forms.gle/BYfxQqKgUpYfiyUo8

Fallback:
fakerjs+license@gmail.com

---

## Credits

Created by thomwithah

---

## Roadmap (light touch)

SAMISH is designed to become device-agnostic over time.

Support currently exists for BEACN software, with additional audio interface ecosystems planned for future releases.

---
## Sleep & Hibernate Diagnostics Tool

**What it does** – Scans running processes, services, and drivers to pinpoint the exact application or component that blocks Windows from entering sleep or hibernate. It reports the offending process name, PID, and the power‑request type (e.g., `SYSTEM`, `AWAYMODE`, `DISPLAY`).

**Why it matters** – Streaming‑audio tools such as **Wave Control**, **Elgato Wave Link**, **GoXLR**, **Voicemeeter**, and media players like **Spotify**, **iTunes**, **Foobar2000**, **VLC** can hold a wake‑lock, keeping the PC awake even after the app is closed. This tool helps you identify those culprits so you can close, re‑configure, or let SAMISH’s adapter automatically clear the lock.

**Limitations** – Relies on Windows power‑reporting APIs; low‑level driver bugs that do not expose a wake source may be missed.

**Future roadmap** – Planned adapters for Elgato, GoXLR, and other popular mixers will integrate directly with this diagnostics engine. The **Demo‑Only** adapter demonstrates how developers can add new device adapters with minimal code.
---
