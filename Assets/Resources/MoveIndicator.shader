Shader "Game/MoveIndicator"
{
    // 右键移动标记专用材质（英雄联盟 「指令地表标记」 观感）。
    //
    // 设计：
    //   1. 纯 Unlit + 顶点色，不参与光照，保证任何光照设置下颜色稳定
    //   2. 软边完全由【顶点色 alpha】承担（网格生成时写死径向渐变），
    //      shader 本身不需要任何贴图或 mask 参数 —— 既省资源又不会因 missing texture 变白
    //   3. ZWrite Off + Transparent：贴地标线不与地面打架，也不会写深度挡住后续透明物体
    //   4. Cull Off：箭头是「由多个侧面组成的立体光楔」，转动时正反面都会出现
    //
    // 注意：本项目使用 Built-in 渲染管线（manifest 中无 URP 依赖），
    //       因此直接使用经典 ShaderLab + CGPROGRAM，不需要 URP 的 HLSL / SubShader Tags。

    Properties
    {
        _TintColor ("Tint Color", Color) = (0.27, 0.95, 0.63, 1)
        _Opacity   ("Opacity",    Float) = 1.0
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Transparent"
            "Queue"      = "Transparent"
            "IgnoreProjector" = "True"
        }
        LOD 100

        Lighting Off
        ZWrite Off
        Cull Off
        Blend SrcAlpha OneMinusSrcAlpha

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 2.5
            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float4 color  : COLOR;   // 顶点色：携带软边与角度调制的 alpha
            };

            struct v2f
            {
                float4 pos    : SV_POSITION;
                float4 vcolor : COLOR;
            };

            fixed4 _TintColor;
            float  _Opacity;

            v2f vert (appdata v)
            {
                v2f o;
                o.pos    = UnityObjectToClipPos(v.vertex);
                o.vcolor = v.color;
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                fixed4 col = i.vcolor * _TintColor;
                col.a *= _Opacity;
                return col;
            }
            ENDCG
        }
    }

    FallBack "Transparent/VertexLit"
}
