// =============================================================================
// InteractionController.cs
// =============================================================================
// 玩家交互控制器。负责把「输入」翻译成「对 Interactable 的触发」：
//
//   鼠标左键  -> 射线命中 Interactable -> Interact()
//   鼠标悬停  -> 记录当前指向的对象并通过 onHoverChanged 抛出名称（为商人/NPC 头顶 UI 预留）
//   玩家靠近  -> 命中 allowProximity 的 Interactable -> Interact()（走进洞口即传送）
//
// 设计要点：
//   - 只做「判定 + 转发」，具体做什么由 Interactable 上的事件决定（依赖倒置）
//   - 用 RaycastNonAlloc + Interactable 静态注册表，避免每帧 GC 与 FindObjectsOfType
//   - UI 遮挡检查必须区分 pointerId：IsPointerOverGameObject() 只判断左键(-1)，
//     本项目左键用于交互、右键用于移动，因此这里统一按左键语义检查
// =============================================================================

using UnityEngine;
using UnityEngine.Events;
using UnityEngine.EventSystems;

[AddComponentMenu("Game/InteractionController")]
public class InteractionController : MonoBehaviour
{
    [Header("References")]
    public Transform player;
    public Camera worldCamera;

    [Header("Click")]
    [Tooltip("左键可交互的最大射线距离")]
    public float maxDistance = 80f;

    [Header("Output")]
    [Tooltip("悬停对象变化时回调，参数为对象显示名（无对象时为空串）。用于以后做商人/NPC 名字提示")]
    public StringUnityEvent onHoverChanged = new StringUnityEvent();

    [System.Serializable]
    public class StringUnityEvent : UnityEvent<string> { }

    private const int MaxHits = 32;
    private readonly RaycastHit[] _hits = new RaycastHit[MaxHits];

    private Interactable _hovered;
    private string _hoveredName = "";

    void Update()
    {
        if (worldCamera == null) return;

        HandleHover();
        HandleClick();
        HandleProximity();
    }

    // ---------------------------------------------------------------------
    // 悬停：不是为了美观，而是为「之后可能有商人」留出 UI 挂钩点
    // ---------------------------------------------------------------------
    private void HandleHover()
    {
        Interactable found = null;

        if (!IsPointerOverUI() && TryGetPointerRay(out Ray ray))
            found = PickInteractable(ray);

        if (found == _hovered) return;

        _hovered = found;
        string newName = (found != null && found.allowClick)
            ? (string.IsNullOrEmpty(found.interactName) ? found.name : found.interactName)
            : "";

        if (newName == _hoveredName) return;

        _hoveredName = newName;
        onHoverChanged?.Invoke(newName);
    }

    // ---------------------------------------------------------------------
    // 左键：点击触发物体
    // ---------------------------------------------------------------------
    private void HandleClick()
    {
        if (!Input.GetMouseButtonDown(0)) return;   // 0 = 左键
        if (IsPointerOverUI()) return;              // 点在 UI（面板/按钮）上不算交互
        if (!TryGetPointerRay(out Ray ray)) return;

        var target = PickInteractable(ray);
        if (target == null || !target.allowClick) return;

        target.Interact();
    }

    // ---------------------------------------------------------------------
    // 靠近自动触发（洞口传送等）
    // ---------------------------------------------------------------------
    private void HandleProximity()
    {
        if (player == null) return;

        // 倒序遍历：Interact() 可能触发传送，进而让物体 OnDisable -> Interactable.All.Remove，
        // 正序遍历会当场抛 InvalidOperationException。
        // 倒序时移除的是当前索引 i，后续索引均小于 i、不受影响，因此安全。
        for (int i = Interactable.All.Count - 1; i >= 0; i--)
        {
            var it = Interactable.All[i];
            if (it == null || !it.allowProximity) continue;

            float r = it.proximityRadius;
            if (r <= 0f) continue;

            // sqrMagnitude 比较，避免开方
            float sqrDist = (it.transform.position - player.position).sqrMagnitude;
            if (sqrDist <= r * r)
                it.Interact();
        }
    }

    // ---------------------------------------------------------------------
    // 工具
    // ---------------------------------------------------------------------
    private bool TryGetPointerRay(out Ray ray)
    {
        ray = worldCamera.ScreenPointToRay(Input.mousePosition);
        return true;
    }

    /// <summary>从射线中挑出最近的 Interactable（容忍挂在父节点上的情况）。</summary>
    private Interactable PickInteractable(Ray ray)
    {
        int count = Physics.RaycastNonAlloc(ray, _hits, maxDistance);
        if (count <= 0) return null;

        for (int i = 0; i < count; i++)
        {
            var hit = _hits[i];
            // 用 transform.GetComponentInParent 而不是 collider 自身，
            // 这样 Hit 到子网格（如洞口的底座/光环）也能找到根部挂的 Interactable
            var it = hit.transform != null ? hit.transform.GetComponentInParent<Interactable>() : null;
            if (it != null) return it;
        }
        return null;
    }

    /// <summary>UI 遮挡检查。左键语义用 -1（默认值）。</summary>
    private bool IsPointerOverUI()
    {
        return EventSystem.current != null && EventSystem.current.IsPointerOverGameObject();
    }

    /// <summary>当前悬停的可交互对象（外部查询用）。</summary>
    public Interactable GetHovered()
    {
        return _hovered;
    }
}
