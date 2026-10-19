"""Focused Lua 5.1 tests loading the production LuaTexts and HideBlizzard files.

Run: PYTHONPATH=/workspace/.onboarding/python python -B -m unittest discover -s Tests -v
Requires lupa==2.6 (or a compatible Lupa exposing lupa.lua51).
"""
from pathlib import Path
import unittest

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]

HARNESS = r'''
function new_harness(localized)
 local h = { errors={}, events={}, deferred={}, combat=false, mutations=0, violations=0, pet_name='Fluffy' }
 local env = setmetatable({}, {__index=_G}); env._G=env
 local modules={}
 local function noop() end
 local function frame()
  local f={shown=true,hooks=0}
  function f:Hide() self.shown=false end
  function f:Show() self.shown=true; if self.onshow then self.onshow(self) end end
  function f:SetScript() end
  function f:RegisterEvent() end
  return f
 end
 env.CreateFrame=frame
 env.C_ChatInfo={}; env.C_Secrets={}
 env.UnitGUID=function() return 'public-player-guid' end
 env.UnitName=function() return h.pet_name end
 env.UnitExists=function() return true end
 env.issecretvalue=function(v) return v==h.secret and h.secret~=nil end
 env.hasanysecretvalues=function() return false end
 env.geterrorhandler=function() return function(err) h.errors[#h.errors+1]=err end end
 env.ClassicExpansionAtLeast=function() return false end
 env.InCombatLockdown=function() return h.combat or h.actual_lockdown end
 env.LibStub=function() return {NotifyChange=noop} end
 env.UnregisterUnitWatch=function(f) h:mutation(); f.unwatched=true end
 env.PitBull4={
  L=setmetatable({}, {__index=function(_,key) if localized and key=='Name' then return 'Nom' end; return key end}),
  Utils={IsUnitIdentitySecret=function() return false end},
  NewModule=function(_,name)
   local m={enabled=true}
   for _,method in ipairs({'SetModuleType','SetName','SetDescription','SetLayoutOptionsFunction','SetGlobalOptionsFunction','Print'}) do m[method]=noop end
   function m:SetDefaults(layout,global) self.db={profile={global=global,layouts={}}} end
   function m:RegisterEvent(event,method) h.events[event]=method or event end
   function m:IsEnabled() return self.enabled end
   modules[name]=m; return m
  end,
  OutOfCombatWrapper=function(_,fn)
   return function(...)
    if h.combat then h.deferred[#h.deferred+1]={fn=fn,args={...}}
    else return fn(...) end
   end
  end,
 }
 function h:load(path, source)
  local fn=assert(loadstring(source,'@'..path)); setfenv(fn,env); fn()
 end
 function h:mutation()
  if self.combat then self.violations=self.violations+1; error('protected frame mutation in combat') end
  self.mutations=self.mutations+1
 end
 function h:blizzard_frame()
  local f=frame()
  function f:Hide() h:mutation(); self.shown=false end
  function f:UnregisterAllEvents() h:mutation(); self.unregistered=true end
  function f:SetParent(parent) h:mutation(); self.parent=parent end
  function f:HookScript(script,fn) h:mutation(); assert(script=='OnShow'); self.onshow=fn; self.hooks=self.hooks+1 end
  function f:RegisterEvent() h:mutation() end
  function f:SetMovable() h:mutation() end
  function f:SetUserPlaced() h:mutation() end
  function f:SetDontSavePosition() h:mutation() end
  return f
 end
 function h:pet_created() env.PetFrame=self:blizzard_frame(); return env.PetFrame end
 function h:event(event,...)
  local method=self.events[event]; if method then modules.HideBlizzard[method](modules.HideBlizzard,event,...) end
 end
 function h:regen()
  self.combat=false; local pending=self.deferred; self.deferred={}
  for _,action in ipairs(pending) do action.fn(unpack(action.args)) end
 end
 function h:setup_hiding()
  self.hide=modules.HideBlizzard
  self.hide.db.profile.global={player=true}
  env.PlayerFrame=self:blizzard_frame()
  self.hide:OnEnable()
 end
 function h:setup_texts(angle_source)
  self.texts=modules.LuaTexts
  self.secret={}; self.form=nil
  local scripts={
   Name=function() return h.pet_name end, AFK=function() return h.afk end, DND=function() return nil end,
   HostileColor=function() return 255,128,0 end, ClassColor=function() return 0,255,0 end,
   Level=function() return '80' end, DruidForm=function() return h.form end,
   WrapString=function(s,a,b) return a..s..b end, IsSecretValue=env.issecretvalue,
  }
  scripts.ScriptEnv=scripts
  local fn=assert(loadstring(angle_source)); setfenv(fn,scripts); fn()
  self.texts.ScriptEnv=scripts
 end
 function h:render(code,name)
  local f={db={code=code,events={}},display=nil}
  function f:Show() end
  function f:GetFont() return 'test-font',12 end
  function f:SetFont() end
  function f:SetAlpha() end
  function f:SetWordWrap() end
  function f:SetText(value) self.display=value end
  function f:SetFormattedText(fmt,...)
   local index=0
   for spec in fmt:gmatch('%%[-+ #0]*%d*%.?%d*([sdxfg])') do
    index=index+1
    if select(index,...)==nil then error("bad argument #"..(index+2).." to 'SetFormattedText' (string expected, got nil)") end
   end
   self.format=fmt; self.values={...}
   -- This mock's render sink accepts an opaque name without inspecting it.
   for i=1,index do if self.values[i]==h.secret then self.display='<secret>'; return end end
   self.display=string.format(fmt,...)
  end
  self.texts:AddFontString({unit='pet',layout='CustomPets',layout_db={cyrillic_name_fallback=false}},f,name or 'Lua:Name')
  return f
 end
 h.env=env; return h
end
'''

