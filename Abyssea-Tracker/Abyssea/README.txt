Abyssea Tracker - CatsEyeXI Edition
Version 1.7.3 Release
by IntegReady

PURPOSE
-------
A CatsEyeXI-focused Ashita v4 addon for Abyssea progression and farming.

FEATURES
--------
- Nine Abyssea field zones
- Alphabetical NM browser
- Physical pop-item ownership and storage-location display
- Key-item progression tracking
- CatsEyeXI-specific NM drop information where imported
- Red, Blue and Yellow proc reference/checklists
- Draggable standalone proc tracker
- Searchable Abyssite and Atma collections
- Draggable Visitant time / Abyssea light status bar
- Distinct acquisition sounds
- Full and Compact modes

INSTALL
-------
Copy the 'Abyssea' folder into:
Ashita/addons/

Load:
  /addon load abyssea

MAIN COMMANDS
-------------
/aby
/aby show
/aby hide
/aby refresh
/aby mode full
/aby mode compact
/aby sound on
/aby sound off
/aby bar
/aby bar on
/aby bar off

PINNED NM TRACKER
-----------------
/aby track <NM name>
/aby untrack <NM name>
/aby tracker
/aby tracker on
/aby tracker off
/aby tracker clear

PROC TRACKER
------------
/aby proctracker
/aby proctracker on
/aby proctracker off
/aby proctracker red on|off
/aby proctracker blue on|off
/aby proctracker yellow on|off
/aby proctracker clear


KEY ITEM CACHE POLICY
---------------------
- Atmas and Abyssites may restore owned state from the saved cache.
- Consumable NM pop key items never restore as confirmed OWNED from cache.
- On addon load, an unconfirmed pop KI is shown as UNVERIFIED and does not
  make an NM appear ready.
- A fresh 0x055 Key Item Log page confirms current owned / missing state.
- Live key-item obtain and loss messages update pop KIs immediately while the
  addon is running.

SERVER / NETWORK BEHAVIOR
-------------------------
The addon is passive and event-driven.

It does not inject outgoing game packets.
It does not poll the CatsEyeXI server.
It does not make web requests while running.

It reacts to normal incoming packets already received by the FFXI client and
reads local Ashita client memory for inventory / ownership information.

Observed incoming packet families:
- 0x00A: zone-in handling
- 0x01E / 0x01F / 0x020: inventory changes
- 0x02A: Abyssea light / Visitant messages
- 0x055: Key Item Log state

Inventory packet bursts are debounced before a local inventory scan.
Static pop-item and key-item watch lists are cached at runtime.

This describes the addon code path only. It does not claim to measure
CatsEyeXI server CPU usage from the client side.

RELEASE 1.5.1
-----------------------
- Cached static watched item / key-item tables.
- Increased inventory-event debounce to reduce repeated local scans.
- Added network behavior information to Settings.
- Replaced the old development README with release documentation.
- Preserved the v1.4.3 clean Atma layout and compact CatsEyeXI banner.

PRE-RELEASE TEST CHECKLIST
--------------------------
1. Load addon and open every main tab.
2. Browse NMs in all nine zones.
3. Run /aby refresh.
4. Test all sound buttons.
5. Enter Abyssea and verify the status bar appears.
6. /heal once and compare displayed lights with the game messages.
7. Move or obtain a tracked pop item and verify ownership.
8. Verify a KI/Abyssite/Atma acquisition alert if practical.
9. Test the pinned NM tracker.
10. Test Red/Blue/Yellow Proc Tracker.
11. Zone out and confirm the status bar disappears.

Author: IntegReady

- Proc header spacing corrected to prevent Current Day overlap.
- UI label changed from Vana'diel Time to CatsEye Time.


v1.6.0 refresh behavior:
- Key items, Atmas and Abyssites are re-read from Ashita local memory every 5 seconds.
- /aby refresh and the REFRESH button force the same live-memory refresh immediately.
- No server packets or requests are sent by this refresh.


v1.6.2 instant KI sync:
- Some private servers do not send a fresh 0x055 Key Item Log until zoning.
- The addon now watches the client's own Obtained/Lost key item system messages.
- Matching NM key items, Abyssites and Atmas update immediately through a temporary local override.
- The next authoritative 0x055 page confirms and replaces the temporary override.
- The REFRESH button remains a local rescan; it does not inject or request server packets.


v1.6.8 - CatsEye KI stable ownership build
- Restores 0x055 packet ownership as authoritative after CatsEye packet diagnostics confirmed Type maps to 512-KI ID pages.
- Uses saved authoritative packet ownership on addon reload, so an addon reload does not require another zone after a page has been captured.
- Keeps live obtain/loss overrides above packet/cache state.
- Keeps Ashita HasKeyItem as a fallback only, because CatsEye returned false for known-owned Abyssea KIs in testing.


v1.6.8: Clean stable CatsEye KI build. Correct 0x055 ownership, reload persistence, and live KI updates retained; developer diagnostics removed.


v1.7.2
- Blue Proc lists now show Piercing, Slashing, and Blunt at the same time.
- The active CatsEye Time window is shown at full brightness and marked CURRENT.
- The two inactive Blue windows remain visible at reduced brightness.
- Standalone Proc Tracker uses the same all-window Blue layout.
