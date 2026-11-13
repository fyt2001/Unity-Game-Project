// =============================================================================
// GameLaunch.cs - 游戏启动流程编排器（腾讯级生产标准）
// =============================================================================
// 参考: ShaoNvClient_H02 GameLaunch / InitLoadingNew
// 设计: 预制体不通过场景序列化挂载，通过 AssetBundle (AB 包) 动态加载
//       Editor 下支持 SimulateAssetBundleInEditor 跳过打包直接运行
//       正式发布时走 AB 包方案，支持热更
// =============================================================================

using System;
using System.Collections;
using System.IO;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.UI;
using XLua;
using MyAssetBundles;
#if UNITY_EDITOR
using UnityEditor;
#endif

public enum LaunchPhase { None = 0, InitLogger, InitFileSystem, InitResources, InitLua, InitModules, StartGame, Complete }

public class GameLaunch : MonoBehaviour
{
    [Header("基础设置")]
    public LuaLoadMode LuaLoadMode = LuaLoadMode.Editor;
    public bool AutoInitResources = false;

    [Header("启动 Loading —— AssetBundle 动态加载（对齐 H02 Initloading）")]
    [Tooltip("LoadingPanel 的 asset 名；bundle 名按 ui/<名字小写>.asset 推导" +
             "（与 Lua 侧 AssetBundleProvider.resolveBundle 同一规则）")]
    public string LoadingPrefabName = "LoadingPanel";

    [Header("启动进度 UI（自动从预制体查找）")]
    public Slider ProgressSlider;
    public Text ProgressText;
    public bool ShowProgress = true;

    [Header("离线调试（无服务器）")]
    [Tooltip("勾选后跳过登录/联网流程，点击登录按钮直接进入主界面。" +
             "启动时该值会写入 Lua 的 Macro.SkipLogin，覆盖 GameMain.lua 中的默认值。" +
             "接上真实服务器后请取消勾选。")]
    public bool SkipLogin = true;

    private GameObject _loadingObj;

    public LaunchPhase CurrentPhase { get; private set; } = LaunchPhase.None;
    public float Progress { get; private set; }
    public event Action OnLaunchComplete;
    public event Action<LaunchPhase> OnPhaseChanged;

    private static GameLaunch _instance;
    private bool _isLaunching;
    private LuaFunction _luaUpdate, _luaLateUpdate, _luaFixedUpdate;
    private int _luaUpdateId, _luaLateUpdateId, _luaFixedUpdateId;
    public static GameLaunch Instance => _instance;

    /// <summary>本地热更版本清单（对齐 H02 GameLaunch.localVersion）。
    /// 启动时从 persistent 读取 versions.csv，无则空清单。完整版本对比/首包更新逻辑待移植 UpdateMgr。</summary>
    public VersionFile localVersion;

    // =========================================================================
    // Unity 生命周期
    // =========================================================================

