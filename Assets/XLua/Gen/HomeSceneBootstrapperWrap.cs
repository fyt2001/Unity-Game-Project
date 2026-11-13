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
    public class HomeSceneBootstrapperWrap 
    {
        public static void __Register(RealStatePtr L)
        {
			ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			System.Type type = typeof(HomeSceneBootstrapper);
			Utils.BeginObjectRegister(type, L, translator, 0, 5, 22, 22);
			
			Utils.RegisterFunc(L, Utils.METHOD_IDX, "BindJoystick", _m_BindJoystick);
			Utils.RegisterFunc(L, Utils.METHOD_IDX, "GetJoystick", _m_GetJoystick);
			Utils.RegisterFunc(L, Utils.METHOD_IDX, "SetJoystickInput", _m_SetJoystickInput);
			Utils.RegisterFunc(L, Utils.METHOD_IDX, "GetPlayerTransform", _m_GetPlayerTransform);
			Utils.RegisterFunc(L, Utils.METHOD_IDX, "GetSceneCamera", _m_GetSceneCamera);
			
			
			Utils.RegisterFunc(L, Utils.GETTER_IDX, "sceneCamera", _g_get_sceneCamera);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "groundSize", _g_get_groundSize);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "playBounds", _g_get_playBounds);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "playerSize", _g_get_playerSize);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "playerColor", _g_get_playerColor);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "playerModelPrefab", _g_get_playerModelPrefab);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "enemyModelPrefab", _g_get_enemyModelPrefab);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "bulletPlayerPrefab", _g_get_bulletPlayerPrefab);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "bulletEnemyPrefab", _g_get_bulletEnemyPrefab);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "dropWeaponPrefab", _g_get_dropWeaponPrefab);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "dropMaterialPrefab", _g_get_dropMaterialPrefab);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "dropItemPrefab", _g_get_dropItemPrefab);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "followLerp", _g_get_followLerp);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "cameraHeight", _g_get_cameraHeight);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "cameraDepth", _g_get_cameraDepth);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "playerMoveSpeed", _g_get_playerMoveSpeed);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "playerMaxHp", _g_get_playerMaxHp);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "playerAtk", _g_get_playerAtk);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "startBattle", _g_get_startBattle);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "portalSceneName", _g_get_portalSceneName);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "portalTriggerRadius", _g_get_portalTriggerRadius);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "portalFallbackSceneName", _g_get_portalFallbackSceneName);
            
			Utils.RegisterFunc(L, Utils.SETTER_IDX, "sceneCamera", _s_set_sceneCamera);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "groundSize", _s_set_groundSize);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "playBounds", _s_set_playBounds);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "playerSize", _s_set_playerSize);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "playerColor", _s_set_playerColor);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "playerModelPrefab", _s_set_playerModelPrefab);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "enemyModelPrefab", _s_set_enemyModelPrefab);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "bulletPlayerPrefab", _s_set_bulletPlayerPrefab);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "bulletEnemyPrefab", _s_set_bulletEnemyPrefab);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "dropWeaponPrefab", _s_set_dropWeaponPrefab);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "dropMaterialPrefab", _s_set_dropMaterialPrefab);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "dropItemPrefab", _s_set_dropItemPrefab);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "followLerp", _s_set_followLerp);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "cameraHeight", _s_set_cameraHeight);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "cameraDepth", _s_set_cameraDepth);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "playerMoveSpeed", _s_set_playerMoveSpeed);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "playerMaxHp", _s_set_playerMaxHp);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "playerAtk", _s_set_playerAtk);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "startBattle", _s_set_startBattle);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "portalSceneName", _s_set_portalSceneName);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "portalTriggerRadius", _s_set_portalTriggerRadius);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "portalFallbackSceneName", _s_set_portalFallbackSceneName);
            
			
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
					
					var gen_ret = new HomeSceneBootstrapper();
					translator.Push(L, gen_ret);
                    
					return 1;
				}
				
			}
			catch(System.Exception gen_e) {
				return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
			}
            return LuaAPI.luaL_error(L, "invalid arguments to HomeSceneBootstrapper constructor!");
            
        }
        
		
        
		
        
        
        
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _m_BindJoystick(RealStatePtr L)
        {
		    try {
            
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
            
            
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
            
            
                
                {
                    VirtualJoystick _joystick = (VirtualJoystick)translator.GetObject(L, 2, typeof(VirtualJoystick));
                    
                    gen_to_be_invoked.BindJoystick( _joystick );
                    
                    
                    
                    return 0;
                }
                
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _m_GetJoystick(RealStatePtr L)
        {
		    try {
            
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
            
            
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
            
            
                
                {
                    
                        var gen_ret = gen_to_be_invoked.GetJoystick(  );
                        translator.Push(L, gen_ret);
                    
                    
                    
                    return 1;
                }
                
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _m_SetJoystickInput(RealStatePtr L)
        {
		    try {
            
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
            
            
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
            
            
                
                {
                    float _x = (float)LuaAPI.lua_tonumber(L, 2);
                    float _y = (float)LuaAPI.lua_tonumber(L, 3);
                    
                    gen_to_be_invoked.SetJoystickInput( _x, _y );
                    
                    
                    
                    return 0;
                }
                
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _m_GetPlayerTransform(RealStatePtr L)
        {
		    try {
            
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
            
            
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
            
            
                
                {
                    
                        var gen_ret = gen_to_be_invoked.GetPlayerTransform(  );
                        translator.Push(L, gen_ret);
                    
                    
                    
                    return 1;
                }
                
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _m_GetSceneCamera(RealStatePtr L)
        {
		    try {
            
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
            
            
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
            
            
                
                {
                    
                        var gen_ret = gen_to_be_invoked.GetSceneCamera(  );
                        translator.Push(L, gen_ret);
                    
                    
                    
                    return 1;
                }
                
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            
        }
        
        
        
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_sceneCamera(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
                translator.Push(L, gen_to_be_invoked.sceneCamera);
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
			
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
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
			
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
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
			
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
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
			
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
                translator.PushUnityEngineColor(L, gen_to_be_invoked.playerColor);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_playerModelPrefab(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
                translator.Push(L, gen_to_be_invoked.playerModelPrefab);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_enemyModelPrefab(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
                translator.Push(L, gen_to_be_invoked.enemyModelPrefab);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_bulletPlayerPrefab(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
                translator.Push(L, gen_to_be_invoked.bulletPlayerPrefab);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_bulletEnemyPrefab(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
                translator.Push(L, gen_to_be_invoked.bulletEnemyPrefab);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_dropWeaponPrefab(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
                translator.Push(L, gen_to_be_invoked.dropWeaponPrefab);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_dropMaterialPrefab(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
                translator.Push(L, gen_to_be_invoked.dropMaterialPrefab);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_dropItemPrefab(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
                translator.Push(L, gen_to_be_invoked.dropItemPrefab);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_followLerp(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
                LuaAPI.lua_pushnumber(L, gen_to_be_invoked.followLerp);
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
			
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
                LuaAPI.lua_pushnumber(L, gen_to_be_invoked.cameraHeight);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_cameraDepth(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
                LuaAPI.lua_pushnumber(L, gen_to_be_invoked.cameraDepth);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_playerMoveSpeed(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
                LuaAPI.lua_pushnumber(L, gen_to_be_invoked.playerMoveSpeed);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_playerMaxHp(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
                LuaAPI.lua_pushnumber(L, gen_to_be_invoked.playerMaxHp);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_playerAtk(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
                LuaAPI.lua_pushnumber(L, gen_to_be_invoked.playerAtk);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_startBattle(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
                LuaAPI.lua_pushboolean(L, gen_to_be_invoked.startBattle);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_portalSceneName(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
                LuaAPI.lua_pushstring(L, gen_to_be_invoked.portalSceneName);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_portalTriggerRadius(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
                LuaAPI.lua_pushnumber(L, gen_to_be_invoked.portalTriggerRadius);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_portalFallbackSceneName(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
                LuaAPI.lua_pushstring(L, gen_to_be_invoked.portalFallbackSceneName);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_sceneCamera(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.sceneCamera = (UnityEngine.Camera)translator.GetObject(L, 2, typeof(UnityEngine.Camera));
            
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
			
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
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
			
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
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
			
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
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
			
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
                UnityEngine.Color gen_value;translator.Get(L, 2, out gen_value);
				gen_to_be_invoked.playerColor = gen_value;
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_playerModelPrefab(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.playerModelPrefab = (UnityEngine.GameObject)translator.GetObject(L, 2, typeof(UnityEngine.GameObject));
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_enemyModelPrefab(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.enemyModelPrefab = (UnityEngine.GameObject)translator.GetObject(L, 2, typeof(UnityEngine.GameObject));
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_bulletPlayerPrefab(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.bulletPlayerPrefab = (UnityEngine.GameObject)translator.GetObject(L, 2, typeof(UnityEngine.GameObject));
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_bulletEnemyPrefab(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.bulletEnemyPrefab = (UnityEngine.GameObject)translator.GetObject(L, 2, typeof(UnityEngine.GameObject));
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_dropWeaponPrefab(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.dropWeaponPrefab = (UnityEngine.GameObject)translator.GetObject(L, 2, typeof(UnityEngine.GameObject));
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_dropMaterialPrefab(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.dropMaterialPrefab = (UnityEngine.GameObject)translator.GetObject(L, 2, typeof(UnityEngine.GameObject));
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_dropItemPrefab(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.dropItemPrefab = (UnityEngine.GameObject)translator.GetObject(L, 2, typeof(UnityEngine.GameObject));
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_followLerp(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.followLerp = (float)LuaAPI.lua_tonumber(L, 2);
            
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
			
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.cameraHeight = (float)LuaAPI.lua_tonumber(L, 2);
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_cameraDepth(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.cameraDepth = (float)LuaAPI.lua_tonumber(L, 2);
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_playerMoveSpeed(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.playerMoveSpeed = (float)LuaAPI.lua_tonumber(L, 2);
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_playerMaxHp(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.playerMaxHp = (float)LuaAPI.lua_tonumber(L, 2);
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_playerAtk(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.playerAtk = (float)LuaAPI.lua_tonumber(L, 2);
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_startBattle(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.startBattle = LuaAPI.lua_toboolean(L, 2);
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_portalSceneName(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.portalSceneName = LuaAPI.lua_tostring(L, 2);
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_portalTriggerRadius(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.portalTriggerRadius = (float)LuaAPI.lua_tonumber(L, 2);
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_portalFallbackSceneName(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                HomeSceneBootstrapper gen_to_be_invoked = (HomeSceneBootstrapper)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.portalFallbackSceneName = LuaAPI.lua_tostring(L, 2);
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
		
		
		
		
    }
}
