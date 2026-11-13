using UnityEngine;
using UnityEngine.Events;
using UnityEngine.EventSystems;
using UnityEngine.Scripting;

// Pointer relay only. Lua owns selection, drop validation and persistence.
[Preserve, DisallowMultipleComponent]
public sealed class ModCardDrag : MonoBehaviour, IBeginDragHandler, IDragHandler,
    IEndDragHandler, IPointerEnterHandler, IPointerExitHandler
{
    [Preserve] public UnityEvent beginDrag = new UnityEvent();
    [Preserve] public UnityEvent drag = new UnityEvent();
    [Preserve] public UnityEvent endDrag = new UnityEvent();
    [Preserve] public UnityEvent enter = new UnityEvent();
    [Preserve] public UnityEvent exit = new UnityEvent();
    [Preserve] public Vector2 pointerPosition;
    [Preserve] public Camera eventCamera;
    private int pointerId;
    private bool dragging;

    [Preserve] public static bool IsMissing(Object value) { return value == null; }

    public void OnBeginDrag(PointerEventData data)
    {
        if (dragging || data.button != PointerEventData.InputButton.Left) return;
        pointerId = data.pointerId;
        dragging = true;
        Capture(data);
        data.eligibleForClick = false;
        beginDrag.Invoke();
    }
    public void OnDrag(PointerEventData data)
    {
        if (!dragging || data.pointerId != pointerId) return;
        Capture(data);
        drag.Invoke();
    }
    public void OnEndDrag(PointerEventData data)
    {
        if (!dragging || data.pointerId != pointerId) return;
        Capture(data);
        dragging = false;
        endDrag.Invoke();
    }
    public void OnPointerEnter(PointerEventData data) { enter.Invoke(); }
    public void OnPointerExit(PointerEventData data) { exit.Invoke(); }
    private void Capture(PointerEventData data)
    {
        pointerPosition = data.position;
        eventCamera = data.pressEventCamera;
    }
    private void OnDisable() { dragging = false; }
    internal void ReleaseCallbacks()
    {
        beginDrag.RemoveAllListeners(); drag.RemoveAllListeners();
        endDrag.RemoveAllListeners(); enter.RemoveAllListeners(); exit.RemoveAllListeners();
    }
    private void OnDestroy() { ReleaseCallbacks(); }
}
