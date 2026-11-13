using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using Game.LocalBackend;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using XLua;

namespace Game.LocalBackendEditor
{
    [InitializeOnLoad]
    public static class OnlineGameplayPlayChecks
    {
        private const string Key = "OnlineGameplayPlayChecks.";
        [Serializable] private sealed class SceneRecord { public string path; public bool loaded; public bool active; }
        [Serializable] private sealed class Scenes { public SceneRecord[] records; }
        private static LocalBackendJob job;
        private static LuaEnv env;
        private static readonly List<string> checks = new List<string>();
        private static readonly List<string> runtimeErrors = new List<string>();
        private static string DirectoryPath { get { return Path.GetFullPath("Docs/Verification"); } }
        private static string SavePath { get { return Path.Combine(Application.persistentDataPath, "save/saveData.lua"); } }
        static OnlineGameplayPlayChecks() { EditorApplication.playModeStateChanged += OnPlayState; }

        [MenuItem("Tools/Local Backend/验证实际游戏流程")]
        public static void Start()
        {
            if (EditorApplication.isPlayingOrWillChangePlaymode) throw new InvalidOperationException("Stop Play before verification.");
            var setup = EditorSceneManager.GetSceneManagerSetup();
            var records = new List<SceneRecord>();
            foreach (var scene in setup)
            {
                if (scene.isLoaded && UnityEngine.SceneManagement.SceneManager.GetSceneByPath(scene.path).isDirty)
                    throw new InvalidOperationException("Save or preserve unsaved scenes before verification.");
                records.Add(new SceneRecord { path = scene.path, loaded = scene.isLoaded, active = scene.isActive });
            }
            SessionState.SetString(Key + "scenes", JsonUtility.ToJson(new Scenes { records = records.ToArray() }));
            SessionState.SetString(Key + "account", OnlineGameBridge.AccountName);
            SessionState.SetString(Key + "saveHash", HashSave());
            SessionState.SetBool(Key + "active", true);
            EditorSceneManager.OpenScene("Assets/Scenes/LaunchScene.unity");
            EditorApplication.isPlaying = true;
        }

        private static void OnPlayState(PlayModeStateChange state)
        {
            if (!SessionState.GetBool(Key + "active", false)) return;
            if (state == PlayModeStateChange.EnteredPlayMode)
            {
                checks.Clear();
                runtimeErrors.Clear();
                Application.logMessageReceived += OnRuntimeLog;
                OnlineGameBridge.AccountName = "play-check-" + Guid.NewGuid().ToString("N");
                job = new LocalBackendJob(Flow(), error =>
                {
                    Directory.CreateDirectory(DirectoryPath);
                    File.WriteAllText(Path.Combine(DirectoryPath, "online_gameplay_play_latest.txt"),
                        DateTime.UtcNow.ToString("o") + "\nScope: Editor Play, local dev rewards, not built Player or anti-cheat\n"
                        + (error == null ? "FLOW COMPLETE; waiting for engine shutdown\n" : "FAIL: " + error + "\n") + string.Join("\n", checks));
                    SessionState.SetBool(Key + "flowPassed", error == null);
                    if (error != null) Debug.LogException(error);
                    else Debug.Log("[OnlineGameplayPlayChecks] PASS " + checks.Count + " stages");
                    // Cancel Lua callbacks before the engine's Lua environment is disposed.
                    OnlineGameBridge.Close();
                    EditorApplication.isPlaying = false;
                });
            }
            else if (state == PlayModeStateChange.EnteredEditMode)
            {
                Application.logMessageReceived -= OnRuntimeLog;
                string original = SessionState.GetString(Key + "saveHash", "");
                Directory.CreateDirectory(DirectoryPath);
                File.AppendAllText(Path.Combine(DirectoryPath, "online_gameplay_play_latest.txt"),
                    "\nOffline save unchanged: " + (original == HashSave()) + "\n"
                    + "Runtime/shutdown errors: " + runtimeErrors.Count + "\n"
                    + string.Join("\n", runtimeErrors) + "\nFinal: "
                    + (SessionState.GetBool(Key + "flowPassed", false) && original == HashSave() && runtimeErrors.Count == 0 ? "PASS" : "FAIL") + "\n");
                var scenes = JsonUtility.FromJson<Scenes>(SessionState.GetString(Key + "scenes", ""));
                var setup = new List<SceneSetup>();
                if (scenes != null) foreach (var scene in scenes.records)
                    setup.Add(new SceneSetup { path = scene.path, isLoaded = scene.loaded, isActive = scene.active });
                if (setup.Count > 0) EditorSceneManager.RestoreSceneManagerSetup(setup.ToArray());
                OnlineGameBridge.AccountName = SessionState.GetString(Key + "account", "local-player");
                SessionState.SetBool(Key + "active", false);
            }
        }

