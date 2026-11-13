using System.Collections.Generic;
using UnityEngine;

// Only the legacy debug text is suppressed; gameplay and enemy overlays keep running.
[DisallowMultipleComponent]
public sealed class GMPanelDebugOverlay : MonoBehaviour
{
    private static readonly HashSet<GMPanelDebugOverlay> VisiblePanels = new HashSet<GMPanelDebugOverlay>();

    public static bool IsVisible
    {
        get
        {
            foreach (var panel in VisiblePanels)
            {
                if (panel != null && panel.isActiveAndEnabled) return true;
            }
            return false;
        }
    }

    private void OnEnable() { VisiblePanels.Add(this); }
    private void OnDisable() { VisiblePanels.Remove(this); }
    private void OnDestroy() { VisiblePanels.Remove(this); }
}
