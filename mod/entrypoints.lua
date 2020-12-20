local oldpcall = pcall
local oldxpcall = xpcall
local debug = debug
local print = print
local localised_print = localised_print
local __DebugAdapter = __DebugAdapter

local function print_exception(type,mesg)
  if mesg == nil then mesg = "<nil>" end
  localised_print({"",
  "***DebugAdapterBlockPrint***\n"..
  "DBG: exception ", type, "\n",
  mesg,"\n"..
  "***EndDebugAdapterBlockPrint***"
  })
end
if not localised_print then
  function print_exception(type,mesg)
    print("***DebugAdapterBlockPrint***\n"..
    "DBG: exception "..type.."\n"..
    __DebugAdapter.describe(mesg).."\n"..
    "***EndDebugAdapterBlockPrint***")
  end
end
__DebugAdapter.stepIgnore(print_exception)

function __DebugAdapter.breakpoint(mesg)
  if mesg then
    print_exception("manual",mesg)
  else
    print("DBG: breakpoint")
  end
  debug.debug()
  return
end

local function stack_has_location()
  local i = 4
  -- 1 = stack_has_location, 2 = on_exception,
  -- 3 = pCallWithStackTraceMessageHandler, 4 = at exception
  local info = debug.getinfo(i,"Sf")
  repeat
    if (info.what ~= "C") and (info.source:sub(1,1) ~= "=") and not __DebugAdapter.isStepIgnore(info.func) then
      return true
    end
    i = i + 1
    info = debug.getinfo(i,"Sf")
  until not info
  return false
end
__DebugAdapter.stepIgnore(stack_has_location)

local on_exception
if __DebugAdapter.instrument then
  on_exception = function (mesg)
    if not stack_has_location() then
      __DebugAdapter.popStack()
      return
    end
    local mtype = type(mesg)
    -- don't bother breaking when a remote.call's error bubbles up, we've already had that one...
    if mtype == "string" and (
        mesg:match("^Error when running interface function") or
        mesg:match("^The mod [a-zA-Z0-9 _-]+ %([0-9.]+%) caused a non%-recoverable error")
        )then
      __DebugAdapter.popStack()
      return
    end
    print_exception("unhandled",mesg)
    debug.debug()
    __DebugAdapter.popStack()
    return
  end
