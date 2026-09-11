require('common');

local imgui = require('imgui');
local d3d = require('d3d8');
local ffi = require('ffi');
local bit = require('bit');
local settings = require('settings');
local data = require('data.abyssea_data');
local catseye_drops = require('data.catseye_drops');
local C = ffi.C;
local d3d8dev = d3d.get_device();

addon.name      = 'abyssea';
addon.author    = 'IntegReady';
addon.version = '1.5.8';
addon.desc      = 'CatsEyeXI Abyssea progression companion with NM, proc, light, time, key-item and pop-item tracking.';
addon.link      = '';


local persisted = settings.load(T{
    version = 1,
    characters = {},
    statusbar_enabled = true,
});

local function get_character_key()
    local ok, name = pcall(function()
        local party = AshitaCore:GetMemoryManager():GetParty();
        if party ~= nil then return party:GetMemberName(0); end
        return nil;
    end);
    if ok and name ~= nil and #tostring(name) > 0 then
        return tostring(name):lower();
    end
    return 'default';
end

local function get_persisted_keyitems()
    local key = get_character_key();
    persisted.characters[key] = persisted.characters[key] or { keyitems = {} };
    persisted.characters[key].keyitems = persisted.characters[key].keyitems or {};
    return persisted.characters[key].keyitems;
end

local function save_persisted_keyitems()
    pcall(function() settings.save(); end);
end

local state = {
    open = { true },
    selected_zone = 1,
    selected_nm = {},
    keyitem_ids = {},
    keyitem_names = {},
    item_ids = {},
    item_owned = {},
    lookup_ready = false,
    last_item_scan = 0,
    monitor_ready = false,
    keyitem_snapshot = {},
    item_snapshot = {},
    item_event_generation = 0,
    keyitem_event_generation = 0,
    packet_keyitems = {},
    packet_keyitem_pages = {},
    zoning = false,
    zone_sync_generation = 0,
    zone_alert_mute_until = 0,
    sounds_enabled = { true },
    sound_item = { true },
    sound_keyitem = { true },
    sound_abyssite = { true },
    sound_atma = { true },
    compact_mode = { false },
    tracker_open = { true },
    tracked_nms = {},
    abyssite_search = { '' },
    atma_search = { '' },
    proc_red = {},
    proc_blue = {},
    proc_yellow = {},
    proc_tracker_open = { false },
    proc_track_red = { false },
    proc_track_blue = { false },
    proc_track_yellow = { false },
    logo_texture = nil,
    logo_load_attempted = false,
    zone_textures = {},
    zone_texture_missing = {},
    nm_texture = nil,
    nm_texture_key = nil,
    nm_texture_missing = {},

    -- Thin in-zone Abyssea status bar. Values are updated only from the
    -- same incoming 0x02A messages used by retail Abyssea.
    statusbar_open = { persisted.statusbar_enabled ~= false },
    abyssea_zone = false,
    abyssea_zone_id = 0,
    visitant_minutes = nil,
    visitant_anchor = 0,
    lights = { pearlescent = 0, azure = 0, ruby = 0, amber = 0, golden = 0, silvery = 0, ebon = 0 },
};

local colors = {
    title   = { 0.94, 0.78, 0.38, 1.00 },
    header  = { 0.72, 0.86, 1.00, 1.00 },
    owned   = { 0.34, 0.96, 0.42, 1.00 },
    missing = { 1.00, 0.31, 0.31, 1.00 },
    source  = { 0.67, 0.74, 0.84, 1.00 },
    muted   = { 0.51, 0.58, 0.68, 1.00 },
    normal  = { 0.90, 0.93, 0.98, 1.00 },
    crystal = { 0.34, 0.76, 1.00, 1.00 },
    crimson = { 0.82, 0.20, 0.27, 1.00 },
    gold    = { 0.95, 0.72, 0.26, 1.00 },
};

-- Abyssea crystal theme. The layout intentionally stays familiar; this skin
-- replaces the generic ImGui feel with a darker FFXI-style presentation.
local theme = {
    windowBg         = { 0.018, 0.028, 0.045, 0.985 },
    titleBg          = { 0.018, 0.060, 0.095, 0.995 },
    titleBgActive    = { 0.025, 0.095, 0.145, 0.995 },
    border           = { 0.20, 0.55, 0.78, 0.78 },
    childBg          = { 0.025, 0.045, 0.070, 0.955 },
    frameBg          = { 0.030, 0.070, 0.110, 0.96 },
    frameHover       = { 0.050, 0.125, 0.185, 0.98 },
    frameActive      = { 0.060, 0.165, 0.235, 1.00 },
    tab              = { 0.025, 0.055, 0.085, 0.98 },
    tabHovered       = { 0.055, 0.165, 0.240, 0.98 },
    tabActive        = { 0.045, 0.220, 0.330, 1.00 },
    header           = { 0.040, 0.145, 0.210, 0.86 },
    headerHovered    = { 0.060, 0.225, 0.320, 0.92 },
    headerActive     = { 0.075, 0.285, 0.395, 0.98 },
    button           = { 0.030, 0.105, 0.155, 0.98 },
    buttonHovered    = { 0.055, 0.210, 0.300, 1.00 },
    buttonActive     = { 0.075, 0.275, 0.385, 1.00 },
    separator        = { 0.18, 0.45, 0.64, 0.60 },
    scrollbarBg      = { 0.010, 0.025, 0.040, 0.72 },
    scrollbarGrab    = { 0.080, 0.285, 0.420, 0.85 },
    scrollbarHover   = { 0.120, 0.430, 0.610, 0.95 },
    scrollbarActive  = { 0.170, 0.580, 0.790, 1.00 },
    checkmark        = { 0.38, 0.82, 1.00, 1.00 },
    accent           = { 0.38, 0.82, 1.00, 1.00 },
};



-- CatsEyeXI drop display. Intentionally text-only and render-safe.
-- No additional D3D textures are created here.
local function get_catseye_nm_drops(zone_index, nm_name)
    local zone = data.zones[zone_index];
    if zone == nil or nm_name == nil then return nil; end
    local zone_table = catseye_drops.zones[zone.short_name or ''];
    if zone_table == nil then return nil; end
    if zone_table[nm_name] ~= nil then return zone_table[nm_name]; end

    local wanted = nm_asset_slug(nm_name);
    for source_name, drops in pairs(zone_table) do
        if nm_asset_slug(source_name) == wanted then
            return drops;
        end
    end
    return nil;
end

local function render_catseye_drops(nm, zone_index)
    local drops = get_catseye_nm_drops(zone_index, nm.name);
    if drops == nil then return; end

    imgui.Spacing();
    imgui.TextColored(colors.header, 'CatsEyeXI Drops');
    imgui.Separator();

    if #drops == 0 then
        imgui.TextColored(colors.muted, 'No CatsEyeXI drops listed for this NM.');
        return;
    end

    for _, drop in ipairs(drops) do
        local marker = '';
        local marker_color = colors.muted;
        if drop.proc == 'red' then
            marker = '[R] ';
            marker_color = { 1.00, 0.40, 0.40, 1.00 };
        elseif drop.proc == 'blue' then
            marker = '[B] ';
            marker_color = { 0.42, 0.72, 1.00, 1.00 };
        elseif drop.proc == 'yellow' then
            marker = '[Y] ';
            marker_color = { 1.00, 0.86, 0.34, 1.00 };
        end

        if marker ~= '' then
            imgui.TextColored(marker_color, marker);
            imgui.SameLine();
        end

        local label = drop.name or 'Unknown drop';
        if drop.quantity ~= nil then
            if drop.quantity == 'up to 3' then
                label = label .. ' (up to 3; Yellow proc unlocks 3rd)';
            else
                label = label .. ' (' .. drop.quantity .. ')';
            end
        end
        imgui.TextColored(colors.normal, label);
    end

    local zone = data.zones[zone_index];
    local has_shared = false;
    if zone ~= nil then
        local prefix = (zone.short_name or '') .. ' Materials ';
        for _, drop in ipairs(drops) do
            if drop.name ~= nil and drop.name:sub(1, #prefix) == prefix then
                has_shared = true;
                break;
            end
        end
    end

    if has_shared then
        imgui.Spacing();
        -- Avoid percent symbols in ImGui formatted-text calls; Ashita's wrapper
        -- can treat them as printf format tokens and destabilize the client.
        imgui.TextColored(colors.muted, 'Shared materials: baseline 5 to 10 percent; up to 24 percent with Yellow proc.');
    end
end

local function push_theme()
    imgui.PushStyleColor(ImGuiCol_Text, colors.normal);
    imgui.PushStyleColor(ImGuiCol_WindowBg, theme.windowBg);
    imgui.PushStyleColor(ImGuiCol_TitleBg, theme.titleBg);
    imgui.PushStyleColor(ImGuiCol_TitleBgActive, theme.titleBgActive);
    imgui.PushStyleColor(ImGuiCol_Border, theme.border);
    imgui.PushStyleColor(ImGuiCol_ChildBg, theme.childBg);
    imgui.PushStyleColor(ImGuiCol_FrameBg, theme.frameBg);
    imgui.PushStyleColor(ImGuiCol_FrameBgHovered, theme.frameHover);
    imgui.PushStyleColor(ImGuiCol_FrameBgActive, theme.frameActive);
    imgui.PushStyleColor(ImGuiCol_Tab, theme.tab);
    imgui.PushStyleColor(ImGuiCol_TabHovered, theme.tabHovered);
    imgui.PushStyleColor(ImGuiCol_TabActive, theme.tabActive);
    imgui.PushStyleColor(ImGuiCol_Header, theme.header);
    imgui.PushStyleColor(ImGuiCol_HeaderHovered, theme.headerHovered);
    imgui.PushStyleColor(ImGuiCol_HeaderActive, theme.headerActive);
    imgui.PushStyleColor(ImGuiCol_Button, theme.button);
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, theme.buttonHovered);
    imgui.PushStyleColor(ImGuiCol_ButtonActive, theme.buttonActive);
    imgui.PushStyleColor(ImGuiCol_Separator, theme.separator);
    imgui.PushStyleColor(ImGuiCol_ScrollbarBg, theme.scrollbarBg);
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrab, theme.scrollbarGrab);
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrabHovered, theme.scrollbarHover);
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrabActive, theme.scrollbarActive);
    imgui.PushStyleColor(ImGuiCol_CheckMark, theme.checkmark);
    imgui.PushStyleColor(ImGuiCol_ResizeGrip, { 0.14, 0.42, 0.60, 0.48 });
    imgui.PushStyleColor(ImGuiCol_ResizeGripHovered, { 0.20, 0.66, 0.88, 0.82 });
    imgui.PushStyleColor(ImGuiCol_ResizeGripActive, { 0.28, 0.78, 1.00, 1.00 });

    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, 2);
    imgui.PushStyleVar(ImGuiStyleVar_ChildRounding, 2);
    imgui.PushStyleVar(ImGuiStyleVar_FrameRounding, 2);
    imgui.PushStyleVar(ImGuiStyleVar_ScrollbarRounding, 2);
    imgui.PushStyleVar(ImGuiStyleVar_TabRounding, 2);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 9, 8 });
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, { 7, 4 });
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { 6, 4 });
    imgui.PushStyleVar(ImGuiStyleVar_ScrollbarSize, 10);
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 1);
    imgui.PushStyleVar(ImGuiStyleVar_ChildBorderSize, 1);
    imgui.PushStyleVar(ImGuiStyleVar_FrameBorderSize, 1);
end

local function pop_theme()
    imgui.PopStyleVar(12);
    imgui.PopStyleColor(27);
end

local function load_logo_texture()
    if state.logo_texture ~= nil then return state.logo_texture; end
    if state.logo_load_attempted then return nil; end
    state.logo_load_attempted = true;

    local path = addon.path .. 'assets\\logo_banner.png';
    if not ashita.fs.exists(path) then return nil; end

    local texture_ptr = ffi.new('IDirect3DTexture8*[1]');
    if C.D3DXCreateTextureFromFileA(d3d8dev, path, texture_ptr) ~= C.S_OK then
        return nil;
    end
    state.logo_texture = d3d.gc_safe_release(ffi.cast('IDirect3DTexture8*', texture_ptr[0]));
    return state.logo_texture;
end

local function render_brand_banner()
    local texture = load_logo_texture();
    if texture ~= nil then
        local avail_width = select(1, imgui.GetContentRegionAvail());
        avail_width = tonumber(avail_width) or 1200;

        -- Compact 1400x150 banner. The asset is authored at this same aspect
        -- ratio so it can fill the window without stretching or cropping.
        local width = math.max(600, avail_width);
        local height = width * (150 / 1400);
        imgui.Image(tonumber(ffi.cast('uint32_t', texture)), { width, height });
    else
        imgui.TextColored(colors.crystal, 'ABYSSEA');
        imgui.SameLine();
        imgui.TextColored(colors.normal, 'TRACKER');
        imgui.SameLine();
        imgui.TextColored(colors.muted, 'by IntegReady');
    end

    -- Thin crimson/crystal accent bands give the banner an Abyssea identity
    -- without changing the existing screen layout.
    imgui.PushStyleColor(ImGuiCol_Separator, { 0.58, 0.12, 0.20, 0.78 });
    imgui.Separator();
    imgui.PopStyleColor();
end

local function zone_image_path(zone_index)
    local zone = data.zones[zone_index];
    if zone == nil then return nil; end
    local name = tostring(zone.short_name or zone.name or ''):lower();
    name = name:gsub('[^%w]+', '_');
    name = name:gsub('^_+', ''):gsub('_+$', '');
    return addon.path .. ('assets\\zones\\%s.png'):format(name);
