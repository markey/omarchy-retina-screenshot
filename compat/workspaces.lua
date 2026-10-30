-- Omarchy 4.5 compatibility. Load AFTER default.hypr.omarchy in hyprland.lua.
-- No package files or monitor/workspace state files are modified.
local manager = o and o.workspaces
if not manager or type(manager.reconcile) ~= "function" or manager.retina_guard then
  return
end

local reconcile = manager.reconcile
manager.retina_guard = true
manager.reconcile = function(added, gone)
  local physical = false
  for _, monitor in ipairs(hl.get_monitors()) do
    if monitor.name ~= gone and not monitor.is_mirror then
      -- FALLBACK is temporary compositor infrastructure, not a desktop to
      -- adopt/renumber workspaces onto. The capture output is also temporary;
      -- leave the desktop untouched until the capture has restored it.
      if monitor.name == "FALLBACK" or monitor.name == "RETINA-SCREENSHOT" then
        return
      end
      physical = true
    end
  end
  if not physical then return end
  return reconcile(added, gone)
end
