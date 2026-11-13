// =============================================================================
// HomeSceneBootstrapper.cs
// =============================================================================
// 主界面场景引导器。
// 挂载到 HomeScene，负责：
//   1. 创建场景相机 + 俯视角跟随
//   2. 创建地面 + 玩家视觉对象
//   3. 启动 Lua 战斗系统（BattleManager）
//   4. 将摇杆输入桥接到 Lua PlayerController
//   5. 每帧同步 Lua 玩家坐标到 Unity Transform
//
// 设计原则（腾讯大厂级）：
//   - 职责单一：只做场景可视层初始化 + 输入桥接
//   - 延迟绑定：Lua 侧 BattleManager 可能晚于 C# Start，使用轮询重试
//   - 防御性编程：所有 Lua 调用 try-catch 包裹，避免崩溃
//   - 内存安全：OnDestroy 清空 Lua 引用，不主动 Dispose（LuaEnv 生命周期由框架管理）
// =============================================================================

using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.SceneManagement;
using UnityEngine.UI;
using XLua;
using System;
using System.Collections.Generic;

[LuaCallCSharp]
public class HomeSceneBootstrapper : MonoBehaviour
{
    [Header("Scene Camera")]
    [Tooltip("场景相机（俯视角跟随玩家），如为空则自动创建")]
    public Camera sceneCamera;

    [Header("Ground")]
    [Tooltip("地面边长。相机视野半宽约 28，玩家活动半径 22，地面需足够大才不会看到边缘虚空")]
    public float groundSize = 110f;
    public float playBounds = 22f;

    [Header("Player Visual")]
    public float playerSize = 1f;
    public Color playerColor = new Color(0.2f, 0.8f, 1f, 1f);

    [Header("3D 角色模型（替换默认方块角色；留空则用 Cube+Cylinder 占位）")]
    public GameObject playerModelPrefab;

    [Header("战斗实体表现层 prefab（由 Lua 组件驱动，见 LuaViewBehaviour）")]
    [Tooltip("敌人/怪物复用的人形模型（QuaterniusHero / BaseCharacter 等）。留空则 Lua 兜底为占位体。")]
    public GameObject enemyModelPrefab;
    [Tooltip("子弹 prefab（玩家=黄 / 敌人=红；缺失则 Lua 兜底发光球）")]
    public GameObject bulletPlayerPrefab;
    public GameObject bulletEnemyPrefab;
    [Tooltip("掉落物 prefab：武器 / 材料 / 道具 模型各异（缺失则 Lua 兜底几何体）")]
    public GameObject dropWeaponPrefab;
    public GameObject dropMaterialPrefab;
    public GameObject dropItemPrefab;

    [Header("Camera Follow")]
    [Tooltip("跟随平滑系数。5 会有明显拖尾感；10 左右接近荒野乱斗的跟手手感")]
    public float followLerp = 10f;
    public float cameraHeight = 22f;
    public float cameraDepth = -16f;

    [Header("Battle Config")]
    public float playerMoveSpeed = 5f;
    public float playerMaxHp = 100f;
    public float playerAtk = 10f;

    [Header("Mode / Portal")]
    [Tooltip("true=战斗场景（启动 Lua 战斗，移动由 BattleManager 驱动）；false=主城场景（C# 本地移动 + 洞口传送）")]
    public bool startBattle = true;
    [Tooltip("洞口传送目标场景名（SceneConfig 中的 key，如 'Battle'），仅主城模式生效")]
    public string portalSceneName = "";
    [Tooltip("进入洞口触发半径")]
    public float portalTriggerRadius = 2.5f;

    [Tooltip("调试兜底：LuaEnv 未就绪（直接打开本场景按 Play）时，用 SceneManager 直接加载的 Unity 场景名。\r\n" +
             "正式流程走 Launch + GameMain.SwitchScene，不会用到此项；留空则禁用兜底。")]
    public string portalFallbackSceneName = "BattleScene";

    private GameObject _groundObj;
    private GameObject _playerObj;
    private Transform _playerTransform;
    private Model3DCharacterView _playerView;
    private CharacterState _playerState = CharacterState.Stand;
    private TopDownCameraFollow _cameraFollow;
    private HomeClearingEnvironment _homeClearing;
    private CharacterController _homeCharacterController;

    private LuaEnv _luaEnv;
    private LuaTable _playerController;
    private LuaFunction _setInputFunc;
    private bool _battleBound;

    // 主城模式：点击移动目的地
    private Vector3? _destination;

    // 主城模式：右键移动的地表标记 / 左键交互控制器
    private MoveClickIndicator _moveMarker;
    private InteractionController _interaction;

    /// <summary>
    /// 摇杆引用。由 Lua 侧 HomeView 通过 BindJoystick 传入。
    /// 采用「C# 每帧轮询 GetOutput()」而非「Lua 注册 onMove 回调」
    /// —— 因为 XLua 无法把 Lua 函数注册到自定义 UnityEvent&lt;Vector2&gt; 子类
    /// （JoystickMoveEvent 没有生成 delegate 桥），AddListener 会直接抛异常，
    /// 导致 HomeView:OnCreate 中断、面板创建失败。
    /// </summary>
    private VirtualJoystick _joystick;

    /// <summary>
    /// 绑定摇杆（由 Lua HomeView 调用）
    /// </summary>
    public void BindJoystick(VirtualJoystick joystick)
    {
        _joystick = joystick;
        if (_joystick != null)
        {
            // 切场景 / 传送后重新绑定持久化摇杆时，先复位到中性，
            // 避免上一场景残留的「按住方向」被新场景读走，导致角色自动移动。
            // （摇杆组件挂在复用的 HomePanel 上，不会随场景卸载而销毁，必须主动复位。）
            _joystick.Reset();
            // 一并清掉自身的点击移动目标：虽然新场景的 Bootstrapper 是全新实例（_destination 天然为 null），
            // 但这里统一复位，覆盖「同场景内面板被关闭再重开」的边界，并与摇杆 Reset 形成对称的输入复位。
            _destination = null;
            Debug.Log("[HomeSceneBootstrapper] Joystick bound (C# polling mode)");
        }
        else
        {
            Debug.Log("[HomeSceneBootstrapper] BindJoystick called with null");
        }
    }

    public VirtualJoystick GetJoystick()
    {
        return _joystick;
    }

