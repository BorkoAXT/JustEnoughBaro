EuropaEncyclopedia = EuropaEncyclopedia or {}
local E = EuropaEncyclopedia

local PACKAGE_NAME = "Europa Encyclopedia"

local function resolveModDirectory()
    for package in ContentPackageManager.EnabledPackages.All do
        if tostring(package.Name) == PACKAGE_NAME then return tostring(package.Dir) end
    end
    error(PACKAGE_NAME .. " is not present in the enabled content packages")
end

E.modDirectory = resolveModDirectory()

function E.path(relativePath)
    return E.modDirectory .. "/" .. string.gsub(relativePath, "^[/\\]+", "")
end

function E.str(value)
    if value == nil then return "" end
    return tostring(value)
end

function E.id(value)
    return string.lower(E.str(value))
end

function E.each(collection)
    local result = {}
    if collection == nil then return result end
    for value in collection do result[#result + 1] = value end
    return result
end

function E.contains(haystack, needle)
    return string.find(string.lower(haystack or ""), string.lower(needle or ""), 1, true) ~= nil
end

function E.splitLines(text)
    local result = {}
    for line in string.gmatch(text or "", "[^\r\n]+") do result[#result + 1] = line end
    return result
end
