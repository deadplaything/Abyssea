Abyssea Tracker - CatsEyeXI Edition
Version 1.5.1 Release
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
Copy the 'abyssea' folder into:
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
- Removed the developer-only KI diagnostic command.
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
