using UnityEngine;
using UnityEngine.EventSystems;

/// <summary>
/// 登录面板 3D 角色点击交互：点击中央的 Spike（RenderTexture 显示）时，
/// 触发场景中 LoginChar_Spike 的 Click 动画。纯 C# 实现，不依赖 XLua 导出。
/// 挂在 LoginPanel 的 m_Char(RawImage) 节点上；RawImage 已开 raycastTarget，
/// 由 Canvas 的 GraphicsRaycaster 命中并派发指针事件。
/// </summary>
public class LoginCharClicker : MonoBehaviour, IPointerClickHandler
{
    private Model3DCharacterView _charView;

    private Model3DCharacterView Resolve()
    {
        if (_charView != null) return _charView;
        var go = GameObject.Find("LoginChar_Spike");
        if (go != null) _charView = go.GetComponent<Model3DCharacterView>();
        return _charView;
    }

    public void OnPointerClick(PointerEventData eventData)
    {
        var view = Resolve();
        if (view != null) view.Play(CharacterState.Click);
    }
}
