// Proves that a failing test turns tools/unity_test.ps1 red. Passes unless AGENT_SELFTEST_FAIL=1
// (set only by: unity_test.ps1 -SelfTest, which filters to this fixture and expects a non-zero exit).
using System;
using NUnit.Framework;

namespace Game.AgentTests
{
    public class AgentSelfTest
    {
        [Test]
        public void DeliberateFailureOnlyWhenRequested()
        {
            if (Environment.GetEnvironmentVariable("AGENT_SELFTEST_FAIL") != "1") Assert.Pass("self-test not requested");
            Assert.Fail("AGENT_SELFTEST_FAIL=1: deliberate failure so unity_test.ps1 must exit non-zero");
        }
    }
}
