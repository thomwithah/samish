SAMISH (Streaming Audio Mixer Interface Sleep Helper)
Created by thomwithah
Version: 1.3.5

A lightweight helper that helps restore normal Windows sleep behavior for streaming audio hardware.

How to Run / Install

- Run Setup.bat or Use Setup.exe, or run Setup.ps1 as Administrator with all the "Included Folders and Files" from below in the same folder. 
- Alternatively, you can use the SAMISH_Setup_vX.X.X.exe to install. This will extract all the files needed to a folder and launch the SAMISH GUI. 
- Note: Although the .exe installers make installtion easy expect antivirus software to flag them. 

Quick start (for BEACN users):

- Run Setup.bat or Use SAMISH.exe, or run Setup.ps1 as Administrator
- Leave Hidden mode selected
- Click Install / Update
- Accept the Power Plan fix if prompted

That's it. SAMISH will run silently in the background.

For full documentation, see README.md

Uninstall:
- Run Uninstall-SAMISH.bat


## Sleep & Hibernate Diagnostics Tool ##

**What it does** 
    - Scans running processes, services, and drivers to identify exactly which application or component is preventing Windows from entering sleep or hibernate. 
    - It reports the offending process name, PID, and the type of power-request (e.g., `SYSTEM`, `AWAYMODE`, `DISPLAY`).

**Why it matters** 
    - Audio-mixing programs such as **Wave Control**, **Elgato Wave Link**, **GoXLR**, **Voicemeeter** and media players like **Spotify**, **iTunes**, **Foobar2000**, **VLC** often hold a wake-lock, keeping the PC awake even after the app is closed. 
    - The diagnostics tool lets you pinpoint those culprits so you can close or re-configure them, adjust the power plan, or let SAMISH's device-adapter help clear the lock.

**Limitations** 
    - Relies on Windows power-reporting APIs; low-level driver bugs that do not expose a wake source may be missed.
**Roadmap** 
    - SAMISH is designed to be fully extensible. Developers can easily write custom adapters using the template structure provided by the mock Demo-Only adapter and drop new .json configurations into the Profiles/ folder.

For commercial licensing inquiries:
https://forms.gle/BYfxQqKgUpYfiyUo8

Fallback:
fakerjs+license@gmail.com


## Included files ##

Keep these files and folders together in the same directory:
- App/ (Background engine, modules, adapters, profiles, and assets)
- Install-SAMISH-Hidden.bat
- Install-SAMISH-Interactive.bat
- Uninstall-SAMISH.bat
- Launch-ColorThemeConfigurator.bat
- Setup.bat
- Setup.ps1
- Setup.exe
- README.txt
- README.md
- USER_GUIDE.md
- ARCHITECTURE.md
- CHANGELOG.md
- README_Config.md
- LICENSE
- COMMERCIAL-LICENSE.md
