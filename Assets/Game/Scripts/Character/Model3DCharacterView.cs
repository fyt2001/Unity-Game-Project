using UnityEngine;
using System.Collections;
using XLua;   // LuaCallCSharp 特性在 XLua 命名空间下

/// <summary>
/// 3D 角色视图：对齐项目 Spine 角色封装约定的 3D 实现。
/// <para>统一状态词表见 CharacterState（Stand / Stop / Click / Special01 / 02 / Open / KongBai / ChuChang）。</para>
/// <para>有 modelPrefab 时实例化真实模型并按包围盒自动缩放居中；否则退回程序化占位体（原 PlaceholderCharacter 行为）。</para>
/// <para>播放优先级：若模型自带 AnimatorController 且含同名状态 → 用 Animator 播放；否则回退到程序化表现（静态模型也能演示状态）。</para>
/// </summary>
// Lua 战斗层需要调用 FlashHurt（受伤表现），必须和其它供 Lua 调用的 C#
// 一样打上标记让 XLua 生成 wrap code；否则 Lua 侧走反射，IL2CPP 下会被裁剪。
[LuaCallCSharp]
public class Model3DCharacterView : CharacterView
{
    [Header("真实模型")] public GameObject modelPrefab;
    public float modelTargetHeight = 2f;

    [Tooltip("用骨骼自动定向：head 在 hips 上方 = up，左右肩连线 = right。改了导入设置导致姿态变化时也不用手工调欧拉角。")]
    public bool autoOrientFromBones = true;
    [Tooltip("骨骼不可用时的回退方案：把包围盒最长的轴旋转到 +Y 立起来。")]
    public bool autoUpright = true;
    [Tooltip("自动立起后如果头朝下（倒立），勾选此项翻转上下。")]
    public bool flipUpright = false;
    [Tooltip("自动把模型的正面转到 +Z。用左右肩骨骼推算朝向，移动时才会正对前进方向。")]
    public bool autoFaceForward = true;
    [Tooltip("自动朝向后如果人物是背对的，勾选此项翻转 180 度。")]
    public bool flipForward = false;
    [Tooltip("在自动朝向基础上再手动微调（度）。")]
    public float modelYaw = 0f;
    [Tooltip("手动欧拉角（关闭 autoUpright 时生效）。")]
    public Vector3 modelRotation = Vector3.zero;

    [Header("占位外观（无模型时生效）")]
    public Color bodyColor = new Color(0.2f, 0.8f, 0.9f);
    public Color headColor = new Color(1f, 0.85f, 0.3f);

    [Header("环境动画")]
    public float bobSpeed = 2f;
    public float bobHeight = 0.15f;
    public float spinSpeed = 25f;
    public bool animate = true;

    [Header("程序化骨骼动画（模型没有动画片段时生效）")]
    [Tooltip("直接驱动骨骼做走路循环。Spike 有骨架但 FBX 里没有动画曲线，靠这个让手脚动起来。")]
    public bool proceduralBones = true;
    public float walkCycleSpeed = 9f;
    public float legSwingAngle = 28f;
    public float kneeBendAngle = 30f;
    public float armSwingAngle = 24f;

    [Header("Q 版夸张（大头短腿卡通用）")]
    [Tooltip("开启：身体上下弹跳 + 左右摇摆 + 前倾。Q 版走路的精髓就是夸张。")]
    public bool chibiStyle = true;
    [Tooltip("每迈一步身体上下弹跳的高度")]
    public float walkBounce = 0.15f;
    [Tooltip("身体左右摇摆角度（度），Q 版重心会左右晃")]
    public float walkSway = 7f;
    [Tooltip("身体前倾角（度）")]
    public float walkLean = 6f;

    [Tooltip("自动计算摆动轴：取角色的「左右方向」在各骨骼自身局部空间的表示，保证手脚是前后摆而不是横着劈叉。")]
    public bool autoSwingAxis = true;
    [Tooltip("手动摆动轴（autoSwingAxis 关闭或找不到骨骼时生效）。")]
    public Vector3 swingAxis = new Vector3(1f, 0f, 0f);

    [Header("动画（留空则用程序化骨骼动画）")]
    [Tooltip("AnimatorController。状态名必须与 CharacterState 一致（Walk / Stand）。有它就播真动画，没有就回退到程序化摆手摆腿。")]
    public RuntimeAnimatorController animatorController;
    [Tooltip("模型 Avatar。Humanoid 重定向必填 —— 从 spike.fbx 生成的那个 Avatar 拖进来。")]
    public Avatar avatar;