else
  on_exception = function (mesg)
    if not stack_has_location() then
      __DebugAdapter.popStack()
      return mesg
    end
    local mtype = type(mesg)
    if mtype == "string" then
      if mesg:match("^Error when running interface function") or
          mesg:match("^The mod [a-zA-Z0-9 _-]+ %([0-9.]+%) caused a non%-recoverable error")
        then
        __DebugAdapter.popStack()
        return mesg
      end
      print_exception("unhandled", mesg)
      debug.debug()
      __DebugAdapter.popStack()
      return mesg
    elseif mtype == "table" and mesg[1] and mesg[1] == "REMSTEP" then
      mesg[1] = ""
      -- 0=traceback 1=on_exception 2=error (rethrow from hook) 3=remote.call hook 4=calling code to remote.call
      -- remove two lines -1=try_func or remoteCallInner, -2=xpcall
      mesg[#mesg+1] = debug.traceback("",4):match("^(.+)\n[^\n]+\n[^\n]+$")
      __DebugAdapter.popStack()
      return mesg
    else
      print_exception("unhandled",mesg)
      debug.debug()
      __DebugAdapter.popStack()
      return mesg
    end
  end
end
--shared for remotestepping
__DebugAdapter.on_exception = on_exception

local entrypoint = {}

function __DebugAdapter.getEntryPointName()
  return entrypoint[#entrypoint]
end
function __DebugAdapter.pushEntryPointName(entry)
  entrypoint[#entrypoint+1] = entry
end
function __DebugAdapter.popEntryPointName()
  local entry = entrypoint[#entrypoint]
  entrypoint[#entrypoint] = nil
  return entry
end

-- don't need the rest in data stage...
if not script then return end
local try
if __DebugAdapter.instrument then
  function try(func,entryname)
    if func == nil then return nil end
    return __DebugAdapter.stepIgnore(function(...)
      __DebugAdapter.pushEntryPointName(entryname)
      func(...)
      __DebugAdapter.popEntryPointName()
    end)
  end
else
  function try(func,entryname)
    if func == nil then return nil end
    return __DebugAdapter.stepIgnore(function(...)
      __DebugAdapter.pushEntryPointName(entryname)
      local success,message = oldxpcall(func,on_exception,...)
      if not success then
        -- factorio will add a new stacktrace below whatever i give it here, and there doesn't seem to be anything i can do about it.
        -- but i can rename it at least...
        local rethrow = error
        rethrow(message,-1)
      end
      __DebugAdapter.popEntryPointName()
    end)
  end
end
__DebugAdapter.stepIgnore(try)

local function caught(filter, user_handler)
  return __DebugAdapter.stepIgnore(function(mesg)
    print_exception(filter,mesg)
    debug.debug()
    if user_handler then
      return user_handler(mesg)
    else
      return mesg
    end
  end)
end
__DebugAdapter.stepIgnore(caught)

function pcall(func,...)
  return oldxpcall(func, caught("pcall"), ...)
end
__DebugAdapter.stepIgnore(pcall)
function xpcall(func, user_handler, ...)
  return oldxpcall(func, caught("xpcall",user_handler), ...)
end
__DebugAdapter.stepIgnore(xpcall)

local oldscript = script
local newscript = {
  __raw = oldscript
}

local registered_handlers = {}
local function check_events(f)
  if __DebugAdapter.checkEvents == false then
    return f
  end
  local de = defines.events
  local groups = {
    built = {
      [de.on_built_entity] = true,
      [de.on_robot_built_entity] = true,
      [de.script_raised_built] = true,
      [de.script_raised_revive] = true,
      [de.on_entity_cloned] = true,
    },

    destroyed = {
      [de.on_entity_died] = 1,
      [de.on_post_entity_died] = 1,

      [de.on_pre_chunk_deleted] = 2,
      [de.on_chunk_deleted] = 2,

      [de.on_pre_surface_cleared] = 3,
      [de.on_surface_cleared] = 3,

      [de.on_pre_surface_deleted] = 4,
      [de.on_surface_deleted] = 4,

      [de.on_pre_player_mined_item] = 5,
      [de.on_player_mined_entity] = 5,
      [de.on_player_mined_item] = 5,
      [de.on_player_mined_tile] = 5,

      [de.on_robot_pre_mined] = 6,
      [de.on_robot_mined] = 6,
      [de.on_robot_mined_entity] = 6,
      [de.on_robot_mined_tile] = 6,

      [de.script_raised_destroy] = true,
    }
  }
  return __DebugAdapter.stepIgnore(function()
    if f then f() end
    __DebugAdapter.pushEntryPointName("check_events")
    if next(registered_handlers) then
      for group,gevents in pairs(groups) do
        local foundany = false
        local notfound = {}
        local hassubgroup = {}
        for event,subgroup in pairs(gevents) do
          if registered_handlers[event] then
            foundany = true
            if subgroup ~= true then
              hassubgroup[subgroup] = true
            end
          else
            notfound[event] = subgroup
          end
        end
        for event,subgroup in pairs(notfound) do
          if hassubgroup[subgroup] then
            notfound[event] = nil
          end
        end
        if foundany and next(notfound) then
          local message = {"Mod Debugger Event Check: ", script.mod_name, " is listening for \"", group, "\" events but not"}
          local singles = {}
          local subgroups = {}
          for event,subgroup in pairs(notfound) do
            local eventname = tostring(event)
            for k,v in pairs(de) do
              if event == v then
                eventname = k
                break
              end
            end
            if subgroup == true then
              singles[#singles+1] = eventname
            else
              subgroups[subgroup] = subgroups[subgroup] or {}
              local sg = subgroups[subgroup]
              sg[#sg+1] = eventname
            end
          end
          if singles[1] then
            message[#message+1] = " "
            message[#message+1] = table.concat(singles,", ")
          end
          local submessages = {}
          for _,subgroup in pairs(subgroups) do
            submessages[#submessages+1] = "at least one of (" .. table.concat(subgroup,", ") .. ")"
          end
          if submessages[1] then
            if singles[1] then
              message[#message+1] = ", "
            else
              message[#message+1] = " "
            end
            message[#message+1] = table.concat(submessages,", ")
          end
          print(table.concat(message))
        end
      end
    end
    __DebugAdapter.popEntryPointName()
  end)
end
__DebugAdapter.stepIgnore(check_events)

function newscript.on_init(f)
  oldscript.on_init(check_events(try(f,"on_init handler")))
end
newscript.on_init()

function newscript.on_load(f)
  oldscript.on_load(check_events(try(f,"on_load handler")))
end
newscript.on_load()

function newscript.on_configuration_changed(f)
  return oldscript.on_configuration_changed(try(f,"on_configuration_changed handler"))
end

function newscript.on_nth_tick(tick,f)
  if not tick then
    return oldscript.on_nth_tick(nil)
  else
    local ttype = type(tick)
    if ttype == "number" then
      return oldscript.on_nth_tick(tick,try(f,("on_nth_tick %d handler"):format(tick)))
    elseif ttype == "table" then
      return oldscript.on_nth_tick(tick,try(f,("on_nth_tick {%s} handler"):format(table.concat(tick,","))))
    else
      error("Bad argument `tick` expected number or table got "..ttype,2)
    end
  end
end

function newscript.on_event(event,f,filters)
  -- on_event checks arg count and throws if event is table and filters is present, even if filters is nil
  local etype = type(event)
  if etype == "number" then
    local evtname = ("event %d"):format(event)
    for k,v in pairs(defines.events) do
      if event == v then
        evtname = k
        break
      end
    end
    registered_handlers[event] = f
    return oldscript.on_event(event,try(f, ("%s handler"):format(evtname)),filters)
  elseif etype == "string" then
    registered_handlers[event] = f
    return oldscript.on_event(event,try(f, ("%s handler"):format(event)))
  elseif etype == "table" then
    for _,e in pairs(event) do
      newscript.on_event(e,f)
    end
  else
    error({"","Invalid Event type ",etype},2)
  end
end

-- if a mod tries to get/wrap/set a handler, the raw get would get my wrapped
-- function, only to wrap it again. This unwraps it, which also preserves identity
-- if a mod wants to test which function is registered for some reason.
function newscript.get_event_handler(event)
  return registered_handlers[event] or oldscript.get_event_handler(event)
end

function newscript.raise_event(event,eventdata)
  __DebugAdapter.pushStack{
    source = "raise_event",
    mod_name = script.mod_name,
    stack = __DebugAdapter.stackTrace(-2, true),
  }
  oldscript.raise_event(event,eventdata)
  __DebugAdapter.popStack()
end

local function wrap_raise(key)
  local raise = oldscript[key]
  if type(raise)=="function" then
    newscript[key] = function (eventdata)
      __DebugAdapter.pushStack{
        source = "raise_event",
        mod_name = script.mod_name,
        stack = __DebugAdapter.stackTrace(-2, true),
      }
      raise(eventdata)
      __DebugAdapter.popStack()
    end
  end
end

for _,fname in pairs{
  "raise_console_chat",
  "raise_player_crafted_item",
  "raise_player_fast_transferred",
  "raise_biter_base_built",
  "raise_market_item_purchased",
  "raise_script_built",
  "raise_script_destroy",
  "raise_script_revive",
  "raise_script_set_tiles",
} do
  wrap_raise(fname)
end

local newscriptmeta = {
  __index = oldscript,
  __newindex = function(t,k,v) oldscript[k] = v end,
  __debugline = "<LuaBootstrap Debug Proxy>",
  __debugtype = "DebugAdapter.LuaBootstrap",
}
__DebugAdapter.stepIgnoreAll(newscript)
__DebugAdapter.stepIgnoreAll(newscriptmeta)
setmetatable(newscript,newscriptmeta)

local oldcommands = commands
local newcommands = {
  __raw = oldcommands,
}

function newcommands.add_command(name,help,f)
  return oldcommands.add_command(name,help,try(f, "command /" .. name))
end

function newcommands.remove_command(name)
  return oldcommands.remove_command(name)
end

local newcommandsmeta = {
  __index = oldcommands,
  __newindex = function(t,k,v) oldcommands[k] = v end,
  __debugline = "<LuaCommandProcessor Debug Proxy>",
  __debugtype = "DebugAdapter.LuaCommandProcessor",
}
__DebugAdapter.stepIgnoreAll(newcommands)
__DebugAdapter.stepIgnoreAll(newcommandsmeta)
setmetatable(newcommands,newcommandsmeta)

script = newscript
commands = newcommands