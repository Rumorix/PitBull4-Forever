local PitBull4 = _G.PitBull4
local L = PitBull4.L

local PitBull4_LuaTexts = PitBull4:NewModule("LuaTexts", "AceHook-3.0")

local new, del = PitBull4.new, PitBull4.del
local InChatMessagingLockdown = C_ChatInfo.InChatMessagingLockdown
local ShouldUnitComparisonBeSecret = C_Secrets.ShouldUnitComparisonBeSecret

local test_frame = CreateFrame("Frame") -- Event validation

local texts = {}
local no_update = {}
local event_cache = {}
local func_cache = {}
local power_cache = {}
PitBull4_LuaTexts.power_cache = power_cache
local hp_cache = {}
PitBull4_LuaTexts.hp_cache = hp_cache
local mouseover_check_cache = {}
PitBull4_LuaTexts.mouseover_check_cache = mouseover_check_cache
local spell_cast_cache = {}
PitBull4_LuaTexts.spell_cast_cache = spell_cast_cache
local unit_cast_ids = {}
PitBull4_LuaTexts.unit_cast_ids = unit_cast_ids
local cast_data = {}
PitBull4_LuaTexts.cast_data = cast_data
local to_update = {}
PitBull4_LuaTexts.to_update = to_update
local afk_cache = {}
PitBull4_LuaTexts.afk_cache = afk_cache
local dnd_cache = {}
PitBull4_LuaTexts.dnd_cache = dnd_cache
local offline_cache = {}
PitBull4_LuaTexts.offline_cache = offline_cache
local dead_cache = {}
PitBull4_LuaTexts.dead_cache = dead_cache
local offline_times = {}
PitBull4_LuaTexts.offline_times = offline_times
local afk_times = {}
PitBull4_LuaTexts.afk_times = afk_times
local dnd = {}
PitBull4_LuaTexts.dnd = dnd
local dead_times = {}
PitBull4_LuaTexts.dead_times = dead_times
local group_members = {}
PitBull4_LuaTexts.group_members = group_members
local player_guid = UnitGUID("player")
local predicted_health = true

