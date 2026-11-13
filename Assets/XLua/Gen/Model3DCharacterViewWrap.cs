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
    public class Model3DCharacterViewWrap 
    {
        public static void __Register(RealStatePtr L)
        {
			ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			System.Type type = typeof(Model3DCharacterView);
			Utils.BeginObjectRegister(type, L, translator, 0, 9, 38, 38);
			
			Utils.RegisterFunc(L, Utils.METHOD_IDX, "FlashHurt", _m_FlashHurt);
			Utils.RegisterFunc(L, Utils.METHOD_IDX, "EquipCombatWeapon", _m_EquipCombatWeapon);
			Utils.RegisterFunc(L, Utils.METHOD_IDX, "BeginCombatAttack", _m_BeginCombatAttack);
			Utils.RegisterFunc(L, Utils.METHOD_IDX, "ReleaseCombatAttack", _m_ReleaseCombatAttack);
			Utils.RegisterFunc(L, Utils.METHOD_IDX, "GetCombatMuzzlePosition", _m_GetCombatMuzzlePosition);
			Utils.RegisterFunc(L, Utils.METHOD_IDX, "ResetCombatWeapon", _m_ResetCombatWeapon);
			Utils.RegisterFunc(L, Utils.METHOD_IDX, "SetCombatPaused", _m_SetCombatPaused);
			Utils.RegisterFunc(L, Utils.METHOD_IDX, "Play", _m_Play);
			Utils.RegisterFunc(L, Utils.METHOD_IDX, "SetFlip", _m_SetFlip);
			
			
			Utils.RegisterFunc(L, Utils.GETTER_IDX, "modelPrefab", _g_get_modelPrefab);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "modelTargetHeight", _g_get_modelTargetHeight);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "autoOrientFromBones", _g_get_autoOrientFromBones);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "autoUpright", _g_get_autoUpright);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "flipUpright", _g_get_flipUpright);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "autoFaceForward", _g_get_autoFaceForward);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "flipForward", _g_get_flipForward);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "modelYaw", _g_get_modelYaw);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "modelRotation", _g_get_modelRotation);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "bodyColor", _g_get_bodyColor);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "headColor", _g_get_headColor);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "bobSpeed", _g_get_bobSpeed);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "bobHeight", _g_get_bobHeight);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "spinSpeed", _g_get_spinSpeed);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "animate", _g_get_animate);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "proceduralBones", _g_get_proceduralBones);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "walkCycleSpeed", _g_get_walkCycleSpeed);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "legSwingAngle", _g_get_legSwingAngle);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "kneeBendAngle", _g_get_kneeBendAngle);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "armSwingAngle", _g_get_armSwingAngle);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "chibiStyle", _g_get_chibiStyle);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "walkBounce", _g_get_walkBounce);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "walkSway", _g_get_walkSway);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "walkLean", _g_get_walkLean);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "autoSwingAxis", _g_get_autoSwingAxis);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "swingAxis", _g_get_swingAxis);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "animatorController", _g_get_animatorController);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "avatar", _g_get_avatar);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "swordWeapon", _g_get_swordWeapon);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "pistolWeapon", _g_get_pistolWeapon);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "hideMeshes", _g_get_hideMeshes);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "fixDarkMaterial", _g_get_fixDarkMaterial);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "materialOverride", _g_get_materialOverride);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "albedoOverride", _g_get_albedoOverride);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "albedoTint", _g_get_albedoTint);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "hurtColor", _g_get_hurtColor);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "hurtFlashTime", _g_get_hurtFlashTime);
            Utils.RegisterFunc(L, Utils.GETTER_IDX, "hurtPunchScale", _g_get_hurtPunchScale);
            
			Utils.RegisterFunc(L, Utils.SETTER_IDX, "modelPrefab", _s_set_modelPrefab);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "modelTargetHeight", _s_set_modelTargetHeight);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "autoOrientFromBones", _s_set_autoOrientFromBones);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "autoUpright", _s_set_autoUpright);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "flipUpright", _s_set_flipUpright);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "autoFaceForward", _s_set_autoFaceForward);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "flipForward", _s_set_flipForward);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "modelYaw", _s_set_modelYaw);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "modelRotation", _s_set_modelRotation);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "bodyColor", _s_set_bodyColor);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "headColor", _s_set_headColor);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "bobSpeed", _s_set_bobSpeed);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "bobHeight", _s_set_bobHeight);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "spinSpeed", _s_set_spinSpeed);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "animate", _s_set_animate);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "proceduralBones", _s_set_proceduralBones);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "walkCycleSpeed", _s_set_walkCycleSpeed);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "legSwingAngle", _s_set_legSwingAngle);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "kneeBendAngle", _s_set_kneeBendAngle);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "armSwingAngle", _s_set_armSwingAngle);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "chibiStyle", _s_set_chibiStyle);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "walkBounce", _s_set_walkBounce);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "walkSway", _s_set_walkSway);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "walkLean", _s_set_walkLean);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "autoSwingAxis", _s_set_autoSwingAxis);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "swingAxis", _s_set_swingAxis);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "animatorController", _s_set_animatorController);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "avatar", _s_set_avatar);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "swordWeapon", _s_set_swordWeapon);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "pistolWeapon", _s_set_pistolWeapon);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "hideMeshes", _s_set_hideMeshes);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "fixDarkMaterial", _s_set_fixDarkMaterial);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "materialOverride", _s_set_materialOverride);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "albedoOverride", _s_set_albedoOverride);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "albedoTint", _s_set_albedoTint);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "hurtColor", _s_set_hurtColor);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "hurtFlashTime", _s_set_hurtFlashTime);
            Utils.RegisterFunc(L, Utils.SETTER_IDX, "hurtPunchScale", _s_set_hurtPunchScale);
            
			
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
					
					var gen_ret = new Model3DCharacterView();
					translator.Push(L, gen_ret);
                    
					return 1;
				}
				
			}
			catch(System.Exception gen_e) {
				return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
			}
            return LuaAPI.luaL_error(L, "invalid arguments to Model3DCharacterView constructor!");
            
        }
        
		
        
		
        
        
        
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _m_FlashHurt(RealStatePtr L)
        {
		    try {
            
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
            
            
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
            
            
                
                {
                    
                    gen_to_be_invoked.FlashHurt(  );
                    
                    
                    
                    return 0;
                }
                
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _m_EquipCombatWeapon(RealStatePtr L)
        {
		    try {
            
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
            
            
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
            
            
                
                {
                    int _pattern = LuaAPI.xlua_tointeger(L, 2);
                    
                    gen_to_be_invoked.EquipCombatWeapon( _pattern );
                    
                    
                    
                    return 0;
                }
                
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _m_BeginCombatAttack(RealStatePtr L)
        {
		    try {
            
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
            
            
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
            
            
                
                {
                    int _pattern = LuaAPI.xlua_tointeger(L, 2);
                    float _dirX = (float)LuaAPI.lua_tonumber(L, 3);
                    float _dirY = (float)LuaAPI.lua_tonumber(L, 4);
                    float _effectiveInterval = (float)LuaAPI.lua_tonumber(L, 5);
                    
                        var gen_ret = gen_to_be_invoked.BeginCombatAttack( _pattern, _dirX, _dirY, _effectiveInterval );
                        LuaAPI.lua_pushnumber(L, gen_ret);
                    
                    
                    
                    return 1;
                }
                
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _m_ReleaseCombatAttack(RealStatePtr L)
        {
		    try {
            
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
            
            
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
            
            
                
                {
                    int _pattern = LuaAPI.xlua_tointeger(L, 2);
                    
                    gen_to_be_invoked.ReleaseCombatAttack( _pattern );
                    
                    
                    
                    return 0;
                }
                
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _m_GetCombatMuzzlePosition(RealStatePtr L)
        {
		    try {
            
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
            
            
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
            
            
                
                {
                    
                        var gen_ret = gen_to_be_invoked.GetCombatMuzzlePosition(  );
                        translator.PushUnityEngineVector3(L, gen_ret);
                    
                    
                    
                    return 1;
                }
                
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _m_ResetCombatWeapon(RealStatePtr L)
        {
		    try {
            
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
            
            
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
            
            
                
                {
                    
                    gen_to_be_invoked.ResetCombatWeapon(  );
                    
                    
                    
                    return 0;
                }
                
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _m_SetCombatPaused(RealStatePtr L)
        {
		    try {
            
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
            
            
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
            
            
                
                {
                    bool _paused = LuaAPI.lua_toboolean(L, 2);
                    
                    gen_to_be_invoked.SetCombatPaused( _paused );
                    
                    
                    
                    return 0;
                }
                
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _m_Play(RealStatePtr L)
        {
		    try {
            
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
            
            
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
            
            
			    int gen_param_count = LuaAPI.lua_gettop(L);
            
                if(gen_param_count == 3&& translator.Assignable<CharacterState>(L, 2)&& LuaTypes.LUA_TBOOLEAN == LuaAPI.lua_type(L, 3)) 
                {
                    CharacterState _state;translator.Get(L, 2, out _state);
                    bool _loop = LuaAPI.lua_toboolean(L, 3);
                    
                    gen_to_be_invoked.Play( _state, _loop );
                    
                    
                    
                    return 0;
                }
                if(gen_param_count == 2&& translator.Assignable<CharacterState>(L, 2)) 
                {
                    CharacterState _state;translator.Get(L, 2, out _state);
                    
                    gen_to_be_invoked.Play( _state );
                    
                    
                    
                    return 0;
                }
                
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            
            return LuaAPI.luaL_error(L, "invalid arguments to Model3DCharacterView.Play!");
            
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _m_SetFlip(RealStatePtr L)
        {
		    try {
            
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
            
            
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
            
            
                
                {
                    bool _flip = LuaAPI.lua_toboolean(L, 2);
                    
                    gen_to_be_invoked.SetFlip( _flip );
                    
                    
                    
                    return 0;
                }
                
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            
        }
        
        
        
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_modelPrefab(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                translator.Push(L, gen_to_be_invoked.modelPrefab);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_modelTargetHeight(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                LuaAPI.lua_pushnumber(L, gen_to_be_invoked.modelTargetHeight);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_autoOrientFromBones(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                LuaAPI.lua_pushboolean(L, gen_to_be_invoked.autoOrientFromBones);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_autoUpright(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                LuaAPI.lua_pushboolean(L, gen_to_be_invoked.autoUpright);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_flipUpright(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                LuaAPI.lua_pushboolean(L, gen_to_be_invoked.flipUpright);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_autoFaceForward(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                LuaAPI.lua_pushboolean(L, gen_to_be_invoked.autoFaceForward);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_flipForward(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                LuaAPI.lua_pushboolean(L, gen_to_be_invoked.flipForward);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_modelYaw(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                LuaAPI.lua_pushnumber(L, gen_to_be_invoked.modelYaw);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_modelRotation(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                translator.PushUnityEngineVector3(L, gen_to_be_invoked.modelRotation);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_bodyColor(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                translator.PushUnityEngineColor(L, gen_to_be_invoked.bodyColor);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_headColor(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                translator.PushUnityEngineColor(L, gen_to_be_invoked.headColor);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_bobSpeed(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                LuaAPI.lua_pushnumber(L, gen_to_be_invoked.bobSpeed);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_bobHeight(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                LuaAPI.lua_pushnumber(L, gen_to_be_invoked.bobHeight);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_spinSpeed(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                LuaAPI.lua_pushnumber(L, gen_to_be_invoked.spinSpeed);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_animate(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                LuaAPI.lua_pushboolean(L, gen_to_be_invoked.animate);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_proceduralBones(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                LuaAPI.lua_pushboolean(L, gen_to_be_invoked.proceduralBones);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_walkCycleSpeed(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                LuaAPI.lua_pushnumber(L, gen_to_be_invoked.walkCycleSpeed);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_legSwingAngle(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                LuaAPI.lua_pushnumber(L, gen_to_be_invoked.legSwingAngle);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_kneeBendAngle(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                LuaAPI.lua_pushnumber(L, gen_to_be_invoked.kneeBendAngle);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_armSwingAngle(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                LuaAPI.lua_pushnumber(L, gen_to_be_invoked.armSwingAngle);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_chibiStyle(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                LuaAPI.lua_pushboolean(L, gen_to_be_invoked.chibiStyle);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_walkBounce(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                LuaAPI.lua_pushnumber(L, gen_to_be_invoked.walkBounce);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_walkSway(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                LuaAPI.lua_pushnumber(L, gen_to_be_invoked.walkSway);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_walkLean(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                LuaAPI.lua_pushnumber(L, gen_to_be_invoked.walkLean);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_autoSwingAxis(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                LuaAPI.lua_pushboolean(L, gen_to_be_invoked.autoSwingAxis);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_swingAxis(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                translator.PushUnityEngineVector3(L, gen_to_be_invoked.swingAxis);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_animatorController(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                translator.Push(L, gen_to_be_invoked.animatorController);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_avatar(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                translator.Push(L, gen_to_be_invoked.avatar);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_swordWeapon(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                translator.Push(L, gen_to_be_invoked.swordWeapon);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_pistolWeapon(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                translator.Push(L, gen_to_be_invoked.pistolWeapon);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_hideMeshes(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                LuaAPI.lua_pushstring(L, gen_to_be_invoked.hideMeshes);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_fixDarkMaterial(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                LuaAPI.lua_pushboolean(L, gen_to_be_invoked.fixDarkMaterial);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_materialOverride(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                translator.Push(L, gen_to_be_invoked.materialOverride);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_albedoOverride(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                translator.Push(L, gen_to_be_invoked.albedoOverride);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_albedoTint(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                translator.PushUnityEngineColor(L, gen_to_be_invoked.albedoTint);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_hurtColor(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                translator.PushUnityEngineColor(L, gen_to_be_invoked.hurtColor);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_hurtFlashTime(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                LuaAPI.lua_pushnumber(L, gen_to_be_invoked.hurtFlashTime);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _g_get_hurtPunchScale(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                LuaAPI.lua_pushnumber(L, gen_to_be_invoked.hurtPunchScale);
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 1;
        }
        
        
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_modelPrefab(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.modelPrefab = (UnityEngine.GameObject)translator.GetObject(L, 2, typeof(UnityEngine.GameObject));
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_modelTargetHeight(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.modelTargetHeight = (float)LuaAPI.lua_tonumber(L, 2);
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_autoOrientFromBones(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.autoOrientFromBones = LuaAPI.lua_toboolean(L, 2);
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_autoUpright(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.autoUpright = LuaAPI.lua_toboolean(L, 2);
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_flipUpright(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.flipUpright = LuaAPI.lua_toboolean(L, 2);
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_autoFaceForward(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.autoFaceForward = LuaAPI.lua_toboolean(L, 2);
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_flipForward(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.flipForward = LuaAPI.lua_toboolean(L, 2);
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_modelYaw(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.modelYaw = (float)LuaAPI.lua_tonumber(L, 2);
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_modelRotation(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                UnityEngine.Vector3 gen_value;translator.Get(L, 2, out gen_value);
				gen_to_be_invoked.modelRotation = gen_value;
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_bodyColor(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                UnityEngine.Color gen_value;translator.Get(L, 2, out gen_value);
				gen_to_be_invoked.bodyColor = gen_value;
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_headColor(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                UnityEngine.Color gen_value;translator.Get(L, 2, out gen_value);
				gen_to_be_invoked.headColor = gen_value;
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_bobSpeed(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.bobSpeed = (float)LuaAPI.lua_tonumber(L, 2);
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_bobHeight(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.bobHeight = (float)LuaAPI.lua_tonumber(L, 2);
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_spinSpeed(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.spinSpeed = (float)LuaAPI.lua_tonumber(L, 2);
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_animate(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.animate = LuaAPI.lua_toboolean(L, 2);
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_proceduralBones(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.proceduralBones = LuaAPI.lua_toboolean(L, 2);
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_walkCycleSpeed(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.walkCycleSpeed = (float)LuaAPI.lua_tonumber(L, 2);
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_legSwingAngle(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.legSwingAngle = (float)LuaAPI.lua_tonumber(L, 2);
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_kneeBendAngle(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.kneeBendAngle = (float)LuaAPI.lua_tonumber(L, 2);
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_armSwingAngle(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.armSwingAngle = (float)LuaAPI.lua_tonumber(L, 2);
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_chibiStyle(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.chibiStyle = LuaAPI.lua_toboolean(L, 2);
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_walkBounce(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.walkBounce = (float)LuaAPI.lua_tonumber(L, 2);
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_walkSway(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.walkSway = (float)LuaAPI.lua_tonumber(L, 2);
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_walkLean(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.walkLean = (float)LuaAPI.lua_tonumber(L, 2);
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_autoSwingAxis(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.autoSwingAxis = LuaAPI.lua_toboolean(L, 2);
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_swingAxis(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                UnityEngine.Vector3 gen_value;translator.Get(L, 2, out gen_value);
				gen_to_be_invoked.swingAxis = gen_value;
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_animatorController(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.animatorController = (UnityEngine.RuntimeAnimatorController)translator.GetObject(L, 2, typeof(UnityEngine.RuntimeAnimatorController));
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_avatar(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.avatar = (UnityEngine.Avatar)translator.GetObject(L, 2, typeof(UnityEngine.Avatar));
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_swordWeapon(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.swordWeapon = (WeaponVisualDefinition)translator.GetObject(L, 2, typeof(WeaponVisualDefinition));
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_pistolWeapon(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.pistolWeapon = (WeaponVisualDefinition)translator.GetObject(L, 2, typeof(WeaponVisualDefinition));
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_hideMeshes(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.hideMeshes = LuaAPI.lua_tostring(L, 2);
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_fixDarkMaterial(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.fixDarkMaterial = LuaAPI.lua_toboolean(L, 2);
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_materialOverride(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.materialOverride = (UnityEngine.Material)translator.GetObject(L, 2, typeof(UnityEngine.Material));
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_albedoOverride(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.albedoOverride = (UnityEngine.Texture)translator.GetObject(L, 2, typeof(UnityEngine.Texture));
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_albedoTint(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                UnityEngine.Color gen_value;translator.Get(L, 2, out gen_value);
				gen_to_be_invoked.albedoTint = gen_value;
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_hurtColor(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                UnityEngine.Color gen_value;translator.Get(L, 2, out gen_value);
				gen_to_be_invoked.hurtColor = gen_value;
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_hurtFlashTime(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.hurtFlashTime = (float)LuaAPI.lua_tonumber(L, 2);
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
        [MonoPInvokeCallbackAttribute(typeof(LuaCSFunction))]
        static int _s_set_hurtPunchScale(RealStatePtr L)
        {
		    try {
                ObjectTranslator translator = ObjectTranslatorPool.Instance.Find(L);
			
                Model3DCharacterView gen_to_be_invoked = (Model3DCharacterView)translator.FastGetCSObj(L, 1);
                gen_to_be_invoked.hurtPunchScale = (float)LuaAPI.lua_tonumber(L, 2);
            
            } catch(System.Exception gen_e) {
                return LuaAPI.luaL_error(L, "c# exception:" + gen_e);
            }
            return 0;
        }
        
		
		
		
		
    }
}
