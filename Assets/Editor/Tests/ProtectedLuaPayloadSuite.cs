// S7-3: tests/ProtectedLuaPayloadTests.cs ported into the Editor test assembly. The test body lives in
// ProtectedLuaPayloadTests.cs next to this file (copied verbatim, still runnable standalone via Main()).
using System;
using System.IO;
using NUnit.Framework;

namespace Game.AgentTests
{
    public class ProtectedLuaPayloadSuite
    {
        [Test]
        public void StandaloneSuiteReturnsZero()
        {
            var output = new StringWriter();
            TextWriter oldOut = Console.Out, oldErr = Console.Error;
            Console.SetOut(output);
            Console.SetError(output);
            int code;
            try { code = ProtectedLuaPayloadTests.Main(); }
            finally { Console.SetOut(oldOut); Console.SetError(oldErr); }
            Assert.AreEqual(0, code, output.ToString());
            StringAssert.Contains("PASS", output.ToString());
        }
    }
}