local PROVIDED_CODES = {
	[L["Class"]] = {
		[L["Standard"]] = {
			events = {['UNIT_CLASSIFICATION_CHANGED']=true,['UNIT_LEVEL']=true,['UNIT_AURA']=true},
			code = [[
return IdentityDisplay(unit, false)]],
		},
		[L["Player classes only"]] = {
			events = {['UNIT_CLASSIFICATION_CHANGED']=true,['UNIT_LEVEL']=true,['UNIT_AURA']=true},
			code = [[
return IdentityDisplay(unit, true)]],
		},
		[L["Short level and race"]] = {
			events = {['UNIT_CLASSIFICATION_CHANGED']=true,['UNIT_LEVEL']=true},
			code = [[
local dr,dg,db = DifficultyColor(unit)
return "|cff%02x%02x%02x%s%s|r %s",dr,dg,db,Level(unit),Classification(unit) and '+' or '',SmartRace(unit) or '']],
		},
		[L["Short"]] = {
			events = {},
			code = [[
if UnitIsPlayer(unit) then
  local cr,cg,cb = ClassColor(unit)
  return "|cff%02x%02x%02x%s|r",cr,cg,cb,Class(unit)
end]],
		},
	},
	[L["Health"]] = {
		[L["Absolute"]] = {
			events = {['UNIT_HEALTH']=true,['UNIT_MAXHEALTH']=true,['UNIT_AURA']=true},
			code = [[
local s = Status(unit)
if s then
  return s
end
return "%s/%s",HP(unit),MaxHP(unit)]],
		},
		[L["Absolute short"]] = {
			events = {['UNIT_HEALTH']=true,['UNIT_MAXHEALTH']=true,['UNIT_AURA']=true},
			code = [[
local s = Status(unit)
if s then
  return s
end
return "%s/%s",Short(HP(unit)),Short(MaxHP(unit))]],
		},
		[L["Difference"]] = {
			events = {['UNIT_HEALTH']=true,['UNIT_MAXHEALTH']=true,['UNIT_AURA']=true},
			code = [[
local s = Status(unit)
if s then
  return s
end
return Minus(MissingHP(unit))]],
		},
		[L["Percent"]] = {
			events = {['UNIT_HEALTH']=true,['UNIT_MAXHEALTH']=true,['UNIT_AURA']=true},
			code = [[
local s = Status(unit)
if s then
  return s
end
return "%s%%",PercentHP(unit)]],
		},
		[L["Mini"]] = {
			events = {['UNIT_HEALTH']=true,['UNIT_MAXHEALTH']=true},
			code = [[
return VeryShort(HP(unit))]],
		},
		[L["Smart"]] = {
			events = {['UNIT_HEALTH']=true,['UNIT_MAXHEALTH']=true,['UNIT_AURA']=true},
			code = [[
local s = Status(unit)
if s then
  return s
end
if UnitIsFriend(unit,"player") then
  return WrapTextInColorCode(HP(unit), "ffff7f7f")
else
  return "%s/%s",Short(HP(unit)),Short(MaxHP(unit))
end]],
		},
		[L["Absolute and percent"]] = {
			events = {['UNIT_HEALTH']=true,['UNIT_MAXHEALTH']=true,['UNIT_AURA']=true},
			code = [[
local s = Status(unit)
if s then
  return s
end
return "%s/%s || %s%%",Short(HP(unit)),Short(MaxHP(unit)),PercentHP(unit)]],
		},
		[L["Informational"]] = {
			events = {['UNIT_HEALTH']=true,['UNIT_MAXHEALTH']=true,['UNIT_AURA']=true},
			code = [[
local s = Status(unit)
if s then
  return s
end
if UnitIsFriend(unit,"player") then
  local miss = WrapString(TruncateWhenZero(MissingHP(unit)), "|cffff7f7f", "|r || ")
  return "%s%s/%s || %s%%",miss,Short(HP(unit)),Short(MaxHP(unit)),PercentHP(unit)
end
return "%s/%s || %s%%",Short(HP(unit)),Short(MaxHP(unit)),PercentHP(unit)]],
		},
	},
	[L["Name"]] = {
		[L["Standard"]] = {
			events = {['UNIT_NAME_UPDATE']=true,['PLAYER_FLAGS_CHANGED'] = true},
			code = [[
return '%s %s',Name(unit),Angle(AFK(unit) or DND(unit))]],
		},
		[L["Hostility-colored"]] = {
			events = {['UNIT_NAME_UPDATE']=true,['PLAYER_FLAGS_CHANGED'] = true,['UNIT_FACTION']=true},
			code = [[
local r,g,b = HostileColor(unit)
return '|cff%02x%02x%02x%s|r %s',r,g,b,Name(unit),Angle(AFK(unit) or DND(unit))]],
		},
		[L["Class-colored"]] = {
			events = {['UNIT_NAME_UPDATE']=true,['PLAYER_FLAGS_CHANGED'] = true},
			code = [[
local r,g,b = ClassColor(unit)
return '|cff%02x%02x%02x%s|r %s',r,g,b,Name(unit),Angle(AFK(unit) or DND(unit))]],
		},
		[L["Long"]] = {
			events = {['UNIT_NAME_UPDATE']=true,['PLAYER_FLAGS_CHANGED'] = true,['UNIT_LEVEL']=true},
			code = [[
local r,g,b = ClassColor(unit)
return '%s |cff%02x%02x%02x%s|r %s',Level(unit),r,g,b,Name(unit),Angle(AFK(unit) or DND(unit))]],
		},
		[L["Long w/ Druid form"]] = {
			events = {['UNIT_NAME_UPDATE']=true,['PLAYER_FLAGS_CHANGED'] = true,['UNIT_LEVEL']=true,['UNIT_AURA']=true},
			code = [[
local r,g,b = ClassColor(unit)
local form = DruidForm(unit)
if form then
  return '%s |cff%02x%02x%02x%s|r (%s) %s',Level(unit),r,g,b,Name(unit),form,Angle(AFK(unit) or DND(unit))
else
  return '%s |cff%02x%02x%02x%s|r %s',Level(unit),r,g,b,Name(unit),Angle(AFK(unit) or DND(unit))
end]],
		},
	},
	[L["Power"]] = {
		[L["Absolute"]] = {
			events = {['UNIT_POWER_FREQUENT']=true,['UNIT_MAXPOWER']=true},
			code = [[
local text = PowerText(unit)
if text then return text end
return "%s%%",PercentPower(unit)]],
		},
		[L["Absolute short"]] = {
			events = {['UNIT_POWER_FREQUENT']=true,['UNIT_MAXPOWER']=true},
			code = [[
local text = PowerText(unit,nil,true)
if text then return text end
return "%s%%",PercentPower(unit)]],
		},
		[L["Difference"]] = {
			events = {['UNIT_POWER_FREQUENT']=true,['UNIT_MAXPOWER']=true},
			code = [[
local missing = PublicMissingPower(unit)
if missing ~= nil then return Minus(missing) end
return "%s%%",PercentPower(unit)]],
		},
		[L["Percent"]] = {
			events = {['UNIT_POWER_FREQUENT']=true,['UNIT_MAXPOWER']=true},
			code = [[
return "%s%%",PercentPower(unit)]],
		},
		[L["Absolute and percent"]] = {
			events = {['UNIT_POWER_FREQUENT']=true,['UNIT_MAXPOWER']=true},
			code = [[
local text = PowerText(unit)
if text then return "%s || %s%%",text,PercentPower(unit) end
return "%s%%",PercentPower(unit)]],
		},
		[L["Mini"]] = {
			events = {['UNIT_POWER_FREQUENT']=true,['UNIT_MAXPOWER']=true},
			code = [[
local text = CurrentPowerText(unit,nil,true)
if text then return text end
return "%s%%",PercentPower(unit)]],
		},
		[L["Smart"]] = {
			events = {['UNIT_POWER_FREQUENT']=true,['UNIT_MAXPOWER']=true},
			code = [[
local text = MissingPowerText(unit,nil,"ff7f7fff")
if text then return text end
return "%s%%",PercentPower(unit)]],
		},
	},
	[L["Druid mana"]] = {
		[L["Absolute"]] = {
			events = {['UNIT_POWER_FREQUENT']=true,['UNIT_MAXPOWER']=true,['UNIT_DISPLAYPOWER']=true},
			code = [[
local visible = ShouldShowDruidMana(unit)
if not visible then return end
local text = PowerText(unit,0)
if text then return text end
return "%s%%",PercentPower(unit,0)]],
		},
		[L["Absolute short"]] = {
			events = {['UNIT_POWER_FREQUENT']=true,['UNIT_MAXPOWER']=true,['UNIT_DISPLAYPOWER']=true},
			code = [[
local visible = ShouldShowDruidMana(unit)
if not visible then return end
local text = PowerText(unit,0,true)
if text then return text end
return "%s%%",PercentPower(unit,0)]],
		},
		[L["Difference"]] = {
			events = {['UNIT_POWER_FREQUENT']=true,['UNIT_MAXPOWER']=true,['UNIT_DISPLAYPOWER']=true},
			code = [[
local visible = ShouldShowDruidMana(unit)
if not visible then return end
local missing = PublicMissingPower(unit,0)
if missing ~= nil then return Minus(missing) end
return "%s%%",PercentPower(unit,0)]],
		},
		[L["Percent"]] = {
			events = {['UNIT_POWER_FREQUENT']=true,['UNIT_MAXPOWER']=true,['UNIT_DISPLAYPOWER']=true},
			code = [[
local visible = ShouldShowDruidMana(unit)
if not visible then return end
return "%s%%",PercentPower(unit,0)]],
		},
		[L["Mini"]] = {
			events = {['UNIT_POWER_FREQUENT']=true,['UNIT_MAXPOWER']=true,['UNIT_DISPLAYPOWER']=true},
			code = [[
local visible = ShouldShowDruidMana(unit)
if not visible then return end
local text = CurrentPowerText(unit,0,true)
if text then return text end
return "%s%%",PercentPower(unit,0)]],
		},
		[L["Smart"]] = {
			events = {['UNIT_POWER_FREQUENT']=true,['UNIT_MAXPOWER']=true,['UNIT_DISPLAYPOWER']=true},
			code = [[
local visible = ShouldShowDruidMana(unit)
if not visible then return end
local text = MissingPowerText(unit,0,"ff7f7fff")
if text then return text end
return "%s%%",PercentPower(unit,0)]],
		},
	},
	[L["Alternate power"]] = {
		[L["Absolute"]] = {
			events = {['UNIT_POWER_FREQUENT']=true,['UNIT_MAXPOWER']=true},
			code = [[
local visible = HasPublicPower(unit,ALTERNATE_POWER_INDEX)
if visible then return PowerText(unit,ALTERNATE_POWER_INDEX) end
if visible == nil then return "%s%%",PercentPower(unit,ALTERNATE_POWER_INDEX) end
return ConfigMode()]],
		},
		[L["Absolute short"]] = {
			events = {['UNIT_POWER_FREQUENT']=true,['UNIT_MAXPOWER']=true},
			code = [[
local visible = HasPublicPower(unit,ALTERNATE_POWER_INDEX)
if visible then return PowerText(unit,ALTERNATE_POWER_INDEX,true) end
if visible == nil then return "%s%%",PercentPower(unit,ALTERNATE_POWER_INDEX) end
return ConfigMode()]],
		},
		[L["Difference"]] = {
			events = {['UNIT_POWER_FREQUENT']=true,['UNIT_MAXPOWER']=true},
			code = [[
local visible = HasPublicPower(unit,ALTERNATE_POWER_INDEX)
if visible then
  local missing = PublicMissingPower(unit,ALTERNATE_POWER_INDEX)
  if missing ~= nil then return Minus(missing) end
end
if visible == nil then return "%s%%",PercentPower(unit,ALTERNATE_POWER_INDEX) end
return ConfigMode()]],
		},
		[L["Percent"]] = {
			events = {['UNIT_POWER_FREQUENT']=true,['UNIT_MAXPOWER']=true},
			code = [[
local visible = HasPublicPower(unit,ALTERNATE_POWER_INDEX)
if visible or visible == nil then return "%s%%",PercentPower(unit,ALTERNATE_POWER_INDEX) end
return ConfigMode()]],
		},
		[L["Mini"]] = {
			events = {['UNIT_POWER_FREQUENT']=true,['UNIT_MAXPOWER']=true},
			code = [[
local visible = HasPublicPower(unit,ALTERNATE_POWER_INDEX)
if visible then return CurrentPowerText(unit,ALTERNATE_POWER_INDEX,true) end
if visible == nil then return "%s%%",PercentPower(unit,ALTERNATE_POWER_INDEX) end
return ConfigMode()]],
		},
		[L["Smart"]] = {
			events = {['UNIT_POWER_FREQUENT']=true,['UNIT_MAXPOWER']=true},
			code = [[
local visible = HasPublicPower(unit,ALTERNATE_POWER_INDEX)
if visible then return MissingPowerText(unit,ALTERNATE_POWER_INDEX,"ffc12267") end
if visible == nil then return "%s%%",PercentPower(unit,ALTERNATE_POWER_INDEX) end
return ConfigMode()]],
		},
	},
	[L["Artifact power"]] = {
		[L["Absolute"]] = {
			events = {['ARTIFACT_XP_UPDATE']=true,['AZERITE_ITEM_EXPERIENCE_CHANGED']=true,['AZERITE_ITEM_POWER_LEVEL_CHANGED']=true,['AZERITE_EMPOWERED_ITEM_SELECTION_UPDATED']=true},
			code = [[
local cur,max,points = ArtifactPower()
if max > 0 then
  if points > 0 then
    return "%s/%s (%d)",cur,max,points
  end
  return "%s/%s",cur,max
end
return ConfigMode()]],
		},
		[L["Absolute short"]] = {
			events = {['ARTIFACT_XP_UPDATE']=true,['AZERITE_ITEM_EXPERIENCE_CHANGED']=true,['AZERITE_ITEM_POWER_LEVEL_CHANGED']=true,['AZERITE_EMPOWERED_ITEM_SELECTION_UPDATED']=true},
			code = [[
local cur,max,points = ArtifactPower()
if max > 0 then
  if points > 0 then
    return "%s/%s (%d)",Short(cur),Short(max),points
  end
  return "%s/%s",Short(cur),Short(max)
end
return ConfigMode()]],
		},
		[L["Difference"]] = {
			events = {['ARTIFACT_XP_UPDATE']=true,['AZERITE_ITEM_EXPERIENCE_CHANGED']=true,['AZERITE_ITEM_POWER_LEVEL_CHANGED']=true,['AZERITE_EMPOWERED_ITEM_SELECTION_UPDATED']=true},
			code = [[
local cur,max,points = ArtifactPower()
if max > 0 then
  local missing = -(max-cur)
  if points > 0 then
    return "%d (%d)",missing,points
  end
  return missing
end
return ConfigMode()]],
		},
		[L["Percent"]] = {
			events = {['ARTIFACT_XP_UPDATE']=true,['AZERITE_ITEM_EXPERIENCE_CHANGED']=true,['AZERITE_ITEM_POWER_LEVEL_CHANGED']=true,['AZERITE_EMPOWERED_ITEM_SELECTION_UPDATED']=true},
			code = [[
local cur,max,points = ArtifactPower()
if max > 0 then
  if points > 0 then
    return "%s%% (%d)",Percent(cur,max),points
  end
  return "%s%%",Percent(cur,max)
end
return ConfigMode()]],
		},
		[L["Mini"]] = {
			events = {['ARTIFACT_XP_UPDATE']=true,['AZERITE_ITEM_EXPERIENCE_CHANGED']=true,['AZERITE_ITEM_POWER_LEVEL_CHANGED']=true,['AZERITE_EMPOWERED_ITEM_SELECTION_UPDATED']=true},
			code = [[
local cur,max,points = ArtifactPower()
if max > 0 then
  if points > 0 then
    return "%s (%d)",VeryShort(cur),points
  end
  return VeryShort(cur)
end
return ConfigMode()]],
		},
	},
	[L["Threat"]] = {
		[L["Percent"]] = {
			events = {['UNIT_THREAT_LIST_UPDATE']=true,['UNIT_THREAT_SITUATION_UPDATE']=true},
			code = [[
local unit_a,unit_b = ThreatPair(unit)
if unit_a and unit_b then
  local _,_,percent = UnitDetailedThreatSituation(unit_a, unit_b)
  if percent and percent ~= 0 then
    return "%s%%",Round(percent,1)
  end
end
return ConfigMode()]],
		},
		[L["Raw percent"]] = {
			events = {['UNIT_THREAT_LIST_UPDATE']=true,['UNIT_THREAT_SITUATION_UPDATE']=true},
			code = [[
local unit_a,unit_b = ThreatPair(unit)
if unit_a and unit_b then
  local _,_,_,raw_percent = UnitDetailedThreatSituation(unit_a, unit_b)
    if raw_percent and raw_percent ~= 0 then
    return "%s%%",Round(raw_percent,1)
  end
end
return ConfigMode()]],
		},
		[L["Colored percent"]] = {
			events = {['UNIT_THREAT_LIST_UPDATE']=true,['UNIT_THREAT_SITUATION_UPDATE']=true},
			code = [[
local unit_a,unit_b = ThreatPair(unit)
if unit_a and unit_b then
  local _,status,percent = UnitDetailedThreatSituation(unit_a, unit_b)
  if percent and percent ~= 0 then
    local r,g,b = ThreatStatusColor(status)
    return "|cff%02x%02x%02x%s%%|r",r,g,b,Round(percent,1)
  end
end
return ConfigMode()]],
		},
		[L["Colored raw percent"]] = {
			events = {['UNIT_THREAT_LIST_UPDATE']=true,['UNIT_THREAT_SITUATION_UPDATE']=true},
			code = [[
local unit_a,unit_b = ThreatPair(unit)
if unit_a and unit_b then
  local _,status,_,raw_percent = UnitDetailedThreatSituation(unit_a, unit_b)
  if raw_percent and raw_percent ~= 0 then
    local r,g,b = ThreatStatusColor(status)
    return "|cff%02x%02x%02x%s%%|r",r,g,b,Round(raw_percent,1)
  end
end
return ConfigMode()]],
		},
	},
	[L["Combo points"]] = {
		[L["Standard"]] = {
			events = {['UNIT_POWER_UPDATE']=true},
			code = [[
local combos = Combos()
if combos ~= 0 then
  return combos
end]],
		},
	},
	[L["Experience"]] = {
		[L["Standard"]] = {
			events = {['UNIT_PET_EXPERIENCE']=true,['PLAYER_XP_UPDATE']=true},
			code = [[
local cur, max, rest = XP(unit), MaxXP(unit), RestXP(unit)
if rest then
  return "%s/%s (%s%%) R: %s%%",cur,max,Percent(cur,max),Percent(rest,max)
else
  return "%s/%s (%s%%)",cur,max,Percent(cur,max)
end]],
		},
		[L["On mouse-over"]] = {
			events = {['UNIT_PET_EXPERIENCE']=true,['PLAYER_XP_UPDATE']=true},
			code = [[
if IsMouseOver() then
  local cur, max, rest = XP(unit), MaxXP(unit), RestXP(unit)
  if rest then
    return "%s/%s (%s%%) R: %s%%",cur,max,Percent(cur,max),Percent(rest,max)
  else
    return "%s/%s (%s%%)",cur,max,Percent(cur,max)
  end
end]],
		},
	},
	[L["Reputation"]] = {
		[L["Standard"]] = {
			events = {['UNIT_FACTION']=true,['UPDATE_FACTION']=true},
			code = [[
local name, _, _, max, cur = WatchedFactionInfo()
if not name then return ConfigMode() end
if IsMouseOver() then
  return name
else
  return "%d/%d (%s%%)",cur,max,Percent(cur,max)
end]],
		},
	},
	[L["PVPTimer"]] = {
		[L["Standard"]] = {
			events = {['PLAYER_FLAGS_CHANGED']=true},
			code = [[
local preview = ConfigMode()
if preview then
  return preview
end
if unit == "player" then
  local pvp = PVPDuration(unit)
  if pvp then
    return "|cffff0000%s|r",FormatDuration(pvp)
  end
end]],
		},
	},
	[L["Cast"]] = {
		[L["Standard name"]] = {
			events = {['UNIT_SPELLCAST_START']=true,['UNIT_SPELLCAST_CHANNEL_START']=true,['UNIT_SPELLCAST_STOP']=true,['UNIT_SPELLCAST_FAILED']=true,['UNIT_SPELLCAST_INTERRUPTED']=true,['UNIT_SPELLCAST_SUCCEEDED']=true,['UNIT_SPELLCAST_DELAYED']=true,['UNIT_SPELLCAST_CHANNEL_UPDATE']=true,['UNIT_SPELLCAST_CHANNEL_STOP']=true,['UNIT_SPELLCAST_EMPOWER_START']=true,['UNIT_SPELLCAST_EMPOWER_STOP']=true,['UNIT_SPELLCAST_EMPOWER_UPDATE']=true,},
			code = [[
local cast_data = CastData(unit)
if cast_data then
  local spell,stop_message,target = cast_data.spell,cast_data.stop_message,cast_data.target
  local stop_time,stop_duration = cast_data.stop_time
  if stop_time then
    stop_duration = GetTime() - stop_time
  end
  Alpha(-(stop_duration or 0) + 1)
  if stop_message then
    return InterruptedBy(cast_data.interrupted_by) or stop_message
  elseif target then
    return "%s (%s)",spell,target
  else
    return spell
  end
end
return ConfigMode()]],
		},
		[L["Standard time"]] = {
			events = {['UNIT_SPELLCAST_START']=true,['UNIT_SPELLCAST_CHANNEL_START']=true,['UNIT_SPELLCAST_STOP']=true,['UNIT_SPELLCAST_FAILED']=true,['UNIT_SPELLCAST_INTERRUPTED']=true,['UNIT_SPELLCAST_DELAYED']=true,['UNIT_SPELLCAST_CHANNEL_UPDATE']=true,['UNIT_SPELLCAST_CHANNEL_STOP']=true,['UNIT_SPELLCAST_EMPOWER_START']=true,['UNIT_SPELLCAST_EMPOWER_STOP']=true,['UNIT_SPELLCAST_EMPOWER_UPDATE']=true,},
			code = [[
local cast_data = CastData(unit)
if cast_data then
  if not cast_data.stop_time then
    local delay = cast_data.delay
    local duration = cast_data.duration and cast_data.duration:GetRemainingDuration()
    local duration_text
    if duration and not (issecretvalue and issecretvalue(duration)) then
      duration_text = ("%.1f"):format(duration)
    end
    if delay and not (issecretvalue and issecretvalue(delay)) and delay ~= 0 then
      local delay_sign = '+'
      if delay < 0 then
        delay_sign = ''
      end
      if duration_text then
        return "|cffff0000%s%s|r %s",delay_sign,Round(delay,1),duration_text
      else
        return "|cffff0000%s%s|r",delay_sign,Round(delay,1)
      end
    elseif duration_text then
      return duration_text
    end
  end
end
return ConfigMode()]],
		},
	},
}

PitBull4_LuaTexts:SetModuleType("text_provider")
PitBull4_LuaTexts:SetName(L["Lua texts"])
PitBull4_LuaTexts:SetDescription(L["Text provider using Lua scripts to generate texts."])