end

local function load_zone_texture(zone_index)
    if state.zone_textures[zone_index] ~= nil then
        return state.zone_textures[zone_index];
    end
    if state.zone_texture_missing[zone_index] then return nil; end

    local path = zone_image_path(zone_index);
    if path == nil or not ashita.fs.exists(path) then
        state.zone_texture_missing[zone_index] = true;
        return nil;
    end

    local texture_ptr = ffi.new('IDirect3DTexture8*[1]');
    if C.D3DXCreateTextureFromFileA(d3d8dev, path, texture_ptr) ~= C.S_OK then
        state.zone_texture_missing[zone_index] = true;
        return nil;
    end

    state.zone_textures[zone_index] = d3d.gc_safe_release(ffi.cast('IDirect3DTexture8*', texture_ptr[0]));
    return state.zone_textures[zone_index];
end

local function render_zone_image_button(zone_index, zone, selected_zone, width, height)
    local texture = load_zone_texture(zone_index);
    local label = (zone.short_name or zone.name) .. '##zone_nav_' .. zone_index;

    if texture == nil then
        -- Safe fallback if an asset is missing.
        return imgui.Button(label, { width, height });
    end

    -- Draw the artwork first, then place a transparent ImGui button over it.
    -- The text is baked into the small local texture, so there are no runtime
    -- font/draw-list dependencies and the whole card remains clickable.
    local x = imgui.GetCursorPosX();
    local y = imgui.GetCursorPosY();

    imgui.Image(tonumber(ffi.cast('uint32_t', texture)), { width, height });

    imgui.SetCursorPosX(x);
    imgui.SetCursorPosY(y);
    imgui.PushStyleColor(ImGuiCol_Button, selected_zone and { 0.05, 0.52, 0.78, 0.18 } or { 0.00, 0.00, 0.00, 0.00 });
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.10, 0.62, 0.88, 0.22 });
    imgui.PushStyleColor(ImGuiCol_ButtonActive, { 0.16, 0.72, 1.00, 0.30 });
    imgui.PushStyleColor(ImGuiCol_Border, selected_zone and { 0.20, 0.78, 1.00, 1.00 } or { 0.10, 0.40, 0.62, 0.82 });
    imgui.PushStyleVar(ImGuiStyleVar_FrameRounding, 3);
    imgui.PushStyleVar(ImGuiStyleVar_FrameBorderSize, selected_zone and 2 or 1);
    local clicked = imgui.Button('##zone_image_button_' .. zone_index, { width, height });
    imgui.PopStyleVar(2);
    imgui.PopStyleColor(4);

    imgui.SetCursorPosX(x);
    imgui.SetCursorPosY(y + height + 4);
    return clicked;
end

ffi.cdef[[
    int __stdcall PlaySoundA(const char* pszSound, void* hmod, unsigned int fdwSound);
]];
local winmm = ffi.load('winmm');
local SND_ASYNC    = 0x0001;
local SND_NODEFAULT= 0x0002;
local SND_FILENAME = 0x00020000;

local SOUND_FILES = {
    item     = 'sounds\\item.wav',
    keyitem  = 'sounds\\keyitem.wav',
    abyssite = 'sounds\\abyssite.wav',
    atma     = 'sounds\\atma.wav',
};

local function play_chime(kind)
    if not state.sounds_enabled[1] then return; end
    if kind == 'item' and not state.sound_item[1] then return; end
    if kind == 'keyitem' and not state.sound_keyitem[1] then return; end
    if kind == 'abyssite' and not state.sound_abyssite[1] then return; end
    if kind == 'atma' and not state.sound_atma[1] then return; end
    local rel = SOUND_FILES[kind];
    if rel == nil then return; end
    local path = addon.path .. rel;
    pcall(function()
        winmm.PlaySoundA(path, nil, SND_ASYNC + SND_NODEFAULT + SND_FILENAME);
    end);
end

local function nm_asset_slug(value)
    value = tostring(value or ''):lower();
    value = value:gsub('[^%w]+', '_');
    value = value:gsub('^_+', ''):gsub('_+$', '');
    return value;
end

local function nm_image_path(zone_index, nm_name)
    local zone = data.zones[zone_index];
    if zone == nil then return nil; end
    local zone_slug = nm_asset_slug(zone.short_name or zone.name);
    local nm_slug = nm_asset_slug(nm_name);
    return addon.path .. ('assets\\nms\\%s\\%s.png'):format(zone_slug, nm_slug);
end

local function release_nm_texture()
    state.nm_texture = nil;
    state.nm_texture_key = nil;
    collectgarbage('collect');
end

local function load_nm_texture(zone_index, nm_name)
    local path = nm_image_path(zone_index, nm_name);
    if path == nil then return nil; end

    local key = tostring(zone_index) .. ':' .. tostring(nm_name);
    if state.nm_texture_key == key then
        return state.nm_texture;
    end

    -- Only keep the currently selected NM texture alive. This prevents the
    -- full NM image library from being loaded into memory at once.
    release_nm_texture();
    state.nm_texture_key = key;

    if state.nm_texture_missing[path] then return nil; end
    if not ashita.fs.exists(path) then
        state.nm_texture_missing[path] = true;
        return nil;
    end

    local texture_ptr = ffi.new('IDirect3DTexture8*[1]');
    if C.D3DXCreateTextureFromFileA(d3d8dev, path, texture_ptr) ~= C.S_OK then
        state.nm_texture_missing[path] = true;
        return nil;
    end

    state.nm_texture = d3d.gc_safe_release(ffi.cast('IDirect3DTexture8*', texture_ptr[0]));
    return state.nm_texture;
end

local function render_nm_artwork(nm, zone_index)
    local texture = load_nm_texture(zone_index, nm.name);
    if texture == nil then return; end

    imgui.Spacing();
    imgui.TextColored(colors.header, 'Monster Profile');
    imgui.Separator();

    local avail_width = select(1, imgui.GetContentRegionAvail());
    avail_width = tonumber(avail_width) or 620;
    local width = math.min(math.max(360, avail_width - 18), 620);
    local height = math.floor(width * 0.56);
    if height > 340 then height = 340; end

    imgui.PushStyleColor(ImGuiCol_Border, { 0.20, 0.60, 0.88, 0.88 });
    imgui.BeginChild('##nm_art_frame_' .. nm_asset_slug(nm.name), { width + 12, height + 12 }, true);
    imgui.Image(tonumber(ffi.cast('uint32_t', texture)), { width, height });
    imgui.EndChild();
    imgui.PopStyleColor();
end

local function push_theme()
    imgui.PushStyleColor(ImGuiCol_WindowBg, theme.windowBg);
    imgui.PushStyleColor(ImGuiCol_TitleBg, theme.titleBg);
    imgui.PushStyleColor(ImGuiCol_TitleBgActive, theme.titleBgActive);
    imgui.PushStyleColor(ImGuiCol_Border, theme.border);
    imgui.PushStyleColor(ImGuiCol_ChildBg, theme.childBg);
    imgui.PushStyleColor(ImGuiCol_FrameBg, theme.frameBg);
    imgui.PushStyleColor(ImGuiCol_FrameBgHovered, theme.frameHover);
    imgui.PushStyleColor(ImGuiCol_Tab, theme.tab);
    imgui.PushStyleColor(ImGuiCol_TabHovered, theme.tabHovered);
    imgui.PushStyleColor(ImGuiCol_TabActive, theme.tabActive);
    imgui.PushStyleColor(ImGuiCol_Header, theme.header);
    imgui.PushStyleColor(ImGuiCol_HeaderHovered, theme.headerHovered);
    imgui.PushStyleColor(ImGuiCol_HeaderActive, theme.headerActive);
    imgui.PushStyleColor(ImGuiCol_ScrollbarBg, theme.scrollbarBg);
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrab, theme.scrollbarGrab);
    imgui.PushStyleColor(ImGuiCol_CheckMark, theme.checkmark);
    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, 7);
    imgui.PushStyleVar(ImGuiStyleVar_ChildRounding, 5);
    imgui.PushStyleVar(ImGuiStyleVar_FrameRounding, 4);
    imgui.PushStyleVar(ImGuiStyleVar_ScrollbarRounding, 5);
    imgui.PushStyleVar(ImGuiStyleVar_TabRounding, 4);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 10, 9 });
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { 5, 4 });
end

local function pop_theme()
    imgui.PopStyleVar(7);
    imgui.PopStyleColor(16);
end

local CONTAINERS = {
    { id = 0,  name = 'Inventory' },  { id = 1,  name = 'Safe' },
    { id = 2,  name = 'Storage' },    { id = 4,  name = 'Locker' },
    { id = 5,  name = 'Satchel' },    { id = 6,  name = 'Sack' },
    { id = 7,  name = 'Case' },       { id = 8,  name = 'Wardrobe' },
    { id = 9,  name = 'Safe 2' },     { id = 10, name = 'Wardrobe 2' },
    { id = 11, name = 'Wardrobe 3' }, { id = 12, name = 'Wardrobe 4' },
    { id = 13, name = 'Wardrobe 5' }, { id = 14, name = 'Wardrobe 6' },
    { id = 15, name = 'Wardrobe 7' }, { id = 16, name = 'Wardrobe 8' },
};

local function normalize(s)
    return (s or ''):lower():gsub('[^%w]', '');
end

-- FFXI frequently abbreviates item display names (for example,
-- 'Tr. Insect Wing' vs. the full log name 'Transparent insect wing').
-- Compare both exact normalized names and token-by-token abbreviations so
-- the tracker can safely resolve normal client abbreviations such as Tr. / H.Q.
local function tokenize_name(s)
    local out = {};
    for token in (s or ''):lower():gmatch('[%w]+') do
        table.insert(out, token);
    end
    return out;
end