    void Start()
    {
        // 入口互斥（P0-1.5）：正式链路由 GameLaunch/Tick 统一驱动，本 Bootstrapper 是表现层。
        // 若 legacy 的 LuaGameBootstrap 已抢先启动（例如 XLuaManager 在 Awake 阶段短暂为 null
        // 导致其守卫失效），本组件必须整体让路，避免与 legacy 双启 Lua、双建 battleManager。
        var legacy = FindObjectOfType<LuaGameBootstrap>();
        if (legacy != null && legacy.IsRunning)
        {
            Debug.Log("[HomeSceneBootstrapper] legacy LuaGameBootstrap 已接管，本组件整体让路并返回（不初始化表现层，避免双份创建）。");
            return;
        }

        // My project 由 GameLaunch + XLuaManager 统一驱动 Lua，优先从 XLuaManager 取 Env；
        // 遗留 LuaGameBootstrap 在本项目中应跳过初始化（见其 Awake 守卫），不作为 Env 来源。
        if (XLuaManager.Instance != null)
            _luaEnv = XLuaManager.Instance.GetLuaEnv();
        if (_luaEnv == null)
            _luaEnv = FindObjectOfType<LuaGameBootstrap>()?.GetLuaEnv();

        // 无论 Lua 环境是否就绪，都先把相机 / 地面 / 角色建出来。
        // 否则单独打开本场景（未走 Launch 启动流程，LuaEnv 为 null）时 Start 会提前 return，
        // 导致角色根本不被创建 —— 表现为「人物没动作 / 看不到角色」。
        if (!startBattle)
        {
            var clearing = GetComponent<HomeClearingEnvironment>();
            if (clearing != null && clearing.IsValid(playBounds, portalTriggerRadius))
                _homeClearing = clearing;
            else if (clearing != null)
                Debug.LogError("[HomeClearing] Invalid scene references or ground/entrance bounds; using legacy ground and portal.");
        }
        CreateSceneCamera();
        CreateGround();
        CreatePlayer();

        if (_homeClearing != null)
        {
            _homeCharacterController = _playerObj.AddComponent<CharacterController>();
            _homeCharacterController.height = 1.8f;
            _homeCharacterController.radius = 0.32f;
            _homeCharacterController.center = new Vector3(0f, 0.9f, 0f);
            _homeCharacterController.skinWidth = 0.025f;
            _homeCharacterController.stepOffset = 0.08f;
            _homeCharacterController.minMoveDistance = 0f;
        }

        // 地表移动标记：主城与战斗两种模式都支持右键点地面移动，故统一创建
        CreateMoveMarker();

        // 交互控制器（左键点击物件 / 走近自动触发）两种模式都需要：
        // 否则战斗场景里放不了「回城传送点」，主城里也点不了洞口。
        CreateInteraction();

        if (!startBattle)
        {
            // 主城模式：C# 本地移动 + 洞口传送到战斗场景（目标由 portalSceneName 决定，当前 = "Battle"）
            CreatePortal();
            Debug.Log("[HomeSceneBootstrapper] 主城模式：右键/摇杆移动 + 左键交互 + 洞口传送（不启动战斗）。");
        }
        else
        {
            // 战斗模式：额外放一个「回城传送点」，点击或走近即传回主城（Home）。
            // 真正的战斗启动仍由 Lua 驱动（见下方 StartBattle），放在这里不影响。
            CreatePortal("Home", "Return to Home", new Vector3(0f, 0f, -16f));
            if (_luaEnv != null)
            {
                StartBattle();
            }
            else
            {
                Debug.LogWarning("[HomeSceneBootstrapper] LuaEnv 未就绪，跳过战斗启动；角色仍会显示并播待机动画。");
            }
        }

        // 离线调试兜底：直接打开本场景按 Play 时没有 Lua 环境，需要自行把摇杆建出来
        CreateDebugUI();
    }

    void Update()
    {
        EnsureJoystick();
        RefreshHud();
        if (Input.GetKeyDown(KeyCode.F1)) _showHud = !_showHud;

        // 调试热键 N：强制进入下一层（绕过层间事件弹窗卡死，方便测试深层）
        if (Input.GetKeyDown(KeyCode.N) && _luaEnv != null)
        {
            try
            {
                _luaEnv.DoString("local GM=require('Game.GameMain'); local d=GM.GetDungeonManager(); if d and d.NextFloor then d:NextFloor() end");
            }
            catch (System.Exception e) { Debug.LogWarning("[HomeSceneBootstrapper] NextFloor hotkey failed: " + e.Message); }
        }

        if (startBattle)
        {
            // ===== 战斗模式：移动由 Lua BattleManager 驱动（沿用原逻辑） =====
            if (_luaEnv == null)
            {
                // 无 Lua 环境（典型：直接打开本场景按 Play，未经 GameLaunch）：
                // 既没有 BattleManager 也没有场景脚本，若在此直接 return，
                // Update 什么都不做 —— 即使摇杆已绑定，角色也完全不动。
                // 必须退化为 C# 本地移动兜底。
                UpdateLocalMove();
                return;
            }

            if (!_battleBound)
            {
                TryBindPlayer();

                // Lua 战斗尚未就绪时退化为 C# 本地移动，保证摇杆依然能操作角色。
                // 典型场景：直接打开 BattleScene 按 Play —— 此时没有 GameLaunch，
                // 也就没有 XLuaManager（Lua 环境）和 Tick 驱动，Lua 侧 Update 链完全不跑。
                UpdateLocalMove();
                return;
            }

            if (_playerController == null) return;

            // 右键点击地面下达移动指令（与主城保持一致的操作方式）
            HandleClickToMove();

            // 地表标记同步：有目的地时显示，抵达或被摇杆取消后淡出
            if (_moveMarker != null)
            {
                if (_destination.HasValue) _moveMarker.MoveTo(_destination.Value);
                else _moveMarker.Hide();
            }

            // 【关键】战斗模式下角色位置由 Lua BattleManager 驱动：
            // SyncPlayerPosition() 每帧会用 Lua 坐标直接覆盖 transform.position，
            // 所以不能像主城那样在这里直接改 transform（会被下一帧覆盖、看起来没反应）。
            // 正确做法是把「方向」作为输入转发给 Lua，由 BattleManager 真正移动角色。
            //
            // 输入优先级：摇杆 > 点击目的地 > 停止
            bool inputHandled = false;

            // 摇杆输入：C# 侧每帧轮询，避免依赖 XLua 的 UnityEvent delegate 桥
            if (_joystick != null)
            {
                Vector2 joy = _joystick.GetOutput();
                if (joy.sqrMagnitude > 0.01f)
                {
                    SetJoystickInput(joy.x, joy.y);
                    _destination = null;   // 摇杆接管，取消点击移动
                    inputHandled = true;
                }
            }

            if (!inputHandled && _destination.HasValue && _playerTransform != null)
            {
                Vector3 to = _destination.Value - _playerTransform.position;
                to.y = 0f;
                if (to.sqrMagnitude < 0.04f)
                {
                    _destination = null;            // 抵达目的地
                    SetJoystickInput(0f, 0f);
                }
                else
                {
                    Vector3 dir = to.normalized;
                    SetJoystickInput(dir.x, dir.z); // 方向交给 Lua 去走
                    inputHandled = true;
                }
            }

            if (!inputHandled)
                SetJoystickInput(0f, 0f);

            SyncPlayerPosition();
            SyncEnemies();   // 仅敌人 HUD（血条/飘字）；敌人 3D 表现由 Lua 组件驱动
            SyncPlayerCombat();
            if (!_combatPaused) UpdatePopups();

            Vector3 moveDir = Vector3.zero;
            moveDir.x = LuaFieldReader.GetOr(_playerController, "inputX", 0f);
            moveDir.z = LuaFieldReader.GetOr(_playerController, "inputY", 0f);

            bool moving = moveDir.sqrMagnitude > 0.001f;
            if (moving)
            {
                // 朝向移动方向：父节点 +Z 对齐移动方向（模型 forward 已设为 +Z）
                Quaternion targetRot = Quaternion.LookRotation(moveDir.normalized, Vector3.up);
                _playerTransform.rotation = Quaternion.Slerp(
                    _playerTransform.rotation,
                    targetRot,
                    Time.deltaTime * followLerp
                );
            }

            // 状态驱动：移动时播放 Walk，停下回到 Stand（让模型有动作）
            if (_playerView != null)
            {
                CharacterState desired = moving ? CharacterState.Walk : CharacterState.Stand;
                if (desired != _playerState)
                {
                    _playerView.Play(desired);
                    _playerState = desired;
                }
            }
            return;
        }

        // ===== 主城模式：C# 本地移动（摇杆优先 + 点击目的地）+ 洞口传送 =====
        if (_playerTransform == null) return;

        UpdateLocalMove();

        // 洞口传送已交给 Interactable + InteractionController 统一处理：
        // 既可左键点击触发，也保留靠近（allowProximity）自动触发，这里不再重复判定。
    }