do
	-- Build the event defaults
	local events = {
		-- Harcoded events basically the ones that aren't just unit=true ones
		['UNIT_PET_EXPERIENCE'] = {pet=true},
		['PLAYER_XP_UPDATE'] = {player=true},
		['ARTIFACT_XP_UPDATE'] = {player=true},
		['AZERITE_ITEM_EXPERIENCE_CHANGED'] = {player=true},
		['AZERITE_ITEM_POWER_LEVEL_CHANGED'] = {player=true},
		['AZERITE_EMPOWERED_ITEM_SELECTION_UPDATED'] = {player=true},
		['UPDATE_FACTION'] = {all=true},
		['UNIT_LEVEL'] = {all=true},

		-- They pass the unit but they don't provide the pairing (e.g.
		-- the target changes) so we'll miss updates if we don't update
		-- every text on every one of these events.  /sigh
		['UNIT_THREAT_LIST_UPDATE'] = {all=true},
		['UNIT_THREAT_SITUATION_UPDATE'] = {all=true},
	}

	-- Iterate the provided codes to fill in all the rest
	for base, codes in next, PROVIDED_CODES do
		for name, entry in next, codes do
			for event in next, entry.events do
				if not events[event] then
					events[event] = {unit=true}
				end
			end
		end
	end

	PitBull4_LuaTexts:SetDefaults({
		elements = {
			['**'] = {
				size = 1,
				attach_to = "root",
				location = "edge_top_left",
				position = 1,
				exists = false,
				code = "",
				events = {},
				enabled = true,
			}
		},
		first = true
	},
	{
		-- Global defaults
		events = events,
	})
end

-- These events should never have the event unregistered unless
-- the module is disabled.  In general they are needed for support
-- for things that cannot be cleaned on an as needed basis and
-- require very little actual processing time.
local protected_events = {
	["UNIT_SPELLCAST_SENT"] = true,
	["GROUP_ROSTER_UPDATE"] = true,
	["PLAYER_TARGET_CHANGED"] = true,
	["PLAYER_FOCUS_CHANGED"] = true,
	["INSTANCE_ENCOUNTER_ENGAGE_UNIT"] = true
}

-- Provide a way to update changed events so existing LuaTexts configs
-- continue to work transparently to end users.
local compat_event_map = {}
compat_event_map.UNIT_POWER = 'UNIT_POWER_UPDATE'
compat_event_map.UNIT_HEALTH_FREQUENT = 'UNIT_HEALTH'
compat_event_map.UNIT_HEALTHMAX = 'UNIT_MAXHEALTH'
compat_event_map.UNIT_MANA = 'UNIT_POWER_FREQUENT'
compat_event_map.UNIT_MAXMANA = 'UNIT_MAXPOWER'
compat_event_map.UNIT_RAGE = 'UNIT_POWER_FREQUENT'
compat_event_map.UNIT_MAXRAGE = 'UNIT_MAXPOWER'
compat_event_map.UNIT_ENERGY = 'UNIT_POWER_FREQUENT'
compat_event_map.UNIT_MAXENERGY = 'UNIT_MAXPOWER'
compat_event_map.UNIT_FOCUS = 'UNIT_POWER_FREQUENT'
compat_event_map.UNIT_MAXFOCUS = 'UNIT_MAXPOWER'
compat_event_map.UNIT_HAPPINESS = 'UNIT_MAXPOWER'
compat_event_map.UNIT_MAXHAPPINESS = 'UNIT_POWER_FREQUENT'
compat_event_map.UNIT_RUNIC_POWER = 'UNIT_POWER_FREQUENT'
compat_event_map.UNIT_MAXRUNIC_POWER = 'UNIT_MAXPOWER'
compat_event_map.UNIT_COMBO_POINTS = 'UNIT_POWER_FREQUENT'
compat_event_map.PARTY_MEMBERS_CHANGED = 'GROUP_ROSTER_UPDATE'
compat_event_map.RAID_ROSTER_UPDATE = 'GROUP_ROSTER_UPDATE'

local function update_events(events)
	for old_event, new_event in next, compat_event_map do
		local value = events[old_event]
		events[old_event] = nil
		if not events[new_event] and value then
			events[new_event] = value
		end
	end
	-- prune "false" and old invalid entries
	for event, value in next, events do
		if not value or not pcall(test_frame.RegisterEvent, test_frame, event) then
			events[event] = nil
		end
	end
end

local function fix_legacy_events()
	local sv = PitBull4.db:GetNamespace("LuaTexts").profiles
	for _, profile in next, sv do
		if profile.global and profile.global.events then
			update_events(profile.global.events)
		end
		local layouts = profile.layouts
		if layouts then
			for _, layout in next, layouts do
				local elements = layout.elements
				if elements then
					for _, text in next, elements do
						if text.events then
							update_events(text.events)
						end
					end
				end
			end
		end
	end
	test_frame:UnregisterAllEvents()
end

local function fix_power_texts()
	local sv = PitBull4.db:GetNamespace("LuaTexts").profiles
	for _, profile in next, sv do
		local layouts = profile.layouts
		if layouts then
			for _, layout in next, layouts do
				local elements = layout.elements
				if elements then
					for _, text in next, elements do
						-- add missing power events
						if text.code and text.code:find("Power(unit)", nil, true) then
							if not text.events then
								text.events = { ["UNIT_POWER_FREQUENT"] = true, ["UNIT_MAXPOWER"] = true }
							else
								if not text.events["UNIT_MAXPOWER"] then
									text.events["UNIT_MAXPOWER"] = true
								end
								if not text.events["UNIT_POWER_FREQUENT"] and not text.events["UNIT_POWER_UPDATE"] then
									text.events["UNIT_POWER_FREQUENT"] = true
								end
							end
						end
						-- add azerite events to artifact power texts
						if text.events and text.events["ARTIFACT_XP_UPDATE"] and not text.events["AZERITE_ITEM_EXPERIENCE_CHANGED"] then
							text.events['AZERITE_ITEM_EXPERIENCE_CHANGED'] = true
							text.events['AZERITE_ITEM_POWER_LEVEL_CHANGED'] = true
							text.events['AZERITE_EMPOWERED_ITEM_SELECTION_UPDATED'] = true
						end
					end
				end
			end
		end
	end
end

-- update pre-mop/pre-dragonflight default rep text for friendships
local function fix_rep_std_text()
	local sv = PitBull4.db:GetNamespace("LuaTexts").profiles
	for _, profile in next, sv do
		local layouts = profile.layouts
		if layouts then
			for _, layout in next, layouts do
				local elements = layout.elements
				if elements then
					for _, text in next, elements do
						if text.code and (text.code:find("GetWatchedFactionInfo", nil, true) or text.code:find("GetFriendshipReputation", nil, true)) then
							text.code = PROVIDED_CODES[L["Reputation"]][L["Standard"]].code
						end
					end
				end
			end
		end
	end
end

-- Patch 074: keep the Focus identity/Class line consistent with Target.
--
-- Older/custom profiles can use a dedicated Focus layout that predates the
-- maintained 12.1 IdentityDisplay path.  In that case Target may still have a
-- visible Lua:Class element while Focus has no corresponding element at all
-- (or an old disabled one), leaving level/classification/creature type absent.
--
-- Perform a one-time, profile-local repair: when Target and Focus use different
-- layouts and Focus lacks an enabled Class element, mirror Target's Class text
-- settings into the Focus layout.  This preserves the user's font/position/code
-- choices and avoids changing layouts where the Focus Class text is already
-- configured.  If Target has no explicit Class element, use the current stock
-- 12.1-safe IdentityDisplay preset as the fallback.
local function patch074_find_singleton_layout(unit_token)
	local main_db = PitBull4.db and PitBull4.db.profile
	local units = main_db and main_db.units
	if not units then
		return nil
	end

	for _, unit_db in pairs(units) do
		if unit_db and unit_db.unit == unit_token then
			return unit_db.layout or L["Normal"]
		end
	end
	return nil
end

local function patch074_focus_class_is_visible(element)
	return type(element) == "table" and element.exists == true and element.enabled ~= false
end

local function patch074_find_class_element(elements)
	if not elements then
		return nil, nil
	end

	local localized_key = "Lua:" .. L["Class"]
	local candidates = { "Lua:Class", localized_key }
	local seen = {}
	local fallback_key, fallback_element
	for i = 1, #candidates do
		local key = candidates[i]
		if not seen[key] then
			seen[key] = true
			local element = rawget(elements, key)
			if type(element) == "table" then
				if patch074_focus_class_is_visible(element) then
					return key, element
				end
				fallback_key, fallback_element = fallback_key or key, fallback_element or element
			end
		end
	end
	return fallback_key, fallback_element
end

local function patch082_is_identity_element(element)
	if not patch074_focus_class_is_visible(element) or type(element.code) ~= "string" then
		return false
	end
	local code = element.code
	return code:find("IdentityDisplay(unit", 1, true) ~= nil or code:find("IdentitySummary(unit", 1, true) ~= nil
end

local function patch082_find_any_identity_element(elements, except_key)
	if type(elements) ~= "table" then return nil, nil end
	for key, element in pairs(elements) do
		if key ~= except_key and patch082_is_identity_element(element) then
			return key, element
		end
	end
	return nil, nil
end

local function patch082_layout_is_shared_with_nonfocus(layout_name)
	local main_db = PitBull4.db and PitBull4.db.profile
	local units = main_db and main_db.units
	if type(units) ~= "table" then return false end
	for _, unit_db in pairs(units) do
		if unit_db and unit_db.unit ~= "focus" and (unit_db.layout or L["Normal"]) == layout_name then
			return true
		end
	end
	return false
end

local function patch074_repair_focus_identity_layout()
	local profile = PitBull4_LuaTexts.db and PitBull4_LuaTexts.db.profile
	if not profile or profile.lorenzo_patch074_focus_identity_migrated then
		return false
	end

	local layouts = profile.layouts
	if not layouts then
		return false
	end

	local target_layout = patch074_find_singleton_layout("target")
	local focus_layout = patch074_find_singleton_layout("focus")
	if not target_layout or not focus_layout then
		return false
	end

	-- Same layout means Target and Focus already share the exact same text
	-- configuration; there is nothing to migrate.
	if target_layout == focus_layout then
		profile.lorenzo_patch074_focus_identity_migrated = true
		return false
	end

	local target_layout_db = layouts[target_layout]
	local focus_layout_db = layouts[focus_layout]
	local target_elements = target_layout_db and target_layout_db.elements
	local focus_elements = focus_layout_db and focus_layout_db.elements
	if not focus_elements then
		return false
	end

	local focus_key, focus_class = patch074_find_class_element(focus_elements)
	if patch074_focus_class_is_visible(focus_class) then
		profile.lorenzo_patch074_focus_identity_migrated = true
		return false
	end

	-- Patch 082: P074 originally checked only the canonical Class slot. Custom
	-- profiles can already contain an equivalent IdentityDisplay text under a
	-- different name. Never inject another Class line in that case. Also never
	-- mutate a layout shared by Focus and another singleton classification.
	local existing_identity_key = patch082_find_any_identity_element(focus_elements, focus_key)
	if existing_identity_key or patch082_layout_is_shared_with_nonfocus(focus_layout) then
		profile.lorenzo_patch074_focus_identity_migrated = true
		return false
	end

	local target_key, target_class = patch074_find_class_element(target_elements)
	local replacement
	if patch074_focus_class_is_visible(target_class) then
		replacement = PitBull4.Utils.deep_copy(target_class)
	else
		replacement = {
			exists = true,
			enabled = true,
			code = PROVIDED_CODES[L["Class"]][L["Standard"]].code,
			events = PitBull4.Utils.deep_copy(PROVIDED_CODES[L["Class"]][L["Standard"]].events),
			attach_to = "PowerBar",
			location = "left",
			position = 1,
			size = 1,
		}
	end

	-- Keep the existing Focus key when one is present so we do not create a
	-- duplicate localized/canonical Class slot. Otherwise mirror Target's key.
	local destination_key = focus_key or target_key or ("Lua:" .. L["Class"])
	replacement.exists = true
	replacement.enabled = true
	replacement.code = replacement.code or PROVIDED_CODES[L["Class"]][L["Standard"]].code
	replacement.events = replacement.events or PitBull4.Utils.deep_copy(PROVIDED_CODES[L["Class"]][L["Standard"]].events)
	replacement.attach_to = replacement.attach_to or "PowerBar"
	replacement.location = replacement.location or "left"
	focus_elements[destination_key] = replacement

	profile.lorenzo_patch074_focus_identity_migrated = true
	return true
end

