using UnityEngine;
using Spine.Unity;

/// <summary>
/// Spine 角色视图：对齐项目 Spine 角色封装约定的 2D 实现。
/// 与 Model3DCharacterView 共用同一套 CharacterState 词表，上层（UI / Lua）无感知。
/// 播放走 SkeletonAnimation.AnimationState.SetAnimation（状态名即 CharacterState 名），
/// 也可配合项目 SpineTimeLine 的 .playable 时间轴使用。
/// </summary>
public class SpineCharacterView : CharacterView
{
    [Header("Spine 骨骼")] public SkeletonAnimation skeleton;

    private void Awake()
    {
        if (skeleton == null) skeleton = GetComponent<SkeletonAnimation>();
    }

    public override void Play(CharacterState state, bool loop = true)
    {
        if (skeleton != null && skeleton.AnimationState != null)
            skeleton.AnimationState.SetAnimation(0, state.ToString(), loop);
    }

    public override void SetFlip(bool flip)
    {
        if (skeleton != null) skeleton.Skeleton.FlipX = flip;
    }
}
