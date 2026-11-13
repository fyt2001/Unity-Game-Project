Shader "Game/DesertOasis/Dust" {
 SubShader {Tags {"Queue"="Transparent" "RenderType"="Transparent"} Blend SrcAlpha OneMinusSrcAlpha ZWrite Off Cull Off
 Pass {
 CGPROGRAM
 #pragma vertex vert
 #pragma fragment frag
 #include "UnityCG.cginc"
 struct input {float4 vertex:POSITION;fixed4 color:COLOR;float2 uv:TEXCOORD0;};
 struct vary {float4 vertex:SV_POSITION;fixed4 color:COLOR;float2 uv:TEXCOORD0;};
 vary vert(input v){vary o;o.vertex=UnityObjectToClipPos(v.vertex);o.color=v.color;o.uv=v.uv;return o;}
 fixed4 frag(vary i):SV_Target{float a=saturate(1-length(i.uv*2-1));return fixed4(i.color.rgb,i.color.a*a*a);}
 ENDCG
 }}
}