    [Header("实体武器（战斗表现，伤害由 Lua 结算）")]
    public WeaponVisualDefinition swordWeapon;
    public WeaponVisualDefinition pistolWeapon;
    private CharacterWeaponView _combatWeapons;

    private GameObject _modelInstance;

    [Header("网格过滤")]
    [Tooltip("按名字隐藏网格，逗号分隔（不区分大小写）。Spike 的 FBX 里 ammo_GEO 是弹药网格，和角色打包在同一个文件、摆在角色旁边，默认隐藏。")]
    public string hideMeshes = "ammo_GEO";

    [Header("材质修正（Blender FBX 常把漫反射导出成黑色，导致模型发暗）")]
    [Tooltip("开启后把模型材质的漫反射底色强制成白色，并可选替换贴图 / 整个材质。")]
    public bool fixDarkMaterial = true;
    [Tooltip("整个材质覆盖（留空则只改底色和贴图）。")]
    public Material materialOverride;
    [Tooltip("漫反射贴图覆盖（留空则保留模型自带贴图）。")]
    public Texture albedoOverride;
    [Tooltip("漫反射底色。Standard 材质里 _Color 会乘以贴图，底色是黑的话贴图再亮也是黑的。")]
    public Color albedoTint = Color.white;

    private Transform _root;
    private float _baseY;
    private bool _built;
    private Animator _animator;
    private CharacterState _current = CharacterState.Stand;

    [Header("受击反馈")]
    public Color hurtColor = new Color(1f, 0.35f, 0.35f);
    public float hurtFlashTime = 0.15f;
    public float hurtPunchScale = 1.15f;

    private Renderer[] _hurtRenderers;
    private Color[] _hurtOriginalColors;
    private float _hurtTimer;
    private bool _hurtCached;
    private Vector3 _rootBaseScale = Vector3.one;
    private Coroutine _oneShot;

    private BoneRef _upperLegL, _lowerLegL, _upperLegR, _lowerLegR, _armL, _armR;
    private bool _hasBones;

    // 左右骨骼判定：同时兼容前缀（l_/left/r_/right，Mixamo/BrawlStars）与后缀（.l/.r/_l/_r，Quaternius）。
    private static bool IsLeftBone(string n)
    {
        return n.StartsWith("l_") || n.StartsWith("left")
            || n.EndsWith(".l") || n.EndsWith("_l") || n.EndsWith("left");
    }
    private static bool IsRightBone(string n)
    {
        return n.StartsWith("r_") || n.StartsWith("right")
            || n.EndsWith(".r") || n.EndsWith("_r") || n.EndsWith("right");
    }

    private void Awake() { Build(); }

    // ===== 受击反馈（Lua 战斗层的 DamageSystem 调用 FlashHurt）=====
    // 与 enemy 的 Lua 组件不同，本类是 C# MonoBehaviour，自带 Update，
    // 所以闪红计时器在这里自行恢复，不需要逻辑层喂 dt。

    /// <summary>受伤表现：瞬间染红 + 缩放脉冲，hurtFlashTime 秒后自动恢复。</summary>
    public void FlashHurt()
    {
        CacheHurtAssets();
        _hurtTimer = hurtFlashTime;

        if (_hurtRenderers != null)
        {
            for (int i = 0; i < _hurtRenderers.Length; i++)
            {
                var mat = _hurtRenderers[i] != null ? _hurtRenderers[i].material : null;
                if (mat != null) mat.color = hurtColor;
            }
        }
        ApplyHurtPunch(hurtPunchScale);
    }

    /// <summary>首次调用时收集 Renderer 与原始颜色：Build() 之后模型才存在。</summary>
    private void CacheHurtAssets()
    {
        if (_hurtCached) return;
        _hurtCached = true;
        if (_root == null) return;

        _rootBaseScale = _root.localScale;
        _hurtRenderers = _root.GetComponentsInChildren<Renderer>(true);
        if (_hurtRenderers == null) return;

        _hurtOriginalColors = new Color[_hurtRenderers.Length];
        for (int i = 0; i < _hurtRenderers.Length; i++)
        {
            var mat = _hurtRenderers[i] != null ? _hurtRenderers[i].material : null;
            _hurtOriginalColors[i] = mat != null ? mat.color : Color.white;
        }
    }

    private void UpdateHurtFlash()
    {
        if (_hurtTimer <= 0f) return;
        _hurtTimer -= Time.deltaTime;
        if (_hurtTimer > 0f) return;

        if (_hurtRenderers != null)
        {
            for (int i = 0; i < _hurtRenderers.Length; i++)
            {
                var mat = _hurtRenderers[i] != null ? _hurtRenderers[i].material : null;
                if (mat != null) mat.color = _hurtOriginalColors[i];
            }
        }
        ApplyHurtPunch(1f);
    }

