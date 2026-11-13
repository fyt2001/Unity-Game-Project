#if UNITY_EDITOR || DEVELOPMENT_BUILD
using System;
using System.Collections;
using System.Text;
using UnityEngine;
using UnityEngine.Networking;

namespace Game.LocalBackend
{
    [Serializable] public sealed class HealthReply
    {
        public string status;
        public bool developmentOnly;
        public int protocolVersion;
    }

    [Serializable] public sealed class LoginReply
    {
        public string token;
        public string accountId;
        public long expiresAt;
    }

    [Serializable] public sealed class Profile
    {
        public string accountId;
        public int revision;
        public int gold;
        public int fragments;
        public int totalRuns;
        public int totalDeaths;
        public int totalExtracts;
        public int highestFloor;
        public string dataJson;
        public GameSnapshot game;
    }

    [Serializable] public sealed class RunReply { public string runId; }
    [Serializable] public sealed class SettlementReply { public Profile profile; public bool replayed; }
    [Serializable] internal sealed class ErrorReply { public string code; public string message; }
    [Serializable] internal sealed class LoginRequest { public string accountName; }
    [Serializable] internal sealed class SaveRequest { public int expectedRevision; public string dataJson; }
    [Serializable] internal sealed class SettlementRequest { public string outcome; }

    public sealed class ApiResult<T> where T : class
    {
        public bool Success { get; internal set; }
        public long Status { get; internal set; }
        public T Data { get; internal set; }
        public string Code { get; internal set; }
        public string Message { get; internal set; }
    }

    // Explicit opt-in client; no PlayerPrefs, offline-save writes, or automatic scene hooks.
    public sealed class LocalBackendClient
    {
        public const string Endpoint = "http://127.0.0.1:8120";
        private string token;
        public bool IsLoggedIn { get { return !string.IsNullOrEmpty(token); } }
        public bool IsBusy { get; private set; }

        public void Logout()
        {
            if (IsBusy) throw new InvalidOperationException("A local request is active.");
            token = null;
        }

        public IEnumerator Health(Action<ApiResult<HealthReply>> callback)
        {
            return Request("GET", "/health", null, false,
                r => r.status == "ok" && r.developmentOnly && r.protocolVersion == 1, callback);
        }

        public IEnumerator Login(string accountName, Action<ApiResult<LoginReply>> callback)
        {
            if (IsBusy) { Fail(callback, "busy", "A local request is active."); yield break; }
            token = null;
            yield return Request("POST", "/api/dev/login", JsonUtility.ToJson(new LoginRequest { accountName = accountName }), false,
                r => !string.IsNullOrEmpty(r.token) && !string.IsNullOrEmpty(r.accountId) && r.expiresAt > 0,
                (ApiResult<LoginReply> result) =>
                {
                    if (result.Success) token = result.Data.token;
                    if (callback != null) callback(result);
                });
        }

        public IEnumerator ReadProfile(Action<ApiResult<Profile>> callback)
        {
            return Request("GET", "/api/profile", null, true, ValidProfile, callback);
        }

        public IEnumerator Save(int expectedRevision, string dataJson, Action<ApiResult<Profile>> callback)
        {
            return Request("PUT", "/api/save", JsonUtility.ToJson(new SaveRequest
                { expectedRevision = expectedRevision, dataJson = dataJson }), true, ValidProfile, callback);
        }

        public IEnumerator StartRun(Action<ApiResult<RunReply>> callback)
        {
            return Request("POST", "/api/runs/start", "{}", true, r => !string.IsNullOrEmpty(r.runId), callback);
        }

        public IEnumerator Settle(string runId, string outcome, Action<ApiResult<SettlementReply>> callback)
        {
            if (string.IsNullOrEmpty(runId)) { Fail(callback, "missing_run", "No local run selected."); return Empty(); }
            return Request("POST", "/api/runs/" + UnityWebRequest.EscapeURL(runId) + "/settle",
                JsonUtility.ToJson(new SettlementRequest { outcome = outcome }), true,
                r => r.profile != null && ValidProfile(r.profile), callback);
        }

        public IEnumerator ReadGameProfile(Action<ApiResult<Profile>> callback)
        {
            return Request("GET", "/api/game/profile", null, true,
                p => ValidProfile(p) && p.game != null, callback);
        }

