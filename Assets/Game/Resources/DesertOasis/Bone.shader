Shader "Game/DesertOasis/IllustratedBone" {
 Properties {_Color("Bone pigment",Color)=(0.78,0.66,0.49,1)}
 SubShader {Tags {"RenderType"="Opaque"}
 Pass {Cull Front
 CGPROGRAM
 #pragma vertex vert
 #pragma fragment frag
 #include "UnityCG.cginc"
 float4 vert(appdata_base v):SV_POSITION {
 float3 world=mul(unity_ObjectToWorld,v.vertex).xyz;
 world+=normalize(UnityObjectToWorldNormal(v.normal))*0.024;
 return mul(UNITY_MATRIX_VP,float4(world,1));
 }
 fixed4 frag():SV_Target{return fixed4(0.23,0.17,0.12,1);}
 ENDCG
 }
 CGPROGRAM
 #pragma surface surf Standard fullforwardshadows
 fixed4 _Color;
 struct Input {float3 worldPos;};
 void surf(Input IN,inout SurfaceOutputStandard o) {
 float pigment=0.94+0.06*sin(IN.worldPos.x*7+IN.worldPos.y*3)*sin(IN.worldPos.z*5);
 o.Albedo=_Color.rgb*pigment; o.Smoothness=0.07; o.Emission=_Color.rgb*0.07;
 }
 ENDCG
 } FallBack "Diffuse"
}
