using System;
using System.IO;
using UnityEditor;
using UnityEngine;

public static class PlatformBuildVerification
{
    [Serializable]
    private sealed class Result
    {
        public string target;
        public string output;
        public string status;
        public string error;
        public string startedUtc;
        public string finishedUtc;
    }

    // Disk-backed status remains readable while BuildPlayer blocks the editor's tool connection.
    public static string StartWebGL()
    {
        return Start(BuildTarget.WebGL);
    }

    public static string StartWindows()
    {
        return Start(BuildTarget.StandaloneWindows64);
    }

    private static string Start(BuildTarget target)
    {
        BuildTools.ValidateBuildTarget(target);
        string directory = Path.GetFullPath(Path.Combine("Builds", "Verification",
            target.ToString().ToLowerInvariant() + "_" + DateTime.UtcNow.ToString("yyyyMMdd_HHmmss") + "_" + Guid.NewGuid().ToString("N")));
        Directory.CreateDirectory(directory);
        string statusPath = Path.Combine(directory, "result.json");
        string output = Path.Combine(directory, target == BuildTarget.WebGL ? "Player" : "Player/Game.exe");
        var result = new Result { target = target.ToString(), output = output, status = "queued" };
        Save(statusPath, result);
        EditorApplication.delayCall += () =>
        {
            result.status = "running";
            result.startedUtc = DateTime.UtcNow.ToString("O");
            Save(statusPath, result);
            try
            {
                BuildTools.BuildPreparedPlayer(target, result.output, BuildOptions.None);
                string expected = target == BuildTarget.WebGL ? Path.Combine(result.output, "index.html") : result.output;
                if (!File.Exists(expected))
                    throw new InvalidOperationException("Successful build is missing " + expected);
                result.status = "succeeded";
            }
            catch (Exception e)
            {
                result.status = "failed";
                result.error = e.ToString();
            }
            finally
            {
                result.finishedUtc = DateTime.UtcNow.ToString("O");
                Save(statusPath, result);
            }
        };
        return statusPath;
    }

    private static void Save(string path, Result result)
    {
        File.WriteAllText(path, JsonUtility.ToJson(result, true));
    }
}