        public IEnumerator GameCommand(string operation, int revision, string id, string host,
            int slot, int uid, int count, string outcome, Action<ApiResult<GameReply>> callback)
        {
            string path;
            string body;
            switch (operation)
            {
                case "purchase":
                    path = "/api/game/shop";
                    body = JsonUtility.ToJson(new ShopCommand { expectedRevision = revision, requestId = id, count = count });
                    break;
                case "loadout":
                    path = "/api/game/loadout";
                    body = JsonUtility.ToJson(new LoadoutCommand { expectedRevision = revision, requestId = id, host = host, slot = slot, uid = uid });
                    break;
                case "upgrade":
                    path = "/api/game/mod/upgrade";
                    body = JsonUtility.ToJson(new UpgradeCommand { expectedRevision = revision, requestId = id, uid = uid });
                    break;
                case "start": path = "/api/game/runs/start"; body = "{}"; break;
                case "settle":
                    if (string.IsNullOrEmpty(id)) { Fail(callback, "missing_run", "No run selected."); return Empty(); }
                    path = "/api/game/runs/" + UnityWebRequest.EscapeURL(id) + "/settle";
                    body = JsonUtility.ToJson(new SettlementRequest { outcome = outcome });
                    break;
                default: Fail(callback, "invalid_operation", "Unknown gameplay command."); return Empty();
            }
            return Request("POST", path, body, true,
                r => r.profile != null && ValidProfile(r.profile) && r.profile.game != null
                    && (operation != "start" || !string.IsNullOrEmpty(r.runId))
                    && (operation != "settle" || (r.reward != null && r.reward.gold >= 0
                        && r.reward.fragments >= 0 && r.reward.outcome == outcome)), callback);
        }

        private static bool ValidProfile(Profile p)
        {
            return !string.IsNullOrEmpty(p.accountId) && p.revision >= 0 && p.gold >= 0
                && p.fragments >= 0 && p.totalRuns >= 0 && p.totalDeaths >= 0
                && p.totalExtracts >= 0 && p.highestFloor >= 0 && !string.IsNullOrEmpty(p.dataJson);
        }

        private static IEnumerator Empty() { yield break; }

        private static void Fail<T>(Action<ApiResult<T>> callback, string code, string message) where T : class
        {
            if (callback != null) callback(new ApiResult<T> { Code = code, Message = message });
        }

        private IEnumerator Request<T>(string method, string path, string body, bool authenticated,
            Func<T, bool> validate, Action<ApiResult<T>> callback) where T : class
        {
            if (IsBusy) { Fail(callback, "busy", "A local request is active."); yield break; }
            if (authenticated && !IsLoggedIn) { Fail(callback, "not_logged_in", "Log in to a local test account first."); yield break; }
            IsBusy = true;
            ApiResult<T> result;
            try
            {
                using (var request = new UnityWebRequest(Endpoint + path, method))
                {
                    request.timeout = 5;
                    request.redirectLimit = 0;
                    request.useHttpContinue = false;
                    request.downloadHandler = new DownloadHandlerBuffer();
                    request.SetRequestHeader("Accept", "application/json");
                    if (body != null)
                    {
                        request.uploadHandler = new UploadHandlerRaw(Encoding.UTF8.GetBytes(body));
                        request.SetRequestHeader("Content-Type", "application/json");
                    }
                    if (authenticated) request.SetRequestHeader("Authorization", "Bearer " + token);
                    yield return request.SendWebRequest();
                    result = Decode<T>(request, validate);
                    if (request.responseCode == 401) token = null;
                }
            }
            finally { IsBusy = false; }
            if (callback != null) callback(result);
        }

        private static ApiResult<T> Decode<T>(UnityWebRequest request, Func<T, bool> validate) where T : class
        {
            var result = new ApiResult<T> { Status = request.responseCode };
            if (request.result != UnityWebRequest.Result.Success)
            {
                result.Code = "network_error";
                result.Message = request.error ?? "Local backend unavailable.";
                try
                {
                    var error = JsonUtility.FromJson<ErrorReply>(request.downloadHandler.text);
                    if (error != null && !string.IsNullOrEmpty(error.code))
                    {
                        result.Code = error.code;
                        result.Message = error.message;
                    }
                }
                catch (ArgumentException) { }
                return result;
            }
            try
            {
                result.Data = JsonUtility.FromJson<T>(request.downloadHandler.text);
                if (result.Data == null || !validate(result.Data)) throw new ArgumentException("Unexpected local response.");
                result.Success = true;
            }
            catch (ArgumentException)
            {
                result.Code = "invalid_response";
                result.Message = "The local response did not match protocol version 1.";
            }
            return result;
        }
    }
}
#endif
