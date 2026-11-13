// =============================================================================
// VirtualJoystick.cs
// =============================================================================
// 自研轻量虚拟摇杆，不依赖 EasyTouch 等第三方插件。
// 基于 Unity EventSystems (IDragHandler, IPointerDownHandler, IPointerUpHandler)。
//
// 设计参考：
//   - 旧项目 ShaoNvClient_H02 使用 EasyTouch ETCJoystick
//   - 新项目自研，去除第三方依赖，核心 API 对齐 ETCJoystick.onMove
//
// 架构：
//   - 外圈 (Background)：摇杆活动区域
//   - 内圈 (Handle)：跟随手指的摇杆把手
//   - 输出：axisX / axisY（-1~1 归一化值）
//   - 事件：onMove(Vector2) / onPointerDown / onPointerUp
//
// 用法：
//   1. 在 Canvas 下创建 Image 作为 Background，挂载 VirtualJoystick
//   2. Background 下创建子 Image 作为 Handle
//   3. 配置 radius（摇杆活动半径）即可
// =============================================================================

using UnityEngine;
using UnityEngine.Events;
using UnityEngine.EventSystems;
using UnityEngine.UI;

[AddComponentMenu("Game/VirtualJoystick")]
public class VirtualJoystick : MonoBehaviour,
    IPointerDownHandler, IPointerUpHandler, IDragHandler
{
    [System.Serializable]
    public class JoystickMoveEvent : UnityEvent<Vector2> { }

    [Header("Handle")]
    [Tooltip("摇杆内圈（把手），需是 Background 的子对象")]
    public RectTransform handle;

    [Header("Settings")]
    [Tooltip("摇杆活动半径（像素）")]
    public float radius = 100f;

    [Tooltip("是否限制在圆形区域内（false = 正方形）")]
    public bool clampToCircle = true;

    [Tooltip("手指松开后是否自动归零")]
    public bool resetOnRelease = true;

    [Tooltip("归零插值速度")]
    public float returnSpeed = 10f;

    [Tooltip("死区阈值（低于此值输出 0）")]
    public float deadZone = 0.05f;

    [Header("Events")]
    public JoystickMoveEvent onMove = new JoystickMoveEvent();
    public UnityEvent onPointerDown = new UnityEvent();
    public UnityEvent onPointerUp = new UnityEvent();

    [Header("Debug")]
    public float axisX;
    public float axisY;

    private RectTransform _bgRect;
    private Vector2 _pointerLocalPos;
    private bool _isDragging;
    private Vector2 _output;

    void Awake()
    {
        _bgRect = GetComponent<RectTransform>();

        if (handle == null)
        {
            var child = transform.Find("Handle");
            if (child != null)
                handle = child as RectTransform;
        }

        if (handle != null)
            handle.anchoredPosition = Vector2.zero;
    }

    void OnEnable()
    {
        _output = Vector2.zero;
        axisX = 0f;
        axisY = 0f;
        if (handle != null)
            handle.anchoredPosition = Vector2.zero;
    }

    void Update()
    {
        if (!_isDragging && resetOnRelease)
        {
            if (handle != null)
            {
                handle.anchoredPosition = Vector2.Lerp(
                    handle.anchoredPosition,
                    Vector2.zero,
                    Time.deltaTime * returnSpeed
                );

                _output.x = handle.anchoredPosition.x / radius;
                _output.y = handle.anchoredPosition.y / radius;
            }
            else
            {
                _output = Vector2.Lerp(_output, Vector2.zero, Time.deltaTime * returnSpeed);
            }

            ApplyDeadZone();
            axisX = _output.x;
            axisY = _output.y;
            onMove?.Invoke(_output);
        }
    }

    public void OnPointerDown(PointerEventData eventData)
    {
        _isDragging = true;
        UpdatePointer(eventData);
        onPointerDown?.Invoke();
    }

    public void OnDrag(PointerEventData eventData)
    {
        if (!_isDragging) return;
        UpdatePointer(eventData);
    }

    public void OnPointerUp(PointerEventData eventData)
    {
        _isDragging = false;
        onPointerUp?.Invoke();
    }

    private void UpdatePointer(PointerEventData eventData)
    {
        if (_bgRect == null) return;

        RectTransformUtility.ScreenPointToLocalPointInRectangle(
            _bgRect,
            eventData.position,
            eventData.pressEventCamera,
            out _pointerLocalPos
        );

        if (clampToCircle)
        {
            float dist = _pointerLocalPos.magnitude;
            if (dist > radius)
                _pointerLocalPos = _pointerLocalPos.normalized * radius;
        }
        else
        {
            _pointerLocalPos.x = Mathf.Clamp(_pointerLocalPos.x, -radius, radius);
            _pointerLocalPos.y = Mathf.Clamp(_pointerLocalPos.y, -radius, radius);
        }

        if (handle != null)
            handle.anchoredPosition = _pointerLocalPos;

        _output.x = _pointerLocalPos.x / radius;
        _output.y = _pointerLocalPos.y / radius;

        ApplyDeadZone();
        axisX = _output.x;
        axisY = _output.y;
        onMove?.Invoke(_output);
    }

    private void ApplyDeadZone()
    {
        if (Mathf.Abs(_output.x) < deadZone) _output.x = 0f;
        if (Mathf.Abs(_output.y) < deadZone) _output.y = 0f;
    }

    public Vector2 GetOutput()
    {
        return new Vector2(axisX, axisY);
    }

    public bool IsDragging()
    {
        return _isDragging;
    }

    /// <summary>
    /// 复位摇杆到中性状态。
    /// 用于切场景 / 传送后：摇杆组件随 HomePanel 持久化复用，若上一场景正处于
    /// 「按住方向」状态，其输出会直接带入新场景，导致角色在新场景里自动朝旧方向移动。
    /// 复位会清零拖拽标记、输出向量与把手位置，并广播中性输出（onMove=0 / onPointerUp），
    /// 保证新场景读取到的第一帧输入就是 0。
    /// </summary>
    public void Reset()
    {
        _isDragging = false;
        _output = Vector2.zero;
        _pointerLocalPos = Vector2.zero;
        axisX = 0f;
        axisY = 0f;
        if (handle != null)
            handle.anchoredPosition = Vector2.zero;
        onPointerUp?.Invoke();
        onMove?.Invoke(Vector2.zero);
    }
}