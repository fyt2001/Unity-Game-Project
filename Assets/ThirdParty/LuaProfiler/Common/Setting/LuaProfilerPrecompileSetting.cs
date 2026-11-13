/*
               #########
              ############
              #############
             ##  ###########
            ###  ###### #####
            ### #######   ####
           ###  ########## ####
          ####  ########### ####
         ####   ###########  #####
        #####   ### ########   #####
       #####   ###   ########   ######
      ######   ###  ###########   ######
     ######   #### ##############  ######
    #######  #####################  ######
    #######  ######################  ######
   #######  ###### #################  ######
   #######  ###### ###### #########   ######
   #######    ##  ######   ######     ######
   #######        ######    #####     #####
    ######        #####     #####     ####
     #####        ####      #####     ###
      #####       ###        ###      #
        ###       ###        ###
         ##       ###        ###
__________#_______####_______####______________
                我们的未来没有BUG
* ==============================================================================
* Filename: LuaProfilerPrecompileSetting.cs
* Created:  2020/4/10 11:01:22
* Author:   エル・プサイ・コングリィ
* Purpose:
* ==============================================================================
*/

#if UNITY_EDITOR_WIN

#if UNITY_EDITOR_WIN || USE_LUA_PROFILER
namespace MikuLuaProfiler
{
    using System;
    using System.Collections.Generic;
    using System.IO;
    using UnityEngine;
#if UNITY_EDITOR
    using UnityEditor;
#endif

    [Serializable]
    public class PreCompileFolderInfo
    {
        public string scriptFolder;
        public List<string> lastModifyDictKeys = new List<string>();
        public List<long> lastModifyDictValues = new List<long>();

        public Dictionary<string, long> GetDict()
        {
            Dictionary<string, long> lastModifyDict = new Dictionary<string, long>();
            for (int i = 0, imax = lastModifyDictKeys.Count; i < imax; i++)
            {
                lastModifyDict[lastModifyDictKeys[i]] = lastModifyDictValues[i];
            }
            return lastModifyDict;
        }
        public void SaveDict(Dictionary<string, long> lastModifyDict)
        {
            foreach (var item in lastModifyDict)
            {
                lastModifyDictKeys.Add(item.Key);
                lastModifyDictValues.Add(item.Value);
            }
        }
        public void ClearDict()
        {
            lastModifyDictKeys.Clear();
            lastModifyDictValues.Clear();
        }
    }

    public class LuaProfilerPrecompileSetting : ScriptableObject
    {
        #region instance
        private static LuaProfilerPrecompileSetting instance;
        public static LuaProfilerPrecompileSetting Instance
        {
            get
            {
                if (instance == null)
                {
                    instance = AssetDatabase.LoadAssetAtPath<LuaProfilerPrecompileSetting>("Assets/LuaProfilerPrecompileSetting.asset");
                    if (instance == null)
                    {
                        UnityEngine.Debug.Log("Lua Profiler: cannot find integration settings, creating default settings");
                        instance = CreateInstance<LuaProfilerPrecompileSetting>();
                        instance.name = "Lua Profiler LuaDeepProfiler Setting";
#if UNITY_EDITOR
                        AssetDatabase.CreateAsset(instance, "Assets/LuaProfilerPrecompileSetting.asset");
#endif
                    }
                }
                return instance;
            }
        }
        #endregion

        #region memeber
        public List<PreCompileFolderInfo> luaDirList = new List<PreCompileFolderInfo>();
        public string outFolder = "LuaOut";
        public string luaSuffix = "*.lua";
        public List<string> luaFilterDirList = new List<string>();

        public bool CheckIsFilterDir(string outPath)
        {
            foreach (var item in luaFilterDirList)
            {
                if (outPath.Contains(item))
                {
                    return true;
                }
                ;
            }
            return false;
        }
        #endregion

        #region static
        public static bool CompileLuaScript(bool showProcess)
        {
            Debug.LogWarning("Lua Profiler: on-disk precompilation is disabled; use Deep Lua in-memory sampling.");
            return false;
        }
        public static string MakePathRelative(string path)
        {
            if (string.IsNullOrEmpty(path))
                return "";
            string fullPath = Path.GetFullPath(path);
            string fullProjectPath = Path.GetFullPath(Environment.CurrentDirectory + Path.DirectorySeparatorChar);

            // If the path contains the Unity project path remove it and return the result
            if (fullPath.Contains(fullProjectPath))
            {
                return fullPath.Replace(fullProjectPath, "");
            }
            // If not, attempt to find a relative path on the same drive
            else if (Path.GetPathRoot(fullPath) == Path.GetPathRoot(fullProjectPath))
            {
                // Remove trailing slash from project path for split count simplicity
                if (fullProjectPath.EndsWith(Path.DirectorySeparatorChar.ToString(), StringComparison.CurrentCulture)) fullProjectPath = fullProjectPath.Substring(0, fullProjectPath.Length - 1);

                string[] fullPathSplit = fullPath.Split(Path.DirectorySeparatorChar);
                string[] projectPathSplit = fullProjectPath.Split(Path.DirectorySeparatorChar);
                int minNumSplits = Mathf.Min(fullPathSplit.Length, projectPathSplit.Length);
                int numCommonElements = 0;
                for (int i = 0; i < minNumSplits; i++)
                {
                    if (fullPathSplit[i] == projectPathSplit[i])
                    {
                        numCommonElements++;
                    }
                    else
                    {
                        break;
                    }
                }
                string result = "";
                int fullPathSplitLength = fullPathSplit.Length;
                for (int i = numCommonElements; i < fullPathSplitLength; i++)
                {
                    result += fullPathSplit[i];
                    if (i < fullPathSplitLength - 1)
                    {
                        result += '/';
                    }
                }

                int numAdditionalElementsInProjectPath = projectPathSplit.Length - numCommonElements;
                for (int i = 0; i < numAdditionalElementsInProjectPath; i++)
                {
                    result = "../" + result;
                }

                return result;

            }
            // Otherwise return the full path
            return fullPath;
        }
        public static string GetCommonPlatformPath(string path)
        {
            if (string.IsNullOrEmpty(path))
            {
                return path;
            }

            return path.Replace('\\', '/');
        }
        #endregion
    }
}

#endif
#endif