    IEnumerator Start()
    {
        _instance = this;
        DontDestroyOnLoad(gameObject);
        Screen.sleepTimeout = SleepTimeout.NeverSleep;
        Application.runInBackground = true;

#if (UNITY_ANDROID || UNITY_IOS) && !UNITY_EDITOR
        // Start upright, then allow the device to rotate to either landscape side.
        Screen.autorotateToPortrait = true;
        Screen.autorotateToPortraitUpsideDown = false;
        Screen.autorotateToLandscapeLeft = true;
        Screen.autorotateToLandscapeRight = true;
        Screen.orientation = ScreenOrientation.Portrait;
        yield return null;
        Screen.orientation = ScreenOrientation.AutoRotation;
#endif

        SceneManager.sceneLoaded += OnSceneLoaded;

        // =====================================================================
        // 启动 Loading —— 先初始化 AssetBundle，再从 AB 加载 LoadingPanel
        //
        // 顺序对齐 H02 GameLaunch.cs:78-87：
        //   AssetBundleManager.Initialize() -> LoadAssetAsync("ui/<name>.asset") -> Instantiate
        //
        // 为什么必须这个顺序：LoadingPanel 的 Spine 动画在 model/loading.asset、背景与
        // 进度条贴图在本包内，全部都在 AB 里；不先 Initialize 就拿不到。
        // 编辑器下 Simulation 模式走 AssetDatabase，看不出差异 —— 属「看起来能跑」的假绿。
        // =====================================================================

        // AB 基址必须与 BuildAssetBundles.cs 的产物布局同源，共三条线一起对齐：
        //   BuildAssetBundles.cs : Path.Combine(streamingAssetsPath, AssetBundlesOutputPath, GetPlatformName())
        //   LuaBundleLoader.cs   : AssetBundlesOutputPath + "/" + GetPlatformName() + "/" + BundleName
        //   AssetBundleManager   : LoadAssetBundleInternal_Legacy 拼的是 base + "/" + bundleName，
        //                          而 Initialize() 传进来的 bundleName 恰好又是 GetPlatformName()="game.asset"
        //   => 基址必须给到 StreamingAssets/AssetBundles/game.asset，
        //      于是 manifest 的真实路径 = .../AssetBundles/game.asset/game.asset（一个文件）。
        // 旧写法只给到 StreamingAssets 根，运行时会去开 StreamingAssets/game.asset —— 那里顶多是个
        // 同名目录，包永远打不开（控制台报 Unable to open archive file: .../StreamingAssets/game.asset）。
        // 而编辑器 Simulation 模式走 AssetDatabase，这条错路照跑不误 —— 教科书级的「假绿」。
        // 两个常量直接取自 MyAssetBundles.Utility，改了构建布局会同步跟着改，不再手写字符串。
        AssetBundleManager.SetSourceAssetBundleURL(FileUtils.StreamingAssetsPath + "/" +
                                                   MyAssetBundles.Utility.AssetBundlesOutputPath + "/" +
                                                   MyAssetBundles.Utility.GetPlatformName());
        var manifestOp = AssetBundleManager.Initialize();
        if (manifestOp != null)
        {
            yield return StartCoroutine(manifestOp);
            if (manifestOp.GetAsset<AssetBundleManifest>() == null)
            {
                DebugLogger.Error("[GameLaunch] AssetBundle manifest failed; launch stopped.");
                yield break;
            }
        }

        yield return StartCoroutine(CreateLaunchLoading());

        yield return StartCoroutine(LaunchSequence());
    }

    /// <summary>
    /// 从 AssetBundle 取 LoadingPanel 并实例化（对齐 H02 GameLaunch.cs:82-87）。
    ///
    /// bundle 名规则与 Lua 侧 AssetBundleProvider.resolveBundle 一致：
    ///   "LoadingPanel" -> "ui/loadingpanel.asset"（asset 名大小写敏感，取路径末段原样）
    /// 贴图与 Spine 都作为依赖自动随包拉取，无需在此单独加载。
    ///
    /// 取不到时只告警、不阻断启动 —— LaunchSequence 仍会继续跑。
    /// </summary>
    private IEnumerator CreateLaunchLoading()
    {
        string bundleName = "ui/" + LoadingPrefabName.ToLowerInvariant() + ".asset";

        var op = UIAssetBundleHelper.LoadPrefabAsync(bundleName, LoadingPrefabName);
        if (op == null)
        {
            DebugLogger.Warn(
                $"[GameLaunch] 无法发起 LoadingPanel 的 AB 加载：bundle={bundleName} asset={LoadingPrefabName}");
            yield break;
        }

        yield return StartCoroutine(op);

        var prefab = op.IsDone() ? op.GetAsset<GameObject>() : null;
        if (prefab == null)
        {
            DebugLogger.Warn(
                $"[GameLaunch] LoadingPanel 从 AssetBundle 取不到：bundle={bundleName} asset={LoadingPrefabName}\n" +
                "  1) 确认 Assets/Game/AssetsPackage/UI_New/Prefabs/View/Loading/LoadingPanel.prefab 存在\n" +
                $"  2) 确认其 .meta 的 assetBundleName 为 {bundleName}");
            yield break;
        }

        _loadingObj = Instantiate(prefab, transform);
        _loadingObj.name = "LaunchLoading";

        EnsureLoadingCanvas(_loadingObj);
#if UNITY_EDITOR
        RepairLoadingShadersForEditor(_loadingObj);
#endif
        SetLoading(_loadingObj);

        DebugLogger.Info($"[GameLaunch] Loading prefab loaded from AssetBundle: {bundleName}");
    }