    /// <summary>
    /// C# 本地移动：摇杆优先 + 点击目的地 + 动画状态驱动。
    ///   - 主城模式：作为正式移动方式
    ///   - 战斗模式：仅在 Lua 战斗未就绪时兜底使用，保证摇杆依然能操作角色
    /// </summary>
    private void UpdateLocalMove()
    {
        if (_playerTransform == null) return;

        HandleClickToMove();

        // 地表移动标记：有目的地时保持显示，抵达或被摇杆取消后自动淡出消失
        if (_moveMarker != null)
        {
            if (_destination.HasValue) _moveMarker.MoveTo(_destination.Value);
            else _moveMarker.Hide();
        }

        Vector3 moveDir = Vector3.zero;

        // 1) 摇杆优先
        if (_joystick != null)
        {
            Vector2 joy = _joystick.GetOutput();
            if (joy.sqrMagnitude > 0.01f)
            {
                moveDir = new Vector3(joy.x, 0f, joy.y);
                _destination = null; // 摇杆接管，取消点击移动
            }
        }

        // 2) 点击目的地移动
        if (moveDir.sqrMagnitude < 1e-4f && _destination.HasValue)
        {
            Vector3 to = _destination.Value - _playerTransform.position;
            to.y = 0f;
            if (to.sqrMagnitude < 0.04f)
            {
                _destination = null;
            }
            else
            {
                moveDir = to.normalized;
            }
        }

        bool moving = moveDir.sqrMagnitude > 1e-4f;
        if (moving)
        {
            // 注意：不要在这里对 moveDir 做 Normalize()。
            // 摇杆分支的 moveDir 来自 VirtualJoystick.GetOutput()（方向×强度，长度 0~1），
            // 必须保留强度才能让「推多少走多快」与 BattleScene(Lua) 完全一致；
            // 否则主城恒满速、战斗变速，同样半推时两场景位移差一倍，
            // 看起来就像「地图大小不一样」。点击移动分支用的是 to.normalized（已是单位向量），不受影响。
            Vector3 np = _playerTransform.position + moveDir * playerMoveSpeed * Time.deltaTime;
            np.x = Mathf.Clamp(np.x, -playBounds, playBounds);
            np.z = Mathf.Clamp(np.z, -playBounds, playBounds);
            np.y = 0f;
            if (_homeCharacterController != null)
            {
                Vector3 before = _playerTransform.position;
                _homeCharacterController.Move(new Vector3(np.x - before.x, -2f * Time.deltaTime, np.z - before.z));
                moving = (_playerTransform.position - before).sqrMagnitude > 0.000001f;
            }
            else
                _playerTransform.position = np;

            Quaternion targetRot = Quaternion.LookRotation(moveDir, Vector3.up);
            _playerTransform.rotation = Quaternion.Slerp(
                _playerTransform.rotation,
                targetRot,
                Time.deltaTime * followLerp
            );
        }

        // 状态驱动：移动时 Walk，停下 Stand
        if (_playerView != null)
        {
            CharacterState desired = moving ? CharacterState.Walk : CharacterState.Stand;
            if (desired != _playerState)
            {
                _playerView.Play(desired);
                _playerState = desired;
            }
        }
    }

    public void SetJoystickInput(float x, float y)
    {
        if (_setInputFunc == null || _playerController == null) return;

        try
        {
            _setInputFunc.Call(_playerController, x, y);
        }
        catch (Exception e)
        {
            Debug.LogError($"[HomeSceneBootstrapper] SetInput error: {e.Message}");
        }
    }

    void OnDestroy()
    {
        ReleaseLuaBindings();
    }

    public void ReleaseLuaBindings()
    {
        enabled = false;
        _setInputFunc?.Dispose(); _setInputFunc = null;
        _playerController?.Dispose(); _playerController = null;
        _luaEnv = null;
        _battleBound = false;
    }

    private void CreateSceneCamera()
    {
        if (sceneCamera == null)
        {
            var camObj = new GameObject("SceneCamera");
            camObj.transform.SetParent(transform, false);
            sceneCamera = camObj.AddComponent<Camera>();
            sceneCamera.depth = 0;
            sceneCamera.clearFlags = CameraClearFlags.SolidColor;
            sceneCamera.backgroundColor = new Color(0.12f, 0.14f, 0.18f, 1f);
            sceneCamera.orthographic = false;
            sceneCamera.fieldOfView = 60f;
            sceneCamera.nearClipPlane = 0.3f;
            sceneCamera.farClipPlane = 200f;

            var audioListener = camObj.AddComponent<AudioListener>();
        }

        // 无论相机是新建的还是场景里已有的，都强制统一为透视投影。
        // 否则场景里预置的正交相机会被原样保留（BattleScene 曾因此是正交、
        // HomeScene 是透视，两个场景远近观感完全不一致）。
        // 俯视角依赖 heightOffset/depthOffset 构成的透视关系，必须走透视。
        sceneCamera.orthographic = false;

        sceneCamera.transform.position = new Vector3(0f, cameraHeight, cameraDepth);
        // 初始朝向同样用 LookAt 反算（旧的 Atan2 参数顺序颠倒会瞄偏，导致角色不居中）。
        // 玩家起始点在原点，抬高 1m 瞄准身体；之后每帧由 TopDownCameraFollow 接管修正。
        sceneCamera.transform.LookAt(new Vector3(0f, 1f, 0f));

        _cameraFollow = sceneCamera.gameObject.AddComponent<TopDownCameraFollow>();
        _cameraFollow.followLerp = followLerp;
        _cameraFollow.heightOffset = cameraHeight;
        _cameraFollow.depthOffset = cameraDepth;
        _cameraFollow.useBounds = true;
        _cameraFollow.boundsMin = new Vector3(-playBounds, 0f, -playBounds);
        _cameraFollow.boundsMax = new Vector3(playBounds, 0f, playBounds);
    }

    private void CreateGround()
    {
        if (_homeClearing != null)
        {
            _groundObj = _homeClearing.Ground;
            return;
        }

        _groundObj = GameObject.CreatePrimitive(PrimitiveType.Plane);
        _groundObj.name = "BattleGround";
        _groundObj.transform.SetParent(transform, false);
        _groundObj.transform.localScale = new Vector3(groundSize / 10f, 1f, groundSize / 10f);

        var rend = _groundObj.GetComponent<Renderer>();
        if (rend != null)
        {
            var shader = Shader.Find("Custom/BattleGrid");
            if (shader != null)
            {
                var mat = new Material(shader);
                mat.SetColor("_BaseColor", new Color(0.18f, 0.22f, 0.28f, 1f));
                mat.SetColor("_GridColor", new Color(0.35f, 0.40f, 0.50f, 1f));
                mat.SetColor("_BoundsColor", Color.yellow);
                mat.SetFloat("_GridSize", 2.0f);
                mat.SetFloat("_LineWidth", 1.5f);
                mat.SetFloat("_Bounds", playBounds);
                mat.SetFloat("_Fade", 1.0f);
                rend.material = mat;
            }
            else
            {
                rend.material.color = new Color(0.18f, 0.22f, 0.28f);
            }
        }
    }

