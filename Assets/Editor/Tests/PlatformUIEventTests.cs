// S7-1: PlatformUIEventChecks.Run() as a [Test] (logic unchanged: the six UGUI event x Lua callback checks).
using NUnit.Framework;

namespace Game.AgentTests
{
    public class PlatformUIEventTests
    {
        [Test]
        public void SixUguiEventsAddInvokeRemoveLuaCallbacks()
        {
            string result = PlatformUIEventChecks.Run();
            StringAssert.StartsWith("Lua UI event checks passed: 6", result);
        }
    }
}
