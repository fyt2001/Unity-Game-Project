// =============================================================================
// AgentHarness.cs - structured, reproducible game driver for agents (Editor only)
// =============================================================================
// Replaces ad-hoc "send free C# to mcp_unity -Code" with a fixed op set driven by JSON scripts:
//   play (implicit: each run enters Play from the script's scene), waitLaunch, waitLua, assertLua,
//   click, gm, joystick, wait, screenshot, dumpLog.
// Output per run: <out>/result.json {pass, steps[], errors[], warnings[], screenshots[], save{}} plus
//   <out>/log.json and PNG screenshots.
// Entry points (all call Start):
//   - batchmode:  Unity -batchmode -projectPath P -executeMethod Game.AgentHarnessEditor.AgentHarness.RunScriptBatch
//                 -agentScript <json> -agentOut <dir>          (no -quit, no -nographics; exits with 0/1/3)
//   - open Editor: tools/game.ps1 drops a request into Temp/AgentHarness/inbox (polled here)
//   - menu:        Tools/Agent Harness/Run smoke_login_home
// Safety: saves go to a per-run sandbox (Storage.SetStorage(SandboxStorage)); the real save file is hashed
// before and after and the run FAILS if it changed. Scenes are recorded and restored like
// OnlineGameplayPlayChecks. Online account name is swapped to a throwaway one and restored.
// =============================================================================
using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using Game.LocalBackend;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;
using XLua;

namespace Game.AgentHarnessEditor
{
    [Serializable]
    public class HarnessStep
    {
        public string op;
        public string label;
        public string expr;
        public float timeoutSec;
        public float seconds;
        public string name;
        public string window;
        public string node;
        public string path;
        public string gm;
        public string arg;
        public float x;
        public float y;
        public float minDistance;
        public bool optional;
    }

    [Serializable]
    public class HarnessScript
    {
        public string name;
        public string description;
        public string include;
        public string scene;
        public float timeoutSec;
        public bool failOnWarnings;
        public string[] failOnWarningContains;
        public HarnessStep[] steps;
    }

    [Serializable] public class StepResult { public int index; public string op; public string label; public bool pass; public string detail; public double seconds; }
    [Serializable] public class SaveCheck { public string path; public string before; public string after; public bool unchanged; public string sandbox; public int redirectedCalls; public int passThroughCalls; }

    [Serializable]
    public class HarnessResult
    {
        public string script;
        public string startedUtc;
        public string finishedUtc;
        public bool pass;
        public bool batch;
        public string status;
        public List<StepResult> steps = new List<StepResult>();
        public List<string> errors = new List<string>();
        public List<string> warnings = new List<string>();
        public List<string> screenshots = new List<string>();
        public SaveCheck save = new SaveCheck();
    }

    [Serializable] internal class SceneRecord { public string path; public bool loaded; public bool active; }
    [Serializable] internal class SceneRecords { public SceneRecord[] records; }
    [Serializable] internal class InboxRequest { public string id; public string script; public string outDir; }

    [InitializeOnLoad]
    public static class AgentHarness
    {
        private const string K = "AgentHarness.";
        private const string DefaultScene = "Assets/Scenes/LaunchScene.unity";
        private static readonly string InboxDir = Path.GetFullPath("Temp/AgentHarness/inbox");

        private static HarnessResult s_result;
        private static HarnessScript s_script;
        private static IEnumerator s_flow;
        private static LuaEnv s_env;
        private static SandboxStorage s_sandbox;
        private static double s_nextInboxPoll;
        private static readonly List<string> s_log = new List<string>();

        static AgentHarness()
        {
            EditorApplication.playModeStateChanged += OnPlayModeChanged;
            EditorApplication.update += OnUpdate;
            if (IsActive) InstallSandbox();   // runs after the domain reload that precedes Play, before scene Awake
        }

        private static bool IsActive { get { return SessionState.GetBool(K + "active", false); } }
        private static string OutDir { get { return SessionState.GetString(K + "out", ""); } }
        private static bool Batch { get { return SessionState.GetBool(K + "batch", false); } }
        private static string RealSavePath { get { return Path.Combine(Application.persistentDataPath, "save/saveData.lua"); } }

        // ------------------------------------------------------------------ entry points