-- Patch 082: repair the specific duplicate identity line P074 could create in
-- existing profiles. P074 always wrote its injected copy into the canonical/
-- localized Class slot. If that slot is active AND another active IdentityDisplay
-- text already exists in the same Focus layout, disable only the Class-slot copy.
-- The pre-existing custom identity element is preserved.
local function patch082_cleanup_p074_duplicate_identity()
	local profile = PitBull4_LuaTexts.db and PitBull4_LuaTexts.db.profile
	if not profile or profile.lorenzo_patch082_identity_dedupe_done then
		return false
	end
	local layouts = profile.layouts
	local focus_layout = patch074_find_singleton_layout("focus")
	local focus_layout_db = layouts and focus_layout and layouts[focus_layout]
	local elements = focus_layout_db and focus_layout_db.elements
	if type(elements) ~= "table" then
		return false
	end

	local class_key, class_element = patch074_find_class_element(elements)
	if class_key and patch082_is_identity_element(class_element) then
		local other_key = patch082_find_any_identity_element(elements, class_key)
		if other_key then
			class_element.enabled = false
			class_element.exists = false
			profile.lorenzo_patch082_identity_dedupe_done = true
			return true
		end
	end

	profile.lorenzo_patch082_identity_dedupe_done = true
	return false
end

local timerframe = CreateFrame("Frame")
PitBull4_LuaTexts.timerframe = timerframe
timerframe:Hide()

function PitBull4_LuaTexts:SetCVar()
	predicted_health = GetCVarBool("predictedHealth")
end

function PitBull4_LuaTexts:OnInitialize()
	-- should probably switch to a global db version check/upgrade process
	-- this doesn't need to run every load
	fix_legacy_events()
	fix_rep_std_text()
	fix_power_texts()
	patch074_repair_focus_identity_layout()
	patch082_cleanup_p074_duplicate_identity()
end

function PitBull4_LuaTexts:OnProfileChanged()
	-- The namespace DB has already switched to the new profile when this callback
	-- runs. Apply the one-time Focus identity repair independently per profile.
	patch074_repair_focus_identity_layout()
	patch082_cleanup_p074_duplicate_identity()
end

function PitBull4_LuaTexts:OnEnable()
	-- On first login the main PitBull profile may finish creating singleton unit
	-- defaults after module initialization/profile callbacks. Retry once here so
	-- the migration is guaranteed to see the final Target/Focus layout mapping.
	patch074_repair_focus_identity_layout()
	patch082_cleanup_p074_duplicate_identity()

	-- UNIT_SPELLCAST_SENT has to always be registered so we can capture
	-- additional data not always available.
	-- self:RegisterUnitEvent("UNIT_SPELLCAST_SENT", nil, "player")
	self:RegisterEvent("GROUP_ROSTER_UPDATE")
	self:RegisterEvent("PLAYER_TARGET_CHANGED")
	self:RegisterEvent("PLAYER_FOCUS_CHANGED")
	self:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")

	-- Hooks to trap OnEnter/OnLeave for the frames.
	self:AddFrameScriptHook("OnEnter")
	self:AddFrameScriptHook("OnLeave")

	self:SecureHook("SetCVar")
	self:SetCVar()

	timerframe:Show()
end

function PitBull4_LuaTexts:OnDisable()
	self:RemoveFrameScriptHook("OnEnter")
	self:RemoveFrameScriptHook("OnLeave")
	timerframe:Hide()
end


-- Midnight 12.1: older saved Health LuaTexts may still calculate a percentage
-- from raw UnitHealth/UnitHealthMax values. Those values can be secret for
-- enemy/boss units, while UnitHealthPercent is the supported public path.

-- Patch 043: migrate the exact pre-12.1 stock Class LuaTexts that can still be
-- persisted in existing profiles.  Custom Class LuaTexts are intentionally left
-- untouched; only the historical built-in source strings are replaced.
local LEGACY_CLASS_STANDARD = [[
local dr,dg,db = DifficultyColor(unit)
local form = DruidForm(unit)
local classification = Classification(unit)
if UnitIsPlayer(unit) or (not UnitIsFriend(unit,"player") and not IsPet(unit)) then
  local cr,cg,cb = ClassColor(unit)
  if form then
    return "%s%s|cff%02x%02x%02x%s|r |cff%02x%02x%02x%s|r (%s) %s",classification or '',classification and ' ' or '',dr,dg,db,Level(unit),cr,cg,cb,Class(unit),form,SmartRace(unit) or ''
  else
    return "%s%s|cff%02x%02x%02x%s|r |cff%02x%02x%02x%s|r %s",classification or '',classification and ' ' or '',dr,dg,db,Level(unit),cr,cg,cb,Class(unit),SmartRace(unit) or ''
  end
else
  if form then
    return "%s%s|cff%02x%02x%02x%s|r (%s) %s",classification or '',classification and ' ' or '',dr,dg,db,Level(unit),form,SmartRace(unit) or ''
  else
    return "%s%s|cff%02x%02x%02x%s|r %s",classification or '',classification and ' ' or '',dr,dg,db,Level(unit),SmartRace(unit) or ''
  end
end]]

local LEGACY_CLASS_PLAYER_ONLY = [[
local dr,dg,db = DifficultyColor(unit)
local form = DruidForm(unit)
local classification = Classification(unit)
if UnitIsPlayer(unit) then
  local cr,cg,cb = ClassColor(unit)
  if form then
    return "%s%s|cff%02x%02x%02x%s|r |cff%02x%02x%02x%s|r (%s) %s",classification or '',classification and ' ' or '',dr,dg,db,Level(unit),cr,cg,cb,Class(unit),form,SmartRace(unit) or ''
  else
    return "%s%s|cff%02x%02x%02x%s|r |cff%02x%02x%02x%s|r %s",classification or '',classification and ' ' or '',dr,dg,db,Level(unit),cr,cg,cb,Class(unit),SmartRace(unit) or ''
  end
else
  if form then
    return "%s%s|cff%02x%02x%02x%s|r (%s) %s",classification or '',classification and ' ' or '',dr,dg,db,Level(unit),form,SmartRace(unit) or ''
  else
    return "%s%s|cff%02x%02x%02x%s|r %s",classification or '',classification and ' ' or '',dr,dg,db,Level(unit),SmartRace(unit) or ''
  end
end]]

-- Patches 041-048 temporarily persisted the stock Class scripts through
-- IdentitySummary(). Profiles saved during that window retain these source
-- strings even after upgrading. Migrate them to the current IdentityDisplay()
-- renderer so compound/restricted units use the maintained 12.1-safe path.
local PATCH041_CLASS_STANDARD = [[
return IdentitySummary(unit, false)]]
local PATCH041_CLASS_PLAYER_ONLY = [[
return IdentitySummary(unit, true)]]

local function normalize_legacy_class_code(code)
	if code == LEGACY_CLASS_STANDARD or code == PATCH041_CLASS_STANDARD then
		return PROVIDED_CODES[L["Class"]][L["Standard"]].code
	elseif code == LEGACY_CLASS_PLAYER_ONLY or code == PATCH041_CLASS_PLAYER_ONLY then
		return PROVIDED_CODES[L["Class"]][L["Player classes only"]].code
	end
	return code
end

local function normalize_legacy_health_percent_code(code)
	if type(code) ~= "string" then
		return code
	end
	return (code:gsub("Percent%s*%(%s*HP%s*%(%s*unit%s*%)%s*,%s*MaxHP%s*%(%s*unit%s*%)%s*%)", "PercentHP(unit)"))
end

-- Standard pre-12.1 Power texts formatted raw UnitPower values directly. Keep
-- custom code intact, but normalize the common stock expressions to helpers
-- that never format secret numbers in addon Lua.
local function normalize_legacy_power_code(code)
	if type(code) ~= "string" then
		return code
	end
	code = code:gsub('return%s+"%%s/%%s",%s*Power%s*%(%s*unit%s*%)%s*,%s*MaxPower%s*%(%s*unit%s*%)', 'local text = PowerText(unit)\nif text then return text end\nreturn "%%s%%%%",PercentPower(unit)')
	code = code:gsub('return%s+"%%s/%%s",%s*Short%s*%(%s*Power%s*%(%s*unit%s*%)%s*%)%s*,%s*Short%s*%(%s*MaxPower%s*%(%s*unit%s*%)%s*%)', 'local text = PowerText(unit,nil,true)\nif text then return text end\nreturn "%%s%%%%",PercentPower(unit)')
	code = code:gsub('return%s+"%%s/%%s%s*%|%|%s*%%s%%%%",%s*Power%s*%(%s*unit%s*%)%s*,%s*MaxPower%s*%(%s*unit%s*%)%s*,%s*PercentPower%s*%(%s*unit%s*%)', 'local text = PowerText(unit)\nif text then return "%%s || %%s%%%%",text,PercentPower(unit) end\nreturn "%%s%%%%",PercentPower(unit)')
	return code
end


local LEGACY_PVP_TIMER_CODE = [[
if unit == "player" then
  local pvp = PVPDuration()
  if pvp then
    return "|cffff0000%s|r",FormatDuration(pvp)
  end
end]]

local function normalize_legacy_pvp_timer_code(code)
	if code == LEGACY_PVP_TIMER_CODE then
		return PROVIDED_CODES[L["PVPTimer"]][L["Standard"]].code
	end
	return code
end

-- Patch 090: exact compatibility map for the stock Name LuaTexts shipped by
-- pre-Midnight PitBull releases. Older profiles persist the Lua source itself,
-- so installing the new addon does not replace these scripts automatically.
-- The old stock Name presets expected Angle() to expand into multiple format
-- values; the current secret-safe renderer forwards the complete suffix as one
-- SetFormattedText argument. Only exact historical stock source strings are
-- rewritten here. Custom Name LuaTexts are intentionally preserved.
local LEGACY_NAME_STANDARD = [[
return '%s %s%s%s',Name(unit),Angle(AFK(unit) or DND(unit))]]

local LEGACY_NAME_HOSTILITY = [[
local r,g,b = HostileColor(unit)
return '|cff%02x%02x%02x%s|r %s%s%s',r,g,b,Name(unit),Angle(AFK(unit) or DND(unit))]]

local LEGACY_NAME_CLASS = [[
local r,g,b = ClassColor(unit)
return '|cff%02x%02x%02x%s|r %s%s%s',r,g,b,Name(unit),Angle(AFK(unit) or DND(unit))]]

local LEGACY_NAME_LONG = [[
local r,g,b = ClassColor(unit)
return '%s |cff%02x%02x%02x%s|r %s%s%s',Level(unit),r,g,b,Name(unit),Angle(AFK(unit) or DND(unit))]]

local LEGACY_NAME_LONG_DRUID = [[
local r,g,b = ClassColor(unit)
local form = DruidForm(unit)
if form then
  return '%s |cff%02x%02x%02x%s|r (%s) %s%s%s',Level(unit),r,g,b,Name(unit),form,Angle(AFK(unit) or DND(unit))
else
  return '%s |cff%02x%02x%02x%s|r %s%s%s',Level(unit),r,g,b,Name(unit),Angle(AFK(unit) or DND(unit))
end]]

local LEGACY_NAME_CODE_MAP = {
	[LEGACY_NAME_STANDARD] = {
		code = PROVIDED_CODES[L["Name"]][L["Standard"]].code,
		events = PROVIDED_CODES[L["Name"]][L["Standard"]].events,
	},
	[LEGACY_NAME_HOSTILITY] = {
		code = PROVIDED_CODES[L["Name"]][L["Hostility-colored"]].code,
		events = PROVIDED_CODES[L["Name"]][L["Hostility-colored"]].events,
	},
	[LEGACY_NAME_CLASS] = {
		code = PROVIDED_CODES[L["Name"]][L["Class-colored"]].code,
		events = PROVIDED_CODES[L["Name"]][L["Class-colored"]].events,
	},
	[LEGACY_NAME_LONG] = {
		code = PROVIDED_CODES[L["Name"]][L["Long"]].code,
		events = PROVIDED_CODES[L["Name"]][L["Long"]].events,
	},
	[LEGACY_NAME_LONG_DRUID] = {
		code = PROVIDED_CODES[L["Name"]][L["Long w/ Druid form"]].code,
		events = PROVIDED_CODES[L["Name"]][L["Long w/ Druid form"]].events,
	},
}

local function normalize_legacy_name_code(code)
	local legacy = LEGACY_NAME_CODE_MAP[code]
	return legacy and legacy.code or code
end

local CURRENT_NAME_CODES = {}
for _, data in pairs(PROVIDED_CODES[L["Name"]]) do
	CURRENT_NAME_CODES[data.code] = true
end

local function profile_upgrade_slot_matches(name, canonical, localized_label)
	return name == canonical or name == ("Lua:" .. L[localized_label])
