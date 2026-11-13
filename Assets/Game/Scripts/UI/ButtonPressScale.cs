// =============================================================================
// ButtonPressScale.cs - 按钮点击缩放反馈（腾讯级生产标准）
// =============================================================================
// 作用: 为任意 Button/Selectable 提供「按下缩小、抬起恢复」的点击反馈。
//
// 设计说明:
//   - 独立组件，不侵入 EnhancedButton / Button，因此可作用于项目中任何按钮类型
//   - 通过 IPointerDownHandler / IPointerUpHandler / IPointerExitHandler 驱动，
//     只要按钮所在 GameObject 能被 GraphicRaycaster 命中即可生效
//   - 使用 Time.unscaledDeltaTime，不受 Time.timeScale(暂停/慢放) 影响
//   - OnDisable 与指针移出时自动恢复原始缩放，避免卡在缩小状态
//   - 记录 Awake 时的 localScale 作为基准，不写死 Vector3.one
// =============================================================================

using System.Collections;
using UnityEngine;
using UnityEngine.EventSystems;

[DisallowMultipleComponent]
public class ButtonPressScale : MonoBehaviour, IPointerDownHandler, IPointerUpHandler, IPointerExitHandler
{
    [Header("Press Scale Settings")]
    [Tooltip("是否启用点击缩放")]
    public bool EnableScale = true;

    [Tooltip("按下时的缩放比例（0.95 = 缩小到 95%）")]
    [Range(0.5f, 1.5f)]
    public float PressedScale = 0.95f;

    [Tooltip("缩放过渡时长（秒）")]
    public float Duration = 0.1f;

    private Vector3 _originScale = Vector3.one;
    private Coroutine _routine;

    private void Awake()
    {
        _originScale = transform.localScale;
    }

    public void OnPointerDown(PointerEventData eventData)
    {
        ScaleTo(_originScale * PressedScale);
    }

    public void OnPointerUp(PointerEventData eventData)
    {
        ScaleTo(_originScale);
    }

    public void OnPointerExit(PointerEventData eventData)
    {
        // 按下后把指针拖出按钮范围时恢复，避免卡在缩小状态
        ScaleTo(_originScale);
    }

    private void OnDisable()
    {
        StopScale();
        transform.localScale = _originScale;
    }

    private void ScaleTo(Vector3 target)
    {
        if (!EnableScale) return;
        StopScale();
        _routine = StartCoroutine(DoScale(target));
    }

    private void StopScale()
    {
        if (_routine != null)
        {
            StopCoroutine(_routine);
            _routine = null;
        }
    }

    private IEnumerator DoScale(Vector3 target)
    {
        Vector3 start = transform.localScale;

        if (Duration <= 0f)
        {
            transform.localScale = target;
            _routine = null;
            yield break;
        }

        float elapsed = 0f;
        while (elapsed < Duration)
        {
            elapsed += Time.unscaledDeltaTime;
            float t = Mathf.Clamp01(elapsed / Duration);
            transform.localScale = Vector3.Lerp(start, target, t);
            yield return null;
        }

        transform.localScale = target;
        _routine = null;
    }
}
