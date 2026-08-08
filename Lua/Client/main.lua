local E = EuropaEncyclopedia
local wikiCreatures = dofile(E.path("Lua/Client/wiki_data.lua")) or {}
local items, creatures, professions, afflictions = {}, {}, {}, {}
local itemByIdentifier, creatureByIdentifier = {}, {}
local afflictionByIdentifier = {}
local professionByIdentifier = {}
local reverseCraft, reverseDeconstruct = {}, {}
local recipeTalents, recipeBlueprints = {}, {}
local creatureHabitats = {}
local window, listBox, detailList, searchBox, currentCategory, imageOverlay, contextHint, contextHintText
local itemFilterControls, itemFilterLabel
local tabButtons = {}
local toggle
local navigateTo
local currentSearch, visible = "", false
local itemCategoryFilter = "All"
local DEFAULT_SETTINGS = { openKey = "J", pageSize = 80 }
local settings = dofile(E.path("config.lua")) or DEFAULT_SETTINGS
local GUIStatic = LuaUserData.CreateStatic("Barotrauma.GUI", true)
local TalentPrefab = LuaUserData.CreateStatic("Barotrauma.TalentPrefab", true)
local AfflictionPrefab = LuaUserData.CreateStatic("Barotrauma.AfflictionPrefab", true)
local EventPrefab = LuaUserData.CreateStatic("Barotrauma.EventPrefab", true)
local Sprite = LuaUserData.CreateStatic("Barotrauma.Sprite", true)
local InventoryStatic = LuaUserData.CreateStatic("Barotrauma.Inventory", true)
local GUI = {
    Frame = LuaUserData.CreateStatic("Barotrauma.GUIFrame", true),
    TextBlock = LuaUserData.CreateStatic("Barotrauma.GUITextBlock", true),
    TextBox = LuaUserData.CreateStatic("Barotrauma.GUITextBox", true),
    Button = LuaUserData.CreateStatic("Barotrauma.GUIButton", true),
    Image = LuaUserData.CreateStatic("Barotrauma.GUIImage", true),
    RectTransform = LuaUserData.CreateStatic("Barotrauma.RectTransform", true),
    LayoutGroup = LuaUserData.CreateStatic("Barotrauma.GUILayoutGroup", true),
    ListBox = LuaUserData.CreateStatic("Barotrauma.GUIListBox", true),
    Canvas = LuaUserData.CreateStatic("Barotrauma.GUICanvas", true),
    Style = LuaUserData.CreateStatic("Barotrauma.GUIStyle", true)
}
setmetatable(GUI, { __index = function(_, key) return GUIStatic[key] end })
local Keys = LuaUserData.CreateEnumTable("Microsoft.Xna.Framework.Input.Keys")
local Anchor = LuaUserData.CreateEnumTable("Barotrauma.Anchor")
local Alignment = LuaUserData.CreateEnumTable("Barotrauma.Alignment")
local openKey = Keys[settings.openKey] or Keys.J
local FULL_RELATIVE_SIZE = 1
local function relativeVector(width, height) return Vector2(width, height) end
local function fullHeightVector(width) return relativeVector(width, FULL_RELATIVE_SIZE) end
local UI_VECTOR = {
    FULL = relativeVector(1, 1), FULL_WIDTH_AUTO_HEIGHT = relativeVector(1, 0),
    IMAGE_CENTER = relativeVector(0.5, 0.5), OVERLAY_WINDOW = relativeVector(0.82, 0.88),
    OVERLAY_INNER = relativeVector(0.97, 0.96), OVERLAY_TITLE = relativeVector(0.86, 0.08),
    OVERLAY_CLOSE = relativeVector(0.09, 0.08), OVERLAY_IMAGE = relativeVector(0.94, 0.84),
    INFO_ROW = relativeVector(1, 0.052), INFO_KEY = relativeVector(0.27, 1),
    INFO_VALUE = relativeVector(0.70, 1), ICON_INFO_ROW = relativeVector(1, 0.074),
    ICON_INFO_ICON = relativeVector(0.075, 0.78), ICON_INFO_TEXT = relativeVector(0.89, 1),
    REQUIREMENT_ROW = relativeVector(1, 0.09), REQUIREMENT_TEXT = relativeVector(0.82, 1),
    REQUIREMENT_ICON_FRAME = relativeVector(0.105, 0.86), REQUIREMENT_ICON = relativeVector(0.76, 0.76),
    LINK_ROW = relativeVector(1, 0.072), LINK_ICON = relativeVector(0.11, 0.82),
    LINK_TEXT = relativeVector(0.86, 1), ITEM_HERO = relativeVector(1, 0.18),
    ITEM_HERO_ICON = relativeVector(0.18, 0.82), ITEM_HERO_TITLE = relativeVector(0.76, 0.38),
    ITEM_HERO_SUMMARY = relativeVector(0.76, 0.58), CREATURE_PREVIEW = relativeVector(1, 0.24),
    CREATURE_PREVIEW_IMAGE = relativeVector(0.96, 0.90), TALENT_TILE = relativeVector(0.30, 0.82),
    TALENT_PRIMARY_TILE = relativeVector(0.145, 0.82), TALENT_PRIMARY_ROW = relativeVector(1, 0.115),
    TALENT_COLUMN = relativeVector(0.32, 1), TALENT_PATH_OPTIONS = relativeVector(0.94, 0.90),
    TALENT_ICON = relativeVector(0.74, 0.72), PROFESSION_HEADER = relativeVector(1, 0.16),
    PROFESSION_ICON = relativeVector(0.16, 0.80), PROFESSION_TITLE = relativeVector(0.78, 0.46),
    PROFESSION_SUMMARY = relativeVector(0.78, 0.50),
    INDEX_ROW = relativeVector(1, 0.082), INDEX_ICON = relativeVector(0.13, 0.82),
    WINDOW = relativeVector(0.72, 0.72), WINDOW_PADDING = relativeVector(0.965, 0.95),
    HEADER = relativeVector(1, 0.09), HEADER_TITLE_AREA = relativeVector(0.58, 1),
    HEADER_TITLE = relativeVector(0.95, 1), HEADER_CONTROLS = relativeVector(0.40, 1),
    SEARCH_AREA = relativeVector(0.84, 0.62), SEARCH_BOX = relativeVector(0.98, 1),
    HEADER_CLOSE = relativeVector(0.14, 0.62), TABS = relativeVector(1, 0.065),
    TAB_BUTTON = relativeVector(0.247, 0.86), BODY = relativeVector(1, 0.79),
    INDEX_PANEL = relativeVector(0.315, 1), DETAIL_PANEL = relativeVector(0.67, 1),
    PANEL_HEADER = relativeVector(0.94, 0.06), PANEL_LIST = relativeVector(0.94, 0.90),
    FILTER_PREVIOUS = relativeVector(0.14, 0.82), FILTER_LABEL = relativeVector(0.68, 0.82),
    FILTER_NEXT = relativeVector(0.14, 0.82),
    FILTER_CONTROLS = relativeVector(0.76, 1), LIST_HEADER_TITLE = relativeVector(0.22, 1),
    DETAIL_HEADER_TITLE = relativeVector(0.78, 1),
    CONTEXT_HINT = relativeVector(0.34, 0.05), CONTEXT_HINT_TEXT = relativeVector(0.96, 1),
    OFFSET_SMALL = relativeVector(0.012, 0), OFFSET_INFO = relativeVector(0.015, 0),
    OFFSET_STANDARD = relativeVector(0.02, 0), OFFSET_TITLE = relativeVector(0.025, 0),
    OFFSET_TABS = relativeVector(0, 0.105), OFFSET_CONTEXT_HINT = relativeVector(0, -0.08)
}
local ITEM_CATEGORY = {
    STRUCTURE = 1, DECORATIVE = 2, MACHINE = 4, MEDICAL = 8, WEAPON = 16,
    DIVING = 32, EQUIPMENT = 64, FUEL = 128, ELECTRICAL = 256, MATERIAL = 1024,
    ALIEN = 2048, WRECKED = 4096, ITEM_ASSEMBLY = 8192, LEGACY = 16384, MISC = 32768
}
local NUMBER_PRECISION = 1000
local NUMBER_EPSILON = 0.0005
local PERCENT_SCALE = 100
local GUI_ORDER = { CONTEXT_HINT = 0, WINDOW = 1000, IMAGE_OVERLAY = 1001 }
local DELAY_MS = { CORPSE_TEST = 750, DATABASE_BUILD = 1000 }
local MAX_GUI_PARENT_DEPTH = 12
local TALENT_TREE_BASE_HEIGHT = 0.10
local TALENT_TREE_STAGE_HEIGHT = 0.115
local TALENT_TILE_WIDTH = 0.30
local TALENT_PRIMARY_TILE_WIDTH = 0.145
local TALENT_ROW_COLOR = Color(46, 46, 46, 255)

local function safeField(object, field, fallback)
    if object == nil then return fallback end
    local ok, value = pcall(function() return object[field] end)
    if not ok or value == nil then return fallback end
    return value
end
local function text(value)
    if value == nil then return "" end
    local renderedOk, rendered = pcall(function() return value.ToString() end)
    if renderedOk and rendered ~= nil then
        local renderedText = tostring(rendered)
        if not string.find(renderedText, "^userdata:") then return renderedText end
    end
    local localized = safeField(value, "Value", nil)
    if localized ~= nil and localized ~= value then
        local localizedOk, localizedText = pcall(function() return localized.ToString() end)
        if localizedOk and localizedText ~= nil then return tostring(localizedText) end
        return tostring(localized)
    end
    return E.str(value)
end
local function id(value) return string.lower(text(value)) end
local function cleanDisplayText(value)
    local result = text(value)
    if string.find(result, "^userdata:") then return "" end
    result = string.gsub(result, "%[?color:[%w%._]+%]?", "")
    result = string.gsub(result, "%[?color:end%]?", "")
    result = string.gsub(result, "</?color[^>]*>", "")
    return result
end
local function numberText(value)
    local numeric = tonumber(value)
    if numeric == nil then return text(value) end
    if math.abs(numeric) < NUMBER_EPSILON then numeric = 0 end
    local rounded
    if numeric >= 0 then rounded = math.floor(numeric * NUMBER_PRECISION + 0.5) / NUMBER_PRECISION
    else rounded = math.ceil(numeric * NUMBER_PRECISION - 0.5) / NUMBER_PRECISION end
    return string.gsub(string.gsub(string.format("%.3f", rounded), "0+$", ""), "%.$", "")