    private void CreatePlayer()
    {
        _playerObj = new GameObject("Player");
        _playerObj.transform.SetParent(transform, false);
        _playerObj.transform.position = Vector3.zero;
        _playerTransform = _playerObj.transform;

        if (playerModelPrefab != null)
        {
            // 用 3D 角色模型（如 SpikeCharacter）替换默认方块角色。
            // 朝向/移动/相机跟随仍由 Bootstrapper 统一驱动；关闭模型自带自转，避免与「朝向移动方向」冲突。
            var model = (GameObject)Instantiate(playerModelPrefab);
            model.name = "PlayerModel";
            model.transform.SetParent(_playerTransform, false);
            var cv = model.GetComponent<Model3DCharacterView>();
            if (cv != null)
            {
                _playerView = cv;
                cv.Play(CharacterState.Stand);
            }
        }
        else
        {
            var body = GameObject.CreatePrimitive(PrimitiveType.Cube);
            body.name = "Body";
            body.transform.SetParent(_playerTransform, false);
            body.transform.localPosition = new Vector3(0f, playerSize * 0.5f, 0f);
            body.transform.localScale = Vector3.one * playerSize;
            var bodyRend = body.GetComponent<Renderer>();
            if (bodyRend != null) bodyRend.material.color = playerColor;

            var nose = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
            nose.name = "Nose";
            nose.transform.SetParent(_playerTransform, false);
            nose.transform.localRotation = Quaternion.Euler(90f, 0f, 0f);
            nose.transform.localPosition = new Vector3(0f, playerSize * 0.5f, playerSize * 0.6f);
            nose.transform.localScale = new Vector3(playerSize * 0.4f, playerSize * 0.4f, playerSize * 0.6f);
            var noseRend = nose.GetComponent<Renderer>();
            if (noseRend != null) noseRend.material.color = Color.white;
        }

        if (_cameraFollow != null)
            _cameraFollow.SetTarget(_playerTransform);
    }

    private void StartBattle()
    {
        if (_luaEnv == null) return;

        try
        {
            string script = @"
                local GameMain = require 'Game.GameMain'
                GameMain.StartBattle({
                    player = {
                        maxHp = 100,
                        atk = 10,
                        moveSpeed = 5.0,
                        boundsMinX = -22,
                        boundsMaxX = 22,
                        boundsMinY = -22,
                        boundsMaxY = 22,
                    },
                    maxTime = 1200,
                    waves = {},
                })
            ";
            _luaEnv.DoString(script);
            Debug.Log("[HomeSceneBootstrapper] Battle started via Lua");
        }
        catch (Exception e)
        {
            Debug.LogError($"[HomeSceneBootstrapper] StartBattle error: {e.Message}");
        }
    }

    private int _bindAttempts;

    private void TryBindPlayer()
    {
        if (_luaEnv == null) return;

        // 该调用每帧执行直到绑定成功，日志必须节流，否则刷屏
        _bindAttempts++;
        bool log = _bindAttempts == 1 || _bindAttempts % 120 == 0;

        try
        {
            var gameMain = _luaEnv.Global.GetInPath<LuaTable>("GameMain");
            if (gameMain == null)
            {
                if (log) Debug.LogWarning("[HomeSceneBootstrapper] 绑定失败：_G.GameMain 不存在（GameMain.Init 未执行？）");
                return;
            }

            var getBattleMgr = gameMain.Get<LuaFunction>("GetBattleManager");
            if (getBattleMgr == null)
            {
                if (log) Debug.LogWarning("[HomeSceneBootstrapper] 绑定失败：GameMain.GetBattleManager 不存在");
                return;
            }

            object[] ret = getBattleMgr.Call(gameMain);
            if (ret == null || ret.Length == 0 || ret[0] == null)
            {
                if (log) Debug.LogWarning($"[HomeSceneBootstrapper] 绑定失败：BattleManager 为 nil" +
                    $"（StartBattle 未执行或已失败？retLen={ret?.Length ?? -1}）");
                return;
            }

            var battleMgr = ret[0] as LuaTable;
            if (battleMgr == null)
            {
                if (log) Debug.LogWarning($"[HomeSceneBootstrapper] 绑定失败：返回的不是 LuaTable（实际 {ret[0].GetType().Name}）");
                return;
            }

            _playerController = battleMgr.Get<LuaTable>("playerController");
            if (_playerController == null)
            {
                if (log) Debug.LogWarning("[HomeSceneBootstrapper] 绑定失败：battleManager.playerController 为 nil");
                return;
            }

            _setInputFunc = _playerController.Get<LuaFunction>("SetInput");
            _battleBound = true;

            // 把表现层需要的 prefab 引用注入 Lua 全局 ViewConfig（供 Lua 视图 Instantiate 真实预制体）
            InjectViewConfig();

            if (_playerTransform != null)
            {
                var bind = _playerController.Get<LuaFunction>("BindView");
                bind?.Call(_playerController, _playerTransform);
            }

            Debug.Log("[HomeSceneBootstrapper] PlayerController bound, battle view active");
        }
        catch (System.Exception e)
        {
            // 原实现用空 catch 吞掉一切异常，绑定失败时完全无线索，这里必须打出来
            if (log) Debug.LogWarning($"[HomeSceneBootstrapper] 绑定异常: {e.Message}");
        }
    }

    /// <summary>
    /// 把战斗表现层需要的 prefab 引用注入到 Lua 全局 ViewConfig，
    /// 供 Lua 视图（EnemyView / DropView / BulletView）Instantiate 真实预制体。
    /// 缺失的字段为 null，Lua 侧会自动降级为几何体兜底，保证逻辑不崩。
    /// </summary>
    private void InjectViewConfig()
    {
        if (_luaEnv == null) return;
        try
        {
            _luaEnv.DoString("__EnsureViewConfig = function() _G.ViewConfig = _G.ViewConfig or {} end");
            _luaEnv.DoString("__EnsureViewConfig()");
            var vc = _luaEnv.Global.Get<LuaTable>("ViewConfig");
            if (vc == null) return;

            // 编辑器下自动补齐缺失的敌人模型/动画控制器，免去手动跑
            // Tools/Battle/Generate View Prefabs。产物本应随仓库提交，这里只兜底。
#if UNITY_EDITOR
            // 通过反射调用 Editor 程序集的 Game.EditorTools.ViewPrefabBuilder，
            // 避免运行时程序集直接引用 Editor 程序集导致 CS0234 编译失败。
            EnsureEditorViewPrefabs();

            // Inspector 没手拖时，从生成目录兜底取（子弹 / 掉落物）
            if (bulletPlayerPrefab == null) bulletPlayerPrefab = LoadEditorBattleViewPrefab("BulletPlayer");
            if (bulletEnemyPrefab  == null) bulletEnemyPrefab  = LoadEditorBattleViewPrefab("BulletEnemy");
            if (dropWeaponPrefab   == null) dropWeaponPrefab   = LoadEditorBattleViewPrefab("DropWeapon");
            if (dropMaterialPrefab == null) dropMaterialPrefab = LoadEditorBattleViewPrefab("DropMaterial");
            if (dropItemPrefab     == null) dropItemPrefab     = LoadEditorBattleViewPrefab("DropItem");
#endif

            // 敌人模型：优先用 Inspector 字段；未配则运行时从 Resources 加载 QuaterniusHero（区别于玩家的 SpikeCharacter）；
            // 再否则复用玩家模型。避免「字段未拖 → Lua 走空 FallbackBody → 敌人隐形只剩血条」。
            // 敌人模型优先级：模型库带动作的 EnemyModel（默认）> Inspector 字段（用户显式覆盖）> QuaterniusHero（无动作兜底）> 玩家模型
            var enemyModel = Resources.Load<GameObject>("Characters/EnemyModel");
            if (enemyModel == null) enemyModel = enemyModelPrefab;
            if (enemyModel == null) enemyModel = Resources.Load<GameObject>("Characters/QuaterniusHero");
            if (enemyModel == null) enemyModel = playerModelPrefab;
            if (enemyModel == null)
                Debug.LogWarning("[ViewConfig] 敌人模型未能加载：请在 Inspector 配 enemyModelPrefab，或运行 Tools/Battle/Generate View Prefabs 生成 EnemyModel，否则敌人将仅显示血条。");
            else
                Debug.Log("[ViewConfig] 敌人模型已注入: " + enemyModel.name);
            vc.Set("enemyModel", enemyModel);
            vc.Set("bulletPlayer", bulletPlayerPrefab);
            vc.Set("bulletEnemy", bulletEnemyPrefab);
            vc.Set("dropWeapon", dropWeaponPrefab);
            vc.Set("dropMaterial", dropMaterialPrefab);
            vc.Set("dropItem", dropItemPrefab);

            // 玩家视图：受伤表现（闪红 / 缩放脉冲）由 Lua 的 DamageSystem 调用 FlashHurt。
            // 走 ViewConfig 注入而不是让 Lua 去找静态单例 —— 与 enemyModel 等保持同一套路。
            if (_playerView != null) vc.Set("playerView", _playerView);
        }
        catch (System.Exception e)
        {
            Debug.LogWarning("[HomeSceneBootstrapper] InjectViewConfig error: " + e.Message);
        }
    }

#if UNITY_EDITOR
    // ---- 反射桥接 Editor 程序集（Game.EditorTools.ViewPrefabBuilder），避免运行时程序集反向引用 Editor 程序集 ----
    private static void EnsureEditorViewPrefabs()
    {
        var t = FindEditorToolsType("ViewPrefabBuilder");
        if (t == null) return;
        var m = t.GetMethod("EnsureEnemyAssetsExist", System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Static);
        m?.Invoke(null, null);
    }

