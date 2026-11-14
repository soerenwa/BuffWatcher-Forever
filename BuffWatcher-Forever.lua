-- BuffWatcher Forever: shows Well Fed, Camp Benefits, the Sleeping Bag buff and party
-- buffs at a glance (WoW Forever).
--
-- Forever uses the Midnight addon rules: aura data is "secret" (unreadable) in
-- combat. So buffs are only scanned while auras are readable; in combat the last
-- known state keeps running on its expiration time, and combat end rescans.

local ADDON = ...

local DEFAULTS = {
  locked   = false,
  horizontal = false, -- rows side by side instead of stacked
  point    = { "CENTER", "CENTER", 0, 200 },
  warn     = 5,     -- minutes: chat warning when a buff has less than this left
  sound    = true,  -- sound + chat message when a buff runs out
  autohide = false, -- hide the panel while everything is active with time to spare
  scale    = 1,
  theme    = "forever", -- "forever" (client look), "modern" or "classic"
  bagAtMax = false,     -- keep the Sleeping Bag row at max level too
}

-- All "Well Fed" IDs from the Forever spell data (build 70374), as a fallback
-- in case a name is localized.
local WELL_FED_IDS = {
  19705, 19706, 19708, 19709, 19710, 19711, 24799, 24870, 25694, 25941,
  1225778, 1225779, 1225780, 1225782, 1248406, 1248420, 1248421, 1248422,
  1248688, 1249519, 1249520, 1249521, 1249523, 1249907, 1249926, 1249927,
  1283082, 1294007, 1302064, 1319310,
}
local WELL_FED_ICON = 136000 -- Interface\Icons\Spell_Misc_Food

local function FormatTime(sec)
  sec = math.max(0, math.floor(sec))
  local floor = math.floor
  if sec >= 3600 then
    return string.format("%dh %02dm", floor(sec / 3600), floor((sec % 3600) / 60))
  elseif sec >= 600 then
    return string.format("%dm", floor(sec / 60))
  end
  return string.format("%d:%02d", floor(sec / 60), sec % 60)
end

local TRACKERS = {
  {
    key = "fed", label = "Food",
    names = { ["Well Fed"] = true },
    ids = {}, icons = { [WELL_FED_ICON] = true },
    defaultIcon = WELL_FED_ICON,
  },
  {
    key = "camp", label = "Campfire",
    campOverlap = true, -- stats a stronger class buff covers are shown in grey
    names = { ["Camp Benefits"] = true },
    ids = {}, icons = {},
    -- The 1-minute countdown at the campfire before Camp Benefits arrives.
    pendingNames = { ["Camping"] = true },
    defaultIcon = 135805, -- Interface\Icons\Spell_Fire_Fire
  },
  {
    -- Cozy Sleeping Bag: the buff lasts about 2 hours, the bag has a 1 hour
    -- cooldown. Under an hour left the bag can be used again, so the text turns
    -- orange then. Hidden at max level, where the XP bonus is useless.
    key = "bag", label = "Sleeping Bag",
    names = { ["Well-Rested"] = true, ["Well Rested"] = true },
    ids = {}, icons = {},
    defaultIcon = 133662, -- Interface\Icons\INV_Misc_Bag_BigBagOfEnchantments
    soonBelow = 3600,
    xpOnly = true,
    keepsPanelColor = true, -- never stops the panel from turning green
    value = function(s, now)
      -- Forever shows the bonus in the tooltip ("increased by 3%"), not as stacks.
      local text = s.value or string.format("%d%% XP", math.max(1, s.count or 1))
      if s.expires > 0 then text = text .. ", " .. FormatTime(s.expires - now) .. " left" end
      return text
    end,
  },
}
for _, id in ipairs(WELL_FED_IDS) do TRACKERS[1].ids[id] = true end

local function IsSecret(v)
  return issecretvalue ~= nil and issecretvalue(v) or false
end

-- Class buffs the party can provide. Only shown in a party, never in a raid.
local NO_MANA_CLASSES = { WARRIOR = true, ROGUE = true }
local MELEE_CLASSES   = { WARRIOR = true, ROGUE = true, PALADIN = true, SHAMAN = true }
local FERAL_FORMS     = { [1] = true, [5] = true, [8] = true } -- Cat, Bear, Dire Bear

local function Set(...)
  local set = {}
  for i = 1, select("#", ...) do set[select(i, ...)] = true end
  return set
end

local function UsefulForEveryone() return true end

local function UsesMana(class) return not NO_MANA_CLASSES[class] end

local function FightsInMelee(class)
  if MELEE_CLASSES[class] then return true end
  if class ~= "DRUID" then return false end
  local form = GetShapeshiftFormID and GetShapeshiftFormID()
  return form ~= nil and not IsSecret(form) and FERAL_FORMS[form] == true
end

local GROUP_BUFFS = {
  {
    key = "fort", short = "Fort", full = "Fortitude", class = "PRIEST", icon = 135987,
    names = Set("Power Word: Fortitude", "Prayer of Fortitude"), usefulFor = UsefulForEveryone,
  },
  {
    key = "mark", short = "Mark", full = "Mark of the Wild", class = "DRUID", icon = 136078,
    names = Set("Mark of the Wild", "Gift of the Wild"), usefulFor = UsefulForEveryone,
  },
  {
    key = "int", short = "Int", full = "Arcane Intellect", class = "MAGE", icon = 135932,
    names = Set("Arcane Intellect", "Arcane Brilliance"), usefulFor = UsesMana,
  },
  {
    key = "bless", short = "Blessing", full = "Paladin Blessings", class = "PALADIN", icon = 135906,
    perCaster = true, -- every paladin in the party brings one blessing
    names = Set("Blessing of Might", "Blessing of Wisdom", "Blessing of Kings",
      "Blessing of Salvation", "Blessing of Light", "Blessing of Sanctuary",
      "Greater Blessing of Might", "Greater Blessing of Wisdom", "Greater Blessing of Kings",
      "Greater Blessing of Salvation", "Greater Blessing of Light", "Greater Blessing of Sanctuary"),
    usefulFor = UsefulForEveryone,
  },
  {
    key = "shout", short = "Shout", full = "Battle Shout", class = "WARRIOR", icon = 132333,
    names = Set("Battle Shout"), usefulFor = FightsInMelee,
  },
}
local GROUP_ROW_ICON = 134149 -- Interface\Icons\INV_Misc_GroupNeedMore

-- Lying in the Sleeping Bag: every full minute of rest refreshes Well-Rested
-- (one more stack, up to 3). These aura or channel names mean "in the bag".
local SLEEP_NAMES = { ["Sleeping"] = true, ["Cozy Sleeping Bag"] = true, ["Sleeping Bag"] = true }
local SLEEP_CYCLE = 60
local SLEEP_ROW_HEIGHT = 20

-- Panel style, modelled on the dark guide panels of the Forever UI.
local WHITE       = "Interface\\Buttons\\WHITE8X8"
local PANEL_WIDTH = 150 -- minimum; grows when the stat text needs more room
local ROW_HEIGHT  = 38
local ICON_SIZE   = 26
local ICON_LEFT   = 11
local TEXT_GAP    = 9
local TEXT_RIGHT  = 12
local FONT_SIZE   = 13
local VALUE_FONT_SIZE = 11
local HEADER_HEIGHT = 24

local COLOR_PANEL          = { 0.075, 0.075, 0.14, 0.94 }
local COLOR_PANEL_COMPLETE = { 0.06, 0.24, 0.13, 0.94 } -- every buff is there
local COLOR_BORDER         = { 0.22, 0.22, 0.32, 1 }
local COLOR_HEADER         = { 0.11, 0.10, 0.20, 1 }
local COLOR_MUTED          = { 0.55, 0.55, 0.62 }
local COLOR_SEPARATOR      = { 1, 1, 1, 0.06 }
local COLOR_ROW            = { 1, 1, 1, 0.03 }
local COLOR_BAR            = { 0.56, 0.42, 0.98, 1 }
local COLOR_PRESENT        = { 1, 1, 1 }
local COLOR_MISSING        = { 1, 0.25, 0.25 }
local COLOR_SOON           = { 1, 0.6, 0.15 }

-- Window styles. Text colours (white / red / orange) stay the same in both;
-- a style only changes the chrome. The COLOR_* tables above are filled in
-- place from the active style, so everything that reads them follows along.
local THEMES = {
  -- The look of the Forever client's own unit frames: near-black panels, thin
  -- bronze frames, gold-orange names, amber accents and a blue mana-style bar.
  forever = {
    backdrop = { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 },
    inset = 1,
    panel = { 0.07, 0.06, 0.05, 0.92 }, complete = { 0.06, 0.2, 0.08, 0.92 },
    border = { 0.62, 0.47, 0.22, 1 }, header = { 0.13, 0.10, 0.06, 1 }, headerLine = { 0.62, 0.47, 0.22, 1 },
    separator = { 0.62, 0.47, 0.22, 0.25 }, row = { 1, 0.8, 0.5, 0.03 }, accent = { 0.93, 0.6, 0.18, 1 },
    title = { 0.95, 0.72, 0.3 }, titleText = "BuffWatcher",
    showMark = true, showBar = true,
    barTexture = "Interface\\TargetingFrame\\UI-StatusBar", barColor = { 0.15, 0.42, 0.95, 1 },
    font = nil,
  },
  -- Flat dark panels with purple accents.
  modern = {
    backdrop = { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 },
    inset = 1,
    panel = { 0.075, 0.075, 0.14, 0.94 }, complete = { 0.06, 0.24, 0.13, 0.94 },
    border = { 0.22, 0.22, 0.32, 1 }, header = { 0.11, 0.10, 0.20, 1 }, headerLine = { 0.22, 0.22, 0.32, 1 },
    separator = { 1, 1, 1, 0.06 }, row = { 1, 1, 1, 0.03 }, accent = { 0.56, 0.42, 0.98, 1 },
    title = { 1, 1, 1 }, titleText = "Buff|cff8f6bfaWatch|r",
    showMark = true, showBar = true, barTexture = WHITE, font = nil, -- nil = the game's font
  },
  classic = {
    backdrop = {
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 14,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    },
    inset = 4,
    panel = { 0.04, 0.04, 0.05, 0.9 }, complete = { 0.04, 0.22, 0.06, 0.9 },
    border = { 0.8, 0.8, 0.8, 1 }, header = { 0, 0, 0, 0 }, headerLine = { 1, 0.82, 0, 0.35 },
    separator = { 1, 0.82, 0, 0.15 }, row = { 0, 0, 0, 0 }, accent = { 1, 0.82, 0, 1 },
    title = { 1, 0.82, 0 }, titleText = "BuffWatcher",
    showMark = false, showBar = false,
    barTexture = "Interface\\TargetingFrame\\UI-StatusBar", font = "Fonts\\FRIZQT__.TTF",
  },
}