local function item_name_matches(wanted, candidate)
    if wanted == nil or candidate == nil or wanted == '' or candidate == '' then return false; end
    if normalize(wanted) == normalize(candidate) then return true; end

    local a = tokenize_name(wanted);
    local b = tokenize_name(candidate);
    if #a ~= #b or #a == 0 then return false; end

    for i = 1, #a do
        local x, y = a[i], b[i];
        if x ~= y then
            local shorter, longer = x, y;
            if #shorter > #longer then shorter, longer = longer, shorter; end
            -- A shorter token must be a true prefix of the longer token.
            -- This handles 'tr' -> 'transparent' and 'q' -> 'quality'.
            if longer:sub(1, #shorter) ~= shorter then return false; end
        end
    end
    return true;
end

local function resource_item_names(res)
    local names = {};
    if res == nil then return names; end
    local function add(v)
        if v ~= nil and type(v) == 'string' and #v > 0 then table.insert(names, v); end
    end
    if res.Name ~= nil then
        if type(res.Name) == 'string' then add(res.Name);
        else
            add(res.Name[0]); add(res.Name[1]); add(res.Name[2]);
        end
    end
    if res.LogNameSingular ~= nil then
        if type(res.LogNameSingular) == 'string' then add(res.LogNameSingular);
        else
            add(res.LogNameSingular[0]); add(res.LogNameSingular[1]); add(res.LogNameSingular[2]);
        end
    end
    return names;
end

local function build_keyitem_lookup()
    state.keyitem_ids = {};
    state.keyitem_names = {};
    local rm = AshitaCore:GetResourceManager();
    for id = 0, 65535 do
        local name = rm:GetString('keyitems.names', id);
        if name ~= nil and #name > 1 then
            local key = normalize(name);
            state.keyitem_ids[key] = state.keyitem_ids[key] or {};
            table.insert(state.keyitem_ids[key], id);
            table.insert(state.keyitem_names, { id = id, name = name });
        end
    end
end

-- Resolve a database KI name against Ashita's key-item strings. FFXI resource
-- names can be abbreviated just like normal item names, so first try the fast
-- exact normalized lookup and then fall back to the same prefix/token matcher
-- used for physical items (for example an abbreviated first word or H.Q.).
local function resolve_keyitem_ids(name)
    local key = normalize(name);
    local ids = state.keyitem_ids[key];
    if ids ~= nil and #ids > 0 then return ids; end

    local matched = {};
    for _, entry in ipairs(state.keyitem_names or {}) do
        if item_name_matches(name, entry.name) then
            table.insert(matched, entry.id);
        end
    end

    if #matched > 0 then
        -- Cache the database spelling too so future checks are cheap.
        state.keyitem_ids[key] = matched;
        return matched;
    end
    return nil;
end

local cached_pop_item_names = nil;

local function gather_pop_item_names()
    if cached_pop_item_names ~= nil then return cached_pop_item_names; end

    local names = {};
    for _, zone in ipairs(data.zones) do
        for _, nm in ipairs(zone.nms) do
            for _, req in ipairs(nm.requirements or {}) do
                if req.type == 'item' and req.name then
                    names[normalize(req.name)] = req.name;
                end
            end
        end
    end

    cached_pop_item_names = names;
    return cached_pop_item_names;
end

local function build_item_lookup()
    state.item_ids = {};
    local needed = gather_pop_item_names();
    local remaining = 0;
    for _ in pairs(needed) do remaining = remaining + 1; end
    if remaining == 0 then return; end

    local rm = AshitaCore:GetResourceManager();
    for id = 1, 65535 do
        local res = rm:GetItemById(id);
        if res ~= nil then
            local resource_names = resource_item_names(res);
            for needed_key, wanted_name in pairs(needed) do
                if state.item_ids[needed_key] == nil then
                    local matched = false;
                    for _, resource_name in ipairs(resource_names) do
                        -- Physical items must resolve exactly against one of Ashita's
                        -- resource names. GetItemById exposes both the abbreviated display
                        -- name and the full log name, so normal FFXI abbreviations do not
                        -- require fuzzy matching here. Exact matching prevents unrelated
                        -- inventory items from producing false OWNED states.
                        if normalize(wanted_name) == normalize(resource_name) then
                            state.item_ids[needed_key] = id;
                            remaining = remaining - 1;
                            matched = true;
                            break;
                        end
                    end
                    if matched and remaining <= 0 then break; end
                end
            end
            if remaining <= 0 then break; end
        end
    end
end

local function rebuild_lookups()
    build_keyitem_lookup();
    build_item_lookup();
    state.lookup_ready = true;
end

-- 0x055 contains the server's authoritative Key Item Log as 512-bit pages.
-- When we have seen the page for a KI, prefer that packet-backed state. This
-- avoids depending on the client memory wrapper being refreshed immediately
-- on every server implementation. If a page has not been seen since load,
-- fall back to Ashita's Player:HasKeyItem() just like ItemWatch does.
local function packet_has_keyitem(id)
    local page = math.floor(id / 0x200);
    if state.packet_keyitem_pages[page] then
        return state.packet_keyitems[id] == true, true;
    end
    return false, false;
end

local function persisted_has_keyitem(id)
    local owned = get_persisted_keyitems()[tostring(id)];
    return owned == true;
end

local function remember_keyitem(id, owned)
    local cache = get_persisted_keyitems();
    local k = tostring(id);
    if owned then cache[k] = true; else cache[k] = nil; end
end

local function has_keyitem(name)
    if not state.lookup_ready then rebuild_lookups(); end
    local ids = resolve_keyitem_ids(name);
    if ids == nil or #ids == 0 then return false, nil; end

    -- Match Ashita v4 ItemWatch's ownership method directly. HasKeyItem reads
    -- the key-item state already held by the client and does not send a packet.
    -- Do not let a partial/stale 0x055 page override this local ownership state.
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if player ~= nil then
        for _, id in ipairs(ids) do
            if player:HasKeyItem(id) then
                remember_keyitem(id, true);
                return true, id;
            end
        end
    end

    -- Packet/persisted state is fallback-only for the short period before the
    -- local player KI table is available after login/zoning.
    for _, id in ipairs(ids) do
        local owned, authoritative = packet_has_keyitem(id);
        if authoritative and owned then return true, id; end
        if persisted_has_keyitem(id) then return true, id; end
    end
    return false, ids[1];
end

local function keyitem_count(name)
    if not state.lookup_ready then rebuild_lookups(); end
    local ids = resolve_keyitem_ids(name);
    if ids == nil then return 0, 0; end

    local player = AshitaCore:GetMemoryManager():GetPlayer();
    local count = 0;
    for _, id in ipairs(ids) do
        local owned = false;
        if player ~= nil and player:HasKeyItem(id) then
            owned = true;
            remember_keyitem(id, true);
        else
            local packet_owned, packet_known = packet_has_keyitem(id);
            if packet_known and packet_owned then
                owned = true;
            elseif persisted_has_keyitem(id) then
                owned = true;
            end
        end
        if owned then count = count + 1; end
    end
    return count, #ids;
end

local function scan_items(force)
    local now = os.time();
    if not force and (now - state.last_item_scan) < 2.0 then return; end
    state.last_item_scan = now;
    state.item_owned = {};
    if not state.lookup_ready then rebuild_lookups(); end

    local watch = {};
    for _, id in pairs(state.item_ids) do watch[id] = true; end
    local inventory = AshitaCore:GetMemoryManager():GetInventory();
    if inventory == nil then return; end

    local rm = AshitaCore:GetResourceManager();
    local needed = gather_pop_item_names();

    for _, container in ipairs(CONTAINERS) do
        local max = inventory:GetContainerCountMax(container.id);
        if max ~= nil and max > 0 then
            -- Do not stop on an empty / unavailable slot. Containers can have gaps,
            -- especially after items are injected, moved, sorted, or received.
            for slot = 0, max do
                local ok, invitem = pcall(function() return inventory:GetContainerItem(container.id, slot); end);
                if ok and invitem ~= nil and invitem.Id ~= 0 and invitem.Id ~= 65535 then
                    local tracked = watch[invitem.Id] == true;

                    -- Fallback: resolve the item by the name Ashita reports for the actual
                    -- owned inventory entry. This protects us from resource lookup aliases
                    -- / capitalization differences in the static lookup pass.
                    if not tracked then
                        local res = rm:GetItemById(invitem.Id);
                        if res ~= nil then
                            local resource_names = resource_item_names(res);
                            for needed_key, wanted_name in pairs(needed) do
                                if state.item_ids[needed_key] == nil or state.item_ids[needed_key] == invitem.Id then
                                    for _, resource_name in ipairs(resource_names) do
                                        -- Same rule as the static lookup: exact match only.
                                        -- Ashita provides short and full item names, so this
                                        -- remains abbreviation-safe without fuzzy collisions.
                                        if normalize(wanted_name) == normalize(resource_name) then
                                            state.item_ids[needed_key] = invitem.Id;
                                            watch[invitem.Id] = true;
                                            tracked = true;
                                            break;
                                        end
                                    end
                                end
                                if tracked then break; end
                            end
                        end
                    end

                    if tracked then
                        local count = invitem.Count or 1;
                        local old = state.item_owned[invitem.Id];
                        if old == nil then
                            state.item_owned[invitem.Id] = { count = count, locations = { container.name } };
                        else
                            old.count = old.count + count;
                            local exists = false;
                            for _, n in ipairs(old.locations) do if n == container.name then exists = true; break; end end
                            if not exists then table.insert(old.locations, container.name); end
                        end
                    end
                end
            end
        end
    end
end

local function item_status(name)
    if not state.lookup_ready then rebuild_lookups(); end
    local id = state.item_ids[normalize(name)];
    if id == nil then return false, nil, nil; end
    local info = state.item_owned[id];
    return info ~= nil, id, info;
end

local function req_owned(req)
    if req.type == 'ki' then return has_keyitem(req.name); end
    if req.type == 'item' then return item_status(req.name); end
    return true, nil;
end

local function nm_ready(nm)
    if not nm.requirements or #nm.requirements == 0 then return true; end
    for _, req in ipairs(nm.requirements) do
        local owned = req_owned(req);
        if not owned then return false; end
    end
    return true;
end

local function sorted_nms(zone)
    local out = {};
    for i, nm in ipairs(zone.nms or {}) do out[#out + 1] = { nm = nm, index = i }; end
    table.sort(out, function(a, b) return a.nm.name:lower() < b.nm.name:lower(); end);
    return out;
end


local function build_collection_sets()
    local abyssites, atmas = {}, {};
    for _, entry in ipairs(data.abyssites or {}) do abyssites[normalize(entry.name)] = true; end
    for _, entry in ipairs(data.atmas or {}) do atmas[normalize(entry.name)] = true; end
    return abyssites, atmas;
end

local cached_watched_keyitems = nil;

local function gather_watched_keyitems()
    if cached_watched_keyitems ~= nil then return cached_watched_keyitems; end

    local watched = {};
    for _, zone in ipairs(data.zones or {}) do
        for _, nm in ipairs(zone.nms or {}) do
            for _, req in ipairs(nm.requirements or {}) do
                if req.type == 'ki' and req.name then
                    watched[normalize(req.name)] = { name = req.name, kind = 'keyitem' };
                end
            end
            for _, reward in ipairs(nm.rewards or {}) do
                if reward.type == 'ki' and reward.name then
                    watched[normalize(reward.name)] = { name = reward.name, kind = 'keyitem' };
                end
            end
        end
    end
    for _, entry in ipairs(data.abyssites or {}) do
        watched[normalize(entry.name)] = { name = entry.name, kind = 'abyssite' };
    end
    for _, entry in ipairs(data.atmas or {}) do
        watched[normalize(entry.name)] = { name = entry.name, kind = 'atma' };
    end

    cached_watched_keyitems = watched;
    return cached_watched_keyitems;
end

local function current_item_count_by_name(name)
    local _, _, info = item_status(name);
    return info and (info.count or 0) or 0;
end


local function refresh_current_ownership()
    if not state.lookup_ready then rebuild_lookups(); end
    scan_items(true);

    -- One-time local-memory pass for all tracked KIs. Positive results are
    -- persisted; packet-backed pages remain authoritative for removals.
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if player ~= nil then
        for _, entry in pairs(gather_watched_keyitems()) do
            local ids = resolve_keyitem_ids(entry.name) or {};
            for _, id in ipairs(ids) do
                if player:HasKeyItem(id) then
                    remember_keyitem(id, true);
                else
                    local packet_owned, packet_known = packet_has_keyitem(id);
                    if packet_known and packet_owned then remember_keyitem(id, true); end
                end
            end
        end
    end
    save_persisted_keyitems();
end

local function initialize_monitor()
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    local inventory = AshitaCore:GetMemoryManager():GetInventory();
    if player == nil or inventory == nil then
        state.monitor_ready = false;
        return;
    end
    state.keyitem_snapshot = {};
    state.item_snapshot = {};
    for key, entry in pairs(gather_watched_keyitems()) do
        local count = keyitem_count(entry.name);
        state.keyitem_snapshot[key] = count;
    end
    for key, name in pairs(gather_pop_item_names()) do
        state.item_snapshot[key] = current_item_count_by_name(name);
    end
    state.monitor_ready = true;
end

local function detect_keyitem_changes()
    if state.zoning or os.clock() < (state.zone_alert_mute_until or 0) or not state.monitor_ready then return; end

    for key, entry in pairs(gather_watched_keyitems()) do
        local count = keyitem_count(entry.name);
        local old = state.keyitem_snapshot[key] or 0;
        if count > old then
            play_chime(entry.kind);
            print(('[Abyssea] Obtained %s: %s'):format(entry.kind == 'keyitem' and 'key item' or entry.kind, entry.name));
        end
        state.keyitem_snapshot[key] = count;
    end
end

local function detect_item_changes()
    if state.zoning or os.clock() < (state.zone_alert_mute_until or 0) or not state.monitor_ready then return; end

    -- This is a local-memory scan only. It does not send packets or requests
    -- to the game server. It is now only performed after FFXI reports that
    -- inventory data changed.
    scan_items(true);
    for key, name in pairs(gather_pop_item_names()) do
        local count = current_item_count_by_name(name);
        local old = state.item_snapshot[key] or 0;
        if count > old then
            play_chime('item');
            print(('[Abyssea] Obtained item: %s'):format(name));
        end
        state.item_snapshot[key] = count;
    end
end

local function queue_item_event_refresh()
    state.item_event_generation = state.item_event_generation + 1;
    local generation = state.item_event_generation;
    -- Let Ashita apply the incoming inventory packet to memory first, then
    -- refresh once. Consecutive packets collapse into the latest refresh.
    ashita.tasks.once(0.18, function()
        if generation ~= state.item_event_generation then return; end
        detect_item_changes();
    end);
end

local function parse_keyitem_log_packet(packet)
    if packet == nil or #packet < 0x88 then return false, nil; end

    -- Incoming 0x055 layout:
    --   0x04..0x43 = 0x40-byte availability bitfield
    --   0x44..0x83 = examined/new-state bitfield
    --   0x84..0x87 = page/type (each page represents 0x200 KI ids)
    local p1, p2, p3, p4 = packet:byte(0x84 + 1, 0x87 + 1);
    if p1 == nil then return false, nil; end
    local page = p1 + (p2 or 0) * 0x100 + (p3 or 0) * 0x10000 + (p4 or 0) * 0x1000000;
    if page < 0 or page > 127 then return false, page; end

    -- A 0x055 packet is a complete snapshot for this 512-KI page. Clear the
    -- previous page before applying the new bitfield.
    local first_id = page * 0x200;
    for id = first_id, first_id + 0x1FF do
        state.packet_keyitems[id] = nil;
    end

    for byte_index = 0, 0x3F do
        local value = packet:byte(0x04 + byte_index + 1) or 0;
        if value ~= 0 then
            for bit_index = 0, 7 do
                if bit.band(value, bit.lshift(1, bit_index)) ~= 0 then
                    local id = first_id + (byte_index * 8) + bit_index;
                    state.packet_keyitems[id] = true;
                end
            end
        end
    end
    state.packet_keyitem_pages[page] = true;

    -- Persist the authoritative state for this page so addon reloads preserve
    -- previously observed KI ownership without requesting anything from the server.
    for id = first_id, first_id + 0x1FF do
        remember_keyitem(id, state.packet_keyitems[id] == true);
    end
    save_persisted_keyitems();
    return true, page;
end

local function queue_keyitem_event_refresh()
    state.keyitem_event_generation = state.keyitem_event_generation + 1;
    local generation = state.keyitem_event_generation;
    -- Key Item Log packets can arrive as a short burst. Debounce them so the
    -- UI updates immediately after the burst without continuously polling.
    ashita.tasks.once(0.12, function()
        if generation ~= state.keyitem_event_generation then return; end
        detect_keyitem_changes();
    end);
end

-- Abyssea weakness proc helper -------------------------------------------------
-- Uses local wall-clock time to derive Vana'diel time.  Vana'diel advances at
-- 25x real time and the commonly used FFXI epoch is 2002-01-01 00:00 JST.
local VANA_EARTH_EPOCH = 1009810800;
local VANA_BASE_YEAR = 886;
local VANA_DAY_SECONDS = 86400;
local VANA_YEAR_DAYS = 360;

local vana_days = {
    { name = 'Firesday',     element = 'Fire',      color = { 1.00, 0.35, 0.25, 1.00 } },
    { name = 'Earthsday',    element = 'Earth',     color = { 0.82, 0.68, 0.34, 1.00 } },
    { name = 'Watersday',    element = 'Water',     color = { 0.35, 0.68, 1.00, 1.00 } },
    { name = 'Windsday',     element = 'Wind',      color = { 0.40, 0.90, 0.58, 1.00 } },
    { name = 'Iceday',       element = 'Ice',       color = { 0.55, 0.88, 1.00, 1.00 } },
    { name = 'Lightningday', element = 'Lightning', color = { 0.78, 0.55, 1.00, 1.00 } },
    { name = 'Lightsday',    element = 'Light',     color = { 1.00, 0.92, 0.52, 1.00 } },
    { name = 'Darksday',     element = 'Dark',      color = { 0.72, 0.50, 0.88, 1.00 } },
};

local red_procs = {
    { ws = 'Cyclone',          weapon = 'Dagger',       element = 'Wind' },
    { ws = 'Energy Drain',     weapon = 'Dagger',       element = 'Dark' },
    { ws = 'Red Lotus Blade',  weapon = 'Sword',        element = 'Fire' },
    { ws = 'Seraph Blade',     weapon = 'Sword',        element = 'Light' },
    { ws = 'Freezebite',       weapon = 'Great Sword',  element = 'Ice' },
    { ws = 'Shadow of Death',  weapon = 'Scythe',       element = 'Dark' },
    { ws = 'Raiden Thrust',    weapon = 'Polearm',      element = 'Lightning' },
    { ws = 'Blade: Ei',        weapon = 'Katana',       element = 'Dark' },
    { ws = 'Tachi: Jinpu',     weapon = 'Great Katana', element = 'Wind' },
    { ws = 'Tachi: Koki',      weapon = 'Great Katana', element = 'Light' },
    { ws = 'Seraph Strike',    weapon = 'Club',         element = 'Light' },
    { ws = 'Earth Crusher',    weapon = 'Staff',        element = 'Earth' },
    { ws = 'Sunburst',         weapon = 'Staff',        element = 'Light' },
};

local blue_procs = {
    piercing = {
        { 'Shadowstitch', 'Dagger' }, { 'Dancing Edge', 'Dagger' }, { 'Shark Bite', 'Dagger' }, { 'Evisceration', 'Dagger' },
        { 'Skewer', 'Polearm' }, { 'Wheeling Thrust', 'Polearm' }, { 'Impulse Drive', 'Polearm' },
        { 'Sidewinder', 'Archery' }, { 'Blast Arrow', 'Archery' }, { 'Arching Arrow', 'Archery' }, { 'Empyreal Arrow', 'Archery' },
        { 'Slug Shot', 'Marksmanship' }, { 'Blast Shot', 'Marksmanship' }, { 'Heavy Shot', 'Marksmanship' }, { 'Detonator', 'Marksmanship' },
    },
    slashing = {
        { 'Vorpal Blade', 'Sword' }, { 'Swift Blade', 'Sword' }, { 'Savage Blade', 'Sword' },
        { 'Spinning Slash', 'Great Sword' }, { 'Ground Strike', 'Great Sword' },
        { 'Mistral Axe', 'Axe' }, { 'Decimation', 'Axe' },
        { 'Full Break', 'Great Axe' }, { 'Steel Cyclone', 'Great Axe' },
        { 'Cross Reaper', 'Scythe' }, { 'Spiral Hell', 'Scythe' },
        { 'Blade: Ten', 'Katana' }, { 'Blade: Ku', 'Katana' },
        { 'Tachi: Gekko', 'Great Katana' }, { 'Tachi: Kasha', 'Great Katana' },
    },
    blunt = {
        { 'Raging Fists', 'Hand-to-Hand' }, { 'Spinning Attack', 'Hand-to-Hand' }, { 'Howling Fist', 'Hand-to-Hand' }, { 'Dragon Kick', 'Hand-to-Hand' }, { 'Asuran Fists', 'Hand-to-Hand' },
        { 'Skullbreaker', 'Club' }, { 'True Strike', 'Club' }, { 'Judgment', 'Club' }, { 'Hexa Strike', 'Club' }, { 'Black Halo', 'Club' },
        { 'Heavy Swing', 'Staff' }, { 'Shell Crusher', 'Staff' }, { 'Full Swing', 'Staff' }, { 'Spirit Taker', 'Staff' }, { 'Retribution', 'Staff' },
    },
};

local yellow_procs = {
    Firesday     = { 'Fire III', 'Fire IV', 'Firaga III', 'Flare', 'Katon: Ni', 'Ice Threnody', 'Heat Breath' },
    Earthsday    = { 'Stone III', 'Stone IV', 'Stonega III', 'Quake', 'Doton: Ni', 'Lightning Threnody', 'Magnetite Cloud' },
    Watersday    = { 'Water III', 'Water IV', 'Waterga III', 'Flood', 'Suiton: Ni', 'Fire Threnody', 'Maelstrom' },
    Windsday     = { 'Aero III', 'Aero IV', 'Aeroga III', 'Tornado', 'Huton: Ni', 'Earth Threnody', 'Mysterious Light' },
    Iceday       = { 'Blizzard III', 'Blizzard IV', 'Blizzaga III', 'Freeze', 'Hyoton: Ni', 'Wind Threnody', 'Ice Break' },
    Lightningday = { 'Thunder III', 'Thunder IV', 'Thundaga III', 'Burst', 'Raiton: Ni', 'Water Threnody', 'Mind Blast' },
    Lightsday    = { 'Banish II', 'Banish III', 'Banishga II', 'Holy', 'Flash', 'Dark Threnody', 'Radiant Breath' },
    Darksday     = { 'Drain', 'Aspir', 'Dispel', 'Bio II', 'Kurayami: Ni', 'Light Threnody', 'Eyes On Me' },
};

local function vana_now()
    local elapsed = os.time() - VANA_EARTH_EPOCH;
    local total = (VANA_BASE_YEAR * VANA_YEAR_DAYS * VANA_DAY_SECONDS) + (elapsed * 25);
    local day_number = math.floor(total / VANA_DAY_SECONDS);
    local second_of_day = total % VANA_DAY_SECONDS;
    if second_of_day < 0 then second_of_day = second_of_day + VANA_DAY_SECONDS; end
    local hour = math.floor(second_of_day / 3600);
    local minute = math.floor((second_of_day % 3600) / 60);
    local second = math.floor(second_of_day % 60);
    local day_index = (day_number % 8) + 1;
    return { hour = hour, minute = minute, second = second, day_index = day_index };
end

local function get_blue_window(hour, minute)
    local mins = hour * 60 + minute;
    if mins >= 360 and mins < 840 then
        return 'piercing', 'PIERCING', '06:00 - 13:59', 840;
    elseif mins >= 840 and mins < 1320 then
        return 'slashing', 'SLASHING', '14:00 - 21:59', 1320;
    end
    local boundary = (mins < 360) and 360 or (1440 + 360);
    return 'blunt', 'BLUNT', '22:00 - 05:59', boundary;
end

local function checkbox_map(map, key)
    if map[key] == nil then map[key] = { false }; end
    return map[key];
end

local function reset_proc_map(map)
    for _, v in pairs(map) do v[1] = false; end
end

local function render_proc_header()
    local vt = vana_now();
    local cur = vana_days[vt.day_index];
    local prev = vana_days[((vt.day_index - 2) % 8) + 1];
    local nxt = vana_days[(vt.day_index % 8) + 1];

    -- Keep the live clock / day information on one clean line.
    -- The Yellow element sequence sits on its own line so long day names
    -- (such as Lightningday) can never overlap the sequence text.
    imgui.TextColored(colors.title, 'PROC TRACKER');
    imgui.SameLine(190); imgui.TextColored(colors.muted, 'CatsEye Time:');
    imgui.SameLine(); imgui.TextColored(colors.normal, ('%02d:%02d'):format(vt.hour, vt.minute));
    imgui.SameLine(410); imgui.TextColored(colors.muted, 'Current Day:');
    imgui.SameLine(); imgui.TextColored(cur.color, cur.name .. ' (' .. cur.element .. ')');

    imgui.TextColored(colors.muted, 'Yellow Elements:');
    imgui.SameLine(); imgui.TextColored(prev.color, prev.element);
    imgui.SameLine(); imgui.TextColored(colors.muted, '  /  ');
    imgui.SameLine(); imgui.TextColored(cur.color, cur.element);
    imgui.SameLine(); imgui.TextColored(colors.muted, '  /  ');
    imgui.SameLine(); imgui.TextColored(nxt.color, nxt.element);
    imgui.TextColored(colors.muted, 'Previous                 Current                 Following');
    imgui.Separator();
end

local function render_red_procs()
    imgui.TextColored({ 1.0, 0.35, 0.35, 1.0 }, 'RED PROC - ELEMENTAL WEAPONSKILLS');
    imgui.TextColored(colors.muted, 'Red can be any of these 13 weapon skills. Check them off as your group tries them.');
    imgui.Checkbox('Show Red in Proc Tracker##track_red_proc', state.proc_track_red);
    if state.proc_track_red[1] then state.proc_tracker_open[1] = true; end
    imgui.Separator();
    imgui.BeginChild('##red_proc_list', { -1, -42 }, false);
    for i, entry in ipairs(red_procs) do
        local key = entry.ws;
        imgui.Checkbox(('##red_%d'):format(i), checkbox_map(state.proc_red, key));
        imgui.SameLine();
        imgui.TextColored(colors.normal, entry.ws);
        imgui.SameLine(310); imgui.TextColored(colors.source, entry.weapon);
        imgui.SameLine(500); imgui.TextColored(colors.muted, entry.element);
    end
    imgui.EndChild();
    if imgui.Button('RESET RED##proc_reset_red', { 120, 28 }) then reset_proc_map(state.proc_red); end
end

local function render_blue_procs()
    local vt = vana_now();
    local key, label, range, boundary = get_blue_window(vt.hour, vt.minute);
    local mins = vt.hour * 60 + vt.minute;
    local adjusted = mins;
    if key == 'blunt' and mins < 360 then adjusted = mins + 1440; end
    local remaining = boundary - adjusted;
    local rh, rm = math.floor(remaining / 60), remaining % 60;
    local next_label = key == 'piercing' and 'SLASHING' or (key == 'slashing' and 'BLUNT' or 'PIERCING');

    imgui.TextColored({ 0.38, 0.72, 1.0, 1.0 }, 'BLUE PROC - PHYSICAL WEAPONSKILLS');
    imgui.TextColored(colors.muted, 'The active family is based on CatsEye Time when the NM is claimed or spawned.');
    imgui.Checkbox('Show Blue in Proc Tracker##track_blue_proc', state.proc_track_blue);
    if state.proc_track_blue[1] then state.proc_tracker_open[1] = true; end
    imgui.Spacing();
    imgui.TextColored(colors.header, 'CURRENT WINDOW');
    imgui.SameLine(165); imgui.TextColored({ 0.38, 0.72, 1.0, 1.0 }, label);
    imgui.SameLine(280); imgui.TextColored(colors.normal, range);
    imgui.SameLine(455); imgui.TextColored(colors.muted, ('%dh %02dm remaining'):format(rh, rm));
    imgui.SameLine(650); imgui.TextColored(colors.muted, 'Next: ' .. next_label);
    imgui.Separator();

    imgui.BeginChild('##blue_proc_list', { -1, -42 }, false);
    for i, entry in ipairs(blue_procs[key]) do
        local ws, weapon = entry[1], entry[2];
        local pkey = key .. ':' .. ws;
        imgui.Checkbox(('##blue_%s_%d'):format(key, i), checkbox_map(state.proc_blue, pkey));
        imgui.SameLine(); imgui.TextColored(colors.normal, ws);
        imgui.SameLine(310); imgui.TextColored(colors.source, weapon);
    end
    imgui.EndChild();
    if imgui.Button('RESET BLUE##proc_reset_blue', { 120, 28 }) then reset_proc_map(state.proc_blue); end
end

local function render_yellow_procs()
    local vt = vana_now();
    local indices = { ((vt.day_index - 2) % 8) + 1, vt.day_index, (vt.day_index % 8) + 1 };
    local labels = { 'PREVIOUS', 'CURRENT', 'FOLLOWING' };
    imgui.TextColored({ 1.0, 0.82, 0.25, 1.0 }, 'YELLOW PROC - MAGIC');
    imgui.TextColored(colors.muted, 'Yellow uses the previous, current and following day elements when the NM is claimed or spawned.');
    imgui.Checkbox('Show Yellow in Proc Tracker##track_yellow_proc', state.proc_track_yellow);
    if state.proc_track_yellow[1] then state.proc_tracker_open[1] = true; end
    imgui.Separator();

    local avail_width, avail_height = imgui.GetContentRegionAvail();
    avail_width = tonumber(avail_width) or 900;
    local width = math.max(250, (avail_width - 12) / 3);
    for col = 1, 3 do
        local day = vana_days[indices[col]];
        if col > 1 then imgui.SameLine(); end
        imgui.BeginChild('##yellow_col_' .. col, { width, -42 }, true);
        imgui.TextColored(colors.muted, labels[col]);
        imgui.TextColored(day.color, day.name .. ' - ' .. day.element);
        imgui.Separator();
        for i, spell in ipairs(yellow_procs[day.name]) do
            local pkey = day.name .. ':' .. spell;
            imgui.Checkbox(('##yellow_%d_%d'):format(col, i), checkbox_map(state.proc_yellow, pkey));
            imgui.SameLine(); imgui.Text(spell);
        end
        imgui.EndChild();
    end
    if imgui.Button('RESET YELLOW##proc_reset_yellow', { 130, 28 }) then reset_proc_map(state.proc_yellow); end
end

local function render_procs()
    render_proc_header();
    if imgui.BeginTabBar('##proc_tabs') then
        if imgui.BeginTabItem('Red') then render_red_procs(); imgui.EndTabItem(); end
        if imgui.BeginTabItem('Blue') then render_blue_procs(); imgui.EndTabItem(); end
        if imgui.BeginTabItem('Yellow') then render_yellow_procs(); imgui.EndTabItem(); end
        imgui.EndTabBar();
    end
end

local function any_proc_tracker_enabled()
    return state.proc_track_red[1] or state.proc_track_blue[1] or state.proc_track_yellow[1];
end

local function render_proc_tracker_checkbox(map, key, id, label, detail)
    imgui.Checkbox(id, checkbox_map(map, key));
    imgui.SameLine();
    imgui.TextColored(colors.normal, label);
    if detail ~= nil and detail ~= '' then
        imgui.SameLine(225);
        imgui.TextColored(colors.source, detail);
    end
end

local function render_proc_tracker_window()
    if not state.proc_tracker_open[1] or not any_proc_tracker_enabled() then return; end

    local vt = vana_now();
    local current_day = vana_days[vt.day_index];

    imgui.PushStyleColor(ImGuiCol_WindowBg, { 0.012, 0.025, 0.042, 0.94 });
    imgui.PushStyleColor(ImGuiCol_Border, { 0.18, 0.56, 0.78, 0.78 });
    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, 6);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 9, 8 });
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { 4, 2 });
    imgui.SetNextWindowSize({ 390, 500 }, ImGuiCond_FirstUseEver);
    imgui.SetNextWindowSizeConstraints({ 310, 170 }, { 620, 900 });

    if imgui.Begin('Proc Tracker##abyssea_proc_tracker', state.proc_tracker_open) then
        imgui.TextColored(colors.title, 'PROC TRACKER');
        imgui.SameLine();
        imgui.TextColored(colors.muted, ('%02d:%02d'):format(vt.hour, vt.minute));
        imgui.SameLine();
        imgui.TextColored(current_day.color, current_day.name);
        imgui.Separator();

        if state.proc_track_red[1] then
            imgui.TextColored({ 1.0, 0.35, 0.35, 1.0 }, 'RED');
            imgui.SameLine(70); imgui.TextColored(colors.muted, 'Elemental WS');
            imgui.SameLine(300);
            if imgui.SmallButton('RESET##proc_tracker_red_reset') then reset_proc_map(state.proc_red); end
            for i, entry in ipairs(red_procs) do
                render_proc_tracker_checkbox(state.proc_red, entry.ws, ('##ptr_red_%d'):format(i), entry.ws, entry.weapon);
            end
            if state.proc_track_blue[1] or state.proc_track_yellow[1] then imgui.Separator(); end
        end

        if state.proc_track_blue[1] then
            local key, label, range, boundary = get_blue_window(vt.hour, vt.minute);
            local mins = vt.hour * 60 + vt.minute;
            local adjusted = mins;
            if key == 'blunt' and mins < 360 then adjusted = mins + 1440; end
            local remaining = boundary - adjusted;
            local rh, rm = math.floor(remaining / 60), remaining % 60;
            imgui.TextColored({ 0.38, 0.72, 1.0, 1.0 }, 'BLUE');
            imgui.SameLine(70); imgui.TextColored({ 0.38, 0.72, 1.0, 1.0 }, label);
            imgui.SameLine(); imgui.TextColored(colors.muted, range);
            imgui.TextColored(colors.muted, ('%dh %02dm until next window'):format(rh, rm));
            imgui.SameLine(300);
            if imgui.SmallButton('RESET##proc_tracker_blue_reset') then reset_proc_map(state.proc_blue); end
            for i, entry in ipairs(blue_procs[key]) do
                local ws, weapon = entry[1], entry[2];
                local pkey = key .. ':' .. ws;
                render_proc_tracker_checkbox(state.proc_blue, pkey, ('##ptr_blue_%s_%d'):format(key, i), ws, weapon);
            end
            if state.proc_track_yellow[1] then imgui.Separator(); end
        end

        if state.proc_track_yellow[1] then
            local indices = { ((vt.day_index - 2) % 8) + 1, vt.day_index, (vt.day_index % 8) + 1 };
            local labels = { 'PREV', 'CURRENT', 'NEXT' };
            imgui.TextColored({ 1.0, 0.82, 0.25, 1.0 }, 'YELLOW');
            imgui.SameLine(300);
            if imgui.SmallButton('RESET##proc_tracker_yellow_reset') then reset_proc_map(state.proc_yellow); end
            for col = 1, 3 do
                local day = vana_days[indices[col]];
                imgui.TextColored(colors.muted, labels[col] .. ':');
                imgui.SameLine(70); imgui.TextColored(day.color, day.name .. ' - ' .. day.element);
                for i, spell in ipairs(yellow_procs[day.name]) do
                    local pkey = day.name .. ':' .. spell;
                    render_proc_tracker_checkbox(state.proc_yellow, pkey, ('##ptr_yellow_%d_%d'):format(col, i), spell, '');
                end
                if col < 3 then imgui.Spacing(); end
            end
        end
    end
    imgui.End();
    imgui.PopStyleVar(3);
    imgui.PopStyleColor(2);
