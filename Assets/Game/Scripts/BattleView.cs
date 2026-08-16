// =============================================================================
// BattleView.cs
// =============================================================================
// 战斗可视层（测试用）。
// 负责：
//   1. 创建场景可视对象（地面、玩家、敌人生成点标记）
//   2. 每帧将 Lua 玩家坐标同步到 Unity Transform
//   3. 读取 WASD 输入并传给 Lua PlayerController
//   4. 显示简单调试信息（OnGUI）
//
// 不依赖任何美术资源，全部用基础几何体，方便快速验证战斗框架。
// =============================================================================

using UnityEngine;
using XLua;
using System;

[LuaCallCSharp]
public class BattleView : MonoBehaviour
{
    [Header("场景生成")]
    public bool createSceneOnStart = true;
    public float groundSize = 40f;
    public float playBounds = 18f;   // 玩家活动边界（半边长）

    [Header("玩家外观")]
    public float playerSize = 1f;
    public Color playerColor = Color.cyan;

    [Header("输入")]
    public float inputScale = 1f;
    public KeyCode keyUp = KeyCode.W;
    public KeyCode keyDown = KeyCode.S;
    public KeyCode keyLeft = KeyCode.A;
    public KeyCode keyRight = KeyCode.D;

    // 运行时对象
    private GameObject groundObj;
    private GameObject playerObj;
    private Transform playerTransform;
    private Camera mainCamera;

    // Lua 引用
    private LuaEnv luaEnv;
    private LuaTable playerController;
    private LuaFunction setInputFunc;
    private bool battleStarted = false;

    [Header("相机跟随")]
    public bool cameraFollow = true;
    public float cameraLerp = 4f;        // 越小越滞后
    public float cameraHeight = 20f;     // 相机相对玩家的高度偏移
    public float cameraBack = -20f;      // 相机相对玩家的纵深偏移（45度斜视）

    void Start()
    {
        luaEnv = FindObjectOfType<LuaGameBootstrap>()?.GetLuaEnv();
        if (luaEnv == null)
        {
            Debug.LogError("[BattleView] LuaGameBootstrap not found!");
            return;
        }

        mainCamera = Camera.main;
        if (mainCamera != null)
        {
            // 初始化相机偏移（基于当前相机相对原点的位置）
            cameraHeight = mainCamera.transform.position.y;
            cameraBack = mainCamera.transform.position.z;
        }

        if (createSceneOnStart)
        {
            CreateGround();
            CreatePlayer();
        }
    }

    void Update()
    {
        if (luaEnv == null) return;

        // 延迟获取 PlayerController（战斗启动后才存在）
        if (!battleStarted)
        {
            TryBindPlayer();
            return;
        }

        if (playerController == null) return;

        // 读取输入并传给 Lua
        float ix = 0, iy = 0;
        if (Input.GetKey(keyUp)) iy += 1;
        if (Input.GetKey(keyDown)) iy -= 1;
        if (Input.GetKey(keyLeft)) ix -= 1;
        if (Input.GetKey(keyRight)) ix += 1;
        if (ix != 0 && iy != 0)
        {
            float n = Mathf.Sqrt(ix * ix + iy * iy);
            ix /= n; iy /= n;
        }
        try
        {
            // 注意：Lua 的 SetInput 是 ":" 定义的方法，第一个参数需传 self（playerController）
            setInputFunc?.Call(playerController, ix * inputScale, iy * inputScale);
        }
        catch (Exception e)
        {
            Debug.LogError($"[BattleView] SetInput error: {e.Message}");
        }

        // 将 Lua 玩家坐标同步到 Unity Transform（俯视角：Lua y -> Unity z）
        if (playerTransform != null && playerController != null)
        {
            try
            {
                var getPos = playerController.Get<LuaFunction>("GetPosition");
                object[] r = getPos.Call(playerController);
                float px = System.Convert.ToSingle(r[0] ?? 0);
                float py = System.Convert.ToSingle(r[1] ?? 0);
                playerTransform.position = new Vector3(px, 0, py);
            }
            catch (Exception e)
            {
                Debug.LogError($"[BattleView] SyncPos error: {e.Message}");
            }
        }

        // 面朝移动方向（平滑旋转，带滞后）
        if (playerTransform != null && (ix != 0 || iy != 0))
        {
            // 移动方向映射到 Unity 平面：Lua (x, y) -> Unity (x, z)
            Vector3 moveDir = new Vector3(ix, 0, iy).normalized;
            Quaternion targetRot = Quaternion.LookRotation(moveDir, Vector3.up);
            playerTransform.rotation = Quaternion.Slerp(
                playerTransform.rotation,
                targetRot,
                Time.deltaTime * cameraLerp
            );
        }

        // 相机跟随玩家（带滞后平滑）
        if (cameraFollow && mainCamera != null && playerTransform != null)
        {
            Vector3 targetPos = playerTransform.position + new Vector3(0, cameraHeight, cameraBack);
            mainCamera.transform.position = Vector3.Lerp(
                mainCamera.transform.position,
                targetPos,
                Time.deltaTime * cameraLerp
            );
            // 相机始终看向玩家（保持 45 度斜视方向）
            mainCamera.transform.rotation = Quaternion.Euler(45, 0, 0);
        }
    }

