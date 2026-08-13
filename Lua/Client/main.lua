local E = JustEnoughBaro
local wikiCreatures = dofile(E.path("Lua/Client/wiki_data.lua")) or {}
local roleGuides = dofile(E.path("Lua/Client/role_guides.lua")) or {}
local submarineWikiData = dofile(E.path("Lua/Client/submarine_wiki_data.lua")) or {}
local wiringWikiData = dofile(E.path("Lua/Client/wiring_tooltips.lua")) or {}
local items, creatures, submarines, professions, afflictions = {}, {}, {}, {}, {}
local itemByIdentifier, creatureByIdentifier = {}, {}
local afflictionByIdentifier = {}
local professionByIdentifier = {}
local talentProfession = {}
local reverseCraft, reverseDeconstruct = {}, {}
local recipeTalents, recipeBlueprints = {}, {}
local creatureHabitats = {}
local backdrop, window, listBox, detailList, searchBox, currentCategory
local imageOverlay, contextHint, contextHintText
local itemFilterControls, itemFilterLabel, detailHeaderLabel
local backButton, forwardButton
local tabButtons = {}
local toggle
local navigateTo
local populateList
local showItem
local selectCategory
local navigationHistory = {}
local navigationPosition = 0
local isRestoringHistory = false
local currentSearch, visible = "", false
local itemCategoryFilter = "All"
local DEFAULT_SETTINGS = { openKey = "J", pageSize = 80 }
local settings = dofile(E.path("config.lua")) or DEFAULT_SETTINGS
local GUIStatic = LuaUserData.CreateStatic("Barotrauma.GUI", true)
local TalentPrefab = LuaUserData.CreateStatic("Barotrauma.TalentPrefab", true)
local AfflictionPrefab = LuaUserData.CreateStatic("Barotrauma.AfflictionPrefab", true)
local EventPrefab = LuaUserData.CreateStatic("Barotrauma.EventPrefab", true)
local SubmarineInfo = LuaUserData.CreateStatic("Barotrauma.SubmarineInfo", true)
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
    Style = LuaUserData.CreateStatic("Barotrauma.GUIStyle", true),
}
setmetatable(GUI, {
    __index = function(_, key)
        return GUIStatic[key]
    end,
})
local Keys = LuaUserData.CreateEnumTable("Microsoft.Xna.Framework.Input.Keys")
local Anchor = LuaUserData.CreateEnumTable("Barotrauma.Anchor")
local Alignment = LuaUserData.CreateEnumTable("Barotrauma.Alignment")
local openKey = Keys[settings.openKey] or Keys.J
local openKeyName = settings.openKey or "J"
local openKeySetting

local function applyOpenKey(value)
    local requestedName = E.str(value)
    local requestedKey = Keys[requestedName]
    if requestedKey == nil then
        requestedName = "J"
        requestedKey = Keys.J
        print("[JEB] Unknown key name; using J instead.")
    end
    openKeyName = requestedName
    openKey = requestedKey
end

local function loadInGameSettings()
    local loaded, errorMessage = pcall(function()
        local packageFound, contentPackage = trygetpackage("Just Enough Baro (JEB)")
        if not packageFound then
            return
        end
        local settingFound, setting =
            ConfigService.TryGetConfig(SettingBase.String, contentPackage, "OpenKey")
        if not settingFound then
            return
        end
        openKeySetting = setting
        applyOpenKey(setting.Value)
        setting.OnValueChanged.add(function(changedSetting)
            applyOpenKey(changedSetting.Value)
        end)
    end)
    if not loaded then
        print("[JEB] Could not load in-game key setting: " .. E.str(errorMessage))
    end
end

loadInGameSettings()
local FULL_RELATIVE_SIZE = 1

local function relativeVector(width, height)
    return Vector2(width, height)
end

local function fullHeightVector(width)
    return relativeVector(width, FULL_RELATIVE_SIZE)
end

-- All layout measurements are relative to their parent component.
local UI_VECTOR = {
    FULL = relativeVector(1, 1),
    FULL_WIDTH_AUTO_HEIGHT = relativeVector(1, 0),
    IMAGE_CENTER = relativeVector(0.5, 0.5),
    OVERLAY_WINDOW = relativeVector(0.82, 0.88),
    OVERLAY_INNER = relativeVector(0.97, 0.96),
    OVERLAY_TITLE = relativeVector(0.86, 0.08),
    OVERLAY_CLOSE = relativeVector(0.09, 0.08),
    OVERLAY_IMAGE = relativeVector(0.78, 0.78),
    INFO_ROW = relativeVector(1, 0.058),
    INFO_KEY = relativeVector(0.27, 1),
    INFO_VALUE = relativeVector(0.70, 1),
    ICON_INFO_ROW = relativeVector(1, 0.082),
    ICON_INFO_ICON = relativeVector(0.075, 0.78),
    ICON_INFO_TEXT = relativeVector(0.89, 1),
    REQUIREMENT_ROW = relativeVector(1, 0.095),
    REQUIREMENT_TEXT = relativeVector(0.82, 1),
    REQUIREMENT_ICON_FRAME = relativeVector(0.105, 0.86),
    REQUIREMENT_ICON = relativeVector(0.76, 0.76),
    LINK_ROW = relativeVector(1, 0.078),
    LINK_ICON = relativeVector(0.11, 0.82),
    LINK_TEXT = relativeVector(0.86, 1),
    ITEM_HERO = relativeVector(1, 0.18),
    ITEM_HERO_ICON = relativeVector(0.18, 0.82),
    ITEM_HERO_TITLE = relativeVector(0.76, 0.38),
    ITEM_HERO_SUMMARY = relativeVector(0.76, 0.58),
    CREATURE_PREVIEW = relativeVector(1, 0.24),
    CREATURE_PREVIEW_IMAGE = relativeVector(0.96, 0.90),
    TALENT_TILE = relativeVector(0.30, 0.82),
    TALENT_PRIMARY_TILE = relativeVector(0.145, 0.82),
    TALENT_PRIMARY_ROW = relativeVector(1, 0.115),
    TALENT_COLUMN = relativeVector(0.32, 1),
    TALENT_PATH_OPTIONS = relativeVector(0.94, 0.90),
    TALENT_ICON = relativeVector(0.74, 0.72),
    PROFESSION_HEADER = relativeVector(1, 0.16),
    PROFESSION_ICON = relativeVector(0.16, 0.80),
    PROFESSION_TITLE = relativeVector(0.78, 0.46),
    PROFESSION_SUMMARY = relativeVector(0.78, 0.50),
    INDEX_ROW = relativeVector(1, 0.076),
    INDEX_ICON = relativeVector(0.13, 0.82),
    WINDOW = relativeVector(0.84, 0.84),
    WINDOW_PADDING = relativeVector(0.972, 0.965),
    HEADER = relativeVector(1, 0.115),
    HEADER_ACCENT = relativeVector(0.012, 0.72),
    HEADER_TITLE_AREA = relativeVector(0.43, 1),
    HEADER_TITLE = relativeVector(0.90, 0.72),
    HEADER_CONTROLS = relativeVector(0.55, 1),
    HISTORY_BUTTON = relativeVector(0.12, 0.54),
    SEARCH_AREA = relativeVector(0.61, 0.54),
    SEARCH_BOX = relativeVector(0.98, 1),
    HEADER_CLOSE = relativeVector(0.14, 0.62),
    TABS = relativeVector(1, 0.06),
    TAB_BUTTON = relativeVector(0.198, 0.86),
    BODY = relativeVector(1, 0.765),
    INDEX_PANEL = relativeVector(0.30, 1),
    DETAIL_PANEL = relativeVector(0.685, 1),
    PANEL_HEADER = relativeVector(0.94, 0.072),
    PANEL_LIST = relativeVector(0.94, 0.875),
    FILTER_PREVIOUS = relativeVector(0.14, 0.82),
    FILTER_LABEL = relativeVector(0.68, 0.82),
    FILTER_NEXT = relativeVector(0.14, 0.82),
    FILTER_CONTROLS = relativeVector(0.76, 1),
    LIST_HEADER_TITLE = relativeVector(0.22, 1),
    DETAIL_HEADER_TITLE = relativeVector(0.78, 1),
    CONTEXT_HINT = relativeVector(0.26, 0.052),
    CONTEXT_HINT_TEXT = relativeVector(0.96, 1),
    OFFSET_SMALL = relativeVector(0.012, 0),
    OFFSET_INFO = relativeVector(0.015, 0),
    OFFSET_STANDARD = relativeVector(0.02, 0),
    OFFSET_HEADER_ACCENT = relativeVector(0.012, 0),
    OFFSET_TITLE = relativeVector(0.045, 0),
    OFFSET_TABS = relativeVector(0, 0.13),
    OFFSET_CONTEXT_HINT = relativeVector(0, -0.025),
}
local ITEM_CATEGORY = {
    STRUCTURE = 1,
    DECORATIVE = 2,
    MACHINE = 4,
    MEDICAL = 8,
    WEAPON = 16,
    DIVING = 32,
    EQUIPMENT = 64,
    FUEL = 128,
    ELECTRICAL = 256,
    MATERIAL = 1024,
    ALIEN = 2048,
    WRECKED = 4096,
    ITEM_ASSEMBLY = 8192,
    LEGACY = 16384,
    MISC = 32768,
}
local NUMBER_PRECISION = 1000
local NUMBER_EPSILON = 0.0005
local PERCENT_SCALE = 100
local GUI_ORDER = { CONTEXT_HINT = 999, WINDOW = 1000, IMAGE_OVERLAY = 1001 }
local DELAY_MS = { CORPSE_TEST = 750, DATABASE_BUILD = 1000 }
local MAX_GUI_PARENT_DEPTH = 12
local DEFAULT_AFFLICTION_STRENGTH = 100
local FULL_CONDITION = 1
local EMPTY_VALUE = 0
local TALENT_TREE_BASE_HEIGHT = 0.10
local TALENT_TREE_STAGE_HEIGHT = 0.115
local TALENT_TILE_WIDTH = 0.30
local TALENT_PRIMARY_TILE_WIDTH = 0.145
local COLOR = {
    BACKDROP = Color(3, 10, 14, 238),
    WINDOW = Color(10, 22, 27, 252),
    HEADER = Color(15, 36, 42, 255),
    PANEL = Color(13, 29, 34, 250),
    PANEL_ALTERNATE = Color(18, 38, 43, 245),
    ROW = Color(22, 42, 46, 225),
    TALENT_ROW = Color(27, 48, 51, 255),
    CYAN = Color(102, 211, 218, 255),
    CREAM = Color(232, 222, 184, 255),
    GOLD = Color(218, 179, 104, 255),
    GREEN = Color(132, 202, 151, 255),
    ORANGE = Color(225, 151, 87, 255),
    RED = Color(218, 101, 96, 255),
    MUTED = Color(133, 163, 165, 255),
    TEXT = Color(218, 222, 205, 255),
    HEADING = Color(232, 203, 135, 255),
}

-- Collection helpers ---------------------------------------------------------

local function append(list, value)
    table.insert(list, value)
end

local function isEmpty(list)
    return #list == EMPTY_VALUE
end

local function hasEntries(list)
    return not isEmpty(list)
end

-- Safe conversion and formatting --------------------------------------------

-- LuaCs members are not consistent across every game version and content type.
-- Read optional .NET properties through this helper so compatibility checks stay explicit.

local function safeField(object, field, fallback)
    if object == nil then
        return fallback
    end
    local ok, value = pcall(function()
        return object[field]
    end)
    if not ok or value == nil then
        return fallback
    end
    return value
end
local function text(value)
    if value == nil then
        return ""
    end
    local renderedOk, rendered = pcall(function()
        return value.ToString()
    end)
    if renderedOk and rendered ~= nil then
        local renderedText = tostring(rendered)
        if not string.find(renderedText, "^userdata:") then
            return renderedText
        end
    end
    local localized = safeField(value, "Value", nil)
    if localized ~= nil and localized ~= value then
        local localizedOk, localizedText = pcall(function()
            return localized.ToString()
        end)
        if localizedOk and localizedText ~= nil then
            return tostring(localizedText)
        end
        return tostring(localized)
    end
    return E.str(value)
end
local function id(value)
    return string.lower(text(value))
end
local function cleanDisplayText(value)
    local result = text(value)
    if string.find(result, "^userdata:") then
        return ""
    end
    result = string.gsub(result, "%[?color:[%w%._]+%]?", "")
    result = string.gsub(result, "%[?color:end%]?", "")
    result = string.gsub(result, "</?color[^>]*>", "")
    return result
end
local function numberText(value)
    local numeric = tonumber(value)
    if numeric == nil then
        return text(value)
    end
    if math.abs(numeric) < NUMBER_EPSILON then
        numeric = 0
    end
    local rounded
    if numeric >= 0 then
        rounded = math.floor(numeric * NUMBER_PRECISION + 0.5) / NUMBER_PRECISION
    else
        rounded = math.ceil(numeric * NUMBER_PRECISION - 0.5) / NUMBER_PRECISION
    end
    local formatted = string.gsub(string.format("%.3f", rounded), "0+$", "")
    formatted = string.gsub(formatted, "%.$", "")
    return formatted
end
local function joined(collection, separator)
    local values = {}
    if collection ~= nil then
        for value in collection do
            append(values, text(value))
        end
    end
    return table.concat(values, separator or ", ")
end

-- Item categories and search filters ----------------------------------------

local itemCategoryNames = {
    { ITEM_CATEGORY.STRUCTURE, "Structure" },
    { ITEM_CATEGORY.DECORATIVE, "Decorative" },
    { ITEM_CATEGORY.MACHINE, "Machine" },
    { ITEM_CATEGORY.MEDICAL, "Medical" },
    { ITEM_CATEGORY.WEAPON, "Weapon" },
    { ITEM_CATEGORY.DIVING, "Diving" },
    { ITEM_CATEGORY.EQUIPMENT, "Equipment" },
    { ITEM_CATEGORY.FUEL, "Fuel" },
    { ITEM_CATEGORY.ELECTRICAL, "Electrical" },
    { ITEM_CATEGORY.MATERIAL, "Material" },
    { ITEM_CATEGORY.ALIEN, "Alien" },
    { ITEM_CATEGORY.WRECKED, "Wrecked" },
    { ITEM_CATEGORY.ITEM_ASSEMBLY, "Item Assembly" },
    { ITEM_CATEGORY.LEGACY, "Legacy" },
    { ITEM_CATEGORY.MISC, "Misc" },
}
local function categoryText(value)
    local numeric = tonumber(value) or 0
    if numeric == 0 then
        return "None"
    end
    local names = {}
    for _, pair in ipairs(itemCategoryNames) do
        if math.floor(numeric / pair[1]) % 2 == 1 then
            append(names, pair[2])
        end
    end
    return table.concat(names, ", ")
end
local itemFilterNames = {
    "All",
    "Weapons",
    "Ammunition",
    "Gear",
    "Diving",
    "Medical",
    "Tools",
    "Electrical",
    "Materials",
    "Ores",
    "Ruins & Alien",
    "Miscellaneous",
}
local CATEGORY_PRESENTATION = {
    Bestiary = {
        tab = "BESTIARY",
        title = "FAUNA OF EUROPA",
        description = "Field observations, habitat records, physiology and recoverable specimens from known Europan life.",
    },
    Items = {
        tab = "ITEMS",
        title = "EQUIPMENT & MATERIALS",
        description = "A technical catalogue of equipment, fabrication chains, market data and material recovery.",
    },
    Submarines = {
        tab = "SUBMARINES",
        title = "SUBMARINE CATALOGUE",
        description = "Loaded player vessels organized by class, tier, price and recommended crew complement.",
    },
    Professions = {
        tab = "PROFESSIONS",
        title = "CREW DISCIPLINES",
        description = "Training records, starting competencies and complete specialization pathways for every crew role.",
    },
    Afflictions = {
        tab = "AFFLICTIONS",
        title = "MEDICAL REFERENCE",
        description = "Clinical notes covering symptoms, progressive effects, known treatments and direct causes.",
    },
}
local function hasCategory(value, flag)
    return math.floor((tonumber(value) or 0) / flag) % 2 == 1
end
local function itemFilterCategory(entry)
    local prefab = entry.prefab
    local identifier = entry.identifier
    local tags = string.lower(joined(prefab.Tags, " "))
    local sourcePath = string.lower(prefab.ContentFile and text(prefab.ContentFile.Path) or "")
    local searchable = identifier
        .. " "
        .. string.lower(entry.name)
        .. " "
        .. tags
        .. " "
        .. sourcePath
    if E.contains(searchable, "ore") or E.contains(tags, "mineral") then
        return "Ores"
    end
    if
        hasCategory(prefab.Category, ITEM_CATEGORY.ALIEN)
        or E.contains(sourcePath, "ruin")
        or E.contains(tags, "alien")
    then
        return "Ruins & Alien"
    end
    if
        E.contains(tags, "ammo")
        or E.contains(tags, "ammunition")
        or E.contains(identifier, "round")
        or E.contains(identifier, "magazine")
        or E.contains(identifier, "shell")
    then
        return "Ammunition"
    end
    if hasCategory(prefab.Category, ITEM_CATEGORY.MEDICAL) then
        return "Medical"
    end
    if hasCategory(prefab.Category, ITEM_CATEGORY.DIVING) then
        return "Diving"
    end
    if hasCategory(prefab.Category, ITEM_CATEGORY.WEAPON) then
        return "Weapons"
    end
    if hasCategory(prefab.Category, ITEM_CATEGORY.ELECTRICAL) then
        return "Electrical"
    end
    if hasCategory(prefab.Category, ITEM_CATEGORY.MATERIAL) then
        return "Materials"
    end
    if hasCategory(prefab.Category, ITEM_CATEGORY.EQUIPMENT) then
        return "Gear"
    end
    if E.contains(tags, "tool") or E.contains(sourcePath, "/tools") then
        return "Tools"
    end
    return "Miscellaneous"
end

local function isUsefulCatalogueItem(prefab, identifier)
    if identifier == "portablepump" then
        return true
    end
    if hasCategory(prefab.Category, ITEM_CATEGORY.WRECKED) then
        return false
    end
    local sourcePath = string.lower(prefab.ContentFile and text(prefab.ContentFile.Path) or "")
    if E.contains(sourcePath, "/wreck") or E.contains(identifier, "wrecked") then
        return false
    end
    if hasCategory(prefab.Category, ITEM_CATEGORY.DECORATIVE) then
        return false
    end
    local root = prefab.ConfigElement
    if root == nil then
        return true
    end
    local excludedComponents = { door = true, ladder = true, chair = true, bed = true }
    for child in root.Elements() do
        if excludedComponents[id(child.NameAsIdentifier())] then
            return false
        end
    end
    local furnishingNames = {
        cabinet = true,
        desk = true,
        locker = true,
        shelf = true,
        table = true,
        window = true,
    }
    for word in pairs(furnishingNames) do
        if E.contains(identifier, word) then
            return false
        end
    end
    return true