    private TMPro.TMP_Text _progressTMP;

#if UNITY_EDITOR
    private readonly System.Collections.Generic.List<Material> _loadingEditorMaterials =
        new System.Collections.Generic.List<Material>();

    private void RepairLoadingShadersForEditor(GameObject obj)
    {
        // Foreign-target bundles can contain no shader program for the Editor graphics API.
        foreach (var graphic in obj.GetComponentsInChildren<Graphic>(true))
        {
            var text = graphic as TMPro.TMP_Text;
            var subMesh = graphic as TMPro.TMP_SubMeshUI;
            var original = text != null ? text.fontSharedMaterial :
                subMesh != null ? subMesh.sharedMaterial : graphic.material;
            if (original == null || original.shader == null || original.shader.isSupported)
                continue;

            string shaderPath;
            switch (original.shader.name)
            {
                case "Spine/SkeletonGraphic":
                    shaderPath = "Assets/ThirdParty/Spine/Runtime/spine-unity/Shaders/SkeletonGraphic/Spine-SkeletonGraphic.shader";
                    break;
                case "TextMeshPro/Mobile/Distance Field":
                    shaderPath = "Assets/TextMesh Pro/Shaders/TMP_SDF-Mobile.shader";
                    break;
                default:
                    DebugLogger.Warn($"[GameLaunch] Unsupported Loading shader: {original.shader.name}");
                    continue;
            }

            var shader = AssetDatabase.LoadAssetAtPath<Shader>(shaderPath);
            if (shader == null || !shader.isSupported)
            {
                DebugLogger.Warn($"[GameLaunch] No Editor-compatible Loading shader: {shaderPath}");
                continue;
            }

            var material = new Material(original) { shader = shader, hideFlags = HideFlags.DontSave };
            _loadingEditorMaterials.Add(material);
            if (text != null) text.fontSharedMaterial = material;
            else if (subMesh != null) subMesh.sharedMaterial = material;
            else graphic.material = material;
            graphic.SetMaterialDirty();
        }
    }

    private void ReleaseLoadingEditorMaterials()
    {
        foreach (var material in _loadingEditorMaterials)
            if (material != null) Destroy(material);
        _loadingEditorMaterials.Clear();
    }
#endif

    private void SetLoading(GameObject obj)
    {
        if (obj == null) return;

        if (ProgressSlider == null)
            ProgressSlider = obj.GetComponentInChildren<Slider>(true);

        if (ProgressText == null)
            ProgressText = obj.GetComponentInChildren<Text>(true);

        if (ProgressText == null)
        {
            var description = obj.transform.Find("ContentRoot/m_SliderBar/TextGroup/m_LoadingDesc");
            _progressTMP = description != null ? description.GetComponent<TMPro.TMP_Text>() :
                obj.GetComponentInChildren<TMPro.TMP_Text>(true);
        }

        if (ProgressSlider != null) ProgressSlider.value = 0;
        SetLoadingText("正在初始化...");
    }

    private void SetLoadingText(string text)
    {
        if (ProgressText != null)
            ProgressText.text = text;
        else if (_progressTMP != null)
            _progressTMP.text = text;
    }

