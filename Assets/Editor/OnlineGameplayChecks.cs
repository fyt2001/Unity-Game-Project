using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Text;
using Game.LocalBackend;
using UnityEditor;
using UnityEngine;
using XLua;

namespace Game.LocalBackendEditor
{
    public sealed class OnlineGameplayChecks : EditorWindow
    {
        private static LocalBackendJob job;
        private static readonly List<string> checks = new List<string>();
        [MenuItem("Tools/Local Backend/游戏账号")]
        private static void Open() { GetWindow<OnlineGameplayChecks>("游戏联调"); }
        private void OnGUI()
        {
            using (new EditorGUI.DisabledScope(EditorApplication.isPlaying))
                OnlineGameBridge.AccountName = EditorGUILayout.TextField("联调账号", OnlineGameBridge.AccountName);
            if (GUILayout.Button("验证游戏接入")) Run();
        }
        [MenuItem("Tools/Local Backend/验证游戏接入")]
        public static void Run()
        {
            if (job != null && job.IsRunning) return;
            checks.Clear();
            job = new LocalBackendJob(Check(), error =>
            {
                string directory = Path.GetFullPath("Docs/Verification");
                Directory.CreateDirectory(directory);
                File.WriteAllText(Path.Combine(directory, "online_gameplay_latest.txt"),
                    DateTime.UtcNow.ToString("o") + "\nScope: Editor Lua unit + real HTTP, not Player/device acceptance\n"
                    + (error == null ? "PASS\n" : "FAIL: " + error + "\n") + string.Join("\n", checks));
                if (error != null) Debug.LogException(error);
                else Debug.Log("[OnlineGameplayChecks] PASS " + checks.Count + " groups");
            });
        }
        private static void Require(bool condition, string message)
        {
            if (!condition) throw new Exception(message);
            checks.Add(message);
        }
        private static IEnumerator Check()
        {
            using (var env = new LuaEnv())
            {
                env.AddLoader((ref string path) =>
                {
                    string file = "Assets/Game/LuaScripts/" + path.Replace('.', '/') + ".lua";
                    return File.Exists(file) ? File.ReadAllBytes(file) : null;
                });
                foreach (string file in Directory.GetFiles("Assets/Game/LuaScripts", "*.lua", SearchOption.AllDirectories))
                {
                    env.Global.Set("checkedSource", File.ReadAllText(file));
                    env.DoString("assert(load(checkedSource, 'syntax', 't', {}))");
                }
                checks.Add("All Lua source syntax parsed by XLua");
                var shutdown = env.DoString(File.ReadAllText("tests/ui_shutdown.lua"));
                Require(Convert.ToInt32(shutdown[0]) == 10, "UI shutdown covers cached/pending windows, late animations and optional tokens");
                var result = env.DoString(File.ReadAllText("tests/online_session.lua"));
                Require(Convert.ToInt32(result[0]) >= 25, "Session isolation, immutable retry, expiry recovery, battle Mod effect");
            }
            var client = new LocalBackendClient();
            ApiResult<LoginReply> login = null;
            yield return client.Login("game-check-" + Guid.NewGuid().ToString("N"), r => login = r);
            Require(login != null && login.Success, "Real game account login");
            ApiResult<Profile> profile = null;
            yield return client.ReadGameProfile(r => profile = r);
            Require(profile != null && profile.Success && profile.Data.game.inventory.gold == 0, "Managed profile starts without offline import");
            ApiResult<GameReply> reply = null;
            for (int i = 0; i < 3; i++)
            {
                yield return client.GameCommand("start", 0, "", "", 0, 0, 0, "", r => reply = r);
                Require(reply != null && reply.Success, "Server run start " + i);
                string id = reply.Data.runId;
                yield return client.GameCommand("settle", 0, id, "", 0, 0, 0, "extract", r => reply = r);
                Require(reply.Success && reply.Data.reward.gold == 100, "Explicit reward receipt " + i);
                yield return client.GameCommand("settle", 0, id, "", 0, 0, 0, "extract", r => reply = r);
                Require(reply.Success && reply.Data.replayed && reply.Data.profile.gold == (i + 1) * 100, "No duplicate settlement reward " + i);
            }
            int revision = reply.Data.profile.revision;
            string requestId = OnlineGameBridge.NewRequestId();
            yield return client.GameCommand("purchase", revision, requestId, "", 0, 0, 1, "", r => reply = r);
            Require(reply.Success && reply.Data.profile.gold == 0 && reply.Data.profile.game.inventory.mods.Length == 1, "Shop debits and grants atomically");
            yield return client.GameCommand("purchase", revision, requestId, "", 0, 0, 1, "", r => reply = r);
            Require(reply.Success && reply.Data.replayed && reply.Data.profile.game.inventory.mods.Length == 1, "Purchase retry does not debit or grant again");
            var card = reply.Data.profile.game.inventory.mods[0];
            string host = card.id < 2000 ? "weapon" : card.id < 3000 ? "skill" : "frame";
            int slot = card.id == 3001 || card.id == 2002 ? 2 : card.id == 1003 ? 3 : card.id == 1002 ? 2 : 1;
            revision = reply.Data.profile.revision;
            yield return client.GameCommand("loadout", revision, OnlineGameBridge.NewRequestId(), host, slot, card.uid, 0, "", r => reply = r);
            Require(reply.Success && reply.Data.profile.game.loadout != null, "Server-owned Mod installation");
            var installed = host == "weapon" ? reply.Data.profile.game.loadout.weapon : host == "skill" ? reply.Data.profile.game.loadout.skill : reply.Data.profile.game.loadout.frame;
            Require(installed.installed.Length == 1 && installed.installed[0].uid == card.uid && installed.installed[0].slot == slot, "DTO preserves one-based installed slots");
            yield return client.GameCommand("start", 0, "", "", 0, 0, 0, "", r => reply = r);
            Require(reply.Success && reply.Data.profile.game.inventory.mods[0].uid == card.uid, "Battle start receives authoritative loadout");
            yield return client.GameCommand("settle", 0, reply.Data.runId, "", 0, 0, 0, "death", r => reply = r);
            Require(reply.Success && reply.Data.reward.gold == 0, "Death simulation does not award gold");
            client.Logout();
        }
    }
}
