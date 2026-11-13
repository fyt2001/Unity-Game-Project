using System;
using System.Collections;
using UnityEngine;
using XLua;

namespace Game.LocalBackend
{
    [Serializable] public sealed class GameCard { public int uid; public int id; public int rank; }
    [Serializable] public sealed class GameInventory { public int gold; public GameCard[] mods; }
    [Serializable] public sealed class GameSlot { public string polarity; }
    [Serializable] public sealed class GameInstalled { public int slot; public int uid; }
    [Serializable] public sealed class GameHost { public int capacity; public GameSlot[] slots; public GameInstalled[] installed; }
    [Serializable] public sealed class GameLoadout { public GameHost weapon; public GameHost skill; public GameHost frame; }
    [Serializable] public sealed class GameMeta { public int memoryFragments; }
    [Serializable] public sealed class GameStatistics { public int highestFloor; public int totalRuns; public int totalDeaths; public int totalExtracts; }
    [Serializable] public sealed class GameSnapshot { public GameInventory inventory; public GameLoadout loadout; public GameMeta meta; public GameStatistics statistics; }
    [Serializable] public sealed class GameReward { public int gold; public int fragments; public string outcome; }
#if UNITY_EDITOR || DEVELOPMENT_BUILD
    [Serializable] public sealed class GameReply { public Profile profile; public string runId; public bool replayed; public GameReward reward; }
    [Serializable] internal sealed class ShopCommand { public int expectedRevision; public string requestId; public int count; }
    [Serializable] internal sealed class LoadoutCommand { public int expectedRevision; public string requestId; public string host; public int slot; public int uid; }
    [Serializable] internal sealed class UpgradeCommand { public int expectedRevision; public string requestId; public int uid; }
#endif

    // The class remains available to Lua in release; local networking does not.
    public sealed class OnlineGameBridge : MonoBehaviour
    {
        private static OnlineGameBridge instance;
        public static bool IsSupported
        {
            get
            {
#if UNITY_EDITOR || DEVELOPMENT_BUILD
                return true;
#else
                return false;
#endif
            }
        }
        public static string AccountName { get; set; } = "local-player";
        public static string NewRequestId() { return Guid.NewGuid().ToString("N"); }
        public static void Close()
        {
            if (instance == null) return;
            instance.StopAllCoroutines();
#if UNITY_EDITOR || DEVELOPMENT_BUILD
            instance.activeCallback?.Dispose();
            instance.activeCallback = null;
#endif
            instance.IsBusy = false;
            Destroy(instance.gameObject);
            instance = null;
        }
        public static OnlineGameBridge Instance
        {
            get
            {
                if (!IsSupported) return null;
                if (instance == null)
                {
                    instance = new GameObject("Local gameplay connection").AddComponent<OnlineGameBridge>();
                    DontDestroyOnLoad(instance.gameObject);
                }
                return instance;
            }
        }

        public bool IsBusy { get; private set; }
#if UNITY_EDITOR || DEVELOPMENT_BUILD
        private readonly LocalBackendClient client = new LocalBackendClient();
        private LuaFunction activeCallback;
        public void Login(string account, LuaFunction callback)
        {
            if (IsBusy) { Complete(callback, false, "busy", null); return; }
            IsBusy = true;
            activeCallback = callback;
            StartCoroutine(LoginRoutine(account));
        }

        private IEnumerator LoginRoutine(string account)
        {
            ApiResult<LoginReply> login = null;
            yield return client.Login(account, r => login = r);
            if (login == null || !login.Success) { Finish(false, login == null ? "network_error" : login.Code, null); yield break; }
            ApiResult<Profile> profile = null;
            yield return client.ReadGameProfile(r => profile = r);
            Finish(profile != null && profile.Success, profile == null ? "network_error" : profile.Code,
                profile != null && profile.Success ? new GameReply { profile = profile.Data } : null);
        }

        public void Request(string operation, int revision, string id, string host, int slot,
            int uid, int count, string outcome, LuaFunction callback)
        {
            if (IsBusy) { Complete(callback, false, "busy", null); return; }
            IsBusy = true;
            activeCallback = callback;
            StartCoroutine(RequestRoutine(operation, revision, id, host, slot, uid, count, outcome));
        }

        private IEnumerator RequestRoutine(string operation, int revision, string id, string host,
            int slot, int uid, int count, string outcome)
        {
            if (operation == "refresh")
            {
                ApiResult<Profile> result = null;
                yield return client.ReadGameProfile(r => result = r);
                Finish(result != null && result.Success, result == null ? "network_error" : result.Code,
                    result != null && result.Success ? new GameReply { profile = result.Data } : null);
                yield break;
            }
            ApiResult<GameReply> command = null;
            yield return client.GameCommand(operation, revision, id, host, slot, uid, count, outcome, r => command = r);
            Finish(command != null && command.Success, command == null ? "network_error" : command.Code,
                command != null && command.Success ? command.Data : null);
        }

        private void Finish(bool success, string code, GameReply reply)
        {
            var callback = activeCallback;
            activeCallback = null;
            IsBusy = false;
            Complete(callback, success, code, reply);
        }

        private static void Complete(LuaFunction callback, bool success, string code, GameReply reply)
        {
            if (callback == null) return;
            try { callback.Call(success, code ?? "", reply); }
            catch (Exception error) { Debug.LogError("Gameplay callback failed: " + error.Message); }
            finally { callback.Dispose(); }
        }
#else
        public void Login(string account, LuaFunction callback) { callback?.Dispose(); }
        public void Request(string operation, int revision, string id, string host, int slot,
            int uid, int count, string outcome, LuaFunction callback) { callback?.Dispose(); }
#endif
        private void OnDestroy()
        {
#if UNITY_EDITOR || DEVELOPMENT_BUILD
            activeCallback?.Dispose();
            activeCallback = null;
#endif
            IsBusy = false;
            if (instance == this) instance = null;
        }
    }
}