end

local function profile_upgrade_is_name_slot(name)
	return profile_upgrade_slot_matches(name, "Lua:Name", "Name")
end

local function profile_upgrade_is_class_slot(name)
	return profile_upgrade_slot_matches(name, "Lua:Class", "Class")
end

local function profile_upgrade_is_health_slot(name)
	return profile_upgrade_slot_matches(name, "Lua:Health", "Health")
end

local function profile_upgrade_is_power_slot(name)
	return profile_upgrade_slot_matches(name, "Lua:Power", "Power")
		or profile_upgrade_slot_matches(name, "Lua:Druid mana", "Druid mana")
		or profile_upgrade_slot_matches(name, "Lua:Alternate power", "Alternate power")
end

local function scan_or_upgrade_legacy_profile(do_upgrade)
	local profile = PitBull4_LuaTexts.db and PitBull4_LuaTexts.db.profile
	local result = { total = 0, name = 0, class = 0, health = 0, power = 0, custom_name = 0 }
	if type(profile) ~= "table" or type(profile.layouts) ~= "table" then
		return result
	end

	for _, layout in pairs(profile.layouts) do
		local elements = layout and layout.elements
		if type(elements) == "table" then
			for name, text in pairs(elements) do
				if type(text) == "table" and type(text.code) == "string" then
					local old_code = text.code
					local new_code = old_code
					local replacement_events
					local category

					if profile_upgrade_is_name_slot(name) then
						local legacy = LEGACY_NAME_CODE_MAP[old_code]
						if legacy then
							new_code = legacy.code
							replacement_events = legacy.events
							category = "name"
						elseif not CURRENT_NAME_CODES[old_code] and old_code:find("Name(unit)", 1, true) then
							result.custom_name = result.custom_name + 1
						end
					end

					if not category and profile_upgrade_is_class_slot(name) then
						local normalized = normalize_legacy_class_code(new_code)
						if normalized ~= new_code then
							new_code = normalized
							category = "class"
						end
					end
					if not category and profile_upgrade_is_health_slot(name) then
						local normalized = normalize_legacy_health_percent_code(new_code)
						if normalized ~= new_code then
							new_code = normalized
							category = "health"
						end
					end
					if not category and profile_upgrade_is_power_slot(name) then
						local normalized = normalize_legacy_power_code(new_code)
						if normalized ~= new_code then
							new_code = normalized
							category = "power"
						end
					end

					if category then
						result[category] = result[category] + 1
						result.total = result.total + 1
						if do_upgrade then
							text.code = new_code
							if replacement_events then
								text.events = PitBull4.Utils.deep_copy(replacement_events)
							elseif type(text.events) == "table" then
								update_events(text.events)
							end
						end
					end
				end
			end
		end
	end

	if do_upgrade and result.total > 0 then
		profile.lorenzo_patch090_profile_upgrade = _G.time and _G.time() or true
	end
	return result
end

function PitBull4_LuaTexts:ScanLegacyProfileCompatibility()
	return scan_or_upgrade_legacy_profile(false)
end

function PitBull4_LuaTexts:UpgradeLegacyProfileCompatibility()
	return scan_or_upgrade_legacy_profile(true)
end

local function code_uses_power_values(code)
	return type(code) == "string" and (code:find("Power%s*%(") or code:find("MaxPower%s*%(") or code:find("MissingPower%s*%("))
end

-- Patch 040: do not wait for a raw UnitPower expression to throw. Blizzard now
-- exposes public secrecy predicates specifically so addons can avoid touching
-- raw power values when the current unit/resource is restricted. This preflight
-- is intentionally limited to LuaTexts that still reference the legacy raw
-- Power/MaxPower/MissingPower helpers; stock 12.1-safe helper code is unaffected.
local function raw_power_is_restricted(unit, power_type)
	local secrets = C_Secrets
	if not secrets then
		return false
	end

	local restricted = false
	if secrets.ShouldUnitPowerBeSecret then
		local ok, value = pcall(secrets.ShouldUnitPowerBeSecret, unit, power_type)
		if ok and value == true then
			restricted = true
		end
	end
	if not restricted and secrets.ShouldUnitPowerMaxBeSecret then
		local ok, value = pcall(secrets.ShouldUnitPowerMaxBeSecret, unit, power_type)
		if ok and value == true then
			restricted = true
		end
	end
	return restricted
end

local function power_type_for_code(code)
	if code and code:find("ALTERNATE_POWER_INDEX", 1, true) then
		return ALTERNATE_POWER_INDEX
	elseif code and code:find("unit,0", 1, true) then
		return 0
	end
	return nil
end

local error_text do
	local text_errors = {}
	function error_text(message, func)
		-- ideally we'd just show it once per guid, but alas.
		if func then
			-- hack to fix the '?' as the name of the function pcalled
			message = message:gsub("'%?'",("'%s'"):format(func))
		end
		if not text_errors[message] then
			text_errors[message] = true
			geterrorhandler()(message)
		end
	end
end

local function set_text(font_string, ...)
	local success, err = ... -- varargs are a pcall result
	if not success then
		geterrorhandler()(err)
		-- text_error(("PitBull4_LuaTexts:%s:%s caused an error:\n%s"):format(font_string.frame.layout, font_string.luatexts_name, err))
		-- print("!!", font_string.frame.layout .. ":" .. font_string.luatexts_name)
		font_string:SetText("{err}")
	elseif err ~= nil then
		success, err = pcall(font_string.SetFormattedText, font_string, select(2,...))
		if not success then
			error_text(("PitBull4_LuaTexts:%s:%s caused an error:\n%s"):format(font_string.frame.layout, font_string.luatexts_name, err), "SetFormattedText")
			font_string:SetText("{err}")
		end
	else
		-- not enough parameters so just set an empty string
		font_string:SetText("")
	end
end

local get_cyrillic_fallback_font

local function set_font(font_string)
	local font, size = font_string:GetFont()

	-- Patch 073: when the previous update used the Cyrillic fallback, GetFont()
	-- returns that transient fallback rather than the layout's configured font.
	-- Re-resolve the configured font from the frame/text DB every update so a
	-- later Latin name immediately returns to the user's normal font.
	local frame = font_string.frame
	local text_db = font_string.db
	if frame and text_db and type(frame.GetFont) == "function" then
		local ok_font, configured_font, configured_size = pcall(frame.GetFont, frame, text_db.font, text_db.size)
		if ok_font and configured_font and configured_size then
			font = configured_font
			size = configured_size
		end
	end

	if font_string._pb4_cyrillic_name_fallback then
		font = get_cyrillic_fallback_font() or font
	end

	local success, err = pcall(font_string.SetFont, font_string, font, size, PitBull4_LuaTexts.outline)
	if not success then
		error_text(("PitBull4_LuaTexts:%s:%s caused an error when calling SetFont(%s,%s,%s):\n%s"):format(font_string.frame.layout, font_string.luatexts_name, tostring(font), tostring(size), tostring(PitBull4_LuaTexts.outline), err), "SetFont")
	end
end

local function set_alpha(font_string)
	if PitBull4_LuaTexts.secret_alpha ~= nil then
		local success, err = pcall(font_string.SetAlphaFromBoolean, font_string, PitBull4_LuaTexts.secret_alpha, PitBull4_LuaTexts.secret_alpha_if_true, PitBull4_LuaTexts.secret_alpha_if_false)
		if not success then
			error_text(("PitBull4_LuaTexts:%s:%s caused the following error when calling SetAlphaFromBoolean():\n%s"):format(font_string.frame.layout, font_string.luatexts_name, err), "SetAlphaFromBoolean")
		end
	else
		local success, err = pcall(font_string.SetAlpha, font_string, PitBull4_LuaTexts.alpha)
		if not success then
			error_text(("PitBull4_LuaTexts:%s:%s caused the following error when calling SetAlpha(%s):\n%s"):format(font_string.frame.layout, font_string.luatexts_name, tostring(PitBull4_LuaTexts.alpha), err), "SetAlpha")
		end
	end
end

-- LuaText slot names are persisted in profiles and therefore must not be
-- identified only through the current client's localized display strings.
-- Older/upstream profiles commonly store the canonical English names even on a
-- non-English client (for example "Lua:Class" and "Lua:Power").  Accept both
-- canonical persisted names and localized display names so 12.1 safety guards
-- work across profile upgrades and locale changes.
local lua_name = ("Lua:%s"):format(L["Name"])
local lua_class_name = ("Lua:%s"):format(L["Class"])
local lua_health_name = ("Lua:%s"):format(L["Health"])
local lua_power_name = ("Lua:%s"):format(L["Power"])
local lua_druid_mana_name = ("Lua:%s"):format(L["Druid mana"])
local lua_alternate_power_name = ("Lua:%s"):format(L["Alternate power"])

local function slot_name_matches(name, canonical, localized)
	return name == canonical or name == localized
end

local function is_name_text_name(name)
	return slot_name_matches(name, "Lua:Name", lua_name)
end


-- Patch 073: cross-locale Cyrillic name support.
--
-- PitBull normally applies the selected LibSharedMedia font as a raw font asset.
-- Many popular Latin-only fonts do not contain Cyrillic glyphs, which leaves
-- Russian player names as tofu/square boxes on non-Russian clients.
--
-- WoW 11.1+ exposes alphabet-specific Blizzard Font objects.  For public unit
-- names containing Cyrillic code points, keep the configured PitBull size and
-- outline but temporarily use Blizzard's Russian alphabet font asset.  Latin
-- names continue to use the user's configured font unchanged.
local cyrillic_fallback_font

local function contains_cyrillic_utf8(value)
	if type(value) ~= "string" or (issecretvalue and issecretvalue(value)) then
		return false
	end

	local length = #value
	local i = 1
	while i <= length do
		local first = value:byte(i)
		if first and first >= 0xD0 and first <= 0xD3 then
			local second = value:byte(i + 1)
			if second and second >= 0x80 and second <= 0xBF then
				return true
			end
		elseif first == 0xD4 then
			local second = value:byte(i + 1)
			if second and second >= 0x80 and second <= 0xAF then
				return true
			end
		end
		i = i + 1
	end

	return false
end

get_cyrillic_fallback_font = function()
	if cyrillic_fallback_font then
		return cyrillic_fallback_font
	end

	-- Prefer Blizzard's alphabet-aware font family so the client chooses its
	-- native Russian asset.  ChatFontNormal is intentionally used as the source
	-- because it is designed for cross-locale player/chat text.
	local candidates = {
		_G.ChatFontNormal,
		_G.GameFontNormal,
	}

	for i = 1, #candidates do
		local font_object = candidates[i]
		if font_object and type(font_object.GetFontObjectForAlphabet) == "function" then
			local ok_alphabet, russian_font = pcall(font_object.GetFontObjectForAlphabet, font_object, "russian")
			if ok_alphabet and russian_font and type(russian_font.GetFont) == "function" then
				local ok_font, font_file = pcall(russian_font.GetFont, russian_font)
				if ok_font and font_file then
					cyrillic_fallback_font = font_file
					return cyrillic_fallback_font
				end
			end
		end
	end

	-- Older/fallback clients: Arial Narrow is Blizzard's broadly compatible
	-- cross-locale UI/chat font on non-CJK clients.
	if _G.ChatFontNormal and type(_G.ChatFontNormal.GetFont) == "function" then
		local ok_font, font_file = pcall(_G.ChatFontNormal.GetFont, _G.ChatFontNormal)
		if ok_font and font_file then
			cyrillic_fallback_font = font_file
			return cyrillic_fallback_font
		end
	end

	cyrillic_fallback_font = "Fonts\\ARIALN.TTF"
	return cyrillic_fallback_font
end

local function update_cyrillic_name_fallback(font_string, name, unit)
	font_string._pb4_cyrillic_name_fallback = false

	if not is_name_text_name(name) then
		return
	end

	local frame = font_string.frame
	local layout_db = frame and frame.layout_db
	if layout_db and layout_db.cyrillic_name_fallback == false then
		return
	end

	local ok_name, unit_name = pcall(UnitName, unit)
	if not ok_name or unit_name == nil or (issecretvalue and issecretvalue(unit_name)) then
		return
	end

	font_string._pb4_cyrillic_name_fallback = contains_cyrillic_utf8(unit_name)
end

local function is_class_text_name(name)
	return slot_name_matches(name, "Lua:Class", lua_class_name)
end

local function is_health_text_name(name)
	return slot_name_matches(name, "Lua:Health", lua_health_name)
end

local function is_power_text_name(name)
	return slot_name_matches(name, "Lua:Power", lua_power_name)
end

local function is_druid_mana_text_name(name)
	return slot_name_matches(name, "Lua:Druid mana", lua_druid_mana_name)
end

