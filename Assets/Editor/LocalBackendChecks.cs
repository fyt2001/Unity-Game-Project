using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using Game.LocalBackend;
using UnityEditor;
using UnityEngine;

namespace Game.LocalBackendEditor
{
    public static class LocalBackendChecks
    {
        [Serializable] private sealed class CheckReport
        {
            public string utc;
            public string endpoint;
            public string scope = "Unity Editor HTTP only; no Player/device acceptance";
            public bool passed;
            public string error;
            public string[] checks;
        }

        private static LocalBackendJob job;
        private static List<string> checks;
        public static string Status { get; private set; }
        public static string ReportPath { get; private set; }

        [MenuItem("Tools/Local Backend/验证接口闭环")]
        public static void Start()
        {
            Begin(RoundTrip(), "roundtrip");
        }

        public static void StartOfflineCheck()
        {
            Begin(Offline(), "offline");
        }

        // Scoped manual pump for remote editor sessions that do not dispatch update while unfocused.
        public static string Poll()
        {
            if (job != null && job.IsRunning) job.Tick();
            return Status;
        }

        private static void Begin(IEnumerator routine, string suffix)
        {
            if (job != null && job.IsRunning) throw new InvalidOperationException("Local checks already running.");
            checks = new List<string>();
            Status = "Running";
            string directory = Path.GetFullPath(Path.Combine(Application.dataPath, "../Docs/Verification"));
            Directory.CreateDirectory(directory);
            ReportPath = Path.Combine(directory, "local_backend_" + suffix + "_" + DateTime.UtcNow.ToString("yyyyMMdd_HHmmss") + ".json");
            job = new LocalBackendJob(routine, error =>
            {
                Status = error == null ? "Passed: " + checks.Count : "Failed: " + error.Message;
                var report = new CheckReport
                {
                    utc = DateTime.UtcNow.ToString("o"), endpoint = LocalBackendClient.Endpoint,
                    passed = error == null, error = error == null ? null : error.ToString(), checks = checks.ToArray()
                };
                File.WriteAllText(ReportPath, JsonUtility.ToJson(report, true));
                Debug.Log("Local backend " + Status + "; report: " + ReportPath);
            });
        }

        private static void Require(bool passed, string name)
        {
            if (!passed) throw new InvalidOperationException(name);
            checks.Add(name);
        }

        private static T Success<T>(ApiResult<T> result, string name) where T : class
        {
            Require(result != null && result.Success, name + (result == null ? " (no callback)" : " " + result.Code));
            return result.Data;
        }

        private static IEnumerator Offline()
        {
            var client = new LocalBackendClient();
            ApiResult<HealthReply> result = null;
            yield return client.Health(r => result = r);
            Require(result != null && !result.Success && result.Status == 0, "Offline service terminates with network failure");
            Require(!client.IsBusy && !client.IsLoggedIn, "Offline failure releases client state");
        }

