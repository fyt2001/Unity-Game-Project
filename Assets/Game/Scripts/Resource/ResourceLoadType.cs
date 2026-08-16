// =============================================================================
// ResourceLoadType.cs - 资源加载类型枚举（腾讯级生产标准）
// =============================================================================
// 来源: ShaoNvClient_H02 GoldenEngine.GoldenLoadType
// =============================================================================

/// <summary>
/// 统一资源类型枚举。
/// 用于资源管理系统标识不同类型资源的加载策略。
/// </summary>
public enum ResourceLoadType
{
    /// <summary>GameObject 预制体</summary>
    GameObject = 0,

    /// <summary>Unity 场景</summary>
    Unity,

    /// <summary>Sprite 精灵</summary>
    Sprite,

    /// <summary>SpriteAtlas 图集</summary>
    SpriteAtlas,

    /// <summary>Atlas 图集</summary>
    Atlas,

    /// <summary>Font 字体</summary>
    Font,

    /// <summary>通用 Asset</summary>
    Asset,

    /// <summary>Material 材质</summary>
    Material,

    /// <summary>二进制 Bytes</summary>
    Bytes,

    /// <summary>Audio 音频</summary>
    Audio,

    /// <summary>Text 文本</summary>
    Txt,

    /// <summary>Lua 脚本</summary>
    Lua,

    /// <summary>Protobuf 数据</summary>
    PB,

    /// <summary>未知类型</summary>
    Unknown,
}
