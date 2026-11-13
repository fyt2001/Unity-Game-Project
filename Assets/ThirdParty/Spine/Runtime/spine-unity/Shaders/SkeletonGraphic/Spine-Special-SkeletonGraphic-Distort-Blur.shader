// This is a premultiply-alpha adaptation of the built-in Unity shader "UI/Default" in Unity 5.6.2 to allow Unity UI stencil masking.

Shader "Spine/Special/SkeletonGraphic Distort Blur"
{
	Properties
	{
		[PerRendererData] _MainTex ("Sprite Texture", 2D) = "white" {}
		[Toggle(_STRAIGHT_ALPHA_INPUT)] _StraightAlphaInput("Straight Alpha Texture", Int) = 0
		[Toggle(_CANVAS_GROUP_COMPATIBLE)] _CanvasGroupCompatible("CanvasGroup Compatible", Int) = 0
		_Color ("Tint", Color) = (1,1,1,1)

		[HideInInspector][Enum(UnityEngine.Rendering.CompareFunction)] _StencilComp ("Stencil Comparison", Float) = 8
		[HideInInspector] _Stencil ("Stencil ID", Float) = 0
		[HideInInspector][Enum(UnityEngine.Rendering.StencilOp)] _StencilOp ("Stencil Operation", Float) = 0
		[HideInInspector] _StencilWriteMask ("Stencil Write Mask", Float) = 255
		[HideInInspector] _StencilReadMask ("Stencil Read Mask", Float) = 255

		[HideInInspector] _ColorMask ("Color Mask", Float) = 15

		[Toggle(UNITY_UI_ALPHACLIP)] _UseUIAlphaClip ("Use Alpha Clip", Float) = 0

		// Outline properties are drawn via custom editor.
		[HideInInspector] _OutlineWidth("Outline Width", Range(0,8)) = 3.0
		[HideInInspector] _OutlineColor("Outline Color", Color) = (1,1,0,1)
		[HideInInspector] _OutlineReferenceTexWidth("Reference Texture Width", Int) = 1024
		[HideInInspector] _ThresholdEnd("Outline Threshold", Range(0,1)) = 0.25
		[HideInInspector] _OutlineSmoothness("Outline Smoothness", Range(0,1)) = 1.0
		[HideInInspector][MaterialToggle(_USE8NEIGHBOURHOOD_ON)] _Use8Neighbourhood("Sample 8 Neighbours", Float) = 1
		[HideInInspector] _OutlineMipLevel("Outline Mip Level", Range(0,3)) = 0

		_Distort("Distort Texture", 2D) = "black" {}
		_DistortMask("Distort Mask", 2D) = "white" {}
        [Vector2] _Distort_UV_Speed("Distort UV_Speed", Vector) = (0.1, 0.1, 0, 0)
		_DistortStrength("Distort Strength", Range(0, 1)) = 0.01
		_DistortMainTex("Distort Main Texture", Range(0, 1)) = 1

		_BlurStrength("Blur Strength", Range(0, 5)) = 1
	}

	SubShader
	{
		Tags
		{
			"Queue"="Transparent"
			"IgnoreProjector"="True"
			"RenderType"="Transparent"
			"PreviewType"="Plane"
			"CanUseSpriteAtlas"="True"
		}

		Stencil
		{
			Ref [_Stencil]
			Comp [_StencilComp]
			Pass [_StencilOp]
			ReadMask [_StencilReadMask]
			WriteMask [_StencilWriteMask]
		}

		Cull Off
		Lighting Off
		ZWrite Off
		ZTest [unity_GUIZTestMode]
		Fog { Mode Off }
		Blend One OneMinusSrcAlpha
		ColorMask [_ColorMask]

		GrabPass { }

		Pass {
			Name "Blur"
			Blend Off

			CGPROGRAM
			#pragma shader_feature _ _STRAIGHT_ALPHA_INPUT
			#pragma vertex vert
			#pragma fragment frag
			#include "UnityCG.cginc"

			sampler2D _MainTex;
			sampler2D _DistortMask;
			sampler2D _GrabTexture;
			float _BlurStrength;

			sampler2D _Distort;
			float4 _Distort_ST;
			float2 _Distort_UV_Speed;
			float _DistortStrength;
			float _DistortMainTex;

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
				o.uv = float4(v.uv, TRANSFORM_TEX(v.uv, _Distort) + _Distort_UV_Speed * _Time.g);
				o.uv2 = ComputeGrabScreenPos(o.pos);
				o.vertexColor = v.vertexColor;
				return o;
			}

			float4 frag (VertexOutput i) : SV_Target {
				float ox = 0.5;
				
				float4 distort = tex2D(_Distort, i.uv.zw);
				float2 duv = (distort.rg - float2(distort.b, distort.b)) * _DistortStrength;
				float2 uv = i.uv.xy + duv * _DistortMainTex;
				float4 texColor = tex2D(_MainTex, uv) * i.vertexColor * sign(tex2D(_DistortMask, uv));

				clip(texColor.a - 0.01); // TODO clip alpha

				float strength = _BlurStrength * (Luminance(texColor.rgb) % 0.005 + 0.005) * texColor.a;

				ox *= strength;

				float2 blurUV = i.uv2.xy / i.uv2.w;

				float4 bc = float4(0, 0, 0, 0);
				bc += 0.324 * tex2D(_GrabTexture, blurUV);
				bc += 0.232 * tex2D(_GrabTexture, blurUV + float2(-ox, 0));
				bc += 0.232 * tex2D(_GrabTexture, blurUV + float2(ox, 0));
				bc += 0.0855 * tex2D(_GrabTexture, blurUV + float2(-ox * 2, 0));
				bc += 0.0855 * tex2D(_GrabTexture, blurUV + float2(ox * 2, 0));
				bc += 0.0205 * tex2D(_GrabTexture, blurUV + float2(-ox * 3, 0));
				bc += 0.0205 * tex2D(_GrabTexture, blurUV + float2(ox * 3, 0));
				
				return bc;
			}
			ENDCG
		}

		GrabPass { }

		Pass {
			Name "Blur"
			Blend Off

			CGPROGRAM
			#pragma shader_feature _ _STRAIGHT_ALPHA_INPUT
			#pragma vertex vert
			#pragma fragment frag
			#include "UnityCG.cginc"

			sampler2D _MainTex;
			sampler2D _DistortMask;
			sampler2D _GrabTexture;
			float _BlurStrength;

			sampler2D _Distort;
			float4 _Distort_ST;
			float2 _Distort_UV_Speed;
			float _DistortStrength;
			float _DistortMainTex;

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
				o.uv = float4(v.uv, TRANSFORM_TEX(v.uv, _Distort) + _Distort_UV_Speed * _Time.g);
				o.uv2 = ComputeGrabScreenPos(o.pos);
				o.vertexColor = v.vertexColor;
				return o;
			}

			float4 frag (VertexOutput i) : SV_Target {
				float oy = 0.5;
				
				float4 distort = tex2D(_Distort, i.uv.zw);
				float2 duv = (distort.rg - float2(distort.b, distort.b)) * _DistortStrength;
				float2 uv = i.uv.xy + duv * _DistortMainTex;
				float4 texColor = tex2D(_MainTex, uv) * i.vertexColor * sign(tex2D(_DistortMask, uv));

				clip(texColor.a - 0.01);

				float strength = _BlurStrength * (Luminance(texColor.rgb) % 0.005 + 0.005) * texColor.a;

				oy *= strength;

				float2 blurUV = i.uv2.xy / i.uv2.w;

				float4 bc = float4(0, 0, 0, 0);
				bc += 0.324 * tex2D(_GrabTexture, blurUV);
				bc += 0.232 * tex2D(_GrabTexture, blurUV + float2(0, oy));
				bc += 0.232 * tex2D(_GrabTexture, blurUV + float2(0, -oy));
				bc += 0.0855 * tex2D(_GrabTexture, blurUV + float2(0, oy * 2));
				bc += 0.0855 * tex2D(_GrabTexture, blurUV + float2(0, -oy * 2));
				bc += 0.0205 * tex2D(_GrabTexture, blurUV + float2(0, oy * 3));
				bc += 0.0205 * tex2D(_GrabTexture, blurUV + float2(0,  -oy * 3));

				return bc;
			}
			ENDCG
		}

		GrabPass { }
		
		Pass {
			Name "Distort"
			Blend Off

			CGPROGRAM
			#pragma shader_feature _ _STRAIGHT_ALPHA_INPUT
			#pragma vertex vert
			#pragma fragment frag
			#include "UnityCG.cginc"

			sampler2D _MainTex;
			sampler2D _DistortMask;
			sampler2D _GrabTexture;

			sampler2D _Distort;
			float4 _Distort_ST;
			float2 _Distort_UV_Speed;
			float _DistortStrength;
			float _DistortMainTex;

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
				o.uv = float4(v.uv, TRANSFORM_TEX(v.uv, _Distort) + _Distort_UV_Speed * _Time.g);
				o.uv2 = ComputeGrabScreenPos(o.pos);
				o.vertexColor = v.vertexColor;
				return o;
			}

			float4 frag (VertexOutput i) : SV_Target {
				float4 distort = tex2D(_Distort, i.uv.zw);
				float2 duv = (distort.rg - float2(distort.b, distort.b)) * _DistortStrength;
				float2 uv = i.uv.xy + duv * _DistortMainTex;
				float4 texColor = tex2D(_MainTex, uv) * i.vertexColor * sign(tex2D(_DistortMask, uv));

				float2 guv = i.uv2.xy / i.uv2.w;

				float4 c1 = tex2D(_GrabTexture, guv);
				// TODO rotate duv...
				float4 c2 = tex2D(_GrabTexture, guv + duv);

				return lerp(c2, c1, step(texColor.a, 0.01));
				
				/*
				#if defined(_STRAIGHT_ALPHA_INPUT)
				texColor.rgb *= texColor.a;
				#endif

				return color;*/
			}
			ENDCG
		}

		Pass
		{
			Name "Normal"

		CGPROGRAM
			#pragma shader_feature _ _STRAIGHT_ALPHA_INPUT
			#pragma shader_feature _ _CANVAS_GROUP_COMPATIBLE
			#pragma vertex vert
			#pragma fragment frag
			#pragma target 2.0

			#include "UnityCG.cginc"
			#include "UnityUI.cginc"

			#pragma multi_compile __ UNITY_UI_ALPHACLIP

			sampler2D _Distort;
			float4 _Distort_ST;
			float2 _Distort_UV_Speed;
			float _DistortStrength;
			float _DistortMainTex;

			struct VertexInput {
				float4 vertex   : POSITION;
				float4 color    : COLOR;
				float2 texcoord : TEXCOORD0;
				UNITY_VERTEX_INPUT_INSTANCE_ID
			};

			struct VertexOutput {
				float4 vertex   : SV_POSITION;
				fixed4 color    : COLOR;
				float4 texcoord  : TEXCOORD0;
				float4 worldPosition : TEXCOORD1;
				UNITY_VERTEX_OUTPUT_STEREO
			};

			fixed4 _Color;
			fixed4 _TextureSampleAdd;
			float4 _ClipRect;

			VertexOutput vert (VertexInput IN) {
				VertexOutput OUT;

				UNITY_SETUP_INSTANCE_ID(IN);
				UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(OUT);

				OUT.worldPosition = IN.vertex;
				OUT.vertex = UnityObjectToClipPos(OUT.worldPosition);
				OUT.texcoord = float4(IN.texcoord, TRANSFORM_TEX(IN.texcoord, _Distort) + _Distort_UV_Speed * _Time.g);

				#ifdef UNITY_HALF_TEXEL_OFFSET
				OUT.vertex.xy += (_ScreenParams.zw-1.0) * float2(-1,1);
				#endif

				OUT.color = IN.color * float4(_Color.rgb * _Color.a, _Color.a); // Combine a PMA version of _Color with vertexColor.
				return OUT;
			}

			sampler2D _MainTex;
			sampler2D _DistortMask;

			fixed4 frag (VertexOutput IN) : SV_Target
			{
				float4 distort = tex2D(_Distort, IN.texcoord.zw);
				float2 duv = (distort.rg - float2(distort.b, distort.b)) * _DistortStrength;
				float2 uv = IN.texcoord.xy + duv * _DistortMainTex;
				half4 texColor = tex2D(_MainTex, IN.texcoord.xy + duv * sign(tex2D(_DistortMask, uv).a));

				#if defined(_STRAIGHT_ALPHA_INPUT)
				texColor.rgb *= texColor.a;
				#endif

				half4 color = (texColor + _TextureSampleAdd) * IN.color;
				#ifdef _CANVAS_GROUP_COMPATIBLE
				// CanvasGroup alpha sets vertex color alpha, but does not premultiply it to rgb components.
				color.rgb *= IN.color.a;
				#endif

				color *= UnityGet2DClipping(IN.worldPosition.xy, _ClipRect);

				#ifdef UNITY_UI_ALPHACLIP
				clip (color.a - 0.001);
				#endif

				return color;
			}
		ENDCG
		}
	}
	CustomEditor "SpineShaderWithOutlineGUI"
}
