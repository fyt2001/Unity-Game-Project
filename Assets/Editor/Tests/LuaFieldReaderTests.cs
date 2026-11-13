// S9: behaviour of LuaFieldReader (present key == LuaTable.Get, missing key warns once with the key name).
using System.Text.RegularExpressions;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;
using XLua;

namespace Game.AgentTests
{
    public class LuaFieldReaderTests
    {
        [SetUp] public void Reset() { LuaFieldReader.ResetWarnings(); }
        [TearDown] public void Clean() { LuaFieldReader.ResetWarnings(); }

        [Test]
        public void PresentFieldsMatchLuaTableGet()
        {
            using (var env = new LuaEnv())
            {
                var t = (LuaTable)env.DoString("return { hp = 12.5, isDead = true, id = 7, enemyType = 'boss' }")[0];
                Assert.AreEqual(t.Get<float>("hp"), LuaFieldReader.GetOr(t, "hp", -1f));
                Assert.AreEqual(t.Get<bool>("isDead"), LuaFieldReader.GetOr(t, "isDead", false));
                Assert.AreEqual(t.Get<double>("id"), LuaFieldReader.GetOr(t, "id", -1.0));
                Assert.AreEqual("boss", LuaFieldReader.GetOr<string>(t, "enemyType", "normal"));
                Assert.IsFalse(LuaFieldReader.HasWarned("hp"));
                t.Dispose();
            }
        }

        [Test]
        public void MissingFieldReturnsFallbackAndWarnsOnceWithKey()
        {
            using (var env = new LuaEnv())
            {
                var t = (LuaTable)env.DoString("return { }")[0];
                LogAssert.Expect(LogType.Warning, new Regex(@"\[LuaFieldReader\] Lua field 'inputX' unreadable as Single"));
                Assert.AreEqual(3f, LuaFieldReader.GetOr(t, "inputX", 3f));
                Assert.AreEqual(3f, LuaFieldReader.GetOr(t, "inputX", 3f)); // second failure: silent
                float v;
                Assert.IsFalse(LuaFieldReader.TryGet(t, "inputX", out v));
                Assert.IsTrue(LuaFieldReader.HasWarned("inputX"));
                Assert.IsNull(LuaFieldReader.GetOr<string>(t, "enemyType", null), "nil string is a valid read (C# applies ?? itself)");
                // stack stays balanced: a later read still works
                env.DoString("__probe = { x = 4 }");
                var probe = env.Global.Get<LuaTable>("__probe");
                Assert.AreEqual(4.0, LuaFieldReader.GetOr(probe, "x", 0.0));
                probe.Dispose();
                t.Dispose();
            }
            LogAssert.NoUnexpectedReceived();
        }
    }
}
