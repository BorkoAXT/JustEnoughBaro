JustEnoughBaro = JustEnoughBaro or {}
local E = JustEnoughBaro

local PACKAGE_NAME = "Just Enough Baro"

local function resolveModDirectory()
    for package in ContentPackageManager.EnabledPackages.All do
        if tostring(package.Name) == PACKAGE_NAME then
            return tostring(package.Dir)
        end
    end

    error(PACKAGE_NAME .. " is not present in the enabled content packages")
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
