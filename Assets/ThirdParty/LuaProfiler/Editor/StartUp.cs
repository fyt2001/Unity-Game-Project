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
* Filename: StartUp
* Created:  2018/7/2 11:36:16
* Author:   エル・プサイ・コングリィ
* Purpose:
* ==============================================================================
*/

#if UNITY_EDITOR_WIN
namespace MikuLuaProfiler
{
    // Legacy API kept for window compatibility; this migration never rewrites assemblies or defines.
    public static class InjectMethods
    {
        public static void InjectAllMethods() { UnityEngine.Debug.LogWarning("Lua Profiler: Deep Mono is disabled."); }
        public static void Recompile() { UnityEngine.Debug.LogWarning("Lua Profiler: assembly rewriting is disabled."); }
    }
}
#endif
