Shader "Custom/BattleGrid"
{
    Properties
    {
        _BaseColor  ("Base Color",     Color) = (0.18, 0.22, 0.28, 1)
        _GridColor  ("Grid Color",     Color) = (0.35, 0.40, 0.50, 1)
        _BoundsColor("Bounds Color",   Color) = (1.00, 0.85, 0.20, 1)
        _GridSize   ("Grid Size",      Float) = 2.0    // 每格世界单位
        _LineWidth  ("Line Width",     Float) = 0.04   // 网格线宽（世界单位）
        _Bounds     ("Bounds Half",    Float) = 0.0    // <=0 关闭边界；否则画正方形边界半边长
        _Fade       ("Edge Fade",      Float) = 1.0    // 远处淡出强度
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" }
        LOD 100

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
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float2 worldXZ : TEXCOORD0; // 世界坐标的 XZ 平面
            };

            fixed4 _BaseColor;
            fixed4 _GridColor;
            fixed4 _BoundsColor;
            float  _GridSize;
            float  _LineWidth;
            float  _Bounds;
            float  _Fade;

            v2f vert (appdata v)
            {
                v2f o;
                float4 world = mul(unity_ObjectToWorld, v.vertex);
                o.worldXZ = world.xz;
                o.pos = UnityObjectToClipPos(v.vertex);
                return o;
            }

            // 返回 [0,1]：0=线上，1=格子中心。基于固定世界单位线宽，不依赖 fwidth。
            float GridMask(float2 worldPos, float size, float width)
            {
                float2 c = worldPos / size;
                // 到最近格线的有符号距离（世界单位）
                float2 distToLine = abs(frac(c - 0.5) - 0.5) * size;
                float d = min(distToLine.x, distToLine.y);
                // 线宽范围内为 1，之外渐隐（半宽抗锯齿）
                return 1.0 - smoothstep(width * 0.5, width, d);
            }

            fixed4 frag (v2f i) : SV_Target
            {
                // ---- 网格线（基于世界坐标，任意缩放/平移的平面都正确）----
                float gridMask = GridMask(i.worldXZ, _GridSize, _LineWidth);

                // 远处按距离淡出网格，避免摩尔纹
                float dist = length(i.worldXZ);
                float fade = saturate(1.0 - dist / (120.0 * _Fade));
                gridMask *= fade;

                fixed4 col = lerp(_BaseColor, _GridColor, gridMask);

                // ---- 玩家活动边界（正方形边框，固定世界单位线宽）----
                if (_Bounds > 0.0)
                {
                    float2 d = abs(i.worldXZ) - _Bounds;     // <0 在框内
                    float2 distToEdge = abs(d);              // 到边界的距离（世界单位）
                    float border = 1.0 - smoothstep(_LineWidth * 0.5, _LineWidth, min(distToEdge.x, distToEdge.y));
                    float inside = step(max(d.x, d.y), 0.0); // 仅在框内/框线处绘制
                    col = lerp(col, _BoundsColor, border * inside);
                }

                return col;
            }
            ENDCG
        }
    }
    FallBack "Diffuse"
}
