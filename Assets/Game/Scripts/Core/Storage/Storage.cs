// =============================================================================
// Storage.cs - 存储门面（静态入口，支持运行时注入）
// =============================================================================
// 默认实现为 FileStorage（System.IO），因此 PC / Android / iOS 行为与改造前一致。
//
// 微信小游戏接入后，只需在启动早期执行一次：
//     Storage.SetStorage(new WeChatStorage());
// 即可整体切换到底层 WX SDK，业务代码与 Lua 侧均无需改动。
//
// 之所以用“运行时注入”而不是 #if 平台宏：
//   1. 避免平台宏散落到业务代码；
//   2. 同一个包可在不同平台走不同实现，便于编辑器内模拟与测试。
// =============================================================================

using XLua;

[LuaCallCSharp]
public static class Storage
{
    private static IStorage _current;

    /// <summary>当前存储实现，默认为 <see cref="FileStorage"/>。</summary>
    public static IStorage Current
    {
        get
        {
            if (_current == null) _current = new FileStorage();
            return _current;
        }
    }

    /// <summary>
    /// 注入平台实现（如微信小游戏的 WX SDK 实现）。应在启动早期调用。
    /// 传 null 会重置回默认的 FileStorage。
    /// </summary>
    public static void SetStorage(IStorage storage)
    {
        _current = storage ?? new FileStorage();
    }
}