    private void EnsureLoadingCanvas(GameObject obj)
    {
        if (obj == null) return;

        var canvas = obj.GetComponent<Canvas>();
        if (canvas == null)
        {
            canvas = obj.AddComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            canvas.sortingOrder = 9999;

            var scaler = obj.AddComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.screenMatchMode = CanvasScaler.ScreenMatchMode.MatchWidthOrHeight;
            scaler.referenceResolution = new Vector2(1080, 2400);
            scaler.matchWidthOrHeight = 0.5f;

            obj.AddComponent<GraphicRaycaster>();
            DebugLogger.Info("[GameLaunch] Added Canvas(ScreenSpaceOverlay, ScaleWithScreenSize 1080x2400) to LaunchLoading");
        }
        else
        {
            if (canvas.renderMode == RenderMode.ScreenSpaceCamera && canvas.worldCamera == null)
            {
                canvas.renderMode = RenderMode.ScreenSpaceOverlay;
                canvas.sortingOrder = 9999;
                DebugLogger.Info("[GameLaunch] Fixed LaunchLoading Canvas: ScreenSpaceCamera(nil) -> ScreenSpaceOverlay");
            }

            var scaler = obj.GetComponent<CanvasScaler>();
            if (scaler == null)
            {
                scaler = obj.AddComponent<CanvasScaler>();
                scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
                scaler.screenMatchMode = CanvasScaler.ScreenMatchMode.MatchWidthOrHeight;
                scaler.referenceResolution = new Vector2(1080, 2400);
                scaler.matchWidthOrHeight = 0.5f;
                DebugLogger.Info("[GameLaunch] Added CanvasScaler(ScaleWithScreenSize 1080x2400) to existing LaunchLoading Canvas");
            }
        }
    }

    private void HideLaunchLoading()
    {
        if (_loadingObj != null)
        {
            Destroy(_loadingObj);
            _loadingObj = null;
            DebugLogger.Info("[GameLaunch] LaunchLoading destroyed");
        }
#if UNITY_EDITOR
        ReleaseLoadingEditorMaterials();
#endif
    }

    private void Update() => Tick.OnUpdate();
    private void LateUpdate() => Tick.OnLateUpdate();
    private void FixedUpdate() => Tick.OnFixedUpdate();

    private void OnSceneLoaded(Scene scene, LoadSceneMode mode)
    {
        var listeners = FindObjectsOfType<AudioListener>();
        if (listeners != null && listeners.Length > 1)
        {
            for (int i = 0; i < listeners.Length; i++)
            {
                if (listeners[i].gameObject != gameObject)
                {
                    Destroy(listeners[i]);
                }
            }
        }
    }

    private void OnDestroy()
    {
        ReleaseLuaTicks();
        SceneManager.sceneLoaded -= OnSceneLoaded;
#if UNITY_EDITOR
        ReleaseLoadingEditorMaterials();
#endif
        Tick.Clear();
        if (_instance == this) _instance = null;
    }

    private void OnApplicationQuit() => ReleaseLuaTicks();

    public void ReleaseLuaTicks()
    {
        Tick.Unregister(_luaUpdateId);
        Tick.Unregister(_luaLateUpdateId);
        Tick.Unregister(_luaFixedUpdateId);
        _luaUpdateId = _luaLateUpdateId = _luaFixedUpdateId = 0;
        _luaUpdate?.Dispose(); _luaUpdate = null;
        _luaLateUpdate?.Dispose(); _luaLateUpdate = null;
        _luaFixedUpdate?.Dispose(); _luaFixedUpdate = null;
    }

    // =========================================================================
    // 启动流程
    // =========================================================================

