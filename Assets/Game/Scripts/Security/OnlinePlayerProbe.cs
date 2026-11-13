#if UNITY_EDITOR || DEVELOPMENT_BUILD
using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using Game.LocalBackend;
using UnityEngine;
using XLua;

namespace Game.Security
{
    // Opt-in integration against the localhost development backend, not Release or anti-cheat validation.
    public sealed class OnlinePlayerProbe : MonoBehaviour
    {
        internal static void ReportCallbackOrigins(LuaEnv env)
        {
            if (env == null) return;
            try
            {
                var flags = System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic;
                var translator = typeof(LuaEnv).GetField("translator", flags).GetValue(env);
                var bridges = (IDictionary)typeof(ObjectTranslator).GetField("delegate_bridges", flags).GetValue(translator);
                foreach (DictionaryEntry entry in bridges)
                {
                    if (!((WeakReference)entry.Value).IsAlive) continue;
                    var result = env.DoString("local f=debug.getregistry()[" + entry.Key + "]; local i=type(f)=='function' and debug.getinfo(f,'Sl'); return i and (i.short_src..':'..i.linedefined) or type(f)", "CallbackOriginCheck");
                    Debug.Log("[OnlinePlayerProbe] Live callback: " + (result.Length > 0 ? result[0] : "unknown"));
                }
            }
            catch (Exception error) { Debug.LogWarning("[OnlinePlayerProbe] Callback diagnosis unavailable: " + error.Message); }
        }