    private void ApplyHurtPunch(float s)
    {
        if (_root != null) _root.localScale = _rootBaseScale * s;
    }

    private void Build()
    {
        if (_built) return;
        _built = true;

        _root = new GameObject("Model").transform;
        _root.SetParent(transform, false);
        _root.gameObject.layer = gameObject.layer;

        if (modelPrefab != null) BuildRealModel();
        else BuildPlaceholder();

        SetupAnimator();
        _baseY = transform.position.y;
    }

    /// <summary>
    /// 挂载 Animator：优先用预制体/场景里已有的，没有且指定了 controller 就自动加一个。
    /// 有 controller → 播真动画（Mixamo 重定向）；没有 → 回退到程序化骨骼动画。
    /// </summary>
    private void SetupAnimator()
    {
        _animator = GetComponent<Animator>();
        if (_animator == null) _animator = _root.GetComponentInChildren<Animator>(true);

        if (_animator == null && _modelInstance != null)
            _animator = _modelInstance.AddComponent<Animator>();

        if (_animator == null) return;

        // 位移由 Lua 战斗系统驱动，动画不能抢走根节点移动
        _animator.applyRootMotion = false;

        // controller / avatar 不在 Awake 阶段绑定：此时 prefab 上的跨资产引用（AnimatorController）
        // 可能尚未加载完成，直接赋值会得到 null。改由 EnsureAnimatorBinding 在后续帧兜底绑定。
    }

    /// <summary>
    /// 延迟绑定 AnimatorController 与 Avatar。Awake 阶段 prefab 上的跨资产引用可能尚未就绪，
    /// 故在此兜底：一旦资产加载完成即生效（见 Update 中调用）。
    /// </summary>
    private bool _animatorBound = false;
    private void EnsureAnimatorBinding()
    {
        if (_animatorBound || _animator == null) return;
        // 注意：Awake/早期帧里 prefab 上的跨资产引用可能是「假 null」——底层资产尚未加载，
        // 但 UnityEngine.Object 引用本身存在。直接用 == / != 会被自定义 null 判断误判而漏绑。
        // 用 ReferenceEquals 判断引用是否真实存在，存在则赋值（赋值即触发资产加载）。
        if (!System.Object.ReferenceEquals(animatorController, null) && _animator.runtimeAnimatorController == null)
            _animator.runtimeAnimatorController = animatorController;
        if (!System.Object.ReferenceEquals(avatar, null) && _animator.avatar == null)
            _animator.avatar = avatar;
        if (!System.Object.ReferenceEquals(_animator.runtimeAnimatorController, null))
            _animatorBound = true;
    }

    private void BuildRealModel()
    {
        var inst = Instantiate(modelPrefab);
        inst.name = "RealModel";
        inst.transform.SetParent(_root, false);
        inst.transform.localPosition = Vector3.zero;
        inst.transform.localRotation = Quaternion.identity;
        SetLayerRecursively(inst, gameObject.layer);
        ApplyMeshFilter(inst);
        ApplyMaterialFix(inst);

        // 保留 FBX 导入缩放，避免手动改成 1 而把模型尺寸弄错
        var baseScale = inst.transform.localScale;

        // 1) 计算朝向：优先用骨骼（最可靠），否则回退到包围盒最长轴
        Quaternion finalRot;
        if (autoOrientFromBones && TryComputeBoneOrientation(inst, out var boneRot))
        {
            finalRot = Quaternion.Euler(0f, modelYaw + (flipForward ? 180f : 0f), 0f) * boneRot;
        }
        else
        {
            var pre = ComputeLocalBounds(inst);
            int upAxis = IndexOfMax(pre.size);

            Quaternion upright;
            if (autoUpright && pre.size[upAxis] > 0f)
            {
                Vector3 src = upAxis == 0 ? Vector3.right : (upAxis == 1 ? Vector3.up : Vector3.forward);
                if (flipUpright) src = -src;
                upright = Quaternion.FromToRotation(src, Vector3.up);
            }
            else
            {
                upright = Quaternion.Euler(modelRotation);
            }

            // 先只立起来（不带 yaw），这样骨骼世界位置才是「站立姿态」，才能推算正面朝向
            inst.transform.localRotation = upright;

            float yaw = modelYaw;
            if (autoFaceForward)
                yaw += ComputeForwardYaw(inst) + (flipForward ? 180f : 0f);

            finalRot = Quaternion.Euler(0f, yaw, 0f) * upright;
        }

        inst.transform.localRotation = finalRot;

        // 3) 旋转后重新量包围盒，据此缩放 + 落地居中
        //    注意：必须用「_root 局部空间」的包围盒。原来用世界包围盒赋给 localPosition，
        //    父节点一旦不在原点（登录角色 0,3,4 / 玩家世界坐标）就会把模型推离地面。
        var b = ComputeLocalBounds(inst);
        var s = modelTargetHeight / Mathf.Max(b.size.y, 0.0001f);
        inst.transform.localScale = baseScale * s;
        inst.transform.localPosition = new Vector3(-b.center.x * s, -b.min.y * s, -b.center.z * s);

        CacheBones(inst);
        _modelInstance = inst;
    }

