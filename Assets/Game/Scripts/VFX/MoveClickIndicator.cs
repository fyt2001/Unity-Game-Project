// =============================================================================
// MoveClickIndicator.cs
// =============================================================================
// 右键移动的地表指令标记（英雄联盟式）。
//
// 组成三部分，全部程序化生成网格，零美术资源依赖：
//   1. Ring  地面软边光环：缓慢旋转 + 呼吸。光环做了 4 段角度调制，
//      否则纯圆环旋转起来看不出任何变化（视觉上等于没转）
//   2. Arrow 指向地面的立体光楔：顶点在高处向地面张开，俯视呈箭头/菱形，
//      缓慢上下浮动 + 反向自转
//   3. Burst 点击瞬间的扩散波：快速放大并淡出，给出「指令已下达」的反馈
//
// 生命周期：
//   Ping(pos)  出现 / 下达新指令（触发扩散波）
//   MoveTo(pos) 仅更新位置并保持显示（每帧调用不会重复触发扩散波）
//   Hide()     淡出并停用（到达目的地或指令被取消时）
//
// 性能：网格为静态缓存，同场景只构建一次；材质实例在 OnDestroy 释放。
// =============================================================================

using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

[AddComponentMenu("Game/VFX/MoveClickIndicator")]
public class MoveClickIndicator : MonoBehaviour
{
    [Header("Visual")]
    [Tooltip("标记颜色（默认：英雄联盟风格的青绿）")]
    public Color color = new Color(0.27f, 0.95f, 0.63f, 1f);

    [Tooltip("贴地高度：避免与地面 Z-Fighting")]
    public float groundY = 0.06f;

    [Tooltip("外环半径（世界单位）")]
    public float ringRadius = 1.3f;

    [Tooltip("箭头大小缩放")]
    public float arrowScale = 1f;

    [Header("Animation")]
    public float ringSpinSpeed = 45f;
    public float pulseSpeed = 4f;
    public float bobSpeed = 3f;
    public float bobHeight = 0.22f;
    public float burstDuration = 0.45f;
    public float fadeDuration = 0.2f;

    private Mesh _ringMesh;
    private Mesh _arrowMesh;

    private Transform _ring;
    private Transform _arrow;
    private Transform _burst;
    private Material _ringMat;
    private Material _arrowMat;
    private Material _burstMat;

    private bool _visible;
    private float _opacity;      // 全局淡入淡出系数 0~1
    private float _burstTime;
    private float _clock;

    // ---------------------------------------------------------------------
    // 构建
    // ---------------------------------------------------------------------
    public static MoveClickIndicator Create(Transform parent)
    {
        var go = new GameObject("MoveClickIndicator");
        if (parent != null) go.transform.SetParent(parent, false);

        var indicator = go.AddComponent<MoveClickIndicator>();
        indicator.Build();
        indicator.gameObject.SetActive(false);
        return indicator;
    }

    private void Build()
    {
        // 网格按实例生成：场景里通常只有一个标记，实例级创建可在 OnDestroy 干净释放，
        // 避免 Editor 下「新建 Mesh/Material 未销毁」的泄漏警告（静态缓存无法保证释放时机）。
        _ringMesh = BuildRingMesh(64);
        _arrowMesh = BuildArrowMesh(4);

        _ring = CreatePart("Ring", _ringMesh, out _ringMat);
        _arrow = CreatePart("Arrow", _arrowMesh, out _arrowMat);
        _burst = CreatePart("Burst", _ringMesh, out _burstMat);

        _ring.localScale = Vector3.one * ringRadius;
        _arrow.localScale = Vector3.one * arrowScale;
        _burst.gameObject.SetActive(false);
    }

    private Transform CreatePart(string name, Mesh mesh, out Material mat)
    {
        var go = new GameObject(name);
        go.transform.SetParent(transform, false);

        var mf = go.AddComponent<MeshFilter>();
        mf.sharedMesh = mesh;

        mat = CreateMaterial();
        var mr = go.AddComponent<MeshRenderer>();
        mr.material = mat;
        mr.shadowCastingMode = ShadowCastingMode.Off;
        mr.receiveShadows = false;
        mr.lightProbeUsage = LightProbeUsage.Off;

        return go.transform;
    }

