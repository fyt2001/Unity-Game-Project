using UnityEngine;

/// <summary>
/// 角色状态词表，对齐项目 Spine 角色目录下的 .playable 命名约定：
/// Stand / Stop / Click / Special01 / Special02 / Open / KongBai / ChuChang。
/// 任何角色视图（3D 或 Spine）都按此词表驱动，上层无需区分底层渲染方式。
/// </summary>
public enum CharacterState
{
    Stand,     // 待机
    Walk,      // 移动 / 行走
    Stop,      // 停止
    Click,     // 点击反馈
    Special01, // 技能1
    Special02, // 技能2
    Open,      // 登场 / 开启
    KongBai,   // 空白 / 闲置
    ChuChang   // 出场
}

/// <summary>
/// 角色视图抽象基类，定义统一接口（ICharacterView）。
/// 具体渲染（3D 模型 / Spine 骨骼）由子类实现，资源共享「按角色分目录」布局。
/// </summary>
public abstract class CharacterView : MonoBehaviour, ICharacterView
{
    public abstract void Play(CharacterState state, bool loop = true);
    public abstract void SetFlip(bool flip);
}
