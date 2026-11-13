Shader "Spine/Special/Skeleton Glow" {
	Properties {
		_Cutoff ("Shadow alpha cutoff", Range(0,1)) = 0.1
		[NoScaleOffset] _MainTex ("Main Texture", 2D) = "black" {}
		[Toggle(_STRAIGHT_ALPHA_INPUT)] _StraightAlphaInput("Straight Alpha Texture", Int) = 0
		[HideInInspector] _StencilRef("Stencil Reference", Float) = 1.0
		[HideInInspector][Enum(UnityEngine.Rendering.CompareFunction)] _StencilComp("Stencil Comparison", Float) = 8 // Set to Always as default

		// Outline properties are drawn via custom editor.
		[HideInInspector] _OutlineWidth("Outline Width", Range(0,8)) = 3.0
		[HideInInspector] _OutlineColor("Outline Color", Color) = (1,1,0,1)
		[HideInInspector] _OutlineReferenceTexWidth("Reference Texture Width", Int) = 1024
		[HideInInspector] _ThresholdEnd("Outline Threshold", Range(0,1)) = 0.25
		[HideInInspector] _OutlineSmoothness("Outline Smoothness", Range(0,1)) = 1.0
		[HideInInspector][MaterialToggle(_USE8NEIGHBOURHOOD_ON)] _Use8Neighbourhood("Sample 8 Neighbours", Float) = 1
		[HideInInspector] _OutlineMipLevel("Outline Mip Level", Range(0,3)) = 0

		_FxTexRotation("FX Texture Rotation", float) = 0
        [Vector2] _FxCenterUV("FX Center UV", Vector) = (0, 1, 0, 0)

		_GlowTex("Glow Texture", 2D) = "black" {}
		_AdditiveOrAlphaBlend("Additive Or AlphaBlend", Range(0, 1)) = 0

        [Vector2] _Glow_UV_Speed("Glow UV_Speed", Vector) = (0.1, 0.1, 0, 0)
        _GlowMin("Glow Min", Range(-20, 1)) = 0.3
		_GlowMax("Glow Max", Range(-20, 1)) = 0.8
		_GlowTimeCircle("Glow Time Circle", Float) = 4

		_Distort("Distort Texture", 2D) = "black" {}
        [Vector2] _Distort_UV_Speed("Distort UV_Speed", Vector) = (0.1, 0.1, 0, 0)
		_DistortStrength("Distort Strength", Range(0, 1)) = 0.01
		_DistortMainTex("Distort Main Texture", Range(0, 1)) = 1

		_Dissolve("Dissolve Texture", 2D) = "white" {}
		_DissolveClip("Dissolve Clip", Range(0, 10)) = 0
        _DissolveWorldSpaceScale("World Space Dissolve Factor", float) = 0.1
		_DissolveEdgeColor("Dissolve Edge Color", Color) = (0.0, 0.0, 0.0, 0)
		_DissolveEdgeWidth("Dissolve Edge Width", float) = 0
		_DissolveEdgeSmoothness("Dissolve Edge Smoothness", Range(0.001, 1)) = 0.2
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
			#pragma shader_feature _ _STRAIGHT_ALPHA_INPUT
			#pragma vertex vert
			#pragma fragment frag
			#include "UnityCG.cginc"

			sampler2D _MainTex;

			float _FxTexRotation;
			float2 _FxCenterUV;

			sampler2D _GlowTex;
			float4 _GlowTex_ST;
			float _AdditiveOrAlphaBlend;
			float2 _Glow_UV_Speed;
			float _GlowMin;
			float _GlowMax;
			float _GlowTimeCircle;
			
			sampler2D _Distort;
			float4 _Distort_ST;
			float2 _Distort_UV_Speed;
			float _DistortStrength;
			float _DistortMainTex;

			sampler2D _Dissolve;
			float4 _Dissolve_ST;
			float _DissolveClip;
			float _DissolveWorldSpaceScale;
			float4 _DissolveEdgeColor;
			float _DissolveEdgeWidth;
			float _DissolveEdgeSmoothness;

			struct VertexInput {
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
				float4 vertexColor : COLOR;
			};

			struct VertexOutput {
				float4 pos : SV_POSITION;
				float4 uv : TEXCOORD0;
				float4 uv2 : TEXCOORD1;
				float4 vertexColor : COLOR;
			};

			VertexOutput vert (VertexInput v) {
				const float Deg2Rad = UNITY_PI  / 180;
				VertexOutput o;
				o.pos = UnityObjectToClipPos(v.vertex);
				float2 duv = v.uv - _FxCenterUV;
				float sin, cos;
				sincos(Deg2Rad * _FxTexRotation, sin, cos);
				float2 uv = float2(duv.x * cos + duv.y * sin, duv.y * cos - duv.x * sin) + _FxCenterUV;
				o.uv = float4(v.uv, TRANSFORM_TEX(uv, _Dissolve));
				o.uv2 = float4(TRANSFORM_TEX(uv, _GlowTex) + _Glow_UV_Speed * _Time.g, TRANSFORM_TEX(uv, _Distort) + _Distort_UV_Speed * _Time.g);
				o.vertexColor = v.vertexColor;
				return o;
			}

			float4 frag (VertexOutput i) : SV_Target {
				float4 distort = tex2D(_Distort, i.uv2.zw);
				float2 duv = (distort.rg - float2(distort.b, distort.b)) * _DistortStrength;

				float4 texColor = tex2D(_MainTex, i.uv.xy + duv * _DistortMainTex) * i.vertexColor;
				float4 glowColor = tex2D(_GlowTex, i.uv2.xy + duv * _GlowTex_ST.xy);// i.uv2.xy + duv);
				glowColor *= saturate(lerp(_GlowMin, _GlowMax, 0.5 * sin(_Time.b * UNITY_PI / _GlowTimeCircle) + 0.5));
				glowColor.a *= texColor.a;
				#if defined(_STRAIGHT_ALPHA_INPUT)
				texColor.rgb *= texColor.a;
				glowColor.rgb *= glowColor.a;
				#endif
				float4 color = float4(glowColor.rgb + lerp(1, 1 - glowColor.a, _AdditiveOrAlphaBlend) * texColor.rgb, texColor.a);
				
				float dist = distance(_FxCenterUV, i.uv.xy);
				float dissolve = tex2D(_Dissolve, i.uv.zw).r + dist * _DissolveWorldSpaceScale;
				float dissolveAlpha = step(_DissolveClip, dissolve);
				clip(dissolveAlpha - 0.5);
				float dissolveEdge = saturate(1 - (dissolve - _DissolveClip - _DissolveEdgeWidth) / _DissolveEdgeSmoothness);
				dissolveEdge *= _DissolveEdgeColor.a * (1 - step(_DissolveClip, 0));
				color.rgb = color.rgb * (1 - dissolveEdge) + _DissolveEdgeColor * dissolveEdge;

				return color;
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