LEGACY = [
    "return '%s %s%s%s',Name(unit),Angle(AFK(unit) or DND(unit))",
    "local r,g,b = HostileColor(unit)\nreturn '|cff%02x%02x%02x%s|r %s%s%s',r,g,b,Name(unit),Angle(AFK(unit) or DND(unit))",
    "local r,g,b = ClassColor(unit)\nreturn '|cff%02x%02x%02x%s|r %s%s%s',r,g,b,Name(unit),Angle(AFK(unit) or DND(unit))",
    "local r,g,b = ClassColor(unit)\nreturn '%s |cff%02x%02x%02x%s|r %s%s%s',Level(unit),r,g,b,Name(unit),Angle(AFK(unit) or DND(unit))",
    "local r,g,b = ClassColor(unit)\nlocal form = DruidForm(unit)\nif form then\n  return '%s |cff%02x%02x%02x%s|r (%s) %s%s%s',Level(unit),r,g,b,Name(unit),form,Angle(AFK(unit) or DND(unit))\nelse\n  return '%s |cff%02x%02x%02x%s|r %s%s%s',Level(unit),r,g,b,Name(unit),Angle(AFK(unit) or DND(unit))\nend",
]


class PetRegressionTests(unittest.TestCase):
    def harness(self, texts=False, localized=False):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute(HARNESS)
        h = lua.globals().new_harness(localized)
        path = "Modules/LuaTexts/LuaTexts.lua" if texts else "Modules/HideBlizzard/HideBlizzard.lua"
        h.load(h, path, (ROOT / path).read_text())
        if texts:
            source = (ROOT / "Modules/LuaTexts/ScriptEnv.lua").read_text()
            start = source.index("local function Angle(value)")
            end = source.index("ScriptEnv.Angle = Angle", start) + len("ScriptEnv.Angle = Angle")
            h.setup_texts(h, source[start:end])
        else:
            h.setup_hiding(h)
        return lua, h

    def test_all_exact_legacy_name_presets_render(self):
        for code in LEGACY:
            for form in (None, "Cat"):
                with self.subTest(code=code, form=form):
                    _, h = self.harness(texts=True)
                    h.form = form
                    f = h.render(h, code)
                    self.assertIn("Fluffy", f.display)
                    self.assertEqual(len(h.errors), 0)
                    self.assertNotEqual(f.db.code, code)

    def test_localized_and_canonical_name_slots(self):
        for name in ("Lua:Name", "Lua:Nom"):
            _, h = self.harness(texts=True, localized=True)
            self.assertIn("Fluffy", h.render(h, LEGACY[0], name).display)

    def test_custom_script_is_preserved_and_errors_are_not_masked(self):
        _, h = self.harness(texts=True)
        code = "return '%s %s',Name(unit),nil"
        f = h.render(h, code)
        self.assertEqual(f.db.code, code)
        self.assertEqual(f.display, "{err}")
        self.assertEqual(len(h.errors), 1)

    def test_valid_custom_script_and_unrelated_slot_are_unchanged(self):
        _, h = self.harness(texts=True)
        code = "return '%s!',Name(unit)"
        f = h.render(h, code)
        self.assertEqual(f.db.code, code)
        self.assertEqual(f.display, "Fluffy!")
        unrelated = h.render(h, LEGACY[0], "Lua:Other")
        self.assertEqual(unrelated.db.code, LEGACY[0])
        self.assertEqual(unrelated.display, "{err}")

    def test_secret_name_passes_unchanged_to_render_sink(self):
        lua, h = self.harness(texts=True)
        h.pet_name = h.secret
        f = h.render(h, LEGACY[0])
        self.assertTrue(lua.eval("function(f,s) return f.values[1]==s end")(f, h.secret))
        self.assertEqual(len(h.errors), 0)

    def test_legacy_format_reproduces_missing_fifth_argument(self):
        _, h = self.harness(texts=True)
        # A non-Name slot is deliberately outside the exact Name migration.
        h.render(h, LEGACY[0], "Lua:Other")
        self.assertIn("bad argument #5", h.errors[1])

    def test_late_pet_frame_is_hidden_on_pet_event(self):
        _, h = self.harness()
        pet = h.pet_created(h)
        h.event(h, "UNIT_PET", "player")
        self.assertFalse(pet.shown)
        self.assertEqual(pet.hooks, 1)

    def test_world_and_unitframe_addon_events_retry_discovery(self):
        for event, argument in (("PLAYER_ENTERING_WORLD", None), ("ADDON_LOADED", "Blizzard_UnitFrame")):
            with self.subTest(event=event):
                _, h = self.harness()
                pet = h.pet_created(h)
                h.event(h, event, argument)
                self.assertFalse(pet.shown)

    def test_pet_hiding_is_idempotent_and_handles_replacement(self):
        _, h = self.harness()
        pet = h.pet_created(h)
        for _ in range(5):
            h.event(h, "UNIT_PET", "player")
        self.assertEqual(pet.hooks, 1)
        replacement = h.pet_created(h)
        h.event(h, "UNIT_PET", "player")
        self.assertFalse(replacement.shown)
        self.assertEqual(replacement.hooks, 1)

    def test_combat_defers_all_pet_frame_operations(self):
        _, h = self.harness()
        pet = h.pet_created(h)
        h.combat = True
        before = h.mutations
        h.event(h, "UNIT_PET", "player")
        self.assertTrue(pet.shown)
        self.assertEqual(h.mutations, before)
        h.regen(h)
        self.assertFalse(pet.shown)
        self.assertEqual(h.violations, 0)

    def test_settings_are_rechecked_after_combat(self):
        _, h = self.harness()
        pet = h.pet_created(h)
        h.combat = True
        h.event(h, "UNIT_PET", "player")
        h.hide.db.profile["global"].player = False
        h.regen(h)
        self.assertTrue(pet.shown)
        self.assertEqual(pet.hooks, 0)

    def test_existing_pet_onshow_defers_hide_during_combat(self):
        _, h = self.harness()
        pet = h.pet_created(h)
        h.event(h, "UNIT_PET", "player")
        h.combat = True
        before = h.mutations
        pet.Show(pet)
        self.assertTrue(pet.shown)
        self.assertEqual(h.mutations, before)
        h.regen(h)
        self.assertFalse(pet.shown)
        self.assertEqual(pet.hooks, 1)
        self.assertEqual(h.violations, 0)

    def test_actual_lockdown_blocks_discovery_before_core_combat_state(self):
        _, h = self.harness()
        pet = h.pet_created(h)
        h.actual_lockdown = True
        before = h.mutations
        h.event(h, "UNIT_PET", "player")
        self.assertTrue(pet.shown)
        self.assertEqual(h.mutations, before)
        h.actual_lockdown = False
        h.event(h, "PLAYER_REGEN_ENABLED")
        self.assertFalse(pet.shown)

    def test_module_disable_is_rechecked_after_combat(self):
        _, h = self.harness()
        pet = h.pet_created(h)
        h.combat = True
        h.event(h, "UNIT_PET", "player")
        h.hide.enabled = False
        h.regen(h)
        self.assertTrue(pet.shown)
        self.assertEqual(pet.hooks, 0)

    def test_disabled_module_or_player_option_does_not_hide_pet(self):
        for enabled, player in ((False, True), (True, False)):
            _, h = self.harness()
            pet = h.pet_created(h)
            h.hide.enabled = enabled
            h.hide.db.profile["global"].player = player
            h.event(h, "UNIT_PET", "player")
            self.assertTrue(pet.shown)


if __name__ == "__main__":
    unittest.main()
