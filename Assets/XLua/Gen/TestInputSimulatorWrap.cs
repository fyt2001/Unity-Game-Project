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
    public class TestInputSimulatorWrap 
    {
        public static void __Register(RealStatePtr L)
        {
			ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			System.Type type = typeof(TestInputSimulator);
			Utils.BeginObjectRegister(type, L, translator, 0, 0, 5, 5);
			
			
			
			Utils.RegisterFunc(L, Utils.GETTER_IDX, "moveSpeed", _g_get_moveSpeed);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "keyUp", _g_get_keyUp);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "keyDown", _g_get_keyDown);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "keyLeft", _g_get_keyLeft);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "keyRight", _g_get_keyRight);
            
			Utils.RegisterFunc(L, Utils.SETTER_IDX, "moveSpeed", _s_set_moveSpeed);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "keyUp", _s_set_keyUp);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "keyDown", _s_set_keyDown);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "keyLeft", _s_set_keyLeft);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "keyRight", _s_set_keyRight);
            
			
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
					
					var gen_ret = new TestInputSimulator();
					translator.Push(L, gen_ret);
                    
					return 1;
				}
				
			}
			catch(System.Exception gen_e) {
				return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
			}
            return LuaAPI.luaL_error(L, "invalid arguments to TestInputSimulator constructor!");
            
        }
        
		
        
		
        
        
        
        
        
        
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_moveSpeed(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                TestInputSimulator gen_to_be_invoked = (TestInputSimulator)translator.FastGetCSObj(L, 1);
                LuaAPI.lua_pushnumber(L, gen_to_be_invoked.moveSpeed);
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
			
                TestInputSimulator gen_to_be_invoked = (TestInputSimulator)translator.FastGetCSObj(L, 1);
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
			
                TestInputSimulator gen_to_be_invoked = (TestInputSimulator)translator.FastGetCSObj(L, 1);
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
			
                TestInputSimulator gen_to_be_invoked = (TestInputSimulator)translator.FastGetCSObj(L, 1);
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
			
                TestInputSimulator gen_to_be_invoked = (TestInputSimulator)translator.FastGetCSObj(L, 1);
                translator.Push(L, gen_to_be_invoked.keyRight);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_moveSpeed(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                TestInputSimulator gen_to_be_invoked = (TestInputSimulator)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.moveSpeed = (float)LuaAPI.lua_tonumber(L, 2);
            
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
			
                TestInputSimulator gen_to_be_invoked = (TestInputSimulator)translator.FastGetCSObj(L, 1);
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
			
                TestInputSimulator gen_to_be_invoked = (TestInputSimulator)translator.FastGetCSObj(L, 1);
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
			
                TestInputSimulator gen_to_be_invoked = (TestInputSimulator)translator.FastGetCSObj(L, 1);
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
			
                TestInputSimulator gen_to_be_invoked = (TestInputSimulator)translator.FastGetCSObj(L, 1);
                UnityEngine.KeyCode gen_value;translator.Get(L, 2, out gen_value);
				gen_to_be_invoked.keyRight = gen_value;
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
		
		
		
		
    }
}