        private static IEnumerator RoundTrip()
        {
            CheckDraftConflict();
            var a = new LocalBackendClient();
            var b = new LocalBackendClient();
            var stale = new LocalBackendClient();
            string name = "verify-" + Guid.NewGuid().ToString("N");
            ApiResult<HealthReply> health = null;
            yield return a.Health(r => health = r);
            Success(health, "Protocol/development health");
            ApiResult<Profile> result = null;
            yield return a.ReadProfile(r => result = r);
            Require(!result.Success && result.Code == "not_logged_in", "Unauthenticated client blocked");
            var tokenField = typeof(LocalBackendClient).GetField("token", System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic);
            tokenField.SetValue(a, new string('A', 43));
            yield return a.ReadProfile(r => result = r);
            Require(!result.Success && result.Status == 401 && result.Code == "unauthorized"
                && !string.IsNullOrEmpty(result.Message) && !a.IsLoggedIn, "Invalid session receives structured 401 and clears client token");
            ApiResult<LoginReply> login = null;
            yield return a.Login(name, r => login = r);
            Success(login, "Account A login");
            yield return a.ReadProfile(r => result = r);
            Profile first = Success(result, "Read initial profile");
            Require(first.gold == 0 && first.fragments == 0 && first.totalRuns == 0, "New account has no rewards");
            int revision = first.revision;
            string json = "{\"settings\":{\"musicVolume\":0.25},\"loadout\":{\"weapon\":{\"installed\":[\"test-card\"]}}}";
            yield return a.Save(revision, json, r => result = r);
            Profile saved = Success(result, "Save client data");
            Require(saved.revision == revision + 1 && saved.gold == 0, "Save increments version without minting currency");
            yield return a.ReadProfile(r => result = r);
            Profile read = Success(result, "Read saved data");
            Require(read.dataJson.Contains("test-card") && read.dataJson.Contains("0.25"), "Nested loadout/settings round trip");
            yield return a.Save(revision, "{}", r => result = r);
            Require(!result.Success && result.Status == 409 && result.Code == "revision_conflict"
                && !string.IsNullOrEmpty(result.Message), "Stale write rejected with structured error");
            yield return a.ReadProfile(r => result = r);
            Require(Success(result, "Read after conflict").dataJson == read.dataJson, "Conflict preserves previous save");
            yield return a.Save(read.revision, "{\"gold\":99999}", r => result = r);
            Require(!result.Success && result.Status == 400 && result.Code == "invalid_request"
                && !string.IsNullOrEmpty(result.Message), "Protected currency root rejected with structured error");
            yield return stale.Login(name, r => login = r);
            Success(login, "Same account second session");
            yield return stale.ReadProfile(r => result = r);
            Require(Success(result, "Same account reads saved profile").accountId == first.accountId, "Login maps to stable account");
            yield return b.Login(name + "-b", r => login = r);
            Success(login, "Account B login");
            yield return b.ReadProfile(r => result = r);
            Profile other = Success(result, "Read account B");
            Require(other.accountId != first.accountId && other.dataJson == "{}" && other.gold == 0, "Accounts isolated");
            ApiResult<RunReply> run = null;
            yield return a.StartRun(r => run = r);
            string runId = Success(run, "Start simulated run").runId;
            ApiResult<SettlementReply> settlement = null;
            yield return b.Settle(runId, "extract", r => settlement = r);
            Require(!settlement.Success && (settlement.Status == 403 || settlement.Status == 404), "Other account cannot settle run");
            yield return a.Settle(runId, "extract", r => settlement = r);
            Profile extracted = Success(settlement, "Extract settlement").profile;
            Require(extracted.gold == 100 && extracted.fragments == 5 && extracted.totalRuns == 1
                && extracted.totalExtracts == 1 && extracted.highestFloor == 1, "Server preset rewards applied once");
            yield return a.Settle(runId, "extract", r => settlement = r);
            SettlementReply replay = Success(settlement, "Repeat extraction");
            Require(replay.replayed && replay.profile.gold == 100 && replay.profile.revision == extracted.revision, "Retry does not duplicate rewards");
            yield return a.Settle(runId, "death", r => settlement = r);
            Require(!settlement.Success && settlement.Status == 409 && settlement.Code == "outcome_conflict"
                && !string.IsNullOrEmpty(settlement.Message), "Conflicting settlement rejected with structured error");
            yield return a.StartRun(r => run = r);
            runId = Success(run, "Start second run").runId;
            yield return a.Settle(runId, "death", r => settlement = r);
            Profile died = Success(settlement, "Death settlement").profile;
            Require(died.gold == 100 && died.fragments == 10 && died.totalRuns == 2 && died.totalDeaths == 1, "Death grants fragments only");
            Require(died.dataJson == read.dataJson, "Settlement preserves client save");
            a.Logout();
            Require(!a.IsLoggedIn && !a.IsBusy, "Logout clears memory session");
            yield return a.Login(name, r => login = r);
            Success(login, "Relogin");
            yield return a.ReadProfile(r => result = r);
            Require(Success(result, "Read after relogin").gold == 100, "Relogin retains server save");
            bool cancelledCallback = false;
            var cancelled = new LocalBackendJob(a.ReadProfile(r => cancelledCallback = true), null);
            cancelled.Tick();
            Require(a.IsBusy, "Cancellation probe owns active request");
            ApiResult<HealthReply> busy = null;
            yield return a.Health(r => busy = r);
            Require(!busy.Success && busy.Code == "busy", "Concurrent client request rejected");
            cancelled.Dispose();
            Require(!a.IsBusy && !cancelledCallback, "Cancellation releases request without late callback");
            yield return a.ReadProfile(r => result = r);
            Success(result, "Client remains usable after cancellation");
            a.Logout(); b.Logout(); stale.Logout();
        }

        private static void CheckDraftConflict()
        {
            var draft = new LocalBackendDraft();
            Require(!draft.HasBaseline, "Editing remains disabled until an initial server profile is available");
            draft.Reset(new Profile { revision = 1, dataJson = "{\"settings\":{\"a\":1}}" });
            string edited = "{\"settings\":{\"a\":2}}";
            draft.Text = edited;
            var remote = new Profile { revision = 2, dataJson = "{\"settings\":{\"a\":3}}" };
            draft.Receive(remote);
            Require(draft.HasConflict && draft.BaseRevision == 1 && draft.Text == edited, "Refresh preserves dirty draft and original version");
            remote.revision = 3;
            draft.Receive(remote);
            Require(draft.HasConflict && draft.BaseRevision == 1, "Settlement cannot rebase stale draft over remote changes");
            draft.Reset(remote);
            Require(!draft.IsDirty && !draft.HasConflict && draft.BaseRevision == 3, "Explicit server-data adoption resolves draft");
            draft.Text = edited;
            remote.revision = 4;
            draft.Receive(remote);
            Require(!draft.HasConflict && draft.BaseRevision == 4 && draft.Text == edited, "Currency-only settlement retains draft safely");
        }
    }
}
