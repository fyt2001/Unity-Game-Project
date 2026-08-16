// =============================================================================
// DebugBattlePanel.cs
// =============================================================================
// 测试用战斗信息面板。使用 Unity IMGUI (OnGUI) 显示实时战斗数据。
// 不需要任何 Prefab，挂载即可用。
// =============================================================================

using UnityEngine;
using XLua;

[LuaCallCSharp]
public class DebugBattlePanel : MonoBehaviour
{
    [Header("显示设置")]
    public bool showPanel = true;
    public int fontSize = 16;
    public Color textColor = Color.white;
    public Color bgColor = new Color(0, 0, 0, 0.5f);

    // 缓存的 Lua 数据
    private string playerInfo = "";
    private string battleInfo = "";
    private string enemyInfo = "";
    private string weaponInfo = "";
    private float refreshTimer = 0f;
    private float refreshInterval = 0.5f;  // 每0.5秒刷新一次数据

    void Update()
    {
        refreshTimer += Time.deltaTime;
        if (refreshTimer >= refreshInterval)
        {
            refreshTimer = 0f;
            RefreshData();
        }
    }

    void OnGUI()
    {
        if (!showPanel) return;

        GUIStyle style = new GUIStyle();
        style.fontSize = fontSize;
        style.normal.textColor = textColor;
        style.wordWrap = true;

        // 背景
        Texture2D bgTex = new Texture2D(1, 1);
        bgTex.SetPixel(0, 0, bgColor);
        bgTex.Apply();
        style.normal.background = bgTex;

        float panelWidth = 320;
        float panelHeight = 280;
        float x = 10;
        float y = 10;

        // 绘制面板
        GUI.Box(new Rect(x, y, panelWidth, panelHeight), "", style);

        float textX = x + 10;
        float textY = y + 10;

        GUI.Label(new Rect(textX, textY, panelWidth - 20, 20), "=== Debug Battle Panel ===", style);
        textY += 25;

        GUI.Label(new Rect(textX, textY, panelWidth - 20, panelHeight - textY + y), 
            playerInfo + "\n" + battleInfo + "\n" + enemyInfo + "\n" + weaponInfo, style);
    }

    private void RefreshData()
    {
        var luaEnv = FindObjectOfType<LuaGameBootstrap>()?.GetLuaEnv();
        if (luaEnv == null) return;

        try
        {
            // 获取战斗数据快照
            object[] results = luaEnv.DoString(System.Text.Encoding.UTF8.GetBytes(@"
                local GameMain = require 'Game.GameMain'
                local bm = GameMain.GetBattleManager()
                if not bm then return 'No battle' end
                
                local stats = bm:GetStats()
                local pc = bm.playerController
                local pStats = pc:GetStats()
                
                -- 玩家信息
                local playerStr = string.format(
                    'Player Lv.%d | HP: %d/%d | EXP: %d/%d',
                    pStats.level, pStats.hp, pStats.maxHp, pStats.exp, pStats.expToNext
                )
                
                -- 战斗信息
                local phaseNames = { [0]='None',[1]='Loading',[2]='Countdown',[3]='Running',[4]='Paused',[5]='Victory',[6]='Defeat' }
                local battleStr = string.format(
                    'Phase: %s | Time: %.1fs | Kills: %d | Exp: %d',
                    phaseNames[stats.phase] or 'Unknown',
                    stats.elapsedTime, stats.killCount, stats.expTotal
                )
                
                -- 敌人信息
                local em = bm.enemyManager
                local enemyStr = string.format('Enemies Alive: %d', em:GetAliveCount())
                
                -- 武器信息
                local ws = bm.weaponSystem
                local weapons = ws:GetAllWeapons()
                local weaponStrs = {}
                for _, w in ipairs(weapons) do
                    table.insert(weaponStrs, string.format('  [%d] Lv.%d Dmg:%d', w.id, w.level, w.damage))
                end
                local weaponStr = 'Weapons:\n' .. table.concat(weaponStrs, '\n')
                
                return playerStr, battleStr, enemyStr, weaponStr
            "));

            if (results != null && results.Length >= 4)
            {
                playerInfo = results[0]?.ToString() ?? "N/A";
                battleInfo = results[1]?.ToString() ?? "N/A";
                enemyInfo = results[2]?.ToString() ?? "N/A";
                weaponInfo = results[3]?.ToString() ?? "N/A";
            }
        }
        catch (System.Exception e)
        {
            playerInfo = "Error: " + e.Message;
            battleInfo = "";
            enemyInfo = "";
            weaponInfo = "";
        }
    }
}