        [MenuItem("Tools/Agent Harness/Run smoke_login_home")]
        public static void RunSmokeFromMenu()
        {
            Start("tools/harness_scripts/smoke_login_home.json", DefaultOutDir("smoke_login_home"), false);
        }

        [MenuItem("Tools/Agent Harness/Reset stuck run")]
        public static void ResetStuckRun()
        {
            SessionState.SetBool(K + "active", false);
            Storage.SetStorage(null);
            Debug.Log("[AgentHarness] state cleared");
        }

        /// <summary>-executeMethod entry. Args: -agentScript path [-agentOut dir].</summary>
        public static void RunScriptBatch()
        {
            string script = Arg("-agentScript"), outDir = Arg("-agentOut");
            if (string.IsNullOrEmpty(script)) { Debug.LogError("[AgentHarness] -agentScript missing"); EditorApplication.Exit(3); return; }
            try { Start(script, string.IsNullOrEmpty(outDir) ? DefaultOutDir(Path.GetFileNameWithoutExtension(script)) : outDir, true); }
            catch (Exception e) { Debug.LogException(e); EditorApplication.Exit(3); }
        }

        /// <summary>Starts a run: records scenes and save hash, then enters Play from the script's scene.</summary>
        public static void Start(string scriptPath, string outDir, bool batch)
        {
            if (EditorApplication.isPlayingOrWillChangePlaymode) throw new InvalidOperationException("Stop Play before running the harness.");
            if (IsActive) throw new InvalidOperationException("A harness run is already active (Tools/Agent Harness/Reset stuck run).");
            HarnessScript script = LoadScript(scriptPath);
            Directory.CreateDirectory(outDir);

            var records = new List<SceneRecord>();
            foreach (var s in EditorSceneManager.GetSceneManagerSetup())
            {
                if (s.isLoaded && UnityEngine.SceneManagement.SceneManager.GetSceneByPath(s.path).isDirty)
                    throw new InvalidOperationException("Save or discard unsaved scene changes before running the harness: " + s.path);
                records.Add(new SceneRecord { path = s.path, loaded = s.isLoaded, active = s.isActive });
            }
            SessionState.SetString(K + "scenes", JsonUtility.ToJson(new SceneRecords { records = records.ToArray() }));
            SessionState.SetString(K + "script", Path.GetFullPath(scriptPath));
            SessionState.SetString(K + "out", Path.GetFullPath(outDir));
            SessionState.SetBool(K + "batch", batch);
            SessionState.SetString(K + "saveBefore", HashFile(RealSavePath));
            SessionState.SetString(K + "account", OnlineGameBridge.AccountName);
            SessionState.SetString(K + "started", DateTime.UtcNow.ToString("o"));
            SessionState.SetString(K + "startedEditorTime", EditorApplication.timeSinceStartup.ToString("R"));
            SessionState.SetBool(K + "flowDone", false);
            SessionState.SetBool(K + "active", true);
            File.WriteAllText(Path.Combine(outDir, "result.json"), "{\"status\":\"starting\",\"pass\":false}");
            EditorSceneManager.OpenScene(string.IsNullOrEmpty(script.scene) ? DefaultScene : script.scene);
            InstallSandbox();
            EditorApplication.isPlaying = true;
        }

        // ------------------------------------------------------------------ lifecycle

        private static void InstallSandbox()
        {
            string outDir = OutDir;
            if (string.IsNullOrEmpty(outDir)) return;
            s_sandbox = new SandboxStorage(Application.persistentDataPath, Path.Combine(outDir, "sandbox_persistentData"));
            Storage.SetStorage(s_sandbox);
        }

        private static void OnPlayModeChanged(PlayModeStateChange state)
        {
            if (!IsActive) return;
            if (state == PlayModeStateChange.EnteredPlayMode)
            {
                s_script = LoadScript(SessionState.GetString(K + "script", ""));
                s_result = new HarnessResult
                {
                    script = s_script.name,
                    startedUtc = SessionState.GetString(K + "started", ""),
                    batch = Batch,
                    status = "running",
                };
                s_log.Clear();
                Application.logMessageReceived += OnLog;
                if (!(Storage.Current is SandboxStorage)) InstallSandbox();
                OnlineGameBridge.AccountName = "agent-harness-" + Guid.NewGuid().ToString("N");
                s_flow = Flow(s_script);
            }
            else if (state == PlayModeStateChange.EnteredEditMode)
            {
                Finish();
            }
        }

