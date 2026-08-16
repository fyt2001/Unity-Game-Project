// =============================================================================
// MVCGenerator.cs - Lua MVC代码生成器（腾讯级生产标准）
// =============================================================================
// 来源: ShaoNvClient_H02 MVCTools.cs + GoldenLuaUIComponentManager（提炼精华）
// 升级: 独立的代码生成器，支持自定义模板，不依赖GoldenEngine
// =============================================================================

using System.IO;
using System.Text;
using UnityEditor;
using UnityEngine;

/// <summary>
/// Lua MVC 代码生成器。
/// 一键创建 Model/View/Ctrl 三个 Lua 文件。
/// 支持自定义模板路径和命名约定。
/// </summary>
public class MVCGenerator : EditorWindow
{
    private string _moduleName = "";
    private string _prefabPath = "";
    private string _outputPath = "Assets/Resources/Game/UI/";
    private string _layerName = "Normal";
    private bool _isFullScreen = false;
    private bool _hasMask = true;

    [MenuItem("Tools/MVC/生成 UI 模块", false, 100)]
    [MenuItem("GameObject/UI/MVC/生成 UI 模块", false, 10)]
    public static void ShowWindow()
    {
        var window = GetWindow<MVCGenerator>("MVC 代码生成器");
        window.minSize = new Vector2(400, 350);

        // 从选中 GameObject 自动填充
        if (Selection.activeGameObject != null)
        {
            window._moduleName = Selection.activeGameObject.name.TrimClone();
            window._prefabPath = GetPrefabPath(Selection.activeGameObject);
        }
    }

    private void OnGUI()
    {
        GUILayout.Label("MVC 代码生成器", EditorStyles.boldLabel);
        EditorGUILayout.Space();

        _moduleName = EditorGUILayout.TextField("模块名称", _moduleName);
        _prefabPath = EditorGUILayout.TextField("Prefab 路径", _prefabPath);
        _outputPath = EditorGUILayout.TextField("输出目录", _outputPath);
        _layerName = EditorGUILayout.TextField("UI 层级", _layerName);
        _isFullScreen = EditorGUILayout.Toggle("全屏", _isFullScreen);
        _hasMask = EditorGUILayout.Toggle("有遮罩", _hasMask);

        EditorGUILayout.Space();

        GUI.enabled = !string.IsNullOrEmpty(_moduleName);
        if (GUILayout.Button("生成 Model/View/Ctrl", GUILayout.Height(40)))
        {
            GenerateMVC();
        }
        GUI.enabled = true;

        if (GUILayout.Button("仅生成 Item", GUILayout.Height(30)))
        {
            GenerateItem();
        }
    }

    /// <summary>
    /// 生成完整的 MVC 三件套
    /// </summary>
    private void GenerateMVC()
    {
        string dir = Path.Combine(_outputPath, _moduleName);
        if (!Directory.Exists(dir))
        {
            Directory.CreateDirectory(dir);
        }

        // 生成 Model
        string modelPath = Path.Combine(dir, $"{_moduleName}Model.lua");
        File.WriteAllText(modelPath, GenerateModelTemplate());
        Debug.Log($"[MVC] Model 已生成: {modelPath}");

        // 生成 View
        string viewPath = Path.Combine(dir, $"{_moduleName}View.lua");
        File.WriteAllText(viewPath, GenerateViewTemplate());
        Debug.Log($"[MVC] View 已生成: {viewPath}");

        // 生成 Ctrl
        string ctrlPath = Path.Combine(dir, $"{_moduleName}Ctrl.lua");
        File.WriteAllText(ctrlPath, GenerateCtrlTemplate());
        Debug.Log($"[MVC] Ctrl 已生成: {ctrlPath}");

        AssetDatabase.Refresh();
        EditorUtility.DisplayDialog("成功", $"MVC 模块已生成:\n{dir}", "确定");
    }

