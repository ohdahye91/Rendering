Shader "UI/CircleRepeatDots"
{
    Properties
    {
        [PerRendererData] _MainTex ("Sprite Texture", 2D) = "white" {}
        [NoScaleOffset] _DotTex ("Dot Texture", 2D) = "white" {}
        _Color ("Color", Color) = (1,1,1,1)

        _Count    ("Count", Float) = 8
        _Offset   ("Sub Ball Offset", Float) = -0.5      // k = 1 - Offset
        _UVOffset ("UV Offset (XY)", Vector) = (-0.5, 0.5, 0, 0)

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
            float _Count, _Offset;
            float4 _UVOffset;
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
                // [UV → ×2 → -1 → p]
                // 0~1 UV를 -1~1로, 쿼드 중앙이 원점
                float2 p = i.uv * 2.0 - 1.0;

                // [p → Split → Arctangent2 → a]
                // 3시 = 0, 반시계방향 증가, 범위 -π ~ π
                float a = atan2(p.y, p.x);

                // [TAU ÷ Round(Count) → step]
                // 조각 하나의 각도
                float n     = max(1.0, round(_Count));
                float stepA = TAU / n;

                // [a ÷ step → Floor → × step → Add(+ step÷2) → Rotation]
                // 이 픽셀이 속한 조각의 중앙 각도
                float rot = floor(a / stepA) * stepA + stepA * 0.5;

                // [p → Rotate (Center 0,0)]
                // Shader Graph Rotate 노드(Radians)와 같은 계산
                // mul(행벡터, 행렬) = -rot 만큼 회전 → 조각 중앙이 +X 축으로 접힘
                float s, c;
                sincos(rot, s, c);
                float2x2 m = float2x2(c, -s, s, c);
                float2 r = mul(p, m);

                // [× (1 - Offset) → + (-0.5, 0.5)]
                // 텍스처 중심(0.5,0.5)이 링 반지름 1/k 위치에 놓임
                float k = 1.0 - _Offset;
                float2 uv = r * k + _UVOffset.xy;

                // [Sample Texture]
                // 조각 경계에서 밉맵 튐 방지 → LOD 0
                fixed4 col = tex2Dlod(_DotTex, float4(uv, 0, 0)) * i.color;

                #ifdef UNITY_UI_CLIP_RECT
                col.a *= UnityGet2DClipping(i.worldPos.xy, _ClipRect);
                #endif

                return col;
            }
            ENDCG
        }
    }
}