    private IEnumerator LaunchSequence()
    {
        if (_isLaunching) yield break;
        _isLaunching = true;

        TimeProfiler.Start("TotalLaunch");

        SetPhase(LaunchPhase.InitLogger, 0.05f, "初始化日志...");
        DebugLogger.SetReleaseEnv(!Debug.isDebugBuild);
        yield return null;

        SetPhase(LaunchPhase.InitFileSystem, 0.10f, "检查文件系统...");
        // 走 Storage 抽象：默认 FileStorage(System.IO)。
        // 微信小游戏接入后，在此处注入 WX SDK 实现即可：Storage.SetStorage(new WeChatStorage());
        try { var p = Application.persistentDataPath; if (!Storage.Current.DirectoryExists(p)) Storage.Current.CreateDirectory(p); }
        catch (Exception e) { DebugLogger.Exception(e); }
        yield return null;

        // 热更版本清单：对齐 H02 GameLaunch.localVersion（UpdateMgr 完整对比/首包更新逻辑待移植）
        var vfPath = FileUtils.ToPersistentPathSys("versions.csv");
        localVersion = VersionFile.FromFile(vfPath) ?? new VersionFile();
        WebDownLoadManager.Ensure();
        WebDownLoadManager.Get().LocalVersion = localVersion;
        DebugLogger.Info("[GameLaunch] localVersion loaded (files={0})", localVersion.GetFileInfoMap().Count);

        // 热更：远端版本对比/首包更新（对齐 H02 UpdateMgr.Initializer）
        // CDN 未配置或关闭开关时自动跳过，开发期不阻断启动。
        if (HotfixSettings.AutoUpdateEnabled && !string.IsNullOrEmpty(HotfixSettings.RemoteAssetUrl))
        {
            SetPhase(LaunchPhase.InitFileSystem, 0.15f, "检查热更...");
            UpdateMgr.Ensure();
            yield return StartCoroutine(UpdateMgr.Get().Initializer());
        }

        SetPhase(LaunchPhase.InitResources, 0.20f, "初始化资源...");
        if (AutoInitResources) yield return StartCoroutine(InitResources());
        yield return null;

        // 原文案是 "启动脚本引擎..."：其中「擎」(U+64CE) 不在 FZCuYuan-M03 SDF 的字符集中，
        // 运行时会退化为方块 □ 并刷 The character with Unicode value ... not found 警告。
        // 该 SDF 是静态生成的静态字形图集，缺字只能靠重新生成字体补齐，改动成本很高，
        // 故在不动字体的前提下改用同义且字形完备的文案（启/动/脚/本 均已验证可用）。
        SetPhase(LaunchPhase.InitLua, 0.40f, "启动脚本...");
        var lua = XLuaManager.Instance;
        lua.LoadMode = ResolveLuaLoadMode(Application.isEditor, LuaLoadMode);
        // 协程版初始化：WebGL / 微信小游戏下 Lua AB 必须异步拉取，
        // 非 WebGL 平台 LoadAsync 会在同一帧内完成，行为与原来一致。
        bool luaReady = false;
        yield return StartCoroutine(lua.InitLuaEnvCoroutine(() => luaReady = true));
        if (!luaReady || lua.GetLuaEnv() == null)
        {
            _isLaunching = false;
            UpdateProgressUI(Progress, "脚本加载失败");
            DebugLogger.Error("[GameLaunch] Lua initialization failed; launch stopped.");
            yield break;
        }

        SetPhase(LaunchPhase.InitModules, 0.60f, "加载框架...");
        bool modulesReady = false;
        yield return StartCoroutine(InitLuaModules(() => modulesReady = true));
        if (!modulesReady || !lua.HasGameStarted)
        {
            _isLaunching = false;
            UpdateProgressUI(Progress, "框架加载失败");
            DebugLogger.Error("[GameLaunch] Lua modules failed; launch stopped.");
            yield break;
        }
        yield return null;

        SetPhase(LaunchPhase.StartGame, 0.90f);
        lua.StartGame();
        yield return null;

        SetPhase(LaunchPhase.Complete, 1.0f, "完成");

        HideLaunchLoading();

        TimeProfiler.End("TotalLaunch");
        DebugLogger.Info($"[GameLaunch] Launch Complete!\n{TimeProfiler.Dump()}");

        _isLaunching = false;
        OnLaunchComplete?.Invoke();
    }

    // Scene debug settings must not make a Player read scripts from the editor project.
    private static global::LuaLoadMode ResolveLuaLoadMode(bool isEditor, global::LuaLoadMode configured)
    {
        return isEditor ? configured : global::LuaLoadMode.Device;
    }

