-- 转发到正确路径
-- UIManager require 的是 NewObject.Framework.UI.Manager.UIBlockManager
-- 实际实现在 NewObject.Framework.UI.Block.UIBlockManager
return require("NewObject.Framework.UI.Block.UIBlockManager")
