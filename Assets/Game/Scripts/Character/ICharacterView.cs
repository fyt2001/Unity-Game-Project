/// <summary>
/// 角色视图统一接口。3D（Model3DCharacterView）与 Spine（SpineCharacterView）共用同一套状态词表，
/// 上层（UI / Lua）只依赖此接口，不关心底层是 2D 骨骼还是 3D 模型。
/// 状态名与项目 Spine 角色的 .playable 命名约定一一对应。
/// </summary>
public interface ICharacterView
{
    /// <summary>按状态名播放：Stand / Stop / Click / Special01 / Special02 / Open / KongBai / ChuChang</summary>
    void Play(CharacterState state, bool loop);

    /// <summary>水平翻转（Spine 改 FlipX；3D 改模型 Y 轴旋转 180°）</summary>
    void SetFlip(bool flip);
}
