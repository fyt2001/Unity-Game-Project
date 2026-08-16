// =============================================================================
// EnhancedButton.cs - 增强版Button组件（腾讯级生产标准）
// =============================================================================
// 来源: ShaoNvClient_H02 GoldenEngine.GoldenButton + GoldenButtonAnim2S
// 升级: 合并两个Button增强组件，增加更多回调事件，修复视觉状态Bug
//
// 特性:
//   - 修复Unity原生Button按下后移出仍卡在Pressed状态的Bug
//   - 支持Pointer事件回调（Up/Down/Enter/Exit）
//   - 支持两阶段动画（按下播动画→动画结束才触发onClick）
//   - 支持Normal/Pressed/Disabled三态动画机
// =============================================================================

using System;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;

#if UNITY_EDITOR
using UnityEditor;
using UnityEditor.UI;
#endif

/// <summary>
/// 增强版 Button。
/// 修复视觉状态Bug + 增加Pointer事件监听 + 可选两阶段动画。
/// </summary>
public class EnhancedButton : Button
{
    [Header("Enhanced Settings")]
    [Tooltip("是否等待按下动画播放完毕后再触发onClick")]
    public bool RespondAfterAnimation = false;

    [Tooltip("是否启用两阶段动画模式（需要Animator组件）")]
    public bool UseTwoPhaseAnimation = false;

    private bool _inside;
    private Action<EnhancedButton, string> _pointerEventCallback;
    private bool _shouldRespond;
    private string _nextClip;
    private Animator _animator;

    /// <summary>
    /// 设置 Pointer 事件回调 (Up/Down/Enter/Exit)
    /// </summary>
    public void SetPointerEventListener(Action<EnhancedButton, string> callback)
    {
        _pointerEventCallback = callback;
    }

    protected override void Start()
    {
        base.Start();
        if (UseTwoPhaseAnimation)
        {
            _animator = GetComponent<Animator>();
        }
    }

    protected override void DoStateTransition(SelectionState state, bool instant)
    {
        // 修复Bug：按下后鼠标移出时不应保持Pressed状态
        if (state == SelectionState.Pressed && !_inside)
        {
            state = SelectionState.Normal;
        }
        base.DoStateTransition(state, instant);
    }

    protected override void InstantClearState()
    {
        base.InstantClearState();
        _inside = false;
    }

    private void Update()
    {
        if (!UseTwoPhaseAnimation || _animator == null) return;

        // 动画队列管理
        bool currentAniDone = _animator.GetCurrentAnimatorStateInfo(0).normalizedTime >= 1.0f;
        if (currentAniDone && _nextClip.Length > 0)
        {
            _animator.Play(_nextClip);
            _nextClip = "";
        }

        // 动画结束后触发 onClick
        if (_shouldRespond && _animator.GetCurrentAnimatorStateInfo(0).IsName("Normal"))
        {
            _shouldRespond = false;
            onClick?.Invoke();
        }

        // 处理 Disabled 状态
        bool isDisabled = _animator.GetCurrentAnimatorStateInfo(0).IsName("Disabled");
        bool isPressed = _animator.GetCurrentAnimatorStateInfo(0).IsName("Pressed");
        if (!interactable && !isDisabled && (!isPressed || currentAniDone))
        {
            _nextClip = "";
            _animator.Play("Disabled");
        }
        else if (interactable && isDisabled)
        {
            _nextClip = "";
            _animator.Play("Normal");
        }
    }

    #region Pointer Events

    public override void OnPointerUp(PointerEventData eventData)
    {
        base.OnPointerUp(eventData);
        _pointerEventCallback?.Invoke(this, "OnPointerUp");

        if (UseTwoPhaseAnimation && interactable)
        {
            _nextClip = "Normal";
        }
    }

    public override void OnPointerDown(PointerEventData eventData)
    {
        base.OnPointerDown(eventData);
        _pointerEventCallback?.Invoke(this, "OnPointerDown");

        if (UseTwoPhaseAnimation && interactable)
        {
            if (!_animator.GetCurrentAnimatorStateInfo(0).IsName("Pressed"))
            {
                _animator.Play("Pressed");
            }
            _nextClip = "";
        }
    }

    public override void OnPointerEnter(PointerEventData eventData)
    {
        _inside = true;
        base.OnPointerEnter(eventData);
        _pointerEventCallback?.Invoke(this, "OnPointerEnter");

        if (UseTwoPhaseAnimation && interactable)
        {
            if (!_animator.GetCurrentAnimatorStateInfo(0).IsName("Pressed")
                && eventData.pointerPress == gameObject)
            {
                _animator.Play("Pressed");
            }
            _nextClip = "";
        }
    }

    public override void OnPointerExit(PointerEventData eventData)
    {
        _inside = false;
        base.OnPointerExit(eventData);
        _pointerEventCallback?.Invoke(this, "OnPointerExit");

        if (UseTwoPhaseAnimation && interactable)
        {
            _nextClip = "Normal";
        }
    }

    public override void OnPointerClick(PointerEventData eventData)
    {
        if (!interactable) return;

        if (!RespondAfterAnimation)
        {
            onClick?.Invoke();
        }
        else
        {
            _shouldRespond = true;
        }
    }

    #endregion

    #region Editor

#if UNITY_EDITOR
    [CustomEditor(typeof(EnhancedButton), true)]
    [CanEditMultipleObjects]
    public class EnhancedButtonEditor : ButtonEditor
    {
        public override void OnInspectorGUI()
        {
            EnhancedButton btn = target as EnhancedButton;
            serializedObject.Update();

            EditorGUILayout.PropertyField(serializedObject.FindProperty("RespondAfterAnimation"));
            EditorGUILayout.PropertyField(serializedObject.FindProperty("UseTwoPhaseAnimation"));

            serializedObject.ApplyModifiedProperties();
            base.OnInspectorGUI();
        }
    }

    [MenuItem("GameObject/UI/Enhanced/EnhancedButton", false, 10)]
    static void CreateEnhancedButton(MenuCommand menuCommand)
    {
        GameObject go = new GameObject("EnhancedButton");
        GameObjectUtility.SetParentAndAlign(go, menuCommand.context as GameObject);
        go.AddComponent<Image>();
        go.AddComponent<EnhancedButton>();
        Undo.RegisterCreatedObjectUndo(go, "Create " + go.name);
        Selection.activeObject = go;
    }
#endif

    #endregion
}
