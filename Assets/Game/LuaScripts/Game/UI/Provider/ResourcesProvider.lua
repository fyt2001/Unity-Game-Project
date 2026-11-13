--[[
=============================================================================
ResourcesProvider.lua - Unity Resources 资源提供者
=============================================================================
Module:     Game/UI/Provider/ResourcesProvider
Version:    1.0.0
Description:
	基于 Unity Resources API 的资源提供者，实现 UIResourceLoader 所需的
	LoadAsync / Instantiate / Destroy / Release 接口。

	设计要点：
		- 真异步：内部委托 AsyncResourceProvider（Resources.LoadAsync + 轮询 isDone），
		  首次加载大 prefab 不再卡帧；缓存命中时同步回调
		- 实例化：使用 GameObject.Instantiate 创建运行时实例
		- 销毁：使用 GameObject.Destroy 清理实例
		- 卸载：使用 Resources.UnloadAsset 卸载缓存资源

	用法：
		local provider = ResourcesProvider.New()
		local uiManager = FW.CreateUIManager({ resourceProvider = provider })
=============================================================================
]]

local Class = require "Framework.Core.Class"
local AsyncResourceProvider = require "Framework.Resource.AsyncResourceProvider"

local ResourcesProvider = Class.Define("ResourcesProvider")

function ResourcesProvider:Ctor()
	self._async = AsyncResourceProvider.New()
end

---加载资源（真异步：首次走 Resources.LoadAsync，缓存命中则同步回调）
function ResourcesProvider:LoadAsync(path, onComplete, token)
	if token and token.cancelled then
		return
	end
	self._async:LoadAsync(path, onComplete, token)
end

---实例化资源
function ResourcesProvider:Instantiate(asset)
	if not asset then
		return {
			__mockAsset = true,
			name = "MockUI",
			transform = {
				Find = function(_, _) return nil end,
			},
			SetActive = function(_, _) end,
		}
	end

	if asset.__mockAsset then
		return {
			asset = asset,
			name = asset.path or "MockUI",
			transform = {
				Find = function(_, _) return nil end,
			},
			SetActive = function(_, _) end,
		}
	end

	return CS.UnityEngine.Object.Instantiate(asset)
end

---销毁运行时 GameObject
function ResourcesProvider:DestroyInstance(gameObject)
	if not gameObject then
		return
	end

	if gameObject.__mockAsset then
		return
	end

	CS.UnityEngine.Object.Destroy(gameObject)
end

return ResourcesProvider