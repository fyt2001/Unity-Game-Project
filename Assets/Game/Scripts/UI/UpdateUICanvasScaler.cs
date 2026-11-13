// =============================================================================
// UpdateUICanvasScaler.cs - UI 分辨率自适应（腾讯级生产标准）
// =============================================================================
// 来源: ShaoNvClient_H02 Assets/Game/Scripts/UICore/UpdateUICanvasScaler.cs
// 用途: 根据设备宽高比动态调整 CanvasScaler.matchWidthOrHeight
//       宽屏设备(如 1080×2340) → match=0 以高度为基准
//       方屏设备(如 1024×768)  → match=1 以宽度为基准
// =============================================================================

using UnityEngine;
using UnityEngine.UI;

public class UpdateUICanvasScaler : MonoBehaviour
{
    public CanvasScaler cs;

    private void Start()
    {
        if (cs == null) return;

        float standardWidth = 1080f;
        float standardHeight = 1920f;
        float deviceWidth = Screen.width;
        float deviceHeight = Screen.height;

        float standardAspect = standardHeight / standardWidth;
        float deviceAspect = deviceHeight / deviceWidth;

        if (deviceAspect >= standardAspect)
            cs.matchWidthOrHeight = 1;
        else
            cs.matchWidthOrHeight = 0;
    }
}