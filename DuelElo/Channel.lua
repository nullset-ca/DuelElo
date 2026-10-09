-- Channel.lua: hidden custom channel for realm-wide stats sharing (leaderboard).
local _, ns = ...

local CHANNEL_NAME = "DuelEloLadder"  -- hidden custom channel for realm-wide stats
local CHANNEL_SHARE_EVERY = 1800  -- re-announce our stats this often (seconds, +-jitter)

local Channel = {}
ns.Channel = Channel

local channelId  -- set once we've joined the hidden channel

-- The number changes when channels are reordered, so read it at send time.
function Channel.Id()
    if not channelId then return nil end
    local id = GetChannelName(CHANNEL_NAME)
    if type(id) == "number" and id > 0 and not ns.IsSecret(id) then channelId = id end
    return channelId
end

-- Hide the channel from every chat window and swallow its join/leave notices.
local function hideChannel()
    if ChatFrame_RemoveChannel and NUM_CHAT_WINDOWS then
        for i = 1, NUM_CHAT_WINDOWS do
            local cf = _G["ChatFrame" .. i]
            if cf then pcall(ChatFrame_RemoveChannel, cf, CHANNEL_NAME) end
        end
    end
end

local function isOurChannelNotice(_, _, ...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "string" and not ns.IsSecret(v) and v:find(CHANNEL_NAME, 1, true) then return true end
    end
    return false
end

if ChatFrame_AddMessageEventFilter then
    ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL_NOTICE", isOurChannelNotice)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL_NOTICE_USER", isOurChannelNotice)
end

-- Keep our channel after every other channel, so it never takes /1 or shifts
-- General and Trade: a new channel gets the lowest free number, and the game
-- rejoins custom channels at login, sometimes before General.
local function moveToEnd()
    local swap = C_ChatInfo and C_ChatInfo.SwapChatChannelsByChannelIndex
    if not (swap and GetChannelList and GetChannelName) then return end
    for _ = 1, 20 do
        local mine = GetChannelName(CHANNEL_NAME)
        if type(mine) ~= "number" or mine <= 0 or ns.IsSecret(mine) then return end
        local list, after = { GetChannelList() }, nil
        for i = 1, #list, 3 do
            local id = list[i]
            if type(id) == "number" and not ns.IsSecret(id) and id > mine and (not after or id < after) then
                after = id
            end
        end
        if not after or not pcall(swap, mine, after) then return end
    end
end
Channel.MoveToEnd = moveToEnd

-- Another channel joined (zoning into a city, login): move ours behind it.
local tidyPending = false
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
watcher:RegisterEvent("PLAYER_LOGOUT")
watcher:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGOUT" then
        -- Leave so the game doesn't rejoin it at the next login before General.
        if GetChannelName and LeaveChannelByName and (GetChannelName(CHANNEL_NAME) or 0) ~= 0 then
            pcall(LeaveChannelByName, CHANNEL_NAME)
        end
        return
    end
    if tidyPending or isOurChannelNotice(nil, event, ...) then return end
    if (GetChannelName(CHANNEL_NAME) or 0) == 0 then return end
    tidyPending = true
    C_Timer.After(1, function()
        tidyPending = false
        moveToEnd()
        hideChannel()
    end)
end)

local function scheduleChannelShare()
    C_Timer.After(CHANNEL_SHARE_EVERY + math.random(-300, 300), function()
        ns.Comm.ShareStats(nil)
        scheduleChannelShare()
    end)
end

function Channel.Join()
    if not JoinTemporaryChannel or not GetChannelName then return end
    if not ns.account.settings.shareChannel then
        -- opted out, but the game may have rejoined it from an older session
        if (GetChannelName(CHANNEL_NAME) or 0) ~= 0 and LeaveChannelByName then pcall(LeaveChannelByName, CHANNEL_NAME) end
        return
    end
    pcall(JoinTemporaryChannel, CHANNEL_NAME)
    moveToEnd()
    hideChannel()
    local id = GetChannelName(CHANNEL_NAME)
    if type(id) ~= "number" or id <= 0 then
        ns.DPrint("Could not join the stats channel")
        return
    end
    channelId = id
    ns.DPrint("Joined stats channel " .. id)
    C_Timer.After(math.random(1, 20), function() ns.Comm.ShareStats(nil) end)
    scheduleChannelShare()
end

local function leaveChannel()
    if channelId and LeaveChannelByName then pcall(LeaveChannelByName, CHANNEL_NAME) end
    channelId = nil
end

function ns.SetChannelSharing(on)
    ns.account.settings.shareChannel = on and true or false
    if on then
        if not channelId then Channel.Join() end
    else
        leaveChannel()
    end
end
