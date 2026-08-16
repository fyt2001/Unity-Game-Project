// =============================================================================
// TestInputSimulator.cs
// =============================================================================
// 测试用玩家输入模拟器。
// 使用 WASD 或方向键控制玩家移动，将输入传递给 Lua PlayerController。
// =============================================================================

using UnityEngine;
using XLua;
using System;

[LuaCallCSharp]
public class TestInputSimulator : MonoBehaviour
{
    [Header("输入配置")]
    [Tooltip("移动速度系数")]
    public float moveSpeed = 1.0f;

    [Header("测试按键")]
    public KeyCode keyUp = KeyCode.W;
    public KeyCode keyDown = KeyCode.S;
    public KeyCode keyLeft = KeyCode.A;
    public KeyCode keyRight = KeyCode.D;

    // Lua 函数引用
    private LuaFunction setInputFunc;
    private LuaTable playerController;

    void Start()
    {
        var luaEnv = FindObjectOfType<LuaGameBootstrap>()?.GetLuaEnv();
        if (luaEnv == null) return;

        // 获取 PlayerController 实例的 SetInput 方法
        // 注意：需要 BattleManager 已创建后才能获取
        // 这里延迟到第一次 Update 时获取
    }

    void Update()
    {
        // 尝试获取 PlayerController（延迟获取，因为 BattleManager 可能在 Start 之后才创建）
        if (playerController == null)
        {
            TryGetPlayerController();
            if (playerController == null) return;
        }

        // 读取输入
        float inputX = 0;
        float inputY = 0;

        if (Input.GetKey(keyUp)) inputY += 1;
        if (Input.GetKey(keyDown)) inputY -= 1;
        if (Input.GetKey(keyLeft)) inputX -= 1;
        if (Input.GetKey(keyRight)) inputX += 1;

        // 归一化（防止斜向移动过快）
        if (inputX != 0 && inputY != 0)
        {
            float norm = Mathf.Sqrt(inputX * inputX + inputY * inputY);
            inputX /= norm;
            inputY /= norm;
        }

        inputX *= moveSpeed;
        inputY *= moveSpeed;

        // 传递给 Lua
        try
        {
            setInputFunc?.Call(inputX, inputY);
        }
        catch (Exception e)
        {
            Debug.LogError($"[TestInputSimulator] Error: {e.Message}");
        }
    }

    private void TryGetPlayerController()
    {
        var luaEnv = FindObjectOfType<LuaGameBootstrap>()?.GetLuaEnv();
        if (luaEnv == null) return;

        try
        {
            // 获取 BattleManager -> PlayerController
            var battleMgr = luaEnv.Global.GetInPath<LuaTable>("Game.GameMain.GetBattleManager()");
            if (battleMgr == null) return;

            playerController = battleMgr.Get<LuaTable>("playerController");
            if (playerController != null)
            {
                setInputFunc = playerController.Get<LuaFunction>("SetInput");
                Debug.Log("[TestInputSimulator] PlayerController acquired, input ready");
            }
        }
        catch
        {
            // Battle 还没创建，等待下一帧
        }
    }

    void OnDestroy()
    {
        setInputFunc?.Dispose();
        playerController?.Dispose();
    }
}
