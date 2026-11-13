// =============================================================================
// LuaFieldReader.cs - C# reads of Lua table fields with a diagnosable failure path
// =============================================================================
// Why: HomeSceneBootstrapper reads Lua fields by string key every frame. The old
// code wrapped each read in an empty catch, so a renamed Lua field silently became
// 0/false. Worse, xLua's LuaTable.Get<TKey,TValue> throws for nil -> value type
// BEFORE restoring the Lua stack (see Assets/XLua/Src/LuaTable.cs), so every failed
// read also leaked a stack slot.
//
// Contract:
//   - Field present and convertible: identical to LuaTable.Get (one extra ContainsKey
//     probe for value types, which never throws and restores the stack).
//   - Missing / wrong type: returns false (TryGet) or the caller's fallback (GetOr) and
//     logs ONE warning per key for the whole session, naming the key.
//   - Hot path: no managed allocation on success or on repeated failures; the warning
//     message is only built the first time a key fails.
// Plain C# called from C#: not exported to Lua, so no XLua Generate Code is needed.
// =============================================================================

using System;
using System.Collections.Generic;
using UnityEngine;
using XLua;

public static class LuaFieldReader
{
    private static readonly HashSet<string> s_Warned = new HashSet<string>(StringComparer.Ordinal);

    /// <summary>Reads table[key] as T. Returns false (value = default) when missing or not convertible.</summary>
    public static bool TryGet<T>(LuaTable table, string key, out T value)
    {
        value = default(T);
        if (table == null || key == null) return false;
        try
        {
            if (typeof(T).IsValueType && !table.ContainsKey(key))
            {
                WarnOnce(key, typeof(T), null);
                return false;
            }
            table.Get(key, out value);
            return true;
        }
        catch (Exception e)
        {
            value = default(T);
            WarnOnce(key, typeof(T), e);
            return false;
        }
    }

    /// <summary>Reads table[key] as T, or returns fallback (and warns once per key) when it cannot.</summary>
    public static T GetOr<T>(LuaTable table, string key, T fallback)
    {
        T value;
        return TryGet(table, key, out value) ? value : fallback;
    }

    /// <summary>Logs an exception for a scope once per session (for coarse catch blocks around Lua calls).</summary>
    public static void WarnOnce(string scope, Exception e)
    {
        if (scope == null || !s_Warned.Add(scope)) return;
        Debug.LogWarning("[LuaFieldReader] " + scope + " failed: " + (e != null ? e.GetType().Name + ": " + e.Message : "unknown")
            + ". Further failures of this scope are not logged.");
    }

    /// <summary>True when a warning was already emitted for this key/scope (for tests and diagnostics).</summary>
    public static bool HasWarned(string keyOrScope)
    {
        return keyOrScope != null && s_Warned.Contains(keyOrScope);
    }

    /// <summary>Forget emitted warnings (tests only).</summary>
    public static void ResetWarnings()
    {
        s_Warned.Clear();
    }

    private static void WarnOnce(string key, Type type, Exception e)
    {
        if (!s_Warned.Add(key)) return;
        string reason = e == null ? "missing (nil)" : e.GetType().Name + ": " + e.Message;
        Debug.LogWarning("[LuaFieldReader] Lua field '" + key + "' unreadable as " + type.Name + " (" + reason
            + "). C# uses its fallback value. Check the Lua side for a renamed or removed field."
            + " Further failures of this key are not logged.");
    }
}