local function is_alternate_power_text_name(name)
	return slot_name_matches(name, "Lua:Alternate power", lua_alternate_power_name)
end

local function is_resource_text_name(name)
	return is_power_text_name(name) or is_druid_mana_text_name(name) or is_alternate_power_text_name(name)
end

local function resource_power_type(name, code)
	if is_alternate_power_text_name(name) then
		return ALTERNATE_POWER_INDEX
	elseif is_druid_mana_text_name(name) then
		return 0
	end
	return power_type_for_code(code)
end

local function is_secret_value_error(err)
	if type(err) ~= "string" then
		return false
	end
	err = err:lower()
	return err:find("secret", 1, true) ~= nil or err:find("protected value", 1, true) ~= nil
end
local protected_class_codes = {}
for _, data in pairs(PROVIDED_CODES[L["Class"]]) do
	protected_class_codes[data.code] = true
end

local function set_protected_class_text(font_string, unit)
	-- Do not feed a secret identity string into a multi-purpose LuaText FontString.
	-- Doing so marks its Text aspect secret and can make later public updates harder
	-- to recover cleanly.  The normal full Class text is restored automatically as
	-- soon as Blizzard declassifies the unit identity.
	set_font(font_string)
	set_alpha(font_string)
	font_string:SetWordWrap(false)
	font_string:SetText("")
end

local function set_safe_class_summary(font_string, unit)
	local ScriptEnv = PitBull4_LuaTexts.ScriptEnv
	local ok, fmt, a, b, c, d, e, f, g, h, i, j, k, l, m, n, o = pcall(ScriptEnv.IdentityDisplay, unit, false)
	if ok and type(fmt) == "string" then
		-- SetFormattedText is the supported sink for 12.1 secret identity strings.
		-- Do not inspect any of the returned display arguments here.
		local shown = pcall(font_string.SetFormattedText, font_string, fmt, a, b, c, d, e, f, g, h, i, j, k, l, m, n, o)
		if not shown then
			font_string:SetText("")
		end
	else
		font_string:SetText("")
	end
end

-- Forever 030: preserve the selected stock Power text style when raw power
-- values are secret. The Patch090 fallback forced all restricted Power presets
-- to percentage. Raw numbers are passed directly to Blizzard's FontString sink
-- and are never compared, abbreviated, or otherwise inspected in addon Lua.
local stock_power_modes = {}
local function register_stock_power_modes(group_name)
	local group = PROVIDED_CODES[group_name]
	if not group then return end
	local mode_by_label = {
		[L["Absolute"]] = "absolute",
		[L["Absolute short"]] = "absolute_short",
		[L["Difference"]] = "difference",
		[L["Percent"]] = "percent",
		[L["Absolute and percent"]] = "absolute_percent",
		[L["Mini"]] = "mini",
		[L["Smart"]] = "smart",
	}
	for label, mode in pairs(mode_by_label) do
		local data = group[label]
		if data and type(data.code) == "string" then
			stock_power_modes[data.code] = mode
		end
	end
end
register_stock_power_modes(L["Power"])
register_stock_power_modes(L["Druid mana"])
register_stock_power_modes(L["Alternate power"])

local function stock_power_mode(code)
	return stock_power_modes[code]
end

local function raw_power_values_are_secret(unit, power_type)
	local ok_current, current = pcall(UnitPower, unit, power_type)
	local ok_maximum, maximum = pcall(UnitPowerMax, unit, power_type)
	local ok_missing, missing = pcall(UnitPowerMissing, unit, power_type)
	if ok_current and issecretvalue and issecretvalue(current) then return true end
	if ok_maximum and issecretvalue and issecretvalue(maximum) then return true end
	if ok_missing and issecretvalue and issecretvalue(missing) then return true end
	return raw_power_is_restricted(unit, power_type)
end

local function set_safe_stock_power_text(font_string, unit, power_type, mode)
	local ScriptEnv = PitBull4_LuaTexts.ScriptEnv
	if mode == "percent" then
		local ok, percent = pcall(ScriptEnv.PercentPower, unit, power_type)
		if ok and pcall(font_string.SetFormattedText, font_string, "%s%%", percent) then return true end
		font_string:SetText("")
		return true
	end

	local ok_current, current = pcall(UnitPower, unit, power_type)
	local ok_maximum, maximum = pcall(UnitPowerMax, unit, power_type)
	local ok_missing, missing = pcall(UnitPowerMissing, unit, power_type)

	local shown = false
	if mode == "absolute" and ok_current and ok_maximum then
		shown = pcall(font_string.SetFormattedText, font_string, "%s/%s", current, maximum)
	elseif mode == "absolute_short" and ok_current and ok_maximum then
		-- Secret values cannot be abbreviated safely in addon Lua; retain numeric
		-- display and send the exact values directly to the native sink.
		shown = pcall(font_string.SetFormattedText, font_string, "%s/%s", current, maximum)
	elseif mode == "absolute_percent" and ok_current and ok_maximum then
		local ok_percent, percent = pcall(ScriptEnv.PercentPower, unit, power_type)
		if ok_percent then
			shown = pcall(font_string.SetFormattedText, font_string, "%s/%s || %s%%", current, maximum, percent)
		end
	elseif mode == "difference" and ok_missing then
		shown = pcall(font_string.SetFormattedText, font_string, "-%s", missing)
	elseif mode == "mini" and ok_current then
		shown = pcall(font_string.SetFormattedText, font_string, "%s", current)
	elseif mode == "smart" and ok_missing then
		shown = pcall(font_string.SetFormattedText, font_string, "|cff7f7fff-%s|r", missing)
	end

	if not shown then
		local ok_percent, percent = pcall(ScriptEnv.PercentPower, unit, power_type)
		if not ok_percent or not pcall(font_string.SetFormattedText, font_string, "%s%%", percent) then
			font_string:SetText("")
		end
	end
	return true
end

local function update_text(font_string, event)
	if not texts[font_string] then return end
	if no_update[font_string] then return end
	local code = normalize_legacy_class_code(font_string.db.code)
	code = normalize_legacy_health_percent_code(code)
	code = normalize_legacy_power_code(code)
	code = normalize_legacy_pvp_timer_code(code)
	-- Saved profiles retain historical stock source after an addon upgrade.
	-- Angle now supplies one suffix string, not three formatting arguments.
	-- Reuse the exact stock compatibility map; never patch arbitrary Lua code
	-- or fill missing arguments that could mask a custom script's own error.
	if is_name_text_name(font_string.luatexts_name) then
		code = normalize_legacy_name_code(code)
	end
	if code ~= font_string.db.code then
		font_string.db.code = code
	end
	local frame = font_string.frame
	local name = font_string.luatexts_name
	local unit = frame.unit
	local func = func_cache[code]
	local ScriptEnv = PitBull4_LuaTexts.ScriptEnv

	if not unit or (frame.force_show and not UnitExists(unit) and name ~= L["Name"] and not is_name_text_name(name)) then
		font_string:SetFormattedText("{%s}", font_string.luatexts_name)
		return
	end

	if not func then
		-- Doesn't exist in the cache so we build it
		local lua_string = ("return function(unit) %s end"):format(code)
		local lua_string_name = ("PitBull4_LuaTexts:%s:%s"):format(frame.layout, font_string.luatexts_name)
		local create_func, err = loadstring(lua_string, lua_string_name)
		if create_func then
			-- note the following call is always safe, the only actual code executing is the
			-- return of the function wrapper that's hard coded above.  So no error handling
			-- needed.
			func = create_func()
			setfenv(func, ScriptEnv)
			func_cache[code] = func
		else
			geterrorhandler()(err)
			font_string:SetText("{err}")
			return
		end
	end

	-- Put the font_string and event into the ScriptEnv before running the
	-- user function so we can have access to it without actually requiring
	-- it to be passed to our utility functions.
	ScriptEnv.font_string = font_string
	ScriptEnv.event = event

	-- Set alpha and outline to default values
	PitBull4_LuaTexts.alpha = 1
	PitBull4_LuaTexts.outline = nil
	PitBull4_LuaTexts.word_wrap = nil

	PitBull4_LuaTexts.secret_alpha = nil
	PitBull4_LuaTexts.secret_alpha_if_true = nil
	PitBull4_LuaTexts.secret_alpha_if_false = nil

	-- Patch 073: determine the Lua:Name font from the public unit name only.
	-- Secret names are never inspected and simply keep the configured font.
	update_cyrillic_name_fallback(font_string, name, unit)

	-- Patch 047: do not blank every Class LuaText merely because Blizzard marks
	-- the unit's broad identity as restricted. The stock 12.1 renderers are
	-- deliberately field-safe and can still use public components such as
	-- classId, level, classification and creature type. For custom Class code,
	-- avoid executing potentially unsafe identity logic while restricted and use
	-- the hardened stock summary instead.
	if is_class_text_name(name) and PitBull4.Utils.IsUnitIdentitySecret(unit) and not protected_class_codes[code] then
		set_safe_class_summary(font_string, unit)
		set_font(font_string)
		set_alpha(font_string)
		font_string:SetWordWrap(not not PitBull4_LuaTexts.word_wrap)
		return
	end

	-- Patch 060: a no-resource PowerBar may intentionally exist only as an
	-- invisible layout/attachment anchor so Lua:Class remains visible. Suppress
	-- the Power LuaText itself in that state; otherwise it would still render 0%.
	if is_power_text_name(name) and frame._pb4_no_resource_power_anchor then
		font_string:SetText("")
		set_font(font_string)
		set_alpha(font_string)
		font_string:SetWordWrap(not not PitBull4_LuaTexts.word_wrap)
		return
	end

	-- Forever 030: stock Power presets retain their configured display mode even
	-- when Blizzard protects the raw values. This must run before Patch 040's
	-- generic legacy/custom fallback, which intentionally degrades to percentage.
	if is_resource_text_name(name) then
		local mode = stock_power_mode(code)
		local power_type = resource_power_type(name, code)
		if mode and raw_power_values_are_secret(unit, power_type) then
			set_safe_stock_power_text(font_string, unit, power_type, mode)
			set_font(font_string)
			set_alpha(font_string)
			font_string:SetWordWrap(not not PitBull4_LuaTexts.word_wrap)
			return
		end
	end

	-- Patch 040: preflight legacy/custom raw Power LuaTexts before executing them.
	-- If Blizzard says UnitPower or UnitPowerMax is restricted, running the LuaText
	-- would itself perform forbidden comparisons/formatting before our post-error
	-- fallback can help. Skip that code entirely and render only the supported
	-- percentage result.
	if code_uses_power_values(code) then
		local power_type = power_type_for_code(code)
		if raw_power_is_restricted(unit, power_type) then
			local percent_ok, percent = pcall(ScriptEnv.PercentPower, unit, power_type)
			if percent_ok and percent ~= nil then
				-- FontString:SetFormattedText is an AllowedWhenTainted secret sink.
				-- Passing a secret percentage is supported and marks only the Text aspect.
				local display_ok = pcall(font_string.SetFormattedText, font_string, "%s%%", percent)
				if not display_ok then
					font_string:SetText("")
				end
			else
				font_string:SetText("")
			end
			set_font(font_string)
			set_alpha(font_string)
			font_string:SetWordWrap(not not PitBull4_LuaTexts.word_wrap)
			return
		end
	end

	local ok, a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p = pcall(func, unit)
	if not ok and is_health_text_name(name) and type(a) == "string" and a:find("Percent cannot be used with secret values.", 1, true) then
		-- Do not spam BugSack for a legacy/custom Health LuaText that still reached
		-- Percent(rawHealth, rawMaxHealth). Render Blizzard's safe percentage instead.
		local percent_ok, percent = pcall(ScriptEnv.PercentHP, unit)
		if percent_ok then
			pcall(font_string.SetFormattedText, font_string, "%s%%", percent)
		else
			font_string:SetText("")
		end
	elseif is_class_text_name(name) and
		((not ok) or (ok and hasanysecretvalues(a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p))) then
		-- The Class slot is presentation-only. Existing profiles can contain many
		-- historical variants of the stock script, and 12.1 may fail them through
		-- identity-adjacent APIs whose error text is not consistently labelled
		-- "secret". Any execution failure in this specific slot therefore falls
		-- back to the hardened stock renderer instead of exposing {err}. Unrelated
		-- LuaText slots retain normal error reporting.
		set_safe_class_summary(font_string, unit)
	elseif (is_resource_text_name(name) or code_uses_power_values(code)) and
		(not ok and is_secret_value_error(a)) then
		-- Only recover from a LuaText that actually errored while touching a secret
		-- resource. Successful secret return values are valid: SetFormattedText can
		-- consume them directly and will mark the FontString Text aspect secret.
		local percent_ok, percent = pcall(ScriptEnv.PercentPower, unit, resource_power_type(name, code))
		if percent_ok and percent ~= nil then
			local display_ok = pcall(font_string.SetFormattedText, font_string, "%s%%", percent)
			if not display_ok then
				font_string:SetText("")
			end
		else
			font_string:SetText("")
		end
	else
		set_text(font_string, ok, a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p)
	end
	set_font(font_string)
	set_alpha(font_string)
	font_string:SetWordWrap(not not PitBull4_LuaTexts.word_wrap)