    /// <summary>
    /// 生成 UI Item
    /// </summary>
    private void GenerateItem()
    {
        string dir = Path.Combine(_outputPath, _moduleName);
        if (!Directory.Exists(dir))
        {
            Directory.CreateDirectory(dir);
        }

        string itemPath = Path.Combine(dir, $"{_moduleName}Item.lua");
        File.WriteAllText(itemPath, GenerateItemTemplate());
        Debug.Log($"[MVC] Item 已生成: {itemPath}");

        AssetDatabase.Refresh();
        EditorUtility.DisplayDialog("成功", $"Item 已生成:\n{itemPath}", "确定");
    }

    #region 模板生成

    private string GenerateModelTemplate()
    {
        string date = System.DateTime.Now.ToString("yyyy-MM-dd");
        string author = System.Environment.UserName;

        return $@"--[[
    Module:     {_moduleName}Model
    Author:     {author}
    Date:       {date}
    Description: {_moduleName} 数据模型
--]]

local {_moduleName}Model = {{}}

function {_moduleName}Model:Init()
    self.data = {{}}
end

function {_moduleName}Model:SetData(data)
    self.data = data
end

function {_moduleName}Model:GetData()
    return self.data
end

function {_moduleName}Model:Clear()
    self.data = {{}}
end

return {_moduleName}Model
";
    }

    private string GenerateViewTemplate()
    {
        string date = System.DateTime.Now.ToString("yyyy-MM-dd");
        string author = System.Environment.UserName;

        return $@"--[[
    Module:     {_moduleName}View
    Author:     {author}
    Date:       {date}
    Description: {_moduleName} 视图层
    UI绑定由 UIComponentBinderEditor 自动生成
--]]

local {_moduleName}View = {{}}

-- [自动化替换占位符,不要删除!!!!]

function {_moduleName}View:Init(uiBinder)
    -- 自动绑定由编辑器生成，此处保留手动绑定区域
end

function {_moduleName}View:Refresh(data)
    -- 刷新UI显示
end

function {_moduleName}View:OnDestroy()
    -- 清理引用
end

return {_moduleName}View
";
    }

    private string GenerateCtrlTemplate()
    {
        string date = System.DateTime.Now.ToString("yyyy-MM-dd");
        string author = System.Environment.UserName;

        return $@"--[[
    Module:     {_moduleName}Ctrl
    Author:     {author}
    Date:       {date}
    Description: {_moduleName} 控制器
--]]

local {_moduleName}Ctrl = {{}}

function {_moduleName}Ctrl:OnOpen(params)
    -- 窗口打开时调用
end

function {_moduleName}Ctrl:OnClose()
    -- 窗口关闭时调用
end

function {_moduleName}Ctrl:OnDestroy()
    -- 窗口销毁时调用
end

function {_moduleName}Ctrl:OnBack()
    -- 返回键处理
    return false
end

return {_moduleName}Ctrl
";
    }

    private string GenerateItemTemplate()
    {
        string date = System.DateTime.Now.ToString("yyyy-MM-dd");
        string author = System.Environment.UserName;

        return $@"--[[
    Module:     {_moduleName}Item
    Author:     {author}
    Date:       {date}
    Description: {_moduleName} 列表项
--]]

local {_moduleName}Item = {{}}

function {_moduleName}Item:Init(uiBinder)
    -- [自动化替换占位符,不要删除!!!!]
end

function {_moduleName}Item:SetData(index, data)
    self.index = index
    self.data = data
    self:Refresh()
end

function {_moduleName}Item:Refresh()
    -- 刷新显示
end

function {_moduleName}Item:OnDestroy()
    -- 清理引用
end

return {_moduleName}Item
";
    }

    #endregion

    #region 工具方法

    private static string GetPrefabPath(GameObject go)
    {
        string path = AssetDatabase.GetAssetPath(go);
        if (!string.IsNullOrEmpty(path))
        {
            return path;
        }

        // 场景中的 GameObject，尝试获取 Prefab 路径
        var prefab = PrefabUtility.GetCorrespondingObjectFromSource(go);
        if (prefab != null)
        {
            return AssetDatabase.GetAssetPath(prefab);
        }

        return "";
    }

    #endregion
}
