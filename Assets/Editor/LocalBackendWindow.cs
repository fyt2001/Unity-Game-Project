using System;
using System.Collections;
using System.Collections.Generic;
using Game.LocalBackend;
using UnityEditor;
using UnityEngine;

namespace Game.LocalBackendEditor
{
    internal sealed class LocalBackendDraft
    {
        public string Text = "{}";
        public string BaseData { get; private set; }
        public int BaseRevision { get; private set; } = -1;
        public bool HasConflict { get; private set; }
        public bool HasBaseline { get { return BaseRevision >= 0; } }
        public bool IsDirty { get { return BaseRevision >= 0 && Text != BaseData; } }

        public void Reset(Profile profile)
        {
            Text = BaseData = profile.dataJson;
            BaseRevision = profile.revision;
            HasConflict = false;
        }

        public void Receive(Profile profile)
        {
            if (!IsDirty) { Reset(profile); return; }
            HasConflict = profile.dataJson != BaseData;
            // Currency-only changes can advance the draft base; another writer's data cannot.
            if (!HasConflict) BaseRevision = profile.revision;
        }
    }

    internal sealed class LocalBackendJob : IDisposable
    {
        private readonly Stack<IEnumerator> stack = new Stack<IEnumerator>();
        private readonly Action<Exception> complete;
        private readonly double deadline;
        private AsyncOperation waiting;
        private bool disposed;
        public bool IsRunning { get { return !disposed; } }

        public LocalBackendJob(IEnumerator routine, Action<Exception> complete)
        {
            this.complete = complete;
            deadline = EditorApplication.timeSinceStartup + 120;
            stack.Push(routine);
            EditorApplication.update += Tick;
            AssemblyReloadEvents.beforeAssemblyReload += Dispose;
        }

        internal void Tick()
        {
            if (disposed) return;
            try
            {
                if (EditorApplication.timeSinceStartup > deadline) throw new TimeoutException("Local check timed out.");
                if (waiting != null && !waiting.isDone) { EditorApplication.QueuePlayerLoopUpdate(); return; }
                waiting = null;
                // Nested coroutines share one request lifetime; cancellation unwinds all using blocks.
                for (int i = 0; i < 100 && stack.Count > 0; i++)
                {
                    var current = stack.Peek();
                    if (!current.MoveNext())
                    {
                        stack.Pop();
                        var disposable = current as IDisposable;
                        if (disposable != null) disposable.Dispose();
                        continue;
                    }
                    var async = current.Current as AsyncOperation;
                    if (async != null) { waiting = async; break; }
                    var nested = current.Current as IEnumerator;
                    if (nested != null) { stack.Push(nested); continue; }
                    if (current.Current != null) throw new InvalidOperationException("Unsupported local editor yield.");
                    break;
                }
                if (stack.Count == 0) Finish(null);
                else EditorApplication.QueuePlayerLoopUpdate();
            }
            catch (Exception error) { Finish(error); }
        }

        private void Finish(Exception error)
        {
            Dispose();
            if (complete != null) complete(error);
        }

        public void Dispose()
        {
            if (disposed) return;
            disposed = true;
            EditorApplication.update -= Tick;
            AssemblyReloadEvents.beforeAssemblyReload -= Dispose;
            while (stack.Count > 0)
            {
                var disposable = stack.Pop() as IDisposable;
                if (disposable != null) disposable.Dispose();
            }
            waiting = null;
        }
    }

    public sealed class LocalBackendWindow : EditorWindow
    {
        private LocalBackendClient client;
        private LocalBackendJob job;
        private Profile profile;
        private string accountName = "editor-a";
        private LocalBackendDraft draft = new LocalBackendDraft();
        private string runId;
        private string status = "未连接";
        private MessageType statusType = MessageType.Info;
        private Vector2 scroll;

        [MenuItem("Tools/Local Backend/联调窗口")]
        public static void Open()
        {
            var window = GetWindow<LocalBackendWindow>("本地联调");
            window.minSize = new Vector2(420, 460);
            window.Show();
        }

        private void OnEnable()
        {
            client = new LocalBackendClient(); draft = new LocalBackendDraft();
            profile = null; runId = null; status = "未连接"; statusType = MessageType.Info;
        }
        private void OnDisable() { if (job != null) job.Dispose(); }

        private bool Busy { get { return job != null && job.IsRunning; } }