    private Material CreateMaterial()
    {
        var shader = Shader.Find("Game/MoveIndicator");
        if (shader == null)
        {
            Debug.LogError("[MoveClickIndicator] 找不到 Shader 'Game/MoveIndicator'，请确认 Assets/Resources/MoveIndicator.shader 存在");
            return null;
        }

        var mat = new Material(shader)
        {
            hideFlags = HideFlags.HideAndDontSave
        };
        mat.SetColor("_TintColor", color);
        mat.SetFloat("_Opacity", 0f);
        return mat;
    }

    // ---------------------------------------------------------------------
    // 对外 API
    // ---------------------------------------------------------------------
    /// <summary>下达新移动指令：移动到该点并播放一次扩散波。</summary>
    public void Ping(Vector3 worldPos)
    {
        MoveTo(worldPos);
        _burstTime = 0f;
        if (_burst != null) _burst.gameObject.SetActive(true);
    }

    /// <summary>仅移动标记位置并保持显示（不重置动画、不重复播放扩散波）。</summary>
    public void MoveTo(Vector3 worldPos)
    {
        var p = worldPos;
        p.y = groundY;
        transform.position = p;

        bool wasHidden = !_visible || !gameObject.activeSelf;
        _visible = true;

        if (!gameObject.activeSelf)
        {
            gameObject.SetActive(true);
            _opacity = 0f;      // 淡入
        }

        if (wasHidden) _clock = 0f;
    }

    /// <summary>隐藏（淡出）标记。到达目的地或被取消时调用。</summary>
    public void Hide()
    {
        _visible = false;
    }

    // ---------------------------------------------------------------------
    // 每帧动画
    // ---------------------------------------------------------------------
    void Update()
    {
        if (_ringMat == null) return;

        float targetOpacity = _visible ? 1f : 0f;
        _opacity = Mathf.MoveTowards(_opacity, targetOpacity, Time.deltaTime / Mathf.Max(0.0001f, fadeDuration));

        if (!_visible && _opacity <= 0.0001f)
        {
            if (gameObject.activeSelf) gameObject.SetActive(false);
            return;
        }

        _clock += Time.deltaTime;

        // ---- 地面光环：旋转 + 呼吸 ----
        _ring.localRotation = Quaternion.Euler(0f, _clock * ringSpinSpeed, 0f);
        _ring.localScale = Vector3.one * ringRadius;
        float pulse = 0.78f + 0.22f * Mathf.Sin(_clock * pulseSpeed);
        ApplyOpacity(_ringMat, 0.9f * pulse);

        // ---- 指向地面的光楔 ----
        float bob = 0.5f * (1f + Mathf.Sin(_clock * bobSpeed)) * bobHeight;
        _arrow.localPosition = new Vector3(0f, bob, 0f);
        _arrow.localRotation = Quaternion.Euler(0f, -_clock * ringSpinSpeed * 1.6f, 0f);
        _arrow.localScale = Vector3.one * arrowScale;
        ApplyOpacity(_arrowMat, 0.5f + 0.5f * pulse);

        // ---- 点击扩散波 ----
        if (_burstTime < burstDuration)
        {
            _burstTime += Time.deltaTime;
            float k = Mathf.Clamp01(_burstTime / burstDuration);
            float s = Mathf.Lerp(0.45f, 2.1f, k) * ringRadius;
            _burst.localScale = new Vector3(s, 1f, s);
            ApplyOpacity(_burstMat, (1f - k) * 0.85f);
        }
        else if (_burst.gameObject.activeSelf)
        {
            _burst.gameObject.SetActive(false);
        }
    }

    private void ApplyOpacity(Material mat, float local)
    {
        if (mat == null) return;
        mat.SetFloat("_Opacity", local * _opacity);
    }

    void OnDestroy()
    {
        DestroyMaterial(_ringMat);
        DestroyMaterial(_arrowMat);
        DestroyMaterial(_burstMat);
        DestroyMesh(_ringMesh);
        DestroyMesh(_arrowMesh);
    }

    private static void DestroyMaterial(Material mat)
    {
        if (mat == null) return;
        if (Application.isPlaying) Destroy(mat);
        else DestroyImmediate(mat);
    }

    private static void DestroyMesh(Mesh mesh)
    {
        if (mesh == null) return;
        if (Application.isPlaying) Destroy(mesh);
        else DestroyImmediate(mesh);
    }