    private static GameObject LoadEditorBattleViewPrefab(string name)
    {
        var t = FindEditorToolsType("ViewPrefabBuilder");
        if (t == null) return null;
        var m = t.GetMethod("LoadBattleViewPrefab", System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Static);
        if (m == null) return null;
        return m.Invoke(null, new object[] { name }) as GameObject;
    }

    private static System.Type FindEditorToolsType(string typeName)
    {
        foreach (var asm in System.AppDomain.CurrentDomain.GetAssemblies())
        {
            var t = asm.GetType("Game.EditorTools." + typeName);
            if (t != null) return t;
        }
        return null;
    }
#endif

    private void SyncPlayerPosition()
    {
        if (_playerTransform == null || _playerController == null) return;

        try
        {
            var getPos = _playerController.Get<LuaFunction>("GetPosition");
            object[] r = getPos.Call(_playerController);
            float px = System.Convert.ToSingle(r[0] ?? 0);
            float py = System.Convert.ToSingle(r[1] ?? 0);
            _playerTransform.position = new Vector3(px, 0f, py);
        }
        catch (Exception e)
        {
            Debug.LogError($"[HomeSceneBootstrapper] SyncPos error: {e.Message}");
        }
    }

    // ===== 战斗反馈：头顶血条 + 飘字伤害（HUD 调试叠加层） =====
    // 敌人的 3D 表现已由 Lua 组件（EnemyView/DropView/BulletView）通过真实 prefab 驱动，
    // 这里只负责把敌人 hp 数据投影成头顶血条 / 伤害飘字，不再创建任何实体 GameObject。
    // 逻辑层只存数据，这里每帧轮询 hp 变化来生成飘字，并把 hp/maxHp 投影成头顶血条。
    // 全部是纯 C# 渲染，不改动任何 Lua。
    private class EnemyBarInfo { public Vector3 worldPos; public float hp; public float maxHp; public string enemyType = "normal"; public bool isElite; }
    private class DamagePopup { public Vector3 worldPos; public float value; public float age; public bool isCrit; public bool isPlayer; }
    private List<EnemyBarInfo> _enemyBars = new List<EnemyBarInfo>();
    private Dictionary<int, float> _enemyLastHp = new Dictionary<int, float>();
    private List<DamagePopup> _popups = new List<DamagePopup>();
    private const float PopupLife = 0.9f;
    private bool _combatPaused;

    private float _playerHp = 100f, _playerMaxHp = 100f, _playerLastHp = -1f;
    private Vector3 _playerWorldPos = Vector3.zero;

    private void ResetCombatState()
    {
        _combatPaused = false;
        _enemyBars.Clear();
        _enemyLastHp.Clear();
        _popups.Clear();
        _playerLastHp = -1f;   // 重新进战时避免误报一次伤害飘字
    }

    private void SyncPlayerCombat()
    {
        if (_playerController == null) return;
        try
        {
            float hp = 100f, maxHp = 100f;
            hp = LuaFieldReader.GetOr(_playerController, "hp", hp);
            maxHp = LuaFieldReader.GetOr(_playerController, "maxHp", maxHp);
            _playerHp = hp; _playerMaxHp = maxHp;
            if (_playerTransform != null) _playerWorldPos = _playerTransform.position + Vector3.up * 1.6f;

            if (_playerLastHp > 0f && hp < _playerLastHp - 1e-4)
            {
                _popups.Add(new DamagePopup
                {
                    worldPos = _playerWorldPos,
                    value = _playerLastHp - hp,
                    age = 0f,
                    isCrit = false,
                    isPlayer = true
                });
            }
            _playerLastHp = hp;
        }
        catch (Exception e) { LuaFieldReader.WarnOnce("HomeSceneBootstrapper.SyncPlayerCombat", e); }
    }

    private void UpdatePopups()
    {
        for (int i = _popups.Count - 1; i >= 0; i--)
        {
            var p = _popups[i];
            p.age += Time.deltaTime;
            p.worldPos.y += Time.deltaTime * 1.2f;   // 向上飘
            if (p.age >= PopupLife) _popups.RemoveAt(i);
        }
    }

    // 敌人 HUD（头顶血条 + 伤害飘字）：纯 C# 调试叠加层，不创建任何实体 GameObject。
    // 敌人的 3D 表现已由 Lua 组件（EnemyView）通过真实 prefab 驱动，见 LuaViewBehaviour / EntityViewFactory。
    private void SyncEnemies()
    {
        if (!_battleBound) { ResetCombatState(); return; }

        var gameMain = _luaEnv != null ? _luaEnv.Global.GetInPath<LuaTable>("GameMain") : null;
        if (gameMain == null) { ResetCombatState(); return; }

        var getBM = gameMain.Get<LuaFunction>("GetBattleManager");
        if (getBM == null) { ResetCombatState(); return; }

        object[] ret = getBM.Call(gameMain);
        if (ret == null || ret.Length == 0 || ret[0] == null) { ResetCombatState(); return; }

        var bm = ret[0] as LuaTable;
        _combatPaused = bm != null && bm.Get<int>("phase") == 4;
        var em = bm != null ? bm.Get<LuaTable>("enemyManager") : null;
        if (em == null) { ResetCombatState(); return; }

        var enemies = em.Get<LuaTable>("enemies");
        if (enemies == null) { ResetCombatState(); return; }

        _enemyBars.Clear();
        try
        {
            int count = enemies.Length;
            for (int i = 1; i <= count; i++)
            {
                var enemy = enemies.Get<LuaTable>(i);
                if (enemy == null) continue;

                bool isDead = false;
                isDead = LuaFieldReader.GetOr(enemy, "isDead", isDead);
                if (isDead) continue;

                int id = 0; double ex = 0, ey = 0, hp = 0, maxHp = 0;
                string etype = "normal";
                id = (int)LuaFieldReader.GetOr(enemy, "id", (double)id);
                ex = LuaFieldReader.GetOr(enemy, "x", ex);
                ey = LuaFieldReader.GetOr(enemy, "y", ey);
                hp = LuaFieldReader.GetOr(enemy, "hp", hp);
                maxHp = LuaFieldReader.GetOr(enemy, "maxHp", maxHp);
                etype = LuaFieldReader.GetOr<string>(enemy, "enemyType", etype) ?? "normal";
                // 精英是 isElite 标记，不是独立 enemyType 枚举（见 SpawnDirector 精英生成处）
                bool isElite = false;
                isElite = LuaFieldReader.GetOr(enemy, "isElite", isElite);

                // 血条信息（交给 OnGUI 投影到头顶）
                _enemyBars.Add(new EnemyBarInfo
                {
                    worldPos = new Vector3((float)ex, 1.4f, (float)ey),
                    hp = (float)hp,
                    maxHp = (float)maxHp,
                    enemyType = etype,
                    isElite = isElite
                });

                // 伤害飘字：每帧轮询 hp 下降即视为受到伤害
                if (_enemyLastHp.TryGetValue(id, out float lastHp) && hp < lastHp - 1e-4)
                {
                    _popups.Add(new DamagePopup
                    {
                        worldPos = new Vector3((float)ex, 1.4f, (float)ey),
                        value = (float)(lastHp - hp),
                        age = 0f,
                        isCrit = false,
                        isPlayer = false
                    });
                }
                _enemyLastHp[id] = (float)hp;
            }
        }
        catch (Exception e)
        {
            Debug.LogWarning("[HomeSceneBootstrapper] SyncEnemies error: " + e.Message);
        }
    }