local function CopyInto(dst, src)
  for i = 1, 4 do dst[i] = src[i] end
end


local db

local function Theme()
  return THEMES[db and db.theme] or THEMES.forever
end

local function Inset()
  return Theme().inset
end

-- Every font string goes through ThemeFont, so a style switch can change the font.
local themedFonts = {}
local function ThemeFont(fontString, size)
  themedFonts[#themedFonts + 1] = { fs = fontString, size = size, default = (fontString:GetFont()) }
  fontString:SetFont(Theme().font or (fontString:GetFont()), size, "")
end
local state = {}        -- key -> { active, expires, icon, name, pendingExpires, pendingDuration, warned }
local groupPresent = {} -- group buff key -> list of expiration times (0 = permanent)
local sleep = { active = false, cycleStart = 0, expires = 0, duration = 0, lastRefresh = nil,
  restStart = nil, wasResting = nil }
local scannedBefore = false
local sleepRow
local campRow -- countdown bar under the Campfire row until Camp Benefits arrives
local timerRows = {} -- sleepRow and campRow
local headerButtons = {}
local options -- options menu, created on first use
local UpdateHeaderButtons -- defined with the header buttons
local ApplyTheme -- defined after all windows
local rows = {}
local frame

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff8f6bfaBuffWatcher|r: " .. msg)
end

local function AurasSecret()
  if C_Secrets and C_Secrets.ShouldAurasBeSecret then
    local ok, secret = pcall(C_Secrets.ShouldAurasBeSecret)
    if ok and secret then return true end
  end
  return false
end

local function CopyDefaults(src, dst)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = {} end
      CopyDefaults(v, dst[k])
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
end


-- Stat words in buff tooltips and their short form. On a tie the earlier entry
-- wins, so the longer phrases come first.
local STATS = {
  { "experience", "XP" },
  { "mana regeneration", "MP5" }, { "mana per", "MP5" }, { "mana every", "MP5" },
  { "health regeneration", "HP5" }, { "health per", "HP5" }, { "health every", "HP5" },
  { "attack power", "AP" }, { "spell power", "SP" }, { "spell damage", "SP" },
  { "healing", "Heal" }, { "all stats", "All" }, { "all primary attributes", "All" },
  { "all attributes", "All" }, { "resistances?", "Res" }, { "strength", "Str" },
  { "agility", "Agi" }, { "stamina", "Sta" }, { "intellect", "Int" }, { "spirit", "Spi" },
  { "armor", "Armor" }, { "critical", "Crit" }, { "health", "HP" }, { "mana", "Mana" },
}

local NOT_AN_AMOUNT = {}
for _, unit in ipairs({ "sec", "secs", "second", "seconds", "min", "mins", "minute",
  "minutes", "hr", "hour", "hours", "yd", "yds", "yard", "yards" }) do
  NOT_AN_AMOUNT[unit] = true
end

-- Next number or stat word from pos on: kind, startPos, endPos, statLabel.
local function NextToken(text, pos)
  local numStart, numEnd = text:find("%d+%.?%d*%%?", pos)
  local statStart, statEnd, label
  for _, stat in ipairs(STATS) do
    local s, e = text:find("%f[%a]" .. stat[1] .. "%f[%A]", pos)
    if s and (not statStart or s < statStart) then
      statStart, statEnd, label = s, e, stat[2]
    end
  end
  if statStart and (not numStart or statStart < numStart) then
    return "stat", statStart, statEnd, label
  elseif numStart then
    return "number", numStart, numEnd
  end
end

-- Turns tooltip text into a list of stat parts like { key = "Sta", text = "10 Sta" }.
-- Handles both word orders: "Strength is increased by 25 and Stamina by 10" and
-- "gain 25 Strength". Returns nil when the text holds no stat amount.
local function ParseStatParts(text)
  if not text then return nil end
  text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|n", "\n"):lower()

  local order, totals = {}, {}
  local function Add(label, token)
    local num, percent = token:match("^([%d%.]+)(%%?)$")
    local key = label .. percent
    if not totals[key] then
      totals[key] = { label = label, percent = percent, value = 0 }
      order[#order + 1] = key
    end
    totals[key].value = totals[key].value + tonumber(num)
  end

  for sentence in (text:gsub("%.%s+", "\n")):gmatch("[^\n]+") do
    local pending, pos = {}, 1
    while true do
      local kind, s, e, label = NextToken(sentence, pos)
      if not kind then break end
      pos = e + 1
      if kind == "stat" then
        pending[#pending + 1] = label
      else
        local token = sentence:sub(s, e)
        local nextWord = sentence:sub(e + 1):match("^%s*(%a+)")
        if not NOT_AN_AMOUNT[nextWord or ""] then
          if #pending > 0 then
            for _, stat in ipairs(pending) do Add(stat, token) end
            pending = {}
          else
            local nextKind, nextStart, nextEnd, nextLabel = NextToken(sentence, pos)
            if nextKind == "stat" and sentence:sub(pos, nextStart - 1):match("^%s*$") then
              Add(nextLabel, token)
              pos = nextEnd + 1
            end
          end
        end
      end
    end
  end

  if #order == 0 then return nil end
  local parts = {}
  for i, key in ipairs(order) do
    local t = totals[key]
    parts[i] = { key = key, text = string.format("%g%s %s", t.value, t.percent, t.label) }
  end
  return parts
end

local function JoinParts(parts)
  if not parts then return nil end
  local texts = {}
  for i, part in ipairs(parts) do texts[i] = part.text end
  return table.concat(texts, ", ")
end

-- "25 Str, 10 Sta", or nil when the text holds no stat amount.
local function ParseStats(text)
  return JoinParts(ParseStatParts(text))
end

-- Camp objects don't stack with the matching class buff, and the class buff is
-- always the stronger one. So a campfire stat counts for nothing while you have
-- one of these buffs (keys as ParseStatParts makes them: label plus "%" if any).
local CAMP_OVERRIDES = {
  ["Sta"]   = { "Power Word: Fortitude", "Prayer of Fortitude" },              -- First Aid Kit
  ["All"]   = { "Mark of the Wild", "Gift of the Wild" },                      -- Enchanted Lute
  ["Armor"] = { "Mark of the Wild", "Gift of the Wild" },
  ["Res"]   = { "Mark of the Wild", "Gift of the Wild" },
  ["All%"]  = { "Blessing of Kings", "Greater Blessing of Kings" },            -- Fish Bowl
  ["AP"]    = { "Blessing of Might", "Greater Blessing of Might" },            -- Lodestone
  ["MP5"]   = { "Blessing of Wisdom", "Greater Blessing of Wisdom" },          -- Mana Well
  ["Int"]   = { "Arcane Intellect", "Arcane Brilliance" },                     -- Incense Candle
  ["Spi"]   = { "Divine Spirit", "Prayer of Spirit" },                         -- Faction Banner
  ["Str"]   = { "Strength of Earth" },                                         -- Sharpening Wheel
  ["Crit%"] = { "Leader of the Pack", "Moonkin Aura" },                        -- Camp Chair
}
local GREY = "|cff808080"

local playerBuffNames = {} -- names of your buffs at the last readable scan

-- The class buff that makes this campfire stat useless, or nil.
local function CampOverride(key)
  for _, name in ipairs(CAMP_OVERRIDES[key] or {}) do
    if playerBuffNames[name] then return name end
  end
end

-- Campfire stats with the ones a class buff already covers in grey.
local function FormatCampParts(parts)
  if not parts then return nil end
  local texts = {}
  for i, part in ipairs(parts) do
    texts[i] = CampOverride(part.key) and (GREY .. part.text .. "|r") or part.text
  end
  return table.concat(texts, ", ")
end

-- The buff's tooltip text without its title line, or nil if it can't be read.
local function ReadBuffText(index)
  if not (C_TooltipInfo and C_TooltipInfo.GetUnitAura) then return nil end
  local ok, data = pcall(C_TooltipInfo.GetUnitAura, "player", index, "HELPFUL")
  if not ok or not data or IsSecret(data) or IsSecret(data.lines) or not data.lines then
    return nil
  end
  local out = {}
  for i = 2, #data.lines do
    local text = data.lines[i].leftText
    if text and not IsSecret(text) and text ~= "" then out[#out + 1] = text end
  end
  return table.concat(out, "\n")
end

-- Calls cb(name, icon, expirationTime, duration, spellId, index, count) for every
-- buff (or debuff with filter "HARMFUL").
-- Returns false if a value was secret (the scan is unusable then).
local function ForEachBuff(cb, filter)
  filter = filter or "HELPFUL"
  if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
    for i = 1, 255 do
      local a = C_UnitAuras.GetAuraDataByIndex("player", i, filter)
      if not a then break end
      if IsSecret(a) or IsSecret(a.name) or IsSecret(a.spellId)
        or IsSecret(a.expirationTime) or IsSecret(a.icon) then
        return false
      end
      cb(a.name, a.icon, a.expirationTime, a.duration, a.spellId, i, a.applications)
    end
    return true
  elseif UnitBuff then
    local get = filter == "HARMFUL" and UnitDebuff or UnitBuff
    for i = 1, 40 do
      local name, icon, count, _, duration, expirationTime, _, _, _, spellId = get("player", i)
      if not name then break end
      if IsSecret(name) or IsSecret(spellId) or IsSecret(expirationTime) then
        return false
      end
      cb(name, icon, expirationTime, duration, spellId, i, count)
    end
    return true
  end
  return false
end

local function Matches(t, name, icon, spellId)
  if name and t.names[name] then return true end
  if spellId and t.ids[spellId] then return true end
  if icon and t.icons[icon] then return true end
  return false
end

local function IsSleepName(name)
  return name ~= nil and SLEEP_NAMES[name] == true
end

-- Seconds until the next Well-Rested refresh while lying in the bag, and the
-- length of one cycle; nil when not in the bag. Prefers a real timer (a channel
-- or an aura with a short duration), otherwise counts minutes since lying down
-- or since the last refresh.
-- Lying in the bag puts you in the resting state (zZz). Remember when it began;
-- the state at login does not count, so being in a city at login shows no bar.
local function UpdateResting(now)
  local resting = IsResting and IsResting()
  if IsSecret(resting) then return end
  resting = resting and true or false
  if sleep.wasResting == nil then
    sleep.wasResting = resting
    return
  end
  if resting and not sleep.wasResting then sleep.restStart = now end
  if not resting then sleep.restStart = nil end
  sleep.wasResting = resting
end

local function SleepRemaining(now)
  if UnitChannelInfo then
    local name, _, _, startMS, endMS = UnitChannelInfo("player")
    if name and not IsSecret(name) and not IsSecret(endMS) and not IsSecret(startMS)
      and (IsSleepName(name) or name:lower():find("sleep")) and endMS > startMS then
      return math.max(0, endMS / 1000 - now), (endMS - startMS) / 1000
    end
  end
  if not sleep.active then
    -- Forever marks lying in the bag only with the resting state, which inns
    -- and cities set too. The minute counts from lying down or from the last
    -- Well-Rested refresh; with no refresh for over a minute it was not the
    -- bag (or the bonus is maxed), so the bar goes away.
    if not sleep.restStart then return nil end
    local since = now - math.max(sleep.restStart, sleep.lastRefresh or 0)
    if since >= SLEEP_CYCLE + 10 then return nil end
    return math.max(0, SLEEP_CYCLE - since), SLEEP_CYCLE
  end
  if sleep.duration > 0 and sleep.duration <= 120 and sleep.expires > now then
    return sleep.expires - now, sleep.duration
  end
  local elapsed = (now - sleep.cycleStart) % SLEEP_CYCLE
  return SLEEP_CYCLE - elapsed, SLEEP_CYCLE
end

-- Seconds until Camp Benefits arrives while sitting at the campfire, and the
-- length of the countdown; nil when no countdown runs.
local function CampPendingRemaining(now)
  local s = state.camp
  if not (s and s.pendingExpires and s.pendingExpires > now) then return nil end
  local total = (s.pendingDuration and s.pendingDuration > 0) and s.pendingDuration or 60
  return s.pendingExpires - now, total
end

---------------------------------------------------------------------------
-- Scanning
---------------------------------------------------------------------------

local Refresh -- forward

local function OnExpired(t)
  if db.sound then
    Print("|cffff4040" .. t.label .. " has run out!|r")
    if SOUNDKIT and SOUNDKIT.RAID_WARNING then
      PlaySound(SOUNDKIT.RAID_WARNING, "Master")
    end
  end
end

local function Scan()
  if AurasSecret() then return end

  local found, pending, present = {}, {}, {}
  local names = {}
  local sleepAura
  local function NoteSleep(name, expirationTime, duration)
    if not sleepAura and IsSleepName(name) then
      sleepAura = { expires = expirationTime or 0, duration = duration or 0 }
    end
  end
  -- The short countdown aura before a buff arrives (sitting at the campfire).
  -- Matched by name, or for the campfire by any short aura with "camp" in it.
  local function NotePending(t, name, expirationTime, duration)
    if not (t.pendingNames and name and duration and duration > 0 and duration <= 120
      and expirationTime and expirationTime > 0) then return end
    if t.pendingNames[name] or (t.key == "camp" and name:lower():find("camp")) then
      pending[t.key] = { expires = expirationTime, duration = duration }
    end
  end
  local ok = ForEachBuff(function(name, icon, expirationTime, duration, spellId, index, count)
    if name then names[name] = true end
    NoteSleep(name, expirationTime, duration)
    for _, b in ipairs(GROUP_BUFFS) do
      if name and b.names[name] then
        present[b.key] = present[b.key] or {}
        table.insert(present[b.key], (expirationTime and expirationTime > 0) and expirationTime or 0)
      end
    end
    for _, t in ipairs(TRACKERS) do
      if Matches(t, name, icon, spellId) then
        local exp = (expirationTime and expirationTime > 0) and expirationTime or 0
        local cur = found[t.key]
        -- With several matches keep the longest running one (0 = permanent).
        if not cur or exp == 0 or (cur.expires ~= 0 and exp > cur.expires) then
          found[t.key] = { expires = exp, icon = icon, name = name, index = index,
            count = (not IsSecret(count)) and count or nil }
        end
      else
        NotePending(t, name, expirationTime, duration)
      end
    end
  end)
  if not ok then return end -- secret, keep the old state
  ForEachBuff(function(name, icon, expirationTime, duration, spellId)
    NoteSleep(name, expirationTime, duration)
    for _, t in ipairs(TRACKERS) do
      if not Matches(t, name, icon, spellId) then NotePending(t, name, expirationTime, duration) end
    end
  end, "HARMFUL")

  local now = GetTime()
  local wasSleeping = sleep.active
  sleep.active = sleepAura ~= nil
  if sleepAura then
    sleep.expires, sleep.duration = sleepAura.expires, sleepAura.duration
    if not wasSleeping then sleep.cycleStart = now end
  end

  groupPresent = present
  playerBuffNames = names
  for _, t in ipairs(TRACKERS) do
    local s = state[t.key]
    local f = found[t.key]
    if f then
      local parts = ParseStatParts(ReadBuffText(f.index))
      local value = JoinParts(parts)
      -- A new stack, a higher bonus or a fresh duration means the bag just
      -- refreshed Well-Rested: the next minute starts now. Not on the first scan
      -- after login, where every buff "appears".
      if t.key == "bag" and scannedBefore and (not s.active
        or (f.count or 1) > (s.count or 1) or (value ~= nil and value ~= s.value)
        or f.expires > s.expires + 30) then
        sleep.lastRefresh = now
        if sleep.active then sleep.cycleStart = now end
      end
      if not s.active or f.expires ~= s.expires then s.warned = false end
      s.active, s.expires, s.icon, s.name, s.count = true, f.expires, f.icon, f.name, f.count
      s.value, s.parts = value, parts
    else
      if s.active then OnExpired(t) end
      s.active, s.expires, s.name, s.value, s.parts = false, 0, nil, nil, nil
    end
    local p = pending[t.key]
    s.pendingExpires, s.pendingDuration = p and p.expires, p and p.duration
  end
  scannedBefore = true
  Refresh()
end

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------

local function SavePosition()
  local p, _, rp, x, y = frame:GetPoint(1)
  db.point = { p, rp, x, y }
end

local function ApplyPosition()
  frame:ClearAllPoints()
  local p = db.point
  frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

local rowOrder = {} -- rows top to bottom; hidden ones are skipped by Layout

local function CreateRow(t)
  local row = CreateFrame("Frame", nil, frame)
  row.rowHeight, row.hasLine = ROW_HEIGHT, true
  row:SetHeight(ROW_HEIGHT)

  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  row.bg:SetColorTexture(unpack(COLOR_ROW))

  row.bar = row:CreateTexture(nil, "ARTWORK")
  row.bar:SetPoint("TOPLEFT")
  row.bar:SetPoint("BOTTOMLEFT")
  row.bar:SetWidth(3)
  row.bar:SetColorTexture(unpack(COLOR_BAR))

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(ICON_SIZE, ICON_SIZE)
  row.icon:SetPoint("LEFT", row, "LEFT", ICON_LEFT, 0)
  row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  ThemeFont(row.label, FONT_SIZE)
  row.label:SetShadowOffset(1, -1)
  row.label:SetText(t.label)

  row.value = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  ThemeFont(row.value, VALUE_FONT_SIZE)
  row.value:SetShadowOffset(1, -1)
  row.value:SetPoint("TOPLEFT", row.icon, "RIGHT", TEXT_GAP, -1)

  row.line = row:CreateTexture(nil, "BORDER")
  row.line:SetPoint("TOPLEFT")
  row.line:SetPoint("TOPRIGHT")
  row.line:SetHeight(1)
  row.line:SetColorTexture(unpack(COLOR_SEPARATOR))
  row.vline = row:CreateTexture(nil, "BORDER") -- used in horizontal mode
  row.vline:SetPoint("TOPLEFT")
  row.vline:SetPoint("BOTTOMLEFT")
  row.vline:SetWidth(1)
  row.vline:SetColorTexture(unpack(COLOR_SEPARATOR))
  row.vline:Hide()

  rowOrder[#rowOrder + 1] = row
  return row
end

-- Thin countdown bar right under a row: under the Sleeping Bag while lying in
-- it, under the Campfire while sitting at the fire until Camp Benefits arrives.
-- remaining(now) returns seconds left and the full length, or nil.
local function CreateTimerRow(below, remaining, label)
  local row = CreateFrame("Frame", nil, frame)
  row.rowHeight, row.hasLine = SLEEP_ROW_HEIGHT, false
  row.below, row.remaining = below, remaining
  timerRows[#timerRows + 1] = row
  row:SetHeight(SLEEP_ROW_HEIGHT)

  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  row.bg:SetColorTexture(unpack(COLOR_ROW))

  row.bar = CreateFrame("StatusBar", nil, row)
  row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", ICON_LEFT, -2)
  row.bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -TEXT_RIGHT, 6)
  row.bar:SetStatusBarTexture(WHITE)
  row.bar:SetStatusBarColor(unpack(COLOR_BAR))
  row.bar:SetMinMaxValues(0, 1)

  row.track = row.bar:CreateTexture(nil, "BACKGROUND")
  row.track:SetAllPoints()
  row.track:SetColorTexture(1, 1, 1, 0.08)

  row.text = row.bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  ThemeFont(row.text, 10)
  row.text:SetShadowOffset(1, -1)
  row.text:SetTextColor(unpack(COLOR_PRESENT))
  row.text:SetPoint("CENTER")

  row:SetScript("OnUpdate", function(self)
    local left, total = self.remaining(GetTime())
    if left then
      self.bar:SetValue(left / total)
      self.text:SetText(label .. FormatTime(left))
    end
  end)

  for i, r in ipairs(rowOrder) do
    if r == below then table.insert(rowOrder, i + 1, row) return row end
  end
  rowOrder[#rowOrder + 1] = row
  return row
end

local function RowWidth(row)
  local w = row.label:GetStringWidth()
  if row.value:IsShown() then w = math.max(w, row.value:GetStringWidth()) end
  return math.ceil(ICON_LEFT + ICON_SIZE + TEXT_GAP + w + TEXT_RIGHT)
end

-- Room for the title and the header buttons.
local function HeaderMinWidth()
  if not frame.header then return PANEL_WIDTH end
  local buttons = 0
  for _, b in ipairs(headerButtons) do buttons = buttons + b.buttonWidth + 2 end
  return math.ceil(2 * Inset() + 23 + frame.header.title:GetStringWidth() + 12 + buttons + 4)
end

local function SetPanelSize(width, height)
  if width ~= frame.fittedWidth then
    frame.fittedWidth = width
    frame:SetWidth(width)
  end
  frame:SetHeight(height)
end

-- Places the visible rows under the header: stacked (vertical) or side by side
-- (horizontal, the sleep bar then hangs under the Sleeping Bag cell), and sizes
-- the panel to fit.
local function Layout()
  local inset = Inset()
  local edge = 2 * inset
  local top = -inset - HEADER_HEIGHT
  local minWidth = math.max(PANEL_WIDTH, HeaderMinWidth())
  local visible = {}
  for _, row in ipairs(rowOrder) do
    if row:IsShown() and not row.below then visible[#visible + 1] = row end
  end

  if db.horizontal then
    local x, cells = 0, {}
    for i, row in ipairs(visible) do
      local w = RowWidth(row)
      if i == #visible then w = math.max(w, minWidth - edge - x) end -- last cell fills up
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", frame, "TOPLEFT", inset + x, top)
      row:SetWidth(w)
      row.line:Hide()
      if i > 1 then row.vline:Show() else row.vline:Hide() end
      cells[row] = { x = x, w = w }
      x = x + w
    end
    local height = ROW_HEIGHT
    for _, timer in ipairs(timerRows) do
      local cell = cells[timer.below]
      if timer:IsShown() and cell then
        timer:ClearAllPoints()
        timer:SetPoint("TOPLEFT", frame, "TOPLEFT", inset + cell.x, top - ROW_HEIGHT)
        timer:SetWidth(cell.w)
        height = ROW_HEIGHT + SLEEP_ROW_HEIGHT
      end
    end
    SetPanelSize(math.max(minWidth, edge + x), edge + HEADER_HEIGHT + height)
    return
  end

  local total, widest = 0, 0
  for _, row in ipairs(rowOrder) do
    if row:IsShown() then
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, top - total)
      row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -inset, top - total)
      if row.hasLine then
        if total == 0 then row.line:Hide() else row.line:Show() end
        row.vline:Hide()
        widest = math.max(widest, RowWidth(row))
      end
      total = total + row.rowHeight
    end
  end
  SetPanelSize(math.max(minWidth, edge + widest), edge + HEADER_HEIGHT + (total > 0 and total or ROW_HEIGHT))
end

local function AtMaxLevel(unit)
  local level = UnitLevel(unit or "player")
  local max = GetMaxPlayerLevel and GetMaxPlayerLevel() or 60
  if IsSecret(level) or IsSecret(max) then return false end
  return level >= max
end

-- XP-only rows (Sleeping Bag) are hidden at max level unless the option keeps them.
local function HiddenAtMax(t, unit)
  return t.xpOnly and not db.bagAtMax and AtMaxLevel(unit)
end

local function TrackerVisible(t)
  return not HiddenAtMax(t, "player")
end

local function ApplyLook(row, color, iconTexture, value)
  row.label:SetTextColor(unpack(color))
  row.icon:SetTexture(iconTexture)

  -- Name centred on its own, or name above the stat amounts.
  row.label:ClearAllPoints()
  if value then
    row.label:SetPoint("BOTTOMLEFT", row.icon, "RIGHT", TEXT_GAP, 1)
    row.value:SetText(value)
    row.value:SetTextColor(unpack(color))
    row.value:Show()
  else
    row.label:SetPoint("LEFT", row.icon, "RIGHT", TEXT_GAP, 0)
    row.value:SetText("")
    row.value:Hide()
  end
end


-- Class -> number of connected party members including you; nil unless in a party.
local function PartyClassCounts()
  if not IsInGroup() or IsInRaid() then return nil end
  local counts = {}
  local function Add(unit)
    local _, class = UnitClass(unit)
    if class and not IsSecret(class) then counts[class] = (counts[class] or 0) + 1 end
  end
  Add("player")
  for i = 1, GetNumSubgroupMembers() do
    local unit = "party" .. i
    local connected = UnitIsConnected(unit)
    if IsSecret(connected) or connected then Add(unit) end
  end
  return counts
end

-- The party buffs that matter for you: list of { buff, have, want }, or nil if
-- you are not in a party or nobody in it can provide anything useful.
local function PartyBuffStatus()
  local counts = PartyClassCounts()
  if not counts then return nil end
  local _, myClass = UnitClass("player")
  local now = GetTime()
  local items = {}
  for _, b in ipairs(GROUP_BUFFS) do
    local casters = counts[b.class] or 0
    if casters > 0 and b.usefulFor(myClass) then
      local have = 0
      for _, expires in ipairs(groupPresent[b.key] or {}) do
        if expires == 0 or expires > now then have = have + 1 end
      end
      local want = b.perCaster and casters or 1
      items[#items + 1] = { buff = b, have = math.min(have, want), want = want }
    end
  end
  if #items == 0 then return nil end
  return items
end

-- Shows or hides the party row. Returns false only if a party buff is missing.
local function UpdatePartyRow()
  local row, items = rows.party, PartyBuffStatus()
  if not items then
    row:Hide()
    return true
  end
  row:Show()

  local missing = {}
  for _, item in ipairs(items) do
    if item.have < item.want then
      missing[#missing + 1] = item.want > 1
        and string.format("%s %d/%d", item.buff.short, item.have, item.want)
        or item.buff.short
    end
  end

  if #missing > 0 then
    ApplyLook(row, COLOR_MISSING, GROUP_ROW_ICON, "Missing: " .. table.concat(missing, ", "))
    return false
  end
  ApplyLook(row, COLOR_PRESENT, GROUP_ROW_ICON, string.format("All %d active", #items))
  return true
end

-- Text for the hover tooltip; the panel itself only shows icon and name.
local function StatusLine(s)
  local now = GetTime()
  if s.active then
    if s.expires == 0 then return "active" end
    return FormatTime(s.expires - now) .. " left"
  elseif s.pendingExpires and s.pendingExpires > now then
    return "arrives in " .. FormatTime(s.pendingExpires - now)
  end
  return "missing"
end

local function CreateMainFrame()
  frame = CreateFrame("Frame", "BuffWatcherForeverFrame", UIParent, "BackdropTemplate")
  frame:SetSize(PANEL_WIDTH, 2 + #TRACKERS * ROW_HEIGHT)
  frame:SetFrameStrata("MEDIUM")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self)
    if not db.locked then self:StartMoving() end
  end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SavePosition()
  end)
  if frame.SetBackdrop then
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    frame:SetBackdropColor(unpack(COLOR_PANEL))
    frame:SetBackdropBorderColor(unpack(COLOR_BORDER))
  end
  frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("BuffWatcher Forever")
    for _, t in ipairs(TRACKERS) do
      GameTooltip:AddDoubleLine(t.label, StatusLine(state[t.key]), 1, 1, 1, 1, 1, 1)
    end
    for _, item in ipairs(PartyBuffStatus() or {}) do
      local status = item.have >= item.want and "active"
        or item.want > 1 and (item.have .. "/" .. item.want)
        or "missing"
      GameTooltip:AddDoubleLine(item.buff.full, status, 1, 1, 1, 1, 1, 1)
    end
    local camp = state.camp
    if camp and camp.active and camp.parts then
      for _, part in ipairs(camp.parts) do
        local by = CampOverride(part.key)
        if by then
          GameTooltip:AddLine("Campfire " .. part.text .. " has no effect: " .. by .. " is stronger", 0.6, 0.6, 0.6)
        end
      end
    end
    GameTooltip:AddLine(db.locked and "Locked" or "Drag to move", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function() GameTooltip:Hide() end)

  for _, t in ipairs(TRACKERS) do rows[t.key] = CreateRow(t) end
  rows.party = CreateRow({ label = "Party Buffs" })
  sleepRow = CreateTimerRow(rows.bag, SleepRemaining, "Refresh in ")
  campRow = CreateTimerRow(rows.camp, CampPendingRemaining, "Buff in ")

  -- Header bar: a small accent mark and the title on the left, buttons on the right.
  local header = CreateFrame("Frame", nil, frame)
  header:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
  header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
  header:SetHeight(HEADER_HEIGHT)
  header.bg = header:CreateTexture(nil, "BACKGROUND")
  header.bg:SetAllPoints()
  header.bg:SetColorTexture(unpack(COLOR_HEADER))
  header.line = header:CreateTexture(nil, "BORDER")
  header.line:SetPoint("BOTTOMLEFT")
  header.line:SetPoint("BOTTOMRIGHT")
  header.line:SetHeight(1)
  header.line:SetColorTexture(unpack(COLOR_BORDER))
  header.mark = header:CreateTexture(nil, "ARTWORK")
  header.mark:SetSize(6, 6)
  header.mark:SetPoint("LEFT", header, "LEFT", 10, 0)
  header.mark:SetColorTexture(unpack(COLOR_BAR))
  header.title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  ThemeFont(header.title, 12)
  header.title:SetShadowOffset(1, -1)
  header.title:SetPoint("LEFT", header.mark, "RIGHT", 7, 0)
  header.title:SetTextColor(unpack(COLOR_PRESENT))
  header.title:SetText("Buff|cff8f6bfaWatch|r")
  frame.header = header

  frame:SetScale(db.scale)
  frame.appliedScale = db.scale
  ApplyPosition()
end

function Refresh()
  if not frame then return end
  local now = GetTime()
  local allGood = true    -- everything active with time to spare (autohide)
  local allPresent = true -- everything active at all (green panel)
  local warnSec = db.warn * 60

  for _, t in ipairs(TRACKERS) do
    local s, row = state[t.key], rows[t.key]

    -- No scanning in combat; detect expired buffs by the clock.
    if s.active and s.expires > 0 and s.expires <= now then
      s.active = false
      OnExpired(t)
    end

    if not TrackerVisible(t) then
      row:Hide()
    elseif s.active then
      row:Show()
      local soon = t.soonBelow and s.expires > 0 and s.expires - now < t.soonBelow
      ApplyLook(row, soon and COLOR_SOON or COLOR_PRESENT, s.icon or t.defaultIcon,
        t.value and t.value(s, now) or (t.campOverlap and FormatCampParts(s.parts)) or s.value)
      if soon then allGood = false end
      if s.expires > 0 then
        local left = s.expires - now
        if left < warnSec then
          allGood = false
          if not s.warned and db.sound and left > 1 then
            s.warned = true
            Print("|cffffd200" .. t.label .. " expires in " .. FormatTime(left) .. ".|r")
          end
        end
      end
    else
      row:Show()
      allGood = false
      if not t.keepsPanelColor then allPresent = false end
      ApplyLook(row, COLOR_MISSING, t.defaultIcon)
    end
  end

  UpdateResting(now)
  if rows.bag:IsShown() and SleepRemaining(now) then sleepRow:Show() else sleepRow:Hide() end
  if rows.camp:IsShown() and CampPendingRemaining(now) then campRow:Show() else campRow:Hide() end
  if not UpdatePartyRow() then allGood, allPresent = false, false end
  frame:SetBackdropColor(unpack(allPresent and COLOR_PANEL_COMPLETE or COLOR_PANEL))
  Layout()
  if UpdateHeaderButtons then UpdateHeaderButtons() end
  if db.autohide and allGood then frame:Hide() else frame:Show() end
end

---------------------------------------------------------------------------
-- Party grid: who in the party has which buff
---------------------------------------------------------------------------

local GRID_NAME_WIDTH = 92
local GRID_CELL       = 24
local GRID_ROW_HEIGHT = 22
local GRID_TOP        = 30 -- title area
local GRID_HEADER     = 24 -- column icons
local READY_TEXTURE     = "Interface\\RaidFrame\\ReadyCheck-Ready"
local NOT_READY_TEXTURE = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local grid

-- Header buttons are small drawn glyphs: muted, white on hover, accent colour
-- while their thing is on (grid open, panel locked).
UpdateHeaderButtons = function()
  for _, b in ipairs(headerButtons) do
    if b.redraw then b.redraw(b) end
    local active = b.isActive and b.isActive() or false
    local color = active and COLOR_BAR or (b.hover and COLOR_PRESENT or COLOR_MUTED)
    for _, part in ipairs(b.parts) do part:SetColorTexture(unpack(color)) end
    if b.prominent then
      if active then
        b.bg:SetColorTexture(COLOR_BAR[1], COLOR_BAR[2], COLOR_BAR[3], 0.25)
      else
        b.bg:SetColorTexture(1, 1, 1, b.hover and 0.16 or 0.08)
      end
      b:SetBackdropBorderColor(unpack((active or b.hover) and COLOR_BAR or COLOR_BORDER))
    else
      b.bg:SetColorTexture(1, 1, 1, (active or b.hover) and 0.08 or 0)
    end
  end
  if options and options:IsShown() then
    for _, checkbox in ipairs(options.checkboxes) do checkbox:update() end
  end
end

-- Puts a glyph part at x, y (its top-left corner, relative to the button centre).
local function Place(b, part, w, h, x, y)
  part:ClearAllPoints()
  part:SetSize(w, h)
  part:SetPoint("TOPLEFT", b, "CENTER", x, y)
end

local function AddPart(b, w, h, x, y)
  local part = b:CreateTexture(nil, "ARTWORK")
  Place(b, part, w, h, x, y)
  b.parts[#b.parts + 1] = part
  return part
end

-- Buttons line up from the right edge of the header to the left.
local function CreateHeaderButton(name, tooltip, onClick, prominent)
  local b = CreateFrame("Button", name, frame.header, prominent and "BackdropTemplate" or nil)
  b.buttonWidth = prominent and 26 or 20
  b:SetSize(b.buttonWidth, prominent and 20 or 18)
  local previous = headerButtons[#headerButtons]
  if previous then
    b:SetPoint("RIGHT", previous, "LEFT", prominent and -4 or -2, 0)
  else
    b:SetPoint("RIGHT", frame.header, "RIGHT", -3, 0)
  end
  b.prominent = prominent or false
  if prominent then
    b:SetBackdrop({ edgeFile = WHITE, edgeSize = 1 })
  end
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  if prominent then
    b.bg:SetPoint("TOPLEFT", 1, -1)
    b.bg:SetPoint("BOTTOMRIGHT", -1, 1)
  else
    b.bg:SetAllPoints()
  end
  b.parts = {}
  b.hover, b.isActive, b.redraw = false, false, false
  b:SetScript("OnClick", function()
    onClick()
    UpdateHeaderButtons()
  end)
  b:SetScript("OnEnter", function(self)
    self.hover = true
    UpdateHeaderButtons()
    local title, hint = tooltip()
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(title)
    if hint then GameTooltip:AddLine(hint, 0.7, 0.7, 0.7) end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function(self)
    self.hover = false
    UpdateHeaderButtons()
    GameTooltip:Hide()
  end)
  headerButtons[#headerButtons + 1] = b
  return b
end

-- You plus your party members (never a raid).
local function GridUnits()
  local units = { "player" }
  if IsInGroup() and not IsInRaid() then
    for i = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. i end
  end
  return units
end

-- Food and Campfire for everyone, plus every class buff someone in the party can cast.
local function GridColumns(counts)
  local columns = {}
  for _, t in ipairs(TRACKERS) do
    columns[#columns + 1] = { key = t.key, label = t.label, icon = t.defaultIcon, tracker = t }
  end
  for _, b in ipairs(GROUP_BUFFS) do
    if (counts[b.class] or 0) > 0 then
      columns[#columns + 1] = { key = b.key, label = b.full, icon = b.icon, buff = b }
    end
  end
  return columns
end

-- A unit's buffs, or nil while they can't be read (combat, out of range).
local function UnitBuffList(unit)
  if AurasSecret() or not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
  local list = {}
  for i = 1, 255 do
    local a = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
    if not a then break end
    if IsSecret(a) or IsSecret(a.name) or IsSecret(a.spellId) or IsSecret(a.icon) then return nil end
    list[#list + 1] = a
  end
  return list
end

-- Does this party member benefit from the buff? Same rules as for you; other
-- druids count as melee while their power bar is rage or energy (bear, cat).
local function UnitWantsBuff(unit, b)
  local _, class = UnitClass(unit)
  if not class or IsSecret(class) then return true end
  if unit == "player" or b.usefulFor ~= FightsInMelee then return b.usefulFor(class) end
  if MELEE_CLASSES[class] then return true end
  if class ~= "DRUID" then return false end
  local power = UnitPowerType(unit)
  return not IsSecret(power) and (power == 1 or power == 3)
end

-- "yes", "no", "partial" (with text like "1/2"), "na" or "unknown".
local LOW_FRACTION = 0.2 -- under 20% of its duration left: orange check

local function AuraInfo(a)
  local expires = (a.expirationTime and a.expirationTime > 0) and a.expirationTime or 0
  return { name = a.name, expires = expires, duration = a.duration or 0 }
end

local function ExpiresAt(a)
  return (a.expirationTime and a.expirationTime > 0) and a.expirationTime or math.huge
end

-- "low" when the buff is in its last 20%; permanent buffs never are.
local function Present(a)
  local info = AuraInfo(a)
  if info.expires > 0 and info.duration > 0
    and info.expires - GetTime() < info.duration * LOW_FRACTION then
    return "low", nil, info
  end
  return "yes", nil, info
end

-- state ("yes", "low", "no", "partial", "na", "unknown"), short text, and
-- details of the matching buff (for blessings the one that runs out first).
local function CellState(unit, column, buffs, counts)
  if column.buff and not UnitWantsBuff(unit, column.buff) then return "na", "-" end
  if column.tracker and HiddenAtMax(column.tracker, unit) then return "na", "-" end
  if not buffs then return "unknown", "?" end
  if column.tracker then
    for _, a in ipairs(buffs) do
      if Matches(column.tracker, a.name, a.icon, a.spellId) then return Present(a) end
    end
    return "no"
  end
  local b, have, first = column.buff, 0, nil
  for _, a in ipairs(buffs) do
    if b.names[a.name] then
      have = have + 1
      if not first or ExpiresAt(a) < ExpiresAt(first) then first = a end
    end
  end
  local want = b.perCaster and (counts[b.class] or 1) or 1
  if have >= want then return Present(first) end
  if have > 0 then return "partial", have .. "/" .. want, AuraInfo(first) end
  return "no"
end

-- Tooltip line for a cell, worked out when the mouse is over it.
local function CellStatusText(cell)
  local info, state = cell.info, cell.state
  if state == "yes" or state == "low" or state == "partial" then
    local text
    if info.expires == 0 then
      text = "Active, no time limit"
    else
      text = FormatTime(info.expires - GetTime()) .. " left"
      if info.duration > 0 then text = text .. " of " .. FormatTime(info.duration) end
    end
    if state == "partial" then text = cell.detail .. " active, first ends: " .. text end
    return text, state == "yes" and { 0.3, 1, 0.3 } or COLOR_SOON
  elseif state == "no" then
    return "Missing", COLOR_MISSING
  elseif state == "na" then
    return "Not needed", COLOR_MUTED
  end
  return "Can't be read right now (combat or out of range)", COLOR_MUTED
end

local function GridFont(fontString, size)
  ThemeFont(fontString, size)
  fontString:SetShadowOffset(1, -1)
end

local function CreateGridHeader(index)
  local h = CreateFrame("Frame", nil, grid)
  h:SetSize(18, 18)
  h.icon = h:CreateTexture(nil, "ARTWORK")
  h.icon:SetAllPoints()
  h.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  h:EnableMouse(true)
  h:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(self.label or "")
    GameTooltip:Show()
  end)
  h:SetScript("OnLeave", function() GameTooltip:Hide() end)
  grid.headers[index] = h
  return h
end

local function CreateGridRow(index)
  local row = CreateFrame("Frame", nil, grid)
  row:SetHeight(GRID_ROW_HEIGHT)
  row:SetPoint("TOPLEFT", grid, "TOPLEFT", Inset(), -(GRID_TOP + GRID_HEADER + (index - 1) * GRID_ROW_HEIGHT))
  row:SetPoint("TOPRIGHT", grid, "TOPRIGHT", -Inset(), -(GRID_TOP + GRID_HEADER + (index - 1) * GRID_ROW_HEIGHT))
  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  row.bg:SetColorTexture(1, 1, 1, index % 2 == 1 and 0.03 or 0)
  row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  GridFont(row.name, 12)
  row.name:SetPoint("LEFT", row, "LEFT", 9, 0)
  row.name:SetWidth(GRID_NAME_WIDTH - 4)
  row.name:SetJustifyH("LEFT")
  row.cells = {}
  grid.rows[index] = row
  return row
end

local function CreateGridCell(row, index)
  local cell = CreateFrame("Frame", nil, row)
  cell:SetSize(GRID_CELL, GRID_ROW_HEIGHT)
  cell:SetPoint("LEFT", row, "LEFT", 9 + GRID_NAME_WIDTH + (index - 1) * GRID_CELL, 0)
  cell.icon = cell:CreateTexture(nil, "ARTWORK")
  cell.icon:SetSize(14, 14)
  cell.icon:SetPoint("CENTER")
  cell.label = cell:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  GridFont(cell.label, 10)
  cell.label:SetPoint("CENTER")
  cell:EnableMouse(true)
  cell:SetScript("OnEnter", function(self)
    local text, color = CellStatusText(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self.columnLabel or "")
    GameTooltip:AddLine(self.unitName or "", 1, 1, 1)
    if self.info and self.info.name and self.info.name ~= self.columnLabel then
      GameTooltip:AddLine(self.info.name, 0.8, 0.8, 0.8)
    end
    GameTooltip:AddLine(text, color[1], color[2], color[3])
    GameTooltip:Show()
  end)
  cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
  row.cells[index] = cell
  return cell
end

local function SetCell(cell, state, text, info)
  cell.state, cell.detail, cell.info = state, text, info or false
  if state == "yes" or state == "low" or state == "no" then
    cell.icon:SetTexture(state == "no" and NOT_READY_TEXTURE or READY_TEXTURE)
    -- Orange check: the green one, greyed out and tinted.
    cell.icon:SetDesaturated(state == "low")
    if state == "low" then
      cell.icon:SetVertexColor(unpack(COLOR_SOON))
    else
      cell.icon:SetVertexColor(1, 1, 1)
    end
    cell.icon:Show()
    cell.label:SetText("")
  else
    cell.icon:Hide()
    cell.label:SetText(text or "")
    cell.label:SetTextColor(unpack(state == "partial" and COLOR_SOON or COLOR_MUTED))
  end
end

local function UpdateGrid()
  if not grid then return end
  local _, myClass = UnitClass("player")
  local counts = PartyClassCounts() or { [myClass or "?"] = 1 }
  local columns, units = GridColumns(counts), GridUnits()
  grid.columns = columns

  for j, column in ipairs(columns) do
    local h = grid.headers[j] or CreateGridHeader(j)
    h.icon:SetTexture(column.icon)
    h.label = column.label
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", grid, "TOPLEFT", 10 + GRID_NAME_WIDTH + (j - 1) * GRID_CELL + (GRID_CELL - 18) / 2, -GRID_TOP)
    h:Show()
  end
  for j = #columns + 1, #grid.headers do grid.headers[j]:Hide() end

  for i, unit in ipairs(units) do
    local row = grid.rows[i] or CreateGridRow(i)
    row.unit = unit
    row:Show()
    row.name:SetText(UnitName(unit) or unit)
    local _, class = UnitClass(unit)
    local color = class and not IsSecret(class) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    local connected = unit == "player" or UnitIsConnected(unit)
    local visible = unit == "player" or UnitIsVisible(unit)
    local readable = (IsSecret(connected) or connected) and (IsSecret(visible) or visible)
    if readable and color then
      row.name:SetTextColor(color.r, color.g, color.b)
    else
      row.name:SetTextColor(unpack(COLOR_MUTED))
    end
    local buffs = readable and UnitBuffList(unit) or nil
    for j, column in ipairs(columns) do
      local cell = row.cells[j] or CreateGridCell(row, j)
      cell.unitName, cell.columnLabel = row.name:GetText(), column.label
      cell:Show()
      SetCell(cell, CellState(unit, column, buffs, counts))
    end
    for j = #columns + 1, #row.cells do row.cells[j]:Hide() end
  end
  for i = #units + 1, #grid.rows do grid.rows[i]:Hide() end

  grid:SetSize(20 + GRID_NAME_WIDTH + #columns * GRID_CELL,
    GRID_TOP + GRID_HEADER + #units * GRID_ROW_HEIGHT + 8)
end

local function CreateGrid()
  grid = CreateFrame("Frame", "BuffWatcherForeverGrid", UIParent, "BackdropTemplate")
  grid.headers, grid.rows = {}, {}
  grid:SetPoint("TOPLEFT", frame, "TOPRIGHT", 6, 0)
  grid:SetFrameStrata("MEDIUM")
  grid:SetClampedToScreen(true)
  grid:EnableMouse(true)
  if grid.SetBackdrop then
    grid:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    grid:SetBackdropColor(unpack(COLOR_PANEL))
    grid:SetBackdropBorderColor(unpack(COLOR_BORDER))
  end

  grid.title = grid:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  GridFont(grid.title, 13)
  grid.title:SetTextColor(unpack(COLOR_PRESENT))
  grid.title:SetPoint("TOPLEFT", grid, "TOPLEFT", 10, -9)
  grid.title:SetText("Party Buffs")

  grid.close = CreateFrame("Button", nil, grid)
  grid.close:SetSize(18, 18)
  grid.close:SetPoint("TOPRIGHT", grid, "TOPRIGHT", -5, -5)
  grid.close.text = grid.close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  GridFont(grid.close.text, 13)
  grid.close.text:SetPoint("CENTER")
  grid.close.text:SetText("x")
  grid.close.text:SetTextColor(unpack(COLOR_MUTED))
  grid.close:SetScript("OnClick", function() grid:Hide(); UpdateHeaderButtons() end)
  grid.close:SetScript("OnEnter", function(self) self.text:SetTextColor(unpack(COLOR_PRESENT)) end)
  grid.close:SetScript("OnLeave", function(self) self.text:SetTextColor(unpack(COLOR_MUTED)) end)

  grid.elapsed = 0
  grid:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = self.elapsed + (elapsed or 0)
    if self.elapsed >= 1 then
      self.elapsed = 0
      UpdateGrid()
    end
  end)
  grid:SetScript("OnShow", UpdateHeaderButtons)
  grid:SetScript("OnHide", UpdateHeaderButtons)
  grid:Hide()
  ApplyTheme()
end

local function ToggleGrid()
  if not grid then CreateGrid() end
  if grid:IsShown() then
    grid:Hide()
  else
    UpdateGrid()
    grid:Show()
  end
  UpdateHeaderButtons()
end


local function MenuFont(fontString, size, color)
  ThemeFont(fontString, size)
  fontString:SetShadowOffset(1, -1)
  fontString:SetTextColor(unpack(color or COLOR_PRESENT))
end

-- Square checkbox drawn like the rest of the panel: thin frame, accent fill when on.
local function CreateCheckbox(parent, y, label, get, set)
  local b = CreateFrame("Button", nil, parent)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, y)
  b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, y)
  b:SetHeight(20)
  b.box = b:CreateTexture(nil, "BORDER")
  b.box:SetSize(12, 12)
  b.box:SetPoint("LEFT")
  b.box:SetColorTexture(unpack(COLOR_BORDER))
  b.inner = b:CreateTexture(nil, "ARTWORK")
  b.inner:SetSize(10, 10)
  b.inner:SetPoint("CENTER", b.box)
  b.inner:SetColorTexture(unpack(COLOR_PANEL))
  b.check = b:CreateTexture(nil, "OVERLAY")
  b.check:SetSize(6, 6)
  b.check:SetPoint("CENTER", b.box)
  b.check:SetColorTexture(unpack(COLOR_BAR))
  b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  MenuFont(b.label, 12)
  b.label:SetPoint("LEFT", b.box, "RIGHT", 8, 0)
  b.label:SetText(label)
  b.update = function(self)
    if get() then self.check:Show() else self.check:Hide() end
  end
  b:SetScript("OnClick", function(self)
    set(not get())
    self:update()
    UpdateHeaderButtons()
  end)
  b:SetScript("OnEnter", function(self) self.box:SetColorTexture(unpack(COLOR_BAR)) end)
  b:SetScript("OnLeave", function(self) self.box:SetColorTexture(unpack(COLOR_BORDER)) end)
  return b
end

-- Label with the current value on the right, a thin track and an accent thumb.
local function CreateSlider(parent, y, label, minValue, maxValue, step, get, set, format)
  local f = CreateFrame("Frame", nil, parent)
  f:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, y)
  f:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, y)
  f:SetHeight(34)
  f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  MenuFont(f.label, 12)
  f.label:SetPoint("TOPLEFT")
  f.label:SetText(label)
  f.valueText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  MenuFont(f.valueText, 12, COLOR_MUTED)
  f.valueText:SetPoint("TOPRIGHT")

  local slider = CreateFrame("Slider", nil, f)
  slider:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -18)
  slider:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -18)
  slider:SetHeight(12)
  slider:SetOrientation("HORIZONTAL")
  slider:SetMinMaxValues(minValue, maxValue)
  slider:SetValueStep(step)
  slider:SetObeyStepOnDrag(true)
  slider:EnableMouse(true)
  slider.track = slider:CreateTexture(nil, "BACKGROUND")
  slider.track:SetPoint("LEFT")
  slider.track:SetPoint("RIGHT")
  slider.track:SetHeight(2)
  slider.track:SetColorTexture(1, 1, 1, 0.15)
  slider.thumb = slider:CreateTexture(nil, "OVERLAY")
  slider.thumb:SetSize(8, 12)
  slider.thumb:SetColorTexture(unpack(COLOR_BAR))
  slider:SetThumbTexture(slider.thumb)
  slider:SetScript("OnValueChanged", function(_, value)
    value = math.floor(value / step + 0.5) * step
    set(value)
    f.valueText:SetText(format(value))
  end)
  f.slider = slider
  f.update = function()
    slider:SetValue(get())
    f.valueText:SetText(format(get()))
  end
  return f
end

local OPTIONS_WIDTH = 250

-- Side-by-side choices; the selected one is filled with the accent colour.
local function CreateSegments(parent, y, label, choices, get, set)
  local f = CreateFrame("Frame", nil, parent)
  f:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, y)
  f:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, y)
  f:SetHeight(42)
  f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  MenuFont(f.label, 12)
  f.label:SetPoint("TOPLEFT")
  f.label:SetText(label)
  f.buttons = {}
  local width = (OPTIONS_WIDTH - 20 - (#choices - 1) * 4) / #choices
  for i, choice in ipairs(choices) do
    local b = CreateFrame("Button", nil, f)
    b:SetSize(width, 22)
    b:SetPoint("TOPLEFT", f, "TOPLEFT", (i - 1) * (width + 4), -18)
    b.value = choice.value
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    MenuFont(b.label, 11)
    b.label:SetPoint("CENTER")
    b.label:SetText(choice.label)
    b:SetScript("OnClick", function()
      set(choice.value)
      f.update()
    end)
    f.buttons[i] = b
  end
  f.update = function()
    for _, b in ipairs(f.buttons) do
      if get() == b.value then
        b.bg:SetColorTexture(COLOR_BAR[1], COLOR_BAR[2], COLOR_BAR[3], 0.35)
      else
        b.bg:SetColorTexture(1, 1, 1, 0.06)
      end
    end
  end
  return f
end

local function CreateMenuButton(parent, y, label, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, y)
  b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, y)
  b:SetHeight(22)
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.bg:SetColorTexture(1, 1, 1, 0.06)
  b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  MenuFont(b.label, 12)
  b.label:SetPoint("CENTER")
  b.label:SetText(label)
  b:SetScript("OnClick", onClick)
  b:SetScript("OnEnter", function(self) self.bg:SetColorTexture(1, 1, 1, 0.12) end)
  b:SetScript("OnLeave", function(self) self.bg:SetColorTexture(1, 1, 1, 0.06) end)
  return b
end

local function ResetPosition()
  db.point = { "CENTER", "CENTER", 0, 200 }
  ApplyPosition()
end

-- Point offsets are in the panel's own (scaled) units, so they are rescaled too:
-- the panel then grows or shrinks around its anchor instead of wandering off.
local function SetPanelScale(scale)
  local old = frame.appliedScale or scale
  if old ~= scale then
    db.point[3] = db.point[3] * old / scale
    db.point[4] = db.point[4] * old / scale
  end
  frame:SetScale(scale)
  frame.appliedScale = scale
  ApplyPosition()
end

-- The menu is pinned to the screen where the panel was when it opened, not to
-- the panel itself; otherwise rescaling the panel would move the scale slider
-- away under the mouse and the value would flip between the ends.
local function PlaceOptions()
  options:ClearAllPoints()
  local left, bottom = frame:GetLeft(), frame:GetBottom()
  if frame:IsShown() and left and bottom and not IsSecret(left) and not IsSecret(bottom) then
    local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    options:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * ratio, bottom * ratio - 6)
  else
    options:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end
end

-- Options menu below the panel, in the same style: header bar, checkboxes, sliders.
local function CreateOptions()
  options = CreateFrame("Frame", "BuffWatcherForeverOptions", UIParent, "BackdropTemplate")
  options:SetWidth(OPTIONS_WIDTH)
  PlaceOptions()
  options:SetFrameStrata("HIGH")
  options:SetClampedToScreen(true)
  options:EnableMouse(true)
  if options.SetBackdrop then
    options:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    options:SetBackdropColor(unpack(COLOR_PANEL))
    options:SetBackdropBorderColor(unpack(COLOR_BORDER))
  end

  local header = CreateFrame("Frame", nil, options)
  header:SetPoint("TOPLEFT", options, "TOPLEFT", 1, -1)
  header:SetPoint("TOPRIGHT", options, "TOPRIGHT", -1, -1)
  header:SetHeight(HEADER_HEIGHT)
  header.bg = header:CreateTexture(nil, "BACKGROUND")
  header.bg:SetAllPoints()
  header.bg:SetColorTexture(unpack(COLOR_HEADER))
  header.line = header:CreateTexture(nil, "BORDER")
  header.line:SetPoint("BOTTOMLEFT")
  header.line:SetPoint("BOTTOMRIGHT")
  header.line:SetHeight(1)
  header.line:SetColorTexture(unpack(COLOR_BORDER))
  header.mark = header:CreateTexture(nil, "ARTWORK")
  header.mark:SetSize(6, 6)
  header.mark:SetPoint("LEFT", header, "LEFT", 10, 0)
  header.mark:SetColorTexture(unpack(COLOR_BAR))
  header.title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  MenuFont(header.title, 12)
  header.title:SetPoint("LEFT", header.mark, "RIGHT", 7, 0)
  header.title:SetText("Options")
  options.header = header
  options.close = CreateFrame("Button", nil, header)
  options.close:SetSize(18, 18)
  options.close:SetPoint("RIGHT", header, "RIGHT", -4, 0)
  options.close.text = options.close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  MenuFont(options.close.text, 13, COLOR_MUTED)
  options.close.text:SetPoint("CENTER")
  options.close.text:SetText("x")
  options.close:SetScript("OnClick", function() options:Hide(); UpdateHeaderButtons() end)
  options.close:SetScript("OnEnter", function(self) self.text:SetTextColor(unpack(COLOR_PRESENT)) end)
  options.close:SetScript("OnLeave", function(self) self.text:SetTextColor(unpack(COLOR_MUTED)) end)

  options.checkboxes, options.sliders = {}, {}
  local y = -(HEADER_HEIGHT + 8)
  local function Checkbox(label, key, after)
    local c = CreateCheckbox(options, y, label,
      function() return db[key] end,
      function(value) db[key] = value; if after then after() end end)
    c.key = key
    options.checkboxes[#options.checkboxes + 1] = c
    y = y - 22
  end
  Checkbox("Lock panel", "locked")
  Checkbox("Horizontal layout", "horizontal", Refresh)
  Checkbox("Warning sound and chat", "sound")
  Checkbox("Hide when all buffs are fine", "autohide", Refresh)
  Checkbox("Show Sleeping Bag at max level", "bagAtMax", Refresh)
  y = y - 6

  options.style = CreateSegments(options, y, "Style",
    { { value = "forever", label = "Forever" }, { value = "modern", label = "Modern" },
      { value = "classic", label = "Classic" } },
    function() return db.theme end,
    function(value) db.theme = value; ApplyTheme() end)
  y = y - 48

  local function Slider(label, key, minValue, maxValue, step, format, after)
    local sl = CreateSlider(options, y, label, minValue, maxValue, step,
      function() return db[key] end,
      function(value) db[key] = value; if after then after(value) end end, format)
    sl.key = key
    options.sliders[#options.sliders + 1] = sl
    y = y - 40
  end
  Slider("Scale", "scale", 0.5, 2, 0.05,
    function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end,
    SetPanelScale)
  Slider("Warn before a buff runs out", "warn", 0, 30, 1,
    function(v) return v == 0 and "off" or (v .. " min") end)

  options.reset = CreateMenuButton(options, y, "Reset position", ResetPosition)
  y = y - 22
  options:SetHeight(-y + 10)

  options:SetScript("OnShow", function()
    options.style.update()
    for _, c in ipairs(options.checkboxes) do c:update() end
    for _, sl in ipairs(options.sliders) do sl.update() end
    UpdateHeaderButtons()
  end)
  options:SetScript("OnHide", UpdateHeaderButtons)
  options:Hide()
  ApplyTheme()
end

local function ToggleOptions()
  if not options then CreateOptions() end
  if options:IsShown() then
    options:Hide()
  else
    options.style.update()
    for _, c in ipairs(options.checkboxes) do c:update() end
    for _, sl in ipairs(options.sliders) do sl.update() end
    PlaceOptions()
    options:Show()
  end
  UpdateHeaderButtons()
end

local function ToggleLayout()
  db.horizontal = not db.horizontal
  Refresh()
end

local function ToggleLock()
  db.locked = not db.locked
end

-- Header buttons, right to left: party grid, options, layout direction, lock.
local function CreateHeaderButtons()
  -- Party grid at the far right: larger, framed and filled so it reads as a button.
  local gridButton = CreateHeaderButton("BuffWatcherForeverGridButton", function()
    return "Party buff grid", "Who in your party has which buff"
  end, ToggleGrid, true)
  for row = 0, 2 do
    for col = 0, 2 do AddPart(gridButton, 4, 4, -7 + col * 5, 7 - row * 5) end
  end
  gridButton.isActive = function() return grid ~= nil and grid:IsShown() end

  -- Three slider lines with knobs.
  local optionsButton = CreateHeaderButton("BuffWatcherForeverOptionsButton", function()
    return "Options"
  end, ToggleOptions)
  for i = 0, 2 do
    AddPart(optionsButton, 11, 1, -5, 4 - i * 4)
    AddPart(optionsButton, 3, 3, ({ -3, 2, -1 })[i + 1], 5 - i * 4)
  end
  optionsButton.isActive = function() return options ~= nil and options:IsShown() end

  -- Three bars: stacked rows in vertical mode, side-by-side columns in horizontal.
  local layoutButton = CreateHeaderButton("BuffWatcherForeverLayoutButton", function()
    return db.horizontal and "Switch to vertical" or "Switch to horizontal"
  end, ToggleLayout)
  for _ = 1, 3 do AddPart(layoutButton, 1, 1, 0, 0) end
  layoutButton.redraw = function(b)
    for i, part in ipairs(b.parts) do
      if db.horizontal then
        Place(b, part, 2, 11, -5 + (i - 1) * 4, 5)
      else
        Place(b, part, 11, 2, -5, 5 - (i - 1) * 4)
      end
    end
  end

  -- Padlock: body plus shackle; the shackle lifts and opens when unlocked.
  local lockButton = CreateHeaderButton("BuffWatcherForeverLockButton", function()
    return db.locked and "Unlock panel" or "Lock panel", db.locked and "Panel can't be moved" or "Drag the panel to move it"
  end, ToggleLock)
  lockButton.body = AddPart(lockButton, 9, 6, -4, 0)
  lockButton.top = AddPart(lockButton, 5, 1, -2, 5)
  lockButton.left = AddPart(lockButton, 1, 4, -2, 4)
  lockButton.right = AddPart(lockButton, 1, 4, 2, 4)
  lockButton.redraw = function(b)
    local lift = db.locked and 0 or 2
    Place(b, b.top, 5, 1, -2, 5 + lift)
    Place(b, b.left, 1, 4, -2, 4 + lift)
    Place(b, b.right, 1, db.locked and 4 or 2, 2, 4 + lift)
  end
  lockButton.isActive = function() return db.locked end

  UpdateHeaderButtons()
end

---------------------------------------------------------------------------
-- Styles
---------------------------------------------------------------------------

-- Restyles every window that exists: colours, border, fonts, header bar.
ApplyTheme = function()
  local theme = Theme()
  CopyInto(COLOR_PANEL, theme.panel)
  CopyInto(COLOR_PANEL_COMPLETE, theme.complete)
  CopyInto(COLOR_BORDER, theme.border)
  CopyInto(COLOR_HEADER, theme.header)
  CopyInto(COLOR_SEPARATOR, theme.separator)
  CopyInto(COLOR_ROW, theme.row)
  CopyInto(COLOR_BAR, theme.accent)
  local inset = theme.inset

  local function Chrome(f)
    if f.SetBackdrop then
      f:SetBackdrop(theme.backdrop)
      f:SetBackdropColor(unpack(COLOR_PANEL))
      f:SetBackdropBorderColor(unpack(COLOR_BORDER))
    end
  end
  local function Header(header, owner)
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", owner, "TOPLEFT", inset, -inset)
    header:SetPoint("TOPRIGHT", owner, "TOPRIGHT", -inset, -inset)
    header.bg:SetColorTexture(unpack(COLOR_HEADER))
    header.line:SetColorTexture(unpack(theme.headerLine))
    header.mark:SetColorTexture(unpack(COLOR_BAR))
    if theme.showMark then header.mark:Show() else header.mark:Hide() end
    header.title:ClearAllPoints()
    if theme.showMark then
      header.title:SetPoint("LEFT", header.mark, "RIGHT", 7, 0)
    else
      header.title:SetPoint("LEFT", header, "LEFT", 8, 0)
    end
    header.title:SetTextColor(unpack(theme.title))
  end

  for _, entry in ipairs(themedFonts) do
    entry.fs:SetFont(theme.font or entry.default, entry.size, "")
  end

  Chrome(frame)
  Header(frame.header, frame)
  frame.header.title:SetText(theme.titleText)
  for _, row in ipairs(rowOrder) do
    row.bg:SetColorTexture(unpack(COLOR_ROW))
    if row.hasLine then
      row.bar:SetColorTexture(unpack(COLOR_BAR))
      if theme.showBar then row.bar:Show() else row.bar:Hide() end
      row.line:SetColorTexture(unpack(COLOR_SEPARATOR))
      row.vline:SetColorTexture(unpack(COLOR_SEPARATOR))
    end
  end
  for _, timer in ipairs(timerRows) do
    timer.bar:SetStatusBarTexture(theme.barTexture)
    timer.bar:SetStatusBarColor(unpack(theme.barColor or COLOR_BAR))
  end

  if grid then
    Chrome(grid)
    grid.title:SetTextColor(unpack(theme.title))
    for i, row in ipairs(grid.rows) do
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", grid, "TOPLEFT", inset, -(GRID_TOP + GRID_HEADER + (i - 1) * GRID_ROW_HEIGHT))
      row:SetPoint("TOPRIGHT", grid, "TOPRIGHT", -inset, -(GRID_TOP + GRID_HEADER + (i - 1) * GRID_ROW_HEIGHT))
    end
  end
  if options then
    Chrome(options)
    Header(options.header, options)
    for _, c in ipairs(options.checkboxes) do
      c.box:SetColorTexture(unpack(COLOR_BORDER))
      c.inner:SetColorTexture(unpack(COLOR_PANEL))
      c.check:SetColorTexture(unpack(COLOR_BAR))
    end
    for _, sl in ipairs(options.sliders) do sl.slider.thumb:SetColorTexture(unpack(COLOR_BAR)) end
    options.style.update()
  end

  UpdateHeaderButtons()
  Refresh()
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

-- /bw opens the options menu; everything else lives in the panel and the menu.
local function Slash()
  ToggleOptions()
  Refresh()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterUnitEvent("UNIT_AURA", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
events:RegisterEvent("PLAYER_UPDATE_RESTING")
events:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 ~= ADDON then return end
    BuffWatcherForeverDB = BuffWatcherForeverDB or {}
    db = BuffWatcherForeverDB
    CopyDefaults(DEFAULTS, db)
    db.extra = nil -- custom buff names were removed in 1.5
    for _, t in ipairs(TRACKERS) do
      state[t.key] = { active = false, expires = 0 }
    end
    CreateMainFrame()
    CreateHeaderButtons()
    ApplyTheme()
    SLASH_BUFFWATCHERFOREVER1 = "/bw"
    SLASH_BUFFWATCHERFOREVER2 = "/buffwatcher"
    SlashCmdList.BUFFWATCHERFOREVER = Slash
    C_Timer.NewTicker(1, Refresh)
    Refresh()
    events:UnregisterEvent("ADDON_LOADED")
  elseif db then
    -- PLAYER_ENTERING_WORLD, PLAYER_REGEN_ENABLED, UNIT_AURA, channel start/stop,
    -- PLAYER_UPDATE_RESTING (lying down in the Sleeping Bag)
    Scan()
    Refresh()
  end
end)
