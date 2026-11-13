// =============================================================================
// TopDownCameraFollow.cs
// =============================================================================
// 俯视角相机跟随控制器。
// 专为吸血鬼幸存者类 3D 俯视角游戏设计。
//
// 设计要点（腾讯大厂级）：
//   1. 平滑跟随（Lerp 插值，避免抖动）
//   2. 固定俯视角（45° 斜视，可配置）
//   3. 边界限制（相机不超出场景边界）
//   4. 屏幕震动（受击反馈）
//   5. 缩放控制（滚轮缩放，仅开发者模式；只改距离，不改俯角）
//   6. 目标丢失保护（target 为 null 时保持最后位置）
//
// 用法：
//   挂载到场景相机上，设置 target 为玩家 Transform 即可。
// =============================================================================

using UnityEngine;

[AddComponentMenu("Game/TopDownCameraFollow")]
public class TopDownCameraFollow : MonoBehaviour
{
    [Header("Target")]
    [Tooltip("跟随目标（玩家 Transform）")]
    public Transform target;

    [Header("Follow")]
    [Tooltip("跟随平滑系数（越大越快，越小越滞后）")]
    public float followLerp = 5f;

    [Tooltip("相机高度偏移")]
    public float heightOffset = 20f;

    [Tooltip("相机纵深偏移（负值 = 向后偏移，形成俯视角）")]
    public float depthOffset = -15f;

    [Tooltip("瞄准点相对目标的垂直抬升（让角色身体而非脚底位于屏幕中心）")]
    public float lookHeightOffset = 1f;

    [Header("Bounds")]
    [Tooltip("是否启用边界限制")]
    public bool useBounds = false;

    [Tooltip("场景边界最小坐标")]
    public Vector3 boundsMin = new Vector3(-30f, 0f, -30f);

    [Tooltip("场景边界最大坐标")]
    public Vector3 boundsMax = new Vector3(30f, 0f, 30f);

    [Header("Shake")]
    [Tooltip("震动衰减速度")]
    public float shakeDecay = 5f;

    [Header("Zoom")]
    [Tooltip("是否允许滚轮缩放")]
    public bool allowZoom = true;

    [Tooltip("仅开发者模式下才响应滚轮（Unity Development Build 或编辑器内）。正式包里滚轮不生效。")]
    public bool zoomOnlyInDevMode = true;

    [Tooltip("缩放速度")]
    public float zoomSpeed = 2f;

    [Tooltip("最小距离（相机到目标的距离，不是高度）")]
    public float minZoom = 10f;

    [Tooltip("最大距离")]
    public float maxZoom = 40f;

    [Tooltip("正交相机的 orthographicSize 范围。正交投影下移动相机不改变画面大小，只能改这个值。")]
    public float minOrthoSize = 4f;
    public float maxOrthoSize = 16f;

    private Vector3 _lastTargetPos;
    private Vector3 _shakeOffset;
    private float _shakeIntensity;
    private Camera _cam;

    void Awake()
    {
        _cam = GetComponent<Camera>();
    }

    void Start()
    {
        if (_cam == null) _cam = GetComponent<Camera>();
        if (target != null)
            _lastTargetPos = target.position;
    }

