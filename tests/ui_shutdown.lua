local ROOT_DIR = assert((arg and arg[1]) or rawget(_G, "ROOT"), "usage: lua tests/ui_shutdown.lua <project_root>  (XLua: set global ROOT)"):gsub("\\", "/"):gsub("/+$", "")
package.path = ROOT_DIR .. "/Assets/Game/LuaScripts/?.lua;" .. package.path
local noop = function() end
package.loaded['Framework.UI.Utils.Logger'] = setmetatable({}, {__index=function() return noop end})
local UIManager = require 'Framework.UI.Manager.UIManager'
local Window = require 'Framework.UI.Core.UIWindow'
local Animation = require 'Framework.UI.Animation.UIAnimationManager'
local count = 0
local function check(ok, message) assert(ok, message); count=count+1 end
local opened = Window.New('Open', {})
local cached = Window.New('Cached', {})
for _, window in ipairs({opened, cached}) do
    window:BeginLoading({}); window:CompleteLoading(); window:Create()
    window:Open()
end
cached:Close('cache')
local destroys = 0
local pendingCallback, pendingToken
local loader = {
    CreateToken=function(_, path) return {path=path} end,
    LoadAsync=function(_, _, cb, token) pendingCallback=cb; pendingToken=token end,
    Cancel=function(_, token) token.cancelled=true end,
    Instantiate=function() error('late load instantiated after shutdown') end,
}
local ui = UIManager.New({
    config={Has=function() return true end, Get=function() return {prefab='Pending'} end},
    resourceLoader=loader,
    layerManager={GetOrderedWindows=function() return {opened} end, RemoveWindow=noop},
    zoneManager={RemoveWindow=noop},
    cache={Get=function() return nil end, GetAll=function() return {cached,opened} end, Remove=noop},
    factory={CreateWindow=function(_, name, config) return Window.New(name, config) end,
        DestroyRuntimeObject=function() destroys=destroys+1 end},
})
local pending = ui:Open('Pending')
check(pending:IsLoading(), 'real pending window starts Loading')
ui:Shutdown()
check(opened:IsDestroyed() and cached:IsDestroyed() and pending:IsDestroyed(), 'open/cache/loading destroyed')
check(destroys==3, 'duplicate window references destroyed once')
check(pendingToken.cancelled, 'pending token cancelled')
pendingCallback({},pendingToken)
check(ui:GetLoadingCount()==0 and not ui:IsInputBlocked(), 'late callback cannot revive or block UI')
check(ui:Open('Pending')==nil and ui:Preload('Pending')==nil, 'terminal manager rejects new work')
ui:Shutdown()
check(destroys==3, 'shutdown idempotent')
local complete, fires = nil, 0
local animation=Animation.New({PlayOpenAnimation=function(_, _, cb) complete=cb end})
animation:PlayOpenAnimation({},function() fires=fires+1 end)
animation:StopAll(); complete()
check(fires==0, 'late stopped animation completion ignored')
local Provider=require 'Game.UI.Provider.AssetBundleProvider'
local provider=Provider.New()
local token={}
provider._list={{callbacks={{token=token},{}}}}
provider:Dispose(); provider:Dispose()
check(token.cancelled and #provider._list==0 and next(provider._pending)==nil, 'optional-token provider cleanup')
local callbackFired=false
provider:LoadAsync('Any',function() callbackFired=true end)
check(not callbackFired, 'disposed provider rejects work')
return count
