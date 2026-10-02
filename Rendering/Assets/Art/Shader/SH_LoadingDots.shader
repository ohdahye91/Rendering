Shader "UI/LoadingDotsTex"
{
    Properties
    {
        [PerRendererData] _MainTex ("Sprite Texture", 2D) = "white" {}
        [NoScaleOffset] _DotTex ("Dot Texture", 2D) = "white" {}
        _Color ("Color", Color) = (1,1,1,1)

        [IntRange] _DotCount ("Dot Count", Range(1, 64)) = 8
        _Radius   ("Ring Radius", Range(0, 0.5)) = 0.35
        _DotSize  ("Dot Size", Range(0, 0.25)) = 0.06

        _Speed    ("Speed (rev/sec)", Float) = 1
        [Toggle] _Clockwise ("Clockwise", Float) = 1
        [Toggle] _Stepped   ("Stepped (tick)", Float) = 0
        [Toggle] _AlignToRing ("Align To Ring", Float) = 1

        _Trail    ("Trail Length", Range(0.01, 1)) = 0.8
        _MinAlpha ("Tail Alpha", Range(0, 1)) = 0.15
        _MinScale ("Tail Scale", Range(0, 1)) = 0.5

        // UI Mask 지원
        _StencilComp ("Stencil Comparison", Float) = 8
        _Stencil ("Stencil ID", Float) = 0
        _StencilOp ("Stencil Operation", Float) = 0
        _StencilWriteMask ("Stencil Write Mask", Float) = 255
        _StencilReadMask ("Stencil Read Mask", Float) = 255
        _ColorMask ("Color Mask", Float) = 15
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
        Blend SrcAlpha OneMinusSrcAlpha
        ColorMask [_ColorMask]

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0
            #include "UnityCG.cginc"
            #include "UnityUI.cginc"
            #pragma multi_compile_local _ UNITY_UI_CLIP_RECT

            #define TAU 6.28318530718

            struct appdata
            {
                float4 vertex : POSITION;
                float4 color  : COLOR;
                float2 uv     : TEXCOORD0;
            };

            struct v2f
            {
                float4 pos      : SV_POSITION;
                float4 color    : COLOR;
                float2 uv       : TEXCOORD0;
                float4 worldPos : TEXCOORD1;
            };

            sampler2D _DotTex;
            fixed4 _Color;
            float _DotCount, _Radius, _DotSize;
            float _Speed, _Clockwise, _Stepped, _AlignToRing;
            float _Trail, _MinAlpha, _MinScale;
            float4 _ClipRect;

            v2f vert (appdata v)
            {
                v2f o;
                o.worldPos = v.vertex;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                o.color = v.color * _Color;
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                float dir = (_Clockwise > 0.5) ? 1.0 : -1.0;
                float2 p = i.uv - 0.5;
                p.x *= dir;

                float n = max(1.0, floor(_DotCount));
                float stepAng = TAU / n;

                // 12시 = 0, 시계방향 증가
                float a = atan2(p.x, p.y);
                a = (a < 0) ? a + TAU : a;

                // 가장 가까운 점
                float idx = fmod(round(a / stepAng), n);
                float ca = idx * stepAng;
                float2 radial  = float2(sin(ca), cos(ca));   // 바깥 방향
                float2 tangent = float2(cos(ca), -sin(ca));  // 진행 방향
                float2 center = radial * _Radius;

                // 꼬리 계산
                float head = frac(_Time.y * _Speed) * n;
                head = (_Stepped > 0.5) ? floor(head) : head;
                float behind = frac((head - idx) / n);
                float t = saturate(1.0 - behind / _Trail);

                float scale = lerp(_MinScale, 1.0, t);
                float alpha = lerp(_MinAlpha, 1.0, t);
                float size = max(_DotSize * scale, 1e-5);

                // 점 로컬 좌표 -> 텍스처 UV
                float2 q = p - center;
                float2 local = (_AlignToRing > 0.5)
                    ? float2(dot(q, tangent), dot(q, radial))   // 텍스처 위쪽이 바깥을 향함
                    : float2(q.x * dir, q.y);                  // 화면 기준 고정
                float2 dotUV = local / (size * 2.0) + 0.5;

                // 영역 밖은 버림
                float inside = step(0.0, dotUV.x) * step(dotUV.x, 1.0)
                             * step(0.0, dotUV.y) * step(dotUV.y, 1.0);

                // 칸 경계에서 밉맵이 튀지 않도록 미분값 직접 지정
                float2 gx = ddx(i.uv) / (size * 2.0);
                float2 gy = ddy(i.uv) / (size * 2.0);
                fixed4 tex = tex2Dgrad(_DotTex, dotUV, gx, gy);

                fixed4 col = tex * i.color;
                col.a *= inside * alpha;

                #ifdef UNITY_UI_CLIP_RECT
                col.a *= UnityGet2DClipping(i.worldPos.xy, _ClipRect);
                #endif

                return col;
            }
            ENDCG
        }
    }
}
