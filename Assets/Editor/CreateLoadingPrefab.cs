// =============================================================================
// CreateLoadingPrefab.cs - 自动创建 Loading Prefab
// 参考 ShaoNvClient_H02 InitLoadingNew 的 Prefab 结构
// =============================================================================

using UnityEditor;
using UnityEngine;
using UnityEngine.UI;

public static class CreateLoadingPrefab
{
    private const string PrefabPath = "Assets/Resources/UI/Loading/LoadingPanel.prefab";

    [MenuItem("Tools/UI/创建 Loading Prefab", false, 300)]
    public static void Create()
    {
        // 确保目录存在
        string dir = System.IO.Path.GetDirectoryName(PrefabPath);
        if (!AssetDatabase.IsValidFolder(dir))
        {
            string parent = System.IO.Path.GetDirectoryName(dir);
            string folder = System.IO.Path.GetFileName(dir);
            AssetDatabase.CreateFolder(parent, folder);
        }

        // 创建 Canvas 根节点
        GameObject rootGo = new GameObject("LoadingPanel", typeof(RectTransform));
        rootGo.layer = 5; // UI layer

        // Canvas + CanvasScaler + GraphicRaycaster
        Canvas canvas = rootGo.AddComponent<Canvas>();
        canvas.renderMode = RenderMode.ScreenSpaceOverlay;
        canvas.sortingOrder = 9999;

        CanvasScaler scaler = rootGo.AddComponent<CanvasScaler>();
        scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
        scaler.referenceResolution = new Vector2(1920, 1080);
        scaler.matchWidthOrHeight = 0.5f;

        rootGo.AddComponent<GraphicRaycaster>();

        // UIComponentBinder（Lua 自动绑定）
        rootGo.AddComponent<UIComponentBinder>();

        // ========================================
        // 全屏遮罩背景
        // ========================================
        GameObject bgGo = CreateUIElement("Background", rootGo.transform);
        RectTransform bgRt = bgGo.GetComponent<RectTransform>();
        bgRt.anchorMin = Vector2.zero;
        bgRt.anchorMax = Vector2.one;
        bgRt.sizeDelta = Vector2.zero;
        Image bgImg = bgGo.AddComponent<Image>();
        bgImg.color = new Color(0, 0, 0, 0.85f);

        // ========================================
        // 居中容器
        // ========================================
        GameObject containerGo = CreateUIElement("Container", bgGo.transform);
        RectTransform crt = containerGo.GetComponent<RectTransform>();
        crt.anchorMin = new Vector2(0.5f, 0.5f);
        crt.anchorMax = new Vector2(0.5f, 0.5f);
        crt.sizeDelta = new Vector2(600, 180);

        // ========================================
        // 标题 "LOADING..."
        // ========================================
        GameObject titleGo = CreateUIText("TitleText", containerGo.transform, "LOADING...", 32,
            TextAnchor.MiddleCenter);
        RectTransform trt = titleGo.GetComponent<RectTransform>();
        trt.anchorMin = new Vector2(0.5f, 1f);
        trt.anchorMax = new Vector2(0.5f, 1f);
        trt.sizeDelta = new Vector2(500, 40);
        trt.anchoredPosition = new Vector2(0, -25);

        // ========================================
        // 进度条 m_SliderBar
        // ========================================
        GameObject sliderGo = CreateUIElement("m_SliderBar", containerGo.transform);
        RectTransform srt = sliderGo.GetComponent<RectTransform>();
        srt.anchorMin = new Vector2(0.5f, 0.5f);
        srt.anchorMax = new Vector2(0.5f, 0.5f);
        srt.sizeDelta = new Vector2(500, 20);
        srt.anchoredPosition = Vector2.zero;

        // Slider 背景
        Image sliderBg = sliderGo.AddComponent<Image>();
        sliderBg.color = new Color(0.2f, 0.2f, 0.2f, 1f);
        sliderBg.type = Image.Type.Sliced;

        Slider slider = sliderGo.AddComponent<Slider>();
        slider.interactable = false;
        slider.transition = Selectable.Transition.None;

        // Slider Fill Area
        GameObject fillArea = CreateUIElement("Fill Area", sliderGo.transform);
        RectTransform fart = fillArea.GetComponent<RectTransform>();
        fart.anchorMin = Vector2.zero;
        fart.anchorMax = Vector2.one;
        fart.sizeDelta = new Vector2(-20, 0);
        fart.anchoredPosition = new Vector2(-5, 0);

        GameObject fillGo = CreateUIElement("Fill", fillArea.transform);
        RectTransform frt = fillGo.GetComponent<RectTransform>();
        frt.anchorMin = Vector2.zero;
        frt.anchorMax = Vector2.one;
        frt.sizeDelta = Vector2.zero;
        Image fillImg = fillGo.AddComponent<Image>();
        fillImg.color = new Color(0.2f, 0.6f, 1f, 1f);

        slider.fillRect = frt;
        slider.value = 0;

        // ========================================
        // 加载描述文本 m_LoadingDesc
        // ========================================
        GameObject descGo = CreateUIText("m_LoadingDesc", containerGo.transform, "正在初始化...", 18,
            TextAnchor.MiddleCenter);
        descGo.GetComponent<Text>().color = new Color(0.7f, 0.7f, 0.7f, 1f);
        RectTransform drt = descGo.GetComponent<RectTransform>();
        drt.anchorMin = new Vector2(0.5f, 0.5f);
        drt.anchorMax = new Vector2(0.5f, 0.5f);
        drt.sizeDelta = new Vector2(500, 30);
        drt.anchoredPosition = new Vector2(0, -40);

        // ========================================
        // 版本号 m_VersionText
        // ========================================
        GameObject verGo = CreateUIText("m_VersionText", bgGo.transform, "v1.0.0", 12,
            TextAnchor.LowerRight);
        verGo.GetComponent<Text>().color = new Color(0.5f, 0.5f, 0.5f, 1f);
        RectTransform vrt = verGo.GetComponent<RectTransform>();
        vrt.anchorMin = new Vector2(1f, 0f);
        vrt.anchorMax = new Vector2(1f, 0f);
        vrt.pivot = new Vector2(1f, 0f);
        vrt.sizeDelta = new Vector2(200, 25);
        vrt.anchoredPosition = new Vector2(-20, 20);

        // ========================================
        // 保存 Prefab
        // ========================================
        GameObject prefab = PrefabUtility.SaveAsPrefabAsset(rootGo, PrefabPath);
        Object.DestroyImmediate(rootGo);

        AssetDatabase.Refresh();
        EditorGUIUtility.PingObject(prefab);
        Debug.Log($"[CreateLoadingPrefab] Loading Prefab created: {PrefabPath}");
    }

    private static GameObject CreateUIElement(string name, Transform parent)
    {
        GameObject go = new GameObject(name, typeof(RectTransform));
        go.layer = 5;
        go.transform.SetParent(parent, false);
        return go;
    }

    private static GameObject CreateUIText(string name, Transform parent, string text, int fontSize, TextAnchor align)
    {
        GameObject go = CreateUIElement(name, parent);
        Text txt = go.AddComponent<Text>();
        txt.text = text;
        txt.fontSize = fontSize;
        txt.alignment = align;
        txt.color = Color.white;
        txt.font = Resources.GetBuiltinResource<Font>("Arial.ttf");
        return go;
    }
}
