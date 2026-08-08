EuropaEncyclopedia = EuropaEncyclopedia or {}
local E = EuropaEncyclopedia

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
