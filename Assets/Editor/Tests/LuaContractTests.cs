// S9: C# <-> Lua contract for HomeSceneBootstrapper. The C# side reads these Lua fields by string key every
// frame; a Lua rename used to fail silently. Two tests:
//   1. the contract below covers exactly the keys HomeSceneBootstrapper.cs reads (source scan), and
//   2. real Lua modules, loaded in XLua, expose every key with the expected Lua type.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.SceneManagement;
using XLua;

namespace Game.AgentTests
{
    public class LuaContractTests
    {
        private const string BootstrapperPath = "Assets/Game/Scripts/GameLaunch/HomeSceneBootstrapper.cs";

        // owner -> how the C# side reaches it (HomeSceneBootstrapper.TryBindPlayer / SyncEnemies / SyncPlayerCombat).
        private static readonly string[,] Contract =
        {
            { "GameMain", "GetBattleManager", "function" },
            { "battleManager", "playerController", "table" },
            { "battleManager", "phase", "number" },
            { "battleManager", "enemyManager", "table" },
            { "player", "SetInput", "function" },
            { "player", "BindView", "function" },
            { "player", "GetPosition", "function" },
            { "player", "inputX", "number" },
            { "player", "inputY", "number" },
            { "player", "hp", "number" },
            { "player", "maxHp", "number" },
            { "enemyManager", "enemies", "table" },
            { "enemy", "isDead", "boolean" },
            { "enemy", "id", "number" },
            { "enemy", "x", "number" },
            { "enemy", "y", "number" },
            { "enemy", "hp", "number" },
            { "enemy", "maxHp", "number" },
            { "enemy", "enemyType", "string" },
            { "enemy", "isElite", "boolean" },
        };

        // Keys C# owns itself: InjectViewConfig creates _G.ViewConfig before reading it.
        private static readonly string[] CSharpOwnedKeys = { "ViewConfig" };

        private static readonly Regex ReadRegex = new Regex(
            @"\.Get<[^>]+>\(\s*""(\w+)""\s*\)|LuaFieldReader\.(?:TryGet|GetOr)(?:<[^>]+>)?\(\s*[\w.]+\s*,\s*""(\w+)""");

        [Test]
        public void ContractListsEveryKeyTheBootstrapperReads()
        {
            string source = File.ReadAllText(Path.Combine(AgentTestSupport.ProjectRoot, BootstrapperPath));
            var read = new List<string>();
            foreach (Match m in ReadRegex.Matches(source))
                read.Add(m.Groups[1].Success ? m.Groups[1].Value : m.Groups[2].Value);

            var declared = new HashSet<string>(CSharpOwnedKeys);
            for (int i = 0; i < Contract.GetLength(0); i++) declared.Add(Contract[i, 1]);

            var undeclared = read.Distinct().Where(k => !declared.Contains(k)).ToList();
            var unused = declared.Where(k => !read.Contains(k)).ToList();
            Assert.IsEmpty(undeclared, "HomeSceneBootstrapper reads Lua keys missing from LuaContractTests.Contract: "
                + string.Join(", ", undeclared) + ". Add them (owner, key, Lua type) so the Lua side is checked.");
            Assert.IsEmpty(unused, "Contract lists keys HomeSceneBootstrapper no longer reads: " + string.Join(", ", unused));
            Assert.AreEqual(22, read.Count, "call sites reading Lua by key changed; update this count consciously. Keys: " + string.Join(", ", read));
        }

        private const string SetupLua = @"
local function stub() return setmetatable({}, { __index = function() return function() return nil end end }) end
-- presentation-only modules: keep the test free of GameObjects and VFX
for _, name in ipairs({ 'Game.Battle.View.EntityViewFactory', 'Game.Battle.View.ChainLightningView',
        'Game.Battle.View.FlyingSwordView', 'Game.Battle.VFXManager' }) do
    package.loaded[name] = stub()
end
local GameMain = require 'Game.GameMain'
local BattleManager = require 'Game.Battle.BattleManager'
local bm = BattleManager.New()
local ok, err = pcall(bm.Init, bm, {})
if not ok then error('BattleManager:Init({}) failed in the contract fixture: ' .. tostring(err), 0) end
local em = bm.enemyManager
local enemy = em and em:SpawnEnemy({ x = 1, y = 2, hp = 10, enemyType = 'slime' })
__contract = { GameMain = GameMain, battleManager = bm, player = bm.playerController, enemyManager = em, enemy = enemy }
function __contractType(owner, key)
    local o = __contract[owner]
    if type(o) ~= 'table' then return 'owner ' .. owner .. ' is ' .. type(o) end
    return type(o[key])
end
";

        [Test]
        public void LuaModulesExposeEveryContractKeyWithTheRightType()
        {
            var before = new HashSet<GameObject>(SceneManager.GetActiveScene().GetRootGameObjects());
            try
            {
                using (var env = AgentTestSupport.CreateLuaEnv(AgentTestSupport.LuaRoot))
                {
                    env.DoString(SetupLua, "LuaContractTests.setup");
                    var typeOf = env.Global.Get<LuaFunction>("__contractType");
                    var broken = new List<string>();
                    try
                    {
                        for (int i = 0; i < Contract.GetLength(0); i++)
                        {
                            string owner = Contract[i, 0], key = Contract[i, 1], want = Contract[i, 2];
                            object[] r = typeOf.Call(owner, key);
                            string got = r != null && r.Length > 0 ? r[0] as string : "?";
                            if (got != want) broken.Add(owner + "." + key + " expected " + want + ", got " + got);
                        }
                    }
                    finally
                    {
                        typeOf.Dispose();
                        env.DoString("__contract = nil; __contractType = nil");
                        env.FullGc();
                    }
                    Assert.IsEmpty(broken, "Lua side broke the HomeSceneBootstrapper contract (C# reads these keys every frame; "
                        + "LuaFieldReader would only warn once at runtime): " + string.Join("; ", broken));
                }
            }
            finally
            {
                foreach (var go in SceneManager.GetActiveScene().GetRootGameObjects())
                    if (!before.Contains(go)) UnityEngine.Object.DestroyImmediate(go);
            }
        }
    }
}