    // ===== 子弹表现层 =====
    // 子弹的 3D 表现已交由 Lua 组件（BulletView）通过 prefab + 对象池驱动，由 BulletManager 每帧同步坐标，
    // 不再由 C# 轮询 CreatePrimitive。此处不再创建任何子弹 GameObject。

    // ===== 掉落物表现层 =====
    // 掉落物（武器/材料/道具）的 3D 表现已交由 Lua 组件（DropView）通过 prefab 驱动，由 DropSystem 每帧同步浮动/旋转，
    // 不再由 C# 轮询 CreatePrimitive。此处不再创建任何掉落 GameObject。

    // ===== 调试 HUD：在画面左上角实时显示战斗「效果信息数据」 =====
    // 让用户不用猜：scene / 下潜状态 / 敌人·子弹【数据量】 / C# 实际建出的【视图 GO 数】 / FPS。
    // 关键对比：若「Enemies=5」但「敌人视图GO=0」，说明敌人数据在跑、但可视化没建出来；
    //          若「Enemies=0」，说明这局下潜根本没启动（看前面 Dungeon 状态）。
    private bool _showHud = false;
    private string _hudText = "";

    private void RefreshHud()
    {
        if (!_showHud) { _hudText = ""; return; }
        if (Time.frameCount % 10 != 0) return;   // 节流：每 10 帧读一次 Lua

        if (_luaEnv == null)
        {
            _hudText = startBattle ? "Battle(离线调试, 无 Lua)" : "Home(离线调试, 无 Lua)";
            return;
        }
        try
        {
            // 取数统一走 GM 运行态采样器（Game/GM/GMRuntimeStats.lua），与 GM 面板同源同口径。
            // SampleText() 返回的已是完整 6 行文本（末行即 FPS=... (F1 开关HUD)），C# 侧不再拼任何后缀。
            // 这里原先又手写了一遍 scene/Dungeon/Enemies/Bullets/Time 的取数、再另拼一句 FPS，
            // 与应用退化为两份口径：老 HUD 敌人数取 #enemies（列表长度，含已死未清的），
            // 面板取 EnemyManager:GetAliveCount()；FPS 一个瞬时值、一个滑窗平均 —— 同一个数
            // 在屏幕上对不上，两套代码还会各自演化。S5 收编后全仓只剩这一份实现。
            // 每 10 帧调用是安全的：GMRuntimeStats.Start() 幂等（_hooked 直接 return），
            // 且其帧回调 _onFrame 在 UpdateManager 被 ClearAll 后会自动补钩。
            object[] r = _luaEnv.DoString(
                "local S = require('Game.GM.GMRuntimeStats') return S.SampleText()");
            if (r != null && r.Length > 0 && r[0] != null) _hudText = r[0].ToString();

            // 敌人/子弹/掉落的表现已由 Lua 组件（EnemyView/DropView/BulletView）通过 prefab 驱动，不在此 C# 侧计数。
        }
        catch (System.Exception e)
        {
            _hudText = "HUD ERR: " + e.Message;
        }
    }

    private void OnGUI()
    {
        if (startBattle && _combatPaused) return;
        // ===== 战斗反馈：头顶血条 + 伤害飘字（始终显示，不受调试文本开关影响）=====
        if (startBattle)
        {
            // 敌人血条（boss/elite 加宽）
            foreach (var e in _enemyBars)
            {
                Vector2 sp;
                if (WorldToScreen(e.worldPos, out sp))
                {
                    float scale = e.enemyType == "boss" ? 2.4f : (e.isElite ? 1.6f : 1f);
                    DrawHealthBar(sp, e.hp, e.maxHp, scale);
                }
            }

            // 玩家血条：头顶 + 左下固定条
            if (_battleBound)
            {
                Vector2 psp;
                if (WorldToScreen(_playerWorldPos, out psp)) DrawHealthBar(psp, _playerHp, _playerMaxHp, 1.8f);
            }
            if (_luaEnv == null) DrawPlayerHpBar();

            // 伤害飘字（敌人黄、玩家红，向上飘并淡出）
            foreach (var p in _popups)
            {
                Vector2 sp;
                if (WorldToScreen(p.worldPos, out sp))
                {
                    float a = 1f - p.age / PopupLife;
                    int size = p.isPlayer ? 20 : 16;
                    var st = new GUIStyle() { fontSize = size, fontStyle = FontStyle.Bold, alignment = TextAnchor.MiddleCenter };
                    st.normal.textColor = p.isPlayer
                        ? new Color(1f, 0.35f, 0.35f, a)
                        : new Color(1f, 1f, 0.45f, a);
                    GUI.Label(new Rect(sp.x - 40, sp.y - 20, 80, 40), Mathf.RoundToInt(p.value).ToString(), st);
                }
            }
        }

        // ===== 调试 HUD 文本（F1 开关）=====
        if (_showHud && !GMPanelDebugOverlay.IsVisible && !string.IsNullOrEmpty(_hudText))
        {
            GUI.Label(
                new Rect(10, 10, 380, 150),
                _hudText,
                new GUIStyle()
                {
                    normal = new GUIStyleState() { textColor = Color.yellow },
                    fontSize = 15,
                    fontStyle = FontStyle.Bold
                });
        }
    }

    private bool WorldToScreen(Vector3 world, out Vector2 screen)
    {
        screen = Vector2.zero;
        var cam = Camera.main;
        if (cam == null) return false;
        Vector3 s = cam.WorldToScreenPoint(world);
        if (s.z < 0f) return false;                       // 在相机背后
        screen = new Vector2(s.x, Screen.height - s.y);   // GUI 坐标 y 向下
        return true;
    }

    private void DrawHealthBar(Vector2 screen, float hp, float maxHp, float widthScale)
    {
        if (maxHp <= 0f) return;
        float ratio = Mathf.Clamp01(hp / maxHp);
        float w = 44f * widthScale;
        float h = 6f;
        float x = screen.x - w / 2f;
        float y = screen.y - h / 2f;
        GUI.color = Color.black;
        GUI.DrawTexture(new Rect(x - 1f, y - 1f, w + 2f, h + 2f), Texture2D.whiteTexture);
        Color fill = ratio > 0.5f
            ? Color.Lerp(Color.yellow, Color.green, (ratio - 0.5f) * 2f)
            : Color.Lerp(Color.red, Color.yellow, ratio * 2f);
        GUI.color = fill;
        GUI.DrawTexture(new Rect(x, y, w * ratio, h), Texture2D.whiteTexture);
        GUI.color = Color.white;
    }

    private void DrawPlayerHpBar()
    {
        float bw = 240f, bh = 18f;
        float bx = 16f, by = Screen.height - bh - 28f;
        GUI.color = Color.black;
        GUI.DrawTexture(new Rect(bx - 2f, by - 2f, bw + 4f, bh + 4f), Texture2D.whiteTexture);
        float pr = Mathf.Clamp01(_playerMaxHp > 0f ? _playerHp / _playerMaxHp : 0f);
        GUI.color = Color.green;
        GUI.DrawTexture(new Rect(bx, by, bw * pr, bh), Texture2D.whiteTexture);
        GUI.color = Color.white;
        var st = new GUIStyle() { fontSize = 13, fontStyle = FontStyle.Bold };
        st.normal.textColor = Color.white;
        GUI.Label(new Rect(bx, by - 18f, bw, 18f),
            "玩家 HP: " + Mathf.CeilToInt(_playerHp) + " / " + Mathf.CeilToInt(_playerMaxHp), st);
    }

