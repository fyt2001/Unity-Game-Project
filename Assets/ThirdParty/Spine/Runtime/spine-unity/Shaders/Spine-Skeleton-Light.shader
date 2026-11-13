Shader "Spine/SkeletonLight" {
	Properties {
		_Cutoff ("Shadow alpha cutoff", Range(0,1)) = 0.1
		[NoScaleOffset] _MainTex ("Main Texture", 2D) = "black" {}
		[Toggle(_STRAIGHT_ALPHA_INPUT)] _StraightAlphaInput("Straight Alpha Texture", Int) = 0
		[HideInInspector] _StencilRef("Stencil Reference", Float) = 1.0
		[Enum(UnityEngine.Rendering.CompareFunction)] _StencilComp("Stencil Comparison", Float) = 8 // Set to Always as default
        _ClipRect ("_ClipRect",Vector) = (0,0,0,0)
        _Edge ("Edge", Float) = 0

        _LightType ("Light(0:no,1:dir,2:point)", Int)=0
		[NoScaleOffset] _NormTex ("Normal Texture", 2D) = "gray" {}
        _LightDir ("Light Dir(Pos for point)", Vector) = (1,0,0,0)
        _LightPow ("Light Power", Float) = 0
        _LightColor ("Light Color", Color) = (0,0,0,1)
        _LightRange ("Light Range(point only)", Range(0,5)) = 1
        _LightAmbient ("Light Ambient(point only)", Color) = (0.2,0.2,0.2,1)
		 _LightArea ("Light Texture", 2D) = "gray" {}

		// Outline properties are drawn via custom editor.
		[HideInInspector] _OutlineWidth("Outline Width", Range(0,8)) = 3.0
		[HideInInspector] _OutlineColor("Outline Color", Color) = (1,1,0,1)
		[HideInInspector] _OutlineReferenceTexWidth("Reference Texture Width", Int) = 1024
		[HideInInspector] _ThresholdEnd("Outline Threshold", Range(0,1)) = 0.25
		[HideInInspector] _OutlineSmoothness("Outline Smoothness", Range(0,1)) = 1.0
		[HideInInspector][MaterialToggle(_USE8NEIGHBOURHOOD_ON)] _Use8Neighbourhood("Sample 8 Neighbours", Float) = 1
		[HideInInspector] _OutlineMipLevel("Outline Mip Level", Range(0,3)) = 0
	}

	SubShader {
		Tags { "Queue"="Transparent" "IgnoreProjector"="True" "RenderType"="Transparent" "PreviewType"="Plane" }

		Fog { Mode Off }
		Cull Off
		ZWrite Off
		Blend One OneMinusSrcAlpha
		Lighting Off

		Stencil {
			Ref[_StencilRef]
			Comp[_StencilComp]
			Pass Keep
		}

		Pass {
			Name "Normal"

			CGPROGRAM
            #include "UnityUI.cginc"
			#pragma shader_feature _ _STRAIGHT_ALPHA_INPUT
            #pragma multi_compile_local _ UNITY_UI_CLIP_RECT
			#pragma vertex vert
			#pragma fragment frag
			#include "UnityCG.cginc"
			sampler2D _MainTex;
			sampler2D _NormTex;
			sampler2D _LightArea;
            float4 _ClipRect;
            float _Edge;
            float4 _LightDir;
            float _LightPow;
            float4 _LightColor;
            float _LightRange;
            float4 _LightAmbient;
            float4 _LightArea_ST;
            int _LightType;

			struct VertexInput {
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
				float4 vertexColor : COLOR;
			};

			struct VertexOutput {
				float4 pos : SV_POSITION;
				float4 uv : TEXCOORD0;
				float4 vertexColor : COLOR;
			};

			VertexOutput vert (VertexInput v) {
				VertexOutput o;
				o.pos = UnityObjectToClipPos(v.vertex);
				o.uv.xy = v.uv;
                o.uv.zw = v.vertex.xy;
				o.vertexColor = v.vertexColor;
				return o;
			}

			float4 frag (VertexOutput i) : SV_Target {
				float4 texColor = tex2D(_MainTex, i.uv.xy);
				float4 norDir = tex2D(_NormTex, i.uv.xy) - float4(0.5,0.5,1.0,0);
                float2 lightAreaUV = i.uv.zw;//i.pos.xy/_ScreenParams.xy;
                float2 uv = TRANSFORM_TEX(lightAreaUV, _LightArea);
                float4 lightArea = tex2D(_LightArea, float2(uv.x,-uv.y));

				#if defined(_STRAIGHT_ALPHA_INPUT)
				texColor.rgb *= texColor.a;
				#endif

                #ifdef UNITY_UI_CLIP_RECT

                    texColor.rgba *= (UnityGet2DClipping(i.pos.xy, _ClipRect));
                    //plus alpha minus on edge
                    if(_Edge>0.05){
                        float dis = min(abs(i.pos.y - _ClipRect.y),abs(i.pos.y - _ClipRect.w));
                        texColor.rgba *= clamp( dis/_Edge,0,1.0);
                    }

                #endif

                if(_LightType==1){
                    texColor.rgb += dot(_LightDir,norDir)*texColor.a*_LightPow*2.0*_LightColor;
                    texColor.rgb *= lightArea*2.0;
                }
                else if(_LightType==2){
                    float4 vec = _LightDir - float4(i.uv.z,i.uv.w,0,0);
                    float attn = clamp((_LightRange-length(vec))*1.0/_LightRange,0,1.0);
                    texColor.rgb *= clamp(dot(normalize(vec),norDir)*texColor.a,0,1.0)*attn*2.0*_LightColor*_LightPow + _LightAmbient;
                    texColor.rgb *= lightArea*2.0;
                }
				return (texColor * i.vertexColor);
			}
			ENDCG
		}

		Pass {
			Name "Caster"
			Tags { "LightMode"="ShadowCaster" }
			Offset 1, 1
			ZWrite On
			ZTest LEqual

			Fog { Mode Off }
			Cull Off
			Lighting Off

			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#pragma multi_compile_shadowcaster
			#pragma fragmentoption ARB_precision_hint_fastest
			#include "UnityCG.cginc"
			sampler2D _MainTex;
			fixed _Cutoff;

			struct VertexOutput {
				V2F_SHADOW_CASTER;
				float4 uvAndAlpha : TEXCOORD1;
			};

			VertexOutput vert (appdata_base v, float4 vertexColor : COLOR) {
				VertexOutput o;
				o.uvAndAlpha = v.texcoord;
				o.uvAndAlpha.a = vertexColor.a;
				TRANSFER_SHADOW_CASTER(o)
				return o;
			}

			float4 frag (VertexOutput i) : SV_Target {
				fixed4 texcol = tex2D(_MainTex, i.uvAndAlpha.xy);
				clip(texcol.a * i.uvAndAlpha.a - _Cutoff);
				SHADOW_CASTER_FRAGMENT(i)
			}
			ENDCG
		}
	}
	CustomEditor "SpineShaderWithOutlineGUI"
}