        private static void OnUpdate()
        {
            if (IsActive)
            {
                double started;
                double.TryParse(SessionState.GetString(K + "startedEditorTime", "0"), out started);
                float limit = (s_script != null && s_script.timeoutSec > 0 ? s_script.timeoutSec : 300f) + 60f;
                if (EditorApplication.timeSinceStartup - started > limit)
                {
                    if (s_result != null) s_result.errors.Add("harness watchdog: run exceeded " + limit + "s");
                    if (EditorApplication.isPlaying) { s_flow = null; EditorApplication.isPlaying = false; }
                    else Finish();
                    return;
                }
                if (s_flow != null && EditorApplication.isPlaying && !EditorApplication.isPaused) Tick();
                return;
            }
            if (EditorApplication.timeSinceStartup >= s_nextInboxPoll)
            {
                s_nextInboxPoll = EditorApplication.timeSinceStartup + 1.0;
                PollInbox();
            }
        }

        private static void Tick()
        {
            try
            {
                if (!s_flow.MoveNext()) EndFlow(null);
            }
            catch (Exception e)
            {
                EndFlow(e);
            }
        }

        private static void EndFlow(Exception error)
        {
            s_flow = null;
            if (error != null) s_result.errors.Add("step failed: " + error.Message);
            try { CaptureScreenshot("final"); } catch (Exception e) { s_result.warnings.Add("final screenshot failed: " + e.Message); }
            SessionState.SetBool(K + "flowDone", true);
            WriteResult("exiting-play");
            s_env = null;
            EditorApplication.isPlaying = false;
        }

        private static void Finish()
        {
            Application.logMessageReceived -= OnLog;
            if (s_result == null)
            {
                s_result = new HarnessResult { script = SessionState.GetString(K + "script", ""), batch = Batch };
                s_result.errors.Add("harness lost its state before Play finished (domain reload or crash)");
            }
            string before = SessionState.GetString(K + "saveBefore", "");
            string after = HashFile(RealSavePath);
            s_result.save.path = RealSavePath;
            s_result.save.before = before;
            s_result.save.after = after;
            s_result.save.unchanged = before == after;
            if (s_sandbox != null)
            {
                s_result.save.sandbox = s_sandbox.SandboxRoot;
                s_result.save.redirectedCalls = s_sandbox.RedirectedCalls;
                s_result.save.passThroughCalls = s_sandbox.PassThroughCalls;
            }
            if (!s_result.save.unchanged) s_result.errors.Add("real save file changed during the run: " + RealSavePath);
            Storage.SetStorage(null);
            OnlineGameBridge.AccountName = SessionState.GetString(K + "account", "local-player");

            var scenes = JsonUtility.FromJson<SceneRecords>(SessionState.GetString(K + "scenes", "{}"));
            var setup = new List<SceneSetup>();
            if (scenes != null && scenes.records != null)
                foreach (var s in scenes.records)
                    if (!string.IsNullOrEmpty(s.path)) setup.Add(new SceneSetup { path = s.path, isLoaded = s.loaded, isActive = s.active });
            try { if (setup.Count > 0) EditorSceneManager.RestoreSceneManagerSetup(setup.ToArray()); }
            catch (Exception e) { s_result.warnings.Add("scene restore failed: " + e.Message); }

            if (!SessionState.GetBool(K + "flowDone", false) && s_result.errors.Count == 0)
                s_result.errors.Add("Play ended before the script finished");
            bool batch = Batch;
            SessionState.SetBool(K + "active", false);
            WriteResult("done");
            Debug.Log("[AgentHarness] " + (s_result.pass ? "PASS " : "FAIL ") + s_result.script + " -> " + Path.Combine(OutDir, "result.json"));
            bool pass = s_result.pass;
            s_result = null; s_script = null; s_sandbox = null;
            if (batch) EditorApplication.Exit(pass ? 0 : 1);
        }