end

local function render_sound_settings()
    imgui.TextColored(colors.header, 'ACQUISITION CHIMES');
    imgui.TextColored(colors.muted, 'Chimes are event-driven and play when FFXI reports an inventory or key-item change.');
    imgui.Separator();
    imgui.Checkbox('Enable sounds##aby_sound_master', state.sounds_enabled);
    imgui.Spacing();
    imgui.Checkbox('Physical pop items##aby_sound_item', state.sound_item);
    imgui.SameLine(280);
    if imgui.Button('Test##sound_item') then play_chime('item'); end
    imgui.Checkbox('Key items##aby_sound_keyitem', state.sound_keyitem);
    imgui.SameLine(280);
    if imgui.Button('Test##sound_keyitem') then play_chime('keyitem'); end
    imgui.Checkbox('Abyssites##aby_sound_abyssite', state.sound_abyssite);
    imgui.SameLine(280);
    if imgui.Button('Test##sound_abyssite') then play_chime('abyssite'); end
    imgui.Checkbox('Atmas##aby_sound_atma', state.sound_atma);
    imgui.SameLine(280);
    if imgui.Button('Test##sound_atma') then play_chime('atma'); end
    imgui.Spacing();
    imgui.Separator();
    imgui.TextColored(colors.header, 'DISPLAY MODE');
    imgui.TextColored(colors.muted, 'Full mode is for planning. Compact mode is a small farming panel.');
    if imgui.RadioButton('Full##aby_mode_full', not state.compact_mode[1]) then state.compact_mode[1] = false; end
    imgui.SameLine();
    if imgui.RadioButton('Compact##aby_mode_compact', state.compact_mode[1]) then state.compact_mode[1] = true; end
    imgui.Spacing();
    imgui.Spacing();
    imgui.Separator();
    imgui.TextColored(colors.header, 'PINNED NM TRACKER');
    imgui.Checkbox('Show pinned tracker##aby_tracker_open', state.tracker_open);
    imgui.TextColored(colors.muted, 'Pin an NM from its detail page, or use /aby track <NM name>.');
    imgui.Spacing();
    imgui.Separator();
    imgui.TextColored(colors.header, 'PROC TRACKER');
    imgui.Checkbox('Show Proc Tracker##aby_proc_tracker_open', state.proc_tracker_open);
    imgui.TextColored(colors.muted, 'Choose which proc types appear in the separate farming window.');
    imgui.Checkbox('Red##aby_proc_track_red', state.proc_track_red);
    imgui.SameLine(120); imgui.Checkbox('Blue##aby_proc_track_blue', state.proc_track_blue);
    imgui.SameLine(240); imgui.Checkbox('Yellow##aby_proc_track_yellow', state.proc_track_yellow);
    imgui.TextColored(colors.muted, 'Commands: /aby proctracker on/off | red/blue/yellow on/off');
    imgui.TextColored(colors.muted, 'Other: /aby mode full | compact  |  /aby tracker on/off/clear  |  /aby sound on/off');
    imgui.Spacing();
    imgui.Separator();
    imgui.TextColored(colors.header, 'ABYSSEA STATUS BAR');
    imgui.TextColored(colors.muted, 'Shows Visitant time and current light values while you are inside Abyssea.');
    local bar_before = state.statusbar_open[1];
    imgui.Checkbox('Show Abyssea status bar##aby_statusbar_open', state.statusbar_open);
    if bar_before ~= state.statusbar_open[1] then
        persisted.statusbar_enabled = state.statusbar_open[1];
        pcall(function() settings.save(); end);
    end
    imgui.TextColored(colors.muted, 'The bar is draggable. Command: /aby bar on/off');
    imgui.Spacing();
    imgui.Separator();
    imgui.TextColored(colors.header, 'RELEASE / NETWORK');
    imgui.TextColored(colors.muted, 'Passive, event-driven design. No outgoing packet injection or server polling.');
    imgui.TextColored(colors.muted, 'Inventory and ownership checks read local Ashita client memory.');
