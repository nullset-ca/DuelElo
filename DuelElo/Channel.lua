-- Channel.lua: hidden custom channel for realm-wide stats sharing (leaderboard).
local _, ns = ...

local CHANNEL_NAME = "DuelEloLadder"  -- hidden custom channel for realm-wide stats
local CHANNEL_SHARE_EVERY = 1800  -- re-announce our stats this often (seconds, +-jitter)

local Channel = {}
ns.Channel = Channel

local channelId  -- set once we've joined the hidden channel

function Channel.Id()
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

local function scheduleChannelShare()
    C_Timer.After(CHANNEL_SHARE_EVERY + math.random(-300, 300), function()
        ns.Comm.ShareStats(nil)
        scheduleChannelShare()
    end)
end

function Channel.Join()
    if not ns.account.settings.shareChannel or not JoinTemporaryChannel or not GetChannelName then return end
    pcall(JoinTemporaryChannel, CHANNEL_NAME)
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