        private static void WriteResult(string status)
        {
            if (s_result == null) return;
            s_result.status = status;
            s_result.finishedUtc = DateTime.UtcNow.ToString("o");
            bool stepsOk = s_result.steps.TrueForAll(st => st.pass);
            s_result.pass = status == "done" ? (stepsOk && s_result.errors.Count == 0 && s_result.save.unchanged) : false;
            string dir = OutDir;
            if (string.IsNullOrEmpty(dir)) return;
            Directory.CreateDirectory(dir);
            File.WriteAllText(Path.Combine(dir, "result.json"), JsonUtility.ToJson(s_result, true), new UTF8Encoding(false));
            File.WriteAllText(Path.Combine(dir, "log.json"), "{\"lines\":" + JsonArray(s_log) + "}", new UTF8Encoding(false));
        }

        private static void OnLog(string message, string stack, LogType type)
        {
            if (s_result == null) return;
            string line = type + ": " + message;
            if (s_log.Count < 5000) s_log.Add(line);
            if (type == LogType.Error || type == LogType.Exception || type == LogType.Assert)
            {
                s_result.errors.Add(type == LogType.Exception ? line + " | " + FirstLine(stack) : line);
                return;
            }
            if (type != LogType.Warning) return;
            if (s_script != null && s_script.failOnWarnings) { s_result.errors.Add("warning (failOnWarnings): " + message); return; }
            if (s_script != null && s_script.failOnWarningContains != null)
                foreach (var needle in s_script.failOnWarningContains)
                    if (!string.IsNullOrEmpty(needle) && message.Contains(needle)) { s_result.errors.Add("warning matched '" + needle + "': " + message); return; }
            if (s_result.warnings.Count < 200) s_result.warnings.Add(message);
        }

        // ------------------------------------------------------------------ steps

        private static IEnumerator Flow(HarnessScript script)
        {
            string inject = Environment.GetEnvironmentVariable("AGENT_HARNESS_INJECT");
            for (int i = 0; i < script.steps.Length; i++)
            {
                HarnessStep step = script.steps[i];
                var r = new StepResult { index = i, op = step.op, label = string.IsNullOrEmpty(step.label) ? step.op : step.label };
                s_result.steps.Add(r);
                double t0 = EditorApplication.timeSinceStartup;
                // nested IEnumerators (WaitUntil, Joystick) are driven with an explicit stack
                var stack = new Stack<IEnumerator>();
                stack.Push(RunStep(step, r));
                bool failedOptional = false;
                while (stack.Count > 0)
                {
                    bool more;
                    object current = null;
                    try
                    {
                        more = stack.Peek().MoveNext();
                        if (more) current = stack.Peek().Current;
                    }
                    catch (Exception e)
                    {
                        r.pass = false;
                        r.detail = (e is LuaException ? "Lua error: " : "") + e.Message;
                        r.seconds = EditorApplication.timeSinceStartup - t0;
                        if (step.optional) { s_result.warnings.Add("optional step failed: " + r.label + ": " + r.detail); failedOptional = true; break; }
                        throw new Exception(r.label + ": " + r.detail);
                    }
                    if (!more) { stack.Pop(); continue; }
                    var nested = current as IEnumerator;
                    if (nested != null) { stack.Push(nested); continue; }
                    yield return null;
                }
                r.pass = true;
                if (failedOptional) r.detail = "optional, failed: " + r.detail;
                r.seconds = EditorApplication.timeSinceStartup - t0;
                WriteResult("running");
                if (inject == "lua_error" && step.op == "waitLaunch")
                {
                    var ir = new StepResult { index = i, op = "inject", label = "AGENT_HARNESS_INJECT=lua_error" };
                    s_result.steps.Add(ir);
                    Env().DoString("error('agent harness injected Lua error (AGENT_HARNESS_INJECT=lua_error)')", "AgentHarness.inject");
                    ir.pass = true;
                }
            }
        }