    /// <summary>
    /// 用骨骼自动定向，一次同时解决「站立」和「朝向」：
    /// up      = head - hips（头在髋骨上方，就是角色的上方向）
    /// right   = R肩 - L肩（正交化到与 up 垂直）
    /// forward = right × up
    /// 返回让模型 up→+Y、forward→+Z 的旋转。骨骼不全时返回 false。
    /// </summary>
    private bool TryComputeBoneOrientation(GameObject inst, out Quaternion rot)
    {
        rot = Quaternion.identity;

        Transform hips = null, head = null, l = null, r = null;
        foreach (var tr in inst.GetComponentsInChildren<Transform>(true))
        {
            string n = tr.name.ToLowerInvariant();
            if (n.Contains("geo") || n.EndsWith("end")) continue;

            if (hips == null && n.Contains("hips")) hips = tr;
            if (head == null && (n.Contains("head") || n.Contains("neck"))) head = tr;

            bool isL = IsLeftBone(n);
            bool isR = IsRightBone(n);
            if ((isL || isR) && (n.Contains("shoulder") || n.Contains("clavicle")))
            {
                if (isL && l == null) l = tr;
                else if (isR && r == null) r = tr;
            }
        }

        if (hips == null || head == null || l == null || r == null) return false;

        // 换算到 _root 局部空间，抵消父节点旋转/位移的影响
        Vector3 up = _root.InverseTransformDirection(head.position - hips.position);
        if (up.sqrMagnitude < 1e-10f) return false;
        up.Normalize();

        Vector3 right = _root.InverseTransformDirection(r.position - l.position);
        right -= Vector3.Dot(right, up) * up;          // 正交化，去掉 up 方向上的分量
        if (right.sqrMagnitude < 1e-10f) return false;
        right.Normalize();

        Vector3 forward = Vector3.Cross(right, up);    // forward = right × up
        if (forward.sqrMagnitude < 1e-10f) return false;
        forward.Normalize();

        // LookRotation(f, u) 把本地 +Z 转到 f、+Y 转到 u；
        // 我们要的是反过来（模型自身的 f→+Z、u→+Y），所以取逆
        rot = Quaternion.Inverse(Quaternion.LookRotation(forward, up));
        return true;
    }

    /// <summary>
    /// 用左右骨骼的不对称性推算角色正面朝向，返回把它转到 +Z 所需的 yaw 角（度）。
    /// 右方向 = R肩 - L肩；正面 forward = right × up；再把 forward 旋到 +Z。
    /// </summary>
    private float ComputeForwardYaw(GameObject inst)
    {
        // 分组查找，避免把「肩」和「大腿」混在一起算方向
        string[][] groups = { new[] { "shoulder", "clavicle" }, new[] { "upperleg" } };
        Transform l = null, r = null;

        foreach (var g in groups)
        {
            l = null;
            r = null;
            foreach (var tr in inst.GetComponentsInChildren<Transform>(true))
            {
                string n = tr.name.ToLowerInvariant();
                if (n.Contains("geo") || n.EndsWith("end")) continue;

                bool isL = IsLeftBone(n);
                bool isR = IsRightBone(n);
                if (!isL && !isR) continue;
                if (!(n.Contains(g[0]) || n.Contains(g[1]))) continue;

                if (isL && l == null) l = tr;
                else if (isR && r == null) r = tr;
            }
            if (l != null && r != null) break;
        }

        if (l == null || r == null) return 0f;

        // 世界方向 -> _root 局部方向（抵消父节点旋转，只关心模型自身朝向）
        Vector3 rightLocal = _root.InverseTransformDirection(r.position - l.position);
        rightLocal.y = 0f;
        if (rightLocal.sqrMagnitude < 1e-8f) return 0f;
        rightLocal.Normalize();

        Vector3 forward = Vector3.Cross(rightLocal, Vector3.up);   // forward = right × up
        forward.y = 0f;
        if (forward.sqrMagnitude < 1e-8f) return 0f;
        forward.Normalize();

        // 绕 Y 旋转会把 (x,z) 的方位角 atan2(x,z) 直接加上 yaw，转到 0 即 +Z
        return -Mathf.Atan2(forward.x, forward.z) * Mathf.Rad2Deg;
    }