end

-- local next_spell, next_target
-- function PitBull4_LuaTexts:UNIT_SPELLCAST_SENT(event, unit, target, _, spell_id)
-- 	if not issecretvalue(target) then
-- 		next_spell = spell_id
-- 		next_target = target
-- 		self:OnEvent(event, unit)
-- 	end
-- end

local function copy(t)
	local n = {}
	for k,v in pairs(t) do
		n[k] = v
	end
	return n
end

local function update_cast_data(event, unit, event_cast_id, interrupted_by)
	local spell, _, _, _, _, _, _, uninterruptible, _, cast_id, delay = UnitCastingInfo(unit)
	local channeling = false
	local duration
	if spell then
		duration = UnitCastingDuration(unit)
	else
		local is_empowered
		spell, _, _, _, _, _, uninterruptible, _, is_empowered, _, cast_id  = UnitChannelInfo(unit)
		if is_empowered then
			channeling = true
			duration = UnitEmpoweredChannelDuration(unit)
		elseif spell then
			channeling = true
			duration = UnitChannelDuration(unit)
		end
	end

	local id = cast_id or event_cast_id

	-- Cast IDs can collide between different units in Midnight/12.x.  Store cast
	-- text state per unit token so CastData("player") can never resolve to
	-- party1/party2 data with the same cast ID.
	local data = cast_data[unit]
	if not spell and not id then
		if data then
			cast_data[unit] = del(data)
		end
		unit_cast_ids[unit] = nil
		return
	end

	unit_cast_ids[unit] = unit
	if not data then
		data = new()
		cast_data[unit] = data
	end

	if interrupted_by then
		data.interrupted_by = interrupted_by
	end
	if event == "UNIT_SPELLCAST_FAILED" then
		data.stop_message = _G.FAILED
	elseif event == "UNIT_SPELLCAST_INTERRUPTED" or interrupted_by then
		data.stop_message = _G.INTERRUPTED
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		-- Sometimes the interrupt event happens just before the
		-- success event so clear the stop_message if we get succeded.
		data.stop_message = nil
	end

	if spell then
		data.spell = spell
		data.duration = duration
		-- if unit == "player" and spell_id == next_spell then
		-- 	data.target = next_target
		-- end

		data.casting = not channeling
		data.channeling = channeling
		data.uninterruptible = uninterruptible

		if issecretvalue and issecretvalue(delay) then
			data.delay = nil
		else
			data.delay = delay or 0
		end
		data.cast_id = id

		data.stop_time = nil
		-- data.stop_message = nil
		return
	end
	if not data.spell then
		cast_data[unit] = del(data)
		return
	end

	data.casting = false
	data.channeling = false
	if not data.stop_time then
		data.stop_time = GetTime()
	end
end