end

local function tracker_key(zone_index, nm_name)
    return tostring(zone_index) .. '|' .. normalize(nm_name);
end

local function is_nm_tracked(zone_index, nm_name)
    return state.tracked_nms[tracker_key(zone_index, nm_name)] ~= nil;
end

local function add_tracked_nm(zone_index, nm)
    if nm == nil then return; end
    local key = tracker_key(zone_index, nm.name);
    state.tracked_nms[key] = { zone_index = zone_index, name = nm.name };
    state.tracker_open[1] = true;
end

local function remove_tracked_nm(zone_index, nm_name)
    state.tracked_nms[tracker_key(zone_index, nm_name)] = nil;
end

local function find_nm_in_zone(zone_index, name)
    local zone = data.zones[zone_index];
    if zone == nil then return nil; end
    local wanted = normalize(name);
    for _, nm in ipairs(zone.nms or {}) do
        if normalize(nm.name) == wanted then return nm; end
    end
    return nil;
end

local function tracked_count()
    local n = 0;
    for _ in pairs(state.tracked_nms) do n = n + 1; end
    return n;
end

local function list_contains_normalized(list, name)
    if list == nil or name == nil then return false; end
    local wanted = normalize(name);
    for _, v in ipairs(list) do
        if normalize(v) == wanted then return true; end
    end
    return false;
end

local function requirement_has_gold_pyxis(zone_index, req)
    local zone = data.zones[zone_index];
    if zone == nil or req == nil then return false; end
    if req.type == 'ki' then
        return list_contains_normalized(zone.gold_pyxis_keyitems, req.name);
    end
    return list_contains_normalized(zone.gold_pyxis_items, req.name);
end

local function requirement_source_text(zone_index, req)
    local src = req.source or '';
    if requirement_has_gold_pyxis(zone_index, req) then
        if src ~= '' then return src .. ' / Gold Pyxis'; end
        return 'Gold Pyxis';
    end
    return src;
end

local function render_tracker_requirement(zone_index, req, depth, visited)
    depth = depth or 0;
    visited = visited or {};
    local owned = req_owned(req);
    local c = owned and colors.owned or colors.missing;
    local indent = string.rep('   ', depth);
    local glyph = owned and '[+]' or '[-]';
    imgui.TextColored(c, indent .. glyph .. ' ' .. (req.name or 'Unknown'));

    if req.source and req.source ~= '' then
        local source_nm = find_nm_in_zone(zone_index, req.source);
        local tracker_source = requirement_source_text(zone_index, req);
        imgui.TextColored(colors.source, indent .. '    from ' .. tracker_source);
        if source_nm ~= nil and depth < 4 then
            local visit_key = normalize(source_nm.name);
            if not visited[visit_key] then
                visited[visit_key] = true;
                if source_nm.requirements and #source_nm.requirements > 0 then
                    for _, subreq in ipairs(source_nm.requirements) do
                        render_tracker_requirement(zone_index, subreq, depth + 1, visited);
                    end
                elseif source_nm.spawn_type then
                    imgui.TextColored(colors.muted, indent .. '      ' .. source_nm.spawn_type);
                end
                visited[visit_key] = nil;
            end
        end
    end
end