    public Transform GetPlayerTransform()
    {
        return _playerTransform;
    }

    public Camera GetSceneCamera()
    {
        return sceneCamera;
    }

    // ===== 传送点创建 / 点击移动 / 传送（主城与战斗共用） =====

    /// <summary>
    /// 在场景内创建一个可见的传送点（深色圆盘 + 发光圆环 + 点光源）。
    /// 玩家走入 portalTriggerRadius 即触发传送，也可左键点击触发。
    /// 主城与战斗两种模式都会调用，只是目标场景不同（主城 -> Battle，战斗 -> Home）。
    /// </summary>
    private void CreatePortal(string targetScene = null, string label = "Cave Portal", Vector3? position = null)
    {
        string scene = string.IsNullOrEmpty(targetScene) ? portalSceneName : targetScene;
        Vector3 pos = position ?? new Vector3(0f, 0f, -16f);
        bool useClearing = _homeClearing != null;
        if (useClearing && !position.HasValue)
            pos = _homeClearing.Entrance.position;

        var portal = new GameObject("Portal:" + label);
        portal.transform.SetParent(transform, false);
        portal.transform.position = pos;

        if (useClearing)
        {
            var entryVolume = portal.AddComponent<BoxCollider>();
            entryVolume.isTrigger = true;
            entryVolume.center = new Vector3(0f, 1f, 1.8f);
            entryVolume.size = new Vector3(2.4f, 2.4f, 1.2f);
        }
        else
        {
        // 洞口（深色圆盘）
        var hole = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
        hole.name = "Hole";
        hole.transform.SetParent(portal.transform, false);
        hole.transform.localPosition = new Vector3(0f, 0.05f, 0f);
        hole.transform.localScale = new Vector3(4f, 0.1f, 4f);
        var hr = hole.GetComponent<Renderer>();
        if (hr != null) hr.material.color = new Color(0.02f, 0.02f, 0.06f, 1f);

        // 发光圆环（细圆柱做边缘）
        var ring = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
        ring.name = "Ring";
        ring.transform.SetParent(portal.transform, false);
        ring.transform.localPosition = new Vector3(0f, 0.2f, 0f);
        ring.transform.localScale = new Vector3(4.6f, 0.4f, 4.6f);
        var rr = ring.GetComponent<Renderer>();
        if (rr != null)
        {
            rr.material.color = new Color(0.2f, 0.9f, 1f, 1f);
            rr.material.EnableKeyword("_EMISSION");
            rr.material.SetColor("_EmissionColor", new Color(0.2f, 0.9f, 1f));
        }

        var glow = portal.AddComponent<Light>();
        glow.type = LightType.Point;
        glow.color = new Color(0.3f, 0.9f, 1f);
        glow.intensity = 2f;
        glow.range = 14f;
        }

        // 注册为可交互对象：
        // 左键点击即可传送（后续商人/宝箱等交互物件都走同一套 Interactable 机制）；
        // 同时保留走近自动触发，贴合「角色走入洞口即传送」的直觉。
        var interactable = portal.AddComponent<Interactable>();
        interactable.interactName = label;
        interactable.allowClick = !useClearing;
        interactable.allowProximity = !useClearing;
        interactable.proximityRadius = portalTriggerRadius;
        // Lua guards duplicate run requests; allow another attempt after an async failure.
        interactable.triggerOnce = false;
        interactable.EnsureColliders();
        interactable.onInteract.AddListener(() => TeleportToScene(scene));

        if (useClearing)
            portal.AddComponent<CaveEntranceGate>().Configure(_playerTransform, interactable, portal.GetComponent<BoxCollider>());

        Debug.Log($"[HomeSceneBootstrapper] Portal '{label}' 已创建于 {pos} -> 目标 '{scene}'（左键点击或走近均可传送）");
    }

    /// <summary>
    /// 右键移动的地表指令标记（英雄联盟式：地面光环 + 指向地面的箭头 + 扩散波）。
    /// 仅在存在目的地时显示，到达或被摇杆取消后自动淡出。
    /// </summary>
    private void CreateMoveMarker()
    {
        _moveMarker = MoveClickIndicator.Create(transform);
    }

    /// <summary>
    /// 交互控制器：左键点击场景物体触发（商人/传送门/宝箱等），
    /// 并统一处理 allowProximity 类型的靠近自动触发。
    /// </summary>
    private void CreateInteraction()
    {
        var go = new GameObject("InteractionController");
        go.transform.SetParent(transform, false);
        _interaction = go.AddComponent<InteractionController>();
        _interaction.player = _playerTransform;
        _interaction.worldCamera = sceneCamera;
    }

    /// <summary>
    /// 摇杆兜底查找。
    ///
    /// 场景切换后 UI 层的 HomeView 有可能仍持有【上一个场景】的 Bootstrapper 引用（该对象已随场景销毁），
    /// 于是它不会再对新场景的 Bootstrapper 调用 BindJoystick —— 表现为
    /// 「摇杆明明存在、_battleBound 也为 true，但 _joystick 是 NULL，角色纹丝不动」。
    /// （走 Home → 洞口 → Battle 这条真实路径时就会命中：UIManager 复用了 HomePanel 的 View 实例，
    ///  没有重新执行 HomeView:_bindJoystick，日志里 "Joystick handed to Bootstrapper" 只出现过一次。）
    ///
    /// 这里让 Bootstrapper 主动去场景里找摇杆，不再依赖 UI 层是否正确交接。
    /// </summary>
    private void EnsureJoystick()
    {
        if (_joystick != null) return;

        // 节流：全场景查找没必要每帧做
        if (Time.frameCount % 30 != 0) return;

        var joystick = FindObjectOfType<VirtualJoystick>();
        if (joystick != null)
        {
            BindJoystick(joystick);
            Debug.Log("[HomeSceneBootstrapper] 摇杆兜底绑定成功（UI 层未正确交接时的补救）");
        }
    }

    /// <summary>
    /// 离线调试 UI 兜底。
    ///
    /// 问题背景：直接打开 BattleScene/HomeScene 按 Play 时（未经 GameLaunch），
    /// 没有 Lua 环境，SceneLoader 不会运行，场景脚本（BattleScene.lua）也就不会加载，
    /// 于是没有任何地方去 Open("HomePanel") —— 表现是「场景里根本没有摇杆」。
    /// 这里自行加载摇杆，保证调试时依然能操控角色。
    ///
    /// 正式流程（Launch → ... → 本场景）下 _luaEnv 可用、面板由场景脚本打开，
    /// 本方法会直接跳过，不会重复创建。
    /// </summary>
    private void CreateDebugUI()
    {
        if (_joystick != null) return;      // 已绑定摇杆
        if (_luaEnv != null) return;        // 正式流程：交给场景脚本打开面板

        // HomePanel 已从 Resources 收敛到 AssetBundle
        // （AssetsPackage/UI_New/Prefabs/View/Home/HomePanel.prefab，标签 ui/homepanel.asset）。
        // 故不能再 Resources.Load。编辑器下 AssetBundleManager 走 Simulation 模式
        // （AssetDatabase 解析，不需要 GameLaunch.Initialize），正好覆盖「直接打开本场景按 Play」
        // 这个调试场景；真机不走这里（真机只能从 LaunchScene 进，那时 _luaEnv 非空，本方法直接返回）。
        StartCoroutine(CreateDebugUIRoutine());
    }

