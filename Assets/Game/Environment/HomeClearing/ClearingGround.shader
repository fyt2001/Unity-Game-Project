Shader "Game/HomeClearing/Ground"
{
    Properties
    {
        _Soil ("Soil", Color) = (0.39,0.35,0.28,1)
        _Grass ("Grass", Color) = (0.28,0.38,0.18,1)
        _Clearing ("Clearing center and radii", Vector) = (0,1,16,18)
        _Smoothness ("Smoothness", Range(0,1)) = 0.08
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 200
        CGPROGRAM
        #pragma surface surf Standard fullforwardshadows
        #pragma target 3.0
        fixed4 _Soil, _Grass;
        float4 _Clearing;
        half _Smoothness;
        struct Input { float3 worldPos; };
        float hash(float2 p) { return frac(sin(dot(p,float2(127.1,311.7))) * 43758.5453); }
        float noise(float2 p)
        {
            float2 i=floor(p), f=frac(p);
            f=f*f*(3.0-2.0*f);
            return lerp(lerp(hash(i),hash(i+float2(1,0)),f.x),
                        lerp(hash(i+float2(0,1)),hash(i+1),f.x),f.y);
        }
        void surf(Input IN, inout SurfaceOutputStandard o)
        {
            float2 p=IN.worldPos.xz;
            float broad=noise(p*0.19);
            float edge=length((p-_Clearing.xy)/_Clearing.zw);
            edge += (broad-0.5)*0.24 + (noise(p*0.48)-0.5)*0.10;
            float grass=smoothstep(0.68,1.05,edge);
            float pathX=sin(p.y*0.16)*2.0+p.y*0.15;
            float path=1.0-smoothstep(1.0,2.4,abs(p.x-pathX)+(noise(p*0.6)-0.5)*0.45);
            grass*=1.0-path;
            float detail=noise(p*3.8)*0.55+noise(p*13.0)*0.3+noise(p*31.0)*0.15;
            float patch=lerp(0.91,1.08,broad);
            float3 soil=_Soil.rgb*patch*lerp(0.92,1.07,detail);
            soil*=lerp(1.0,1.07,path);
            float3 vegetation=_Grass.rgb*lerp(0.84,1.16,noise(p*0.5))*lerp(0.94,1.06,detail);
            o.Albedo=lerp(soil,vegetation,grass);
            o.Metallic=0;
            o.Smoothness=_Smoothness;
            o.Occlusion=1;
        }
        ENDCG
    }
    FallBack "Diffuse"
}