    void LateUpdate()
    {
        HandleZoom();   // 先处理缩放，让本帧的位置/角度立刻用上新值

        if (target != null)
            _lastTargetPos = target.position;

        // 【边界处理的关键】只对「注视点」做限制，相机与注视点之间永远保持固定偏移，
        // 这样俯角恒定不变。
        //
        // 原实现是钳制【相机自身位置】：当玩家走到 z=-22 边缘时，相机 z 被从 -38 拽回 -22，
        // 与玩家同 z —— 相机被顶到玩家正上方，俯角由 54° 骤变为接近 90°（垂直俯视），
        // 画面透视关系整个变形，与荒野乱斗「俯角始终恒定」的观感不符。
        Vector3 focus = _lastTargetPos;

        if (useBounds)
        {
            focus.x = Mathf.Clamp(focus.x, boundsMin.x, boundsMax.x);
            focus.z = Mathf.Clamp(focus.z, boundsMin.z, boundsMax.z);
        }

        Vector3 desiredPos = focus + new Vector3(0f, heightOffset, depthOffset);

        transform.position = Vector3.Lerp(transform.position, desiredPos, Time.deltaTime * followLerp);

        if (_shakeIntensity > 0f)
        {
            _shakeOffset = Random.insideUnitSphere * _shakeIntensity;
            _shakeIntensity = Mathf.Lerp(_shakeIntensity, 0f, Time.deltaTime * shakeDecay);
            if (_shakeIntensity < 0.01f)
            {
                _shakeIntensity = 0f;
                _shakeOffset = Vector3.zero;
            }
            transform.position += _shakeOffset;
        }

        // 朝向【固定】：只由偏移量决定，绝不依赖相机的当前实际位置。
        //
        // 为什么不能用 LookRotation(瞄准点 - 相机当前位置)？
        //   相机位置是 Lerp 平滑追赶的，追帧期间它尚未到位，
        //   「当前位置 → 玩家」这条视线的俯角就会偏离标准值
        //   （玩家瞬移/急停时实测从 54° 漂到 74°），画面俯角来回摆动。
        //
        // 固定俯角后：
        //   - 相机滞后再也不会改变俯角，只表现为人物短暂偏离画面中心
        //     （匀速/静止的稳态下仍然居中，滞后量仅 速度/followLerp ≈ 0.5）
        //   - 镜头震动表现为平移而非旋转抖动，观感更稳
        //
        // 俯角推导：相机相对注视点的偏移是 (0, heightOffset, depthOffset)，
        // 视线需指向 -(offset)；再叠加瞄准点抬高 lookHeightOffset，
        // 故 pitch = Atan2(heightOffset - lookHeightOffset, -depthOffset)。
        // 注意参数顺序：写成 Atan2(-depthOffset, heightOffset) 会得到余角（36°）。
        float pitch = Mathf.Atan2(heightOffset - lookHeightOffset, -depthOffset) * Mathf.Rad2Deg;
        transform.rotation = Quaternion.Euler(pitch, 0f, 0f);
    }

    /// <summary>
    /// 滚轮缩放。两种投影的处理方式完全不同：
    ///   - 正交（Orthographic）：移动相机不改变画面大小，必须改 orthographicSize
    ///   - 透视（Perspective）：沿视线拉近/推远，俯角严格锁定（不动角度）
    /// </summary>
    private void HandleZoom()
    {
        if (!IsZoomAllowed()) return;

        float scroll = Mathf.Clamp(Input.GetAxis("Mouse ScrollWheel"), -1f, 1f);
        if (Mathf.Abs(scroll) < 0.001f) return;

        // 按比例缩放：远近手感一致。限制单次幅度，避免某些鼠标一格滚动值过大直接跳到极限。
        float factor = 1f - Mathf.Clamp(scroll * zoomSpeed, -0.5f, 0.5f);

        if (_cam != null && _cam.orthographic)
        {
            _cam.orthographicSize = Mathf.Clamp(_cam.orthographicSize * factor, minOrthoSize, maxOrthoSize);
            return;
        }

        // 用「距离 + 俯角」表示相机偏移：只改距离，俯角不变。
        // 旧写法先改 heightOffset 再按比例反推 depthOffset，一旦被 Clamp 比例就错，
        // 导致 Atan2(-depthOffset, heightOffset) 算出的俯角跟着漂 —— 滚轮就改变了机位角度。
        float pitch = Mathf.Atan2(-depthOffset, heightOffset);                            // 俯角（弧度），锁定
        float dist = Mathf.Sqrt(heightOffset * heightOffset + depthOffset * depthOffset); // 当前距离
        dist = Mathf.Clamp(dist * factor, minZoom, maxZoom);
        heightOffset = dist * Mathf.Cos(pitch);
        depthOffset = -dist * Mathf.Sin(pitch);
    }

    /// <summary>滚轮是否生效：需开启缩放，且（未限制开发者模式 / 当前处于开发者模式）。</summary>
    private bool IsZoomAllowed()
    {
        if (!allowZoom) return false;
        if (!zoomOnlyInDevMode) return true;
        return Debug.isDebugBuild || Application.isEditor;
    }

    public void Shake(float intensity)
    {
        _shakeIntensity = Mathf.Max(_shakeIntensity, intensity);
    }

    public void SetTarget(Transform newTarget)
    {
        target = newTarget;
        if (newTarget != null)
            _lastTargetPos = newTarget.position;
    }

    public void SetAngles(float height, float depth)
    {
        heightOffset = height;
        depthOffset = depth;
    }
}