    private System.Collections.IEnumerator CreateDebugUIRoutine()
    {
        var op = UIAssetBundleHelper.LoadPrefabAsync("ui/homepanel.asset", "HomePanel");
        if (op == null)
        {
            Debug.LogWarning("[HomeSceneBootstrapper] 离线调试：无法发起 HomePanel 的 AB 加载（ui/homepanel.asset）");
            yield break;
        }

        // 编辑器 Simulation 下 IsDone 首帧即为 true，不额外等帧
        while (!UIAssetBundleHelper.IsDone(op)) yield return null;

        var prefab = UIAssetBundleHelper.GetPrefab(op);
        if (prefab == null)
        {
            Debug.LogWarning("[HomeSceneBootstrapper] 离线调试：AB 未取到 HomePanel（ui/homepanel.asset / HomePanel）");
            yield break;
        }

        // UI 必须挂在 Canvas 下才会渲染；本场景可能没有预置 Canvas
        Canvas canvas = FindObjectOfType<Canvas>();
        if (canvas == null)
        {
            var canvasObj = new GameObject("DebugCanvas");
            canvas = canvasObj.AddComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            canvasObj.AddComponent<CanvasScaler>();
            canvasObj.AddComponent<GraphicRaycaster>();

            if (FindObjectOfType<EventSystem>() == null)
                canvasObj.AddComponent<EventSystem>();
        }

        var panel = Instantiate(prefab, canvas.transform, false);
        panel.name = "HomePanel(OfflineDebug)";

        var joystick = panel.GetComponentInChildren<VirtualJoystick>(true);
        if (joystick != null)
        {
            BindJoystick(joystick);
            Debug.Log("[HomeSceneBootstrapper] 离线调试摇杆已启用（未走 Launch，面板由 C# 兜底创建）");
        }
        else
        {
            Debug.LogWarning("[HomeSceneBootstrapper] HomePanel 预制体中未找到 VirtualJoystick，摇杆不可用");
        }
    }

    /// <summary>
    /// 右键 3D 地面下达移动指令（移动端用触摸；点在 UI 如摇杆上时不触发）。
    /// 左键已让位给交互（见 InteractionController），避免与「点击物件」语义冲突。
    /// </summary>
    private void HandleClickToMove()
    {
        bool pressed = false;
        Vector3 screenPoint = Vector3.zero;
        // EventSystems 的 pointerId：-1=左键，-2=右键，-3=中键；触摸时为 fingerId。
        // 关键点：IsPointerOverGameObject() 不带参数时只判断左键，右键必须显式传 -2，
        // 否则右键点在 UI（摇杆/面板）上依然会穿透到场景，误下达移动指令。
        int pointerId = -2;

        // 用运行时能力判断，而非平台宏：
        // 微信小游戏（WebGL）运行在触屏设备上，但不属于 UNITY_ANDROID / UNITY_IOS，
        // 若按平台宏区分会错误落入"鼠标右键"分支，导致触屏点按无法下达移动指令。
        if (Input.touchSupported && Input.touchCount > 0)
        {
            Touch t = Input.GetTouch(0);
            if (t.phase == TouchPhase.Began)
            {
                pressed = true;
                screenPoint = t.position;
                pointerId = t.fingerId;
            }
        }
        else if (Input.GetMouseButtonDown(1))    // 1 = 右键：下达移动指令
        {
            pressed = true;
            screenPoint = Input.mousePosition;
            pointerId = -2;
        }

        if (!pressed) return;
        if (EventSystem.current != null && EventSystem.current.IsPointerOverGameObject(pointerId))
            return; // 点在 UI（如摇杆/按钮）上，不触发移动
        if (sceneCamera == null) return;

        Ray ray = sceneCamera.ScreenPointToRay(screenPoint);
        Plane groundPlane = new Plane(Vector3.up, Vector3.zero);
        if (groundPlane.Raycast(ray, out float enter))
        {
            Vector3 p = ray.GetPoint(enter);
            SetMoveDestination(new Vector3(p.x, 0f, p.z));
        }
    }

    /// <summary>
    /// 记录移动目的地（钳制进活动边界）并刷新地表标记。
    /// </summary>
    private void SetMoveDestination(Vector3 point)
    {
        point.x = Mathf.Clamp(point.x, -playBounds, playBounds);
        point.z = Mathf.Clamp(point.z, -playBounds, playBounds);
        point.y = 0f;

        _destination = point;
        if (_moveMarker != null) _moveMarker.Ping(point);
    }

    /// <summary>
    /// 通过 Lua GameMain.SwitchScene 切到目标场景（洞口传送）。
    /// </summary>
    private void TeleportToScene(string sceneName)
    {
        // 【下潜系统集成】
        // 旧实现一律 GameMain.SwitchScene(scene)，会【绕过】DungeonManager：
        //   进入战斗场景 → 不开局（没有楼层 / 怪潮 / Mod / Build）
        //   回到主城     → 不走结算（渊获不入账、不消耗回城卷轴）
        // 表现就是「和没做下潜系统时一模一样」。这里把两端都接到 Dungeon 上：
        //   进入战斗场景 → GameMain.StartDungeonRun()
        //   回到主城     → DungeonManager:UseReturnScroll()（走撤离结算）
        // 没有进行中的下潜局时（例如直接打开本场景调试）才回退旧行为。
        bool isReturnHome = string.Equals(sceneName, "Home");

        Debug.Log($"[HomeSceneBootstrapper] 进入洞口 -> " +
                  (isReturnHome ? "回城（走撤离结算）" : "开始下潜 Run"));

        if (_luaEnv != null)
        {
            string lua;
            if (isReturnHome)
            {
                lua =
                    "local GameMain = require 'Game.GameMain'; " +
                    "local dm = GameMain.GetDungeonManager(); " +
                    "if dm == nil then GameMain.SwitchScene('Home'); return end; " +
                    "if dm:UseReturnScroll() then return end; " +
                    "local st = dm:GetState(); " +
                    "if st == 'None' or st == 'Result' then GameMain.SwitchScene('Home'); return end; " +
                    "print('[Portal] 无法撤离：需要回城卷轴（当前状态 ' .. tostring(st) .. '）'); ";
            }
            else
            {
                lua = "local GameMain = require 'Game.GameMain'; GameMain.StartDungeonRun()";
            }

            try
            {
                _luaEnv.DoString(lua);
            }
            catch (Exception e)
            {
                Debug.LogError($"[HomeSceneBootstrapper] Teleport error: {e.Message}");
            }
        }
        else
        {
            // LuaEnv 未就绪 == 直接打开本场景按 Play（未经过 GameLaunch / XLuaManager 初始化）。
            // 为了让调试场景下也能验证「洞口 -> 战斗场景」这条链路，
            // 降级为 Unity 原生 SceneManager 直接加载；正式流程（Launch → Login → Home）走不到这里。
            if (string.IsNullOrEmpty(portalFallbackSceneName))
            {
                Debug.LogWarning("[HomeSceneBootstrapper] LuaEnv 未就绪，无法传送（直接运行本场景请走 Launch）。");
                return;
            }

            Debug.LogWarning(
                $"[HomeSceneBootstrapper] LuaEnv 未就绪，降级用 SceneManager 直接加载 '{portalFallbackSceneName}'" +
                "（正式流程请走 Launch/GameLaunch）。");

            try
            {
                SceneManager.LoadScene(portalFallbackSceneName);
            }
            catch (Exception e)
            {
                Debug.LogError(
                    $"[HomeSceneBootstrapper] 兜底场景 '{portalFallbackSceneName}' 加载失败: {e.Message}" +
                    "；请确认该场景已加入 File → Build Settings → Scenes In Build。");
            }
        }
    }
}