end

-- Indexing and prefab lookup -------------------------------------------------

local function addIndex(index, key, value)
    key = id(key)
    index[key] = index[key] or {}
    append(index[key], value)
end
local function addUniqueEntry(index, key, value, identity)
    key = id(key)
    index[key] = index[key] or {}
    local valueIdentity = identity(value)
    for _, existing in ipairs(index[key]) do
        if identity(existing) == valueIdentity then
            return
        end
    end
    append(index[key], value)
end

local function xmlAttribute(tag, name, fallback)
    local value = string.match(tag or "", name .. '%s*=%s*"([^"]*)"')
    return value or fallback or ""
end

local function xmlSection(xml, elementName, attribute, value)
    for opening, body in
        string.gmatch(xml or "", "<" .. elementName .. "%s+([^>]*)>(.-)</" .. elementName .. ">")
    do
        if id(xmlAttribute(opening, attribute, "")) == id(value) then
            return opening, body
        end
    end
    return nil, nil
end

local function findItemPrefab(identifier)
    local key = id(identifier)
    if itemByIdentifier[key] ~= nil then
        return itemByIdentifier[key].prefab
    end
    for prefab in ItemPrefab.Prefabs do
        if id(prefab.Identifier) == key then
            return prefab
        end
    end
    return nil
end

local function findCharacterPrefab(identifier)
    local key = id(identifier)
    if creatureByIdentifier[key] ~= nil then
        return creatureByIdentifier[key].prefab
    end
    for prefab in CharacterPrefab.Prefabs do
        if id(prefab.Identifier) == key then
            return prefab
        end
    end
    return nil
end

local function addUnique(index, key, value)
    key = id(key)
    index[key] = index[key] or {}
    for _, existing in ipairs(index[key]) do
        if existing == value then
            return
        end
    end
    append(index[key], value)
end

local function prettyIdentifier(value)
    local knownNames = {
        blunttrauma = "Blunt Force Trauma",
        gunshotwound = "Gunshot Wound",
        bitewounds = "Bite Wounds",
        explosiondamage = "Explosion Damage",
        radiationsickness = "Radiation Sickness",
        huskinfection = "Husk Infection",
        lacerations = "Lacerations",
        bleeding = "Bleeding",
        burn = "Burn",
        stun = "Stun",
        electrical = "Electrical",
        mechanical = "Mechanical",
        medical = "Medical",
        weapons = "Weapons",
        helm = "Helm",
        walkingspeed = "Walking Speed",
        swimmingspeed = "Swimming Speed",
        propulsionspeed = "Propulsion Speed",
        flowresistance = "Flow Resistance",
        pressureprotection = "Pressure Protection",
    }
    if knownNames[id(value)] ~= nil then
        return knownNames[id(value)]
    end
    local result = string.gsub(text(value), "(%l)(%u)", "%1 %2")
    result = string.gsub(result, "[_%-]+", " ")
    return (
        string.gsub(result, "(%a)([%w']*)", function(first, rest)
            return string.upper(first) .. string.lower(rest)
        end)
    )
end

local CREATURE_NAME_OVERRIDES = {
    hammerhead_mnamed = "Moping Jack",
    spineling_morbusine = "Viperling",
    humanhusk = "Husk",
    terminalcell = "Terminal Cells",
    hammerheadspawn = "Hammerhead Spawn",
    hammerheadmatriarch = "Hammerhead Matriarch",
}
local CREATURE_WIKI_ALIASES = {
    hammerhead_mnamed = "mopingjack",
    spineling_morbusine = "viperling",
    humanhusk = "husk",
    husk_chimera = "huskchimera",
    husk_exosuit = "huskexosuit",
    mudraptor_passive = "mudraptor",
    balloon = "petcthulhu",
    orangeboy = "petraptor",
    peanut = "petsmallcrawler",
}

local CREATURE_HABITATS = {
    charybdis = "The Abyss",
    endworm = "The Abyss",
    latcher = "The Abyss",
    jove = "Eye of Europa (campaign ending)",
    ancient = "Eye of Europa and Ancient settlements",
    cyborgworm = "Eye of Europa",
    fractalguardian = "Alien Ruins",
    fractalguardian2 = "Alien Ruins",
    fractalguardian3 = "Alien Ruins",
    fractalguardian_emp = "Alien Ruins and the campaign ending",
    portalguardian = "The campaign ending",
    guardianrepairbot = "Spawned by damaged Guardian variants",
    leucocyte = "Inside Thalamus-controlled wrecks",
    terminalcell = "Inside Thalamus-controlled wrecks",
    swarmfeeder = "Alien Ruins",
    watcher = "Open waters, especially later biomes",
}

local CREATURE_WEAKSPOTS = {
    charybdis = "Mouth",
    endworm = "Mouth and exposed flesh between armor plates",
    hammerheadmatriarch = "Egg sac/head",
    moloch = "Core beneath the shell",
    molochblack = "Core beneath the shell",
    watcher = "Eye",
}

local WIRING_WIKI_ALIASES = {
    abscomponent = "acoscomponent",
    engine = "engines",
    shuttleengine = "engines",
    pump = "pumps",
    smallpump = "pumps",
    largepump = "pumps",
    door = "doorshatches",
    hatch = "doorshatches",
    fabricator = "fabricatordeconstructor",
    deconstructor = "fabricatordeconstructor",
    medicalfabricator = "medicalfabricator",
    dockingport = "dockinghatchport",
    dockinghatch = "dockinghatchport",
}

-- The wiki's older connection-panel tables use placeholders such as "The
-- input signal" for several logic components. These descriptions spell out
-- the actual operation performed at each of those pins.
local LOGIC_COMPONENT_PIN_DESCRIPTIONS = {
    abscomponent = {
        signalin = "Accepts any number whose absolute value will be calculated.",
        signalout = "Outputs the absolute (non-negative) value of SIGNAL_IN.",
    },
    acoscomponent = {
        signalin = "Accepts a number from -1 to 1 as a cosine value.",
        signalout = "Outputs, in degrees, the angle whose cosine is SIGNAL_IN.",
    },
    asincomponent = {
        signalin = "Accepts a number from -1 to 1 as a sine value.",
        signalout = "Outputs, in degrees, the angle whose sine is SIGNAL_IN.",
    },
    atancomponent = {
        signalin = "Accepts a tangent value and calculates its inverse tangent.",
        signalinx = "Accepts the X coordinate when the component is used in two-coordinate ATAN2 mode.",
        signaliny = "Accepts the Y coordinate when the component is used in two-coordinate ATAN2 mode.",
        signalout = "Outputs the calculated angle in degrees; X and Y inputs use the ATAN2 calculation.",
    },
    coscomponent = {
        signalin = "Accepts an angle in degrees.",
        signalout = "Outputs the cosine of the angle received through SIGNAL_IN.",
    },
    sincomponent = {
        signalin = "Accepts an angle in degrees.",
        signalout = "Outputs the sine of the angle received through SIGNAL_IN.",
    },
    tancomponent = {
        signalin = "Accepts an angle in degrees.",
        signalout = "Outputs the tangent of the angle received through SIGNAL_IN.",
    },
    squarerootcomponent = {
        signalin = "Accepts the number whose square root will be calculated.",
        signalout = "Outputs the square root of SIGNAL_IN.",
    },
    notcomponent = {
        signalin = "Checks whether this input is receiving a signal.",
        signalout = "Outputs the configured true signal only while SIGNAL_IN receives no signal.",
    },
    andcomponent = {
        signalin1 = "First condition; both inputs must receive a signal within the configured time frame.",
        signalin2 = "Second condition; both inputs must receive a signal within the configured time frame.",
        setoutput = "Changes the value emitted when both input conditions are true.",
        signalout = "Outputs the configured true value when both inputs receive a signal in time.",
    },
    orcomponent = {
        signalin1 = "First condition; receiving a signal here satisfies the OR operation.",
        signalin2 = "Second condition; receiving a signal here satisfies the OR operation.",
        setoutput = "Changes the value emitted when either input condition is true.",
        signalout = "Outputs the configured true value when either input receives a signal.",
    },
    xorcomponent = {
        signalin1 = "First condition; exactly one of the two inputs must receive a signal.",
        signalin2 = "Second condition; exactly one of the two inputs must receive a signal.",
        setoutput = "Changes the value emitted when exactly one input condition is true.",
        signalout = "Outputs the configured true value when one input, but not both, receives a signal.",
    },
    equalscomponent = {
        signalin1 = "First value to compare for equality.",
        signalin2 = "Second value to compare for equality.",
        setoutput = "Changes the value emitted when both compared inputs are equal.",
        signalout = "Outputs the configured true value when SIGNAL_IN_1 equals SIGNAL_IN_2.",
    },
    greatercomponent = {
        signalin1 = "The value tested as the left side of the greater-than comparison.",
        signalin2 = "The value tested as the right side of the greater-than comparison.",
        setoutput = "Changes the value emitted when the comparison is true.",
        signalout = "Outputs the configured true value when SIGNAL_IN_1 is greater than SIGNAL_IN_2.",
    },
    regexfindcomponent = {
        signalin = "The text to test against the component's regular-expression pattern.",
        setoutput = "Changes the value emitted when the text matches the pattern.",
        signalout = "Outputs the configured true value when SIGNAL_IN matches the regular expression.",
    },
    signalcheckcomponent = {
        signalin = "The value to compare with the component's target signal.",
        setoutput = "Changes the value emitted when the received value matches the target.",
        settargetsignal = "Changes the target value that SIGNAL_IN must match.",
        signalout = "Outputs the configured true value when SIGNAL_IN matches the target signal.",
    },
    oscillatorcomponent = {
        setfrequency = "Sets how many oscillation cycles are generated per second, in hertz.",
        setoutputtype = "Selects the waveform: 0 for pulse, 1 for sine, or 2 for square.",
        signalout = "Outputs the periodic waveform generated with the selected frequency and type.",
    },
}

local function wiringWikiKey(value)
    return string.gsub(id(value), "[^a-z0-9]", "")
end

local function creatureBaseIdentifier(identifier)
    local key = id(identifier)
    if CREATURE_WIKI_ALIASES[key] ~= nil then
        return CREATURE_WIKI_ALIASES[key]
    end
    return string.gsub(key, "_m$", "")
end

local function creatureFamily(identifier, displayName)
    local searchable = id(identifier) .. " " .. creatureBaseIdentifier(identifier) .. " " .. id(displayName)
    local families = {
        { "hammerhead", "Hammerheads" },
        { "crawler", "Crawlers" },
        { "mudraptor", "Mudraptors" },
        { "moloch", "Molochs" },
        { "spineling", "Spinelings" },
        { "fractalguardian", "Fractal Guardians" },
        { "husk", "Husks" },
        { "thresher", "Threshers" },
        { "worm", "Abyssal creatures" },
    }
    for _, pair in ipairs(families) do
        if E.contains(searchable, pair[1]) then
            return pair[2]
        end
    end
    return "Other creatures"
end

local function joinedPretty(collection, separator)
    local values = {}
    if collection ~= nil then
        for value in collection do
            append(values, prettyIdentifier(value))
        end
    end
    return table.concat(values, separator or ", ")
end

-- Runtime database construction ---------------------------------------------

local function indexMonsterEvents(element, biome)
    if element == nil then
        return
    end
    if id(element.NameAsIdentifier()) == "monsterevent" then
        local characterFile = element.GetAttributeString("characterfile", "")
        local spawnTypes = element.GetAttributeString("spawntype", "")
        for spawnType in string.gmatch(spawnTypes, "[^,%s]+") do
            addUnique(creatureHabitats, characterFile, prettyIdentifier(spawnType))
        end
        if text(biome) ~= "" then
            addUnique(creatureHabitats, characterFile, "Biome: " .. prettyIdentifier(biome))
        end
    end
    for child in element.Elements() do
        indexMonsterEvents(child, biome)
    end
end