    // ---------------------------------------------------------------------
    // 程序化网格
    // ---------------------------------------------------------------------
    /// <summary>
    /// 水平圆环（构建在 XZ 平面）。软边与旋转可见性都由顶点色承担：
    ///   - 径向：外侧 -> 亮环 -> 内侧，两端 alpha 淡出成柔和光带
    ///   - 角度：4 段亮暗调制，否则完美对称的圆」转起来肉眼完全看不出
    /// </summary>
    private static Mesh BuildRingMesh(int segments)
    {
        float[] radii = { 0.55f, 0.78f, 0.94f, 1.15f };
        float[] alphas = { 0.00f, 1.00f, 1.00f, 0.00f };

        var verts = new List<Vector3>((segments + 1) * radii.Length);
        var cols = new List<Color>((segments + 1) * radii.Length);
        var norms = new List<Vector3>((segments + 1) * radii.Length);
        var idx = new List<int>(segments * (radii.Length - 1) * 6);

        for (int s = 0; s <= segments; s++)
        {
            float ang = (float)s / segments * Mathf.PI * 2f;
            float cos = Mathf.Cos(ang);
            float sin = Mathf.Sin(ang);

            // 角度调制（4 段）-> 旋转时可见
            float angPulse = Mathf.Clamp01(0.45f + 0.55f * Mathf.Abs(Mathf.Cos(ang * 2f)));

            for (int r = 0; r < radii.Length; r++)
            {
                verts.Add(new Vector3(cos * radii[r], 0f, sin * radii[r]));
                norms.Add(Vector3.up);
                cols.Add(new Color(1f, 1f, 1f, alphas[r] * angPulse));
            }
        }

        int stride = radii.Length;
        for (int s = 0; s < segments; s++)
        {
            for (int r = 0; r < radii.Length - 1; r++)
            {
                int a = s * stride + r;
                int b = a + 1;
                int c = (s + 1) * stride + r;
                int d = c + 1;

                idx.Add(a); idx.Add(c); idx.Add(b);
                idx.Add(b); idx.Add(c); idx.Add(d);
            }
        }

        return FinishMesh(verts, cols, norms, idx, "MoveIndicator_Ring");
    }

    /// <summary>
    /// 指向地面的立体光楔：顶点在高处，向水平面张开成多棱锥。
    /// 俯视是一枚指向中心的箭头/菱形，侧看是从天指向地面的能量漏斗。
    /// </summary>
    private static Mesh BuildArrowMesh(int sides)
    {
        const float apexHeight = 1.25f;
        const float baseRadius = 0.42f;
        const float baseAlpha = 0.12f;

        var verts = new List<Vector3>(sides * 2 + 1);
        var cols = new List<Color>(sides * 2 + 1);
        var idx = new List<int>(sides * 3);

        // 顶点：最亮
        verts.Add(new Vector3(0f, apexHeight, 0f));
        cols.Add(new Color(1f, 1f, 1f, 0.95f));
        const int apexIndex = 0;

        for (int s = 0; s < sides; s++)
        {
            float a0 = (float)s / sides * Mathf.PI * 2f;
            float a1 = (float)(s + 1) / sides * Mathf.PI * 2f;

            int i0 = verts.Count;
            verts.Add(new Vector3(Mathf.Cos(a0) * baseRadius, 0f, Mathf.Sin(a0) * baseRadius));
            cols.Add(new Color(1f, 1f, 1f, baseAlpha));

            int i1 = verts.Count;
            verts.Add(new Vector3(Mathf.Cos(a1) * baseRadius, 0f, Mathf.Sin(a1) * baseRadius));
            cols.Add(new Color(1f, 1f, 1f, baseAlpha));

            idx.Add(apexIndex); idx.Add(i0); idx.Add(i1);
        }

        return FinishMesh(verts, cols, null, idx, "MoveIndicator_Arrow");
    }

    private static Mesh FinishMesh(List<Vector3> verts, List<Color> cols, List<Vector3> norms, List<int> idx, string name)
    {
        var mesh = new Mesh { name = name };
        mesh.SetVertices(verts);
        mesh.SetColors(cols);
        if (norms != null) mesh.SetNormals(norms);
        mesh.SetTriangles(idx, 0);
        mesh.hideFlags = HideFlags.HideAndDontSave;
        mesh.RecalculateBounds();
        return mesh;
    }
}