    /// <summary>按名字找到腿/手臂骨骼并记下绑定姿态，供程序化走路循环驱动。</summary>
    private void CacheBones(GameObject inst)
    {
        Transform sideL = null, sideR = null;

        foreach (var tr in inst.GetComponentsInChildren<Transform>(true))
        {
            string n = tr.name.ToLowerInvariant();
            if (n.Contains("geo") || n.EndsWith("end")) continue;   // 跳过网格节点和末端辅助骨

            bool left = IsLeftBone(n);
            bool right = IsRightBone(n);
            if (!left && !right) continue;

            if (n.Contains("upperleg"))
            {
                if (left) _upperLegL = new BoneRef(tr); else _upperLegR = new BoneRef(tr);
            }
            else if (n.Contains("lowerleg"))
            {
                if (left) _lowerLegL = new BoneRef(tr); else _lowerLegR = new BoneRef(tr);
            }
            else if (n.Contains("shoulder") || n.Contains("upperarm"))
            {
                if (left) { _armL = new BoneRef(tr); if (sideL == null) sideL = tr; }
                else { _armR = new BoneRef(tr); if (sideR == null) sideR = tr; }
            }
        }

        _hasBones = _upperLegL != null || _upperLegR != null || _armL != null || _armR != null;

        // 没有肩膀就退化用大腿来定左右方向
        if (sideL == null && _upperLegL != null) sideL = _upperLegL.t;
        if (sideR == null && _upperLegR != null) sideR = _upperLegR.t;

        ApplySwingAxes(sideL, sideR);
    }

    /// <summary>
    /// 计算每根骨骼的摆动轴 = 角色「左右方向」在该骨骼自身局部空间的表示。
    /// 绕这个轴旋转，肢体就在矢状面（前后）内摆动；
    /// 写死世界轴则会因为各绑定（Blender / Mixamo / 3dsMax）骨骼局部轴朝向不同而变成横着劈叉。
    /// </summary>
    private void ApplySwingAxes(Transform sideL, Transform sideR)
    {
        bool auto = autoSwingAxis && sideL != null && sideR != null;
        Vector3 worldRight = Vector3.right;

        if (auto)
        {
            worldRight = sideR.position - sideL.position;
            worldRight.y = 0f;                                  // 保持摆动平面竖直
            if (worldRight.sqrMagnitude > 1e-8f) worldRight.Normalize();
            else { worldRight = Vector3.right; auto = false; }
        }

        var all = new[] { _upperLegL, _lowerLegL, _upperLegR, _lowerLegR, _armL, _armR };
        foreach (var b in all)
        {
            if (b == null) continue;
            b.swingAxis = auto ? b.t.InverseTransformDirection(worldRight).normalized : swingAxis;
        }
    }

    private class BoneRef
    {
        public Transform t;
        public Quaternion bindRot;
        public Vector3 swingAxis;
        public BoneRef(Transform t) { this.t = t; bindRot = t.localRotation; }
    }

    /// <summary>
    /// 按名字隐藏多余网格。荒野乱斗的模型常把弹药（ammo_GEO）和角色打包在同一个 FBX，
    /// 绑定姿态下它就飘在角色旁边，不属于角色本体，需要隐藏。
    /// </summary>
    private void ApplyMeshFilter(GameObject inst)
    {
        if (string.IsNullOrEmpty(hideMeshes)) return;

        var keys = hideMeshes.Split(',');
        foreach (var rend in inst.GetComponentsInChildren<Renderer>(true))
        {
            var name = rend.name.ToLowerInvariant();
            foreach (var raw in keys)
            {
                var key = raw.Trim().ToLowerInvariant();
                if (key.Length > 0 && name.Contains(key))
                {
                    rend.enabled = false;
                    break;
                }
            }
        }
    }