end
local function joined(collection, separator)
    local values = {}
    if collection ~= nil then
        for value in collection do values[#values + 1] = text(value) end
    end
    return table.concat(values, separator or ", ")
end
local itemCategoryNames = {
    {ITEM_CATEGORY.STRUCTURE, "Structure"}, {ITEM_CATEGORY.DECORATIVE, "Decorative"},
    {ITEM_CATEGORY.MACHINE, "Machine"}, {ITEM_CATEGORY.MEDICAL, "Medical"},
    {ITEM_CATEGORY.WEAPON, "Weapon"}, {ITEM_CATEGORY.DIVING, "Diving"},
    {ITEM_CATEGORY.EQUIPMENT, "Equipment"}, {ITEM_CATEGORY.FUEL, "Fuel"},
    {ITEM_CATEGORY.ELECTRICAL, "Electrical"}, {ITEM_CATEGORY.MATERIAL, "Material"},
    {ITEM_CATEGORY.ALIEN, "Alien"}, {ITEM_CATEGORY.WRECKED, "Wrecked"},
    {ITEM_CATEGORY.ITEM_ASSEMBLY, "Item Assembly"}, {ITEM_CATEGORY.LEGACY, "Legacy"},
    {ITEM_CATEGORY.MISC, "Misc"}
}
local function categoryText(value)
    local numeric = tonumber(value) or 0
    if numeric == 0 then return "None" end
    local names = {}
    for _, pair in ipairs(itemCategoryNames) do
        if math.floor(numeric / pair[1]) % 2 == 1 then names[#names + 1] = pair[2] end
    end
    return table.concat(names, ", ")
end
local itemFilterNames = {
    "All", "Weapons", "Ammunition", "Gear", "Diving", "Medical", "Tools",
    "Electrical", "Materials", "Ores", "Ruins & Alien", "Miscellaneous"
}
local function hasCategory(value, flag)
    return math.floor((tonumber(value) or 0) / flag) % 2 == 1
end
local function itemFilterCategory(entry)
    local prefab = entry.prefab
    local identifier = entry.identifier
    local tags = string.lower(joined(prefab.Tags, " "))
    local sourcePath = string.lower(prefab.ContentFile and text(prefab.ContentFile.Path) or "")
    local searchable = identifier .. " " .. string.lower(entry.name) .. " " .. tags .. " " .. sourcePath
    if E.contains(searchable, "ore") or E.contains(tags, "mineral") then return "Ores" end
    if hasCategory(prefab.Category, ITEM_CATEGORY.ALIEN) or E.contains(sourcePath, "ruin") or E.contains(tags, "alien") then return "Ruins & Alien" end
    if E.contains(tags, "ammo") or E.contains(tags, "ammunition") or E.contains(identifier, "round") or
        E.contains(identifier, "magazine") or E.contains(identifier, "shell") then return "Ammunition" end
    if hasCategory(prefab.Category, ITEM_CATEGORY.MEDICAL) then return "Medical" end
    if hasCategory(prefab.Category, ITEM_CATEGORY.DIVING) then return "Diving" end
    if hasCategory(prefab.Category, ITEM_CATEGORY.WEAPON) then return "Weapons" end
    if hasCategory(prefab.Category, ITEM_CATEGORY.ELECTRICAL) then return "Electrical" end
    if hasCategory(prefab.Category, ITEM_CATEGORY.MATERIAL) then return "Materials" end
    if hasCategory(prefab.Category, ITEM_CATEGORY.EQUIPMENT) then return "Gear" end
    if E.contains(tags, "tool") or E.contains(sourcePath, "/tools") then return "Tools" end
    return "Miscellaneous"
end
local function addIndex(index, key, value)
    key = id(key); index[key] = index[key] or {}; index[key][#index[key] + 1] = value
end
local function addUniqueEntry(index, key, value, identity)
    key = id(key)
    index[key] = index[key] or {}
    local valueIdentity = identity(value)
    for _, existing in ipairs(index[key]) do
        if identity(existing) == valueIdentity then return end
    end
    index[key][#index[key] + 1] = value
end

local function xmlAttribute(tag, name, fallback)
    local value = string.match(tag or "", name .. "%s*=%s*\"([^\"]*)\"")
    return value or fallback or ""
end

local function xmlSection(xml, elementName, attribute, value)
    for opening, body in string.gmatch(xml or "", "<" .. elementName .. "%s+([^>]*)>(.-)</" .. elementName .. ">") do
        if id(xmlAttribute(opening, attribute, "")) == id(value) then return opening, body end
    end
    return nil, nil
end

local function findItemPrefab(identifier)
    local key = id(identifier)
    if itemByIdentifier[key] ~= nil then return itemByIdentifier[key].prefab end
    for prefab in ItemPrefab.Prefabs do if id(prefab.Identifier) == key then return prefab end end
    return nil
end

local function findCharacterPrefab(identifier)
    local key = id(identifier)
    if creatureByIdentifier[key] ~= nil then return creatureByIdentifier[key].prefab end
    for prefab in CharacterPrefab.Prefabs do if id(prefab.Identifier) == key then return prefab end end
    return nil
end

local function addUnique(index, key, value)
    key = id(key)
    index[key] = index[key] or {}
    for _, existing in ipairs(index[key]) do if existing == value then return end end
    index[key][#index[key] + 1] = value
end

local function prettyIdentifier(value)
    local knownNames = {
        blunttrauma="Blunt Force Trauma", gunshotwound="Gunshot Wound", bitewounds="Bite Wounds",
        explosiondamage="Explosion Damage", radiationsickness="Radiation Sickness", huskinfection="Husk Infection",
        lacerations="Lacerations", bleeding="Bleeding", burn="Burn", stun="Stun",
        electrical="Electrical", mechanical="Mechanical", medical="Medical", weapons="Weapons", helm="Helm",
        walkingspeed="Walking Speed", swimmingspeed="Swimming Speed", propulsionspeed="Propulsion Speed",
        flowresistance="Flow Resistance", pressureprotection="Pressure Protection"
    }
    if knownNames[id(value)] ~= nil then return knownNames[id(value)] end
    local result = string.gsub(text(value), "(%l)(%u)", "%1 %2")
    result = string.gsub(result, "[_%-]+", " ")
    return (string.gsub(result, "(%a)([%w']*)", function(first, rest)
        return string.upper(first) .. string.lower(rest)
    end))
end

local function joinedPretty(collection, separator)
    local values = {}
    if collection ~= nil then for value in collection do values[#values + 1] = prettyIdentifier(value) end end
    return table.concat(values, separator or ", ")
end

local function indexMonsterEvents(element, biome)
    if element == nil then return end
    if id(element.NameAsIdentifier()) == "monsterevent" then
        local characterFile = element.GetAttributeString("characterfile", "")
        local spawnTypes = element.GetAttributeString("spawntype", "")
        for spawnType in string.gmatch(spawnTypes, "[^,%s]+") do addUnique(creatureHabitats, characterFile, prettyIdentifier(spawnType)) end
        if text(biome) ~= "" then addUnique(creatureHabitats, characterFile, "Biome: " .. prettyIdentifier(biome)) end
    end
    for child in element.Elements() do indexMonsterEvents(child, biome) end
end

local function buildDatabase()
    items, creatures, professions, afflictions, reverseCraft, reverseDeconstruct = {}, {}, {}, {}, {}, {}
    itemByIdentifier, creatureByIdentifier, afflictionByIdentifier, professionByIdentifier = {}, {}, {}, {}
    recipeTalents, recipeBlueprints, creatureHabitats = {}, {}, {}
    local seenItems = {}
    for prefab in ItemPrefab.Prefabs do
        if prefab ~= nil and prefab.Identifier ~= nil then
            local entry = { prefab = prefab, identifier = id(prefab.Identifier), name = text(prefab.Name) }
            local hidden = prefab.ConfigElement ~= nil and prefab.ConfigElement.GetAttributeBool("hideinmenus", false)
            local filePath = prefab.ContentFile and text(prefab.ContentFile.Path) or ""
            local isLegacy = math.floor((tonumber(prefab.Category) or 0) / ITEM_CATEGORY.LEGACY) % 2 == 1 or E.contains(filePath, "/Legacy/")
            if entry.name ~= "" and not hidden and not isLegacy and not seenItems[entry.identifier] then
                seenItems[entry.identifier] = true
                items[#items + 1] = entry
                itemByIdentifier[entry.identifier] = entry
                for _, recipe in ipairs(E.each(prefab.FabricationRecipes.Values)) do
                    for _, requirement in ipairs(E.each(recipe.RequiredItems)) do
                        for _, ingredient in ipairs(E.each(requirement.ItemPrefabs)) do
                            addUniqueEntry(reverseCraft, ingredient.Identifier, entry, function(value) return value.identifier end)
                        end
                    end
                end
                for _, output in ipairs(E.each(prefab.DeconstructItems)) do addIndex(reverseDeconstruct, output.ItemIdentifier, { source = entry, output = output }) end
                for _, recipeIdentifier in ipairs(E.each(prefab.UnlockedRecipeInToolTip)) do
                    addIndex(recipeBlueprints, recipeIdentifier, entry)
                end
            end
        end
    end
    for _, target in ipairs(items) do
        if target.prefab.ConfigElement ~= nil then
            for recipe in target.prefab.ConfigElement.GetChildElements("Fabricate") do
                for requirement in recipe.Elements() do
                    local elementName = id(requirement.NameAsIdentifier())
                    if elementName == "item" or elementName == "requireditem" then
                        local ingredientIdentifier = id(requirement.GetAttributeIdentifier("identifier", ""))
                        local ingredientTag = id(requirement.GetAttributeIdentifier("tag", ""))
                        if ingredientIdentifier ~= "" then
                            addUniqueEntry(reverseCraft, ingredientIdentifier, target, function(value) return value.identifier end)
                        elseif ingredientTag ~= "" then
                            for _, candidate in ipairs(items) do
                                for tag in candidate.prefab.Tags do
                                    if id(tag) == ingredientTag then
                                        addUniqueEntry(reverseCraft, candidate.identifier, target, function(value) return value.identifier end)
                                        break
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    for talent in TalentPrefab.TalentPrefabs do
        if talent ~= nil and talent.ConfigElement ~= nil then
            for child in talent.ConfigElement.Elements() do
                if id(child.NameAsIdentifier()) == "addedrecipe" then
                    local recipeIdentifier = child.GetAttributeIdentifier("itemidentifier", "")
                    if id(recipeIdentifier) ~= "" then addIndex(recipeTalents, recipeIdentifier, talent) end
                end
            end
        end
    end
    local jobsXml = File.Exists("Content/Jobs.xml") and File.Read("Content/Jobs.xml") or ""
    local talentTreesXml = File.Exists("Content/Talents/TalentTrees.xml") and File.Read("Content/Talents/TalentTrees.xml") or ""
    local coreAfflictionIdentifiers = {}
    for _, path in ipairs({"Content/Afflictions.xml", "Content/AfflictionsGeneticMaterial.xml"}) do
        local xml = File.Exists(path) and File.Read(path) or ""
        for identifier in string.gmatch(xml, "identifier%s*=%s*\"([^\"]+)\"") do
            coreAfflictionIdentifiers[id(identifier)] = true
        end
    end
    local crewProfessions = { captain=true, engineer=true, mechanic=true, securityofficer=true, medicaldoctor=true, assistant=true }
    for prefab in JobPrefab.Prefabs do
        local professionIdentifier = prefab and id(prefab.Identifier) or ""
        if crewProfessions[professionIdentifier] and text(prefab.Name) ~= "" then
            local _, jobXml = xmlSection(jobsXml, "Job", "identifier", prefab.Identifier)
            local _, treeXml = xmlSection(talentTreesXml, "TalentTree", "jobidentifier", prefab.Identifier)
            professions[#professions + 1] = {
                prefab = prefab, identifier = id(prefab.Identifier), name = text(prefab.Name),
                jobXml = jobXml, treeXml = treeXml
            }
            professionByIdentifier[professionIdentifier] = professions[#professions]
        end
    end
    local seenAfflictionNames = {}
    for prefab in AfflictionPrefab.Prefabs do
        if prefab ~= nil and prefab.Identifier ~= nil then
            local entry = { prefab=prefab, identifier=id(prefab.Identifier), name=text(prefab.Name) }
            if entry.name == "" then entry.name = prettyIdentifier(entry.identifier) end
            local normalizedName = id(entry.name)
            if coreAfflictionIdentifiers[entry.identifier] and entry.identifier ~= "" and
                afflictionByIdentifier[entry.identifier] == nil and not seenAfflictionNames[normalizedName] then
                afflictions[#afflictions + 1] = entry
                afflictionByIdentifier[entry.identifier] = entry
                seenAfflictionNames[normalizedName] = true
            end
        end
    end
    for event in EventPrefab.Prefabs do indexMonsterEvents(event.ConfigElement, event.BiomeIdentifier) end
    local seenCreatures = {}
    local retiredCreatures = { carrier=true, coelanth=true, charybdisold=true }
    for prefab in CharacterPrefab.Prefabs do
        if prefab ~= nil and prefab.Identifier ~= nil and id(prefab.Identifier) ~= "human" then
            local filePath = prefab.ContentFile and text(prefab.ContentFile.Path) or ""
            local fileName = string.match(filePath, "([^/\\]+)%.xml$") or id(prefab.Identifier)
            local identifier = id(prefab.Identifier)
            local legacy = E.contains(fileName, "legacy") or E.contains(identifier, "legacy") or retiredCreatures[identifier]
            if not legacy and not seenCreatures[identifier] then
                seenCreatures[identifier] = true
                creatures[#creatures + 1] = {
                prefab = prefab, identifier = id(prefab.Identifier), name = text(prefab.Name),
                habitats = creatureHabitats[id(fileName)] or creatureHabitats[id(prefab.Identifier)] or {}
                }
                creatureByIdentifier[identifier] = creatures[#creatures]
            end
        end
    end
    table.sort(items, function(a,b) return a.name < b.name end)
    table.sort(creatures, function(a,b) return a.name < b.name end)
    table.sort(professions, function(a,b) return a.name < b.name end)
    table.sort(afflictions, function(a,b) return a.name < b.name end)
end

local function creaturePreviewSprite(prefab)
    local source = prefab
    while source ~= nil do
        local characterPath = source.ContentFile and text(source.ContentFile.Path) or ""
        local directory, fileName = string.match(characterPath, "^(.*)[/\\]([^/\\]+)%.xml$")
        if directory ~= nil then
            local ragdollPath = directory .. "/Ragdolls/" .. fileName .. "DefaultRagdoll.xml"
            if File.Exists(ragdollPath) then
                local xml = File.Read(ragdollPath)
                local texture = string.match(xml, "<[Rr]agdoll.-texture=\"([^\"]+)\"")
                local bestX, bestY, bestW, bestH, bestArea
                for x, y, w, h in string.gmatch(xml, "sourcerect=\"(%-?%d+),%s*(%-?%d+),%s*(%d+),%s*(%d+)\"") do
                    local area = tonumber(w) * tonumber(h)
                    if bestArea == nil or area > bestArea then bestX, bestY, bestW, bestH, bestArea = x, y, w, h, area end
                end
                if texture ~= nil and bestArea ~= nil then
                    return Sprite(texture, Rectangle(tonumber(bestX), tonumber(bestY), tonumber(bestW), tonumber(bestH)))
                end
            end
        end
        source = source.ParentPrefab
    end
    return nil
end

local function wikiCreatureSprite(entry)
    local wiki = wikiCreatures[entry.identifier]
    if wiki == nil or wiki.image == nil or wiki.image == "" then return nil end
    local imagePath = E.path(wiki.image)
    if not File.Exists(imagePath) then return nil end
    return Sprite(imagePath, UI_VECTOR.IMAGE_CENTER)
end

local function showImageOverlay(sprite, titleText)
    if imageOverlay ~= nil then imageOverlay.Visible = false; imageOverlay = nil end
    imageOverlay = GUI.Frame(GUI.RectTransform(UI_VECTOR.OVERLAY_WINDOW, GUIStatic.Canvas, Anchor.Center), "GUIFrameListBox")
    local inner = GUI.Frame(GUI.RectTransform(UI_VECTOR.OVERLAY_INNER, imageOverlay.RectTransform, Anchor.Center), "InnerFrame")
    local title = GUI.TextBlock(GUI.RectTransform(UI_VECTOR.OVERLAY_TITLE, inner.RectTransform, Anchor.TopLeft),
        string.upper(titleText), Color(101, 203, 218, 255), GUI.Style.SubHeadingFont, Alignment.CenterLeft, false, "")
    title.CanBeFocused = false
    local close = GUI.Button(GUI.RectTransform(UI_VECTOR.OVERLAY_CLOSE, inner.RectTransform, Anchor.TopRight), "×", Alignment.Center, "GUICancelButton")
    close.OnClicked = function() imageOverlay.Visible = false; imageOverlay = nil; return true end
    local image = GUI.Image(GUI.RectTransform(UI_VECTOR.OVERLAY_IMAGE, inner.RectTransform, Anchor.BottomCenter), sprite, true)
    image.CanBeFocused = false
end

local function clear(component)
    if component ~= nil then component.Content.ClearChildren() end
end

local function line(parent, value, style)
    return GUI.TextBlock(
        GUI.RectTransform(UI_VECTOR.FULL_WIDTH_AUTO_HEIGHT, parent, Anchor.TopCenter),
        text(value), Color(206, 213, 190, 255), nil, Alignment.TopLeft, true, style or "")
end

local function label(parent, value, alignment, color)
    return GUI.TextBlock(
        GUI.RectTransform(UI_VECTOR.FULL, parent, Anchor.Center), text(value),
        color or Color(152, 177, 184, 255), GUI.Style.SmallFont,
        alignment or Alignment.CenterLeft, false, "")
end

local function heading(parent, value)
    return GUI.TextBlock(
        GUI.RectTransform(UI_VECTOR.FULL_WIDTH_AUTO_HEIGHT, parent, Anchor.TopCenter),
        string.upper(text(value)), Color(92, 185, 201, 255), GUI.Style.SubHeadingFont,
        Alignment.TopLeft, true, "")
end

local palette = {
    cyan=Color(101, 203, 218, 255), cream=Color(222, 211, 164, 255),
    green=Color(130, 205, 151, 255), orange=Color(224, 157, 93, 255), red=Color(220, 104, 104, 255),
    muted=Color(152, 177, 184, 255)
}

local function infoRow(parent, key, value, color)
    local row = GUI.Frame(GUI.RectTransform(UI_VECTOR.INFO_ROW, parent, Anchor.TopCenter), "ListBoxElement")
    local keyText = GUI.TextBlock(GUI.RectTransform(UI_VECTOR.INFO_KEY, row.RectTransform, Anchor.CenterLeft),
        string.upper(text(key)), nil, GUI.Style.SmallFont, Alignment.CenterLeft, false, "")
    keyText.RectTransform.RelativeOffset = UI_VECTOR.OFFSET_INFO; keyText.CanBeFocused = false
    local valueText = GUI.TextBlock(GUI.RectTransform(UI_VECTOR.INFO_VALUE, row.RectTransform, Anchor.CenterRight),
        text(value), nil, GUI.Style.SmallFont, Alignment.CenterLeft, false, "")
    valueText.CanBeFocused = false
    return row
end

local function iconInfoRow(parent, sprite, caption, value, color, tooltip)
    local row = GUI.Frame(GUI.RectTransform(UI_VECTOR.ICON_INFO_ROW, parent, Anchor.TopCenter), "ListBoxElement")
    if sprite ~= nil then
        local image = GUI.Image(GUI.RectTransform(UI_VECTOR.ICON_INFO_ICON, row.RectTransform, Anchor.CenterLeft), sprite, true)
        image.RectTransform.RelativeOffset = UI_VECTOR.OFFSET_SMALL; image.CanBeFocused = false
    end
    local block = GUI.TextBlock(GUI.RectTransform(UI_VECTOR.ICON_INFO_TEXT, row.RectTransform, Anchor.CenterRight),
        string.upper(text(caption)) .. "\n" .. text(value), nil, GUI.Style.SmallFont, Alignment.CenterLeft, false, "")
    block.CanBeFocused = false; row.ToolTip = tooltip or text(value)
    return row
end

local skillJobs = {
    electrical = "engineer",
    helm = "captain",
    mechanical = "mechanic",
    medical = "medicaldoctor",
    weapons = "securityofficer"
}

local function titleCase(value)
    return prettyIdentifier(value)
end

local function fallbackSkillIcon(identifier)
    local jobIdentifier = skillJobs[id(identifier)]
    if jobIdentifier == nil then return nil end
    local job = nil
    for prefab in JobPrefab.Prefabs do if id(prefab.Identifier) == jobIdentifier then job = prefab; break end end
    return job and safeField(job, "IconSmall", safeField(job, "Icon", nil)) or nil
end

local function requirementRow(parent, captionText, iconSprite, tooltip, onClick)
    local row = GUI.Frame(GUI.RectTransform(UI_VECTOR.REQUIREMENT_ROW, parent, Anchor.TopCenter), "ListBoxElement")
    local caption
    if onClick ~= nil then
        caption = GUI.Button(GUI.RectTransform(UI_VECTOR.REQUIREMENT_TEXT, row.RectTransform, Anchor.CenterLeft),
            captionText .. "  ›", Alignment.CenterLeft, "GUIButtonSmall")
        caption.OnClicked = function() onClick(); return true end
        caption.ToolTip = tooltip or captionText
    else
        caption = GUI.TextBlock(GUI.RectTransform(UI_VECTOR.REQUIREMENT_TEXT, row.RectTransform, Anchor.CenterLeft),
            captionText, nil, GUI.Style.SmallFont, Alignment.CenterLeft, false, "")
    end
    caption.RectTransform.RelativeOffset = UI_VECTOR.OFFSET_STANDARD
    if onClick == nil then caption.CanBeFocused = false end
    local square = GUI.Frame(GUI.RectTransform(UI_VECTOR.REQUIREMENT_ICON_FRAME, row.RectTransform, Anchor.CenterRight), "TalentBackground")
    if iconSprite ~= nil then
        local image = GUI.Image(GUI.RectTransform(UI_VECTOR.REQUIREMENT_ICON, square.RectTransform, Anchor.Center), iconSprite, true)
        image.CanBeFocused = false
    else
        label(square.RectTransform, "?", Alignment.Center, Color(101, 203, 218, 255))
    end
    square.ToolTip = tooltip or captionText
    square.CanBeFocused = false
end

local function skillRequirement(parent, identifier, level, displayName, iconSprite)
    local name = text(displayName)
    if name == "" then name = titleCase(identifier) end
    local jobIdentifier = skillJobs[id(identifier)]
    local function openProfession()
        if jobIdentifier == nil then return end
        local profession = professionByIdentifier[jobIdentifier]
        if profession ~= nil then navigateTo("Professions", profession, id(identifier)) end
    end
    local tooltip = name .. " skill required: " .. text(level)
    if jobIdentifier ~= nil then tooltip = tooltip .. "\n\nClick to open the associated profession tree." end
    requirementRow(parent, name .. " skill " .. text(level), iconSprite or fallbackSkillIcon(identifier), tooltip,
        jobIdentifier ~= nil and openProfession or nil)
end

local function recipeUnlockRequirements(parent, prefab)
    local identifier = id(prefab.Identifier)
    local talents = recipeTalents[identifier] or {}
    local blueprints = recipeBlueprints[identifier] or {}
    for _, talent in ipairs(talents) do
        local name = text(talent.DisplayName)
        requirementRow(parent, "Required perk: " .. name, talent.Icon, name)
    end
    for _, blueprint in ipairs(blueprints) do
        local sprite = blueprint.prefab.InventoryIcon or blueprint.prefab.Sprite
        requirementRow(parent, "Required blueprint: " .. blueprint.name, sprite, blueprint.name)
    end
    if #talents == 0 and #blueprints == 0 then
        requirementRow(parent, "Required: recipe unlock", nil, "This recipe must be learned before fabrication.")
    end
end

local function itemButton(parent, entry, suffix)
    local button = GUI.Button(GUI.RectTransform(UI_VECTOR.LINK_ROW, parent, Anchor.TopCenter), "", Alignment.CenterLeft, "ListBoxElement")
    local sprite = entry.prefab.InventoryIcon or entry.prefab.Sprite
    if sprite ~= nil then
        local icon = GUI.Image(GUI.RectTransform(UI_VECTOR.LINK_ICON, button.RectTransform, Anchor.CenterLeft), sprite, true)
        icon.Color = entry.prefab.InventoryIcon and entry.prefab.InventoryIconColor or entry.prefab.SpriteColor
        icon.CanBeFocused = false
    end
    local caption = GUI.TextBlock(
        GUI.RectTransform(UI_VECTOR.LINK_TEXT, button.RectTransform, Anchor.CenterRight),
        entry.name .. (suffix or ""), nil, GUI.Style.SmallFont, Alignment.CenterLeft, false, "")
    caption.CanBeFocused = false
    button.OnClicked = function() navigateTo("Items", entry); return true end
    return button
end

local function conditionRequirementText(minimumCondition, maximumCondition)
    local minimum = tonumber(minimumCondition) or 0
    local maximum = tonumber(maximumCondition) or 1
    if maximum < 1 then return "  •  condition ≤ " .. numberText(maximum * PERCENT_SCALE) .. "%" end
    if minimum > 0 then return "  •  condition ≥ " .. numberText(minimum * PERCENT_SCALE) .. "%" end
    return ""
end

local function recipeIngredient(parent, candidatePrefabs, amount, minimumCondition, maximumCondition)
    local candidates, seen = {}, {}
    for _, prefab in ipairs(candidatePrefabs or {}) do
        local identifier = prefab and id(prefab.Identifier) or ""
        if identifier ~= "" and not seen[identifier] then
            seen[identifier] = true
            candidates[#candidates + 1] = prefab
        end
    end
    table.sort(candidates, function(a, b) return text(a.Name) < text(b.Name) end)
    local suffix = "  x" .. text(amount) .. conditionRequirementText(minimumCondition, maximumCondition)
    if #candidates == 1 then
        local prefab = candidates[1]
        itemButton(parent, {prefab=prefab, identifier=id(prefab.Identifier), name=text(prefab.Name)}, suffix)
        return
    end
    if #candidates > 1 then
        local names = {}
        for _, prefab in ipairs(candidates) do names[#names + 1] = text(prefab.Name) end
        local first = candidates[1]
        requirementRow(parent, table.concat(names, " or ") .. suffix,
            first.InventoryIcon or first.Sprite, "Any one of these ingredients satisfies this slot.")
        return
    end
    line(parent, "Compatible ingredient" .. suffix)
end

local function itemPrefabsWithTag(tagIdentifier)
    local matches, targetTag = {}, id(tagIdentifier)
    if targetTag == "" then return matches end
    for _, entry in ipairs(items) do
        for tag in entry.prefab.Tags do
            if id(tag) == targetTag then matches[#matches + 1] = entry.prefab; break end
        end
    end
    return matches
end

local function recipeTitle(index, total, displayName)
    local rawName = id(displayName)
    local purpose = "Craft new"
    if rawName == "recycleitem" then purpose = "Refill or recycle"
    elseif rawName ~= "" then purpose = cleanDisplayText(displayName); if purpose == "" then purpose = prettyIdentifier(displayName) end end
    if total > 1 then return "Recipe " .. text(index) .. " of " .. text(total) .. "  •  " .. purpose end
    return purpose
end

local function renderXmlRecipes(prefab, parent)
    if prefab.ConfigElement == nil then return 0 end
    local xmlRecipes = E.each(prefab.ConfigElement.GetChildElements("Fabricate"))
    if #xmlRecipes > 0 then heading(parent, "\nCrafting") end
    for recipeIndex, recipe in ipairs(xmlRecipes) do
        if #xmlRecipes > 1 then heading(parent, recipeTitle(recipeIndex, #xmlRecipes, recipe.GetAttributeString("displayname", ""))) end
        local amount = recipe.GetAttributeInt("amount", 1)
        local requiredTime = recipe.GetAttributeFloat("requiredtime", 1)
        local devices = recipe.GetAttributeString("suitablefabricators", "")
        line(parent, "OUTPUT x" .. text(amount) .. "  •  " .. text(requiredTime) .. " s")
        local deviceNames = {}; for device in string.gmatch(devices, "[^,%s]+") do deviceNames[#deviceNames + 1] = prettyIdentifier(device) end
        line(parent, "DEVICE  " .. (#deviceNames > 0 and table.concat(deviceNames, ", ") or "Fabricator"))
        local requiresRecipe = recipe.GetAttributeBool("requiresrecipe", false)
        local hasSkills = false
        for requirement in recipe.Elements() do
            if id(requirement.NameAsIdentifier()) == "requiredskill" then hasSkills = true; break end
        end
        if hasSkills or requiresRecipe then heading(parent, "Requirements") end
        for requirement in recipe.Elements() do
            if id(requirement.NameAsIdentifier()) == "requiredskill" then
                local identifier = requirement.GetAttributeIdentifier("identifier", "")
                skillRequirement(parent, identifier, requirement.GetAttributeInt("level", 0))
            end
        end
        if requiresRecipe then recipeUnlockRequirements(parent, prefab) end
        for requirement in recipe.Elements() do
            local elementName = id(requirement.NameAsIdentifier())
            if elementName == "item" or elementName == "requireditem" then
                local identifier = requirement.GetAttributeIdentifier("identifier", "")
                local quantity = requirement.GetAttributeInt("count", requirement.GetAttributeInt("amount", 1))
                local ingredient = findItemPrefab(identifier)
                local tag = requirement.GetAttributeIdentifier("tag", "")
                local candidates = ingredient ~= nil and {ingredient} or itemPrefabsWithTag(tag)
                recipeIngredient(parent, candidates, quantity,
                    requirement.GetAttributeFloat("mincondition", 0), requirement.GetAttributeFloat("maxcondition", 1))
            end
        end
    end
    return #xmlRecipes
end

local merchantNames = {
    merchantoutpost="Outpost Merchant", merchantcity="Colony Merchant", merchantresearch="Research Merchant",
    merchantmilitary="Military Merchant", merchantmine="Mining Merchant", merchantmedical="Medical Merchant",
    merchantengineering="Engineering Merchant", merchantarmory="Armory Merchant", merchantclown="Clown Merchant",
    merchanthusk="Husk Merchant", merchantnightclub="Nightclub Merchant"
}

local function showItemCapabilities(prefab, parent)
    local root = prefab.ConfigElement
    if root == nil then return end
    local protection, stats, skillBonuses, attacks, requirements, equipment = {}, {}, {}, {}, {}, {}
    local function addAffectedEffects(target, identifiers, suffix)
        for identifier in string.gmatch(identifiers or "", "[^,%s]+") do
            target[#target + 1] = prettyIdentifier(identifier) .. suffix
        end
    end
    local function walk(element, context)
        local name = id(element.NameAsIdentifier())
        local nextContext = context
        if name == "fabricate" or name == "deconstruct" then return end
        if name == "wearable" then
            nextContext = "wearable"
            local slots = element.GetAttributeString("slots", "")
            if slots ~= "" then equipment[#equipment + 1] = "EQUIP SLOTS  " .. slots end
        elseif name == "meleeweapon" then
            nextContext = "weapon"
            local slots = element.GetAttributeString("slots", "")
            if slots ~= "" then equipment[#equipment + 1] = "HAND SLOTS  " .. slots end
            local reload = element.GetAttributeFloat("reload", 0)
            if reload > 0 then equipment[#equipment + 1] = "ATTACK COOLDOWN  " .. text(reload) .. " s" end
        elseif name == "rangedweapon" then
            nextContext = "weapon"
            equipment[#equipment + 1] = "SPREAD  " .. text(element.GetAttributeFloat("spread", 0)) ..
                "°  •  UNSKILLED " .. text(element.GetAttributeFloat("unskilledspread", 0)) .. "°"
        elseif name == "projectile" then
            nextContext = "weapon"
        elseif name == "damagemodifier" and context == "wearable" then
            local multiplier = element.GetAttributeFloat("damagemultiplier", 1)
            local affected = element.GetAttributeString("afflictionidentifiers", element.GetAttributeString("afflictiontypes", "damage"))
            local probabilityMultiplier = element.GetAttributeFloat("probabilitymultiplier", 1)
            if multiplier < 1 then
                addAffectedEffects(protection, affected, "  " .. text(math.floor((1 - multiplier) * PERCENT_SCALE + 0.5)) .. "% resistance")
            elseif probabilityMultiplier < 1 then
                addAffectedEffects(protection, affected, "  " .. text(math.floor((1 - probabilityMultiplier) * PERCENT_SCALE + 0.5)) .. "% affliction resistance")
            end
        elseif name == "skillmodifier" and context == "wearable" then
            local skillName = prettyIdentifier(element.GetAttributeString("skillidentifier", ""))
            local skillValue = element.GetAttributeFloat("skillvalue", 0)
            skillBonuses[#skillBonuses + 1] = skillName .. " skill  " .. (skillValue >= 0 and "+" or "") .. text(skillValue)
        elseif name == "statvalue" and context == "wearable" then
            local stat = prettyIdentifier(element.GetAttributeString("stattype", ""))
            local value = element.GetAttributeFloat("value", 0)
            stats[#stats + 1] = stat .. "  " .. (value >= 0 and "+" or "") .. text(math.floor(value * PERCENT_SCALE + 0.5)) .. "%"
        elseif name == "statuseffect" and id(element.GetAttributeString("type", "")) == "onwearing" then
            local speed = element.GetAttributeFloat("speedmultiplier", 1)
            local pressure = element.GetAttributeFloat("pressureprotection", 0)
            if speed ~= 1 then stats[#stats + 1] = "Speed multiplier  " .. text(math.floor(speed * PERCENT_SCALE + 0.5)) .. "%" end
            if pressure > 0 then stats[#stats + 1] = "Pressure protection  " .. text(pressure) end
        elseif name == "attack" or name == "explosion" then
            nextContext = "attack"
            local structureDamage = element.GetAttributeFloat("structuredamage", 0)
            local itemDamage = element.GetAttributeFloat("itemdamage", 0)
            local penetration = element.GetAttributeFloat("penetration", 0)
            if structureDamage > 0 then attacks[#attacks + 1] = "Structure damage  " .. text(structureDamage) end
            if itemDamage > 0 then attacks[#attacks + 1] = "Item damage  " .. text(itemDamage) end
            if penetration > 0 then attacks[#attacks + 1] = "Penetration  " .. text(math.floor(penetration * PERCENT_SCALE + 0.5)) .. "%" end
        elseif name == "affliction" and context == "attack" then
            local strength = element.GetAttributeFloat("strength", element.GetAttributeFloat("amount", 0))
            local probability = element.GetAttributeFloat("probability", 1)
            attacks[#attacks + 1] = prettyIdentifier(element.GetAttributeString("identifier", "damage")) .. "  " .. text(strength) ..
                (probability < 1 and "  (" .. text(math.floor(probability * 100)) .. "% chance)" or "")
        elseif name == "requireditem" and context ~= nil then
            local identifier = element.GetAttributeIdentifier("identifier", "")
            local target = findItemPrefab(identifier)
            requirements[#requirements + 1] = target and text(target.Name) or prettyIdentifier(identifier)
        end
        for child in element.Elements() do walk(child, nextContext) end
    end
    walk(root, nil)
    if #equipment > 0 then heading(parent, "\nEquipment"); for _, value in ipairs(equipment) do line(parent, value) end end
    if #protection > 0 or #stats > 0 or #skillBonuses > 0 then
        heading(parent, "\nProtection and passive effects")
        for _, value in ipairs(protection) do line(parent, value) end
        for _, value in ipairs(stats) do line(parent, value) end
        for _, value in ipairs(skillBonuses) do line(parent, value) end
    end
    if #attacks > 0 then heading(parent, "\nDamage"); for _, value in ipairs(attacks) do line(parent, value) end end
    if #requirements > 0 then heading(parent, "\nRequires to operate"); for _, value in ipairs(requirements) do line(parent, value) end end
end

local function showMerchantInfo(prefab, parent)
    local priceElement = prefab.ConfigElement and prefab.ConfigElement.GetChildElement("price") or nil
    if priceElement == nil and prefab.DefaultPrice == nil then return end
    heading(parent, "\nMerchants and prices")
    local staticCount = 0
    if priceElement ~= nil then
        local basePrice = priceElement.GetAttributeInt("baseprice", prefab.DefaultPrice and prefab.DefaultPrice.Price or 0)
        for storePrice in priceElement.GetChildElements("price") do
            if storePrice.GetAttributeBool("sold", priceElement.GetAttributeBool("sold", true)) then
                staticCount = staticCount + 1
                local storeIdentifier = id(storePrice.GetAttributeString("storeidentifier", storePrice.GetAttributeString("locationtype", "merchant")))
                local price = math.floor(basePrice * storePrice.GetAttributeFloat("multiplier", 1) + 0.5)
                local restrictions = {}
                local faction = storePrice.GetAttributeString("requiredfaction", "")
                if faction ~= "" then restrictions[#restrictions + 1] = "faction " .. prettyIdentifier(faction) end
                for reputation in storePrice.GetChildElements("reputation") do
                    restrictions[#restrictions + 1] = prettyIdentifier(reputation.GetAttributeString("faction", "")) .. " reputation " .. text(reputation.GetAttributeFloat("min", 0))
                end
                line(parent, (merchantNames[storeIdentifier] or prettyIdentifier(storeIdentifier)) .. "  " .. text(price) .. " mk base" ..
                    (#restrictions > 0 and "  •  " .. table.concat(restrictions, ", ") or ""))
            end
        end
        if staticCount == 0 and priceElement.GetAttributeBool("sold", true) then
            staticCount = 1
            line(parent, "Standard merchants  " .. text(basePrice) .. " mk base")
        end
    end
    if staticCount == 0 then line(parent, "Not sold by standard merchants.") end

    local campaign = Game.GameSession and Game.GameSession.Campaign or nil
    local location = campaign and campaign.Map and campaign.Map.CurrentLocation or nil
    local liveCount = 0
    if location ~= nil and location.Stores ~= nil then
        pcall(function()
            for pair in location.Stores do
                local store = pair.Value or pair
                local info = prefab.GetPriceInfo(store)
                if info ~= nil and info.CanBeBought then
                    liveCount = liveCount + 1
                    local price = store.GetAdjustedItemBuyPrice(prefab, info, true)
                    line(parent, (merchantNames[id(store.Identifier)] or prettyIdentifier(store.Identifier)) .. "  " .. text(price) .. " mk  •  LIVE ADJUSTED")
                end
            end
        end)
    end
    if liveCount == 0 then line(parent, "Live adjusted prices appear while docked at an applicable campaign merchant.") end
end

function showItem(entry)
    clear(detailList)
    local p = entry.prefab
    local hero = GUI.Frame(GUI.RectTransform(UI_VECTOR.ITEM_HERO, detailList.Content.RectTransform, Anchor.TopCenter), "InnerFrame")
    local sprite = p.InventoryIcon or p.Sprite
    if sprite ~= nil then
        local image = GUI.Image(GUI.RectTransform(UI_VECTOR.ITEM_HERO_ICON, hero.RectTransform, Anchor.CenterLeft), sprite, true)
        image.RectTransform.RelativeOffset = UI_VECTOR.OFFSET_STANDARD; image.Color = p.InventoryIcon and p.InventoryIconColor or p.SpriteColor
        image.CanBeFocused = false
    end
    local title = GUI.TextBlock(GUI.RectTransform(UI_VECTOR.ITEM_HERO_TITLE, hero.RectTransform, Anchor.TopRight),
        string.upper(entry.name), palette.cyan, GUI.Style.SubHeadingFont, Alignment.CenterLeft, false, "")
    title.CanBeFocused = false
    local description = text(p.Description)
    local summary = GUI.TextBlock(GUI.RectTransform(UI_VECTOR.ITEM_HERO_SUMMARY, hero.RectTransform, Anchor.BottomRight),
        description ~= "" and description or "No description supplied by the loaded content package.",
        Color(206, 213, 190, 255), GUI.Style.SmallFont, Alignment.TopLeft, true, "")
    summary.CanBeFocused = false
    infoRow(detailList.Content.RectTransform, "Identifier", entry.identifier)
    infoRow(detailList.Content.RectTransform, "Category", categoryText(p.Category), palette.orange)
    if joined(p.Tags) ~= "" then infoRow(detailList.Content.RectTransform, "Tags", joined(p.Tags), palette.muted) end
    if p.DefaultPrice ~= nil then infoRow(detailList.Content.RectTransform, "Base price", text(p.DefaultPrice.Price) .. " mk", palette.green) end
    if p.MaxStackSize ~= nil then infoRow(detailList.Content.RectTransform, "Stack size", text(p.MaxStackSize)) end
    local recipes = E.each(p.FabricationRecipes.Values)
    if #recipes == 0 then
        if renderXmlRecipes(p, detailList.Content.RectTransform) == 0 then
            heading(detailList.Content.RectTransform, "\nCrafting")
            line(detailList.Content.RectTransform, "Not craftable: the loaded prefab defines no fabrication recipe.")
        end
    else
        heading(detailList.Content.RectTransform, "\nCrafting")
        for recipeIndex, recipe in ipairs(recipes) do
            if #recipes > 1 then heading(detailList.Content.RectTransform,
                recipeTitle(recipeIndex, #recipes, safeField(recipe, "DisplayName", ""))) end
            line(detailList.Content.RectTransform, "OUTPUT x" .. text(recipe.Amount) .. "  •  " .. text(recipe.RequiredTime) .. " s")
            line(detailList.Content.RectTransform, "DEVICE  " .. joinedPretty(recipe.SuitableFabricatorIdentifiers))
            local requiredSkills = E.each(recipe.RequiredSkills)
            if #requiredSkills > 0 or recipe.RequiresRecipe then heading(detailList.Content.RectTransform, "Requirements") end
            for _, skill in ipairs(requiredSkills) do
                skillRequirement(detailList.Content.RectTransform, skill.Identifier, skill.Level, skill.DisplayName, skill.Icon)
            end
            if recipe.RequiresRecipe then recipeUnlockRequirements(detailList.Content.RectTransform, p) end
            for _, requirement in ipairs(E.each(recipe.RequiredItems)) do
                local candidates = E.each(safeField(requirement, "ItemPrefabs", nil))
                if #candidates == 0 and requirement.FirstMatchingPrefab ~= nil then candidates[1] = requirement.FirstMatchingPrefab end
                recipeIngredient(detailList.Content.RectTransform, candidates, requirement.Amount,
                    safeField(requirement, "MinCondition", 0), safeField(requirement, "MaxCondition", 1))
            end
        end
    end

    local used = reverseCraft[entry.identifier] or {}
    if #used > 0 then heading(detailList.Content.RectTransform, "\nCan be used to craft") end
    for _, target in ipairs(used) do itemButton(detailList.Content.RectTransform, target) end

    local outputs, combinedOutputs = E.each(p.DeconstructItems), {}
    for _, output in ipairs(outputs) do
        local outputIdentifier = id(output.ItemIdentifier)
        local combined = combinedOutputs[outputIdentifier]
        if combined == nil then
            combined = { identifier = output.ItemIdentifier, amount = 0, commonness = 1 }
            combinedOutputs[outputIdentifier] = combined
        end
        combined.amount = combined.amount + (tonumber(output.Amount) or 0)
        combined.commonness = math.min(combined.commonness, tonumber(output.Commonness) or 1)
    end
    if #outputs > 0 then heading(detailList.Content.RectTransform, "\nDeconstructs into") end
    local sortedOutputs = {}
    for _, output in pairs(combinedOutputs) do sortedOutputs[#sortedOutputs + 1] = output end
    table.sort(sortedOutputs, function(a, b) return id(a.identifier) < id(b.identifier) end)
    for _, output in ipairs(sortedOutputs) do
        local target = findItemPrefab(output.identifier)
        local suffix = "  x" .. text(output.amount)
        if output.commonness < 1 then suffix = suffix .. "  (conditional, " .. text(math.floor(output.commonness * 100)) .. "% minimum)" end
        if target ~= nil then itemButton(detailList.Content.RectTransform, {prefab=target, identifier=id(target.Identifier), name=text(target.Name)}, suffix)
        else line(detailList.Content.RectTransform, text(output.identifier) .. suffix) end
    end

    local sources = reverseDeconstruct[entry.identifier] or {}
    if #sources > 0 then heading(detailList.Content.RectTransform, "\nDeconstruction sources") end
    local combinedSources = {}
    for _, source in ipairs(sources) do
        local key = source.source.identifier
        combinedSources[key] = combinedSources[key] or { source = source.source, amount = 0 }
        combinedSources[key].amount = combinedSources[key].amount + (tonumber(source.output.Amount) or 0)
    end
    local sortedSources = {}; for _, source in pairs(combinedSources) do sortedSources[#sortedSources + 1] = source end
    table.sort(sortedSources, function(a, b) return a.source.name < b.source.name end)
    for _, source in ipairs(sortedSources) do itemButton(detailList.Content.RectTransform, source.source, "  → x" .. text(source.amount)) end

    showItemCapabilities(p, detailList.Content.RectTransform)
    showMerchantInfo(p, detailList.Content.RectTransform)
end

local function collectCreatureDrops(prefab)
    local drops = {}
    local function addDrop(identifier, amount, note)
        local key = id(identifier)
        if key == "" then return end
        local drop = drops[key] or { identifier = identifier, amount = 0, notes = {} }
        drop.amount = math.max(drop.amount, tonumber(amount) or 1)
        if note ~= nil and note ~= "" then drop.notes[note] = true end
        drops[key] = drop
    end
    local function walk(element, deconstruction)
        if element == nil then return end
        local elementName = id(element.NameAsIdentifier())
        local isDeconstruction = deconstruction
        if elementName == "statuseffect" then
            isDeconstruction = id(element.GetAttributeString("type", "")) == "ondeconstructed"
        elseif elementName == "inventory" then
            local weight = element.GetAttributeFloat("commonness", 1)
            for child in element.Elements() do
                if id(child.NameAsIdentifier()) == "item" then
                    local chance = child.GetAttributeFloat("commonness", 1)
                    addDrop(child.GetAttributeIdentifier("identifier", ""), child.GetAttributeInt("amount", 1),
                        "loot pool weight " .. text(weight * chance))
                end
            end
        elseif elementName == "spawnitem" and isDeconstruction then
            local identifiers = element.GetAttributeString("identifiers", element.GetAttributeString("identifier", ""))
            local probability = element.GetAttributeFloat("probability", 1)
            for identifier in string.gmatch(identifiers, "[^,%s]+") do
                addDrop(identifier, element.GetAttributeInt("count", 1), text(math.floor(probability * 100)) .. "% when deconstructed")
            end
        end
        for child in element.Elements() do walk(child, isDeconstruction) end
    end
    walk(prefab.ConfigElement, false)
    local result = {}
    for _, drop in pairs(drops) do result[#result + 1] = drop end
    table.sort(result, function(a, b) return id(a.identifier) < id(b.identifier) end)
    return result
end

local function showCreature(entry)
    clear(detailList)
    local p = entry.prefab
    heading(detailList.Content.RectTransform, entry.name)
    local wiki = wikiCreatures[entry.identifier]
    local preview = wikiCreatureSprite(entry) or creaturePreviewSprite(p)
    if preview ~= nil then
        local previewFrame = GUI.Frame(GUI.RectTransform(UI_VECTOR.CREATURE_PREVIEW, detailList.Content.RectTransform, Anchor.TopCenter), "InnerFrame")
        local previewButton = GUI.Button(GUI.RectTransform(UI_VECTOR.FULL, previewFrame.RectTransform, Anchor.Center), "", Alignment.Center, "ListBoxElement")
        local image = GUI.Image(GUI.RectTransform(UI_VECTOR.CREATURE_PREVIEW_IMAGE, previewButton.RectTransform, Anchor.Center), preview, true)
        image.CanBeFocused = false
        previewButton.ToolTip = "Click to enlarge"
        previewButton.OnClicked = function() showImageOverlay(preview, entry.name); return true end
    end
    line(detailList.Content.RectTransform, "SPECIES  " .. entry.name)
    local variantIdentifier = id(p.VariantOf)
    if variantIdentifier ~= "" then
        local parentPrefab = findCharacterPrefab(variantIdentifier)
        line(detailList.Content.RectTransform, "VARIANT OF  " .. (parentPrefab and text(parentPrefab.Name) or prettyIdentifier(variantIdentifier)))
    end
    if p.ConfigElement ~= nil then
        local description = wiki and wiki.description or p.ConfigElement.GetAttributeString("description", "")
        heading(detailList.Content.RectTransform, "\nDescription")
        line(detailList.Content.RectTransform, description ~= "" and description or "No official description is provided by the loaded content package.")
        if wiki ~= nil then line(detailList.Content.RectTransform, "SOURCE  Official Barotrauma Wiki  •  current game statistics remain prefab-derived") end
        local health = p.ConfigElement.GetChildElement("health")
        local vitality = health and health.GetAttributeFloat("vitality", 0) or 0
        if vitality > 0 then heading(detailList.Content.RectTransform, "\nHealth"); line(detailList.Content.RectTransform, "VITALITY  " .. text(vitality)) end
        local group = text(p.Group)
        if group ~= "" then line(detailList.Content.RectTransform, "GROUP  " .. prettyIdentifier(group)) end
    end
    heading(detailList.Content.RectTransform, "\nFound in")
    if #entry.habitats > 0 then line(detailList.Content.RectTransform, table.concat(entry.habitats, ", "))
    else line(detailList.Content.RectTransform, "No standard monster-event habitat is declared for this creature.") end
    local drops = collectCreatureDrops(p)
    heading(detailList.Content.RectTransform, "\nDrops")
    if #drops == 0 then line(detailList.Content.RectTransform, "No corpse loot or deconstruction drops are declared.") end
    for _, drop in ipairs(drops) do
        local target = findItemPrefab(drop.identifier)
        local notes = {}; for note in pairs(drop.notes) do notes[#notes + 1] = note end; table.sort(notes)
        local suffix = "  x" .. text(drop.amount) .. (#notes > 0 and "  •  " .. table.concat(notes, ", ") or "")
        if target ~= nil then itemButton(detailList.Content.RectTransform, {prefab=target, identifier=id(target.Identifier), name=text(target.Name)}, suffix)
        else line(detailList.Content.RectTransform, prettyIdentifier(drop.identifier) .. suffix) end
    end
end

local function findTalent(identifier)
    local key = id(identifier)
    for talent in TalentPrefab.TalentPrefabs do
        if talent ~= nil and id(talent.Identifier) == key then return talent end
    end
    return nil
end

local function afflictionIcon(prefab)
    local icon = safeField(prefab, "Icon", nil)
    if icon ~= nil then return icon end
    local afflictionType = id(safeField(prefab, "AfflictionType", safeField(prefab, "Type", "")))
    for candidate in AfflictionPrefab.Prefabs do
        local candidateType = id(safeField(candidate, "AfflictionType", safeField(candidate, "Type", "")))
        local candidateIcon = safeField(candidate, "Icon", nil)
        if afflictionType ~= "" and candidateType == afflictionType and candidateIcon ~= nil then return candidateIcon end
    end
    for _, fallbackIdentifier in ipairs({"stun", "psychosis", "oxygenlow"}) do
        for candidate in AfflictionPrefab.Prefabs do
            if id(candidate.Identifier) == fallbackIdentifier then
                local fallbackIcon = safeField(candidate, "Icon", nil)
                if fallbackIcon ~= nil then return fallbackIcon end
            end
        end
    end
    return nil
end

local function talentTile(parent, identifier, tileSize)
    local talent = findTalent(identifier)
    local tile = GUI.Frame(GUI.RectTransform(tileSize or UI_VECTOR.TALENT_TILE, parent, Anchor.CenterLeft), "TalentBackground")
    if talent ~= nil and talent.Icon ~= nil then
        local image = GUI.Image(GUI.RectTransform(UI_VECTOR.TALENT_ICON, tile.RectTransform, Anchor.Center), talent.Icon, true)
        image.CanBeFocused = false
    else label(tile.RectTransform, "?", Alignment.Center, palette.cyan) end
    local name = talent and text(talent.DisplayName) or prettyIdentifier(identifier)
    local description = talent and cleanDisplayText(talent.Description) or "No description is exposed by this talent prefab."
    tile.ToolTip = name .. "\n\n" .. description
    return tile
end

local function centeredTalentTiles(layout, identifiers, tileSize, tileWidth)
    local spacerWidth = math.max(0, (1 - #identifiers * tileWidth) / 2)
    if spacerWidth > 0 then GUI.Frame(GUI.RectTransform(relativeVector(spacerWidth, 1), layout), nil) end
    for _, identifier in ipairs(identifiers) do talentTile(layout, identifier, tileSize) end
    if spacerWidth > 0 then GUI.Frame(GUI.RectTransform(relativeVector(spacerWidth, 1), layout), nil) end
end

local function showProfession(entry, focusSkill)
    clear(detailList)
    local p = entry.prefab
    local header = GUI.Frame(GUI.RectTransform(UI_VECTOR.PROFESSION_HEADER, detailList.Content.RectTransform, Anchor.TopCenter), "InnerFrame")
    local jobIcon = safeField(p, "Icon", safeField(p, "IconSmall", nil))
    if jobIcon ~= nil then
        local image = GUI.Image(GUI.RectTransform(UI_VECTOR.PROFESSION_ICON, header.RectTransform, Anchor.CenterLeft), jobIcon, true)
        image.RectTransform.RelativeOffset = UI_VECTOR.OFFSET_STANDARD; image.CanBeFocused = false
    end
    local title = GUI.TextBlock(GUI.RectTransform(UI_VECTOR.PROFESSION_TITLE, header.RectTransform, Anchor.TopRight),
        string.upper(entry.name), palette.cyan, GUI.Style.SubHeadingFont, Alignment.CenterLeft, false, "")
    title.CanBeFocused = false
    local description = text(safeField(p, "Description", ""))
    local summary = GUI.TextBlock(GUI.RectTransform(UI_VECTOR.PROFESSION_SUMMARY, header.RectTransform, Anchor.BottomRight),
        description ~= "" and description or "Read-only profession reference and talent tree.",
        Color(206, 213, 190, 255), GUI.Style.SmallFont, Alignment.TopLeft, true, "")
    summary.CanBeFocused = false
    heading(detailList.Content.RectTransform, "\nStarting skills")
    local skillsXml = string.match(entry.jobXml or "", "<[Ss]kills[^>]*>(.-)</[Ss]kills>") or ""
    local skillCount = 0
    for skillTag in string.gmatch(skillsXml, "<[Ss]kill%s+([^>/]-)/?>") do
        local identifier = xmlAttribute(skillTag, "identifier", "")
        local range = xmlAttribute(skillTag, "level", "0")
        if identifier ~= "" then
            skillCount = skillCount + 1
            if id(identifier) == id(focusSkill) then
                requirementRow(detailList.Content.RectTransform,
                    string.upper(prettyIdentifier(identifier)) .. "  •  " .. range .. " starting skill",
                    fallbackSkillIcon(identifier), "Crafting requirement points to this profession skill.")
            else
                iconInfoRow(detailList.Content.RectTransform, fallbackSkillIcon(identifier),
                    prettyIdentifier(identifier), range .. " starting skill", palette.cream)
            end
        end
    end
    if skillCount == 0 then line(detailList.Content.RectTransform, "No starting-skill definition was found for this loaded profession.") end
    heading(detailList.Content.RectTransform, "\nTalent tree")
    line(detailList.Content.RectTransform, "REFERENCE ONLY  •  Hover a talent icon to read its name and effect.")
    local treeXml = entry.treeXml or ""
    if treeXml == "" then
        line(detailList.Content.RectTransform, "This loaded profession does not expose a talent tree.")
        return
    end
    local paths, maximumStages = {}, 0
    for subtreeTag, subtreeBody in string.gmatch(treeXml, "<[Ss]ub[Tt]ree([^>]*)>(.-)</[Ss]ub[Tt]ree>") do
        local path = {
            name=prettyIdentifier(xmlAttribute(subtreeTag, "identifier", "Talent path")),
            pathType=id(xmlAttribute(subtreeTag, "type", "specialization")), stages={}
        }
        for stageBody in string.gmatch(subtreeBody, "<[Tt]alent[Oo]ptions[^>]*>(.-)</[Tt]alent[Oo]ptions>") do
            local stage = {}
            for optionTag in string.gmatch(stageBody, "<[Tt]alent[Oo]ption%s+([^>/]-)/?>") do
                local identifier = xmlAttribute(optionTag, "identifier", "")
                if identifier ~= "" then stage[#stage + 1] = identifier end
            end
            path.stages[#path.stages + 1] = stage
        end
        maximumStages = math.max(maximumStages, #path.stages)
        paths[#paths + 1] = path
    end
    for _, path in ipairs(paths) do
        if path.pathType == "primary" then
            heading(detailList.Content.RectTransform, path.name)
            for _, stage in ipairs(path.stages) do
                local primaryFrame = GUI.Frame(GUI.RectTransform(UI_VECTOR.TALENT_PRIMARY_ROW, detailList.Content.RectTransform, Anchor.TopCenter), "InnerFrame")
                primaryFrame.Color = TALENT_ROW_COLOR
                local primaryOptions = GUI.LayoutGroup(GUI.RectTransform(UI_VECTOR.TALENT_PATH_OPTIONS, primaryFrame.RectTransform, Anchor.Center), true, Anchor.CenterLeft)
                centeredTalentTiles(primaryOptions.RectTransform, stage, UI_VECTOR.TALENT_PRIMARY_TILE, TALENT_PRIMARY_TILE_WIDTH)
            end
        end
    end
    local specializations = {}
    maximumStages = 0
    for _, path in ipairs(paths) do
        if path.pathType ~= "primary" then
            specializations[#specializations + 1] = path
            maximumStages = math.max(maximumStages, #path.stages)
        end
    end
    local treeHeight = TALENT_TREE_BASE_HEIGHT + maximumStages * TALENT_TREE_STAGE_HEIGHT
    local tree = GUI.Frame(GUI.RectTransform(relativeVector(1, treeHeight), detailList.Content.RectTransform, Anchor.TopCenter), "InnerFrame")
    local columnAnchors = {Anchor.TopLeft, Anchor.TopCenter, Anchor.TopRight}
    for pathIndex, path in ipairs(specializations) do
        if pathIndex <= #columnAnchors then
            local column = GUI.LayoutGroup(GUI.RectTransform(UI_VECTOR.TALENT_COLUMN, tree.RectTransform, columnAnchors[pathIndex]), false, Anchor.TopCenter)
            local columnRowHeight = 1 / (#path.stages + 1)
            local pathHeader = GUI.Button(GUI.RectTransform(relativeVector(1, columnRowHeight), column.RectTransform), string.upper(path.name), Alignment.Center, "GUIButtonSmall")
            pathHeader.Enabled = false
            for _, stage in ipairs(path.stages) do
                local stageFrame = GUI.Frame(GUI.RectTransform(relativeVector(1, columnRowHeight), column.RectTransform), "InnerFrame")
                stageFrame.Color = TALENT_ROW_COLOR
                local options = GUI.LayoutGroup(GUI.RectTransform(UI_VECTOR.TALENT_PATH_OPTIONS, stageFrame.RectTransform, Anchor.Center), true, Anchor.CenterLeft)
                centeredTalentTiles(options.RectTransform, stage, UI_VECTOR.TALENT_TILE, TALENT_TILE_WIDTH)
            end
        end
    end
end

local function itemAfflictionLinks(targetIdentifier, targetType)
    local treatments, causes = {}, {}
    local target, typeTarget = id(targetIdentifier), id(targetType)
    local function scanItem(entry)
        local treatmentStrength, suitability, causeStrength = 0, 0, 0
        local numericCategory = tonumber(entry.prefab.Category) or 0
        local isMedical = math.floor(numericCategory / ITEM_CATEGORY.MEDICAL) % 2 == 1
        local function walk(element)
            local name = id(element.NameAsIdentifier())
            if name == "suitabletreatment" and isMedical then
                local suitableIdentifier = id(element.GetAttributeString("identifier", ""))
                local suitableType = id(element.GetAttributeString("type", ""))
                if suitableIdentifier == target or (typeTarget ~= "" and suitableType == typeTarget) then
                    suitability = math.max(suitability, element.GetAttributeFloat("suitability", 0))
                end
            elseif name == "reduceaffliction" and isMedical then
                local identifier = id(element.GetAttributeString("identifier", ""))
                local afflictionType = id(element.GetAttributeString("type", ""))
                if identifier == target or (typeTarget ~= "" and afflictionType == typeTarget) then
                    local amount = element.GetAttributeFloat("amount", element.GetAttributeFloat("strength", 0))
                    treatmentStrength = math.max(treatmentStrength, math.abs(amount))
                end
            elseif name == "affliction" then
                local identifier = id(element.GetAttributeString("identifier", ""))
                if identifier == target then
                    local strength = element.GetAttributeFloat("strength", element.GetAttributeFloat("amount", 0))
                    if strength < 0 then treatmentStrength = treatmentStrength + math.abs(strength)
                    elseif strength > 0 then causeStrength = causeStrength + strength end
                end
            end
            for child in element.Elements() do walk(child) end
        end
        if entry.prefab.ConfigElement ~= nil then walk(entry.prefab.ConfigElement) end
        if treatmentStrength > 0 or suitability > 0 then
            treatments[#treatments + 1] = {entry=entry, strength=treatmentStrength, suitability=suitability}
        end
        if causeStrength > 0 then causes[#causes + 1] = {entry=entry, strength=causeStrength} end
    end
    for _, item in ipairs(items) do scanItem(item) end
    table.sort(treatments, function(a, b)
        if a.suitability ~= b.suitability then return a.suitability > b.suitability end
        if a.strength ~= b.strength then return a.strength > b.strength end
        return a.entry.name < b.entry.name
    end)
    table.sort(causes, function(a, b) return a.strength > b.strength end)
    return treatments, causes
end

local showAffliction
local function afflictionButton(parent, entry, suffix)
    local button = GUI.Button(GUI.RectTransform(UI_VECTOR.LINK_ROW, parent, Anchor.TopCenter), "", Alignment.CenterLeft, "ListBoxElement")
    local sprite = afflictionIcon(entry.prefab)
    if sprite ~= nil then
        local icon = GUI.Image(GUI.RectTransform(UI_VECTOR.LINK_ICON, button.RectTransform, Anchor.CenterLeft), sprite, true)
        icon.CanBeFocused = false
    end
    local caption = GUI.TextBlock(GUI.RectTransform(UI_VECTOR.LINK_TEXT, button.RectTransform, Anchor.CenterRight),
        entry.name .. (suffix or ""), nil, GUI.Style.SmallFont, Alignment.CenterLeft, false, "")
    caption.CanBeFocused = false
    button.OnClicked = function() navigateTo("Afflictions", entry); return true end
    return button
end

showAffliction = function(entry)
    clear(detailList)
    local p = entry.prefab
    local icon = afflictionIcon(p)
    local afflictionType = text(safeField(p, "AfflictionType", safeField(p, "Type", "Affliction")))
    iconInfoRow(detailList.Content.RectTransform, icon, entry.name, prettyIdentifier(afflictionType), palette.cyan)
    local description = cleanDisplayText(safeField(p, "Description", ""))
    heading(detailList.Content.RectTransform, "\nEffect")
    line(detailList.Content.RectTransform, description ~= "" and description or "No general description is supplied by the loaded content package.")
    local maxStrength = safeField(p, "MaxStrength", 100)
    infoRow(detailList.Content.RectTransform, "Maximum strength", numberText(maxStrength))
    infoRow(detailList.Content.RectTransform, "Limb specific", safeField(p, "LimbSpecific", false) and "Yes" or "No")
    heading(detailList.Content.RectTransform, "\nStat debuffs by strength")
    local effectCount = 0
    for _, effect in ipairs(E.each(safeField(p, "Effects", nil))) do
        effectCount = effectCount + 1
        local range = numberText(safeField(effect, "MinStrength", 0)) .. "–" .. numberText(safeField(effect, "MaxStrength", maxStrength))
        local values = {}
        for _, field in ipairs({"MinVitalityDecrease", "MaxVitalityDecrease", "StrengthChange", "SpeedMultiplier", "SkillMultiplier", "Resistance"}) do
            local value = safeField(effect, field, nil)
            local numeric = tonumber(value)
            local multiplier = field == "SpeedMultiplier" or field == "SkillMultiplier" or field == "Resistance"
            if value ~= nil and ((numeric == nil) or (multiplier and numeric ~= 1) or (not multiplier and numeric ~= 0)) then
                values[#values + 1] = prettyIdentifier(field) .. "  " .. numberText(value)
            end
        end
        infoRow(detailList.Content.RectTransform, "Strength " .. range, #values > 0 and table.concat(values, "  •  ") or "Behavior defined by this effect stage", palette.red)
    end
    if effectCount == 0 then line(detailList.Content.RectTransform, "No staged stat modifiers are exposed through LuaCs for this affliction.") end
    local treatments, causes = itemAfflictionLinks(entry.identifier, afflictionType)
    heading(detailList.Content.RectTransform, "\nTreatments")
    if #treatments == 0 then line(detailList.Content.RectTransform, "No loaded medical item is marked as a suitable treatment.") end
    for _, link in ipairs(treatments) do
        local details = link.strength > 0 and ("  •  reduces up to " .. numberText(link.strength)) or ""
        if link.suitability > 0 then details = details .. "  •  suitability " .. numberText(link.suitability) end
        itemButton(detailList.Content.RectTransform, link.entry, details)
    end
    heading(detailList.Content.RectTransform, "\nCaused by")
    local relatedCauses = { bloodloss={"bleeding"} }
    local relatedCount = 0
    for _, identifier in ipairs(relatedCauses[entry.identifier] or {}) do
        local related = afflictionByIdentifier[identifier]
        if related ~= nil then
            relatedCount = relatedCount + 1
            afflictionButton(detailList.Content.RectTransform, related, "  •  ongoing cause")
        end
    end
    if #causes == 0 and relatedCount == 0 then line(detailList.Content.RectTransform, "No direct cause is declared by loaded items or afflictions.") end
    for _, link in ipairs(causes) do itemButton(detailList.Content.RectTransform, link.entry, "  •  applies " .. numberText(link.strength)) end
end

navigateTo = function(category, entry, focus)
    if entry == nil then return end
    currentCategory = category
    currentSearch = ""
    if searchBox ~= nil then searchBox.Text = "" end
    if itemFilterControls ~= nil then itemFilterControls.Visible = category == "Items" end
    populateList()
    for tabCategory, button in pairs(tabButtons) do button.Selected = tabCategory == category end
    if category == "Bestiary" then showCreature(entry)
    elseif category == "Items" then showItem(entry)
    elseif category == "Professions" then showProfession(entry, focus)
    else showAffliction(entry) end
end

function populateList(forceSearch)
    if listBox == nil then return end
    if forceSearch ~= nil then currentSearch = forceSearch; searchBox.Text = forceSearch end
    clear(listBox)
    local source = items
    if currentCategory == "Bestiary" then source = creatures
    elseif currentCategory == "Professions" then source = professions
    elseif currentCategory == "Afflictions" then source = afflictions end
    local shown, limit = 0, tonumber(settings.pageSize) or DEFAULT_SETTINGS.pageSize
    for _, entry in ipairs(source) do
        local tags, category = "", ""
        if currentCategory == "Items" then
            tags = joined(entry.prefab.Tags)
            category = categoryText(entry.prefab.Category)
        elseif currentCategory == "Afflictions" then
            category = text(safeField(entry.prefab, "AfflictionType", safeField(entry.prefab, "Type", "")))
        end
        local matchesItemFilter = currentCategory ~= "Items" or itemCategoryFilter == "All" or itemFilterCategory(entry) == itemCategoryFilter
        if matchesItemFilter and (E.contains(entry.name, currentSearch) or E.contains(entry.identifier, currentSearch) or E.contains(tags, currentSearch) or E.contains(category, currentSearch)) then
            shown = shown + 1
            if shown <= limit then
                local label = entry.name
                local button = GUI.Button(GUI.RectTransform(UI_VECTOR.INDEX_ROW, listBox.Content.RectTransform), "", Alignment.CenterLeft, "ListBoxElement")
                if currentCategory ~= "Bestiary" then
                    local sprite = nil
                    if currentCategory == "Items" then sprite = entry.prefab.InventoryIcon or entry.prefab.Sprite
                    elseif currentCategory == "Professions" then sprite = safeField(entry.prefab, "IconSmall", safeField(entry.prefab, "Icon", nil))
                    elseif currentCategory == "Afflictions" then sprite = afflictionIcon(entry.prefab) end
                    if sprite ~= nil then
                        local icon = GUI.Image(GUI.RectTransform(UI_VECTOR.INDEX_ICON, button.RectTransform, Anchor.CenterLeft), sprite, true)
                        if currentCategory == "Items" then
                            icon.Color = entry.prefab.InventoryIcon and entry.prefab.InventoryIconColor or entry.prefab.SpriteColor
                        end
                        icon.CanBeFocused = false
                    end
                end
                local captionWidth = currentCategory == "Bestiary" and 0.96 or 0.83
                local caption = GUI.TextBlock(
                    GUI.RectTransform(fullHeightVector(captionWidth), button.RectTransform, Anchor.CenterRight),
                    label, nil, GUI.Style.SmallFont, Alignment.CenterLeft, false, "")
                caption.CanBeFocused = false
                button.OnClicked = function()
                    navigateTo(currentCategory, entry)
                    return true
                end
            end
        end
    end
    if shown > limit then line(listBox.Content.RectTransform, "Refine search to view " .. text(shown - limit) .. " more entries.") end
end

local function selectCategory(name)
    currentCategory = name
    currentSearch = ""
    if searchBox then searchBox.Text = "" end
    populateList()
    clear(detailList)
    if itemFilterControls ~= nil then itemFilterControls.Visible = name == "Items" end
    for category, button in pairs(tabButtons) do button.Selected = category == name end
    heading(detailList.Content.RectTransform, name)
    if name == "Items" then
        line(detailList.Content.RectTransform, "Select an item to view crafting, used-to-craft, deconstruction outputs, and material sources on one page.")
    elseif name == "Professions" then
        line(detailList.Content.RectTransform, "Select a profession to inspect its starting skills and read-only talent tree.")
    elseif name == "Afflictions" then
        line(detailList.Content.RectTransform, "Select an affliction to inspect effects, stat changes, treatments and causes.")
    end
end

local function createWindow()
    local canvas = GUIStatic.Canvas
    local windowSize = UI_VECTOR.WINDOW
    local windowRect = GUI.RectTransform(windowSize, canvas, Anchor.Center)
    window = GUI.Frame(windowRect, "GUIFrameListBox")
    local padded = GUI.Frame(GUI.RectTransform(UI_VECTOR.WINDOW_PADDING, window.RectTransform, Anchor.Center), nil)

    local header = GUI.Frame(GUI.RectTransform(UI_VECTOR.HEADER, padded.RectTransform, Anchor.TopCenter), "InnerFrame")
    local titleArea = GUI.Frame(GUI.RectTransform(UI_VECTOR.HEADER_TITLE_AREA, header.RectTransform, Anchor.TopLeft), nil)
    local title = GUI.TextBlock(
        GUI.RectTransform(UI_VECTOR.HEADER_TITLE, titleArea.RectTransform, Anchor.CenterLeft),
        "EUROPA ENCYCLOPEDIA", Color(101, 203, 218, 255), GUI.Style.SubHeadingFont,
        Alignment.CenterLeft, false, "")
    title.RectTransform.RelativeOffset = UI_VECTOR.OFFSET_TITLE

    local headerControls = GUI.LayoutGroup(GUI.RectTransform(UI_VECTOR.HEADER_CONTROLS, header.RectTransform, Anchor.TopRight), true, Anchor.CenterRight)
    local searchArea = GUI.Frame(GUI.RectTransform(UI_VECTOR.SEARCH_AREA, headerControls.RectTransform), nil)
    searchBox = GUI.TextBox(GUI.RectTransform(UI_VECTOR.SEARCH_BOX, searchArea.RectTransform, Anchor.Center), "")
    searchBox.OnTextChangedDelegate = function(_, newText)
        currentSearch = text(newText)
        populateList()
        return true
    end
    local close = GUI.Button(GUI.RectTransform(UI_VECTOR.HEADER_CLOSE, headerControls.RectTransform), "×", Alignment.Center, "GUICancelButton")
    close.OnClicked = function() toggle(); return true end

    local tabs = GUI.LayoutGroup(GUI.RectTransform(UI_VECTOR.TABS, padded.RectTransform, Anchor.TopCenter), true, Anchor.CenterLeft)
    tabs.RectTransform.RelativeOffset = UI_VECTOR.OFFSET_TABS
    tabButtons = {}
    for _, category in ipairs({"Bestiary", "Items", "Professions", "Afflictions"}) do
        local b = GUI.Button(GUI.RectTransform(UI_VECTOR.TAB_BUTTON, tabs.RectTransform), string.upper(category), Alignment.Center, "GUIButtonSmall")
        b.OnClicked = function() selectCategory(category); return true end
        tabButtons[category] = b
    end
    local body = GUI.Frame(GUI.RectTransform(UI_VECTOR.BODY, padded.RectTransform, Anchor.BottomCenter), nil)
    local left = GUI.Frame(GUI.RectTransform(UI_VECTOR.INDEX_PANEL, body.RectTransform, Anchor.BottomLeft), "InnerFrame")
    local right = GUI.Frame(GUI.RectTransform(UI_VECTOR.DETAIL_PANEL, body.RectTransform, Anchor.BottomRight), "InnerFrame")
    local listHeader = GUI.Frame(GUI.RectTransform(UI_VECTOR.PANEL_HEADER, left.RectTransform, Anchor.TopCenter), nil)
    local listHeaderTitle = GUI.Frame(GUI.RectTransform(UI_VECTOR.LIST_HEADER_TITLE, listHeader.RectTransform, Anchor.CenterLeft), nil)
    label(listHeaderTitle.RectTransform, "INDEX", Alignment.CenterLeft, Color(101, 203, 218, 255))
    itemFilterControls = GUI.LayoutGroup(GUI.RectTransform(UI_VECTOR.FILTER_CONTROLS, listHeader.RectTransform, Anchor.CenterRight), true, Anchor.CenterRight)
    local previousFilter = GUI.Button(GUI.RectTransform(UI_VECTOR.FILTER_PREVIOUS, itemFilterControls.RectTransform), "‹", Alignment.Center, "GUIButtonSmall")
    itemFilterLabel = GUI.Button(GUI.RectTransform(UI_VECTOR.FILTER_LABEL, itemFilterControls.RectTransform), "ALL", Alignment.Center, "GUIButtonSmall")
    itemFilterLabel.Enabled = false
    local nextFilter = GUI.Button(GUI.RectTransform(UI_VECTOR.FILTER_NEXT, itemFilterControls.RectTransform), "›", Alignment.Center, "GUIButtonSmall")
    local function cycleFilter(direction)
        local selectedIndex = 1
        for index, name in ipairs(itemFilterNames) do if name == itemCategoryFilter then selectedIndex = index; break end end
        selectedIndex = ((selectedIndex - 1 + direction) % #itemFilterNames) + 1
        itemCategoryFilter = itemFilterNames[selectedIndex]
        itemFilterLabel.Text = string.upper(itemCategoryFilter)
        populateList()
    end
    previousFilter.OnClicked = function() cycleFilter(-1); return true end
    nextFilter.OnClicked = function() cycleFilter(1); return true end
    local detailHeader = GUI.Frame(GUI.RectTransform(UI_VECTOR.PANEL_HEADER, right.RectTransform, Anchor.TopCenter), nil)
    local detailHeaderTitle = GUI.Frame(GUI.RectTransform(UI_VECTOR.DETAIL_HEADER_TITLE, detailHeader.RectTransform, Anchor.CenterLeft), nil)
    label(detailHeaderTitle.RectTransform, "ARCHIVE RECORD", Alignment.CenterLeft, Color(101, 203, 218, 255))
    listBox = GUI.ListBox(GUI.RectTransform(UI_VECTOR.PANEL_LIST, left.RectTransform, Anchor.BottomCenter))
    detailList = GUI.ListBox(GUI.RectTransform(UI_VECTOR.PANEL_LIST, right.RectTransform, Anchor.BottomCenter))
    selectCategory("Bestiary")
end

toggle = function()
    visible = not visible
    if visible and window == nil then createWindow() end
    if window ~= nil then window.Visible = visible end
    if not visible and imageOverlay ~= nil then imageOverlay.Visible = false; imageOverlay = nil end
    print("[Europa Encyclopedia] " .. (visible and "opened" or "closed"))
end

local function getFocusedEntry()
    local function entryFromPrefab(prefab)
        if prefab == nil or prefab.Identifier == nil then return nil end
        return itemByIdentifier[id(prefab.Identifier)]
    end
    local function prefabFromUserData(data)
        if data == nil then return nil end
        if LuaUserData.IsTargetType(data, "Barotrauma.Item") then return data.Prefab end
        if LuaUserData.IsTargetType(data, "Barotrauma.ItemPrefab") then return data end
        if LuaUserData.IsTargetType(data, "Barotrauma.FabricationRecipe") then return data.TargetItem end
        if LuaUserData.IsTargetType(data, "Barotrauma.PurchasedItem") then return data.ItemPrefab end
        return nil
    end

    local selectedSlot = InventoryStatic.SelectedSlot
    if selectedSlot ~= nil and selectedSlot.Item ~= nil then
        local entry = entryFromPrefab(selectedSlot.Item.Prefab)
        if entry ~= nil then return "Items", entry end
    end

    local hovered = GUIStatic.MouseOn
    local depth = 0
    while hovered ~= nil and depth < MAX_GUI_PARENT_DEPTH do
        local entry = entryFromPrefab(prefabFromUserData(hovered.UserData))
        if entry ~= nil then return "Items", entry end
        hovered = hovered.Parent
        depth = depth + 1
    end

    local controlled = Character.Controlled
    if controlled == nil then return nil, nil end
    local focusedItem = controlled.FocusedItem
    if focusedItem ~= nil and focusedItem.Prefab ~= nil then
        local entry = itemByIdentifier[id(focusedItem.Prefab.Identifier)]
        if entry ~= nil then return "Items", entry end
    end
    local focusedCharacter = controlled.FocusedCharacter
    if focusedCharacter == nil and controlled.SelectedCharacter ~= nil and controlled.SelectedCharacter.IsDead then
        focusedCharacter = controlled.SelectedCharacter
    end
    if focusedCharacter ~= nil and focusedCharacter.IsDead and focusedCharacter.SpeciesName ~= nil then
        local entry = creatureByIdentifier[id(focusedCharacter.SpeciesName)]
        if entry ~= nil then return "Bestiary", entry end
    end
    return nil, nil
end

local function openFocusedEntry()
    local category, entry = getFocusedEntry()
    if entry == nil then return false end
    visible = true
    if window == nil then createWindow() end
    window.Visible = true
    navigateTo(category, entry)
    print("[Europa Encyclopedia] opened focused " .. string.lower(category) .. " entry: " .. entry.name)
    return true
end

local function updateContextHint()
    local category, entry = getFocusedEntry()
    if visible or entry == nil then
        if contextHint ~= nil then contextHint.Visible = false end
        return
    end
    if contextHint == nil then
        contextHint = GUI.Frame(GUI.RectTransform(UI_VECTOR.CONTEXT_HINT, GUIStatic.Canvas, Anchor.BottomCenter), "InnerFrame")
        contextHint.RectTransform.RelativeOffset = UI_VECTOR.OFFSET_CONTEXT_HINT
        contextHintText = GUI.TextBlock(GUI.RectTransform(UI_VECTOR.CONTEXT_HINT_TEXT, contextHint.RectTransform, Anchor.Center),
            "", Color(206, 213, 190, 255), GUI.Style.SmallFont, Alignment.Center, false, "")
        contextHintText.CanBeFocused = false
    end
    contextHintText.Text = "[" .. text(settings.openKey) .. "]  OPEN " .. string.upper(category) .. ":  " .. entry.name
    contextHint.Visible = true
    contextHint.AddToGUIUpdateList(false, GUI_ORDER.CONTEXT_HINT)
end

Hook.Add("think", "EuropaEncyclopedia.Input", function()
    updateContextHint()
    if PlayerInput.KeyHit(openKey) then
        if visible then toggle()
        elseif not openFocusedEntry() then toggle() end
    end
    if visible and PlayerInput.KeyHit(Keys.Escape) then toggle() end
    if visible and window ~= nil then window.AddToGUIUpdateList(false, GUI_ORDER.WINDOW) end
    if imageOverlay ~= nil then imageOverlay.AddToGUIUpdateList(false, GUI_ORDER.IMAGE_OVERLAY) end
end)

Game.AddCommand("encyclopedia", "Toggle the Europa Encyclopedia", function() toggle() end)

Game.AddCommand("encyclopedia_corpse", "Single player: spawn a creature at the cursor and turn spawned monsters into corpses", function(args)
    if not Game.IsSingleplayer then
        print("[Europa Encyclopedia] encyclopedia_corpse is a single-player test command.")
        return
    end
    local target = id(args and args[1] or "")
    if target == "" or findCharacterPrefab(target) == nil or target == "human" then
        print("[Europa Encyclopedia] Usage: encyclopedia_corpse <species identifier>  (example: encyclopedia_corpse mudraptor)")
        return
    end
    print("[Europa Encyclopedia] Spawning " .. target .. "; all living monsters will be killed after spawning.")
    Game.ExecuteCommand("spawn " .. target .. " cursor")
    Timer.Wait(function() Game.ExecuteCommand("killmonsters") end, DELAY_MS.CORPSE_TEST)
end)

Hook.Add("stop", "EuropaEncyclopedia.Stop", function() if window ~= nil then window.Visible = false end end)

Timer.Wait(function()
    buildDatabase()
end, DELAY_MS.DATABASE_BUILD)
