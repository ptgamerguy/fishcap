--[[
    fishcap - Daily fishing counter for Phoenix XI (Ashita v4)
]]

addon.name      = 'fishcap';
addon.author    = 'Darklighter';
addon.version   = '1.6';
addon.desc      = 'Tracks daily fishing cap (200) including items and line breaks.';
addon.commands  = {'fishcap', 'fcap'};

require('common');
local chat     = require('chat');
local imgui    = require('imgui');
local settings = require('settings');

local default_settings = T{
    count      = 0,
    last_reset = os.date('%Y-%m-%d'),
    cap        = 200,
    visible    = true,
    pos_x      = 100,
    pos_y      = 100,
};

local fishcap = T{
    settings = nil,
    last_count_time = 0,
    player_name = '',
};

-- Patterns (only used after confirming it is your name)
local count_patterns = T{
    'caught a ',
    'caught an ',
    'your line breaks',
    'your rod breaks',
};

local function clean_message(msg)
    msg = msg:gsub('[\x00-\x1F]', '');
    msg = msg:gsub('|c%x%x%x%x%x%x%x%x', '');
    msg = msg:gsub('|r', '');
    return msg:lower();
end

local function get_player_name()
    local player = GetPlayerEntity();
    if player ~= nil and player.Name ~= nil then
        return player.Name:lower();
    end
    return '';
end

local function check_daily_reset()
    local today = os.date('%Y-%m-%d');
    if fishcap.settings.last_reset ~= today then
        fishcap.settings.count = 0;
        fishcap.settings.last_reset = today;
        settings.save();
        print(chat.header('fishcap'):append(chat.message('Daily counter reset.')));
    end
end

local function print_status()
    local color = 207;
    if fishcap.settings.count >= fishcap.settings.cap then
        color = 167;
    elseif fishcap.settings.count >= fishcap.settings.cap - 20 then
        color = 208;
    end
    print(chat.header('fishcap'):append(chat.color1(color, string.format('%d / %d', fishcap.settings.count, fishcap.settings.cap))));
end

--------------------------------------------------
-- Events
--------------------------------------------------

ashita.events.register('load', 'load_cb', function ()
    fishcap.settings = settings.load(default_settings);
    fishcap.player_name = get_player_name();
    check_daily_reset();
    print(chat.header('fishcap'):append(chat.message('Loaded. Type /fishcap help')));
end);

ashita.events.register('unload', 'unload_cb', function ()
    settings.save();
end);

-- Update player name if it was empty at load
ashita.events.register('packet_in', 'packet_in_cb', function (e)
    if fishcap.player_name == '' then
        fishcap.player_name = get_player_name();
    end
end);

ashita.events.register('text_in', 'text_in_cb', function (e)
    if e.injected then return; end

    check_daily_reset();

    local lower = clean_message(e.message);

    -- Ignore "didn't catch" messages
    if lower:find("didn't catch", 1, true) or lower:find('did not catch', 1, true) then
        return;
    end

    -- Only count if the message starts with our own name
    -- or is a "Your line/rod breaks" message
    local is_mine = false;

    if fishcap.player_name ~= '' and lower:find('^' .. fishcap.player_name, 1) then
        is_mine = true;
    end

    -- Always allow the "Your line breaks" style messages
    if lower:find('your line breaks', 1, true) or lower:find('your rod breaks', 1, true) then
        is_mine = true;
    end

    if not is_mine then
        return;
    end

    for _, pat in ipairs(count_patterns) do
        if lower:find(pat, 1, true) then
            -- 2 second cooldown to prevent double counting
            local now = os.clock();
            if now - fishcap.last_count_time < 2.0 then
                return;
            end
            fishcap.last_count_time = now;

            fishcap.settings.count = fishcap.settings.count + 1;
            settings.save();

            if fishcap.settings.count >= fishcap.settings.cap then
                print(chat.header('fishcap'):append(chat.error(string.format('CAP REACHED: %d / %d', fishcap.settings.count, fishcap.settings.cap))));
            elseif fishcap.settings.count % 10 == 0 or fishcap.settings.count >= fishcap.settings.cap - 15 then
                print_status();
            end
            break;
        end
    end
end);

ashita.events.register('command', 'command_cb', function (e)
    local args = e.command:args();
    if (#args == 0 or not args[1]:any('/fishcap', '/fcap')) then
        return;
    end

    e.blocked = true;
    local cmd = args[2] and args[2]:lower() or 'status';

    if cmd == 'reset' or cmd == 'r' then
        fishcap.settings.count = 0;
        fishcap.settings.last_reset = os.date('%Y-%m-%d');
        settings.save();
        print(chat.header('fishcap'):append(chat.message('Counter reset to 0.')));

    elseif cmd == 'set' and args[3] then
        local n = tonumber(args[3]);
        if n then
            fishcap.settings.count = math.max(0, math.floor(n));
            settings.save();
            print_status();
        end

    elseif cmd == 'show' then
        fishcap.settings.visible = true;
        settings.save();

    elseif cmd == 'hide' then
        fishcap.settings.visible = false;
        settings.save();

    elseif cmd == 'help' then
        print(chat.header('fishcap'):append(chat.message('Commands:')));
        print(chat.message('  /fishcap          - show current count'));
        print(chat.message('  /fishcap reset    - reset counter'));
        print(chat.message('  /fishcap set <n>  - set counter'));
        print(chat.message('  /fishcap show/hide'));

    else
        check_daily_reset();
        print_status();
    end
end);

-- On-screen display
ashita.events.register('d3d_present', 'present_cb', function ()
    if not fishcap.settings or not fishcap.settings.visible then return; end

    imgui.SetNextWindowPos({ fishcap.settings.pos_x, fishcap.settings.pos_y }, ImGuiCond_FirstUseEver);
    imgui.SetNextWindowBgAlpha(0.65);

    local flags = bit.bor(
        ImGuiWindowFlags_NoTitleBar,
        ImGuiWindowFlags_NoResize,
        ImGuiWindowFlags_AlwaysAutoResize,
        ImGuiWindowFlags_NoFocusOnAppearing,
        ImGuiWindowFlags_NoNav
    );

    if imgui.Begin('fishcap##display', true, flags) then
        local count = fishcap.settings.count;
        local cap   = fishcap.settings.cap;
        local text  = string.format('Fishing: %d / %d', count, cap);

        if count >= cap then
            imgui.TextColored({ 1.0, 0.25, 0.25, 1.0 }, text);
        elseif count >= cap - 20 then
            imgui.TextColored({ 1.0, 0.85, 0.2, 1.0 }, text);
        else
            imgui.TextColored({ 0.4, 1.0, 0.4, 1.0 }, text);
        end

        local x, y = imgui.GetWindowPos();
        if x ~= fishcap.settings.pos_x or y ~= fishcap.settings.pos_y then
            fishcap.settings.pos_x = x;
            fishcap.settings.pos_y = y;
            settings.save();
        end
    end
    imgui.End();
end);