        private static IEnumerator RunStep(HarnessStep s, StepResult r)
        {
            switch (s.op)
            {
                case "play":
                    r.detail = "already in Play";
                    yield break;
                case "waitLaunch":
                    yield return WaitUntil(() => GameLaunch.Instance != null && GameLaunch.Instance.CurrentPhase == LaunchPhase.Complete,
                        Timeout(s, 90), "GameLaunch.CurrentPhase == Complete", r);
                    var manager = UnityEngine.Object.FindObjectOfType<XLuaManager>();
                    if (manager == null || manager.GetLuaEnv() == null) throw new Exception("XLuaManager / LuaEnv not available after launch");
                    s_env = manager.GetLuaEnv();
                    yield break;
                case "waitLua":
                    yield return WaitUntil(() => EvalBool(s.expr), Timeout(s, 30), s.expr, r);
                    yield break;
                case "assertLua":
                    if (!EvalBool(s.expr)) throw new Exception("assertLua false: " + s.expr);
                    r.detail = s.expr;
                    yield break;
                case "wait":
                    double until = EditorApplication.timeSinceStartup + Math.Max(0.05f, s.seconds);
                    while (EditorApplication.timeSinceStartup < until) yield return null;
                    yield break;
                case "click":
                    r.detail = Click(s);
                    yield break;
                case "gm":
                    r.detail = Gm(s.gm, s.arg);
                    yield break;
                case "joystick":
                    yield return Joystick(s, r);
                    yield break;
                case "screenshot":
                    r.detail = CaptureScreenshot(string.IsNullOrEmpty(s.name) ? "shot_" + r.index : s.name);
                    yield break;
                case "dumpLog":
                    WriteResult("running");
                    r.detail = Path.Combine(OutDir, "log.json");
                    yield break;
                default:
                    throw new Exception("unknown op '" + s.op + "' (play|waitLaunch|waitLua|assertLua|wait|click|gm|joystick|screenshot|dumpLog)");
            }
        }

        private static float Timeout(HarnessStep s, float fallback) { return s.timeoutSec > 0 ? s.timeoutSec : fallback; }

        private static IEnumerator WaitUntil(Func<bool> predicate, float timeoutSec, string what, StepResult r)
        {
            double deadline = EditorApplication.timeSinceStartup + timeoutSec;
            string lastError = null;
            while (true)
            {
                try { if (predicate()) { r.detail = what; yield break; } lastError = null; }
                catch (Exception e) { lastError = e.Message; }
                if (EditorApplication.timeSinceStartup > deadline)
                    throw new TimeoutException("timeout " + timeoutSec + "s waiting for: " + what + (lastError != null ? " (last error: " + lastError + ")" : ""));
                yield return null;
            }
        }

        private static LuaEnv Env()
        {
            if (s_env == null) throw new Exception("Lua env not ready: put a waitLaunch step first");
            return s_env;
        }

        private static bool EvalBool(string expr)
        {
            object[] v = Env().DoString("return " + expr, "AgentHarness.expr");
            return v != null && v.Length > 0 && v[0] is bool && (bool)v[0];
        }

        private static string Click(HarnessStep s)
        {
            GameObject target;
            string where;
            if (!string.IsNullOrEmpty(s.window))
            {
                Env().Global.Set("__harness_window", s.window);
                object[] v = Env().DoString(
                    "local w = require('Game.GameMain').GetUIManager():GetWindow(__harness_window); __harness_window = nil; return w and w.gameObject",
                    "AgentHarness.click");
                var root = v != null && v.Length > 0 ? v[0] as GameObject : null;
                if (root == null) throw new Exception("window '" + s.window + "' has no GameObject (not open?)");
                Transform t = string.IsNullOrEmpty(s.node) ? root.transform : FindDeep(root.transform, s.node);
                if (t == null) throw new Exception("node '" + s.node + "' not found under window '" + s.window + "'");
                target = t.gameObject;
                where = s.window + "/" + s.node;
            }
            else
            {
                target = GameObject.Find(s.path);
                if (target == null) throw new Exception("hierarchy path not found: " + s.path);
                where = s.path;
            }
            if (!target.activeInHierarchy) throw new Exception(where + " is inactive");
            var selectable = target.GetComponent<Selectable>();
            if (selectable != null && !selectable.IsInteractable()) throw new Exception(where + " is not interactable");
            if (EventSystem.current == null) throw new Exception("no EventSystem in scene");
            var data = new PointerEventData(EventSystem.current) { button = PointerEventData.InputButton.Left };
            bool handled = ExecuteEvents.Execute(target, data, ExecuteEvents.pointerClickHandler);
            if (!handled) throw new Exception(where + " has no IPointerClickHandler");
            return "clicked " + where;
        }

        private static Transform FindDeep(Transform root, string name)
        {
            if (root.name == name) return root;
            for (int i = 0; i < root.childCount; i++)
            {
                var hit = FindDeep(root.GetChild(i), name);
                if (hit != null) return hit;
            }
            return null;
        }