    /// <summary>
    /// 战斗启动后，获取 PlayerController 并绑定视图对象
    /// </summary>
    private void TryBindPlayer()
    {
        try
        {
            var gm = luaEnv.Global.Get<LuaTable>("GameMain");
            if (gm == null) return;

            // GameMain.GetPlayerController 是一个 LuaFunction
            var getPcFunc = gm.Get<LuaFunction>("GetPlayerController");
            if (getPcFunc == null) return;

            // 调用 GameMain.GetPlayerController()
            object[] ret = getPcFunc.Call(gm);
            if (ret == null || ret.Length == 0 || ret[0] == null) return;

            playerController = ret[0] as LuaTable;
            if (playerController == null) return;

            setInputFunc = playerController.Get<LuaFunction>("SetInput");
            battleStarted = true;

            // 绑定 Unity Transform 到 Lua 玩家（Lua 会在移动时同步坐标）
            if (playerTransform != null)
            {
                var bind = playerController.Get<LuaFunction>("BindView");
                bind?.Call(playerController, playerTransform);
            }

            Debug.Log("[BattleView] PlayerController bound, battle view active");
        }
        catch
        {
            // 战斗尚未启动，下一帧重试
        }
    }

    /// <summary>
    /// 创建地面：用自定义 Shader（Custom/BattleGrid）基于世界坐标程序化绘制网格，
    /// 不再依赖 LineRenderer 等额外 GameObject（"预制体"画线方式）。
    /// </summary>
    private void CreateGround()
    {
        groundObj = GameObject.CreatePrimitive(PrimitiveType.Plane);
        groundObj.name = "BattleGround";
        groundObj.transform.localScale = new Vector3(groundSize / 10f, 1, groundSize / 10f);

        var rend = groundObj.GetComponent<Renderer>();
        if (rend)
        {
            var shader = Shader.Find("Custom/BattleGrid");
            if (shader != null)
            {
                var mat = new Material(shader);
                mat.SetColor("_BaseColor",  new Color(0.18f, 0.22f, 0.28f, 1));
                mat.SetColor("_GridColor",  new Color(0.35f, 0.40f, 0.50f, 1));
                mat.SetColor("_BoundsColor", Color.yellow);
                mat.SetFloat("_GridSize", 2.0f);   // 每格 2 米
                mat.SetFloat("_LineWidth", 1.5f);
                mat.SetFloat("_Bounds", playBounds > 0 ? playBounds : 0f); // 活动边界半边长
                mat.SetFloat("_Fade", 1.0f);
                rend.material = mat;
            }
            else
            {
                // 兜底：找不到 shader 时给个纯色，避免全黑
                rend.material.color = new Color(0.18f, 0.22f, 0.28f);
                Debug.LogWarning("[BattleView] Custom/BattleGrid shader not found, using flat color.");
            }
        }
    }

    /// <summary>
    /// 创建玩家：身体（立方体）+ 正面指示器（锥体指向 +Z）
    /// 父物体旋转以面朝移动方向
    /// </summary>
    private void CreatePlayer()
    {
        // 父物体（负责位置和朝向）
        playerObj = new GameObject("Player");
        playerTransform = playerObj.transform;
        playerObj.transform.position = new Vector3(0, 0, 0);

        // 身体
        var body = GameObject.CreatePrimitive(PrimitiveType.Cube);
        body.name = "Body";
        body.transform.SetParent(playerTransform);
        body.transform.localPosition = new Vector3(0, playerSize * 0.5f, 0);
        body.transform.localScale = Vector3.one * playerSize;
        var bodyRend = body.GetComponent<Renderer>();
        if (bodyRend) bodyRend.material.color = playerColor;

        // 正面指示器（锥体，尖端朝 +Z = 前方）
        var nose = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
        nose.name = "Nose";
        nose.transform.SetParent(playerTransform);
        // 圆柱默认沿 Y 轴，旋转使其朝 +Z，并放到身体前方
        nose.transform.localRotation = Quaternion.Euler(90, 0, 0);
        nose.transform.localPosition = new Vector3(0, playerSize * 0.5f, playerSize * 0.6f);
        nose.transform.localScale = new Vector3(playerSize * 0.4f, playerSize * 0.4f, playerSize * 0.6f);
        var noseRend = nose.GetComponent<Renderer>();
        if (noseRend) noseRend.material.color = Color.white;
    }

    void OnGUI()
    {
        if (!battleStarted || playerController == null) return;
        try
        {
            var getPos = playerController.Get<LuaFunction>("GetPosition");
            object[] r = getPos.Call(playerController);
            float x = (float)(r[0] ?? 0);
            float y = (float)(r[1] ?? 0);
            GUI.Label(new Rect(10, 10, 300, 20), $"Player pos: ({x:F1}, {y:F1})");
        }
        catch { }
    }

    void OnDestroy()
    {
        // 注意：setInputFunc / playerController 是从 LuaEnv 中取出的引用，
        // 其生命周期由 Lua GC 管理。当组件销毁时 LuaEnv 可能已先被释放，
        // 此时调用 Dispose 会触发 "this lua env had disposed!" 异常。
        // 因此这里只清空引用，不主动 Dispose，避免访问已释放的 env。
        setInputFunc = null;
        playerController = null;
        battleStarted = false;
    }
}
