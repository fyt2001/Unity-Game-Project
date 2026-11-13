Shader "Game/DesertOasis/PaintedSand" {
 Properties { _MainTex("Painted sand",2D)="white"{} _Color("Tint",Color)=(0.87,0.83,0.76,1) }
 SubShader { Tags {"RenderType"="Opaque"} LOD 200
 CGPROGRAM
 #pragma surface surf Standard fullforwardshadows
 #pragma target 3.0
 sampler2D _MainTex; fixed4 _Color;
 struct Input {float3 worldPos;};
 void surf(Input IN,inout SurfaceOutputStandard o) {
 float2 p=IN.worldPos.xz*0.038;
 fixed3 c=tex2D(_MainTex,p).rgb*_Color.rgb;
 float luminance=dot(c,float3(0.299,0.587,0.114));
 c=lerp(luminance.xxx,c,0.62)*0.80;
 o.Albedo=c; o.Smoothness=0.03; o.Metallic=0; o.Emission=c*0.08;
 }
 ENDCG
 } FallBack "Diffuse"
}