    /// <summary>
    /// 修正发暗的材质：Blender 的节点材质导不进 FBX，Unity 读到的漫反射底色接近黑色，
    /// 而 Standard 的 _Color 是乘以贴图的，结果就是贴图再亮模型也是黑的。
    /// 这里把底色刷成白色，并可按需替换贴图 / 整个材质。
    /// </summary>
    private void ApplyMaterialFix(GameObject inst)
    {
        if (!fixDarkMaterial) return;

        foreach (var rend in inst.GetComponentsInChildren<Renderer>(true))
        {
            if (materialOverride != null)
            {
                // 用 sharedMaterials 直接替换，不产生运行时材质副本
                var shared = new Material[rend.sharedMaterials.Length];
                for (int i = 0; i < shared.Length; i++) shared[i] = materialOverride;
                rend.sharedMaterials = shared;
                continue;
            }

            var mats = rend.materials;              // 取副本，避免改到共享资源
            for (int i = 0; i < mats.Length; i++)
            {
                var m = mats[i];
                if (m == null) continue;

                if (albedoOverride != null) m.SetTexture("_MainTex", albedoOverride);
                m.color = albedoTint;
            }
            rend.materials = mats;
        }
    }

    /// <summary>把模型所有 Renderer 的世界包围盒 8 个角换算到 _root 局部空间，得到局部 AABB。</summary>
    private Bounds ComputeLocalBounds(GameObject inst)
    {
        var renderers = inst.GetComponentsInChildren<Renderer>();
        var result = new Bounds();
        bool init = false;
        foreach (var r in renderers)
        {
            var wb = r.bounds;              // 世界空间 AABB（含父节点位移）
            var c = wb.center;
            var e = wb.extents;
            for (int i = 0; i < 8; i++)
            {
                var corner = new Vector3(
                    c.x + ((i & 1) == 0 ? -e.x : e.x),
                    c.y + ((i & 2) == 0 ? -e.y : e.y),
                    c.z + ((i & 4) == 0 ? -e.z : e.z));
                var lp = _root.InverseTransformPoint(corner);   // 世界 -> _root 局部
                if (!init) { result = new Bounds(lp, Vector3.zero); init = true; }
                else result.Encapsulate(lp);
            }
        }
        return result;
    }

    private static int IndexOfMax(Vector3 v)
    {
        if (v.x >= v.y && v.x >= v.z) return 0;
        return (v.y >= v.z) ? 1 : 2;
    }

    private void BuildPlaceholder()
    {
        var body = CreatePart(PrimitiveType.Capsule, "Body", bodyColor);
        body.localPosition = new Vector3(0f, 1.0f, 0f);
        body.localScale = new Vector3(0.9f, 1.1f, 0.9f);

        var head = CreatePart(PrimitiveType.Sphere, "Head", headColor);
        head.localPosition = new Vector3(0f, 2.1f, 0f);
        head.localScale = Vector3.one * 0.8f;

        var eyeL = CreatePart(PrimitiveType.Sphere, "EyeL", Color.white);
        eyeL.localPosition = new Vector3(-0.18f, 2.2f, 0.35f);
        eyeL.localScale = Vector3.one * 0.18f;

        var eyeR = CreatePart(PrimitiveType.Sphere, "EyeR", Color.white);
        eyeR.localPosition = new Vector3(0.18f, 2.2f, 0.35f);
        eyeR.localScale = Vector3.one * 0.18f;

        var armL = CreatePart(PrimitiveType.Capsule, "ArmL", bodyColor);
        armL.localPosition = new Vector3(-0.7f, 1.1f, 0f);
        armL.localScale = new Vector3(0.3f, 0.9f, 0.3f);

        var armR = CreatePart(PrimitiveType.Capsule, "ArmR", bodyColor);
        armR.localPosition = new Vector3(0.7f, 1.1f, 0f);
        armR.localScale = new Vector3(0.3f, 0.9f, 0.3f);

        var legL = CreatePart(PrimitiveType.Capsule, "LegL", bodyColor);
        legL.localPosition = new Vector3(-0.3f, 0.1f, 0f);
        legL.localScale = new Vector3(0.35f, 0.9f, 0.35f);

        var legR = CreatePart(PrimitiveType.Capsule, "LegR", bodyColor);
        legR.localPosition = new Vector3(0.3f, 0.1f, 0f);
        legR.localScale = new Vector3(0.35f, 0.9f, 0.35f);
    }

    private void SetLayerRecursively(GameObject target, int layer)
    {
        target.layer = layer;
        foreach (Transform child in target.transform) SetLayerRecursively(child.gameObject, layer);
    }

    private Transform CreatePart(PrimitiveType type, string name, Color color)
    {
        var go = GameObject.CreatePrimitive(type);
        go.name = name;
        go.transform.SetParent(_root, false);
        go.layer = _root.gameObject.layer;
        var rend = go.GetComponent<Renderer>();
        if (rend != null)
        {
            rend.material = new Material(Shader.Find("Standard"));
            rend.material.color = color;
        }
        return go.transform;
    }

