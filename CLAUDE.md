# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

KeepToss is a keyboard-driven audio sample preview and sorting tool built with Delphi. It uses the Free Vision (FV) text-mode UI framework for its console-based interface.

## Build Commands

Build the project using MSBuild with RAD Studio:
```
msbuild Source/KeepToss.dproj /p:Config=Debug /p:Platform=Win32
```

Or use the MCP build tool:
```
mcp__dbuildmcp__msbuild with projectfile="C:/projects/KeepToss/Source/KeepToss.dproj"
```

Output location: `Source\Win32\Debug\KeepToss.exe`

## Architecture

### Application Structure
- **Source/KeepToss.dpr** - Main program entry point, creates TMyApp (inherits from TApplication)
- **Libraries/fv-delphi/** - Free Vision TUI framework (console GUI toolkit)

### Free Vision Framework
The application uses legacy Turbo Pascal `OBJECT` syntax (not `CLASS`). Key units from fv-delphi:

- `App.pas` - Application framework (TApplication base class)
- `Views.pas` - View hierarchy (TView, TGroup, TWindow)
- `Dialogs.pas` - Dialog controls (TDialog, TButton, TInputLine)
- `Menus.pas` - Menu system (TMenuBar, TStatusLine)
- `Drivers.pas` - Keyboard/mouse input handling
- `Video.pas` - Windows Console API output

### Key Conventions
- Uses `ShortString` for FV string types (`Sw_String`, `PString`)
- Range checking should be OFF (`{$R-}`) in units with pointer arithmetic
- Windows Console API for display and input
- Primary target: Win32 platform