    private IEnumerator InitLuaModules(Action onComplete = null)
    {
        var lua = XLuaManager.Instance;

        lua.LoadScript("Framework.Framework");
        lua.LoadScript("Common.Define");

        lua.SafeDoString(@"
            _G.GameMain = require 'Game.GameMain'
            _G.GameMain.Init()
            local UM = require 'Framework.Core.UpdateManager'
            local TM = require 'Framework.Core.TimerManager'
            _G.__LuaTick  = function(dt) UM:GetInstance():OnUpdate(dt) TM:GetInstance():Update(dt * 1000) end
            _G.__LuaLateTick = function(dt) UM:GetInstance():OnLateUpdate(dt) end
            _G.__LuaFixedTick = function(dt) UM:GetInstance():OnFixedUpdate(dt) end
        ");

        // 把 Inspector 上的离线开关同步进 Lua（覆盖 GameMain.lua 中的默认值）
        // 容错：Macro 此时可能尚未创建，先确保其为表再赋值
        string skipLoginLua = SkipLogin ? "true" : "false";
        lua.SafeDoString("Macro = Macro or {}; Macro.SkipLogin = " + skipLoginLua);
        DebugLogger.Info($"[GameLaunch] Macro.SkipLogin = {SkipLogin} (离线跳过登录)");

        var gameMainTable = lua.GetGlobalValue<LuaTable>("GameMain");
        lua.SetGameMain(gameMainTable);

        ReleaseLuaTicks();
        _luaUpdate = lua.GetGlobalFunction("__LuaTick");
        _luaLateUpdate = lua.GetGlobalFunction("__LuaLateTick");
        if (_luaUpdate != null) _luaUpdateId = Tick.RegisterUpdate(dt => { try { _luaUpdate.Call(dt); } catch (Exception e) { DebugLogger.Exception(e); } });
        else DebugLogger.Error("[GameLaunch] __LuaTick 未定义，Lua 侧 Update 回调链不会被驱动！请检查 GameMain.Init() 是否完整执行。");
        if (_luaLateUpdate != null) _luaLateUpdateId = Tick.RegisterLateUpdate(dt => { try { _luaLateUpdate.Call(dt); } catch (Exception e) { DebugLogger.Exception(e); } });
        else DebugLogger.Error("[GameLaunch] __LuaLateUpdate 未定义，Lua 侧 LateUpdate 回调链不会被驱动！请检查 GameMain.Init() 是否完整执行。");
        _luaFixedUpdate = lua.GetGlobalFunction("__LuaFixedTick");
        if (_luaFixedUpdate != null) _luaFixedUpdateId = Tick.RegisterFixedUpdate(dt => { try { _luaFixedUpdate.Call(dt); } catch (Exception e) { DebugLogger.Exception(e); } });
        else DebugLogger.Error("[GameLaunch] __LuaFixedTick 未定义，Lua 侧 FixedUpdate 回调链不会被驱动！请检查 GameMain.Init() 是否完整执行。");

        SetPhase(LaunchPhase.InitModules, 0.80f, "启动游戏...");
        yield return null;
        onComplete?.Invoke();
    }

    protected virtual IEnumerator InitResources() { yield return null; }

    // =========================================================================
    // 进度 UI
    // =========================================================================

    private void SetPhase(LaunchPhase phase, float progress, string desc = "")
    {
        CurrentPhase = phase;
        Progress = progress;
        OnPhaseChanged?.Invoke(phase);
        UpdateProgressUI(progress, desc);
    }

    public void UpdateProgressUI(float progress, string desc = "")
    {
        if (ProgressSlider != null) ProgressSlider.value = progress;
        if (!string.IsNullOrEmpty(desc)) SetLoadingText(desc);
    }

    // =========================================================================
    // 调试
    // =========================================================================

    [ContextMenu("Start Battle")]
    public void StartBattle()
    {
        XLuaManager.Instance.SafeDoString("GameMain.StartBattle({})");
    }

    [ContextMenu("Shutdown Lua")]
    public void ShutdownLua()
    {
        XLuaManager.Instance.Dispose();
    }
}
