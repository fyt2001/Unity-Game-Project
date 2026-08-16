#if USE_UNI_LUA
using LuaAPI = UniLua.Lua;
using RealStatePtr = UniLua.ILuaState;
using LuaCSFunction = UniLua.CSharpFunctionDelegate;
#else
using LuaAPI = XLua.LuaDLL.Lua;
using RealStatePtr = System.IntPtr;
using LuaCSFunction = XLua.LuaDLL.lua_CSFunction;
#endif

using XLua;
using System.Collections.Generic;


namespace XLua.CSObjectWrap
{
    using Utils = XLua.Utils;
    public class BattleViewWrap 
    {
        public static void __Register(RealStatePtr L)
        {
			ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			System.Type type = typeof(BattleView);
			Utils.BeginObjectRegister(type, L, translator, 0, 0, 14, 14);
			
			
			
			Utils.RegisterFunc(L, Utils.GETTER_IDX, "createSceneOnStart", _g_get_createSceneOnStart);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "groundSize", _g_get_groundSize);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "playBounds", _g_get_playBounds);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "playerSize", _g_get_playerSize);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "playerColor", _g_get_playerColor);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "inputScale", _g_get_inputScale);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "keyUp", _g_get_keyUp);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "keyDown", _g_get_keyDown);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "keyLeft", _g_get_keyLeft);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "keyRight", _g_get_keyRight);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "cameraFollow", _g_get_cameraFollow);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "cameraLerp", _g_get_cameraLerp);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "cameraHeight", _g_get_cameraHeight);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "cameraBack", _g_get_cameraBack);
            
			Utils.RegisterFunc(L, Utils.SETTER_IDX, "createSceneOnStart", _s_set_createSceneOnStart);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "groundSize", _s_set_groundSize);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "playBounds", _s_set_playBounds);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "playerSize", _s_set_playerSize);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "playerColor", _s_set_playerColor);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "inputScale", _s_set_inputScale);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "keyUp", _s_set_keyUp);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "keyDown", _s_set_keyDown);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "keyLeft", _s_set_keyLeft);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "keyRight", _s_set_keyRight);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "cameraFollow", _s_set_cameraFollow);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "cameraLerp", _s_set_cameraLerp);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "cameraHeight", _s_set_cameraHeight);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "cameraBack", _s_set_cameraBack);
            
			
			Utils.EndObjectRegister(type, L, translator, null, null,
			    null, null, null);

		    Utils.BeginClassRegister(type, L, __CreateInstance, 1, 0, 0);
			
			
            
			
			
			
			Utils.EndClassRegister(type, L, translator);
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int __CreateInstance(RealStatePtr L)
        {
            
			try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
				if(LuaAPI.lua_gettop(L) == 1)
				{
					
					var gen_ret = new BattleView();
					translator.Push(L, gen_ret);
                    
					return 1;
				}
				
			}
			catch(System.Exception gen_e) {
				return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
			}
            return LuaAPI.luaL_error(L, "invalid arguments to BattleView constructor!");
            
        }
        
		
        
		
        
        
        
        
        
        
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_createSceneOnStart(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                BattleView gen_to_be_invoked = (BattleView)translator.FastGetCSObj(L, 1);
                LuaAPI.lua_pushboolean(L, gen_to_be_invoked.createSceneOnStart);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_groundSize(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                BattleView gen_to_be_invoked = (BattleView)translator.FastGetCSObj(L, 1);
                LuaAPI.lua_pushnumber(L, gen_to_be_invoked.groundSize);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_playBounds(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                BattleView gen_to_be_invoked = (BattleView)translator.FastGetCSObj(L, 1);
                LuaAPI.lua_pushnumber(L, gen_to_be_invoked.playBounds);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_playerSize(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                BattleView gen_to_be_invoked = (BattleView)translator.FastGetCSObj(L, 1);
                LuaAPI.lua_pushnumber(L, gen_to_be_invoked.playerSize);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_playerColor(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                BattleView gen_to_be_invoked = (BattleView)translator.FastGetCSObj(L, 1);
                translator.PushUnityEngineColor(L, gen_to_be_invoked.playerColor);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_inputScale(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                BattleView gen_to_be_invoked = (BattleView)translator.FastGetCSObj(L, 1);
                LuaAPI.lua_pushnumber(L, gen_to_be_invoked.inputScale);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_keyUp(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                BattleView gen_to_be_invoked = (BattleView)translator.FastGetCSObj(L, 1);
                translator.Push(L, gen_to_be_invoked.keyUp);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_keyDown(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                BattleView gen_to_be_invoked = (BattleView)translator.FastGetCSObj(L, 1);
                translator.Push(L, gen_to_be_invoked.keyDown);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_keyLeft(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                BattleView gen_to_be_invoked = (BattleView)translator.FastGetCSObj(L, 1);
                translator.Push(L, gen_to_be_invoked.keyLeft);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_keyRight(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                BattleView gen_to_be_invoked = (BattleView)translator.FastGetCSObj(L, 1);
                translator.Push(L, gen_to_be_invoked.keyRight);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_cameraFollow(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                BattleView gen_to_be_invoked = (BattleView)translator.FastGetCSObj(L, 1);
                LuaAPI.lua_pushboolean(L, gen_to_be_invoked.cameraFollow);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_cameraLerp(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                BattleView gen_to_be_invoked = (BattleView)translator.FastGetCSObj(L, 1);
                LuaAPI.lua_pushnumber(L, gen_to_be_invoked.cameraLerp);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_cameraHeight(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                BattleView gen_to_be_invoked = (BattleView)translator.FastGetCSObj(L, 1);
                LuaAPI.lua_pushnumber(L, gen_to_be_invoked.cameraHeight);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_cameraBack(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                BattleView gen_to_be_invoked = (BattleView)translator.FastGetCSObj(L, 1);
                LuaAPI.lua_pushnumber(L, gen_to_be_invoked.cameraBack);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_createSceneOnStart(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                BattleView gen_to_be_invoked = (BattleView)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.createSceneOnStart = LuaAPI.lua_toboolean(L, 2);
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_groundSize(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                BattleView gen_to_be_invoked = (BattleView)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.groundSize = (float)LuaAPI.lua_tonumber(L, 2);
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_playBounds(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                BattleView gen_to_be_invoked = (BattleView)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.playBounds = (float)LuaAPI.lua_tonumber(L, 2);
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_playerSize(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                BattleView gen_to_be_invoked = (BattleView)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.playerSize = (float)LuaAPI.lua_tonumber(L, 2);
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_playerColor(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                BattleView gen_to_be_invoked = (BattleView)translator.FastGetCSObj(L, 1);
                UnityEngine.Color gen_value;translator.Get(L, 2, out gen_value);
				gen_to_be_invoked.playerColor = gen_value;
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_inputScale(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                BattleView gen_to_be_invoked = (BattleView)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.inputScale = (float)LuaAPI.lua_tonumber(L, 2);
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_keyUp(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                BattleView gen_to_be_invoked = (BattleView)translator.FastGetCSObj(L, 1);
                UnityEngine.KeyCode gen_value;translator.Get(L, 2, out gen_value);
				gen_to_be_invoked.keyUp = gen_value;
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_keyDown(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                BattleView gen_to_be_invoked = (BattleView)translator.FastGetCSObj(L, 1);
                UnityEngine.KeyCode gen_value;translator.Get(L, 2, out gen_value);
				gen_to_be_invoked.keyDown = gen_value;
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_keyLeft(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                BattleView gen_to_be_invoked = (BattleView)translator.FastGetCSObj(L, 1);
                UnityEngine.KeyCode gen_value;translator.Get(L, 2, out gen_value);
				gen_to_be_invoked.keyLeft = gen_value;
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_keyRight(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                BattleView gen_to_be_invoked = (BattleView)translator.FastGetCSObj(L, 1);
                UnityEngine.KeyCode gen_value;translator.Get(L, 2, out gen_value);
				gen_to_be_invoked.keyRight = gen_value;
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_cameraFollow(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                BattleView gen_to_be_invoked = (BattleView)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.cameraFollow = LuaAPI.lua_toboolean(L, 2);
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_cameraLerp(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                BattleView gen_to_be_invoked = (BattleView)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.cameraLerp = (float)LuaAPI.lua_tonumber(L, 2);
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_cameraHeight(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                BattleView gen_to_be_invoked = (BattleView)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.cameraHeight = (float)LuaAPI.lua_tonumber(L, 2);
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_cameraBack(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                BattleView gen_to_be_invoked = (BattleView)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.cameraBack = (float)LuaAPI.lua_tonumber(L, 2);
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
		
		
		
		
    }
}
