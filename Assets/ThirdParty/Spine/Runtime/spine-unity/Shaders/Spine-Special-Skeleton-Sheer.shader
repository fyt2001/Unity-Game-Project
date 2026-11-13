Shader "Spine/Special/Skeleton Sheer" {
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

		_Sheer("Sheer", Range(0, 1)) = 0.5
		_BlurStrength("Blur Strength", Range(0, 5)) = 1
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

		GrabPass { "_BlurGrab1" }

		Pass {
			Name "Blur"

			CGPROGRAM
			#pragma shader_feature _ _STRAIGHT_ALPHA_INPUT
			#pragma vertex vert
			#pragma fragment frag
			#include "UnityCG.cginc"

			sampler2D _MainTex;
			sampler2D _BlurGrab1;
			float _BlurStrength;

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
				VertexOutput o;
				o.pos = UnityObjectToClipPos(v.vertex);
				o.uv = float4(v.uv, 0, 0);
				o.uv2 = ComputeGrabScreenPos(o.pos);
				o.vertexColor = v.vertexColor;
				return o;
			}

			float4 frag (VertexOutput i) : SV_Target {
				float ox = 0.5;

				float4 texColor = tex2D(_MainTex, i.uv.xy) * i.vertexColor;

				clip(texColor.a - 0.01); // TODO clip alpha

				float strength = _BlurStrength * (Luminance(texColor.rgb) % 0.005 + 0.005) * texColor.a;

				ox *= strength;

				float2 blurUV = i.uv2.xy / i.uv2.w;

				float4 bc = float4(0, 0, 0, 0);
				bc += 0.324 * tex2D(_BlurGrab1, blurUV);
				bc += 0.232 * tex2D(_BlurGrab1, blurUV + float2(-ox, 0));
				bc += 0.232 * tex2D(_BlurGrab1, blurUV + float2(ox, 0));
				bc += 0.0855 * tex2D(_BlurGrab1, blurUV + float2(-ox * 2, 0));
				bc += 0.0855 * tex2D(_BlurGrab1, blurUV + float2(ox * 2, 0));
				bc += 0.0205 * tex2D(_BlurGrab1, blurUV + float2(-ox * 3, 0));
				bc += 0.0205 * tex2D(_BlurGrab1, blurUV + float2(ox * 3, 0));
				
				return bc;
			}
			ENDCG
		}

		GrabPass { "_BlurGrab2" }

		Pass {
			Name "Blur"

			CGPROGRAM
			#pragma shader_feature _ _STRAIGHT_ALPHA_INPUT
			#pragma vertex vert
			#pragma fragment frag
			#include "UnityCG.cginc"

			sampler2D _MainTex;
			sampler2D _BlurGrab2;
			float _BlurStrength;

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
				VertexOutput o;
				o.pos = UnityObjectToClipPos(v.vertex);
				o.uv = float4(v.uv, 0, 0);
				o.uv2 = ComputeGrabScreenPos(o.pos);
				o.vertexColor = v.vertexColor;
				return o;
			}

			float4 frag (VertexOutput i) : SV_Target {
				float oy = 0.5;

				float4 texColor = tex2D(_MainTex, i.uv.xy) * i.vertexColor;

				clip(texColor.a - 0.01);

				float strength = _BlurStrength * (Luminance(texColor.rgb) % 0.005 + 0.005) * texColor.a;

				oy *= strength;

				float2 blurUV = i.uv2.xy / i.uv2.w;

				float4 bc = float4(0, 0, 0, 0);
				bc += 0.324 * tex2D(_BlurGrab2, blurUV);
				bc += 0.232 * tex2D(_BlurGrab2, blurUV + float2(0, oy));
				bc += 0.232 * tex2D(_BlurGrab2, blurUV + float2(0, -oy));
				bc += 0.0855 * tex2D(_BlurGrab2, blurUV + float2(0, oy * 2));
				bc += 0.0855 * tex2D(_BlurGrab2, blurUV + float2(0, -oy * 2));
				bc += 0.0205 * tex2D(_BlurGrab2, blurUV + float2(0, oy * 3));
				bc += 0.0205 * tex2D(_BlurGrab2, blurUV + float2(0,  -oy * 3));

				return bc;
			}
			ENDCG
		}

		Pass {
			Name "Normal"

			CGPROGRAM
			#pragma shader_feature _ _STRAIGHT_ALPHA_INPUT
			#pragma vertex vert
			#pragma fragment frag
			#include "UnityCG.cginc"

			sampler2D _MainTex;
			float _Sheer;

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
				VertexOutput o;
				o.pos = UnityObjectToClipPos(v.vertex);
				o.uv = float4(v.uv, 0, 0);
				o.vertexColor = v.vertexColor;
				return o;
			}

			float4 frag (VertexOutput i) : SV_Target {
				float4 texColor = tex2D(_MainTex, i.uv.xy) * i.vertexColor;
				texColor.a *= 1 - _Sheer;
				#if defined(_STRAIGHT_ALPHA_INPUT)
				texColor.rgb *= texColor.a;
				#endif
				
				return texColor;
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
