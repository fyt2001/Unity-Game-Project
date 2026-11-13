Shader "Game/DesertOasis/ShallowWater" {
 Properties {_Color("Water pigment",Color)=(0.36,0.53,0.48,0.65)}
 SubShader {Tags {"Queue"="Transparent" "RenderType"="Transparent"} ZWrite Off
 CGPROGRAM
 #pragma surface surf Standard alpha:fade
 fixed4 _Color;
 struct Input {float3 worldPos;float4 color:COLOR;};
 void surf(Input IN,inout SurfaceOutputStandard o) {
 float wave=pow(saturate(sin(IN.worldPos.x*2+IN.worldPos.z*1.1-_Time.y*0.45)),22);
 o.Albedo=_Color.rgb+wave*0.08; o.Emission=_Color.rgb*0.1; o.Smoothness=0.3; o.Alpha=_Color.a*IN.color.a;
 }
 ENDCG
 } FallBack "Transparent/Diffuse"
}