    private CharacterWeaponView CombatWeapons()
    {
        EnsureAnimatorBinding();
        if (_combatWeapons == null)
        {
            _combatWeapons = gameObject.AddComponent<CharacterWeaponView>();
            _combatWeapons.Initialize(_modelInstance, _animator, _root, swordWeapon, pistolWeapon);
        }
        return _combatWeapons;
    }

    public void EquipCombatWeapon(int pattern) { CombatWeapons().Equip(pattern); }
    public float BeginCombatAttack(int pattern, float dirX, float dirY, float effectiveInterval)
    {
        return CombatWeapons().Begin(pattern, dirX, dirY, effectiveInterval);
    }
    public void ReleaseCombatAttack(int pattern) { CombatWeapons().Release(pattern); }
    public Vector3 GetCombatMuzzlePosition() { return CombatWeapons().MuzzlePosition(); }
    public void ResetCombatWeapon() { if (_combatWeapons != null) _combatWeapons.Clear(); }
    public void SetCombatPaused(bool paused) { if (_combatWeapons != null) _combatWeapons.SetPaused(paused); }

    public override void Play(CharacterState state, bool loop = true)
    {
        _current = state;

        // 兜底绑定：CreatePlayer 在 Start 阶段调用 Play 时首帧 Update 尚未跑，
        // 这里先确保 controller/avatar 已绑上，否则会错误地落到程序化占位分支。
        EnsureAnimatorBinding();

        if (_animator != null && _animator.runtimeAnimatorController != null && HasState(state))
        {
            // AnimatorController 分支原本忽略 loop 参数，是否循环取决于 clip 导入设置。
            // 这里在 loop=true 时强制把对应 clip 设为循环，避免走路/待机只播一遍就停。
            if (loop) EnsureClipLoop(state);
            _animator.CrossFade(state.ToString(), 0.2f, 0);
            return;
        }

        PlayProcedural(state, loop);
    }

    private bool HasState(CharacterState s)
    {
        return _animator.HasState(0, Animator.StringToHash(s.ToString()));
    }

    /// <summary>
    /// AnimatorController 分支原本忽略 Play() 传入的 loop 参数，是否循环完全取决于 clip
    /// 导入设置里的 Loop Time。为保证走路/待机等循环类状态真正循环（而非播一遍就停在末帧），
    /// 这里在运行时把对应 clip 的 isLooping 强制打开。
    /// clip 名常带骨架前缀（如 CharacterArmature|Walk），按状态名后缀匹配。
    /// </summary>
    private void EnsureClipLoop(CharacterState state)
    {
        if (_animator == null || _animator.runtimeAnimatorController == null) return;
        var clips = _animator.runtimeAnimatorController.animationClips;
        if (clips == null) return;

        string stateName = state.ToString();
        foreach (var clip in clips)
        {
            if (clip == null) continue;
            if (clip.name == stateName
                || clip.name.EndsWith("|" + stateName, System.StringComparison.Ordinal)
                || clip.name.EndsWith("_" + stateName, System.StringComparison.Ordinal))
            {
                // Motion.isLooping 在较新 Unity 中为只读（由 wrapMode 派生），
                // 运行时无法直接赋值；改为设置 wrapMode 来强制循环。
                if (clip.wrapMode != WrapMode.Loop)
                    clip.wrapMode = WrapMode.Loop;
            }
        }
    }

    private void PlayProcedural(CharacterState state, bool loop)
    {
        if (_oneShot != null) { StopCoroutine(_oneShot); _oneShot = null; }

        switch (state)
        {
            case CharacterState.Stand:
            case CharacterState.KongBai:
            case CharacterState.Walk:
                animate = true;
                break;
            case CharacterState.Stop:
                animate = false;
                break;
            case CharacterState.Click:
                _oneShot = StartCoroutine(Bounce());
                break;
            case CharacterState.Special01:
            case CharacterState.Special02:
                _oneShot = StartCoroutine(SpinBurst());
                break;
            case CharacterState.Open:
            case CharacterState.ChuChang:
                _oneShot = StartCoroutine(Entrance());
                break;
        }
    }

    private IEnumerator Bounce()
    {
        float baseY = _baseY;
        for (float i = 0; i < 1f; i += Time.deltaTime * 3f)
        {
            transform.position = new Vector3(transform.position.x, baseY + Mathf.Sin(i * Mathf.PI) * 0.4f, transform.position.z);
            yield return null;
        }
        transform.position = new Vector3(transform.position.x, baseY, transform.position.z);
        _oneShot = null;
    }