        private const string GmLua = @"
local id, arg = __harness_gm_id, __harness_gm_arg
__harness_gm_id, __harness_gm_arg = nil, nil
local G = require 'Game.GM.GMCommands'
for _, c in ipairs(G.list) do
    if c.id == id then
        if c.available then
            local ok, reason = c.available()
            if not ok then return false, 'unavailable: ' .. tostring(reason) end
        end
        if not c.fn then return false, 'command has no fn' end
        local value = arg
        if value == nil and c.params and c.params[1] then value = c.params[1].default end
        return true, tostring(c.fn(value))
    end
end
return false, 'unknown GM command id: ' .. tostring(id)";

        private static string Gm(string id, string arg)
        {
            Env().Global.Set("__harness_gm_id", id);
            Env().Global.Set("__harness_gm_arg", arg);
            object[] v = Env().DoString(GmLua, "AgentHarness.gm");
            bool ok = v != null && v.Length > 0 && v[0] is bool && (bool)v[0];
            string msg = v != null && v.Length > 1 ? Convert.ToString(v[1]) : "";
            if (!ok) throw new Exception("GM " + id + ": " + msg);
            return "GM " + id + " -> " + msg;
        }

        private static IEnumerator Joystick(HarnessStep s, StepResult r)
        {
            var boot = UnityEngine.Object.FindObjectOfType<HomeSceneBootstrapper>();
            if (boot == null) throw new Exception("HomeSceneBootstrapper not in scene");
            VirtualJoystick stick = null;
            double bindDeadline = EditorApplication.timeSinceStartup + Timeout(s, 10);
            while ((stick = boot.GetJoystick()) == null)
            {
                if (EditorApplication.timeSinceStartup > bindDeadline) throw new Exception("joystick never bound to HomeSceneBootstrapper");
                yield return null;
            }
            Transform player = boot.GetPlayerTransform();
            if (player == null) throw new Exception("player transform missing");
            Vector3 start = player.position;
            var data = new PointerEventData(EventSystem.current);
            stick.OnPointerDown(data);
            double until = EditorApplication.timeSinceStartup + Math.Max(0.2f, s.seconds);
            while (EditorApplication.timeSinceStartup < until)
            {
                stick.axisX = s.x;
                stick.axisY = s.y;
                yield return null;
            }
            stick.OnPointerUp(data);
            player = boot.GetPlayerTransform();
            float moved = player != null ? Vector3.Distance(new Vector3(start.x, 0, start.z), new Vector3(player.position.x, 0, player.position.z)) : 0f;
            r.detail = "moved " + moved.ToString("F2") + " (min " + s.minDistance + ")";
            if (moved < s.minDistance) throw new Exception("joystick input did not move the player enough: " + r.detail);
        }

        private static string CaptureScreenshot(string name)
        {
            string dir = OutDir;
            string file = Path.Combine(dir, SafeName(name) + ".png");
            const int w = 1280, h = 720;
            var rt = RenderTexture.GetTemporary(w, h, 24);
            var prevActive = RenderTexture.active;
            var cams = new List<Camera>(Camera.allCameras);
            cams.Sort((a, b) => a.depth.CompareTo(b.depth));
            try
            {
                RenderTexture.active = rt;
                GL.Clear(true, true, Color.black);
                foreach (var cam in cams)
                {
                    if (cam.targetTexture != null) continue; // offscreen cameras (e.g. login character RT) feed UI already
                    var prev = cam.targetTexture;
                    cam.targetTexture = rt;
                    cam.Render();
                    cam.targetTexture = prev;
                }
                RenderTexture.active = rt;
                var tex = new Texture2D(w, h, TextureFormat.RGB24, false);
                tex.ReadPixels(new Rect(0, 0, w, h), 0, 0);
                tex.Apply();
                File.WriteAllBytes(file, tex.EncodeToPNG());
                UnityEngine.Object.DestroyImmediate(tex);
            }
            finally
            {
                RenderTexture.active = prevActive;
                RenderTexture.ReleaseTemporary(rt);
            }
            if (s_result != null) s_result.screenshots.Add(file);
            return file + " (camera render, " + cams.Count + " cameras; Screen Space Overlay canvases are not captured)";
        }

