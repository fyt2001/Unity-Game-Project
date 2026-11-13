using TMPro;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.Scripting;
using UnityEngine.UI;

[Preserve]
public static class UIRuntimeCleanup
{
    // Only call at terminal teardown of the owned UI hierarchy, never when caching a window.
    [Preserve]
    public static void ReleaseCallbacks(GameObject root)
    {
        if (root == null) return;
        foreach (var control in root.GetComponentsInChildren<Button>(true)) control.onClick.RemoveAllListeners();
        foreach (var control in root.GetComponentsInChildren<Toggle>(true)) control.onValueChanged.RemoveAllListeners();
        foreach (var control in root.GetComponentsInChildren<Slider>(true)) control.onValueChanged.RemoveAllListeners();
        foreach (var control in root.GetComponentsInChildren<Scrollbar>(true)) control.onValueChanged.RemoveAllListeners();
        foreach (var control in root.GetComponentsInChildren<ScrollRect>(true)) control.onValueChanged.RemoveAllListeners();
        foreach (var control in root.GetComponentsInChildren<Dropdown>(true)) control.onValueChanged.RemoveAllListeners();
        foreach (var control in root.GetComponentsInChildren<TMP_Dropdown>(true)) control.onValueChanged.RemoveAllListeners();
        foreach (var control in root.GetComponentsInChildren<InputField>(true))
        {
            control.onValueChanged.RemoveAllListeners();
            control.onEndEdit.RemoveAllListeners();
        }
        foreach (var control in root.GetComponentsInChildren<TMP_InputField>(true))
        {
            control.onValueChanged.RemoveAllListeners();
            control.onEndEdit.RemoveAllListeners();
            control.onSubmit.RemoveAllListeners();
            control.onSelect.RemoveAllListeners();
            control.onDeselect.RemoveAllListeners();
        }
        foreach (var control in root.GetComponentsInChildren<EnhancedButton>(true)) control.SetPointerEventListener(null);
        foreach (var control in root.GetComponentsInChildren<ModCardDrag>(true))
            control.ReleaseCallbacks();
        foreach (var trigger in root.GetComponentsInChildren<EventTrigger>(true))
            foreach (var entry in trigger.triggers) entry.callback.RemoveAllListeners();
        foreach (var binder in root.GetComponentsInChildren<UIComponentBinder>(true)) binder.LuaInstance = null;
    }
}