        private void OnGUI()
        {
            scroll = EditorGUILayout.BeginScrollView(scroll);
            EditorGUILayout.LabelField("本地测试服务", EditorStyles.boldLabel);
            EditorGUILayout.LabelField("地址", LocalBackendClient.Endpoint);
            EditorGUILayout.HelpBox(status, statusType);
            using (new EditorGUI.DisabledScope(Busy))
            {
                accountName = EditorGUILayout.TextField("测试账号", accountName);
                using (new EditorGUILayout.HorizontalScope())
                {
                    if (GUILayout.Button("连接检查")) Begin(client.Health(r => Report(r, "服务在线")));
                    if (GUILayout.Button("登录") && ConfirmDiscard()) Begin(LoginAndRead());
                    using (new EditorGUI.DisabledScope(!client.IsLoggedIn))
                    {
                        if (GUILayout.Button("退出账号"))
                        {
                            if (ConfirmDiscard())
                            {
                                client.Logout(); profile = null; runId = null; draft = new LocalBackendDraft();
                                status = "已退出测试账号"; statusType = MessageType.Info;
                            }
                        }
                    }
                }
                using (new EditorGUI.DisabledScope(!client.IsLoggedIn))
                {
                    EditorGUILayout.Space();
                    EditorGUILayout.LabelField("服务端存档", EditorStyles.boldLabel);
                    if (profile != null)
                    {
                        EditorGUILayout.LabelField("账号 ID", profile.accountId);
                        EditorGUILayout.LabelField("版本", profile.revision.ToString());
                        EditorGUILayout.LabelField("金币 / 碎片", profile.gold + " / " + profile.fragments);
                        EditorGUILayout.LabelField("总局数 / 撤离 / 死亡", profile.totalRuns + " / " + profile.totalExtracts + " / " + profile.totalDeaths);
                    }
                    EditorGUILayout.LabelField("测试数据 JSON");
                    using (new EditorGUI.DisabledScope(!draft.HasBaseline))
                        draft.Text = EditorGUILayout.TextArea(draft.Text, GUILayout.MinHeight(110));
                    using (new EditorGUILayout.HorizontalScope())
                    {
                        if (GUILayout.Button(EditorGUIUtility.IconContent("Refresh", "读取服务端存档"), GUILayout.Width(32)))
                            Begin(client.ReadProfile(ApplyProfile));
                        using (new EditorGUI.DisabledScope(profile == null))
                        {
                            using (new EditorGUI.DisabledScope(draft.HasConflict))
                                if (GUILayout.Button("保存测试数据")) Begin(client.Save(draft.BaseRevision, draft.Text, ApplySavedProfile));
                            if (draft.HasConflict && GUILayout.Button("采用服务端数据") && ConfirmDiscard())
                            {
                                draft.Reset(profile);
                                status = "已采用服务端数据"; statusType = MessageType.Info;
                            }
                        }
                    }
                    EditorGUILayout.Space();
                    EditorGUILayout.LabelField("模拟结算", EditorStyles.boldLabel);
                    EditorGUILayout.SelectableLabel(runId ?? "无测试对局", GUILayout.Height(20));
                    if (GUILayout.Button("开始测试对局")) Begin(client.StartRun(r =>
                    {
                        if (Report(r, "测试对局已开始")) runId = r.Data.runId;
                    }));
                    using (new EditorGUI.DisabledScope(string.IsNullOrEmpty(runId)))
                    using (new EditorGUILayout.HorizontalScope())
                    {
                        if (GUILayout.Button("模拟撤离")) Begin(client.Settle(runId, "extract", ApplySettlement));
                        if (GUILayout.Button("模拟死亡")) Begin(client.Settle(runId, "death", ApplySettlement));
                    }
                }
            }
            EditorGUILayout.EndScrollView();
            if (Busy) Repaint();
        }

        private IEnumerator LoginAndRead()
        {
            profile = null; runId = null; draft = new LocalBackendDraft();
            yield return client.Login(accountName, r => Report(r, "测试账号已登录"));
            if (client.IsLoggedIn) yield return client.ReadProfile(ApplyProfile);
        }

        private bool Report<T>(ApiResult<T> result, string success) where T : class
        {
            statusType = result.Success ? MessageType.Info : MessageType.Error;
            status = result.Success ? success : result.Status + " " + result.Code + ": " + result.Message;
            if (!client.IsLoggedIn) { profile = null; runId = null; }
            Repaint();
            return result.Success;
        }

        private void ApplyProfile(ApiResult<Profile> result)
        {
            if (!Report(result, "服务端存档已同步")) return;
            if (profile == null) draft.Reset(result.Data);
            else draft.Receive(result.Data);
            profile = result.Data;
            ShowConflict();
        }

        private void ApplySavedProfile(ApiResult<Profile> result)
        {
            if (!Report(result, "测试数据已保存")) return;
            profile = result.Data;
            draft.Reset(profile);
        }

        private void ApplySettlement(ApiResult<SettlementReply> result)
        {
            if (!Report(result, result.Success && result.Data.replayed ? "重复请求：奖励未重复发放" : "模拟结算完成")) return;
            profile = result.Data.profile;
            draft.Receive(profile);
            ShowConflict();
            // Keep the run ID so retry/replay behavior can be exercised explicitly.
        }

        private void ShowConflict()
        {
            if (!draft.HasConflict) return;
            status = "服务端数据已被其他会话修改，本地草稿已保留。";
            statusType = MessageType.Warning;
        }

        private bool ConfirmDiscard()
        {
            return !draft.IsDirty || EditorUtility.DisplayDialog("覆盖本地草稿？", "当前草稿尚未保存。", "继续", "取消");
        }

        private void Begin(IEnumerator routine)
        {
            if (Busy) return;
            status = "请求中"; statusType = MessageType.Info;
            job = new LocalBackendJob(routine, error =>
            {
                if (error != null) { status = error.Message; statusType = MessageType.Error; }
                Repaint();
            });
        }
    }
}