        // ------------------------------------------------------------------ inbox (Editor open)

        private static void PollInbox()
        {
            if (EditorApplication.isPlayingOrWillChangePlaymode || EditorApplication.isCompiling || !Directory.Exists(InboxDir)) return;
            foreach (string req in Directory.GetFiles(InboxDir, "*.json"))
            {
                InboxRequest r;
                DateTime written = File.GetLastWriteTimeUtc(req);
                try { r = JsonUtility.FromJson<InboxRequest>(File.ReadAllText(req)); }
                catch (Exception e) { Debug.LogWarning("[AgentHarness] bad inbox request " + req + ": " + e.Message); File.Delete(req); continue; }
                File.Delete(req);
                // A request nobody picked up within 2 minutes belongs to a game.ps1 that already gave up: never start it later.
                if ((DateTime.UtcNow - written).TotalSeconds > 120) { Debug.LogWarning("[AgentHarness] dropped stale inbox request " + r.id); continue; }
                try { Start(r.script, r.outDir, false); }
                catch (Exception e)
                {
                    Directory.CreateDirectory(r.outDir);
                    File.WriteAllText(Path.Combine(r.outDir, "result.json"),
                        "{\"status\":\"done\",\"pass\":false,\"errors\":[" + JsonString("start failed: " + e.Message) + "]}");
                }
                return; // one run at a time
            }
        }

        // ------------------------------------------------------------------ helpers

        private static HarnessScript LoadScript(string path)
        {
            string full = Path.GetFullPath(path);
            var script = JsonUtility.FromJson<HarnessScript>(File.ReadAllText(full));
            if (script == null || script.steps == null) throw new Exception("invalid harness script: " + full);
            if (string.IsNullOrEmpty(script.name)) script.name = Path.GetFileNameWithoutExtension(full);
            if (!string.IsNullOrEmpty(script.include))
            {
                var baseScript = LoadScript(Path.Combine(Path.GetDirectoryName(full), script.include));
                var all = new List<HarnessStep>(baseScript.steps);
                all.AddRange(script.steps);
                script.steps = all.ToArray();
                if (string.IsNullOrEmpty(script.scene)) script.scene = baseScript.scene;
                if (script.failOnWarningContains == null || script.failOnWarningContains.Length == 0) script.failOnWarningContains = baseScript.failOnWarningContains;
            }
            return script;
        }

        private static string DefaultOutDir(string name)
        {
            return Path.GetFullPath(Path.Combine("Logs/AgentRuns", DateTime.Now.ToString("yyyyMMdd_HHmmss") + "_" + SafeName(name)));
        }

        private static string Arg(string name)
        {
            string[] args = Environment.GetCommandLineArgs();
            for (int i = 0; i < args.Length - 1; i++) if (args[i] == name) return args[i + 1];
            return null;
        }

        private static string HashFile(string path)
        {
            if (!File.Exists(path)) return "absent";
            using (var sha = SHA256.Create()) return BitConverter.ToString(sha.ComputeHash(File.ReadAllBytes(path))).Replace("-", "");
        }

        private static string SafeName(string s)
        {
            var sb = new StringBuilder();
            foreach (char c in s ?? "") sb.Append(char.IsLetterOrDigit(c) || c == '_' || c == '-' ? c : '_');
            return sb.Length == 0 ? "shot" : sb.ToString();
        }

        private static string FirstLine(string s)
        {
            if (string.IsNullOrEmpty(s)) return "";
            int n = s.IndexOf('\n');
            return n < 0 ? s : s.Substring(0, n);
        }

        private static string JsonString(string s)
        {
            var sb = new StringBuilder("\"");
            foreach (char c in s ?? "")
            {
                if (c == '"' || c == '\\') sb.Append('\\').Append(c);
                else if (c < 0x20) sb.Append("\\u").Append(((int)c).ToString("x4"));
                else sb.Append(c);
            }
            return sb.Append('"').ToString();
        }

        private static string JsonArray(List<string> items)
        {
            var sb = new StringBuilder("[");
            for (int i = 0; i < items.Count; i++) { if (i > 0) sb.Append(','); sb.Append(JsonString(items[i])); }
            return sb.Append(']').ToString();
        }
    }
}