        private readonly List<string> stages = new List<string>();
        private readonly List<string> runtimeErrors = new List<string>();
        private LuaEnv environment;
        private bool onlineGuard;
        private string savePath;
        private string saveHash;

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.BeforeSceneLoad)]
        private static void StartIfRequested()
        {
            if (Application.isEditor || Array.IndexOf(Environment.GetCommandLineArgs(), "--verify-online-gameplay") < 0) return;
            var host = new GameObject("OnlinePlayerProbe");
            DontDestroyOnLoad(host);
            host.AddComponent<OnlinePlayerProbe>();
        }

        private void Awake()
        {
            Application.logMessageReceived += OnRuntimeLog;
            OnlineGameBridge.AccountName = "player-check-" + Guid.NewGuid().ToString("N");
        }

        private void OnDestroy()
        {
            Application.logMessageReceived -= OnRuntimeLog;
            environment = null;
        }

        private void OnRuntimeLog(string message, string trace, LogType type)
        {
            if (type == LogType.Error || type == LogType.Exception
                || message.Contains("try to dispose a LuaEnv") || message.Contains("[XLuaManager] TryCall("))
                runtimeErrors.Add(message + (string.IsNullOrEmpty(trace) ? "" : "\n" + trace));
        }

        // Advance nested iterators here so exceptions from every wait and Lua snippet reach one failure path.
        private IEnumerator Start()
        {
            var stack = new Stack<IEnumerator>();
            stack.Push(Flow());
            while (stack.Count > 0)
            {
                Exception failure = null;
                try
                {
                    EnsureOnlineGuard();
                    CheckRuntimeErrors();
                    var current = stack.Peek();
                    if (!current.MoveNext())
                    {
                        stack.Pop();
                        (current as IDisposable)?.Dispose();
                    }
                    else if (current.Current is IEnumerator nested) stack.Push(nested);
                    else if (current.Current != null) throw new InvalidOperationException("Unsupported probe yield.");
                }
                catch (Exception error) { failure = error; }
                if (failure != null)
                {
                    Fail(failure);
                    yield break;
                }
                if (stack.Count > 0) yield return null;
            }
            Debug.Log("[OnlinePlayerProbe] PASS stages=" + stages.Count + "; localhost dev backend only; not Release/anti-cheat");
            Application.Quit(0);
        }

        private void EnsureOnlineGuard()
        {
            if (onlineGuard) return;
            var manager = FindObjectOfType<XLuaManager>();
            var available = manager == null ? null : manager.GetLuaEnv();
            if (available == null) return;
            // Guard the game's own quit-time Commit even if launch or login subsequently fails.
            available.DoString("assert(require('Game.Online.OnlineSession').SelectOnline()); assert(require('Game.Save.SaveData').IsOnline())", "OnlinePlayerProbeGuard");
            onlineGuard = true;
        }

        private void CheckRuntimeErrors()
        {
            if (runtimeErrors.Count != 0) throw new InvalidOperationException("Runtime/shutdown error: " + runtimeErrors[0]);
        }

        private void Fail(Exception error)
        {
            try { EnsureOnlineGuard(); }
            catch (Exception guardError) { Debug.LogError("[OnlinePlayerProbe] Save guard failed: " + guardError); }
            environment = null;
            try { OnlineGameBridge.Close(); }
            catch (Exception closeError) { Debug.LogError("[OnlinePlayerProbe] Connection cleanup failed: " + closeError); }
            finally
            {
                Debug.LogError("[OnlinePlayerProbe] FAIL stages=" + stages.Count + ": " + error);
                Application.Quit(1);
            }
        }

        private void Do(string source)
        {
            if (environment == null) throw new InvalidOperationException("Game Lua environment unavailable.");
            environment.DoString(source, "OnlinePlayerProbe");
        }

        private bool Evaluate(string condition)
        {
            if (environment == null) throw new InvalidOperationException("Game Lua environment unavailable.");
            var value = environment.DoString("return " + condition, "OnlinePlayerProbeWait");
            return value.Length > 0 && value[0] is bool result && result;
        }

        private IEnumerator Wait(Func<bool> predicate, string stage)
        {
            float deadline = Time.realtimeSinceStartup + 40f;
            while (!predicate())
            {
                if (Time.realtimeSinceStartup >= deadline) throw new TimeoutException(stage);
                yield return null;
            }
            stages.Add(stage);
            Debug.Log("[OnlinePlayerProbe] Stage " + stages.Count + ": " + stage);
        }

        private string HashSave()
        {
            if (!File.Exists(savePath)) return "absent";
            using (var stream = File.OpenRead(savePath))
            using (var sha = SHA256.Create()) return Convert.ToBase64String(sha.ComputeHash(stream));
        }

        private IEnumerator Flow()
        {
            savePath = Path.Combine(Application.persistentDataPath, "save/saveData.lua");
            saveHash = HashSave();
            if (!OnlineGameBridge.IsSupported || !new Uri(LocalBackendClient.Endpoint).IsLoopback)
                throw new InvalidOperationException("Probe requires the localhost development backend.");
            yield return Wait(() =>
            {
                var launch = FindObjectOfType<GameLaunch>();
                return launch != null && launch.CurrentPhase == LaunchPhase.Complete;
            }, "Launch completes");
            var manager = FindObjectOfType<XLuaManager>();
            if (manager == null || manager.GetLuaEnv() == null) throw new InvalidOperationException("Game Lua environment unavailable.");
            environment = manager.GetLuaEnv();
            Do(@"_onlinePlayerProbe={game=require 'Game.GameMain', session=require 'Game.Online.OnlineSession', save=require 'Game.Save.SaveData'};
                local p=_onlinePlayerProbe; assert(p.session.IsSelected() and p.save.IsOnline())");
            yield return Wait(() => Evaluate("_onlinePlayerProbe.game.GetUIManager():IsOpen('LoginPanel')"), "Login panel opens");
            Do(@"local p=_onlinePlayerProbe; local c=p.game.GetUIManager():GetWindow('LoginPanel'):GetController();
                c:OnRefresh(); assert(p.session.IsSelected() and p.save.IsOnline()); c:_onLoginClick()");
            yield return Wait(() => Evaluate("_onlinePlayerProbe.session.IsReady() and _onlinePlayerProbe.game.GetCurrentScene()=='Home' and _onlinePlayerProbe.game.GetUIManager():IsOpen('HomePanel')"), "Real login controller enters online Home");
            Do("local p=_onlinePlayerProbe; assert(p.save.Get().inventory.gold==0 and #p.save.Get().inventory.mods==0); assert(p.session.GetAccountName()==CS.Game.LocalBackend.OnlineGameBridge.AccountName)");
            for (int run = 1; run <= 3; run++)
            {
                Do("assert(_onlinePlayerProbe.session.IsSelected()); assert(_onlinePlayerProbe.game.StartDungeonRun())");
                yield return Wait(() => Evaluate("_onlinePlayerProbe.game.GetDungeonManager()~=nil and _onlinePlayerProbe.game.GetDungeonManager().battleManager~=nil and _onlinePlayerProbe.game.GetDungeonManager().battleManager.phase==3"), "Real battle starts " + run);
                Do(@"local p=_onlinePlayerProbe; local dm=p.game.GetDungeonManager(); local pc=dm.battleManager.playerController;
                    assert(dm.runData.onlineRunId==p.session.GetRunId());
                    p.base={atk=pc.atk,atkSpeed=pc.atkSpeed,maxHp=pc.maxHp,critDmg=pc.critDmg,moveSpeed=pc.moveSpeed};
                    assert(dm:UseReturnScroll())");
                yield return Wait(() => Evaluate("_onlinePlayerProbe.game.GetDungeonManager().lastResult and _onlinePlayerProbe.game.GetDungeonManager().lastResult.settlementStatus=='confirmed' and _onlinePlayerProbe.game.GetUIManager():IsOpen('RunResultPanel')"), "Extraction receipt confirmed " + run);
                Do("local p=_onlinePlayerProbe; assert(p.game.GetDungeonManager().battleManager.phase==4); assert(p.game.GetUIManager():GetWindow('RunResultPanel'):GetModel().result.gold==100); assert(p.save.Get().inventory.gold==" + (run * 100) + "); assert(p.game.GetDungeonManager():BackToHome())");
                yield return Wait(() => Evaluate("_onlinePlayerProbe.game.GetCurrentScene()=='Home' and _onlinePlayerProbe.game.GetUIManager():IsOpen('HomePanel')"), "Receipt returns Home " + run);
            }
            Do("_onlinePlayerProbe.game.GetUIManager():Open('ShopPanel')");
            yield return Wait(() => Evaluate("_onlinePlayerProbe.game.GetUIManager():IsOpen('ShopPanel') and not _onlinePlayerProbe.session.IsBusy()"), "Shop refreshed");
            Do("_onlinePlayerProbe.game.GetUIManager():GetWindow('ShopPanel'):GetController():_onBuy(1)");
            yield return Wait(() => Evaluate("not _onlinePlayerProbe.session.IsBusy() and #_onlinePlayerProbe.save.Get().inventory.mods==1 and _onlinePlayerProbe.save.Get().inventory.gold==0"), "Real Shop buys server-owned card");
            Do(@"local p=_onlinePlayerProbe; p.game.GetUIManager():Close('ShopPanel','Verification');
                p.card=p.save.Get().inventory.mods[1]; p.config=assert(require('Game.Mod.ModConfig').Get(p.card.id));
                p.host=p.config.category=='Weapon' and 'weapon' or p.config.category=='Skill' and 'skill' or 'frame';
                p.game.GetUIManager():Open('ModStationPanel')");
            yield return Wait(() => Evaluate("_onlinePlayerProbe.game.GetUIManager():IsOpen('ModStationPanel') and not _onlinePlayerProbe.session.IsBusy()"), "Mod station refreshed");
            Do(@"local p=_onlinePlayerProbe; local w=p.game.GetUIManager():GetWindow('ModStationPanel'); w:GetModel():SetHost(p.host);
                local c=w:GetController(); c:_refresh(); c:_onBagItem(p.card.uid);
                for i in ipairs(p.save.Get().loadout[p.host].slots) do
                    if require('Game.Mod.ModSystem').CanInstall(p.host,p.card.uid,i) then p.slot=i; break end
                end; assert(p.slot); c:_onSlot(p.slot)");
            yield return Wait(() => Evaluate("not _onlinePlayerProbe.session.IsBusy() and _onlinePlayerProbe.save.Get().loadout[_onlinePlayerProbe.host].installed[_onlinePlayerProbe.slot]==_onlinePlayerProbe.card.uid"), "Real Mod controller equips owned card");
            Do("local p=_onlinePlayerProbe; p.game.GetUIManager():Close('ModStationPanel','Verification'); assert(p.game.StartDungeonRun())");
            yield return Wait(() => Evaluate("_onlinePlayerProbe.game.GetDungeonManager()~=nil and _onlinePlayerProbe.game.GetDungeonManager().battleManager~=nil and _onlinePlayerProbe.game.GetDungeonManager().battleManager.phase==3"), "Equipped real battle starts");
            Do(@"local p=_onlinePlayerProbe; local dm=p.game.GetDungeonManager(); local pc=dm.battleManager.playerController;
                assert(dm.runData.onlineRunId==p.session.GetRunId()); local effect=p.config.effect; local value=effect.base+effect.perRank*p.card.rank;
                local function equal(a,b) assert(math.abs(a-b)<0.0001,tostring(a)..' differs from '..tostring(b)) end;
                if effect.stat=='__capacity' then equal(dm.derived.capacity[p.host],10+value)
                elseif effect.mode=='add' then equal(dm.derived.add[effect.stat],value)
                else equal(dm.derived.mul[effect.stat],value) end;
                if effect.stat=='damageMul' then equal(pc.atk,p.base.atk*value); equal(dm.battleManager.weaponSystem._modDamageMul,value)
                elseif effect.stat=='fireRate' then equal(pc.atkSpeed,p.base.atkSpeed+value)
                elseif effect.stat=='maxHp' then equal(pc.maxHp,p.base.maxHp+value)
                elseif effect.stat=='critDamage' then equal(pc.critDmg,p.base.critDmg*value)
                elseif effect.stat=='moveSpeed' then equal(pc.moveSpeed,p.base.moveSpeed*value)
                elseif effect.stat=='projectileCount' then equal(dm.battleManager.weaponSystem._modProjectileBonus,value) end;
                assert(dm:UseReturnScroll())");
            stages.Add("Owned card affects actual battle attributes or capacity");
            yield return Wait(() => Evaluate("_onlinePlayerProbe.game.GetDungeonManager().lastResult and _onlinePlayerProbe.game.GetDungeonManager().lastResult.settlementStatus=='confirmed' and _onlinePlayerProbe.game.GetUIManager():IsOpen('RunResultPanel')"), "Equipped extraction receipt confirmed");
            Do("local p=_onlinePlayerProbe; assert(p.save.IsOnline()); assert(p.save.Get().statistics.totalExtracts==4); assert(p.save.Get().inventory.gold==100)");
            if (HashSave() != saveHash) throw new InvalidOperationException("Offline save changed during online flow.");
            environment = null;
            manager.Dispose();
            if (manager.GetLuaEnv() != null) throw new InvalidOperationException("Lua environment rejected shutdown.");
            float observationEnd = Time.realtimeSinceStartup + 0.3f;
            while (Time.realtimeSinceStartup < observationEnd) yield return null;
            CheckRuntimeErrors();
            if (HashSave() != saveHash) throw new InvalidOperationException("Offline save changed during shutdown.");
            stages.Add("Lua shutdown and 0.3-second observation complete; offline save unchanged");
        }
    }
}
#endif