local tmp = {}
local function fix_cast_data()
	local current_time = GetTime()
	for unit_key in next, cast_data do
		tmp[#tmp + 1] = unit_key
	end

	for _, unit_key in next, tmp do
		local data = cast_data[unit_key]
		if data.stop_time then
			if data.stop_time - current_time + 1 <= 0 then
				cast_data[unit_key] = del(data)
				unit_cast_ids[unit_key] = nil
			end
		elseif not data.casting and not data.channeling then
			cast_data[unit_key] = del(data)
			unit_cast_ids[unit_key] = nil
		end

		-- local found = false
		-- for font_string in pairs(spell_cast_cache) do
		-- 	if unit == font_string.frame.unit then
		-- 		found = true
		-- 		to_update[font_string] = 0 -- update now
		-- 	end
		-- end
		-- if not found and cast_data[cast_id] then
		-- 	cast_data[cast_id] = del(data)
		-- end
	end

	for font_string in next, spell_cast_cache do
		to_update[font_string] = 0
	end

	if not next(cast_data) then
		wipe(unit_cast_ids)
	end
	wipe(tmp)
end

local compare_units

local function update_texts_for_unit(unit, event)
	for font_string in pairs(texts) do
		local frame = font_string.frame
		if frame and compare_units(frame.unit, unit) then
			update_text(font_string, event or "_unit_refresh")
		end
	end
end

local function schedule_texts_for_unit(unit, delay, event)
	for font_string in pairs(texts) do
		local frame = font_string.frame
		if frame and compare_units(frame.unit, unit) then
			to_update[font_string] = delay or 0
		end
	end
end

function PitBull4_LuaTexts:PLAYER_TARGET_CHANGED(event)
	update_cast_data(nil, "target")
	update_texts_for_unit("target", event)
	update_texts_for_unit("targettarget", event)
	schedule_texts_for_unit("target", 0.08, event)
	schedule_texts_for_unit("target", 0.30, event)
	schedule_texts_for_unit("targettarget", 0.08, event)
	self:OnEvent(event)
end

function PitBull4_LuaTexts:PLAYER_FOCUS_CHANGED(event)
	update_cast_data(nil, "focus")
	update_texts_for_unit("focus", event)
	update_texts_for_unit("focustarget", event)
	schedule_texts_for_unit("focus", 0.08, event)
	schedule_texts_for_unit("focus", 0.30, event)
	schedule_texts_for_unit("focustarget", 0.08, event)
	self:OnEvent(event)
end

function PitBull4_LuaTexts:INSTANCE_ENCOUNTER_ENGAGE_UNIT(event)
	-- Keep this in sync with PitBull4.Utils.GetBestUnitID(), which registers
	-- boss unit IDs up to MAX_BOSS_FRAMES.
	for i = 1, _G.MAX_BOSS_FRAMES or 5 do
		update_cast_data(nil, ("boss%d"):format(i))
	end
	self:OnEvent(event)
end

function compare_units(unit_a, unit_b)
	if not unit_a or not unit_b then
		return false
	end
	if ShouldUnitComparisonBeSecret then
		local ok_secret, secret = pcall(ShouldUnitComparisonBeSecret, unit_a, unit_b)
		if ok_secret and secret then
			return false
		end
	end
	if UnitIsUnit then
		local ok, same = pcall(UnitIsUnit, unit_a, unit_b)
		if ok then
			return same and true or false
		end
	end
	local ok_equal, equal = pcall(function() return unit_a == unit_b end)
	return ok_equal and equal or false
end

local first = true
local function update_timers()
	if first then
		first = false
		PitBull4_LuaTexts:GROUP_ROSTER_UPDATE()
	end
	for unit, guid in pairs(group_members) do
		if not UnitIsConnected(unit) then
			if not offline_times[guid] then
				offline_times[guid] = GetTime()
				for font_string in next, offline_cache do
					if compare_units(font_string.frame.unit, unit) then
						to_update[font_string] = 0
					end
				end
			end
			afk_times[guid] = nil
			if dnd[guid] then
				dnd[guid] = nil
				for font_string in next, dnd_cache do
					if compare_units(font_string.frame.unit, unit) then
						to_update[font_string] = 0
					end
				end
			end
		elseif InChatMessagingLockdown() then
			offline_times[guid] = nil
			afk_times[guid] = nil -- UpdateIn will clear it
			if dnd[guid] then
				dnd[guid] = nil
				for font_string in next, dnd_cache do
					if compare_units(font_string.frame.unit, unit) then
						to_update[font_string] = 0
					end
				end
			end
		else
			offline_times[guid] = nil
			if UnitIsAFK(unit) then
				if not afk_times[guid] then
					afk_times[guid] = GetTime()
					for font_string in next, afk_cache do
						if compare_units(font_string.frame.unit, unit) then
							to_update[font_string] = 0
						end
					end
				end
			else
				afk_times[guid] = nil
				local dnd_change = false
				if UnitIsDND(unit) then
					if not dnd[guid] then
						dnd[guid] = true
						dnd_change = true
					end
				else
					if dnd[guid] then
						dnd[guid] = nil
						dnd_change = true
					end
				end
				if dnd_change then
					for font_string in next, dnd_cache do
						if compare_units(font_string.frame.unit, unit) then
							to_update[font_string] = 0
						end
					end
				end
			end
		end
		if UnitIsDeadOrGhost(unit) then
			if not dead_times[guid] then
				dead_times[guid] = GetTime()
				for font_string in next, dead_cache do
					if compare_units(font_string.frame.unit, unit) then
						to_update[font_string] = 0
					end
				end
			end
		else
			dead_times[guid] = nil
		end
	end
end

function PitBull4_LuaTexts:GROUP_ROSTER_UPDATE(event)
  local prefix, min, max = "raid", 1, GetNumGroupMembers()
	if not IsInRaid() then
		prefix, min = "party", 0
	end
	if max == 0 then
		-- not in a raid or a party
		wipe(group_members)
		group_members["player"] = player_guid
		wipe(offline_times)
		wipe(dead_times)
		wipe(afk_times)
		return
	end

	wipe(group_members)
	for i = min, max do
		local unit
		if i == 0 then
			unit = 'player'
		else
			unit = prefix .. i
		end
		local guid = UnitGUID(unit)
		group_members[unit] = guid

		if guid then
			tmp[guid] = true
		end
	end

	-- Cleanup any timers that reference people no longer in the party
	for guid in pairs(offline_times) do
		if not tmp[guid] then
			offline_times[guid] = nil
		end
	end
	for guid in pairs(dead_times) do
		if not tmp[guid] then
			dead_times[guid] = nil
		end
	end
	for guid in pairs(afk_times) do
		if not tmp[guid] then
			afk_times[guid] = nil
		end
	end
	wipe(tmp)

	self:OnEvent(event)
end

function PitBull4_LuaTexts:OnEvent(event, unit, ...)
	local event_entry = event_cache[event]
	if not event_entry then return end
	local event_config = self.db.profile.global.events[event]
	local all, by_unit, player, pet

	if event_config then
		all, by_unit = event_config.all, event_config.unit
		player, pet = event_config.player, event_config.pet
	else
		-- Sucks but if for some reason the event entry is missing update all
		all = true
	end

	if event == "PLAYER_FLAGS_CHANGED" then
		update_timers()
	elseif string.sub(event,1,15) == "UNIT_SPELLCAST_" and event ~= "UNIT_SPELLCAST_SENT" then
		-- spell casting events need to go through
		local _, interrupted_by, cast_id
		if event == "UNIT_SPELLCAST_CHANNEL_STOP" or event == "UNIT_SPELLCAST_INTERRUPTED" then
			_, _, interrupted_by, cast_id = ...
		elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
			_, _, _, interrupted_by, cast_id = ...
		else
			_, _, cast_id = ...
		end
		update_cast_data(event, unit, cast_id, interrupted_by)
	end

	for font_string in pairs(event_entry) do
		local fs_unit = font_string.frame.unit
		local by_unit_match = unit and by_unit and compare_units(fs_unit, unit)
		local player_match = unit and player and compare_units(unit, "player")
		local pet_match = unit and pet and (compare_units(fs_unit, "pet") or compare_units(fs_unit, "vehicle"))
		if all or font_string.frame.is_wacky or by_unit_match or player_match or pet_match then
			update_text(font_string, event)
		end
	end
end

function PitBull4_LuaTexts:OnEnter(frame)
	self.mouseover = frame
	for font_string, cache_frame in pairs(mouseover_check_cache) do
		if frame == cache_frame then
			update_text(font_string, "_mouseover")
		end
	end
end

function PitBull4_LuaTexts:OnLeave(frame)
	self.mouseover = nil
	for font_string, cache_frame in pairs(mouseover_check_cache) do
		if frame == cache_frame then
			update_text(font_string, "_mouseover")
		end
	end
end

-- Timed updates
local timer = 0
timerframe:SetScript("OnUpdate", function(self, elapsed)
	-- Fast updates for healthbars
	if predicted_health and next(hp_cache) then
		for font_string in pairs(hp_cache) do
			to_update[font_string] = 0
		end
	end

  -- cast text
	fix_cast_data()

	-- Update the timers once a second
	timer = timer + elapsed
	if timer > 1 then
		timer = 0
		update_timers()
	end

	-- Look for frames to update.  time values of less than
	-- or equal to zero update the frame, otherwise we simply
	-- subtract the elapsed time and update the time left.
	for font_string,time in pairs(to_update) do
		time = time - elapsed
		if time <= 0 then
			to_update[font_string] = nil
			update_text(font_string,"_timer")
		else
			to_update[font_string] = time
		end
	end
end)

function PitBull4_LuaTexts:OnNewLayout(layout)
	local layout_db = self.db.profile.layouts[layout]

	if not layout_db.first then
		return
	end
	layout_db.first = false

	local text_elements = layout_db.elements
	for k in pairs(text_elements) do
		text_elements[k] = nil
	end
	for name, data in pairs {
		["Lua:"..L["Name"]] = {
			code = PROVIDED_CODES[L["Name"]][L["Standard"]].code,
			events = copy(PROVIDED_CODES[L["Name"]][L["Standard"]].events),
			attach_to = "HealthBar",
			location = "left"
		},
		["Lua:"..L["Health"]] = {
			code = PROVIDED_CODES[L["Health"]][L["Absolute and percent"]].code,
			events = copy(PROVIDED_CODES[L["Health"]][L["Absolute and percent"]].events),
			attach_to = "HealthBar",
			location = "right"
		},
		["Lua:"..L["Class"]] = {
			code = PROVIDED_CODES[L["Class"]][L["Standard"]].code,
			events = copy(PROVIDED_CODES[L["Class"]][L["Standard"]].events),
			attach_to = "PowerBar",
			location = "left"
		},
		["Lua:"..L["Power"]] = {
			code = PROVIDED_CODES[L["Power"]][L["Absolute"]].code,
			events = copy(PROVIDED_CODES[L["Power"]][L["Absolute"]].events),
			attach_to = "PowerBar",
			location = "right"
		},
		["Lua:"..L["Reputation"]] = {
			code = PROVIDED_CODES[L["Reputation"]][L["Standard"]].code,
			events = copy(PROVIDED_CODES[L["Reputation"]][L["Standard"]].events),
			attach_to = "ReputationBar",
			location = "center"
		},
		["Lua:"..L["Cast"]] = {
			code = PROVIDED_CODES[L["Cast"]][L["Standard name"]].code,
			events = copy(PROVIDED_CODES[L["Cast"]][L["Standard time"]].events),
			attach_to = "CastBar",
			location = "left"
		},
		["Lua:"..L["Cast time"]] = {
			code = PROVIDED_CODES[L["Cast"]][L["Standard time"]].code,
			events = copy(PROVIDED_CODES[L["Cast"]][L["Standard name"]].events),
			attach_to = "CastBar",
			location = "right"
		},
		["Lua:"..L["Experience"]] = {
			code = PROVIDED_CODES[L["Experience"]][L["Standard"]].code,
			events = copy(PROVIDED_CODES[L["Experience"]][L["Standard"]].events),
			attach_to = "ExperienceBar",
			location = "center"
		},
		["Lua:"..L["Threat"]] = {
			code = PROVIDED_CODES[L["Threat"]][L["Percent"]].code,
			events = copy(PROVIDED_CODES[L["Threat"]][L["Percent"]].events),
			attach_to = "ThreatBar",
			location = "center"
		},
		["Lua:"..L["Druid mana"]] = {
			code = PROVIDED_CODES[L["Druid mana"]][L["Absolute"]].code,
			events = copy(PROVIDED_CODES[L["Druid mana"]][L["Absolute"]].events),
			attach_to = "AltManaBar",
			location = "center"
		},
		["Lua:"..L["PVPTimer"]] = {
			code = PROVIDED_CODES[L["PVPTimer"]][L["Standard"]].code,
			events = copy(PROVIDED_CODES[L["PVPTimer"]][L["Standard"]].events),
			location = "out_right_top"
		},
		["Lua:"..L["Alternate power"]] = {
			code = PROVIDED_CODES[L["Alternate power"]][L["Percent"]].code,
			events = copy(PROVIDED_CODES[L["Alternate power"]][L["Percent"]].events),
			attach_to = "AltPowerBar",
			location = "right"
		},
		["Lua:"..L["Artifact power"]] = {
			code = PROVIDED_CODES[L["Artifact power"]][L["Absolute"]].code,
			events = copy(PROVIDED_CODES[L["Artifact power"]][L["Absolute"]].events),
			attach_to = "ArtifactPowerBar",
			location = "center"
		},
	} do
		local text_db = text_elements[name]
		text_db.exists = true
		for k, v in pairs(data) do
			text_db[k] = v
		end
	end
end

local function event_cache_insert(event, font_string)
	local event_entry = event_cache[event]
	if not event_entry then
		event_entry = {}
		event_cache[event] = event_entry
		if not protected_events[event] then
			PitBull4_LuaTexts:RegisterEvent(event, "OnEvent")
		end
	end
	event_entry[font_string] = true
end

function PitBull4_LuaTexts:AddFontString(frame, font_string, name, data)
	local db = font_string.db

	no_update[font_string] = nil
	font_string:Show()
	-- This font_string is already assigned to us.  So do nothing but
	-- update the text.
	if texts[font_string] then
		update_text(font_string,"_update")
		if spell_cast_cache[font_string]  then
			-- The actual object the frame is pointing at may have changed
			-- or this may be a wacky unit that we don't get events for so
			-- we need to check the cast info anyway.
			update_cast_data(nil,frame.unit)
		end
		return true
	end

	-- Setup the font_string
	texts[font_string] = true
	font_string.frame = frame
	font_string.luatexts_name = name
	for event, enabled in next, db.events do
		if enabled then
			event_cache_insert(event, font_string)
		end
	end

	update_text(font_string,"_new")

	if spell_cast_cache[font_string] then
		-- If the font_string is looking to display spell cast
		-- info update the cast_data that we didn't have becuase
		-- we may not have had events for it turned on.  The
		-- timed update will actually draw the data on the frame
		-- later.
		update_cast_data(nil,frame.unit)
	end

	return true
end

function PitBull4_LuaTexts:RemoveFontString(font_string)
	-- Remove the font_string from the event_cache
	for event,entry in pairs(event_cache) do
		entry[font_string] = nil
		-- Nobody wants this event so stop watching it.
		if not next(entry) then
			if not protected_events[event] then
				self:UnregisterEvent(event)
			end
			event_cache[event] = nil
		end
	end

	power_cache[font_string] = nil
	hp_cache[font_string] = nil
	mouseover_check_cache[font_string] = nil
	spell_cast_cache[font_string] = nil
	to_update[font_string] = nil
	afk_cache[font_string] = nil
	dnd_cache[font_string] = nil
	offline_cache[font_string] = nil
	dead_cache[font_string] = nil
	if not next(mouseover_check_cache) then
		self.mouseover = nil
	end

	font_string.frame = nil
	texts[font_string] = nil
end

-- When a frame is hidden stop updating any texts
-- attached to it.  When it is shown it will be
-- updated again and cause everything to be put
-- back.
function PitBull4_LuaTexts:OnHide(frame)
	for font_string in pairs(texts) do
		if font_string.frame == frame then
			no_update[font_string] = true
			power_cache[font_string] = nil
			hp_cache[font_string] = nil
			mouseover_check_cache[font_string] = nil
			spell_cast_cache[font_string] = nil
			to_update[font_string] = nil
			afk_cache[font_string] = nil
			dnd_cache[font_string] = nil
			offline_cache[font_string] = nil
			dead_cache[font_string] = nil
			if not next(mouseover_check_cache) then
				self.mouseover = nil
			end
			font_string:Hide()
		end
	end
end

-- Handle updating after a config change
local function update()
	local layout = PitBull4.Options.GetCurrentLayout()

	for frame in PitBull4:IterateFramesForLayout(layout) do
		PitBull4_LuaTexts:ForceTextUpdate(frame)
	end
end

-- Event validation
local validate_timer = nil
local function ClearStatusText()
	local frame = LibStub("AceConfigDialog-3.0").OpenFrames["PitBull4"]
	if frame then
		local user = frame:GetUserDataTable()
		user.rootframe:SetStatusText("")
	end
end

PitBull4_LuaTexts:SetLayoutOptionsFunction(function(self)
	local values = {}
	local value_key_to_entry = {}
	values[""] = L["Custom"]
	value_key_to_entry[""] = {
		code = "",
		events = {},
	}
	for base, codes in pairs(PROVIDED_CODES) do
		for name, entry in pairs(codes) do
			local key = ("%s: %s"):format(base, name)
			values[key] = key
			value_key_to_entry[key] = entry
		end
	end

	return 'default_codes', {
		type = 'select',
		name = L["Code"],
		desc = L["Some codes provided for you."],
		get = function(info)
			local db = PitBull4.Options.GetTextLayoutDB()
			local code = db.code
			for k, preset_entry in pairs(value_key_to_entry) do
				if preset_entry.code == code then
					local preset_events = preset_entry.events
					local events = db.events
					local match = true
					for event,flag in pairs(events) do
						if preset_events[event] ~= flag then
							match = false
						end
					end
					for event,flag in pairs(preset_events) do
						if flag ~= events[event] then
							match = false
						end
					end
					if match then
						return k
					end
				end
			end
			return ""
		end,
		set = function(info, value)
			local entry = value_key_to_entry[value]
			local db = PitBull4.Options.GetTextLayoutDB()
			db.code = entry.code
			db.events = copy(entry.events)

			update()
		end,
		values = values,
		width = 'double',
	}, 'code', {
		type = 'input',
		name = L["Code"],
		desc = L["Enter a Lua script."],
		get = function(info)
			return PitBull4.Options.GetTextLayoutDB().code:gsub("|","||")
		end,
		set = function(info, value)
			local db = PitBull4.Options.GetTextLayoutDB()
			func_cache[db.code] = nil
			db.code = value:gsub("||","|")
			update()
		end,
		multiline = true,
		width = 'full',
	}, 'events', {
		type = 'multiselect',
		dialogControl = 'Dropdown',
		name = L["Events"],
		desc = L["Events to cause the text to update."],
		get = function(info,key)
			return PitBull4.Options.GetTextLayoutDB().events[key]
		end,
		set = function(info,key,value)
			local events = PitBull4.Options.GetTextLayoutDB().events
			events[key] = value or nil
			update()
		end,
		width = 'double',
		values = function(info)
			local t = {}
			for event in pairs(self.db.profile.global.events) do
				t[event] = event
			end
			return t
		end,
	}
end)

local CURRENT_EVENT
PitBull4_LuaTexts:SetGlobalOptionsFunction(function(self)
	local update_for_values = {
		all = L["All"],
		player = L["Player"],
		pet = L["Pet"],
		unit = L["Unit passed in arg1 of event"],
	}
	if not CURRENT_EVENT then
		CURRENT_EVENT = next(self.db.profile.global.events)
	end

	local function hidden(info)
		return not self.db.profile.global.enabled
	end

	return 'current_event', {
		type = 'select',
		name = L["Current event"],
		desc = L["Change the current event you are editing."],
		get = function(info)
			local events = self.db.profile.global.events
			if not rawget(events,CURRENT_EVENT) then
				CURRENT_EVENT = next(events)
			end
			return CURRENT_EVENT
		end,
		set = function(info, value)
			CURRENT_EVENT = value
		end,
		values = function(info)
			local t = {}
			local events = self.db.profile.global.events
			for k,v in pairs(events) do
				t[k] = k
			end
			return t
		end,
		hidden = hidden,
		width = 'double',
	}, 'new_event', {
		type = 'input',
		name = L["New event"],
		desc = L["Add a new event to LuaTexts."],
		get = function(info) return "" end,
		set = function(info, value)
			self.db.profile.global.events[value] = {unit=true}
			CURRENT_EVENT = value
		end,
		validate = function(info, value)
			local success, err = pcall(test_frame.RegisterEvent, test_frame, value)
			if not success then
				if validate_timer then PitBull4_LuaTexts:CancelTimer(validate_timer) end
				validate_timer = PitBull4_LuaTexts:ScheduleTimer(ClearStatusText, 3)
				return err
			end
			test_frame:UnregisterAllEvents()
			return true
		end,
		hidden = hidden,
	}, 'edit_event', {
		type = 'group',
		name = L["Edit event"],
		desc = L["Edit which units the event triggers updates on."],
		inline = true,
		hidden = hidden,
		args = {
			delete = {
				type = 'execute',
				name = L["Delete"],
				desc = L["Delete current event."],
				func = function(info)
					local events = self.db.profile.global.events
					events[CURRENT_EVENT] = nil
					CURRENT_EVENT = next(events)
				end,
				confirm = true,
				confirmText = L["Are you sure you want to delete this event?"],
			},
			update_for = {
				type = 'multiselect',
				name = L["Update for"],
				desc = L["Select the units that this event will trigger text updates on."],
				get = function(info,key)
					return self.db.profile.global.events[CURRENT_EVENT][key]
				end,
				set = function(invo,key,value)
					local event = self.db.profile.global.events[CURRENT_EVENT]
					event[key] = value
				end,
				values = update_for_values,
				width = 'double',
			},
		}
	}
end)
