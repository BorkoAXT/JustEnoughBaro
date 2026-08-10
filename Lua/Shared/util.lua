JustEnoughBaro = JustEnoughBaro or {}
local E = JustEnoughBaro

local PACKAGE_NAME = "Just Enough Baro (JEB)"

local function directoryFromScript()
    local ok, info = pcall(function()
        return debug and debug.getinfo and debug.getinfo(1, "S")
    end)
    if not ok or info == nil or info.source == nil then
        return nil
    end

    local source = tostring(info.source):gsub("^@", "")
    local directory = source:match("^(.*)[/\\]Lua[/\\]Shared[/\\][^/\\]+$")
    if directory ~= nil then
        return directory
    end
    if source:match("^Lua[/\\]Shared[/\\][^/\\]+$") then
        return "."
    end
    return nil
end

local function directoryFromPackages(collection)
    if collection == nil then
        return nil
    end

    local ok, directory = pcall(function()
        for package in collection do
            if string.lower(tostring(package.Name)) == string.lower(PACKAGE_NAME) then
                return tostring(package.Dir)
            end
        end
    end)
    if ok then
        return directory
    end
    return nil
end

local function resolveModDirectory()
    local scriptDirectory = directoryFromScript()
    if scriptDirectory ~= nil and scriptDirectory ~= "" then
        return scriptDirectory
    end

    -- The collection's shape differs between Barotrauma/LuaCs versions.
    local manager = ContentPackageManager
    local enabled = manager and manager.EnabledPackages
    local all = enabled and enabled.All
    local packageDirectory = directoryFromPackages(all) or directoryFromPackages(enabled)
    if packageDirectory ~= nil and packageDirectory ~= "" then
        return packageDirectory
    end

    error("[" .. PACKAGE_NAME .. "] Could not resolve the mod directory")
end

E.modDirectory = resolveModDirectory()

function E.path(relativePath)
    return E.modDirectory .. "/" .. string.gsub(relativePath, "^[/\\]+", "")
end

function E.str(value)
    if value == nil then
        return ""
    end

    return tostring(value)
end

function E.id(value)
    return string.lower(E.str(value))
end

function E.each(collection)
    local result = {}
    if collection == nil then
        return result
    end

    for value in collection do
        table.insert(result, value)
    end

    return result
end

function E.contains(haystack, needle)
    return string.find(string.lower(haystack or ""), string.lower(needle or ""), 1, true) ~= nil
end
