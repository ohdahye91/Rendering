Shader "UI/CornerWarpFlow"
{
    Properties
    {
        [PerRendererData] _MainTex ("Texture", 2D) = "white" {}
        _Color ("Tint", Color) = (1,1,1,1)

        // 꼭짓점별 오프셋 (UV 단위, 0.1 = 10%)
        [Vec2] _OffsetBL ("Bottom Left",  Vector) = (0, 0, 0, 0)
        [Vec2] _OffsetBR ("Bottom Right", Vector) = (0, 0, 0, 0)
        [Vec2] _OffsetTR ("Top Right",    Vector) = (0, 0, 0, 0)
        [Vec2] _OffsetTL ("Top Left",     Vector) = (0, 0, 0, 0)

        // 패턴 흐름 (포지션 기준)
        [Vec2] _FlowSpeed ("Flow Speed", Vector) = (50, 50, 0, 0)
        _TileSize ("Tile Size", Float) = 100
    }

    SubShader
    {
        Tags { "Queue"="Transparent" "RenderType"="Transparent" "IgnoreProjector"="True" "CanUseSpriteAtlas"="True" }
        Cull Off
        ZWrite Off
        ZTest [unity_GUIZTestMode]
        Blend SrcAlpha OneMinusSrcAlpha

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float4 color  : COLOR;
                float2 uv     : TEXCOORD0;
            };

            struct v2f
            {
                float4 pos    : SV_POSITION;
                float4 color  : COLOR;
                float2 uv     : TEXCOORD0;
                float2 objPos : TEXCOORD1;
            };

            sampler2D _MainTex;
            fixed4 _Color;
            float2 _OffsetBL, _OffsetBR, _OffsetTR, _OffsetTL;
            float2 _FlowSpeed;
            float _TileSize;

            float3x3 SquareToQuad(float2 p0, float2 p1, float2 p2, float2 p3)
            {
                float2 d1 = p1 - p2;
                float2 d2 = p3 - p2;
                float2 d3 = p0 - p1 + p2 - p3;

                float det = d1.x * d2.y - d2.x * d1.y;
                float g = (d3.x * d2.y - d2.x * d3.y) / det;
                float h = (d1.x * d3.y - d3.x * d1.y) / det;

                return float3x3(
                    p1.x - p0.x + g * p1.x,  p3.x - p0.x + h * p3.x,  p0.x,
                    p1.y - p0.y + g * p1.y,  p3.y - p0.y + h * p3.y,  p0.y,
                    g,                       h,                       1.0
                );
            }

            float3x3 Inverse3x3(float3x3 m)
            {
                float3 a = m[0], b = m[1], c = m[2];
                float3 r0 = cross(b, c);
                float3 r1 = cross(c, a);
                float3 r2 = cross(a, b);
                float det = dot(a, r0);
                return transpose(float3x3(r0, r1, r2)) / det;
            }

            v2f vert (appdata v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                o.objPos = v.vertex.xy;   // Position(Object) → Swizzle xy
                o.color = v.color * _Color;
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                // 왜곡 역변환
                float2 p0 = float2(0, 0) + _OffsetBL;
                float2 p1 = float2(1, 0) + _OffsetBR;
                float2 p2 = float2(1, 1) + _OffsetTR;
                float2 p3 = float2(0, 1) + _OffsetTL;

                float3x3 inv = Inverse3x3(SquareToQuad(p0, p1, p2, p3));
                float3 s = mul(inv, float3(i.uv, 1.0));
                float2 warpedUV = s.xy / s.z;

                float inside = step(0, warpedUV.x) * step(warpedUV.x, 1)
                             * step(0, warpedUV.y) * step(warpedUV.y, 1);

                // UV 1당 포지션 변화량 = 사각형 크기 (메쉬 정보 없이 미분으로 구함)
                float2 rectSize = fwidth(i.objPos) / max(fwidth(i.uv), 1e-6);

                // 왜곡된 포지션
                float2 warpedPos = i.objPos + (warpedUV - i.uv) * rectSize;

                // (Position + Time * Speed) / TileSize
                float2 patternUV = (warpedPos + _Time.y * _FlowSpeed) / _TileSize;

                fixed4 col = tex2D(_MainTex, patternUV) * i.color;
                col.a *= inside;
                return col;
            }
            ENDCG
        }
    }
}