local function render_tracker_window()
    if tracked_count() == 0 or not state.tracker_open[1] then return; end

    imgui.PushStyleColor(ImGuiCol_WindowBg, { 0.025, 0.035, 0.055, 0.90 });
    imgui.PushStyleColor(ImGuiCol_Border, { 0.22, 0.42, 0.62, 0.72 });
    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, 6);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 9, 8 });
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { 4, 2 });
    imgui.SetNextWindowSize({ 390, 420 }, ImGuiCond_FirstUseEver);
    imgui.SetNextWindowSizeConstraints({ 285, 150 }, { 650, 900 });

    if imgui.Begin('NM Tracker##abyssea_tracker_overlay', state.tracker_open) then
        imgui.TextColored(colors.title, 'ABYSSEA TARGETS');
        imgui.SameLine();
        imgui.TextColored(colors.muted, ('%d pinned'):format(tracked_count()));
        imgui.SameLine(300);
        if imgui.SmallButton('CLEAR##tracker_clear') then state.tracked_nms = {}; end
        imgui.Separator();

        local ordered = {};
        for _, entry in pairs(state.tracked_nms) do table.insert(ordered, entry); end
        table.sort(ordered, function(a, b)
            if a.zone_index == b.zone_index then return a.name:lower() < b.name:lower(); end
            return a.zone_index < b.zone_index;
        end);

        for i, entry in ipairs(ordered) do
            local nm = find_nm_in_zone(entry.zone_index, entry.name);
            local zone = data.zones[entry.zone_index];
            if nm ~= nil and zone ~= nil then
                imgui.TextColored(nm_ready(nm) and colors.owned or colors.title, nm.name);
                imgui.SameLine();
                imgui.TextColored(colors.muted, '- ' .. (zone.short_name or zone.name));
                imgui.SameLine(330);
                if imgui.SmallButton('X##tracker_remove_' .. i) then
                    remove_tracked_nm(entry.zone_index, entry.name);
                end

                if nm.requirements and #nm.requirements > 0 then
                    local visited = { [normalize(nm.name)] = true };
                    for _, req in ipairs(nm.requirements) do
                        render_tracker_requirement(entry.zone_index, req, 0, visited);
                    end
                else
                    imgui.TextColored(colors.muted, nm.spawn_type or 'No tracked requirement.');
                end
                if i < #ordered then imgui.Separator(); end
            end
        end
    end
    imgui.End();
    imgui.PopStyleVar(3);
    imgui.PopStyleColor(2);
end

local function render_requirement(req, zone_index)
    local owned, id, info = req_owned(req);
    local status_color = owned and colors.owned or colors.missing;
    local label = (req.type == 'ki') and 'KEY ITEM' or 'POP ITEM';

    imgui.TextColored(status_color, owned and 'OWNED' or 'MISSING');
    imgui.SameLine(88);
    imgui.TextColored(colors.muted, label);
    imgui.SameLine(175);
    imgui.TextColored(status_color, req.name or 'Unknown');

    local source_text = requirement_source_text(zone_index, req);
    if source_text ~= '' then
        imgui.SameLine(530);
        imgui.TextColored(colors.source, 'From:');
        imgui.SameLine();
        imgui.TextColored(colors.source, source_text);
    end

    if req.type == 'item' and owned and info ~= nil then
        local where = table.concat(info.locations or {}, ', ');
        imgui.TextColored(colors.muted, ('    x%d  Stored: %s'):format(info.count or 1, where));
    elseif id == nil and imgui.IsItemHovered() then
        imgui.SetTooltip(req.type == 'ki' and 'Key item name was not found in Ashita resources.' or 'Item name was not found in Ashita resources.');
    end
end

local function render_nm_detail(nm, zone_index)
    imgui.TextColored(nm_ready(nm) and colors.owned or colors.title, nm.name);
    imgui.SameLine(700);
    if is_nm_tracked(zone_index, nm.name) then
        if imgui.SmallButton('UNTRACK##nm_track_btn') then remove_tracked_nm(zone_index, nm.name); end
    else
        if imgui.SmallButton('TRACK##nm_track_btn') then add_tracked_nm(zone_index, nm); end
    end
    if nm.location then
        imgui.SameLine();
        imgui.TextColored(colors.muted, nm.location);
    end
    imgui.Separator();

    if nm.spawn_type then
        imgui.TextColored(colors.header, 'Spawn:');
        imgui.SameLine();
        imgui.Text(nm.spawn_type);
    end
    if nm.respawn then
        imgui.SameLine(300);
        imgui.TextColored(colors.header, 'Respawn:');
        imgui.SameLine();
        imgui.Text(nm.respawn);
    end
    if nm.source_note then
        imgui.TextColored(colors.muted, nm.source_note);
    end

    imgui.Spacing();
    imgui.TextColored(colors.header, 'Requirements');
    imgui.Separator();
    if not nm.requirements or #nm.requirements == 0 then
        imgui.TextColored(colors.muted, 'No pop item or key item required.');
    else
        for _, req in ipairs(nm.requirements) do render_requirement(req, zone_index); end
    end

    render_nm_artwork(nm, zone_index);

    if nm.rewards and #nm.rewards > 0 then
        imgui.Spacing();
        imgui.TextColored(colors.header, 'Progression Rewards');
        imgui.Separator();
        for _, reward in ipairs(nm.rewards) do
            local owned = false;
            if reward.type == 'ki' then owned = has_keyitem(reward.name); end
            imgui.TextColored(reward.type == 'ki' and (owned and colors.owned or colors.missing) or colors.normal, reward.name);
            if reward.used_for then
                imgui.SameLine(530);
                imgui.TextColored(colors.source, 'Used for: ' .. reward.used_for);
            end
        end
    end

    render_catseye_drops(nm, zone_index);
end

