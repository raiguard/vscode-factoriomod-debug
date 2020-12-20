__Profiler = __Profiler or {}
local __Profiler = __Profiler

local normalizeLuaSource = require("__debugadapter__/normalizeLuaSource.lua")
local print = print
local localised_print = localised_print
local debug = debug

--- Total time accumulated in this lua state
local luatotal
--- Time accumulated per line
local linedata = {}
--- Time accumulated per function
local funcdata = {}

if not __Profiler.slowStart then
  __Profiler.slowStart = 20
end
if not __Profiler.updateRate then
  __Profiler.updateRate = 500
end

local function getlinetimer(file,line)
  local f = linedata[file]
  if not f then
    f = {}
    linedata[file] = f
  end

  local ld = f[line]
  if not ld then
    ld = {count=0}
    f[line] = ld
    -- start stopped
    local t = game.create_profiler(true)
    ld.timer = t

  end
  ld.count = ld.count + 1
  return ld.timer
end

local function getfunctimer(file,line)
  -- line data needs file for dumps to work
  if not linedata[file] then linedata[file] = {} end

  local f = funcdata[file]
  if not f then
    f = {}
    funcdata[file] = f
  end

  local fd = f[line]
  if not fd then
    fd = {count=0}
    f[line] = fd
    -- start stopped
    local t = game.create_profiler(true)
    fd.timer = t

  end
  fd.count = fd.count + 1
  return fd.timer
end

local dumpcount = 0
local dumpnow
local hooktimer -- time not yet accumulated to specific line/function timer(s)
local activeline -- the timer for the current line, if any
local callstack = {} -- the timers for lines higher up the callstack, if any
local calltree = { -- timer tree for flamegraph
  root = true,
  children = {}
}
--[[
  treenode = {
    -- any names this fun is called by
    funcnames = {string=>itself}
    -- file and line are as close to unique id per function as we get
    filename = string,
    line = int,
    -- time in this tree...
    timer = timer,
    -- nodes called from this node
    children = treenode[filename..line],
  }
]]

local function dumptree(tree)
  if tree.root then
    print("PROOT:")
  else
    localised_print{"","PTREE:",tree.funcname,":",tree.filename,":",tree.line,":",tree.timer}
  end
  for _,node in pairs(tree.children) do
    dumptree(node)
  end
  print("PTEND:")
end


local function getstackbranch(treenode,source,linedefined,name)
  local fname = (name or '(anon)')
  local childindex = fname..":"..source..":"..linedefined
  local child = treenode.children[childindex]
  if child then
    return child
  else
    child = {
      name = childindex,
      funcname = fname, filename = source, line = linedefined,
      timer = game.create_profiler(true),
      children = {}
    }
    treenode.children[childindex] = child
    return child
  end
end

local function accumulate_hook_time()
  if hooktimer then
    if not luatotal then
      luatotal = game.create_profiler(true)
    end
    luatotal.add(hooktimer)
    if activeline then
      activeline.add(hooktimer)
    end
    for _,stackframe in pairs(callstack) do
      local linetimer = stackframe.linetimer
      if linetimer then
        linetimer.add(hooktimer)
      end
      local functimer = stackframe.functimer
      if functimer then
        functimer.add(hooktimer)
      end
      --stack timers
      local stacknode = stackframe.node
      if stacknode then
        stacknode.timer.add(hooktimer)
      end
    end
  end
end

local function dump()
  local t = game.create_profiler()
  print("***DebugAdapterBlockPrint***\nPROFILE:")
  localised_print{"","PMN:",script.mod_name,":",luatotal}
  luatotal = nil
  for file,f in pairs(linedata) do
    print("PFN:"..file)
    for line,ld in pairs(f) do
      localised_print{"","PLN:",line,":",ld.timer,":",ld.count}
    end
    local fd = funcdata[file]
    if fd then
      for line,ft in pairs(fd) do
        localised_print{"","PFT:",line,":",ft.timer,":",ft.count}
      end
    end
  end

  -- walk calltree
  dumptree(calltree)

  t.stop()
  localised_print{"","POV:",t}
  print("***EndDebugAdapterBlockPrint***")
  linedata = {}
  funcdata = {}
  activeline = nil
  for _,frame in pairs(callstack) do
    frame.linetimer = nil
    frame.functimer = nil
    frame.node = nil
  end
  hooktimer = nil
  calltree = { root = true, children = {} }
end

local function attach()
  local getinfo = debug.getinfo
  local sub = string.sub
  debug.sethook(function(event,line)
    if hooktimer then
      hooktimer.stop()
    elseif game then
      hooktimer = game.create_profiler(true)
    else
      return
    end
    if event == "line" then
      accumulate_hook_time()
      local info = getinfo(2,"S") -- currently executing function
      local s = info.source
      if sub(s,1,1) == "@" then
        s = normalizeLuaSource(s)
        activeline = getlinetimer(s,line)
        --print("line @"..s..":"..line)
      else
        activeline = nil
      end
    elseif event == "call" or event == "tail call" then
      accumulate_hook_time()
      local info = getinfo(2,"nS") -- call target
      local s = info.source
      local functimer
      if (__Profiler.trackFuncs ~= false) then
        if sub(s,1,1) == "@" then
          s = normalizeLuaSource(s)
          functimer = getfunctimer(s,info.linedefined)
        end
      end
      local top = #callstack
      local node
      if (__Profiler.trackTree ~= false) then
        if top == 0 then
          node = calltree
        else
          node = callstack[top].node
        end
        if node then
          node = getstackbranch(node,s,info.linedefined,info.name)
        end
      end
      -- push activeline to callstack
      callstack[top+1] = {
        linetimer = activeline,
        functimer = functimer,
        node = node,
        tail= event=="tail call",
      }
      activeline = nil
    elseif event == "return" then
      accumulate_hook_time()
      -- pop from callstack until not tail, return to activeline
      for i = #callstack,1,-1 do
        local stackframe = callstack[i]
        callstack[i] = nil
        if not stackframe.tail then
          activeline = stackframe.linetimer
          break
        end
      end

      -- make sure to stop counting when we exit lua
      local parent = getinfo(3,"f") -- returning to
      if not parent then
        local info = getinfo(2,"S") -- returning from
        -- top of stack
        if info.what == "main" or info.what == "Lua" then
          dumpcount = dumpcount + 1
          if dumpcount < __Profiler.slowStart or
            dumpcount % __Profiler.updateRate == 0 or
            dumpnow
            then
            dump()
            dumpnow = nil
          end
        end
      end
    end
    if hooktimer then
      return hooktimer.reset()
    end
  end, (__Profiler.trackLines ~= false) and "clr" or "cr")
end

if script.mod_name ~= "debugadapter" then -- don't hook myself!
  remote.add_interface("__profiler_" .. script.mod_name ,{
    dump = function()
      dumpnow = true
    end,
    slow = function()
      dumpcount = 0
      dumpnow = true
    end,
  })
  log("profiler registered for " .. script.mod_name)
  attach()
end