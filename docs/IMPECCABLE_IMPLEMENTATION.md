# DEX//PROMPTENDER - Impeccable UI/UX Implementation

Baseline: GitHub main at 97d0c3569139ab46f99cf68054270688178adb87.
Date: 2026-11-14. Platform: native macOS SwiftUI/AppKit. Mode: Operate.

This is the bounded implementation of all 15 IDs from the Impeccable gauntlet. The existing PROMPTENDER visual voice, offline compiler, explicit Serve authorization, Keychain, wildcard safety, and isolated DexCraft importer remain authoritative.

## Quick Wins

- QW-01: TransparentTextEditor.swift uses adaptive text/caret colors and an explicit VoiceOver label/help.
- QW-02: RootPopoverView, MixingRoomView and AppDelegate honor system Reduce Motion for drawer/popover transitions.
- QW-03: MixingRoomView expands multiline status text; wildcard operations have recoverable detail receipts.
- QW-04: MixingRoomView adds VoiceOver names and enlarged targets to the icon-only window/drawer buttons.
- QW-05: HouseSpecialsAndSettingsView names provider-specific key actions, styles removal as destructive, reflows the controls, and adds larger hit targets.

## High-Impact Polish

- HP-01: MixingRoomView uses a compact native section menu while keeping visible section tabs in the wide detached window.
- HP-02: FlightComparisonView exposes full prompt text in DisclosureGroup and accessible target-selection states.
- HP-03: ServeConfirmationSheet wraps endpoint/identity values and blocks stale-draft execution.
- HP-04: WildcardsStudioView exposes incomplete remote bank fetches as inline retryable errors and disables unsafe save/sync.
- HP-05: WildcardsStudioView and HouseSpecialsAndSettingsView give major editing and settings actions 44pt minimum heights; secondary bank actions use a menu.
- HP-06: AppearanceSettingsStore debounces disk writes, offers explicit termination flush and caches NSImage by path/mtime.

## Structural UX Upgrades

- ST-01: PromptenderCoordinator, MixingRoomView and ServeConfirmationSheet compare a compile snapshot (draft, target/recipe, mode, intent, assets, locks, parameters, variables, enhancement choices, wildcard state) before Copy or Serve, and recheck before network submit.
- ST-02: AppDelegate, RootPopoverView and MixingRoomView constrain window geometry to screen visible bounds and use a one-panel layout at narrow widths.
- ST-03: PromptenderDesignSystem.swift holds native semantic design tokens and glass modifiers, removed from PrimaryPanelView.swift; redundant Cellar wrapping is reduced.
- ST-04: PromptenderCoordinator, WildcardStore and WildcardsStudioView expose a persistent outcome receipt with complete/failed destination steps, recovery copy, and Reveal Backups in Finder.

## Evidence and limitations

- Native SwiftPM debug build passed on Big Mac.
- 36/36 automated tests across seven suites passed. New tests cover fresh/stale output behavior, Serve refusal after edits, wildcard bank revisions and failure receipts.
- The Impeccable web HTML/CSS detector does not apply to native SwiftUI. Native offscreen SwiftUI render probes passed at 480x660, 720x560, and 960x660, plus standalone Wildcards, Settings, and Serve content views. Images were visually inspected against the app's established dark-shell treatment. Live pointer/keyboard, VoiceOver, macOS Increased Contrast, arbitrary user-image contrast, and MacBook installation remain unverified.
- Automated validation used mock transport; no live DexDiffusion PUT/DELETE, paid cloud requests, or private legacy data modifications.
- The MacBook installed app is unchanged. Big Mac source/build artifacts are a staging result, not notarized deployment.