local function render_zone(zone, zone_index)
    local list = sorted_nms(zone);
    if state.selected_nm[zone_index] == nil then state.selected_nm[zone_index] = 1; end
    local selected = state.selected_nm[zone_index];
    if selected > #list then selected = 1; state.selected_nm[zone_index] = 1; end

    imgui.TextColored(colors.header, zone.name);
    if zone.expansion then
        imgui.SameLine();
        imgui.TextColored(colors.muted, '(' .. zone.expansion .. ' of Abyssea)');
    end
    imgui.SameLine(740);
    imgui.TextColored(colors.muted, ('%d NMs'):format(#list));
    imgui.Separator();

    imgui.BeginChild('##nm_list_' .. zone_index, { 255, -1 }, true);
    imgui.TextColored(colors.title, 'NOTORIOUS MONSTERS');
    imgui.Separator();
    for i, entry in ipairs(list) do
        local nm = entry.nm;
        local ready = nm_ready(nm);
        local label = nm.name .. '##nm_' .. zone_index .. '_' .. i;
        if ready and nm.requirements and #nm.requirements > 0 then
            imgui.PushStyleColor(ImGuiCol_Text, colors.owned);
        end
        if imgui.Selectable(label, selected == i) then
            state.selected_nm[zone_index] = i;
            selected = i;
        end
        if ready and nm.requirements and #nm.requirements > 0 then imgui.PopStyleColor(); end
    end
    imgui.EndChild();

    imgui.SameLine();
    imgui.BeginChild('##nm_detail_' .. zone_index, { -1, -1 }, true);
    if #list > 0 then render_nm_detail(list[selected].nm, zone_index); end
    imgui.EndChild();
end

local function render_nm_pops()
    -- Three-panel NM browser: zones -> NM list -> selected NM details.
    -- This keeps zone navigation permanently visible instead of using a second tab bar.
    local zone_index = tonumber(state.selected_zone) or 1;
    if zone_index < 1 or zone_index > #data.zones then zone_index = 1; end
    state.selected_zone = zone_index;

    local zone_width = 228;
    local nm_width = 285;


    -- Left: Abyssea zone selector.
    imgui.BeginChild('##abyssea_zone_nav', { zone_width, -1 }, true);
    imgui.TextColored(colors.title, 'ABYSSEA ZONES');
    imgui.Separator();
    imgui.Spacing();

    -- Zone navigation uses the actual zone header artwork as the button face.
    -- Assets are pre-sized to UI resolution and loaded once, so the buttons are
    -- lightweight even though all nine are visible at the same time.
    local zone_card_width = zone_width - 18;
    local zone_card_height = 64;

    for i, zone in ipairs(data.zones) do
        local selected_zone = (i == zone_index);
        if render_zone_image_button(i, zone, selected_zone, zone_card_width, zone_card_height) then
            state.selected_zone = i;
            zone_index = i;
        end
    end
    imgui.EndChild();

    local zone = data.zones[zone_index];
    local list = sorted_nms(zone);
    if state.selected_nm[zone_index] == nil then state.selected_nm[zone_index] = 1; end
    local selected = state.selected_nm[zone_index];
    if selected < 1 or selected > #list then
        selected = 1;
        state.selected_nm[zone_index] = 1;
    end

    -- Middle: NM list for the selected zone.
    imgui.SameLine();
    imgui.BeginChild('##abyssea_nm_browser_' .. zone_index, { nm_width, -1 }, true);
    imgui.TextColored(colors.title, 'NOTORIOUS MONSTERS');
    imgui.SameLine();
    imgui.TextColored(colors.muted, ('(%d)'):format(#list));
    imgui.Separator();
    for i, entry in ipairs(list) do
        local nm = entry.nm;
        local ready = nm_ready(nm);
        local has_reqs = nm.requirements and #nm.requirements > 0;
        local label = nm.name .. '##nm_browser_' .. zone_index .. '_' .. i;
        if ready and has_reqs then imgui.PushStyleColor(ImGuiCol_Text, colors.owned); end
        if imgui.Selectable(label, selected == i) then
            state.selected_nm[zone_index] = i;
            selected = i;
        end
        if ready and has_reqs then imgui.PopStyleColor(); end
    end
    imgui.EndChild();

    -- Right: selected zone/NM detail.
    imgui.SameLine();
    imgui.BeginChild('##abyssea_nm_detail_panel_' .. zone_index, { -1, -1 }, true);
    imgui.TextColored(colors.header, zone.name);
    if zone.expansion then
        imgui.SameLine();
        imgui.TextColored(colors.muted, '(' .. zone.expansion .. ' of Abyssea)');
    end
    imgui.SameLine(650);
    imgui.TextColored(colors.muted, ('%d NMs'):format(#list));
    imgui.Separator();
    if #list > 0 then render_nm_detail(list[selected].nm, zone_index); end
    imgui.EndChild();
end

local function sorted_collection(list)
    local out = {};
    for _, entry in ipairs(list or {}) do out[#out + 1] = entry; end
    table.sort(out, function(a, b) return a.name:lower() < b.name:lower(); end);
    return out;
end

local function render_collection(list, empty_text, title)
    if #list == 0 then imgui.TextColored(colors.muted, empty_text); return; end

    local search = (title == 'ATMAS') and state.atma_search or state.abyssite_search;
    local search_label = (title == 'ATMAS') and 'Search Atmas...' or 'Search Abyssites...';

    imgui.SetNextItemWidth(360);
    imgui.InputText('##collection_search_' .. (title or 'list'), search, 128);
    if search[1] == '' and imgui.IsItemHovered() then
        imgui.SetTooltip(search_label);
    end
    imgui.SameLine();
    if imgui.SmallButton('CLEAR##collection_search_clear_' .. (title or 'list')) then search[1] = ''; end

    local all_rows = sorted_collection(list);
    local rows = {};
    local needle = normalize(search[1]);
    for _, entry in ipairs(all_rows) do
        local hay = normalize((entry.name or '') .. ' ' .. (entry.source or '') .. ' ' .. (entry.category or ''));
        if needle == '' or hay:find(needle, 1, true) then table.insert(rows, entry); end
    end

    local owned_count = 0;
    local total_owned = 0;
    for _, entry in ipairs(all_rows) do if has_keyitem(entry.name) then total_owned = total_owned + 1; end end
    for _, entry in ipairs(rows) do if has_keyitem(entry.name) then owned_count = owned_count + 1; end end

    imgui.TextColored(colors.header, title or 'COLLECTION');
    imgui.SameLine(740);
    if needle == '' then
        imgui.TextColored(colors.muted, ('%d / %d owned'):format(total_owned, #all_rows));
    else
        imgui.TextColored(colors.muted, ('%d results  |  %d / %d total owned'):format(#rows, total_owned, #all_rows));
    end
    imgui.Separator();
    imgui.TextColored(colors.muted, 'STATUS');
    imgui.SameLine(95); imgui.TextColored(colors.muted, 'NAME');
    imgui.SameLine(555); imgui.TextColored(colors.muted, 'WHERE IT COMES FROM');
    imgui.Separator();

    imgui.BeginChild('##collection_' .. (title or 'list'), { -1, -1 }, false);
    for i, entry in ipairs(rows) do
        local owned = has_keyitem(entry.name);
        local display = entry.name;
        if normalize(entry.name) == normalize('Lunar abyssite') then
            local count, total = keyitem_count(entry.name);
            if total > 1 then display = ('%s  (%d/%d)'):format(entry.name, count, total); owned = count > 0; end
        end
        imgui.TextColored(owned and colors.owned or colors.missing, owned and 'OWNED' or 'MISSING');
        imgui.SameLine(95);
        imgui.TextColored(owned and colors.owned or colors.missing, display);
        if entry.category then
            imgui.SameLine(445);
            imgui.TextColored(colors.muted, '[' .. entry.category .. ']');
        end
        if entry.source then
            imgui.SameLine(555);
            imgui.TextColored(colors.source, entry.source);
        end
        if i < #rows then imgui.Separator(); end
    end
    if #rows == 0 then imgui.TextColored(colors.muted, 'No matches.'); end
    imgui.EndChild();
end

local function render_compact()
    local zone = data.zones[state.selected_zone] or data.zones[1];
    local list = sorted_nms(zone);
    if state.selected_nm[state.selected_zone] == nil then state.selected_nm[state.selected_zone] = 1; end
    local selected = state.selected_nm[state.selected_zone];
    if selected > #list then selected = 1; state.selected_nm[state.selected_zone] = 1; end

    imgui.TextColored(colors.title, 'ABYSSEA');
    imgui.SameLine();
    imgui.TextColored(colors.muted, zone.short_name or zone.name);
    imgui.SameLine(315);
    if imgui.SmallButton('FULL##compact_full') then state.compact_mode[1] = false; end
    imgui.Separator();

    -- Small zone selector. Cycling keeps the compact window narrow.
    if imgui.SmallButton('<##compact_prev_zone') then
        state.selected_zone = state.selected_zone - 1;
        if state.selected_zone < 1 then state.selected_zone = #data.zones; end
    end
    imgui.SameLine();
    imgui.TextColored(colors.header, zone.short_name or zone.name);
    imgui.SameLine();
    if imgui.SmallButton('>##compact_next_zone') then
        state.selected_zone = state.selected_zone + 1;
        if state.selected_zone > #data.zones then state.selected_zone = 1; end
    end
    imgui.Separator();

    imgui.BeginChild('##compact_nm_list', { 150, -1 }, true);
    for i, entry in ipairs(list) do
        local nm = entry.nm;
        local ready = nm_ready(nm);
        if ready and nm.requirements and #nm.requirements > 0 then imgui.PushStyleColor(ImGuiCol_Text, colors.owned); end
        if imgui.Selectable(nm.name .. '##compact_nm_' .. i, selected == i) then
            state.selected_nm[state.selected_zone] = i;
            selected = i;
        end
        if ready and nm.requirements and #nm.requirements > 0 then imgui.PopStyleColor(); end
    end
    imgui.EndChild();

    imgui.SameLine();
    imgui.BeginChild('##compact_detail', { -1, -1 }, true);
    if #list > 0 then
        local nm = list[selected].nm;
        imgui.TextColored(nm_ready(nm) and colors.owned or colors.title, nm.name);
        imgui.SameLine(300);
        if is_nm_tracked(state.selected_zone, nm.name) then
            if imgui.SmallButton('UNTRACK##compact_track') then remove_tracked_nm(state.selected_zone, nm.name); end
        else
            if imgui.SmallButton('TRACK##compact_track') then add_tracked_nm(state.selected_zone, nm); end
        end
        imgui.Separator();
        if not nm.requirements or #nm.requirements == 0 then
            imgui.TextColored(colors.muted, nm.spawn_type or 'No tracked requirement.');
        else
            for _, req in ipairs(nm.requirements) do
                local owned, _, info = req_owned(req);
                local c = owned and colors.owned or colors.missing;
                imgui.TextColored(c, owned and 'OWNED' or 'MISSING');
                imgui.SameLine(72);
                imgui.TextColored(c, req.name or 'Unknown');
                if req.source and req.source ~= '' then
                    imgui.TextColored(colors.source, '  From: ' .. req.source);
                end
                if req.type == 'item' and owned and info ~= nil then
                    imgui.TextColored(colors.muted, ('  x%d  %s'):format(info.count or 1, table.concat(info.locations or {}, ', ')));
                end
            end
        end
    end
    imgui.EndChild();
end


-- Retail Abyssea zone/message mapping used by the incoming 0x02A packet.
-- CatsEyeXI uses the same Abyssea messages, so this stays passive and local:
-- no outgoing packets, no polling, no injected requests.
local abyssea_messages = {
    [15]  = 7315, -- Konschtat
    [132] = 7315, -- La Theine
    [45]  = 7315, -- Tahrongi
    [215] = 7215, -- Attohwa
    [216] = 7315, -- Misareaux
    [217] = 7315, -- Vunkerl
    [218] = 7315, -- Altepa
    [253] = 7215, -- Uleguerand
    [254] = 7315, -- Grauberg
};

local function read_u16_le(packet, offset)
    if packet == nil or #packet < offset + 2 then return nil; end
    local a, b = packet:byte(offset + 1, offset + 2);
    if a == nil or b == nil then return nil; end
    return a + b * 0x100;
end

local function read_u32_le(packet, offset)
    if packet == nil or #packet < offset + 4 then return nil; end
    local a, b, c, d = packet:byte(offset + 1, offset + 4);
    if a == nil then return nil; end
    return a + (b or 0) * 0x100 + (c or 0) * 0x10000 + (d or 0) * 0x1000000;
end

local function current_zone_id()
    local ok, zone_id = pcall(function()
        local party = AshitaCore:GetMemoryManager():GetParty();
        if party == nil then return 0; end
        return party:GetMemberZone(0) or 0;
    end);
    return ok and tonumber(zone_id) or 0;
end

local function refresh_abyssea_zone_state()
    local zid = current_zone_id();
    state.abyssea_zone_id = zid;
    state.abyssea_zone = abyssea_messages[zid] ~= nil;
    if not state.abyssea_zone then
        state.visitant_minutes = nil;
        state.visitant_anchor = 0;
        state.lights.pearlescent = 0;
        state.lights.azure = 0;
        state.lights.ruby = 0;
        state.lights.amber = 0;
        state.lights.golden = 0;
        state.lights.silvery = 0;
        state.lights.ebon = 0;
    end
end

local function set_visitant_minutes(value)
    value = tonumber(value);
    if value == nil then return; end
    state.visitant_minutes = math.max(0, value);
    state.visitant_anchor = os.clock();
end

local function add_visitant_minutes(value)
    value = tonumber(value);
    if value == nil then return; end
    local current = state.visitant_minutes or 0;
    if state.visitant_minutes ~= nil and state.visitant_anchor > 0 then
        current = math.max(0, current - ((os.clock() - state.visitant_anchor) / 60));
    end
    state.visitant_minutes = current + value;
    state.visitant_anchor = os.clock();
end

local function parse_abyssea_status_packet(packet)
    if not state.abyssea_zone or packet == nil or #packet < 0x1C then return; end
    local offset = abyssea_messages[state.abyssea_zone_id];
    if offset == nil then return; end

    -- 0x02A: header 0x00-0x03, Player 0x04, Param1..4 0x08..0x17,
    -- Player Index 0x18, Message ID 0x1A.
    local p1 = read_u32_le(packet, 0x08) or 0;
    local p2 = read_u32_le(packet, 0x0C) or 0;
    local p3 = read_u32_le(packet, 0x10) or 0;
    local p4 = read_u32_le(packet, 0x14) or 0;
    local msg = read_u16_le(packet, 0x1A);
    if msg == nil then return; end
    msg = bit.band(msg, 0x3FFF);
    local rel = msg - offset;

    if rel == 0 then
        state.lights.pearlescent = p1;
        state.lights.ebon = p2;
        state.lights.golden = p3;
        state.lights.silvery = p4;
    elseif rel == 1 then
        state.lights.azure = p1;
        state.lights.ruby = p2;
        state.lights.amber = p3;
    elseif rel == 9 or rel == 10 or rel == 45 then
        set_visitant_minutes(p1);
    elseif rel == 12 then
        add_visitant_minutes(p1);
    elseif rel == 183 then
        state.lights.pearlescent = math.min(state.lights.pearlescent + 5, 230);
    elseif rel == 184 then
        state.lights.golden = math.min(state.lights.golden + 5 * (p1 + 1), 200);
    elseif rel == 185 then
        state.lights.silvery = math.min(state.lights.silvery + 5 * (p1 + 1), 200);
    elseif rel == 186 then
        state.lights.ebon = math.min(state.lights.ebon + p1 + 1, 200);
    elseif rel == 187 then
        state.lights.azure = math.min(state.lights.azure + 8, 255);
    elseif rel == 188 then
        state.lights.ruby = math.min(state.lights.ruby + 8, 255);
    elseif rel == 189 then
        state.lights.amber = math.min(state.lights.amber + 8, 255);
    end
end



-- Ashita's Points addon tracks Abyssea status from the incoming chat text that
-- FFXI already renders to the client.  Keep the 0x02A parser above as a passive
-- fallback, but use the same text-driven path here because it is reliable on
-- CatsEyeXI and does not send or request anything from the server.
local abyssea_light_gains = {
    pearlescent = { feeble = 0, faint = 5, mild = 10, strong = 15, intense = 0, max = 230 },
    golden      = { feeble = 0, faint = 5, mild = 10, strong = 15, intense = 0, max = 200 },
    silvery     = { feeble = 0, faint = 5, mild = 10, strong = 15, intense = 0, max = 200 },
    ebon        = { feeble = 0, faint = 1, mild = 2, strong = 3, intense = 0, max = 200 },
    azure       = { feeble = 8, faint = 16, mild = 24, strong = 32, intense = 64, max = 255 },
    ruby        = { feeble = 8, faint = 16, mild = 24, strong = 32, intense = 64, max = 255 },
    amber       = { feeble = 8, faint = 16, mild = 24, strong = 32, intense = 64, max = 255 },
};

local function set_visitant_seconds(value)
    value = tonumber(value);
    if value == nil then return; end
    state.visitant_minutes = math.max(0, value) / 60;
    state.visitant_anchor = os.clock();
end

local function update_abyssea_status_from_text(message)
    if not state.abyssea_zone or message == nil then return; end

    -- Match the same client messages used successfully by the Ashita Points
    -- addon.  regex.search is used instead of exact-line matching so timestamps,
    -- chat coloring and surrounding text do not matter.
    local results = ashita.regex.search(message, 'visitant status will wear off in (\\d+) (minute|minutes|second|seconds)');
    if results ~= nil then
        local amount = tonumber(results[1][2]);
        local unit = tostring(results[1][3] or ''):lower();
        if amount ~= nil then
            if unit == 'minute' or unit == 'minutes' then
                set_visitant_seconds(amount * 60);
            else
                set_visitant_seconds(amount);
            end
        end
        return;
    end

    results = ashita.regex.search(message, 'Pearlescent: (\\d+) / Ebon: (\\d+)');
    if results ~= nil then
        state.lights.pearlescent = tonumber(results[1][2]) or state.lights.pearlescent;
        state.lights.ebon = tonumber(results[1][3]) or state.lights.ebon;
    end

    results = ashita.regex.search(message, 'Golden: (\\d+) / Silvery: (\\d+)');
    if results ~= nil then
        state.lights.golden = tonumber(results[1][2]) or state.lights.golden;
        state.lights.silvery = tonumber(results[1][3]) or state.lights.silvery;
    end

    results = ashita.regex.search(message, 'Azure: (\\d+) / Ruby: (\\d+) / Amber: (\\d+)');
    if results ~= nil then
        state.lights.azure = tonumber(results[1][2]) or state.lights.azure;
        state.lights.ruby = tonumber(results[1][3]) or state.lights.ruby;
        state.lights.amber = tonumber(results[1][4]) or state.lights.amber;
    end

    results = ashita.regex.search(message, 'body emits a (feeble|faint|mild|strong|intense) (pearlescent|golden|silvery|ebon|azure|ruby|amber) light!');
    if results == nil then
        results = ashita.regex.search(message, 'body emits an (feeble|faint|mild|strong|intense) (pearlescent|golden|silvery|ebon|azure|ruby|amber) light!');
    end
    if results ~= nil then
        local strength = tostring(results[1][2] or ''):lower();
        local light = tostring(results[1][3] or ''):lower();
        local info = abyssea_light_gains[light];
        if info ~= nil and info[strength] ~= nil then
            state.lights[light] = math.min((state.lights[light] or 0) + info[strength], info.max);
        end
    end
end
local function visitant_time_text()
    if state.visitant_minutes == nil then return '--:--'; end
    local seconds = math.floor(state.visitant_minutes * 60);
    if state.visitant_anchor > 0 then
        seconds = math.max(0, seconds - math.floor(os.clock() - state.visitant_anchor));
    end
    local h = math.floor(seconds / 3600);
    local m = math.floor((seconds % 3600) / 60);
    local sec = seconds % 60;
    if h > 0 then return ('%d:%02d:%02d'):format(h, m, sec); end
    return ('%02d:%02d'):format(m, sec);
end

local function render_abyssea_statusbar()
    if not state.statusbar_open[1] or not state.abyssea_zone or state.zoning then return; end

    -- Wide but intentionally thin. Fixed columns use the available width instead
    -- of bunching all light values against the left side of the bar.
    imgui.SetNextWindowSize({ 960, 34 }, ImGuiCond_Always);
    imgui.SetNextWindowSizeConstraints({ 960, 34 }, { 1200, 34 });
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 10, 6 });
    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, 3);
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 1);
    imgui.PushStyleColor(ImGuiCol_WindowBg, { 0.018, 0.028, 0.045, 0.94 });
    imgui.PushStyleColor(ImGuiCol_Border, { 0.35, 0.30, 0.72, 0.90 });

    local flags = bit.bor(ImGuiWindowFlags_NoTitleBar, ImGuiWindowFlags_NoResize,
        ImGuiWindowFlags_NoScrollbar, ImGuiWindowFlags_NoCollapse);
    if imgui.Begin('Abyssea Status##integready_statusbar', state.statusbar_open, flags) then
        imgui.TextColored({ 0.77, 0.56, 1.00, 1.00 }, 'ABYSSEA');

        imgui.SameLine(105);
        imgui.TextColored(colors.muted, 'TIME');
        imgui.SameLine(); imgui.TextColored(colors.gold, visitant_time_text());

        imgui.SameLine(220);
        imgui.TextColored({ 0.90, 0.90, 0.96, 1.00 }, 'PEARL');
        imgui.SameLine(); imgui.TextColored(colors.normal, tostring(state.lights.pearlescent));

        imgui.SameLine(315);
        imgui.TextColored({ 0.20, 0.62, 1.00, 1.00 }, 'AZURE');
        imgui.SameLine(); imgui.TextColored(colors.normal, tostring(state.lights.azure));

        imgui.SameLine(410);
        imgui.TextColored({ 1.00, 0.28, 0.30, 1.00 }, 'RUBY');
        imgui.SameLine(); imgui.TextColored(colors.normal, tostring(state.lights.ruby));

        imgui.SameLine(495);
        imgui.TextColored({ 1.00, 0.68, 0.22, 1.00 }, 'AMBER');
        imgui.SameLine(); imgui.TextColored(colors.normal, tostring(state.lights.amber));

        imgui.SameLine(595);
        imgui.TextColored({ 1.00, 0.82, 0.30, 1.00 }, 'GOLD');
        imgui.SameLine(); imgui.TextColored(colors.normal, tostring(state.lights.golden));

        imgui.SameLine(675);
        imgui.TextColored({ 0.76, 0.82, 0.92, 1.00 }, 'SILVER');
        imgui.SameLine(); imgui.TextColored(colors.normal, tostring(state.lights.silvery));

        imgui.SameLine(775);
        imgui.TextColored({ 0.57, 0.45, 0.72, 1.00 }, 'EBON');
        imgui.SameLine(); imgui.TextColored(colors.normal, tostring(state.lights.ebon));
    end
    imgui.End();

    imgui.PopStyleColor(2);
    imgui.PopStyleVar(3);
end

ashita.events.register('load', 'abyssea_load', function()
    refresh_abyssea_zone_state();
    rebuild_lookups();
    refresh_current_ownership();
    initialize_monitor();
end);

-- Event-driven ownership updates. These handlers only react to packets that
-- FFXI is already sending to the client; the addon never polls or requests
-- inventory / key-item data from the server.
ashita.events.register('text_in', 'abyssea_status_text_in', function (e)
    if e == nil or e.injected then return; end
    update_abyssea_status_from_text(e.message);
end);

ashita.events.register('packet_in', 'abyssea_packet_in', function(e)
    -- Zone In: FFXI rebuilds inventory over a burst that may contain pauses.
    -- Do not treat any of those packets as acquisitions. Keep a hard mute window
    -- across the whole zone-load period and continually refresh the ownership
    -- baseline silently as inventory / KI packets arrive.
    if e.id == 0x000A then
        state.zoning = true;
        state.abyssea_zone = false;
        state.monitor_ready = false;
        state.item_event_generation = state.item_event_generation + 1;
        state.keyitem_event_generation = state.keyitem_event_generation + 1;
        state.zone_sync_generation = state.zone_sync_generation + 1;
        local zone_generation = state.zone_sync_generation;
        state.zone_alert_mute_until = os.clock() + 60.0;
        state.packet_keyitems = {};
        state.packet_keyitem_pages = {};

        ashita.tasks.once(1.50, function()
            if zone_generation ~= state.zone_sync_generation then return; end
            refresh_abyssea_zone_state();
        end);

        -- After the one-minute zone-load grace period, take one final silent snapshot.
        -- The monitor only becomes live after this point.
        ashita.tasks.once(60.25, function()
            if zone_generation ~= state.zone_sync_generation then return; end
            refresh_abyssea_zone_state();
            rebuild_lookups();
            refresh_current_ownership();
            initialize_monitor();
            state.zoning = false;
        end);
        return;
    end

    -- 0x02A is the standard retail Abyssea status/light message packet.
    if e.id == 0x002A then
        parse_abyssea_status_packet(e.data);
        return;
    end

    -- 0x01E Modify Inventory, 0x01F Item Assign, 0x020 Item Update.
    if e.id == 0x001E or e.id == 0x001F or e.id == 0x0020 then
        if state.zoning or os.clock() < (state.zone_alert_mute_until or 0) then
            -- Apply this packet to the displayed ownership state, but never compare
            -- it against the pre-zone snapshot. Re-baseline silently after Ashita
            -- has applied the packet to local memory.
            state.item_event_generation = state.item_event_generation + 1;
            local generation = state.item_event_generation;
            ashita.tasks.once(0.25, function()
                if generation ~= state.item_event_generation then return; end
                scan_items(true);
                for key, name in pairs(gather_pop_item_names()) do
                    state.item_snapshot[key] = current_item_count_by_name(name);
                end
            end);
            return;
        end
        queue_item_event_refresh();
        return;
    end

    -- 0x055 Key Item Log. Parse immediately, but during zone load only use the
    -- result to refresh the silent baseline; do not fire acquisition alerts.
    if e.id == 0x0055 then
        parse_keyitem_log_packet(e.data);
        if state.zoning or os.clock() < (state.zone_alert_mute_until or 0) then
            state.keyitem_event_generation = state.keyitem_event_generation + 1;
            local generation = state.keyitem_event_generation;
            ashita.tasks.once(0.15, function()
                if generation ~= state.keyitem_event_generation then return; end
                for key, entry in pairs(gather_watched_keyitems()) do
                    state.keyitem_snapshot[key] = keyitem_count(entry.name);
                end
            end);
            return;
        end
        queue_keyitem_event_refresh();
        return;
    end
end);

ashita.events.register('command', 'abyssea_command', function(e)
    local args = e.command:args();
    if #args == 0 then return; end
    local cmd = args[1]:lower();
    if cmd ~= '/abyssea' and cmd ~= '/aby' then return; end
    e.blocked = true;

    if #args == 1 or args[2]:lower() == 'toggle' then
        state.open[1] = not state.open[1];
    elseif args[2]:lower() == 'show' then
        state.open[1] = true;
    elseif args[2]:lower() == 'hide' then
        state.open[1] = false;
    elseif args[2]:lower() == 'refresh' then
        rebuild_lookups(); refresh_current_ownership(); initialize_monitor();
        print('[Abyssea] Ownership refreshed from local client state and saved packet data.');
    elseif args[2]:lower() == 'mode' then
        if #args >= 3 and args[3]:lower() == 'compact' then
            state.compact_mode[1] = true;
            print('[Abyssea] Compact mode enabled.');
        elseif #args >= 3 and args[3]:lower() == 'full' then
            state.compact_mode[1] = false;
            print('[Abyssea] Full mode enabled.');
        else
            state.compact_mode[1] = not state.compact_mode[1];
            print(('[Abyssea] %s mode enabled.'):format(state.compact_mode[1] and 'Compact' or 'Full'));
        end
    elseif args[2]:lower() == 'track' then
        if #args < 3 then
            print('[Abyssea] Usage: /aby track <NM name>');
        else
            local wanted = table.concat(args, ' ', 3);
            local found = nil;
            local found_zone = nil;
            for zi, zone in ipairs(data.zones) do
                for _, nm in ipairs(zone.nms or {}) do
                    if normalize(nm.name) == normalize(wanted) then found = nm; found_zone = zi; break; end
                end
                if found ~= nil then break; end
            end
            if found ~= nil then
                add_tracked_nm(found_zone, found);
                print(('[Abyssea] Tracking NM: %s'):format(found.name));
            else
                print(('[Abyssea] NM not found: %s'):format(wanted));
            end
        end
    elseif args[2]:lower() == 'untrack' then
        if #args < 3 then
            print('[Abyssea] Usage: /aby untrack <NM name>');
        else
            local wanted = table.concat(args, ' ', 3);
            local removed = false;
            for key, entry in pairs(state.tracked_nms) do
                if normalize(entry.name) == normalize(wanted) then state.tracked_nms[key] = nil; removed = true; end
            end
            print(removed and ('[Abyssea] Stopped tracking: ' .. wanted) or ('[Abyssea] NM was not pinned: ' .. wanted));
        end
    elseif args[2]:lower() == 'tracker' then
        if #args >= 3 and args[3]:lower() == 'clear' then
            state.tracked_nms = {};
            print('[Abyssea] Pinned NM tracker cleared.');
        elseif #args >= 3 and args[3]:lower() == 'on' then
            state.tracker_open[1] = true;
            print('[Abyssea] Pinned NM tracker shown.');
        elseif #args >= 3 and args[3]:lower() == 'off' then
            state.tracker_open[1] = false;
            print('[Abyssea] Pinned NM tracker hidden.');
        else
            state.tracker_open[1] = not state.tracker_open[1];
        end
    elseif args[2]:lower() == 'proctracker' then
        local subtype = (#args >= 3) and args[3]:lower() or nil;
        local action = (#args >= 4) and args[4]:lower() or nil;
        local function set_toggle(ref, act)
            if act == 'on' then ref[1] = true;
            elseif act == 'off' then ref[1] = false;
            else ref[1] = not ref[1]; end
        end
        if subtype == 'red' then
            set_toggle(state.proc_track_red, action);
            if state.proc_track_red[1] then state.proc_tracker_open[1] = true; end
            print(('[Abyssea] Proc Tracker Red %s.'):format(state.proc_track_red[1] and 'enabled' or 'disabled'));
        elseif subtype == 'blue' then
            set_toggle(state.proc_track_blue, action);
            if state.proc_track_blue[1] then state.proc_tracker_open[1] = true; end
            print(('[Abyssea] Proc Tracker Blue %s.'):format(state.proc_track_blue[1] and 'enabled' or 'disabled'));
        elseif subtype == 'yellow' then
            set_toggle(state.proc_track_yellow, action);
            if state.proc_track_yellow[1] then state.proc_tracker_open[1] = true; end
            print(('[Abyssea] Proc Tracker Yellow %s.'):format(state.proc_track_yellow[1] and 'enabled' or 'disabled'));
        elseif subtype == 'on' then
            state.proc_tracker_open[1] = true;
            print('[Abyssea] Proc Tracker shown.');
        elseif subtype == 'off' then
            state.proc_tracker_open[1] = false;
            print('[Abyssea] Proc Tracker hidden.');
        elseif subtype == 'clear' then
            reset_proc_map(state.proc_red); reset_proc_map(state.proc_blue); reset_proc_map(state.proc_yellow);
            print('[Abyssea] Proc Tracker checklists reset.');
        else
            state.proc_tracker_open[1] = not state.proc_tracker_open[1];
            print(('[Abyssea] Proc Tracker %s.'):format(state.proc_tracker_open[1] and 'shown' or 'hidden'));
        end
    elseif args[2]:lower() == 'bar' or args[2]:lower() == 'statusbar' then
        if #args >= 3 and args[3]:lower() == 'on' then
            state.statusbar_open[1] = true;
            persisted.statusbar_enabled = true; pcall(function() settings.save(); end);
            print('[Abyssea] Status bar enabled.');
        elseif #args >= 3 and args[3]:lower() == 'off' then
            state.statusbar_open[1] = false;
            persisted.statusbar_enabled = false; pcall(function() settings.save(); end);
            print('[Abyssea] Status bar disabled.');
        else
            state.statusbar_open[1] = not state.statusbar_open[1];
            persisted.statusbar_enabled = state.statusbar_open[1]; pcall(function() settings.save(); end);
            print(('[Abyssea] Status bar %s.'):format(state.statusbar_open[1] and 'enabled' or 'disabled'));
        end
    elseif args[2]:lower() == 'sound' then
        if #args >= 3 and args[3]:lower() == 'on' then
            state.sounds_enabled[1] = true;
            print('[Abyssea] Acquisition sounds enabled.');
        elseif #args >= 3 and args[3]:lower() == 'off' then
            state.sounds_enabled[1] = false;
            print('[Abyssea] Acquisition sounds disabled.');
        else
            state.sounds_enabled[1] = not state.sounds_enabled[1];
            print(('[Abyssea] Acquisition sounds %s.'):format(state.sounds_enabled[1] and 'enabled' or 'disabled'));
        end
    end
end);

ashita.events.register('d3d_present', 'abyssea_present', function()
    push_theme();
    render_abyssea_statusbar();
    render_tracker_window();
    render_proc_tracker_window();
    if not state.open[1] then pop_theme(); return; end
    if state.compact_mode[1] then
        imgui.SetNextWindowSize({ 560, 390 }, ImGuiCond_FirstUseEver);
        imgui.SetNextWindowSizeConstraints({ 440, 280 }, { 800, 760 });
    else
        imgui.SetNextWindowSize({ 1320, 900 }, ImGuiCond_FirstUseEver);
        imgui.SetNextWindowSizeConstraints({ 1040, 700 }, { 1850, 1350 });
    end

    if imgui.Begin('Abyssea Tracker##integready', state.open) then
        if state.compact_mode[1] then
            render_compact();
        else
            render_brand_banner();
            imgui.Spacing();

            -- Compact action strip beneath the logo keeps controls accessible
            -- while allowing the artwork to remain the visual focus.
            imgui.PushStyleColor(ImGuiCol_ChildBg, { 0.018, 0.050, 0.078, 0.98 });
            imgui.BeginChild('##aby_actionbar', { -1, 38 }, true);
            imgui.TextColored(colors.muted, 'by IntegReady');
            imgui.SameLine(150);
            if imgui.Button('REFRESH##aby_refresh', { 92, 25 }) then
                refresh_current_ownership();
                initialize_monitor();
                print('[Abyssea] Ownership refreshed from local client state and saved packet data.');
            end
            imgui.SameLine();
            imgui.TextColored(state.sounds_enabled[1] and colors.owned or colors.muted, state.sounds_enabled[1] and 'SOUND ON' or 'SOUND OFF');
            imgui.SameLine(1000);
            imgui.TextColored(colors.muted, 'ABYSSEA PROGRESSION COMPANION');
            imgui.EndChild();
            imgui.PopStyleColor();
            imgui.Spacing();

            if imgui.BeginTabBar('##abyssea_tabs') then
                if imgui.BeginTabItem('NM Pops') then render_nm_pops(); imgui.EndTabItem(); end
                if imgui.BeginTabItem('Procs') then render_procs(); imgui.EndTabItem(); end
                if imgui.BeginTabItem('Abyssites') then render_collection(data.abyssites, 'No abyssites found.', 'ABYSSITES'); imgui.EndTabItem(); end
                if imgui.BeginTabItem('Atmas') then render_collection(data.atmas, 'No atmas found.', 'ATMAS'); imgui.EndTabItem(); end
                if imgui.BeginTabItem('Settings') then render_sound_settings(); imgui.EndTabItem(); end
                imgui.EndTabBar();
            end
        end
    end
    imgui.End();
    pop_theme();
end);
