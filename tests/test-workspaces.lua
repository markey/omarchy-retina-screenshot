-- Run the REAL installed Omarchy manager on an in-memory desktop. Never talks
-- to Hyprland or writes the user's state. Needs Lua and an Omarchy installation.
local root = arg[0]:match('^(.*)/tests/') or '.'
local files = {
  ['/virtual/omarchy/monitor-workspaces'] = '0\tDP-1\tTest Monitor\n1\t\tRETINA-SCREENSHOT\n2\t\tFALLBACK\n',
  ['/virtual/omarchy/monitor-workspaces-merged'] = ''
}
local real_open = io.open
local manager_path = os.getenv('OMARCHY_WORKSPACE_MANAGER') or '/usr/share/omarchy/default/hypr/monitor-workspaces.lua'
local source = assert(real_open(manager_path, 'r'))
local manager_source = source:read('*a'); source:close()
-- Read the helper before substituting filesystem access.
local helper = assert(real_open(root .. '/compat/workspaces.lua', 'r'))
local helper_source = helper:read('*a'); helper:close()
io.open = function(path, mode)
  -- Some Omarchy revisions keep workspace state under omarchy/monitors.
  -- Keep both layouts inside the same in-memory fixture.
  path = path:gsub('/omarchy/monitors/workspaces', '/omarchy/monitor-workspaces')
  if mode == 'r' then
    if files[path] == nil then return nil end
    return { lines = function() return files[path]:gmatch('[^\n]+') end, close = function() end }
  end
  files[path] = ''
  return { write = function(_, value) files[path] = files[path] .. value end, close = function() end }
end
package.preload['default.hypr.paths'] = function() return {state_home='/virtual'} end
local monitors, workspaces = {}, {}
local function monitor(name, description)
  local m = {name=name, description=description, id=1, focused=true}
  function m:set_workspace(args) self.active_workspace = workspaces[tonumber(args.workspace)] end
  return m
end
local dp = monitor('DP-1', 'Test Monitor')
local fallback = monitor('FALLBACK', 'FALLBACK')
local retina = monitor('RETINA-SCREENSHOT', 'RETINA-SCREENSHOT')
local function create(id, mon, windows, persistent)
  local w = {id=id, name=tostring(id), monitor=mon, windows=windows or 0, special=false, persistent=persistent}
  workspaces[id]=w
  return w
end
local function reset()
  workspaces={}; monitors={dp}
  for id=1,10 do create(id, dp, ({[1]=2,[2]=1,[3]=1,[4]=2})[id], true) end
  dp.active_workspace=workspaces[1]
end
local function operation(kind) return function(args) return {kind=kind,args=args} end end
o = {shell_quote=function(s) return s end, bind_expressions={}}
hl = {
  get_monitors=function() return monitors end,
  get_workspaces=function() local out={} for _,w in pairs(workspaces) do out[#out+1]=w end return out end,
  get_workspace=function(id) return workspaces[tonumber(id)] end,
  get_active_window=function() return nil end,
  get_active_monitor=function() return monitors[1] end,
  get_window=function() return nil end,
  on=function() end,
  dsp={workspace={change_id=operation('id'), move=operation('move')},focus=operation('focus')}
}
hl.get_monitor=function(name) for _,m in ipairs(monitors) do if m.name==name then return m end end end
hl.dispatch=function(op)
  local a=op.args
  if op.kind=='id' then
    local old=tonumber(a.workspace); local w=workspaces[old]
    workspaces[old]=nil; w.id=a.id; w.name=tostring(a.id); workspaces[a.id]=w
    if w.persistent then create(old,w.monitor,0,true) end
  elseif op.kind=='move' then
    workspaces[tonumber(a.workspace)].monitor=hl.get_monitor(a.monitor)
  elseif op.kind=='focus' and a.workspace then
    local id=tonumber(a.workspace)
    local w=workspaces[id] or create(id,monitors[1],0,false)
    w.monitor.active_workspace=w
  end
end
local function occupied()
  local ids={}; for id,w in pairs(workspaces) do if w.windows>0 then ids[#ids+1]=id end end
  table.sort(ids); return table.concat(ids, ',')
end
local function fallback_cycle(manager)
  monitors={fallback}; fallback.active_workspace=create(21,fallback,0,false)
  for _,w in pairs(workspaces) do w.monitor=fallback end
  manager.reconcile(nil,'DP-1')
  monitors={dp}; dp.active_workspace=workspaces[1]
  for _,w in pairs(workspaces) do w.monitor=dp end
  workspaces[21]=nil
  manager.reconcile('DP-1')
end
reset()
local manager = assert(load(manager_source))()
fallback_cycle(manager)
assert(occupied() == '22,23,24,25', 'fixture must reproduce upstream fallback bug')
files['/virtual/omarchy/monitor-workspaces-merged'] = ''
reset()
manager = assert(load(manager_source))()
assert(load(helper_source))()
local guarded = manager.reconcile
assert(load(helper_source))()
assert(manager.reconcile == guarded, 'helper should not wrap twice')
fallback_cycle(manager)
assert(occupied() == '1,2,3,4', 'guard must preserve original workspace IDs')
assert(files['/virtual/omarchy/monitor-workspaces-merged'] == '', 'no merge records should be created')
-- A reload during capture would normally adopt the moved workspace. Defer it.
reset()
monitors={dp,retina}; retina.active_workspace=create(11,retina,0,false)
manager.reconcile('RETINA-SCREENSHOT')
workspaces[1].monitor=retina
manager.reconcile()
assert(occupied() == '1,2,3,4' and workspaces[1].monitor == retina)
workspaces[1].monitor=dp
monitors={dp}; workspaces[11]=nil
manager.reconcile(nil,'RETINA-SCREENSHOT')
assert(occupied() == '1,2,3,4')
-- Reconciliation resumes once real displays remain, including other monitors.
local calls=0
o.workspaces={reconcile=function() calls=calls+1 end}
assert(load(helper_source))()
monitors={dp}; o.workspaces.reconcile(); assert(calls==1)
monitors={}; o.workspaces.reconcile(); assert(calls==1)
monitors={dp,retina}; o.workspaces.reconcile(); assert(calls==1)
o.workspaces.reconcile(nil,'RETINA-SCREENSHOT'); assert(calls==2)
monitors={dp,fallback}; o.workspaces.reconcile(); assert(calls==2)
o.workspaces.reconcile(nil,'FALLBACK'); assert(calls==3)
print('ok: actual Omarchy fallback reproduction, prevention, capture reload, idempotence, and reconciliation resumption')