local function buildDatabase()
    items, creatures, submarines, professions, afflictions = {}, {}, {}, {}, {}
    reverseCraft, reverseDeconstruct = {}, {}
    itemByIdentifier, creatureByIdentifier, afflictionByIdentifier, professionByIdentifier =
        {}, {}, {}, {}
    recipeTalents, recipeBlueprints, creatureHabitats, talentProfession = {}, {}, {}, {}
    local seenItems = {}
    for prefab in ItemPrefab.Prefabs do
        if prefab ~= nil and prefab.Identifier ~= nil then
            local entry =
                { prefab = prefab, identifier = id(prefab.Identifier), name = text(prefab.Name) }
            local hidden = prefab.ConfigElement ~= nil
                and prefab.ConfigElement.GetAttributeBool("hideinmenus", false)
            local filePath = prefab.ContentFile and text(prefab.ContentFile.Path) or ""
            local isLegacy = hasCategory(prefab.Category, ITEM_CATEGORY.LEGACY)
                or E.contains(filePath, "/Legacy/")
            if
                entry.name ~= ""
                and not hidden
                and not isLegacy
                and isUsefulCatalogueItem(prefab, entry.identifier)
                and not seenItems[entry.identifier]
            then
                seenItems[entry.identifier] = true
                append(items, entry)
                itemByIdentifier[entry.identifier] = entry
                for _, recipe in ipairs(E.each(prefab.FabricationRecipes.Values)) do
                    for _, requirement in ipairs(E.each(recipe.RequiredItems)) do
                        for _, ingredient in ipairs(E.each(requirement.ItemPrefabs)) do
                            addUniqueEntry(
                                reverseCraft,
                                ingredient.Identifier,
                                entry,
                                function(value)
                                    return value.identifier
                                end
                            )
                        end
                    end
                end
                for _, output in ipairs(E.each(prefab.DeconstructItems)) do
                    addIndex(
                        reverseDeconstruct,
                        output.ItemIdentifier,
                        { source = entry, output = output }
                    )
                end
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
                        local ingredientIdentifier =
                            id(requirement.GetAttributeIdentifier("identifier", ""))
                        local ingredientTag = id(requirement.GetAttributeIdentifier("tag", ""))
                        if ingredientIdentifier ~= "" then
                            addUniqueEntry(
                                reverseCraft,
                                ingredientIdentifier,
                                target,
                                function(value)
                                    return value.identifier
                                end
                            )
                        elseif ingredientTag ~= "" then
                            for _, candidate in ipairs(items) do
                                for tag in candidate.prefab.Tags do
                                    if id(tag) == ingredientTag then
                                        addUniqueEntry(
                                            reverseCraft,
                                            candidate.identifier,
                                            target,
                                            function(value)
                                                return value.identifier
                                            end
                                        )
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
    local seenSubmarines = {}
    for submarineInfo in SubmarineInfo.SavedSubmarines do
        local submarineName = text(safeField(submarineInfo, "DisplayName", submarineInfo.Name))
        local submarineIdentifier = id(safeField(submarineInfo, "Name", submarineName))
        local isPlayerSubmarine = safeField(submarineInfo, "IsPlayer", false)
        local submarineType = id(safeField(submarineInfo, "Type", ""))
        local isBeaconStation = safeField(submarineInfo, "IsBeacon", false)
            or submarineType == "beaconstation"
            or E.contains(submarineIdentifier, "beaconstation")
            or E.contains(submarineName, "beacon station")
        local isCorrupted = safeField(submarineInfo, "IsFileCorrupted", false)
        if
            isPlayerSubmarine
            and not isBeaconStation
            and not isCorrupted
            and submarineName ~= ""
            and not seenSubmarines[submarineIdentifier]
        then
            seenSubmarines[submarineIdentifier] = true
            append(submarines, {
                prefab = submarineInfo,
                identifier = submarineIdentifier,
                name = submarineName,
            })
        end
    end
    for talent in TalentPrefab.TalentPrefabs do
        if talent ~= nil and talent.ConfigElement ~= nil then
            for child in talent.ConfigElement.Elements() do
                if id(child.NameAsIdentifier()) == "addedrecipe" then
                    local recipeIdentifier = child.GetAttributeIdentifier("itemidentifier", "")
                    if id(recipeIdentifier) ~= "" then
                        addIndex(recipeTalents, recipeIdentifier, talent)
                    end
                end
            end
        end
    end
    local jobsXml = File.Exists("Content/Jobs.xml") and File.Read("Content/Jobs.xml") or ""
    local talentTreesXml = File.Exists("Content/Talents/TalentTrees.xml")
            and File.Read("Content/Talents/TalentTrees.xml")
        or ""
    local coreAfflictionIdentifiers = {}
    for _, path in ipairs({ "Content/Afflictions.xml", "Content/AfflictionsGeneticMaterial.xml" }) do
        local xml = File.Exists(path) and File.Read(path) or ""
        for identifier in string.gmatch(xml, 'identifier%s*=%s*"([^"]+)"') do
            coreAfflictionIdentifiers[id(identifier)] = true
        end
    end
    local crewProfessions = {
        captain = true,
        engineer = true,
        mechanic = true,
        securityofficer = true,
        medicaldoctor = true,
        assistant = true,
    }
    for prefab in JobPrefab.Prefabs do
        local professionIdentifier = prefab and id(prefab.Identifier) or ""
        if crewProfessions[professionIdentifier] and text(prefab.Name) ~= "" then
            local _, jobXml = xmlSection(jobsXml, "Job", "identifier", prefab.Identifier)
            local _, treeXml =
                xmlSection(talentTreesXml, "TalentTree", "jobidentifier", prefab.Identifier)
            professions[#professions + 1] = {
                prefab = prefab,
                identifier = id(prefab.Identifier),
                name = text(prefab.Name),
                jobXml = jobXml,
                treeXml = treeXml,
            }
            professionByIdentifier[professionIdentifier] = professions[#professions]
            for talentIdentifier in string.gmatch(treeXml or "", 'identifier%s*=%s*"([^"]+)"') do
                talentProfession[id(talentIdentifier)] = professionIdentifier
            end
        end
    end
    local seenAfflictionNames = {}
    for prefab in AfflictionPrefab.Prefabs do
        if prefab ~= nil and prefab.Identifier ~= nil then
            local entry =
                { prefab = prefab, identifier = id(prefab.Identifier), name = text(prefab.Name) }
            if entry.name == "" then
                entry.name = prettyIdentifier(entry.identifier)
            end
            local normalizedName = id(entry.name)
            if
                coreAfflictionIdentifiers[entry.identifier]
                and entry.identifier ~= ""
                and afflictionByIdentifier[entry.identifier] == nil
                and not seenAfflictionNames[normalizedName]
            then
                append(afflictions, entry)
                afflictionByIdentifier[entry.identifier] = entry
                seenAfflictionNames[normalizedName] = true
            end
        end
    end
    for event in EventPrefab.Prefabs do
        indexMonsterEvents(event.ConfigElement, event.BiomeIdentifier)
    end
    local seenCreatures = {}
    local retiredCreatures = { carrier = true, coelanth = true, charybdisold = true }
    for prefab in CharacterPrefab.Prefabs do
        if prefab ~= nil and prefab.Identifier ~= nil and id(prefab.Identifier) ~= "human" then
            local filePath = prefab.ContentFile and text(prefab.ContentFile.Path) or ""
            local fileName = string.match(filePath, "([^/\\]+)%.xml$") or id(prefab.Identifier)
            local identifier = id(prefab.Identifier)
            local legacy = E.contains(fileName, "legacy")
                or E.contains(identifier, "legacy")
                or retiredCreatures[identifier]
            if not legacy and not seenCreatures[identifier] then
                seenCreatures[identifier] = true
                creatures[#creatures + 1] = {
                    prefab = prefab,
                    identifier = id(prefab.Identifier),
                    name = CREATURE_NAME_OVERRIDES[identifier]
                        or (identifier:match("_m$") and string.gsub(text(prefab.Name), "_m$", "") .. " (Mission variant)")
                        or text(prefab.Name),
                    family = creatureFamily(identifier, text(prefab.Name)),
                    habitats = creatureHabitats[id(fileName)] or creatureHabitats[id(
                        prefab.Identifier
                    )] or {},
                }
                creatureByIdentifier[identifier] = creatures[#creatures]
            end
        end
    end
    table.sort(items, function(a, b)
        return a.name < b.name
    end)
    table.sort(creatures, function(a, b)
        if a.family ~= b.family then
            return a.family < b.family
        end
        return a.name < b.name
    end)
    table.sort(submarines, function(a, b)
        local tierA = tonumber(safeField(a.prefab, "Tier", 1)) or 1
        local tierB = tonumber(safeField(b.prefab, "Tier", 1)) or 1
        if tierA ~= tierB then
            return tierA < tierB
        end
        local priceA = tonumber(safeField(a.prefab, "Price", 0)) or 0
        local priceB = tonumber(safeField(b.prefab, "Price", 0)) or 0
        if priceA ~= priceB then
            return priceA < priceB
        end
        return a.name < b.name
    end)
    table.sort(professions, function(a, b)
        return a.name < b.name
    end)
    table.sort(afflictions, function(a, b)
        return a.name < b.name
    end)
end

-- Images and reusable GUI components ----------------------------------------

local function creaturePreviewSprite(prefab)
    local source = prefab
    while source ~= nil do
        local characterPath = source.ContentFile and text(source.ContentFile.Path) or ""
        local directory, fileName = string.match(characterPath, "^(.*)[/\\]([^/\\]+)%.xml$")
        if directory ~= nil then
            local ragdollPath = directory .. "/Ragdolls/" .. fileName .. "DefaultRagdoll.xml"
            if File.Exists(ragdollPath) then
                local xml = File.Read(ragdollPath)
                local texture = string.match(xml, '<[Rr]agdoll.-texture="([^"]+)"')
                local bestX, bestY, bestW, bestH, bestArea
                for x, y, w, h in
                    string.gmatch(xml, 'sourcerect="(%-?%d+),%s*(%-?%d+),%s*(%d+),%s*(%d+)"')
                do
                    local area = tonumber(w) * tonumber(h)
                    if bestArea == nil or area > bestArea then
                        bestX, bestY, bestW, bestH, bestArea = x, y, w, h, area
                    end
                end
                if texture ~= nil and bestArea ~= nil then
                    return Sprite(
                        texture,
                        Rectangle(
                            tonumber(bestX),
                            tonumber(bestY),
                            tonumber(bestW),
                            tonumber(bestH)
                        )
                    )
                end
            end
        end
        source = source.ParentPrefab
    end
    return nil
end

local function wikiCreatureSprite(entry)
    local wiki = wikiCreatures[entry.identifier]
        or wikiCreatures[creatureBaseIdentifier(entry.identifier)]
    if wiki == nil or wiki.image == nil or wiki.image == "" then
        return nil
    end
    local imagePath = E.path(wiki.image)
    if not File.Exists(imagePath) then
        return nil
    end
    return Sprite(imagePath, UI_VECTOR.IMAGE_CENTER)
end

local function showImageOverlay(sprite, titleText)
    if imageOverlay ~= nil then
        imageOverlay.Visible = false
        imageOverlay = nil
    end
    imageOverlay = GUI.Frame(
        GUI.RectTransform(UI_VECTOR.OVERLAY_WINDOW, GUIStatic.Canvas, Anchor.Center),
        "GUIFrameListBox"
    )
    imageOverlay.Color = COLOR.WINDOW
    local inner = GUI.Frame(
        GUI.RectTransform(UI_VECTOR.OVERLAY_INNER, imageOverlay.RectTransform, Anchor.Center),
        "InnerFrame"
    )
    inner.Color = COLOR.PANEL
    local title = GUI.TextBlock(
        GUI.RectTransform(UI_VECTOR.OVERLAY_TITLE, inner.RectTransform, Anchor.TopLeft),
        string.upper(titleText),
        COLOR.CYAN,
        GUI.Style.SubHeadingFont,
        Alignment.CenterLeft,
        false,
        ""
    )
    title.CanBeFocused = false
    local close = GUI.Button(
        GUI.RectTransform(UI_VECTOR.OVERLAY_CLOSE, inner.RectTransform, Anchor.TopRight),
        "×",
        Alignment.Center,
        "GUICancelButton"
    )
    close.OnClicked = function()
        imageOverlay.Visible = false
        imageOverlay = nil
        return true
    end
    local image = GUI.Image(
        GUI.RectTransform(UI_VECTOR.OVERLAY_IMAGE, inner.RectTransform, Anchor.BottomCenter),
        sprite,
        true
    )
    image.CanBeFocused = false
end

local function clear(component)
    if component ~= nil then
        component.Content.ClearChildren()
    end
end

local function resetScroll(component)
    if component == nil then
        return
    end
    pcall(function()
        component.BarScroll = 0
    end)
    pcall(function()
        component.ScrollBar.BarScroll = 0
    end)
end

local function semanticTextColor(value)
    local content = string.upper(text(value))
    if string.find(content, "^SOURCE") then
        return COLOR.MUTED
    end
    if string.find(content, "^NO ") or string.find(content, "^NOT ") then
        return COLOR.MUTED
    end
    if string.find(content, "WARNING") or string.find(content, "DAMAGE") then
        return COLOR.RED
    end
    if string.find(content, "^OUTPUT") or string.find(content, "LIVE ADJUSTED") then
        return COLOR.GREEN
    end
    if string.find(content, "^DEVICE") or string.find(content, "^REQUIRES") then
        return COLOR.GOLD
    end
    if
        string.find(content, "^VITALITY")
        or string.find(content, "^SPECIES")
        or string.find(content, "^GROUP")
    then
        return COLOR.CYAN
    end
    return COLOR.TEXT
end

local function line(parent, value, style)
    return GUI.TextBlock(
        GUI.RectTransform(UI_VECTOR.FULL_WIDTH_AUTO_HEIGHT, parent, Anchor.TopCenter),
        text(value),
        semanticTextColor(value),
        nil,
        Alignment.TopLeft,
        true,
        style or ""
    )
end

local function coloredLine(parent, value, color, style)
    return GUI.TextBlock(
        GUI.RectTransform(UI_VECTOR.FULL_WIDTH_AUTO_HEIGHT, parent, Anchor.TopCenter),
        text(value),
        color,
        nil,
        Alignment.TopLeft,
        true,
        style or ""
    )
end

local function label(parent, value, alignment, color)
    return GUI.TextBlock(
        GUI.RectTransform(UI_VECTOR.FULL, parent, Anchor.Center),
        text(value),
        color or COLOR.MUTED,
        GUI.Style.SmallFont,
        alignment or Alignment.CenterLeft,
        false,
        ""
    )
end

local function heading(parent, value, color)
    local headingText = GUI.TextBlock(
        GUI.RectTransform(UI_VECTOR.FULL_WIDTH_AUTO_HEIGHT, parent, Anchor.TopCenter),
        string.upper(text(value)),
        color or COLOR.HEADING,
        GUI.Style.SubHeadingFont,
        Alignment.TopLeft,
        true,
        ""
    )
    return headingText
end

local palette = {
    cyan = COLOR.CYAN,
    cream = COLOR.CREAM,
    green = COLOR.GREEN,
    orange = COLOR.ORANGE,
    red = COLOR.RED,
    muted = COLOR.MUTED,
}

local function infoRow(parent, key, value, color)
    local row =
        GUI.Frame(GUI.RectTransform(UI_VECTOR.INFO_ROW, parent, Anchor.TopCenter), "ListBoxElement")
    row.Color = COLOR.ROW
    local keyText = GUI.TextBlock(
        GUI.RectTransform(UI_VECTOR.INFO_KEY, row.RectTransform, Anchor.CenterLeft),
        string.upper(text(key)),
        COLOR.GOLD,
        GUI.Style.SmallFont,
        Alignment.CenterLeft,
        false,
        ""
    )
    keyText.RectTransform.RelativeOffset = UI_VECTOR.OFFSET_INFO
    keyText.CanBeFocused = false
    local valueText = GUI.TextBlock(
        GUI.RectTransform(UI_VECTOR.INFO_VALUE, row.RectTransform, Anchor.CenterRight),
        text(value),
        color or COLOR.TEXT,
        GUI.Style.SmallFont,
        Alignment.CenterLeft,
        false,
        ""
    )
    valueText.CanBeFocused = false
    return row
end

local function iconInfoRow(parent, sprite, caption, value, color, tooltip)
    local row = GUI.Frame(
        GUI.RectTransform(UI_VECTOR.ICON_INFO_ROW, parent, Anchor.TopCenter),
        "ListBoxElement"
    )
    row.Color = COLOR.ROW
    if sprite ~= nil then
        local image = GUI.Image(
            GUI.RectTransform(UI_VECTOR.ICON_INFO_ICON, row.RectTransform, Anchor.CenterLeft),
            sprite,
            true
        )
        image.RectTransform.RelativeOffset = UI_VECTOR.OFFSET_SMALL
        image.CanBeFocused = false
    end
    local block = GUI.TextBlock(
        GUI.RectTransform(UI_VECTOR.ICON_INFO_TEXT, row.RectTransform, Anchor.CenterRight),
        string.upper(text(caption)) .. "\n" .. text(value),
        color or COLOR.CREAM,
        GUI.Style.SmallFont,
        Alignment.CenterLeft,
        false,
        ""
    )
    block.CanBeFocused = false
    row.ToolTip = tooltip or text(value)
    return row
end

local skillJobs = {
    electrical = "engineer",
    helm = "captain",
    mechanical = "mechanic",
    medical = "medicaldoctor",
    weapons = "securityofficer",
}

local function titleCase(value)
    return prettyIdentifier(value)
end

-- Crafting requirements and linked item rows --------------------------------

local function fallbackSkillIcon(identifier)
    local jobIdentifier = skillJobs[id(identifier)]
    if jobIdentifier == nil then
        return nil
    end
    local job = nil
    for prefab in JobPrefab.Prefabs do
        if id(prefab.Identifier) == jobIdentifier then
            job = prefab
            break
        end
    end
    return job and safeField(job, "IconSmall", safeField(job, "Icon", nil)) or nil
end

local function requirementRow(parent, captionText, iconSprite, tooltip, onClick)
    local row = GUI.Frame(
        GUI.RectTransform(UI_VECTOR.REQUIREMENT_ROW, parent, Anchor.TopCenter),
        "ListBoxElement"
    )
    row.Color = COLOR.ROW
    local caption
    if onClick ~= nil then
        caption = GUI.Button(
            GUI.RectTransform(UI_VECTOR.REQUIREMENT_TEXT, row.RectTransform, Anchor.CenterLeft),
            captionText .. "  ›",
            Alignment.CenterLeft,
            "GUIButtonSmall"
        )
        caption.OnClicked = function()
            onClick()
            return true
        end
        caption.ToolTip = tooltip or captionText
    else
        caption = GUI.TextBlock(
            GUI.RectTransform(UI_VECTOR.REQUIREMENT_TEXT, row.RectTransform, Anchor.CenterLeft),
            captionText,
            nil,
            GUI.Style.SmallFont,
            Alignment.CenterLeft,
            false,
            ""
        )
    end
    caption.RectTransform.RelativeOffset = UI_VECTOR.OFFSET_STANDARD
    if onClick == nil then
        caption.CanBeFocused = false
    end
    local square = GUI.Frame(
        GUI.RectTransform(UI_VECTOR.REQUIREMENT_ICON_FRAME, row.RectTransform, Anchor.CenterRight),
        "TalentBackground"
    )
    if iconSprite ~= nil then
        local image = GUI.Image(
            GUI.RectTransform(UI_VECTOR.REQUIREMENT_ICON, square.RectTransform, Anchor.Center),
            iconSprite,
            true
        )
        image.CanBeFocused = false
    else
        label(square.RectTransform, "?", Alignment.Center, COLOR.CYAN)
    end
    square.ToolTip = tooltip or captionText
    square.CanBeFocused = false
end

local function skillRequirement(parent, identifier, level, displayName, iconSprite)
    local name = text(displayName)
    if name == "" then
        name = titleCase(identifier)
    end
    local jobIdentifier = skillJobs[id(identifier)]
    local function openProfession()
        if jobIdentifier == nil then
            return
        end
        local profession = professionByIdentifier[jobIdentifier]
        if profession ~= nil then
            currentSearch = ""
            if searchBox ~= nil then
                searchBox.Text = ""
            end
            navigateTo("Professions", profession, id(identifier))
        end
    end
    local tooltip = name .. " skill required: " .. text(level)
    if jobIdentifier ~= nil then
        tooltip = tooltip .. "\n\nClick to open the associated profession tree."
    end
    requirementRow(
        parent,
        name .. " skill " .. text(level),
        iconSprite or fallbackSkillIcon(identifier),
        tooltip,
        jobIdentifier ~= nil and openProfession or nil
    )
end

local function recipeUnlockRequirements(parent, prefab)
    local identifier = id(prefab.Identifier)
    local talents = recipeTalents[identifier] or {}
    local blueprints = recipeBlueprints[identifier] or {}
    for _, talent in ipairs(talents) do
        local name = text(talent.DisplayName)
        local professionIdentifier = talentProfession[id(talent.Identifier)]
        local function openTalent()
            local profession = professionByIdentifier[professionIdentifier]
            if profession == nil then
                return
            end
            currentSearch = ""
            if searchBox ~= nil then
                searchBox.Text = ""
            end
            navigateTo("Professions", profession, id(talent.Identifier))
        end
        requirementRow(
            parent,
            "Required perk: " .. name,
            talent.Icon,
            name .. "\n\nClick to open this perk in its profession tree.",
            professionIdentifier ~= nil and openTalent or nil
        )
    end
    for _, blueprint in ipairs(blueprints) do
        local sprite = blueprint.prefab.InventoryIcon or blueprint.prefab.Sprite
        requirementRow(parent, "Required blueprint: " .. blueprint.name, sprite, blueprint.name)
    end
    if isEmpty(talents) and isEmpty(blueprints) then
        requirementRow(
            parent,
            "Required: recipe unlock",
            nil,
            "This recipe must be learned before fabrication."
        )
    end
end

local function itemButton(parent, entry, suffix)
    local button = GUI.Button(
        GUI.RectTransform(UI_VECTOR.LINK_ROW, parent, Anchor.TopCenter),
        "",
        Alignment.CenterLeft,
        "ListBoxElement"
    )
    button.Color = COLOR.ROW
    local sprite = entry.prefab.InventoryIcon or entry.prefab.Sprite
    if sprite ~= nil then
        local icon = GUI.Image(
            GUI.RectTransform(UI_VECTOR.LINK_ICON, button.RectTransform, Anchor.CenterLeft),
            sprite,
            true
        )
        icon.Color = entry.prefab.InventoryIcon and entry.prefab.InventoryIconColor
            or entry.prefab.SpriteColor
        icon.CanBeFocused = false
    end
    local caption = GUI.TextBlock(
        GUI.RectTransform(UI_VECTOR.LINK_TEXT, button.RectTransform, Anchor.CenterRight),
        entry.name .. (suffix or ""),
        COLOR.CREAM,
        GUI.Style.SmallFont,
        Alignment.CenterLeft,
        false,
        ""
    )
    caption.CanBeFocused = false
    button.OnClicked = function()
        navigateTo("Items", entry)
        return true
    end
    return button
end

local function conditionRequirementText(minimumCondition, maximumCondition)
    local minimum = tonumber(minimumCondition) or 0
    local maximum = tonumber(maximumCondition) or FULL_CONDITION
    if maximum < FULL_CONDITION then
        return "  •  condition ≤ " .. numberText(maximum * PERCENT_SCALE) .. "%"
    end
    if minimum > 0 then
        return "  •  condition ≥ " .. numberText(minimum * PERCENT_SCALE) .. "%"
    end
    return ""
end

local function recipeIngredient(
    parent,
    candidatePrefabs,
    amount,
    minimumCondition,
    maximumCondition
)
    local candidates, seen = {}, {}
    for _, prefab in ipairs(candidatePrefabs or {}) do
        local identifier = prefab and id(prefab.Identifier) or ""
        if identifier ~= "" and not seen[identifier] then
            seen[identifier] = true
            append(candidates, prefab)
        end
    end
    table.sort(candidates, function(a, b)
        return text(a.Name) < text(b.Name)
    end)
    local suffix = "  x"
        .. text(amount)
        .. conditionRequirementText(minimumCondition, maximumCondition)
    if #candidates == 1 then
        local prefab = candidates[1]
        itemButton(
            parent,
            { prefab = prefab, identifier = id(prefab.Identifier), name = text(prefab.Name) },
            suffix
        )
        return
    end
    if #candidates > 1 then
        local allAmmunitionContainers = true
        for _, candidate in ipairs(candidates) do
            local candidateIdentifier = id(candidate.Identifier)
            if
                not E.contains(candidateIdentifier, "box")
                and not E.contains(candidateIdentifier, "shells")
            then
                allAmmunitionContainers = false
                break
            end
        end
        if allAmmunitionContainers and (tonumber(maximumCondition) or 1) < 1 then
            requirementRow(
                parent,
                "Any compatible empty ammunition box" .. suffix,
                candidates[1].InventoryIcon or candidates[1].Sprite,
                "Use any compatible ammunition container that meets the empty-condition requirement."
            )
            return
        end
        local names = {}
        for _, prefab in ipairs(candidates) do
            append(names, text(prefab.Name))
        end
        local first = candidates[1]
        requirementRow(
            parent,
            table.concat(names, " or ") .. suffix,
            first.InventoryIcon or first.Sprite,
            "Any one of these ingredients satisfies this slot."
        )
        return
    end
    line(parent, "Compatible ingredient" .. suffix)
end

local function itemPrefabsWithTag(tagIdentifier)
    local matches, targetTag = {}, id(tagIdentifier)
    if targetTag == "" then
        return matches
    end
    for _, entry in ipairs(items) do
        for tag in entry.prefab.Tags do
            if id(tag) == targetTag then
                append(matches, entry.prefab)
                break
            end
        end
    end
    return matches
end

local function recipeTitle(index, total, displayName)
    local rawName = id(displayName)
    local purpose = "Craft new"
    if rawName == "recycleitem" then
        purpose = "Refill or recycle"
    elseif rawName ~= "" then
        purpose = cleanDisplayText(displayName)
        if purpose == "" then
            purpose = prettyIdentifier(displayName)
        end
    end
    if total > 1 then
        return "Recipe " .. text(index) .. " of " .. text(total) .. "  •  " .. purpose
    end
    return purpose
end

local function renderXmlRecipes(prefab, parent)
    if prefab.ConfigElement == nil then
        return 0
    end
    local xmlRecipes = E.each(prefab.ConfigElement.GetChildElements("Fabricate"))
    if #xmlRecipes > 0 then
        heading(parent, "\nCrafting")
    end
    for recipeIndex, recipe in ipairs(xmlRecipes) do
        if #xmlRecipes > 1 then
            heading(
                parent,
                recipeTitle(recipeIndex, #xmlRecipes, recipe.GetAttributeString("displayname", ""))
            )
        end
        local amount = recipe.GetAttributeInt("amount", 1)
        local requiredTime = recipe.GetAttributeFloat("requiredtime", 1)
        local devices = recipe.GetAttributeString("suitablefabricators", "")
        line(parent, "OUTPUT x" .. text(amount) .. "  •  " .. text(requiredTime) .. " s")
        local deviceNames = {}
        for device in string.gmatch(devices, "[^,%s]+") do
            append(deviceNames, prettyIdentifier(device))
        end
        line(
            parent,
            "DEVICE  " .. (#deviceNames > 0 and table.concat(deviceNames, ", ") or "Fabricator")
        )
        local requiresRecipe = recipe.GetAttributeBool("requiresrecipe", false)
        local hasSkills = false
        for requirement in recipe.Elements() do
            if id(requirement.NameAsIdentifier()) == "requiredskill" then
                hasSkills = true
                break
            end
        end
        if hasSkills or requiresRecipe then
            heading(parent, "Requirements")
        end
        for requirement in recipe.Elements() do
            if id(requirement.NameAsIdentifier()) == "requiredskill" then
                local identifier = requirement.GetAttributeIdentifier("identifier", "")
                skillRequirement(parent, identifier, requirement.GetAttributeInt("level", 0))
            end
        end
        if requiresRecipe then
            recipeUnlockRequirements(parent, prefab)
        end
        for requirement in recipe.Elements() do
            local elementName = id(requirement.NameAsIdentifier())
            if elementName == "item" or elementName == "requireditem" then
                local identifier = requirement.GetAttributeIdentifier("identifier", "")
                local quantity =
                    requirement.GetAttributeInt("count", requirement.GetAttributeInt("amount", 1))
                local ingredient = findItemPrefab(identifier)
                local tag = requirement.GetAttributeIdentifier("tag", "")
                local candidates = ingredient ~= nil and { ingredient } or itemPrefabsWithTag(tag)
                recipeIngredient(
                    parent,
                    candidates,
                    quantity,
                    requirement.GetAttributeFloat("mincondition", 0),
                    requirement.GetAttributeFloat("maxcondition", 1)
                )
            end
        end
    end
    return #xmlRecipes
end

local merchantNames = {
    merchantoutpost = "Outpost Merchant",
    merchantcity = "Colony Merchant",
    merchantresearch = "Research Merchant",
    merchantmilitary = "Military Merchant",
    merchantmine = "Mining Merchant",
    merchantmedical = "Medical Merchant",
    merchantengineering = "Engineering Merchant",
    merchantarmory = "Armory Merchant",
    merchantclown = "Clown Merchant",
    merchanthusk = "Husk Merchant",
    merchantnightclub = "Nightclub Merchant",
}

local function showItemCapabilities(prefab, parent)
    local root = prefab.ConfigElement
    if root == nil then
        return
    end
    local protection, stats, skillBonuses, attacks, requirements, equipment, connections = {}, {}, {}, {}, {}, {}, {}
    local ammunitionTags, isRangedWeapon = {}, false
    local connectionOrder = 0
    local attackIdentities = {}
    local attackEffects = {}
    local attackScalars = {}
    local function addAttack(value)
        local identity = id(value)
        if attackIdentities[identity] then
            return
        end
        attackIdentities[identity] = true
        append(attacks, value)
    end
    local function addAttackEffect(identifier, strength, probability)
        local effectIdentifier = id(identifier)
        local effect = attackEffects[effectIdentifier]
        if effect == nil then
            effect = {
                name = prettyIdentifier(identifier),
                components = {},
                identities = {},
            }
            attackEffects[effectIdentifier] = effect
        end
        local componentIdentity = numberText(strength) .. ":" .. numberText(probability)
        if effect.identities[componentIdentity] then
            return
        end
        effect.identities[componentIdentity] = true
        append(effect.components, {
            strength = tonumber(strength) or 0,
            probability = tonumber(probability) or 1,
        })
    end
    local function addAttackScalar(labelText, value, suffix)
        local key = id(labelText)
        attackScalars[key] = attackScalars[key] or {
            label = labelText,
            suffix = suffix or "",
            values = {},
            seen = {},
        }
        local normalized = numberText(value)
        if not attackScalars[key].seen[normalized] then
            attackScalars[key].seen[normalized] = true
            attackScalars[key].values[#attackScalars[key].values + 1] = normalized
        end
    end
    local function addAffectedEffects(target, identifiers, suffix)
        for identifier in string.gmatch(identifiers or "", "[^,%s]+") do
            target[#target + 1] = prettyIdentifier(identifier) .. suffix
        end
    end
    local function walk(element, context)
        local name = id(element.NameAsIdentifier())
        local nextContext = context
        if name == "fabricate" or name == "deconstruct" then
            return
        elseif name == "connectionpanel" then
            nextContext = "connectionpanel"
        elseif
            context == "connectionpanel"
            and (name == "connection" or name == "input" or name == "output")
        then
            local connectionName = element.GetAttributeString("name", "")
            if connectionName ~= "" then
                local displayIdentifier = element.GetAttributeString("displayname", "")
                local displayKey = string.match(displayIdentifier, "^connection%.([^~]+)")
                if displayKey == "signalinx" or displayKey == "signaloutx" then
                    displayKey = connectionName
                end
                connectionOrder = connectionOrder + 1
                connections[id(connectionName)] = {
                    name = prettyIdentifier(displayKey or connectionName),
                    wikiKey = wiringWikiKey(displayKey or connectionName),
                    direction = name == "input" and "INPUT"
                        or (name == "output" and "OUTPUT" or "PIN"),
                    order = connectionOrder,
                }
            end
        end
        if name == "wearable" then
            nextContext = "wearable"
            local slots = element.GetAttributeString("slots", "")
            if slots ~= "" then
                equipment[#equipment + 1] = "EQUIP SLOTS  " .. slots
                if E.contains(slots, "bag") then
                    equipment[#equipment + 1] = "BAG SLOT  Held with both hands; cannot be stored in normal inventory slots."
                end
            end
        elseif name == "meleeweapon" then
            nextContext = "weapon"
            local slots = element.GetAttributeString("slots", "")
            if slots ~= "" then
                equipment[#equipment + 1] = "HAND SLOTS  " .. slots
                if E.contains(slots, "bag") then
                    equipment[#equipment + 1] = "BAG SLOT  Held with both hands; cannot be stored in normal inventory slots."
                end
            end
            local reload = element.GetAttributeFloat("reload", 0)
            if reload > 0 then
                equipment[#equipment + 1] = "ATTACK COOLDOWN  " .. text(reload) .. " s"
            end
        elseif name == "rangedweapon" then
            nextContext = "weapon"
            isRangedWeapon = true
            equipment[#equipment + 1] = "SPREAD  "
                .. text(element.GetAttributeFloat("spread", 0))
                .. "°  •  UNSKILLED "
                .. text(element.GetAttributeFloat("unskilledspread", 0))
                .. "°"
        elseif name == "projectile" then
            nextContext = "weapon"
        elseif name == "containable" then
            for compatible in string.gmatch(element.GetAttributeString("items", ""), "[^,%s]+") do
                ammunitionTags[id(compatible)] = true
            end
        elseif name == "damagemodifier" and context == "wearable" then
            local multiplier = element.GetAttributeFloat("damagemultiplier", 1)
            local affected = element.GetAttributeString(
                "afflictionidentifiers",
                element.GetAttributeString("afflictiontypes", "damage")
            )
            local probabilityMultiplier = element.GetAttributeFloat("probabilitymultiplier", 1)
            if multiplier < 1 then
                addAffectedEffects(
                    protection,
                    affected,
                    "  "
                        .. text(math.floor((1 - multiplier) * PERCENT_SCALE + 0.5))
                        .. "% resistance"
                )
            elseif probabilityMultiplier < 1 then
                addAffectedEffects(
                    protection,
                    affected,
                    "  "
                        .. text(math.floor((1 - probabilityMultiplier) * PERCENT_SCALE + 0.5))
                        .. "% affliction resistance"
                )
            end
        elseif name == "skillmodifier" and context == "wearable" then
            local skillName = prettyIdentifier(element.GetAttributeString("skillidentifier", ""))
            local skillValue = element.GetAttributeFloat("skillvalue", 0)
            skillBonuses[#skillBonuses + 1] = skillName
                .. " skill  "
                .. (skillValue >= 0 and "+" or "")
                .. text(skillValue)
        elseif name == "statvalue" and context == "wearable" then
            local stat = prettyIdentifier(element.GetAttributeString("stattype", ""))
            local value = element.GetAttributeFloat("value", 0)
            stats[#stats + 1] = stat
                .. "  "
                .. (value >= 0 and "+" or "")
                .. text(math.floor(value * PERCENT_SCALE + 0.5))
                .. "%"
        elseif
            name == "statuseffect" and id(element.GetAttributeString("type", "")) == "onwearing"
        then
            local speed = element.GetAttributeFloat("speedmultiplier", 1)
            local pressure = element.GetAttributeFloat("pressureprotection", 0)
            if speed ~= 1 then
                stats[#stats + 1] = "Speed multiplier  "
                    .. text(math.floor(speed * PERCENT_SCALE + 0.5))
                    .. "%"
            end
            if pressure > 0 then
                stats[#stats + 1] = "Pressure protection  " .. text(pressure)
            end
        elseif name == "attack" or name == "explosion" then
            nextContext = "attack"
            local structureDamage = element.GetAttributeFloat("structuredamage", 0)
            local itemDamage = element.GetAttributeFloat("itemdamage", 0)
            local penetration = element.GetAttributeFloat("penetration", 0)
            if structureDamage > 0 then
                addAttackScalar("Structure damage", structureDamage)
            end
            if itemDamage > 0 then
                addAttackScalar("Item damage", itemDamage)
            end
            if penetration > 0 then
                addAttackScalar(
                    "Penetration",
                    math.floor(penetration * PERCENT_SCALE + 0.5),
                    "%"
                )
            end
        elseif name == "affliction" and context == "attack" then
            local strength =
                element.GetAttributeFloat("strength", element.GetAttributeFloat("amount", 0))
            local probability = element.GetAttributeFloat("probability", 1)
            addAttackEffect(
                element.GetAttributeString("identifier", "damage"),
                strength,
                probability
            )
        elseif name == "requireditem" and context ~= nil then
            local identifier = element.GetAttributeIdentifier("identifier", "")
            local target = findItemPrefab(identifier)
            requirements[#requirements + 1] = target and text(target.Name)
                or prettyIdentifier(identifier)
        end
        for child in element.Elements() do
            walk(child, nextContext)
        end
    end
    walk(root, nil)
    local scalarKeys = {}
    for key in pairs(attackScalars) do
        scalarKeys[#scalarKeys + 1] = key
    end
    table.sort(scalarKeys)
    for _, key in ipairs(scalarKeys) do
        local scalar = attackScalars[key]
        local values = table.concat(scalar.values, " / ") .. scalar.suffix
        if #scalar.values > 1 then
            values = values .. "  (attack components)"
        end
        addAttack(scalar.label .. "  " .. values)
    end
    local sortedEffectIdentifiers = {}
    for effectIdentifier in pairs(attackEffects) do
        append(sortedEffectIdentifiers, effectIdentifier)
    end
    table.sort(sortedEffectIdentifiers)
    for _, effectIdentifier in ipairs(sortedEffectIdentifiers) do
        local effect = attackEffects[effectIdentifier]
        local totalStrength = 0
        local allGuaranteed = true
        local componentDescriptions = {}
        for _, component in ipairs(effect.components) do
            totalStrength = totalStrength + component.strength
            if component.probability < 1 then
                allGuaranteed = false
            end
            append(
                componentDescriptions,
                numberText(component.strength)
                    .. (
                        component.probability < 1
                            and " at " .. numberText(
                                math.floor(component.probability * PERCENT_SCALE + 0.5)
                            ) .. "%"
                        or ""
                    )
            )
        end
        if #effect.components > 1 and allGuaranteed then
            addAttack(
                effect.name
                    .. "  "
                    .. numberText(totalStrength)
                    .. " total  ("
                    .. numberText(#effect.components)
                    .. " components)"
            )
        else
            addAttack(effect.name .. "  " .. table.concat(componentDescriptions, " + "))
        end
    end
    if #equipment > 0 then
        heading(parent, "\nEquipment")
        for _, value in ipairs(equipment) do
            line(parent, value)
        end
    end
    if #protection > 0 or #stats > 0 or #skillBonuses > 0 then
        heading(parent, "\nProtection and passive effects", COLOR.TEXT)
        for _, value in ipairs(protection) do
            coloredLine(parent, value, COLOR.TEXT)
        end
        for _, value in ipairs(stats) do
            coloredLine(parent, value, COLOR.TEXT)
        end
        for _, value in ipairs(skillBonuses) do
            coloredLine(parent, value, COLOR.TEXT)
        end
    end
    if #attacks > 0 then
        heading(parent, "\nDamage", COLOR.TEXT)
        for _, value in ipairs(attacks) do
            coloredLine(parent, value, COLOR.TEXT)
        end
    end
    if isRangedWeapon and next(ammunitionTags) ~= nil then
        local ammunition = {}
        local function containsDamageElement(element)
            if element == nil then
                return false
            end
            local elementName = id(element.NameAsIdentifier())
            if elementName == "attack" or elementName == "explosion" then
                return true
            end
            for child in element.Elements() do
                if containsDamageElement(child) then
                    return true
                end
            end
            return false
        end
        local function ammunitionDamageSummary(ammunitionPrefab)
            local totals = {}
            local function scan(element, inAttack)
                if element == nil then
                    return
                end
                local elementName = id(element.NameAsIdentifier())
                local attackContext = inAttack or elementName == "attack" or elementName == "explosion"
                if elementName == "affliction" and attackContext then
                    local effectIdentifier = id(element.GetAttributeString("identifier", "damage"))
                    local strength = element.GetAttributeFloat(
                        "strength",
                        element.GetAttributeFloat("amount", 0)
                    )
                    totals[effectIdentifier] = (totals[effectIdentifier] or 0) + strength
                end
                for child in element.Elements() do
                    scan(child, attackContext)
                end
            end
            scan(ammunitionPrefab.ConfigElement, false)
            local parts = {}
            for effectIdentifier, strength in pairs(totals) do
                if strength > 0 then
                    parts[#parts + 1] = prettyIdentifier(effectIdentifier)
                        .. " "
                        .. numberText(strength)
                end
            end
            table.sort(parts)
            return table.concat(parts, ", ")
        end
        for _, candidate in ipairs(items) do
            local matches = ammunitionTags[candidate.identifier] == true
            if not matches then
                for tag in candidate.prefab.Tags do
                    if ammunitionTags[id(tag)] then
                        matches = true
                        break
                    end
                end
            end
            if
                matches
                and candidate.identifier ~= id(prefab.Identifier)
                and containsDamageElement(candidate.prefab.ConfigElement)
            then
                ammunition[#ammunition + 1] = candidate
            end
        end
        table.sort(ammunition, function(a, b)
            return a.name < b.name
        end)
        if #ammunition > 0 then
            heading(parent, "\nDamage by ammunition", COLOR.TEXT)
            line(parent, "Weapon damage is defined by its loaded projectile. Open an ammunition entry for the complete damage breakdown.")
            for _, candidate in ipairs(ammunition) do
                local summary = ammunitionDamageSummary(candidate.prefab)
                itemButton(
                    parent,
                    candidate,
                    summary ~= "" and "  •  " .. summary or "  •  damage source"
                )
            end
        end
    end
    if #requirements > 0 then
        heading(parent, "\nRequires to operate")
        for _, value in ipairs(requirements) do
            line(parent, value)
        end
    end
    local itemName = text(prefab.Name)
    local identifierKey = wiringWikiKey(prefab.Identifier)
    local nameKey = wiringWikiKey(itemName)
    local wikiKey = WIRING_WIKI_ALIASES[identifierKey] or identifierKey
    local wiringWiki = wiringWikiData[wikiKey] or wiringWikiData[nameKey]
    -- Some component pages do not publish a connection-panel table, but do
    -- publish an exact functional description. Keep that description tied to
    -- the actual item even when a compatible panel layout comes from an alias.
    local directWiringWiki = wiringWikiData[identifierKey] or wiringWikiData[nameKey]
    local wiringSummary = text(
        (directWiringWiki and directWiringWiki.summary)
        or (wiringWiki and wiringWiki.summary)
        or ""
    )
    local connectionDescriptions = {}
    local connectionWikiNames = {}
    local connectionWikiDirections = {}
    if wiringWiki ~= nil then
        for _, wikiPin in ipairs(wiringWiki.pins or {}) do
            local pinKey = wiringWikiKey(wikiPin.name)
            connectionDescriptions[pinKey] = wikiPin.tooltip
            connectionWikiNames[pinKey] = wikiPin.name
            connectionWikiDirections[pinKey] = string.upper(wikiPin.direction or "")
        end
    end
    local connectionKeys = {}
    for key in pairs(connections) do
        connectionKeys[#connectionKeys + 1] = key
    end
    table.sort(connectionKeys, function(a, b)
        return connections[a].order < connections[b].order
    end)
    if wiringWiki ~= nil then
        local matchedPins = 0
        for _, key in ipairs(connectionKeys) do
            local pin = connections[key]
            if
                connectionDescriptions[pin.wikiKey] ~= nil
                and connectionWikiDirections[pin.wikiKey] == pin.direction
            then
                matchedPins = matchedPins + 1
            end
        end
        if matchedPins ~= #connectionKeys or matchedPins ~= #(wiringWiki.pins or {}) then
            connectionDescriptions = {}
            connectionWikiNames = {}
        end
    end
    if #connectionKeys > 0 then
        local inputKeys, outputKeys = {}, {}
        for _, key in ipairs(connectionKeys) do
            if connections[key].direction == "OUTPUT" then
                outputKeys[#outputKeys + 1] = key
            else
                inputKeys[#inputKeys + 1] = key
            end
        end
        local rows = math.max(1, #inputKeys, #outputKeys)
        local card = GUI.Frame(
            GUI.RectTransform(relativeVector(0.46, 0.17 + rows * 0.065), parent, Anchor.TopCenter),
            "ConnectionPanel"
        )
        card.RectTransform.MinSize = Point(400, 210 + (rows - 1) * 42)
        card.RectTransform.MaxSize = Point(520, 210 + (rows - 1) * 42)
        local cardTitle = GUI.TextBlock(
            GUI.RectTransform(relativeVector(0.94, 0.10), card.RectTransform, Anchor.TopCenter),
            "Connection Panel for " .. itemName,
            COLOR.GREEN,
            GUI.Style.SmallFont,
            Alignment.Center,
            false,
            ""
        )
        cardTitle.RectTransform.RelativeOffset = relativeVector(0, 0.02)
        cardTitle.CanBeFocused = false
        local instruction = GUI.TextBlock(
            GUI.RectTransform(relativeVector(0.94, 0.08), card.RectTransform, Anchor.TopCenter),
            "Hover over pins to see their descriptions.",
            COLOR.HEADING,
            GUI.Style.SmallFont,
            Alignment.Center,
            false,
            ""
        )
        instruction.RectTransform.RelativeOffset = relativeVector(0, 0.105)
        instruction.CanBeFocused = false
        local panel = GUI.Frame(
            GUI.RectTransform(relativeVector(0.90, 0.60), card.RectTransform, Anchor.Center),
            "ConnectionPanelFront"
        )
        panel.RectTransform.MinSize = Point(360, 92 + (rows - 1) * 38)
        panel.RectTransform.MaxSize = Point(480, 92 + (rows - 1) * 38)
        local inputs = GUI.LayoutGroup(
            GUI.RectTransform(relativeVector(0.46, 0.86), panel.RectTransform, Anchor.CenterLeft),
            false,
            Anchor.TopLeft
        )
        local outputs = GUI.LayoutGroup(
            GUI.RectTransform(relativeVector(0.46, 0.86), panel.RectTransform, Anchor.CenterRight),
            false,
            Anchor.TopRight
        )
        local function addPin(target, key, isOutput)
            local pin = connections[key]
            local logicDescriptions = LOGIC_COMPONENT_PIN_DESCRIPTIONS[identifierKey]
                or LOGIC_COMPONENT_PIN_DESCRIPTIONS[nameKey]
            local exactLogicDescription = logicDescriptions
                and (logicDescriptions[pin.wikiKey] or logicDescriptions[wiringWikiKey(key)])
            local pinDescription = exactLogicDescription
                or connectionDescriptions[pin.wikiKey]
                or connectionDescriptions[wiringWikiKey(key)]
                or ""
            local description
            if exactLogicDescription ~= nil then
                description = exactLogicDescription
            elseif wiringSummary ~= "" and pinDescription ~= "" then
                description = wiringSummary .. "\n\n" .. pinDescription
            elseif wiringSummary ~= "" then
                description = wiringSummary
                    .. "\n\nThe official connection panel does not provide a more specific description for this pin."
            elseif pinDescription ~= "" then
                description = pinDescription
            else
                description = "The official wiki does not currently provide a description for this pin."
            end
            local displayName = connectionWikiNames[pin.wikiKey]
                or connectionWikiNames[wiringWikiKey(key)]
                or key
            local row = GUI.Frame(
                GUI.RectTransform(relativeVector(1, math.min(0.30, 0.82 / rows)), target),
                nil
            )
            row.RectTransform.MinSize = Point(0, 38)
            row.RectTransform.MaxSize = Point(1000, 42)
            local socket = GUI.Frame(
                GUI.RectTransform(
                    relativeVector(0.16, 0.76),
                    row.RectTransform,
                    isOutput and Anchor.CenterRight or Anchor.CenterLeft
                ),
                "ConnectionPanelConnection"
            )
            socket.RectTransform.MinSize = Point(34, 34)
            socket.RectTransform.MaxSize = Point(38, 38)
            local isPower = E.contains(key, "power")
            local pinLabel = GUI.Frame(
                GUI.RectTransform(
                    relativeVector(0.82, 0.70),
                    row.RectTransform,
                    isOutput and Anchor.CenterLeft or Anchor.CenterRight
                ),
                "ConnectionPanelLabel"
            )
            pinLabel.RectTransform.MinSize = Point(110, 28)
            pinLabel.RectTransform.MaxSize = Point(220, 34)
            pinLabel.Color = isPower and COLOR.RED or COLOR.CYAN
            local pinText = GUI.TextBlock(
                GUI.RectTransform(relativeVector(0.94, 0.90), pinLabel.RectTransform, Anchor.Center),
                string.upper(displayName),
                COLOR.CREAM,
                GUI.Style.SmallFont,
                Alignment.Center,
                false,
                ""
            )
            pinText.CanBeFocused = false
            pinLabel.ToolTip = description
            pinText.ToolTip = description
            socket.ToolTip = description
        end
        for _, key in ipairs(inputKeys) do
            addPin(inputs.RectTransform, key, false)
        end
        for _, key in ipairs(outputKeys) do
            addPin(outputs.RectTransform, key, true)
        end
        local requirement = GUI.TextBlock(
            GUI.RectTransform(relativeVector(0.94, 0.10), card.RectTransform, Anchor.BottomCenter),
            "Requires:  🔧  Screwdriver",
            COLOR.GREEN,
            GUI.Style.SmallFont,
            Alignment.Center,
            false,
            ""
        )
        requirement.CanBeFocused = false
    end
end

local function showMerchantInfo(prefab, parent)
    local priceElement = prefab.ConfigElement and prefab.ConfigElement.GetChildElement("price")
        or nil
    if priceElement == nil and prefab.DefaultPrice == nil then
        return
    end
    heading(parent, "\nMerchants and prices")
    local staticCount = 0
    if priceElement ~= nil then
        local basePrice = priceElement.GetAttributeInt(
            "baseprice",
            prefab.DefaultPrice and prefab.DefaultPrice.Price or 0
        )
        for storePrice in priceElement.GetChildElements("price") do
            if storePrice.GetAttributeBool("sold", priceElement.GetAttributeBool("sold", true)) then
                staticCount = staticCount + 1
                local storeIdentifier = id(
                    storePrice.GetAttributeString(
                        "storeidentifier",
                        storePrice.GetAttributeString("locationtype", "merchant")
                    )
                )
                local price =
                    math.floor(basePrice * storePrice.GetAttributeFloat("multiplier", 1) + 0.5)
                local restrictions = {}
                local faction = storePrice.GetAttributeString("requiredfaction", "")
                if faction ~= "" then
                    restrictions[#restrictions + 1] = "faction " .. prettyIdentifier(faction)
                end
                for reputation in storePrice.GetChildElements("reputation") do
                    restrictions[#restrictions + 1] = prettyIdentifier(
                        reputation.GetAttributeString("faction", "")
                    ) .. " reputation " .. text(
                        reputation.GetAttributeFloat("min", 0)
                    )
                end
                line(
                    parent,
                    (merchantNames[storeIdentifier] or prettyIdentifier(storeIdentifier))
                        .. "  "
                        .. text(price)
                        .. " mk base"
                        .. (
                            #restrictions > 0 and "  •  " .. table.concat(restrictions, ", ")
                            or ""
                        )
                )
            end
        end
        if staticCount == 0 and priceElement.GetAttributeBool("sold", true) then
            staticCount = 1
            line(parent, "Standard merchants  " .. text(basePrice) .. " mk base")
        end
    end
    if staticCount == 0 then
        line(parent, "Not sold by standard merchants.")
    end

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
                    line(
                        parent,
                        (merchantNames[id(store.Identifier)] or prettyIdentifier(store.Identifier))
                            .. "  "
                            .. text(price)
                            .. " mk  •  LIVE ADJUSTED"
                    )
                end
            end
        end)
    end
    if liveCount == 0 then
        line(parent, "Live adjusted prices appear while docked at an applicable campaign merchant.")
    end
end

local function durationText(seconds)
    local total = math.floor((tonumber(seconds) or 0) + 0.5)
    local minutes = math.floor(total / 60)
    local remaining = total % 60
    return text(minutes) .. "m " .. text(remaining) .. "s"
end

local function showSupplyDuration(prefab, parent)
    local identifier = id(prefab.Identifier)
    if E.contains(identifier, "fuelrod") then
        local durability = tonumber(safeField(prefab, "Health", 100)) or 100
        heading(parent, "\nFuel endurance by quality")
        line(
            parent,
            "Reactor runtime is not a fixed clock: it changes with fission rate, reactor fuel efficiency, and the number of inserted rods. Quality increases rod durability."
        )
        for _, quality in ipairs({
            { "Normal", 1 },
            { "Good", 1.1 },
            { "Excellent", 1.2 },
            { "Masterwork", 1.3 },
        }) do
            line(parent, quality[1] .. "  •  " .. numberText(durability * quality[2]) .. " durability")
        end
        return
    end
    local normalDuration = nil
    if E.contains(identifier, "divingmask") or E.contains(identifier, "clowndivingmask") then
        normalDuration = 400
    elseif
        E.contains(identifier, "divingsuit")
        or identifier == "slipsuit"
        or identifier == "pucs"
        or identifier == "exosuit"
    then
        normalDuration = 666
    end
    if normalDuration == nil then
        return
    end
    heading(parent, "\nBreathing-supply endurance")
    line(parent, "Times assume continuous use with a full tank.")
    local qualities = {
        { "Normal", 1 },
        { "Good", 1.1 },
        { "Excellent", 1.2 },
        { "Masterwork", 1.3 },
    }
    for _, quality in ipairs(qualities) do
        line(
            parent,
            quality[1]
                .. "  •  Oxygen Tank "
                .. durationText(normalDuration * quality[2])
                .. "  •  Oxygenite Tank "
                .. durationText(normalDuration * 2 * quality[2])
        )
    end
    line(parent, "Fuel tanks are not breathing supplies and cause oxygen loss; Incendium fuel also burns the wearer.")
end

-- Detail pages ---------------------------------------------------------------

showItem = function(entry)
    clear(detailList)
    local p = entry.prefab
    local hero = GUI.Frame(
        GUI.RectTransform(UI_VECTOR.ITEM_HERO, detailList.Content.RectTransform, Anchor.TopCenter),
        "InnerFrame"
    )
    hero.Color = COLOR.PANEL_ALTERNATE
    local sprite = p.InventoryIcon or p.Sprite
    if sprite ~= nil then
        local image = GUI.Image(
            GUI.RectTransform(UI_VECTOR.ITEM_HERO_ICON, hero.RectTransform, Anchor.CenterLeft),
            sprite,
            true
        )
        image.RectTransform.RelativeOffset = UI_VECTOR.OFFSET_STANDARD
        image.Color = p.InventoryIcon and p.InventoryIconColor or p.SpriteColor
        image.CanBeFocused = false
    end
    local title = GUI.TextBlock(
        GUI.RectTransform(UI_VECTOR.ITEM_HERO_TITLE, hero.RectTransform, Anchor.TopRight),
        string.upper(entry.name),
        COLOR.CREAM,
        GUI.Style.SubHeadingFont,
        Alignment.CenterLeft,
        false,
        ""
    )
    title.CanBeFocused = false
    local description = text(p.Description)
    local summary = GUI.TextBlock(
        GUI.RectTransform(UI_VECTOR.ITEM_HERO_SUMMARY, hero.RectTransform, Anchor.BottomRight),
        description ~= "" and description
            or "No description supplied by the loaded content package.",
        COLOR.TEXT,
        GUI.Style.SmallFont,
        Alignment.TopLeft,
        true,
        ""
    )
    summary.CanBeFocused = false
    infoRow(detailList.Content.RectTransform, "Identifier", entry.identifier)
    infoRow(detailList.Content.RectTransform, "Category", categoryText(p.Category), palette.orange)
    if joined(p.Tags) ~= "" then
        infoRow(detailList.Content.RectTransform, "Tags", joined(p.Tags), palette.muted)
    end
    if p.DefaultPrice ~= nil then
        infoRow(
            detailList.Content.RectTransform,
            "Base price",
            text(p.DefaultPrice.Price) .. " mk",
            palette.green
        )
    end
    if p.MaxStackSize ~= nil then
        infoRow(detailList.Content.RectTransform, "Stack size", text(p.MaxStackSize))
    end
    local recipes = E.each(p.FabricationRecipes.Values)
    if isEmpty(recipes) then
        if renderXmlRecipes(p, detailList.Content.RectTransform) == 0 then
            heading(detailList.Content.RectTransform, "\nCrafting")
            line(
                detailList.Content.RectTransform,
                "Not craftable: the loaded prefab defines no fabrication recipe."
            )
        end
    else
        heading(detailList.Content.RectTransform, "\nCrafting")
        for recipeIndex, recipe in ipairs(recipes) do
            if #recipes > 1 then
                heading(
                    detailList.Content.RectTransform,
                    recipeTitle(recipeIndex, #recipes, safeField(recipe, "DisplayName", ""))
                )
            end
            line(
                detailList.Content.RectTransform,
                "OUTPUT x" .. text(recipe.Amount) .. "  •  " .. text(recipe.RequiredTime) .. " s"
            )
            line(
                detailList.Content.RectTransform,
                "DEVICE  " .. joinedPretty(recipe.SuitableFabricatorIdentifiers)
            )
            local requiredSkills = E.each(recipe.RequiredSkills)
            if #requiredSkills > 0 or recipe.RequiresRecipe then
                heading(detailList.Content.RectTransform, "Requirements")
            end
            for _, skill in ipairs(requiredSkills) do
                skillRequirement(
                    detailList.Content.RectTransform,
                    skill.Identifier,
                    skill.Level,
                    skill.DisplayName,
                    skill.Icon
                )
            end
            if recipe.RequiresRecipe then
                recipeUnlockRequirements(detailList.Content.RectTransform, p)
            end
            for _, requirement in ipairs(E.each(recipe.RequiredItems)) do
                local candidates = E.each(safeField(requirement, "ItemPrefabs", nil))
                if #candidates == 0 and requirement.FirstMatchingPrefab ~= nil then
                    candidates[1] = requirement.FirstMatchingPrefab
                end
                recipeIngredient(
                    detailList.Content.RectTransform,
                    candidates,
                    requirement.Amount,
                    safeField(requirement, "MinCondition", 0),
                    safeField(requirement, "MaxCondition", 1)
                )
            end
        end
    end

    local used = reverseCraft[entry.identifier] or {}
    if hasEntries(used) then
        heading(detailList.Content.RectTransform, "\nCan be used to craft")
    end
    for _, target in ipairs(used) do
        itemButton(detailList.Content.RectTransform, target)
    end

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
    if hasEntries(outputs) then
        heading(detailList.Content.RectTransform, "\nDeconstructs into")
    end
    local sortedOutputs = {}
    for _, output in pairs(combinedOutputs) do
        sortedOutputs[#sortedOutputs + 1] = output
    end
    table.sort(sortedOutputs, function(a, b)
        return id(a.identifier) < id(b.identifier)
    end)
    for _, output in ipairs(sortedOutputs) do
        local target = findItemPrefab(output.identifier)
        local suffix = "  x" .. text(output.amount)
        if output.commonness < 1 then
            suffix = suffix
                .. "  (conditional, "
                .. text(math.floor(output.commonness * 100))
                .. "% minimum)"
        end
        if target ~= nil then
            itemButton(
                detailList.Content.RectTransform,
                { prefab = target, identifier = id(target.Identifier), name = text(target.Name) },
                suffix
            )
        else
            line(detailList.Content.RectTransform, text(output.identifier) .. suffix)
        end
    end

    local sources = reverseDeconstruct[entry.identifier] or {}
    if hasEntries(sources) then
        heading(detailList.Content.RectTransform, "\nDeconstruction sources")
    end
    local combinedSources = {}
    for _, source in ipairs(sources) do
        local key = source.source.identifier
        combinedSources[key] = combinedSources[key] or { source = source.source, amount = 0 }
        combinedSources[key].amount = combinedSources[key].amount
            + (tonumber(source.output.Amount) or 0)
    end
    local sortedSources = {}
    for _, source in pairs(combinedSources) do
        sortedSources[#sortedSources + 1] = source
    end
    table.sort(sortedSources, function(a, b)
        return a.source.name < b.source.name
    end)
    for _, source in ipairs(sortedSources) do
        itemButton(
            detailList.Content.RectTransform,
            source.source,
            "  → x" .. text(source.amount)
        )
    end

    showItemCapabilities(p, detailList.Content.RectTransform)
    showSupplyDuration(p, detailList.Content.RectTransform)
    showMerchantInfo(p, detailList.Content.RectTransform)
end

local function collectCreatureDrops(prefab)
    local drops = {}
    local function addDrop(identifier, amount, note)
        local key = id(identifier)
        if key == "" then
            return
        end
        local drop = drops[key] or { identifier = identifier, amount = 0, notes = {} }
        drop.amount = math.max(drop.amount, tonumber(amount) or 1)
        if note ~= nil and note ~= "" then
            drop.notes[note] = true
        end
        drops[key] = drop
    end
    local function walk(element, deconstruction)
        if element == nil then
            return
        end
        local elementName = id(element.NameAsIdentifier())
        local isDeconstruction = deconstruction
        if elementName == "statuseffect" then
            isDeconstruction = id(element.GetAttributeString("type", "")) == "ondeconstructed"
        elseif elementName == "inventory" then
            local weight = element.GetAttributeFloat("commonness", 1)
            for child in element.Elements() do
                if id(child.NameAsIdentifier()) == "item" then
                    local chance = child.GetAttributeFloat("commonness", 1)
                    addDrop(
                        child.GetAttributeIdentifier("identifier", ""),
                        child.GetAttributeInt("amount", 1),
                        "loot pool weight " .. text(weight * chance)
                    )
                end
            end
        elseif elementName == "spawnitem" and isDeconstruction then
            local identifiers = element.GetAttributeString(
                "identifiers",
                element.GetAttributeString("identifier", "")
            )
            local probability = element.GetAttributeFloat("probability", 1)
            for identifier in string.gmatch(identifiers, "[^,%s]+") do
                addDrop(
                    identifier,
                    element.GetAttributeInt("count", 1),
                    text(math.floor(probability * 100)) .. "% when deconstructed"
                )
            end
        end
        for child in element.Elements() do
            walk(child, isDeconstruction)
        end
    end
    walk(prefab.ConfigElement, false)
    local result = {}
    for _, drop in pairs(drops) do
        result[#result + 1] = drop
    end
    table.sort(result, function(a, b)
        return id(a.identifier) < id(b.identifier)
    end)
    return result
end

local function showCreature(entry)
    clear(detailList)
    local p = entry.prefab
    heading(detailList.Content.RectTransform, entry.name)
    local wiki = wikiCreatures[entry.identifier]
        or wikiCreatures[creatureBaseIdentifier(entry.identifier)]
    local preview = wikiCreatureSprite(entry) or creaturePreviewSprite(p)
    if preview ~= nil then
        local previewFrame = GUI.Frame(
            GUI.RectTransform(
                UI_VECTOR.CREATURE_PREVIEW,
                detailList.Content.RectTransform,
                Anchor.TopCenter
            ),
            "InnerFrame"
        )
        previewFrame.Color = COLOR.PANEL_ALTERNATE
        local previewButton = GUI.Button(
            GUI.RectTransform(UI_VECTOR.FULL, previewFrame.RectTransform, Anchor.Center),
            "",
            Alignment.Center,
            "ListBoxElement"
        )
        local image = GUI.Image(
            GUI.RectTransform(
                UI_VECTOR.CREATURE_PREVIEW_IMAGE,
                previewButton.RectTransform,
                Anchor.Center
            ),
            preview,
            true
        )
        image.CanBeFocused = false
        previewButton.ToolTip = "Click to enlarge"
        previewButton.OnClicked = function()
            showImageOverlay(preview, entry.name)
            return true
        end
    end
    line(detailList.Content.RectTransform, "SPECIES  " .. entry.name)
    local baseIdentifier = creatureBaseIdentifier(entry.identifier)
    local foundIn = CREATURE_HABITATS[baseIdentifier]
    if foundIn == nil and #entry.habitats > 0 then
        foundIn = table.concat(entry.habitats, ", ")
    end
    if foundIn == nil then
        if entry.family == "Husks" then
            foundIn = "Submarines, wrecks, ruins, and locations affected by the Husk infection"
        elseif entry.family == "Other creatures" then
            foundIn = "Special encounters, ruins, caves, or open waters depending on the creature"
        else
            foundIn = "Normal open waters and mission encounters"
        end
    end
    line(detailList.Content.RectTransform, "FOUND IN  " .. foundIn)
    local variantIdentifier = id(p.VariantOf)
    if variantIdentifier ~= "" then
        local parentPrefab = findCharacterPrefab(variantIdentifier)
        line(
            detailList.Content.RectTransform,
            "VARIANT OF  "
                .. (parentPrefab and text(parentPrefab.Name) or prettyIdentifier(variantIdentifier))
        )
    end
    if p.ConfigElement ~= nil then
        local description = wiki and wiki.description
            or p.ConfigElement.GetAttributeString("description", "")
        heading(detailList.Content.RectTransform, "\nDescription")
        line(
            detailList.Content.RectTransform,
            description ~= "" and description
                or "No official description is provided by the loaded content package."
        )
        local health = p.ConfigElement.GetChildElement("health")
        local vitality = health and health.GetAttributeFloat("vitality", 0) or 0
        if vitality > 0 then
            heading(detailList.Content.RectTransform, "\nHealth")
            line(detailList.Content.RectTransform, "VITALITY  " .. text(vitality))
        end
        if entry.identifier:match("_m$") then
            heading(detailList.Content.RectTransform, "\nMission-variant differences")
            line(
                detailList.Content.RectTransform,
                "BOSS MISSION VARIANT  •  Uses a boss health bar and mission-enforced aggression."
            )
            local parentPrefab = p.ParentPrefab
            local parentHealth = parentPrefab
                    and parentPrefab.ConfigElement
                    and parentPrefab.ConfigElement.GetChildElement("health")
                or nil
            local parentVitality = parentHealth and parentHealth.GetAttributeFloat("vitality", 0)
                or 0
            if vitality > 0 and parentVitality > 0 and vitality ~= parentVitality then
                line(
                    detailList.Content.RectTransform,
                    "VITALITY  " .. numberText(parentVitality) .. " normal → " .. numberText(vitality) .. " mission"
                )
            end
            line(
                detailList.Content.RectTransform,
                "Other values shown on this page come from the mission prefab, not the normal creature."
            )
        end
    end
    local familyTips = {
        ["Hammerheads"] = "Keep the submarine moving and deny them a clean charge at the hull.",
        ["Crawlers"] = "Watch breached compartments: crawlers can enter the submarine and overwhelm isolated crew.",
        ["Mudraptors"] = "Their armor makes frontal shots inefficient; maintain distance and target exposed limbs or gaps.",
        ["Molochs"] = "Their soft core is the priority target. Active sonar can attract and agitate them.",
        ["Spinelings"] = "Change direction when they line up a volley and engage after their spines are spent.",
        ["Fractal Guardians"] = "Use cover inside ruins and avoid fighting their ranged and melee attacks in open corridors.",
        ["Husks"] = "Keep your distance and treat any husk infection immediately after contact.",
        ["Threshers"] = "Avoid their mouth and concentrate fire on less-armored tissue.",
        ["Abyssal creatures"] = "Use heavy submarine weapons, preserve distance, and keep repair teams ready before engaging.",
        ["Other creatures"] = "Observe its attack pattern before committing; preserve distance and protect breached compartments.",
    }
    heading(detailList.Content.RectTransform, "\nCombat notes")
    if entry.identifier == "hammerheadmatriarch" then
        line(detailList.Content.RectTransform, "BEHAVIOR  Passive until provoked.")
    end
    line(detailList.Content.RectTransform, "TIP  " .. familyTips[entry.family])
    local weakspots, strongestMultiplier = {}, 1
    local damageTypes = {}
    local function scanWeakspots(element, limbName)
        if element == nil then
            return
        end
        local elementName = id(element.NameAsIdentifier())
        local currentLimb = limbName
        if elementName == "limb" then
            currentLimb = element.GetAttributeString(
                "name",
                element.GetAttributeString("type", element.GetAttributeString("id", "Body"))
            )
        end
        local multiplier = element.GetAttributeFloat("damagemultiplier", 1)
        if elementName == "damagemodifier" then
            local affected = element.GetAttributeString(
                "afflictionidentifiers",
                element.GetAttributeString("afflictiontypes", "")
            )
            for affectedType in string.gmatch(affected, "[^,%s]+") do
                local key = id(affectedType)
                local previous = damageTypes[key]
                if previous == nil or multiplier > previous.multiplier then
                    damageTypes[key] = {
                        name = prettyIdentifier(affectedType),
                        multiplier = multiplier,
                    }
                end
            end
        end
        if currentLimb ~= nil and multiplier > strongestMultiplier then
            strongestMultiplier = multiplier
            weakspots = { prettyIdentifier(currentLimb) }
        elseif currentLimb ~= nil and multiplier == strongestMultiplier and multiplier > 1 then
            weakspots[#weakspots + 1] = prettyIdentifier(currentLimb)
        end
        for child in element.Elements() do
            scanWeakspots(child, currentLimb)
        end
    end
    scanWeakspots(p.ConfigElement, nil)
    if #weakspots > 0 then
        line(
            detailList.Content.RectTransform,
            "WEAKSPOTS  " .. table.concat(weakspots, ", ") .. "  •  " .. numberText(strongestMultiplier) .. "× damage"
        )
    elseif CREATURE_WEAKSPOTS[baseIdentifier] ~= nil then
        line(
            detailList.Content.RectTransform,
            "WEAKSPOTS  " .. CREATURE_WEAKSPOTS[baseIdentifier]
        )
    else
        line(detailList.Content.RectTransform, "WEAKSPOTS  No special weakspot; target exposed, unarmored body parts.")
    end
    local vulnerable, resistant = {}, {}
    for _, damageType in pairs(damageTypes) do
        local description = damageType.name .. " " .. numberText(damageType.multiplier) .. "×"
        if damageType.multiplier > 1 then
            vulnerable[#vulnerable + 1] = description
        elseif damageType.multiplier < 1 then
            resistant[#resistant + 1] = description
        end
    end
    table.sort(vulnerable)
    table.sort(resistant)
    if #vulnerable > 0 then
        line(detailList.Content.RectTransform, "TAKES MOST DAMAGE FROM  " .. table.concat(vulnerable, ", "))
    end
    if #resistant > 0 then
        line(detailList.Content.RectTransform, "RESISTANCES  " .. table.concat(resistant, ", "))
    end
    local drops = collectCreatureDrops(p)
    heading(detailList.Content.RectTransform, "\nDrops")
    if isEmpty(drops) then
        line(
            detailList.Content.RectTransform,
            "No corpse loot or deconstruction drops are declared."
        )
    end
    for _, drop in ipairs(drops) do
        local target = findItemPrefab(drop.identifier)
        local notes = {}
        for note in pairs(drop.notes) do
            notes[#notes + 1] = note
        end
        table.sort(notes)
        local suffix = "  x"
            .. text(drop.amount)
            .. (#notes > 0 and "  •  " .. table.concat(notes, ", ") or "")
        if target ~= nil then
            itemButton(
                detailList.Content.RectTransform,
                { prefab = target, identifier = id(target.Identifier), name = text(target.Name) },
                suffix
            )
        else
            line(detailList.Content.RectTransform, prettyIdentifier(drop.identifier) .. suffix)
        end
    end
end

local function findTalent(identifier)
    local key = id(identifier)
    for talent in TalentPrefab.TalentPrefabs do
        if talent ~= nil and id(talent.Identifier) == key then
            return talent
        end
    end
    return nil
end

local function submarineTierColor(tier)
    if tier == 3 then
        return COLOR.GOLD
    end
    if tier == 2 then
        return COLOR.CYAN
    end
    return COLOR.CREAM
end

local SUBMARINE_WEAPON_NAMES = {
    coilgun = "Coilgun",
    doublecoilgun = "Double Coilgun",
    chaingun = "Chaingun",
    flakcannon = "Flak Cannon",
    pulselaser = "Pulse Laser",
    railgun = "Railgun",
}

local function loadedSubmarineWeapons(info)
    local counts = {}
    local root = safeField(info, "SubmarineElement", nil)
    local function walk(element)
        if element == nil then
            return
        end
        if id(element.NameAsIdentifier()) == "item" then
            local identifier = id(element.GetAttributeIdentifier("identifier", ""))
            local weaponName = SUBMARINE_WEAPON_NAMES[identifier]
            if weaponName ~= nil then
                counts[weaponName] = (counts[weaponName] or 0) + 1
            end
        end
        for child in element.Elements() do
            walk(child)
        end
    end
    walk(root)

    local weapons = {}
    local gunCount = 0
    for weaponName, count in pairs(counts) do
        append(weapons, numberText(count) .. " " .. weaponName .. (count == 1 and "" or "s"))
        gunCount = gunCount + count
    end
    table.sort(weapons)
    return weapons, gunCount
end

local function wikiWeaponCount(weapons)
    local total = 0
    for _, weapon in ipairs(weapons or {}) do
        total = total + (tonumber(string.match(weapon, "^(%d+)")) or 0)
    end
    return total
end

local function showSubmarine(entry)
    clear(detailList)
    local info = entry.prefab
    heading(detailList.Content.RectTransform, entry.name)

    local preview = safeField(info, "PreviewImage", nil)
    if preview ~= nil then
        local previewFrame = GUI.Frame(
            GUI.RectTransform(
                UI_VECTOR.CREATURE_PREVIEW,
                detailList.Content.RectTransform,
                Anchor.TopCenter
            ),
            "InnerFrame"
        )
        previewFrame.Color = COLOR.PANEL_ALTERNATE
        local previewButton = GUI.Button(
            GUI.RectTransform(UI_VECTOR.FULL, previewFrame.RectTransform, Anchor.Center),
            "",
            Alignment.Center,
            "ListBoxElement"
        )
        local previewImage = GUI.Image(
            GUI.RectTransform(
                UI_VECTOR.CREATURE_PREVIEW_IMAGE,
                previewButton.RectTransform,
                Anchor.Center
            ),
            preview,
            true
        )
        previewImage.CanBeFocused = false
        previewButton.ToolTip = "Open submarine preview"
        previewButton.OnClicked = function()
            showImageOverlay(preview, entry.name)
            return true
        end
    end

    local description = cleanDisplayText(safeField(info, "Description", ""))
    line(
        detailList.Content.RectTransform,
        description ~= "" and description or "No description is supplied by this submarine file."
    )

    infoRow(
        detailList.Content.RectTransform,
        "Class",
        prettyIdentifier(safeField(info, "SubmarineClass", "Unknown")),
        COLOR.CYAN
    )
    local tier = tonumber(safeField(info, "Tier", 1)) or 1
    infoRow(
        detailList.Content.RectTransform,
        "Tier",
        "Tier " .. numberText(tier),
        submarineTierColor(tier)
    )
    infoRow(
        detailList.Content.RectTransform,
        "Price",
        numberText(safeField(info, "Price", 0)) .. " mk",
        COLOR.GREEN
    )

    local minimumCrew = numberText(safeField(info, "RecommendedCrewSizeMin", 1))
    local maximumCrew = numberText(safeField(info, "RecommendedCrewSizeMax", 1))
    infoRow(
        detailList.Content.RectTransform,
        "Recommended crew",
        minimumCrew .. "–" .. maximumCrew,
        COLOR.CREAM
    )
    infoRow(
        detailList.Content.RectTransform,
        "Crew experience",
        prettyIdentifier(safeField(info, "RecommendedCrewExperience", "Unknown"))
    )
    infoRow(
        detailList.Content.RectTransform,
        "Cargo capacity",
        numberText(safeField(info, "CargoCapacity", 0))
    )

    local dimensions = safeField(info, "Dimensions", nil)
    if dimensions ~= nil then
        local width = numberText(safeField(dimensions, "X", safeField(dimensions, "Width", 0)))
        local height = numberText(safeField(dimensions, "Y", safeField(dimensions, "Height", 0)))
        infoRow(detailList.Content.RectTransform, "Dimensions", width .. " × " .. height)
    end

    local wiki = submarineWikiData[id(safeField(info, "Name", entry.identifier))]
    if wiki ~= nil then
        infoRow(
            detailList.Content.RectTransform,
            "Horizontal speed",
            numberText(wiki.horizontalSpeed) .. " km/h at 50 Helm",
            COLOR.CYAN
        )
        infoRow(
            detailList.Content.RectTransform,
            "Descent speed",
            numberText(wiki.descentSpeed) .. " km/h",
            COLOR.CYAN
        )
    else
        infoRow(
            detailList.Content.RectTransform,
            "Speed",
            "Not published for this custom submarine",
            COLOR.MUTED
        )
    end

    local weapons, gunCount = loadedSubmarineWeapons(info)
    if isEmpty(weapons) and wiki ~= nil then
        weapons = wiki.weapons or {}
        gunCount = wikiWeaponCount(weapons)
    end
    heading(detailList.Content.RectTransform, "\nStarting armament")
    infoRow(detailList.Content.RectTransform, "Installed guns", numberText(gunCount), COLOR.RED)
    if hasEntries(weapons) then
        for _, weapon in ipairs(weapons) do
            coloredLine(detailList.Content.RectTransform, "•  " .. weapon, COLOR.CREAM)
        end
    else
        coloredLine(detailList.Content.RectTransform, "No installed guns detected.", COLOR.MUTED)
    end
    if wiki ~= nil then
        if (wiki.hardpoints or 0) > 0 then
            coloredLine(
                detailList.Content.RectTransform,
                "•  " .. numberText(wiki.hardpoints) .. " open turret hardpoint(s)",
                COLOR.GOLD
            )
        end
        if (wiki.largeHardpoints or 0) > 0 then
            coloredLine(
                detailList.Content.RectTransform,
                "•  " .. numberText(wiki.largeHardpoints) .. " open large hardpoint(s)",
                COLOR.GOLD
            )
        end
        for _, feature in ipairs(wiki.other or {}) do
            coloredLine(detailList.Content.RectTransform, "•  " .. feature, COLOR.TEXT)
        end
    end

    heading(detailList.Content.RectTransform, "\nOperational notes")
    line(
        detailList.Content.RectTransform,
        "Scout vessels favor mobility and exploration, Attack vessels emphasize weapon coverage, and Transport vessels trade agility for cargo and crew capacity. Inspect the vessel before departure: weapon hardpoints, fabrication facilities and emergency equipment vary by design."
    )
    line(
        detailList.Content.RectTransform,
        "\nSOURCE  Loaded submarine file  •  General guidance: Official Barotrauma Wiki"
    )
end

local function afflictionIcon(prefab)
    local icon = safeField(prefab, "Icon", nil)
    if icon ~= nil then
        return icon
    end
    local afflictionType = id(safeField(prefab, "AfflictionType", safeField(prefab, "Type", "")))
    for candidate in AfflictionPrefab.Prefabs do
        local candidateType =
            id(safeField(candidate, "AfflictionType", safeField(candidate, "Type", "")))
        local candidateIcon = safeField(candidate, "Icon", nil)
        if afflictionType ~= "" and candidateType == afflictionType and candidateIcon ~= nil then
            return candidateIcon
        end
    end
    for _, fallbackIdentifier in ipairs({ "stun", "psychosis", "oxygenlow" }) do
        for candidate in AfflictionPrefab.Prefabs do
            if id(candidate.Identifier) == fallbackIdentifier then
                local fallbackIcon = safeField(candidate, "Icon", nil)
                if fallbackIcon ~= nil then
                    return fallbackIcon
                end
            end
        end
    end
    return nil
end

local function talentTile(parent, identifier, tileSize, focusedIdentifier)
    local talent = findTalent(identifier)
    local tile = GUI.Frame(
        GUI.RectTransform(tileSize or UI_VECTOR.TALENT_TILE, parent, Anchor.CenterLeft),
        "TalentBackground"
    )
    if talent ~= nil and talent.Icon ~= nil then
        local image = GUI.Image(
            GUI.RectTransform(UI_VECTOR.TALENT_ICON, tile.RectTransform, Anchor.Center),
            talent.Icon,
            true
        )
        image.CanBeFocused = false
    else
        label(tile.RectTransform, "?", Alignment.Center, palette.cyan)
    end
    local name = talent and text(talent.DisplayName) or prettyIdentifier(identifier)
    local description = talent and cleanDisplayText(talent.Description)
        or "No description is exposed by this talent prefab."
    tile.ToolTip = name .. "\n\n" .. description
    if id(identifier) == id(focusedIdentifier) then
        tile.Color = COLOR.GOLD
        tile.ToolTip = "CRAFTING REQUIREMENT\n\n" .. tile.ToolTip
    end
    return tile
end

local function centeredTalentTiles(layout, identifiers, tileSize, tileWidth, focusedIdentifier)
    local spacerWidth = math.max(0, (1 - #identifiers * tileWidth) / 2)
    if spacerWidth > 0 then
        GUI.Frame(GUI.RectTransform(relativeVector(spacerWidth, 1), layout), nil)
    end
    for _, identifier in ipairs(identifiers) do
        talentTile(layout, identifier, tileSize, focusedIdentifier)
    end
    if spacerWidth > 0 then
        GUI.Frame(GUI.RectTransform(relativeVector(spacerWidth, 1), layout), nil)
    end
end

local function showProfession(entry, focusSkill)
    clear(detailList)
    local p = entry.prefab
    local header = GUI.Frame(
        GUI.RectTransform(
            UI_VECTOR.PROFESSION_HEADER,
            detailList.Content.RectTransform,
            Anchor.TopCenter
        ),
        "InnerFrame"
    )
    header.Color = COLOR.PANEL_ALTERNATE
    local jobIcon = safeField(p, "Icon", safeField(p, "IconSmall", nil))
    if jobIcon ~= nil then
        local image = GUI.Image(
            GUI.RectTransform(UI_VECTOR.PROFESSION_ICON, header.RectTransform, Anchor.CenterLeft),
            jobIcon,
            true
        )
        image.RectTransform.RelativeOffset = UI_VECTOR.OFFSET_STANDARD
        image.CanBeFocused = false
    end
    local title = GUI.TextBlock(
        GUI.RectTransform(UI_VECTOR.PROFESSION_TITLE, header.RectTransform, Anchor.TopRight),
        string.upper(entry.name),
        COLOR.CREAM,
        GUI.Style.SubHeadingFont,
        Alignment.CenterLeft,
        false,
        ""
    )
    title.CanBeFocused = false
    local description = text(safeField(p, "Description", ""))
    local summary = GUI.TextBlock(
        GUI.RectTransform(UI_VECTOR.PROFESSION_SUMMARY, header.RectTransform, Anchor.BottomRight),
        description ~= "" and description or "Read-only profession reference and talent tree.",
        COLOR.TEXT,
        GUI.Style.SmallFont,
        Alignment.TopLeft,
        true,
        ""
    )
    summary.CanBeFocused = false
    local guide = roleGuides[entry.identifier]
    if guide ~= nil then
        heading(detailList.Content.RectTransform, "\nField guide")
        coloredLine(detailList.Content.RectTransform, "CORE RESPONSIBILITIES", COLOR.GOLD)
        for _, responsibility in ipairs(guide.responsibilities or {}) do
            coloredLine(detailList.Content.RectTransform, "•  " .. responsibility, COLOR.CREAM)
        end
        coloredLine(detailList.Content.RectTransform, "\nPRACTICAL TIPS", COLOR.CYAN)
        for _, tip in ipairs(guide.tips or {}) do
            coloredLine(detailList.Content.RectTransform, "◆  " .. tip, COLOR.TEXT)
        end
        local sourceLine = coloredLine(
            detailList.Content.RectTransform,
            "\nSOURCE  Official Barotrauma Wiki  •  Advice summarized for in-game use",
            COLOR.MUTED
        )
        sourceLine.ToolTip = guide.source or "Official Barotrauma Wiki"
    end
    heading(detailList.Content.RectTransform, "\nStarting skills")
    local skillsXml = string.match(entry.jobXml or "", "<[Ss]kills[^>]*>(.-)</[Ss]kills>") or ""
    local skillCount = 0
    for skillTag in string.gmatch(skillsXml, "<[Ss]kill%s+([^>/]-)/?>") do
        local identifier = xmlAttribute(skillTag, "identifier", "")
        local range = xmlAttribute(skillTag, "level", "0")
        if identifier ~= "" then
            skillCount = skillCount + 1
            if id(identifier) == id(focusSkill) then
                requirementRow(
                    detailList.Content.RectTransform,
                    string.upper(prettyIdentifier(identifier))
                        .. "  •  "
                        .. range
                        .. " starting skill",
                    fallbackSkillIcon(identifier),
                    "Crafting requirement points to this profession skill."
                )
            else
                iconInfoRow(
                    detailList.Content.RectTransform,
                    fallbackSkillIcon(identifier),
                    prettyIdentifier(identifier),
                    range .. " starting skill",
                    palette.cream
                )
            end
        end
    end
    if skillCount == 0 then
        line(
            detailList.Content.RectTransform,
            "No starting-skill definition was found for this loaded profession."
        )
    end
    heading(detailList.Content.RectTransform, "\nTalent tree")
    line(
        detailList.Content.RectTransform,
        "REFERENCE ONLY  •  Hover a talent icon to read its name and effect."
    )
    local treeXml = entry.treeXml or ""
    if treeXml == "" then
        line(
            detailList.Content.RectTransform,
            "This loaded profession does not expose a talent tree."
        )
        return
    end
    local paths, maximumStages = {}, 0
    for subtreeTag, subtreeBody in
        string.gmatch(treeXml, "<[Ss]ub[Tt]ree([^>]*)>(.-)</[Ss]ub[Tt]ree>")
    do
        local path = {
            name = prettyIdentifier(xmlAttribute(subtreeTag, "identifier", "Talent path")),
            pathType = id(xmlAttribute(subtreeTag, "type", "specialization")),
            stages = {},
        }
        for stageBody in
            string.gmatch(subtreeBody, "<[Tt]alent[Oo]ptions[^>]*>(.-)</[Tt]alent[Oo]ptions>")
        do
            local stage = {}
            local showcaseTag = string.match(stageBody, "<[Ss]how[Cc]ase[Tt]alent%s+([^>]*)>")
            if showcaseTag ~= nil then
                local showcaseIdentifier = xmlAttribute(showcaseTag, "identifier", "")
                if showcaseIdentifier ~= "" then
                    stage[#stage + 1] = showcaseIdentifier
                end
            else
                for optionTag in string.gmatch(stageBody, "<[Tt]alent[Oo]ption%s+([^>/]-)/?>") do
                    local identifier = xmlAttribute(optionTag, "identifier", "")
                    if identifier ~= "" then
                        stage[#stage + 1] = identifier
                    end
                end
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
                local primaryFrame = GUI.Frame(
                    GUI.RectTransform(
                        UI_VECTOR.TALENT_PRIMARY_ROW,
                        detailList.Content.RectTransform,
                        Anchor.TopCenter
                    ),
                    "InnerFrame"
                )
                primaryFrame.Color = COLOR.TALENT_ROW
                local primaryOptions = GUI.LayoutGroup(
                    GUI.RectTransform(
                        UI_VECTOR.TALENT_PATH_OPTIONS,
                        primaryFrame.RectTransform,
                        Anchor.Center
                    ),
                    true,
                    Anchor.CenterLeft
                )
                centeredTalentTiles(
                    primaryOptions.RectTransform,
                    stage,
                    UI_VECTOR.TALENT_PRIMARY_TILE,
                    TALENT_PRIMARY_TILE_WIDTH,
                    focusSkill
                )
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
    local tree = GUI.Frame(
        GUI.RectTransform(
            relativeVector(1, treeHeight),
            detailList.Content.RectTransform,
            Anchor.TopCenter
        ),
        "InnerFrame"
    )
    local columnAnchors = { Anchor.TopLeft, Anchor.TopCenter, Anchor.TopRight }
    for pathIndex, path in ipairs(specializations) do
        if pathIndex <= #columnAnchors then
            local column = GUI.LayoutGroup(
                GUI.RectTransform(
                    UI_VECTOR.TALENT_COLUMN,
                    tree.RectTransform,
                    columnAnchors[pathIndex]
                ),
                false,
                Anchor.TopCenter
            )
            local columnRowHeight = 1 / (#path.stages + 1)
            local pathHeader = GUI.Button(
                GUI.RectTransform(relativeVector(1, columnRowHeight), column.RectTransform),
                string.upper(path.name),
                Alignment.Center,
                "GUIButtonSmall"
            )
            pathHeader.Enabled = false
            for _, stage in ipairs(path.stages) do
                local stageFrame = GUI.Frame(
                    GUI.RectTransform(relativeVector(1, columnRowHeight), column.RectTransform),
                    "InnerFrame"
                )
                stageFrame.Color = COLOR.TALENT_ROW
                local options = GUI.LayoutGroup(
                    GUI.RectTransform(
                        UI_VECTOR.TALENT_PATH_OPTIONS,
                        stageFrame.RectTransform,
                        Anchor.Center
                    ),
                    true,
                    Anchor.CenterLeft
                )
                centeredTalentTiles(
                    options.RectTransform,
                    stage,
                    UI_VECTOR.TALENT_TILE,
                    TALENT_TILE_WIDTH,
                    focusSkill
                )
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
                if
                    suitableIdentifier == target
                    or (typeTarget ~= "" and suitableType == typeTarget)
                then
                    suitability = math.max(suitability, element.GetAttributeFloat("suitability", 0))
                end
            elseif name == "reduceaffliction" and isMedical then
                local identifier = id(element.GetAttributeString("identifier", ""))
                local afflictionType = id(element.GetAttributeString("type", ""))
                if identifier == target or (typeTarget ~= "" and afflictionType == typeTarget) then
                    local amount = element.GetAttributeFloat(
                        "amount",
                        element.GetAttributeFloat("strength", 0)
                    )
                    treatmentStrength = math.max(treatmentStrength, math.abs(amount))
                end
            elseif name == "affliction" then
                local identifier = id(element.GetAttributeString("identifier", ""))
                if identifier == target then
                    local strength = element.GetAttributeFloat(
                        "strength",
                        element.GetAttributeFloat("amount", 0)
                    )
                    if strength < 0 then
                        treatmentStrength = treatmentStrength + math.abs(strength)
                    elseif strength > 0 then
                        causeStrength = causeStrength + strength
                    end
                end
            end
            for child in element.Elements() do
                walk(child)
            end
        end
        if entry.prefab.ConfigElement ~= nil then
            walk(entry.prefab.ConfigElement)
        end
        if treatmentStrength > 0 or suitability > 0 then
            treatments[#treatments + 1] =
                { entry = entry, strength = treatmentStrength, suitability = suitability }
        end
        if causeStrength > 0 then
            causes[#causes + 1] = { entry = entry, strength = causeStrength }
        end
    end
    for _, item in ipairs(items) do
        scanItem(item)
    end
    table.sort(treatments, function(a, b)
        if a.suitability ~= b.suitability then
            return a.suitability > b.suitability
        end
        if a.strength ~= b.strength then
            return a.strength > b.strength
        end
        return a.entry.name < b.entry.name
    end)
    table.sort(causes, function(a, b)
        return a.strength > b.strength
    end)
    return treatments, causes
end

local showAffliction
local function afflictionButton(parent, entry, suffix)
    local button = GUI.Button(
        GUI.RectTransform(UI_VECTOR.LINK_ROW, parent, Anchor.TopCenter),
        "",
        Alignment.CenterLeft,
        "ListBoxElement"
    )
    button.Color = COLOR.ROW
    local sprite = afflictionIcon(entry.prefab)
    if sprite ~= nil then
        local icon = GUI.Image(
            GUI.RectTransform(UI_VECTOR.LINK_ICON, button.RectTransform, Anchor.CenterLeft),
            sprite,
            true
        )
        icon.CanBeFocused = false
    end
    local caption = GUI.TextBlock(
        GUI.RectTransform(UI_VECTOR.LINK_TEXT, button.RectTransform, Anchor.CenterRight),
        entry.name .. (suffix or ""),
        COLOR.CREAM,
        GUI.Style.SmallFont,
        Alignment.CenterLeft,
        false,
        ""
    )
    caption.CanBeFocused = false
    button.OnClicked = function()
        navigateTo("Afflictions", entry)
        return true
    end
    return button
end

showAffliction = function(entry)
    clear(detailList)
    local p = entry.prefab
    local icon = afflictionIcon(p)
    local afflictionType = text(safeField(p, "AfflictionType", safeField(p, "Type", "Affliction")))
    iconInfoRow(
        detailList.Content.RectTransform,
        icon,
        entry.name,
        prettyIdentifier(afflictionType),
        palette.cyan
    )
    local description = cleanDisplayText(safeField(p, "Description", ""))
    heading(detailList.Content.RectTransform, "\nEffect")
    line(
        detailList.Content.RectTransform,
        description ~= "" and description
            or "No general description is supplied by the loaded content package."
    )
    local maxStrength = safeField(p, "MaxStrength", DEFAULT_AFFLICTION_STRENGTH)
    infoRow(detailList.Content.RectTransform, "Maximum strength", numberText(maxStrength))
    infoRow(
        detailList.Content.RectTransform,
        "Limb specific",
        safeField(p, "LimbSpecific", false) and "Yes" or "No"
    )
    heading(detailList.Content.RectTransform, "\nStat debuffs by strength")
    local effectCount = 0
    for _, effect in ipairs(E.each(safeField(p, "Effects", nil))) do
        effectCount = effectCount + 1
        local range = numberText(safeField(effect, "MinStrength", 0))
            .. "–"
            .. numberText(safeField(effect, "MaxStrength", maxStrength))
        local values = {}
        for _, field in ipairs({
            "MinVitalityDecrease",
            "MaxVitalityDecrease",
            "StrengthChange",
            "SpeedMultiplier",
            "SkillMultiplier",
            "Resistance",
        }) do
            local value = safeField(effect, field, nil)
            local numeric = tonumber(value)
            local multiplier = field == "SpeedMultiplier"
                or field == "SkillMultiplier"
                or field == "Resistance"
            if
                value ~= nil
                and (
                    (numeric == nil)
                    or (multiplier and numeric ~= 1)
                    or (not multiplier and numeric ~= 0)
                )
            then
                values[#values + 1] = prettyIdentifier(field) .. "  " .. numberText(value)
            end
        end
        infoRow(
            detailList.Content.RectTransform,
            "Strength " .. range,
            #values > 0 and table.concat(values, "  •  ")
                or "Behavior defined by this effect stage",
            palette.red
        )
    end
    if effectCount == 0 then
        line(
            detailList.Content.RectTransform,
            "No staged stat modifiers are exposed through LuaCs for this affliction."
        )
    end
    local treatments, causes = itemAfflictionLinks(entry.identifier, afflictionType)
    heading(detailList.Content.RectTransform, "\nTreatments")
    if #treatments == 0 then
        line(
            detailList.Content.RectTransform,
            "No loaded medical item is marked as a suitable treatment."
        )
    end
    for _, link in ipairs(treatments) do
        local details = link.strength > 0 and ("  •  reduces up to " .. numberText(link.strength))
            or ""
        if link.suitability > 0 then
            details = details .. "  •  suitability " .. numberText(link.suitability)
        end
        itemButton(detailList.Content.RectTransform, link.entry, details)
    end
    heading(detailList.Content.RectTransform, "\nCaused by")
    local relatedCauses = { bloodloss = { "bleeding" } }
    local relatedCount = 0
    for _, identifier in ipairs(relatedCauses[entry.identifier] or {}) do
        local related = afflictionByIdentifier[identifier]
        if related ~= nil then
            relatedCount = relatedCount + 1
            afflictionButton(detailList.Content.RectTransform, related, "  •  ongoing cause")
        end
    end
    if #causes == 0 and relatedCount == 0 then
        line(
            detailList.Content.RectTransform,
            "No direct cause is declared by loaded items or afflictions."
        )
    end
    for _, link in ipairs(causes) do
        itemButton(
            detailList.Content.RectTransform,
            link.entry,
            "  •  applies " .. numberText(link.strength)
        )
    end
end

local function updateHistoryButtons()
    if backButton ~= nil then
        backButton.Enabled = navigationPosition > 1
    end
    if forwardButton ~= nil then
        forwardButton.Enabled = navigationPosition < #navigationHistory
    end
end

local function recordNavigation(category, entry, focus)
    if isRestoringHistory then
        return
    end
    while #navigationHistory > navigationPosition do
        table.remove(navigationHistory)
    end
    append(navigationHistory, {
        category = category,
        entry = entry,
        focus = focus,
        search = currentSearch,
        itemFilter = itemCategoryFilter,
    })
    navigationPosition = #navigationHistory
    updateHistoryButtons()
end

local function restoreNavigation(position)
    local state = navigationHistory[position]
    if state == nil then
        return
    end
    navigationPosition = position
    currentSearch = state.search or ""
    itemCategoryFilter = state.itemFilter or "All"
    if searchBox ~= nil then
        searchBox.Text = currentSearch
    end
    if itemFilterLabel ~= nil then
        itemFilterLabel.Text = string.upper(itemCategoryFilter)
    end
    isRestoringHistory = true
    if state.entry ~= nil then
        navigateTo(state.category, state.entry, state.focus)
    else
        selectCategory(state.category)
    end
    isRestoringHistory = false
    updateHistoryButtons()
end

navigateTo = function(category, entry, focus)
    if entry == nil then
        return
    end
    recordNavigation(category, entry, focus)
    currentCategory = category
    if itemFilterControls ~= nil then
        itemFilterControls.Visible = category == "Items"
    end
    if detailHeaderLabel ~= nil then
        detailHeaderLabel.Text = string.upper(category) .. "  /  " .. string.upper(entry.name)
    end
    populateList()
    for tabCategory, button in pairs(tabButtons) do
        button.Selected = tabCategory == category
    end
    if category == "Bestiary" then
        showCreature(entry)
    elseif category == "Items" then
        showItem(entry)
    elseif category == "Submarines" then
        showSubmarine(entry)
    elseif category == "Professions" then
        showProfession(entry, focus)
    else
        showAffliction(entry)
    end
    resetScroll(detailList)
end

-- Navigation and window construction ----------------------------------------

populateList = function(forceSearch)
    if listBox == nil then
        return
    end
    if forceSearch ~= nil then
        currentSearch = forceSearch
        searchBox.Text = forceSearch
    end
    clear(listBox)
    local source = items
    if currentCategory == "Bestiary" then
        source = creatures
    elseif currentCategory == "Submarines" then
        source = submarines
    elseif currentCategory == "Professions" then
        source = professions
    elseif currentCategory == "Afflictions" then
        source = afflictions
    end
    local shown, limit = 0, tonumber(settings.pageSize) or DEFAULT_SETTINGS.pageSize
    for _, entry in ipairs(source) do
        local tags, category = "", ""
        if currentCategory == "Items" then
            tags = joined(entry.prefab.Tags)
            category = categoryText(entry.prefab.Category)
        elseif currentCategory == "Submarines" then
            category = prettyIdentifier(safeField(entry.prefab, "SubmarineClass", ""))
        elseif currentCategory == "Afflictions" then
            category =
                text(safeField(entry.prefab, "AfflictionType", safeField(entry.prefab, "Type", "")))
        end
        local searching = text(currentSearch) ~= ""
        local matchesItemFilter = currentCategory ~= "Items"
            or searching
            or itemCategoryFilter == "All"
            or itemFilterCategory(entry) == itemCategoryFilter
        if
            matchesItemFilter
            and (
                E.contains(entry.name, currentSearch)
                or E.contains(entry.identifier, currentSearch)
                or E.contains(tags, currentSearch)
                or E.contains(category, currentSearch)
            )
        then
            shown = shown + 1
            if shown <= limit then
                local entryLabel = entry.name
                if currentCategory == "Bestiary" then
                    entryLabel = entry.identifier == "jove" and entry.name .. " (Spoiler)"
                        or entry.name
                end
                local button = GUI.Button(
                    GUI.RectTransform(UI_VECTOR.INDEX_ROW, listBox.Content.RectTransform),
                    "",
                    Alignment.CenterLeft,
                    "ListBoxElement"
                )
                button.Color = COLOR.ROW
                if currentCategory == "Submarines" then
                    local tier = tonumber(safeField(entry.prefab, "Tier", 1)) or 1
                    local tierFrame = GUI.Frame(
                        GUI.RectTransform(
                            UI_VECTOR.INDEX_ICON,
                            button.RectTransform,
                            Anchor.CenterLeft
                        ),
                        "InnerFrame"
                    )
                    tierFrame.Color = COLOR.PANEL_ALTERNATE
                    label(
                        tierFrame.RectTransform,
                        "TIER\n" .. numberText(tier),
                        Alignment.Center,
                        submarineTierColor(tier)
                    )
                elseif currentCategory ~= "Bestiary" then
                    local sprite = nil
                    if currentCategory == "Items" then
                        sprite = entry.prefab.InventoryIcon or entry.prefab.Sprite
                    elseif currentCategory == "Professions" then
                        sprite = safeField(
                            entry.prefab,
                            "IconSmall",
                            safeField(entry.prefab, "Icon", nil)
                        )
                    elseif currentCategory == "Afflictions" then
                        sprite = afflictionIcon(entry.prefab)
                    end
                    if sprite ~= nil then
                        local icon = GUI.Image(
                            GUI.RectTransform(
                                UI_VECTOR.INDEX_ICON,
                                button.RectTransform,
                                Anchor.CenterLeft
                            ),
                            sprite,
                            true
                        )
                        if currentCategory == "Items" then
                            icon.Color = entry.prefab.InventoryIcon
                                    and entry.prefab.InventoryIconColor
                                or entry.prefab.SpriteColor
                        end
                        icon.CanBeFocused = false
                    end
                end
                local captionWidth = currentCategory == "Bestiary" and 0.96 or 0.83
                local caption = GUI.TextBlock(
                    GUI.RectTransform(
                        fullHeightVector(captionWidth),
                        button.RectTransform,
                        Anchor.CenterRight
                    ),
                    entryLabel,
                    currentCategory == "Bestiary" and entry.identifier == "jove" and COLOR.RED
                        or COLOR.CREAM,
                    GUI.Style.SmallFont,
                    Alignment.CenterLeft,
                    false,
                    ""
                )
                caption.CanBeFocused = false
                button.OnClicked = function()
                    navigateTo(currentCategory, entry)
                    return true
                end
            end
        end
    end
    if shown > limit then
        line(
            listBox.Content.RectTransform,
            "Refine search to view " .. text(shown - limit) .. " more entries."
        )
    end
    resetScroll(listBox)
end

selectCategory = function(name)
    currentCategory = name
    if not isRestoringHistory then
        currentSearch = ""
        if searchBox then
            searchBox.Text = ""
        end
    end
    recordNavigation(name, nil, nil)
    populateList()
    clear(detailList)
    if itemFilterControls ~= nil then
        itemFilterControls.Visible = name == "Items"
    end
    for category, button in pairs(tabButtons) do
        button.Selected = category == name
    end
    local presentation = CATEGORY_PRESENTATION[name]
    if detailHeaderLabel ~= nil then
        detailHeaderLabel.Text = "COLLECTION OVERVIEW  /  " .. string.upper(name)
    end
    heading(detailList.Content.RectTransform, presentation.title)
    line(detailList.Content.RectTransform, presentation.description)
    line(detailList.Content.RectTransform, "\nSelect a record from the index to begin.")
    resetScroll(detailList)
end

local function createWindow()
    local canvas = GUIStatic.Canvas
    local windowSize = UI_VECTOR.WINDOW
    backdrop = GUI.Frame(GUI.RectTransform(UI_VECTOR.FULL, canvas, Anchor.Center), "GUIFrame")
    backdrop.Color = COLOR.BACKDROP

    local windowRect = GUI.RectTransform(windowSize, backdrop.RectTransform, Anchor.Center)
    window = GUI.Frame(windowRect, "GUIFrameListBox")
    window.Color = COLOR.WINDOW
    local padded = GUI.Frame(
        GUI.RectTransform(UI_VECTOR.WINDOW_PADDING, window.RectTransform, Anchor.Center),
        nil
    )

    local header = GUI.Frame(
        GUI.RectTransform(UI_VECTOR.HEADER, padded.RectTransform, Anchor.TopCenter),
        "InnerFrame"
    )
    header.Color = COLOR.HEADER
    local headerAccent = GUI.Frame(
        GUI.RectTransform(UI_VECTOR.HEADER_ACCENT, header.RectTransform, Anchor.CenterLeft),
        "InnerFrame"
    )
    headerAccent.Color = COLOR.GOLD
    headerAccent.RectTransform.RelativeOffset = UI_VECTOR.OFFSET_HEADER_ACCENT
    local titleArea = GUI.Frame(
        GUI.RectTransform(UI_VECTOR.HEADER_TITLE_AREA, header.RectTransform, Anchor.TopLeft),
        nil
    )
    local title = GUI.TextBlock(
        GUI.RectTransform(UI_VECTOR.HEADER_TITLE, titleArea.RectTransform, Anchor.CenterLeft),
        "JUST ENOUGH BARO",
        COLOR.CREAM,
        GUI.Style.SubHeadingFont,
        Alignment.CenterLeft,
        false,
        ""
    )
    title.RectTransform.RelativeOffset = UI_VECTOR.OFFSET_TITLE
    title.CanBeFocused = false

    local headerControls = GUI.LayoutGroup(
        GUI.RectTransform(UI_VECTOR.HEADER_CONTROLS, header.RectTransform, Anchor.TopRight),
        true,
        Anchor.CenterRight
    )
    backButton = GUI.Button(
        GUI.RectTransform(UI_VECTOR.HISTORY_BUTTON, headerControls.RectTransform),
        "‹ BACK",
        Alignment.Center,
        "GUIButtonSmall"
    )
    backButton.ToolTip = "Return to the previous encyclopedia page"
    backButton.OnClicked = function()
        restoreNavigation(navigationPosition - 1)
        return true
    end
    forwardButton = GUI.Button(
        GUI.RectTransform(UI_VECTOR.HISTORY_BUTTON, headerControls.RectTransform),
        "NEXT ›",
        Alignment.Center,
        "GUIButtonSmall"
    )
    forwardButton.ToolTip = "Return to the next encyclopedia page"
    forwardButton.OnClicked = function()
        restoreNavigation(navigationPosition + 1)
        return true
    end
    updateHistoryButtons()
    local searchArea =
        GUI.Frame(GUI.RectTransform(UI_VECTOR.SEARCH_AREA, headerControls.RectTransform), nil)
    searchBox = GUI.TextBox(
        GUI.RectTransform(UI_VECTOR.SEARCH_BOX, searchArea.RectTransform, Anchor.Center),
        currentSearch
    )
    searchBox.ToolTip = "Search by name, identifier, category or tag"
    searchBox.OnTextChangedDelegate = function(_, newText)
        currentSearch = text(newText)
        populateList()
        return true
    end
    local close = GUI.Button(
        GUI.RectTransform(UI_VECTOR.HEADER_CLOSE, headerControls.RectTransform),
        "×",
        Alignment.Center,
        "GUICancelButton"
    )
    close.OnClicked = function()
        toggle()
        return true
    end

    local tabs = GUI.LayoutGroup(
        GUI.RectTransform(UI_VECTOR.TABS, padded.RectTransform, Anchor.TopCenter),
        true,
        Anchor.CenterLeft
    )
    tabs.RectTransform.RelativeOffset = UI_VECTOR.OFFSET_TABS
    tabButtons = {}
    for _, category in ipairs({ "Bestiary", "Items", "Submarines", "Professions", "Afflictions" }) do
        local button = GUI.Button(
            GUI.RectTransform(UI_VECTOR.TAB_BUTTON, tabs.RectTransform),
            CATEGORY_PRESENTATION[category].tab,
            Alignment.Center,
            "GUIButtonSmall"
        )
        button.OnClicked = function()
            selectCategory(category)
            return true
        end
        tabButtons[category] = button
    end
    local body =
        GUI.Frame(GUI.RectTransform(UI_VECTOR.BODY, padded.RectTransform, Anchor.BottomCenter), nil)
    local left = GUI.Frame(
        GUI.RectTransform(UI_VECTOR.INDEX_PANEL, body.RectTransform, Anchor.BottomLeft),
        "InnerFrame"
    )
    left.Color = COLOR.PANEL_ALTERNATE
    local right = GUI.Frame(
        GUI.RectTransform(UI_VECTOR.DETAIL_PANEL, body.RectTransform, Anchor.BottomRight),
        "InnerFrame"
    )
    right.Color = COLOR.PANEL
    local listHeader = GUI.Frame(
        GUI.RectTransform(UI_VECTOR.PANEL_HEADER, left.RectTransform, Anchor.TopCenter),
        nil
    )
    local listHeaderTitle = GUI.Frame(
        GUI.RectTransform(UI_VECTOR.LIST_HEADER_TITLE, listHeader.RectTransform, Anchor.CenterLeft),
        nil
    )
    label(listHeaderTitle.RectTransform, "RECORD INDEX", Alignment.CenterLeft, COLOR.GOLD)
    itemFilterControls = GUI.LayoutGroup(
        GUI.RectTransform(UI_VECTOR.FILTER_CONTROLS, listHeader.RectTransform, Anchor.CenterRight),
        true,
        Anchor.CenterRight
    )
    local previousFilter = GUI.Button(
        GUI.RectTransform(UI_VECTOR.FILTER_PREVIOUS, itemFilterControls.RectTransform),
        "‹",
        Alignment.Center,
        "GUIButtonSmall"
    )
    itemFilterLabel = GUI.Button(
        GUI.RectTransform(UI_VECTOR.FILTER_LABEL, itemFilterControls.RectTransform),
        "ALL",
        Alignment.Center,
        "GUIButtonSmall"
    )
    itemFilterLabel.Enabled = false
    local nextFilter = GUI.Button(
        GUI.RectTransform(UI_VECTOR.FILTER_NEXT, itemFilterControls.RectTransform),
        "›",
        Alignment.Center,
        "GUIButtonSmall"
    )
    local function cycleFilter(direction)
        local selectedIndex = 1
        for index, name in ipairs(itemFilterNames) do
            if name == itemCategoryFilter then
                selectedIndex = index
                break
            end
        end
        selectedIndex = ((selectedIndex - 1 + direction) % #itemFilterNames) + 1
        itemCategoryFilter = itemFilterNames[selectedIndex]
        itemFilterLabel.Text = string.upper(itemCategoryFilter)
        populateList()
    end
    previousFilter.OnClicked = function()
        cycleFilter(-1)
        return true
    end
    nextFilter.OnClicked = function()
        cycleFilter(1)
        return true
    end
    local detailHeader = GUI.Frame(
        GUI.RectTransform(UI_VECTOR.PANEL_HEADER, right.RectTransform, Anchor.TopCenter),
        nil
    )
    local detailHeaderTitle = GUI.Frame(
        GUI.RectTransform(
            UI_VECTOR.DETAIL_HEADER_TITLE,
            detailHeader.RectTransform,
            Anchor.CenterLeft
        ),
        nil
    )
    detailHeaderLabel =
        label(detailHeaderTitle.RectTransform, "SELECTED ENTRY", Alignment.CenterLeft, COLOR.GOLD)
    listBox = GUI.ListBox(
        GUI.RectTransform(UI_VECTOR.PANEL_LIST, left.RectTransform, Anchor.BottomCenter)
    )
    detailList = GUI.ListBox(
        GUI.RectTransform(UI_VECTOR.PANEL_LIST, right.RectTransform, Anchor.BottomCenter)
    )
    selectCategory("Bestiary")
end

toggle = function()
    visible = not visible
    if visible and window == nil then
        createWindow()
    end
    if backdrop ~= nil then
        backdrop.Visible = visible
    end
    if window ~= nil then
        window.Visible = visible
    end
    if not visible and imageOverlay ~= nil then
        imageOverlay.Visible = false
        imageOverlay = nil
    end
    print("[JEB] " .. (visible and "opened" or "closed"))
end

-- Context-sensitive opening and game hooks ----------------------------------

local function getFocusedEntry()
    local function entryFromPrefab(prefab)
        if prefab == nil or prefab.Identifier == nil then
            return nil
        end
        return itemByIdentifier[id(prefab.Identifier)]
    end
    local function prefabFromUserData(data)
        if data == nil then
            return nil
        end
        if LuaUserData.IsTargetType(data, "Barotrauma.Item") then
            return data.Prefab
        end
        if LuaUserData.IsTargetType(data, "Barotrauma.ItemPrefab") then
            return data
        end
        if LuaUserData.IsTargetType(data, "Barotrauma.FabricationRecipe") then
            return data.TargetItem
        end
        if LuaUserData.IsTargetType(data, "Barotrauma.PurchasedItem") then
            return data.ItemPrefab
        end
        return nil
    end

    local selectedSlot = InventoryStatic.SelectedSlot
    if selectedSlot ~= nil and selectedSlot.Item ~= nil then
        local entry = entryFromPrefab(selectedSlot.Item.Prefab)
        if entry ~= nil then
            return "Items", entry
        end
    end

    local hovered = GUIStatic.MouseOn
    local depth = 0
    while hovered ~= nil and depth < MAX_GUI_PARENT_DEPTH do
        local entry = entryFromPrefab(prefabFromUserData(hovered.UserData))
        if entry ~= nil then
            return "Items", entry
        end
        hovered = hovered.Parent
        depth = depth + 1
    end

    local controlled = Character.Controlled
    if controlled == nil then
        return nil, nil
    end
    local focusedItem = controlled.FocusedItem
    if focusedItem ~= nil and focusedItem.Prefab ~= nil then
        local entry = itemByIdentifier[id(focusedItem.Prefab.Identifier)]
        if entry ~= nil then
            return "Items", entry
        end
    end
    local focusedCharacter = controlled.FocusedCharacter
    if
        focusedCharacter == nil
        and controlled.SelectedCharacter ~= nil
        and controlled.SelectedCharacter.IsDead
    then
        focusedCharacter = controlled.SelectedCharacter
    end
    if
        focusedCharacter ~= nil
        and focusedCharacter.IsDead
        and focusedCharacter.SpeciesName ~= nil
    then
        local entry = creatureByIdentifier[id(focusedCharacter.SpeciesName)]
        if entry ~= nil then
            return "Bestiary", entry
        end
    end
    return nil, nil
end

local function openFocusedEntry()
    local category, entry = getFocusedEntry()
    if entry == nil then
        return false
    end
    visible = true
    if window == nil then
        createWindow()
    end
    backdrop.Visible = true
    window.Visible = true
    navigateTo(category, entry)
    print(
        "[JEB] opened focused "
            .. string.lower(category)
            .. " entry: "
            .. entry.name
    )
    return true
end

local function updateContextHint()
    local category, entry = getFocusedEntry()
    if visible or Game.GameSession == nil then
        if contextHint ~= nil then
            contextHint.Visible = false
        end
        return
    end
    if contextHint == nil then
        contextHint = GUI.Button(
            GUI.RectTransform(UI_VECTOR.CONTEXT_HINT, GUIStatic.Canvas, Anchor.BottomCenter),
            "",
            Alignment.Center,
            "GUIButtonSmall"
        )
        contextHint.Color = COLOR.HEADER
        contextHint.RectTransform.RelativeOffset = UI_VECTOR.OFFSET_CONTEXT_HINT
        contextHint.ToolTip = "Open Just Enough Baro"
        contextHint.OnClicked = function()
            if not openFocusedEntry() then
                toggle()
            end
            return true
        end
        contextHintText = GUI.TextBlock(
            GUI.RectTransform(UI_VECTOR.CONTEXT_HINT_TEXT, contextHint.RectTransform, Anchor.Center),
            "",
            COLOR.TEXT,
            GUI.Style.SmallFont,
            Alignment.Center,
            false,
            ""
        )
        contextHintText.CanBeFocused = false
    end
    if entry ~= nil then
        contextHintText.Text = "[" .. openKeyName .. "]  INSPECT  " .. string.upper(entry.name)
        contextHint.ToolTip = "Open the " .. entry.name .. " encyclopedia record"
    else
        contextHintText.Text = "[" .. openKeyName .. "]  ENCYCLOPEDIA"
        contextHint.ToolTip = "Open Just Enough Baro"
    end
    contextHint.Visible = true
    contextHint.AddToGUIUpdateList(false, GUI_ORDER.CONTEXT_HINT)
end

Hook.Add("think", "JustEnoughBaro.Input", function()
    updateContextHint()
    local typingInSearch = false
    if visible and searchBox ~= nil then
        pcall(function()
            typingInSearch = searchBox.Selected or searchBox.IsFocused
        end)
    end
    if PlayerInput.KeyHit(openKey) and not typingInSearch then
        if visible then
            toggle()
        elseif not openFocusedEntry() then
            toggle()
        end
    end
    if visible and PlayerInput.KeyHit(Keys.Escape) then
        toggle()
    end
    if visible and backdrop ~= nil then
        backdrop.AddToGUIUpdateList(false, GUI_ORDER.WINDOW)
    end
    if imageOverlay ~= nil then
        imageOverlay.AddToGUIUpdateList(false, GUI_ORDER.IMAGE_OVERLAY)
    end
end)

Game.AddCommand("encyclopedia", "Toggle Just Enough Baro", function()
    toggle()
end)

Game.AddCommand(
    "encyclopedia_corpse",
    "Single player: spawn a creature at the cursor and turn spawned monsters into corpses",
    function(args)
        if not Game.IsSingleplayer then
            print("[JEB] encyclopedia_corpse is a single-player test command.")
            return
        end
        local target = id(args and args[1] or "")
        if target == "" or findCharacterPrefab(target) == nil or target == "human" then
            print(
                "[JEB] Usage: encyclopedia_corpse <species identifier>  (example: encyclopedia_corpse mudraptor)"
            )
            return
        end
        print(
            "[JEB] Spawning "
                .. target
                .. "; all living monsters will be killed after spawning."
        )
        Game.ExecuteCommand("spawn " .. target .. " cursor")
        Timer.Wait(function()
            Game.ExecuteCommand("killmonsters")
        end, DELAY_MS.CORPSE_TEST)
    end
)

Hook.Add("stop", "JustEnoughBaro.Stop", function()
    if backdrop ~= nil then
        backdrop.Visible = false
    end
    if window ~= nil then
        window.Visible = false
    end
end)

Timer.Wait(function()
    buildDatabase()
end, DELAY_MS.DATABASE_BUILD)
