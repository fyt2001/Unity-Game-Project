using System;
using UnityEngine;
using UnityEngine.UI;
using XLua;

public static class PlatformUIEventChecks
{
    public static string Run()
    {
        using (var lua = new LuaEnv())
        {
            lua.Global.Set("vector", Vector2.one);
            Check(lua, new Button.ButtonClickedEvent(), "");
            Check(lua, new Toggle.ToggleEvent(), "true");
            Check(lua, new Slider.SliderEvent(), "1");
            Check(lua, new ScrollRect.ScrollRectEvent(), "vector");
            Check(lua, new InputField.OnChangeEvent(), "'text'");
            Check(lua, new TMPro.TMP_InputField.SubmitEvent(), "'text'");
        }
        return "Lua UI event checks passed: 6. Editor only; verify Player separately.";
    }

    private static void Check(LuaEnv lua, object evt, string argument)
    {
        lua.Global.Set("evt", evt);
        lua.DoString(@"
            local count = 0
            local callback = function() count = count + 1 end
            evt:AddListener(callback)
            evt:Invoke(" + argument + @")
            assert(count == 1, 'First listener invocation')
            evt:RemoveListener(callback)
            evt:Invoke(" + argument + @")
            assert(count == 1, 'Listener still active after removal')
            evt:AddListener(callback)
            evt:Invoke(" + argument + @")
            assert(count == 2, 'Rebind did not invoke exactly once')
            evt:RemoveListener(callback)
            evt:Invoke(" + argument + @")
            assert(count == 2, 'Rebound listener was not removed')
        ", "UIEventVerification");
        lua.Global.Set<string, object>("evt", null);
    }
}