        private static void OnRuntimeLog(string message, string stack, LogType type)
        {
            if (type == LogType.Error || type == LogType.Exception
                || message.Contains("try to dispose a LuaEnv") || message.Contains("[XLuaManager] TryCall("))
                runtimeErrors.Add(message);
        }

        private static string HashSave()
        {
            if (!File.Exists(SavePath)) return "absent";
            using (var sha = SHA256.Create()) return Convert.ToBase64String(sha.ComputeHash(File.ReadAllBytes(SavePath)));
        }
        private static bool Evaluate(string condition)
        {
            var value = env.DoString("return " + condition);
            return value.Length > 0 && value[0] is bool && (bool)value[0];
        }
        private static void Do(string source) { env.DoString(source); }
        private static IEnumerator Wait(Func<bool> predicate, string label)
        {
            double deadline = EditorApplication.timeSinceStartup + 30;
            while (!predicate())
            {
                if (EditorApplication.timeSinceStartup > deadline) throw new TimeoutException(label);
                yield return null;
            }
            checks.Add(label);
        }
        private static IEnumerator Flow()
        {
            yield return Wait(() => GameLaunch.Instance != null && GameLaunch.Instance.CurrentPhase == LaunchPhase.Complete, "Launch completes");
            var manager = UnityEngine.Object.FindObjectOfType<XLuaManager>();
            if (manager == null || manager.GetLuaEnv() == null) throw new Exception("Game Lua environment unavailable.");
            env = manager.GetLuaEnv();
            new GameObject("Verification_DuplicateLuaManager").AddComponent<XLuaManager>();
            double duplicateTime = EditorApplication.timeSinceStartup + 0.2;
            while (EditorApplication.timeSinceStartup < duplicateTime) yield return null;
            if (manager.GetLuaEnv() != env) throw new Exception("Duplicate manager invalidated the live environment.");
            checks.Add("Duplicate manager teardown leaves the live environment and game ticks intact");
            Do("verifyGame=require 'Game.GameMain'; verifySession=require 'Game.Online.OnlineSession'; verifySave=require 'Game.Save.SaveData'");
            yield return Wait(() => Evaluate("verifyGame.GetUIManager():IsOpen('LoginPanel')"), "Login panel opens");
            Do("require('Framework.Framework').Event():Broadcast('LoginPanel_OnServerSelect'); assert(verifySession.IsSelected()); verifyGame.GetUIManager():GetWindow('LoginPanel'):GetController():_onLoginClick()");
            yield return Wait(() => Evaluate("verifySession.IsReady() and verifyGame.GetCurrentScene()=='Home' and verifyGame.GetUIManager():IsOpen('HomePanel')"), "Actual login controller enters Home with server data");
            for (int i = 0; i < 3; i++)
            {
                Do("assert(verifyGame.StartDungeonRun())");
                yield return Wait(() => Evaluate("verifyGame.GetDungeonManager()~=nil and verifyGame.GetDungeonManager().battleManager~=nil and verifyGame.GetDungeonManager().battleManager.phase==3"), "Playable online battle starts " + i);
                Do("local pc=verifyGame.GetDungeonManager().battleManager.playerController; verifyBase={atk=pc.atk,atkSpeed=pc.atkSpeed,maxHp=pc.maxHp,critDmg=pc.critDmg,moveSpeed=pc.moveSpeed}; assert(verifyGame.GetDungeonManager():UseReturnScroll())");
                yield return Wait(() => Evaluate("verifyGame.GetDungeonManager().lastResult and verifyGame.GetDungeonManager().lastResult.settlementStatus=='confirmed' and verifyGame.GetUIManager():IsOpen('RunResultPanel')"), "Actual extraction receives server acknowledgement and result UI opens " + i);
                Do("assert(verifyGame.GetDungeonManager().battleManager.phase==4); assert(verifyGame.GetUIManager():GetWindow('RunResultPanel'):GetModel().result.gold==100); assert(verifyGame.GetDungeonManager():BackToHome())");
                yield return Wait(() => Evaluate("verifyGame.GetCurrentScene()=='Home' and verifyGame.GetUIManager():IsOpen('HomePanel')"), "Confirmed result returns Home " + i);
            }
            Do("assert(verifySave.Get().inventory.gold==300); verifyGame.GetUIManager():Open('ShopPanel')");
            yield return Wait(() => Evaluate("verifyGame.GetUIManager():IsOpen('ShopPanel') and not verifySession.IsBusy()"), "Shop opens with refreshed server inventory");
            Do("verifyGame.GetUIManager():GetWindow('ShopPanel'):GetController():_onBuy(1)");
            yield return Wait(() => Evaluate("not verifySession.IsBusy() and #verifySave.Get().inventory.mods==1 and verifySave.Get().inventory.gold==0"), "Real shop controller buys one server-owned card");
            Do("verifyCardUid=verifySave.Get().inventory.mods[1].uid; verifyUpgradeDone=false; verifySession.Upgrade(verifyCardUid,function(ok) assert(ok); verifyUpgradeDone=true end)");
            yield return Wait(() => Evaluate("verifyUpgradeDone and not verifySession.IsBusy() and verifySave.Get().inventory.mods[1].rank==2"), "Server card upgrade reaches gameplay snapshot");
            Do("verifyGame.GetUIManager():Close('ShopPanel','Verification'); verifyCard=verifySave.Get().inventory.mods[1]; verifyCfg=require('Game.Mod.ModConfig').Get(verifyCard.id); verifyHost=verifyCfg.category=='Weapon' and 'weapon' or verifyCfg.category=='Skill' and 'skill' or 'frame'; verifyGame.GetUIManager():Open('ModStationPanel')");
            yield return Wait(() => Evaluate("verifyGame.GetUIManager():IsOpen('ModStationPanel') and not verifySession.IsBusy()"), "Mod station opens and refreshes");
            Do("local w=verifyGame.GetUIManager():GetWindow('ModStationPanel'); w:GetModel():SetHost(verifyHost); local c=w:GetController(); c:_refresh(); c:_onBagItem(verifyCard.uid); for i,slot in ipairs(verifySave.Get().loadout[verifyHost].slots) do if require('Game.Mod.ModSystem').CanInstall(verifyHost,verifyCard.uid,i) then verifySlot=i; break end end; assert(verifySlot); c:_onSlot(verifySlot)");
            yield return Wait(() => Evaluate("not verifySession.IsBusy() and verifySave.Get().loadout[verifyHost].installed[verifySlot]==verifyCard.uid"), "Actual Mod controller installs owned card");
            Do("verifyGame.GetUIManager():Close('ModStationPanel','Verification'); assert(verifyGame.StartDungeonRun())");
            yield return Wait(() => Evaluate("verifyGame.GetDungeonManager()~=nil and verifyGame.GetDungeonManager().battleManager~=nil and verifyGame.GetDungeonManager().battleManager.phase==3"), "Equipped loadout reaches real battle");
            Do(@"local dm=verifyGame.GetDungeonManager(); local pc=dm.battleManager.playerController;
                assert(dm.runData.onlineRunId==verifySession.GetRunId());
                local effect=verifyCfg.effect; local value=effect.base+effect.perRank*2;
                local function equal(a,b) assert(math.abs(a-b)<0.0001,tostring(a)..' differs from '..tostring(b)) end;
                if effect.stat=='__capacity' then equal(dm.derived.capacity[verifyHost],10+value)
                elseif effect.mode=='add' then equal(dm.derived.add[effect.stat],value)
                else equal(dm.derived.mul[effect.stat],value) end;
                if effect.stat=='damageMul' then equal(pc.atk,verifyBase.atk*value); equal(dm.battleManager.weaponSystem._modDamageMul,value)
                elseif effect.stat=='fireRate' then equal(pc.atkSpeed,verifyBase.atkSpeed+value)
                elseif effect.stat=='maxHp' then equal(pc.maxHp,verifyBase.maxHp+value)
                elseif effect.stat=='critDamage' then equal(pc.critDmg,verifyBase.critDmg*value)
                elseif effect.stat=='moveSpeed' then equal(pc.moveSpeed,verifyBase.moveSpeed*value)
                elseif effect.stat=='projectileCount' then equal(dm.battleManager.weaponSystem._modProjectileBonus,value) end");
            checks.Add("Rank-two server card changes actual battle attributes or capacity");
            Do(@"local settle=verifySession.Settle;
                verifySession.Settle=function(_,callback) callback(false,'network_error'); return true end;
                local ok,err=pcall(function() assert(verifyGame.GetDungeonManager():UseReturnScroll()) end);
                verifySession.Settle=settle; assert(ok,err)");
            yield return Wait(() => Evaluate("verifyGame.GetDungeonManager().lastResult.settlementStatus=='failed' and verifyGame.GetUIManager():IsOpen('RunResultPanel')"), "Injected settlement failure remains on result panel");
            Do(@"local dm=verifyGame.GetDungeonManager(); assert(dm.battleManager.phase==4);
                verifyFrozenTime=dm.battleManager.elapsedTime;
                assert(not dm:BackToHome()); assert(verifyGame.SwitchScene('Home')==false);
                local w=verifyGame.GetUIManager():GetWindow('RunResultPanel');
                assert(w:GetModel():GetConfirmText()=='重试结算'); assert(w:GetView()._confirmBtn.interactable)");
            double pauseTime = EditorApplication.timeSinceStartup + 1;
            while (EditorApplication.timeSinceStartup < pauseTime) yield return null;
            Do(@"assert(verifyGame.GetDungeonManager().battleManager.phase==4);
                assert(verifyGame.GetDungeonManager().battleManager.elapsedTime==verifyFrozenTime);
                verifyGame.GetUIManager():GetWindow('RunResultPanel'):GetView()._confirmBtn.onClick:Invoke()");
            checks.Add("Failed settlement blocks Home, preserves pause and offers real retry button");
            yield return Wait(() => Evaluate("verifyGame.GetDungeonManager().lastResult.settlementStatus=='confirmed' and verifyGame.GetUIManager():IsOpen('RunResultPanel')"), "Equipped run settles");
            ScreenCapture.CaptureScreenshot(Path.Combine(DirectoryPath, "online_gameplay_result.png"));
            double captureTime = EditorApplication.timeSinceStartup + 1;
            while (EditorApplication.timeSinceStartup < captureTime) yield return null;
            env = null;
            manager.Dispose();
            if (manager.GetLuaEnv() != null) throw new Exception("Lua environment rejected shutdown.");
            manager.Dispose();
            checks.Add("Explicit shutdown releases cached UI callbacks and LuaEnv; repeated Dispose is harmless");
            double shutdownTime = EditorApplication.timeSinceStartup + 0.3;
            while (EditorApplication.timeSinceStartup < shutdownTime) yield return null;
            if (runtimeErrors.Count != 0) throw new Exception("Runtime/shutdown errors: " + string.Join("; ", runtimeErrors));
        }
    }
}
