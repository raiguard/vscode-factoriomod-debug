__DebugAdapter = __DebugAdapter or {
  nohook = true,
  stepIgnore = function(f) return f end,
  stepIgnoreAll = function(t) return t end,
  -- evaluate needs this, but without hooks we can only end up in this lua state when remote.call is legal
  canRemoteCall = function() return true end,
}

local datastring = require("__debugadapter__/datastring.lua")
local ReadBreakpoints = datastring.ReadBreakpoints
local json = require("__debugadapter__/json.lua")
local script = script
local remote = remote
remote = rawget(remote,"__raw") or remote
local debug = debug
local print = print
local pairs = pairs

require("__debugadapter__/stacks.lua") -- might have already been run, but load it now if not

--- call a remote function in all registered mods
---@param funcname string Name of remote function to call
---@return table<string,any> Results indexed by mod name
local function callAll(funcname,...)
  local results = {}
  local call = remote.call
  for remotename,_ in pairs(remote.interfaces) do
    local modname = remotename:match("^__debugadapter_(.+)$")
    if modname then
      results[modname] = call(remotename,funcname,...)
    end
  end
  return results
end
__DebugAdapter.stepIgnore(callAll)

-- calls from other entrypoints come here anyway, so just skip right to it
local function updateBreakpoints(change)
  local source,changedbreaks = ReadBreakpoints(change)
  callAll("setBreakpoints",source,changedbreaks)
end
__DebugAdapter.updateBreakpoints = updateBreakpoints

local variables = require("__debugadapter__/variables.lua")
if __DebugAdapter.nohook then
  -- if hooks are not installed, we need to set up enough of the libraries for
  -- calls that come in here (mostly on_tick) to be able to run appropriately,
  -- and enough to track long refs logged from DA's lua state correctly still
  require("__debugadapter__/evaluate.lua")
  require("__debugadapter__/print.lua")

  -- and a minimal version of the __da_da remote so other lua can print vars
  remote.add_interface("__debugadapter_" .. script.mod_name ,{
    setBreakpoints = function() end,
    remoteCallInner = function() error("`debugadapter` is not hooked") end,
    remoteHasInterface = function() return false end, -- we're not hooked, don't call anything via remoteCallInner
    longVariables = __DebugAdapter.variables,
    evaluate = __DebugAdapter.evaluate,
  })
end

local whoiscache = {}
local function whois(remotename)
  local interfaces = remote.interfaces
  local call = remote.call

  local firstguess = whoiscache[remotename] or remotename
  local debugname = "__debugadapter_"..firstguess
  if interfaces[debugname] then
    if call(debugname,"remoteHasInterface",firstguess) then
      whoiscache[remotename] = firstguess
      return firstguess
    end
  end

  for interfacename,_ in pairs(interfaces) do
    local modname = interfacename:match("^__debugadapter_(.+)$")
    if modname then
      if call(interfacename,"remoteHasInterface",remotename) then
        whoiscache[remotename] = modname
        return modname
      end
    end
  end

  return nil
end

local sharedevents = {}
script.on_init(__DebugAdapter.stepIgnore(function()
  print("DBG: on_init")
  debug.debug()
  variables.clear()
  if sharedevents.on_init then return sharedevents.on_init() end
end))

script.on_load(__DebugAdapter.stepIgnore(function()
  print("DBG: on_load")
  debug.debug()
  variables.clear()
  if sharedevents.on_load then return sharedevents.on_load() end
end))

script.on_event(defines.events.on_tick,__DebugAdapter.stepIgnore(function(e)
  print("DBG: on_tick")
  debug.debug()
  variables.clear(true)
  if sharedevents.on_tick then return sharedevents.on_tick(e) end
end))

remote.add_interface("debugadapter",__DebugAdapter.stepIgnoreAll{
  updateBreakpoints = updateBreakpoints,
  whois = whois,

  pushStack = __DebugAdapter.pushStack,
  popStack = __DebugAdapter.popStack,
  peekStacks = __DebugAdapter.peekStacks,
})

return sharedevents