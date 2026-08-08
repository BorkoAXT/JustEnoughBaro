local E = EuropaEncyclopedia
local NET_SYNC = "europaencyclopedia.sync"
local NET_REQUEST = "europaencyclopedia.request"
local unlocked = {}
local currentKey = "no_campaign"

local function safeKey()
    local session = Game.GameSession
    if session == nil then return "no_campaign" end
    local path = session.DataPath and (session.DataPath.SavePath or session.DataPath.LoadPath) or nil
    local raw = tostring(path or session.GameMode or "campaign")
    return string.gsub(string.lower(raw), "[^%w_%-]", "_")
end

local function savePath() return "LocalMods/Europa Encyclopedia/Data/" .. currentKey .. ".txt" end

local function load()
    unlocked = {}
    currentKey = safeKey()
    local path = savePath()
    if not File.Exists(path) then return end
    for _, line in ipairs(E.splitLines(File.Read(path))) do unlocked[string.lower(line)] = true end
end

local function save()
    local values = {}
    for identifier in pairs(unlocked) do values[#values + 1] = identifier end
    table.sort(values)
    File.Write(savePath(), table.concat(values, "\n"))
end

local function payload()
    local values = {}
    for identifier in pairs(unlocked) do values[#values + 1] = identifier end
    table.sort(values)
    return table.concat(values, ";")
end

local function sendSync(connection, newlyUnlocked)
    local msg = Networking.Start(NET_SYNC)
    msg.WriteString(payload())
    msg.WriteString(newlyUnlocked or "")
    if connection == nil then Networking.Send(msg) else Networking.Send(msg, connection) end
end

Hook.Add("roundStart", "EuropaEncyclopedia.Load", function()
    load()
    sendSync(nil, "")
end)

Hook.Add("roundEnd", "EuropaEncyclopedia.Save", save)

Hook.Add("character.death", "EuropaEncyclopedia.Discover", function(character)
    if character == nil or character.IsHuman or character.SpeciesName == nil then return end
    local identifier = E.id(character.SpeciesName)
    if identifier == "" or unlocked[identifier] then return end
    unlocked[identifier] = true
    save()
    sendSync(nil, identifier)
end)

Networking.Receive(NET_REQUEST, function(_, client)
    sendSync(client and client.Connection or nil, "")
end)

load()
