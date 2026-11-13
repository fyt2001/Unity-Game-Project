// Assets/Editor/HotfixProbe.cs   ← 验收期临时文件，Phase 7 收尾时连同 .meta 一起删除
// 用途：P1-2 等价性验收期间，把热更 CDN 指向本地 http.server，使 GameLaunch.cs:287
//       与 UpdateMgr.cs:73 两道闸门同时通过（默认 RemoteAssetUrl 恒空 ⇒ 链路永不执行）。
// 端口说明：方案书写的 8080 已被本机其它进程占用（PID 24288，根目录不是本探针目录），
//           故改用空闲端口 8123，服务根目录 = C:/Unity_1/design_tmp/hotfix_probe。
//
// 附加能力（等价性验收专用）：HotfixUIProbeRunner 每帧【只读】采样 GameLaunch 的进度 UI，
// 仅在其值发生变化时打一行 [UIProbe]，把「③UI 表现」从无法取样的截图变成可 diff 的文本。
// 采样器不写任何字段、不改任何行为，改前改后同一份 ⇒ 不污染等价性判定。
// 已知取样局限：同帧内连续调用的中间态（如 UpdateMgr.cs:164 SetProgress(1f) → :165 SetDesc
// 「更新中 1/1」，二者与 GameLaunch.cs:294 SetPhase(0.2) 落在同一帧）只能看到该帧的终态；
// 该局限对改前改后完全对称，不影响等价性判定。
using System.Globalization;
using UnityEngine;

public static class HotfixProbe
{
    // 同一个 BeforeSceneLoad 内：先挂日志落盘观察者，再注入 URL 并打印。
    // （两个 BeforeSceneLoad 方法的执行顺序未定义，拆开会导致注入那行漏采。）
    [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.BeforeSceneLoad)]
    static void Probe()
    {
        // 把本次 Play 的 Console 全量落到 p1-2_evidence/<tag>.txt（tag 由 tag.txt 指定）。
        // 纯观察者（不写任何游戏状态），改前改后同一份 ⇒ 不影响等价性；
        // 目的是让「①日志序列」的比对是字节级 diff，而不是手工转录。
        string tag = "run";
        try { tag = System.IO.File.ReadAllText("C:/Unity_1/design_tmp/hotfix_probe/tag.txt").Trim(); }
        catch { }
        var path = "C:/Unity_1/design_tmp/p1-2_evidence/" + tag + ".txt";
        try { System.IO.File.WriteAllText(path, ""); } catch { }
        Application.logMessageReceived += (cond, stack, type) =>
        {
            try { System.IO.File.AppendAllText(path, "[" + type + "] " + cond + "\n"); } catch { }
        };

        HotfixSettings.RemoteAssetUrl = "http://127.0.0.1:8123/";
        Debug.Log("[HotfixProbe] RemoteAssetUrl injected = " + HotfixSettings.RemoteAssetUrl);
    }

    [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
    static void ProbeUI()
    {
        var go = new GameObject("HotfixUIProbe");
        go.hideFlags = HideFlags.HideAndDontSave;
        Object.DontDestroyOnLoad(go);
        go.AddComponent<HotfixUIProbeRunner>();
    }
}

public class HotfixUIProbeRunner : MonoBehaviour
{
    float _lastV = float.NaN;
    string _lastT = null;
    bool _none;

    void Update()
    {
        var gl = GameLaunch.Instance;
        if (gl == null) return;

        var sl = gl.ProgressSlider;   // UnityEngine.Object 重载 == ，销毁后 == null
        if (sl == null)
        {
            if (!_none)
            {
                _none = true;
                Debug.Log("[UIProbe] slider=<none> text=" + (_lastT ?? "<null>"));
            }
            return;
        }
        _none = false;

        float v = sl.value;
        string t = ReadText(gl);
        if (v != _lastV || t != _lastT)
        {
            _lastV = v; _lastT = t;
            Debug.Log(string.Format(CultureInfo.InvariantCulture,
                "[UIProbe] slider={0} text={1}",
                v.ToString("0.#####", CultureInfo.InvariantCulture), t ?? "<null>"));
        }
    }

    // ProgressText 为 null 时 GameLaunch 会退到私有字段 _progressTMP（GameLaunch.cs:162-163），
    // 这里反射【只读】它，保证「文案」这一维不漏采。
    static string ReadText(GameLaunch gl)
    {
        if (gl.ProgressText != null) return gl.ProgressText.text;
        var f = typeof(GameLaunch).GetField("_progressTMP",
            System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
        var tmp = f != null ? f.GetValue(gl) : null;
        if (tmp == null) return null;
        var p = tmp.GetType().GetProperty("text");
        return p != null ? p.GetValue(tmp, null) as string : null;
    }
}