    private IEnumerator SpinBurst()
    {
        float start = transform.eulerAngles.y;
        for (float i = 0; i < 1f; i += Time.deltaTime * 2f)
        {
            transform.eulerAngles = new Vector3(0, start + i * 360f, 0);
            yield return null;
        }
        _oneShot = null;
    }

    private IEnumerator Entrance()
    {
        var baseScale = _root.localScale;
        for (float i = 0; i < 1f; i += Time.deltaTime * 2f)
        {
            float s = Mathf.Lerp(0.01f, 1f, i);
            _root.localScale = baseScale * s;
            yield return null;
        }
        _root.localScale = baseScale;
        _oneShot = null;
    }

    public override void SetFlip(bool flip)
    {
        if (_root != null) _root.localEulerAngles = new Vector3(0, flip ? 180f : 0f, 0f);
    }

    /// <summary>正弦驱动的走路循环：左右腿反相摆动、膝盖弯曲、手臂与同侧腿反相。</summary>
    private void ApplyWalkCycle()
    {
        if (!_hasBones) return;

        float phase = Time.time * walkCycleSpeed;
        float s = Mathf.Sin(phase);

        SwingBone(_upperLegL, s * legSwingAngle);
        SwingBone(_upperLegR, -s * legSwingAngle);

        // 膝盖只朝后弯：腿摆到后面时弯曲最多
        SwingBone(_lowerLegL, -Mathf.Max(0f, -s) * kneeBendAngle);
        SwingBone(_lowerLegR, -Mathf.Max(0f, s) * kneeBendAngle);

        // 手臂与同侧腿反相
        SwingBone(_armL, -s * armSwingAngle);
        SwingBone(_armR, s * armSwingAngle);
    }

    private void SwingBone(BoneRef b, float angle)
    {
        if (b == null || b.t == null) return;
        b.t.localRotation = b.bindRot * Quaternion.AngleAxis(angle, b.swingAxis);
    }

    /// <summary>回到绑定姿态（停下 / 待机时把骨骼收回）。</summary>
    private void RestoreBones(float k)
    {
        if (!_hasBones) return;
        LerpBone(_upperLegL, k);
        LerpBone(_lowerLegL, k);
        LerpBone(_upperLegR, k);
        LerpBone(_lowerLegR, k);
        LerpBone(_armL, k);
        LerpBone(_armR, k);
    }

    private void LerpBone(BoneRef b, float k)
    {
        if (b == null || b.t == null) return;
        b.t.localRotation = Quaternion.Slerp(b.t.localRotation, b.bindRot, k);
    }

    private void Update()
    {
        UpdateHurtFlash();
        EnsureAnimatorBinding();
        if (!animate || _current == CharacterState.Stop) return;

        // 有 AnimatorController 时真动画接管，不再叠加程序化位移和骨骼摆动
        if (_animator != null && _animator.runtimeAnimatorController != null) return;

        if (_current == CharacterState.Walk)
        {
            // 相位与摆腿共用 walkCycleSpeed，保证弹跳和迈步严格同步（每步弹一次）
            float phase = Time.time * walkCycleSpeed;

            // 身体上下弹跳：Q 版走路最明显的特征
            float bounce = chibiStyle
                ? Mathf.Abs(Mathf.Sin(phase)) * walkBounce
                : Mathf.Abs(Mathf.Sin(phase)) * bobHeight * 1.5f;
            transform.position = new Vector3(transform.position.x, _baseY + bounce, transform.position.z);

            // 前倾 + 左右摇摆（Q 版重心左右晃）；朝向由上层控制，这里不动 Y
            float lean = chibiStyle ? walkLean : Mathf.Sin(phase) * 8f;
            float sway = chibiStyle ? Mathf.Sin(phase) * walkSway : 0f;
            _root.localEulerAngles = new Vector3(lean, _root.localEulerAngles.y, sway);

            if (proceduralBones) ApplyWalkCycle();
            else RestoreBones(Time.deltaTime * 8f);
        }
        else // Stand / KongBai 待机：轻微呼吸起伏，骨骼收回绑定姿态
        {
            float t = Time.time * bobSpeed;
            transform.position = new Vector3(transform.position.x, _baseY + Mathf.Sin(t) * bobHeight, transform.position.z);
            _root.localEulerAngles = new Vector3(0f, _root.localEulerAngles.y, 0f);
            RestoreBones(Time.deltaTime * 8f);
        }
    }
}
