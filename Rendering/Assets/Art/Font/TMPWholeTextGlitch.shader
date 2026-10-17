// TMP 텍스트 "전체"에 적용되는 계단식 왜곡 쉐이더
// TMPWholeTextEffect.cs 가 텍스트를 RenderTexture로 캡처해서 _MainTex로 넘겨준다.
// 시간 자동 애니메이션 없음 → _Offset 값으로 왜곡 구간을 직접 이동 (Animator / 스크립트로 애니메이션)
// (입력은 프리멀티플라이드 알파 / Blend One OneMinusSrcAlpha)
Shader "UI/TMP Whole Text Glitch"
{
    Properties
    {
        [PerRendererData] _MainTex ("Captured Text (Script)", 2D) = "black" {}
        _Color ("Tint", Color) = (1,1,1,1)

        [Header(Gradient)]
        [Toggle(_GRADIENT_ON)] _UseGradient ("Use Gradient", Float) = 1
        _TopColor ("Top Color", Color) = (1,1,1,1)
        _BottomColor ("Bottom Color", Color) = (0.45,0.45,0.45,1)
        _GradientMin ("Gradient Bottom (UV)", Range(0,1)) = 0.1
        _GradientMax ("Gradient Top (UV)", Range(0,1)) = 0.9

        [Header(Distortion Zone)]
        _Offset ("Offset (Zone Position X)", Float) = 0.5
        _Intensity ("Intensity", Range(0,1)) = 1
        _Width ("Zone Width (UV)", Range(0.01,1.5)) = 0.3
        _Softness ("Zone Edge Softness", Range(0,1)) = 0.15

        [Header(Staircase)]
        _StepCount ("Step Count (Horizontal Bands)", Float) = 40
        _StepSlope ("Step Slope (Diagonal)", Range(-1,1)) = 0.25
        _BandShift ("Band Random Shift (UV)", Range(0,0.3)) = 0.03
        _Streak ("Streak (Band Y Snap)", Range(0,1)) = 1

        [Header(Stretch)]
        _Stretch ("Stretch Amount", Range(0,1)) = 0.85
        [Enum(Left,0,Right,1)] _StretchSide ("Stretch Anchor Side", Float) = 1
        _XSteps ("Pixel Steps X (0 = Off)", Float) = 0

        [Header(Wave)]
        _WaveAmount ("Wave Amount (UV)", Range(0,0.2)) = 0.02
        _WaveFrequency ("Wave Frequency", Float) = 3

        [Header(Pattern)]
        _Seed ("Seed", Float) = 0
        _RGBSplit ("RGB Split (UV)", Range(0,0.05)) = 0

        [Header(Render)]
        [Enum(UnityEngine.Rendering.CompareFunction)] _ZTest ("ZTest (UI: Always / 3D: LessEqual)", Float) = 8

        [HideInInspector] _StencilComp ("Stencil Comparison", Float) = 8
        [HideInInspector] _Stencil ("Stencil ID", Float) = 0
        [HideInInspector] _StencilOp ("Stencil Operation", Float) = 0
        [HideInInspector] _StencilWriteMask ("Stencil Write Mask", Float) = 255
        [HideInInspector] _StencilReadMask ("Stencil Read Mask", Float) = 255
        [HideInInspector] _ColorMask ("Color Mask", Float) = 15
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
        ZTest [_ZTest]
        Blend One OneMinusSrcAlpha
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
            #pragma multi_compile_local _ UNITY_UI_ALPHACLIP
            #pragma shader_feature_local _GRADIENT_ON

            struct appdata
            {
                float4 vertex : POSITION;
                float4 color  : COLOR;
                float2 uv     : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
                float4 pos      : SV_POSITION;
                fixed4 color    : COLOR;
                float2 uv       : TEXCOORD0;
                float4 localPos : TEXCOORD1;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;
            fixed4 _Color;
            float4 _ClipRect;

            fixed4 _TopColor, _BottomColor;
            float _GradientMin, _GradientMax;

            float _Offset, _Intensity, _Width, _Softness;
            float _StepCount, _StepSlope, _BandShift, _Streak;
            float _Stretch, _StretchSide, _XSteps;
            float _WaveAmount, _WaveFrequency;
            float _Seed, _RGBSplit;

            float hash21(float2 p)
            {
                float3 p3 = frac(float3(p.xyx) * 0.1031);
                p3 += dot(p3, p3.yzx + 33.33);
                return frac((p3.x + p3.y) * p3.z);
            }

            v2f vert(appdata v)
            {
                v2f o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                o.localPos = v.vertex;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                o.color = v.color * _Color;
                return o;
            }

            half4 SampleText(float2 uv)
            {
                half4 c = tex2D(_MainTex, uv);
                float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
                return c * inside;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                float2 uv = i.uv;

                // ---- 가로 띠(계단) 나누기
                float stepCount = max(_StepCount, 1.0);
                float band  = floor(uv.y * stepCount);
                float bandY = (band + 0.5) / stepCount;
                float h1 = hash21(float2(band, _Seed));
                float h2 = hash21(float2(band + 17.3, _Seed + 4.1));

                // ---- 띠마다 구간 중심을 대각선으로 밀어서 계단 모양 경계 생성
                float center = _Offset + (bandY - 0.5) * _StepSlope;
                float halfW  = max(_Width * 0.5, 1e-4);
                float d      = abs(uv.x - center) / halfW;
                float mask   = 1.0 - smoothstep(1.0 - _Softness, 1.0, d);
                mask *= _Intensity;

                // ---- 늘어짐: 구간 한쪽 끝을 기준으로 띠마다 다른 비율로 잡아늘림
                float anchor   = center + (_StretchSide * 2.0 - 1.0) * halfW;
                float stretchF = lerp(1.0, h1 * h1, _Stretch);   // 작을수록 더 길게 늘어남
                float sx = anchor + (uv.x - anchor) * stretchF;

                // ---- 띠별 랜덤 밀림 + 웨이브 왜곡
                sx += (h2 - 0.5) * 2.0 * _BandShift;
                sx += sin(bandY * _WaveFrequency * 6.2831853 + _Seed) * _WaveAmount;

                // ---- X 픽셀 계단화 (옵션)
                if (_XSteps > 0.5)
                    sx = (floor(sx * _XSteps) + 0.5) / _XSteps;

                uv.x = lerp(uv.x, sx, mask);

                // ---- 띠 안에서 한 줄만 샘플 → 가로 줄무늬(스트릭)
                uv.y = lerp(uv.y, bandY, mask * _Streak);

                // ---- RGB 분리 (구간 안에서만)
                float split = _RGBSplit * mask;
                half4 cR = SampleText(uv + float2(split, 0));
                half4 cG = SampleText(uv);
                half4 cB = SampleText(uv - float2(split, 0));
                half4 col = half4(cR.r, cG.g, cB.b, max(cG.a, max(cR.a, cB.a)));

                // ---- 텍스트 전체 기준 세로 그라데이션 (곱하기 → 아웃라인 색 유지)
                #ifdef _GRADIENT_ON
                    float gy = saturate((i.uv.y - _GradientMin) / max(_GradientMax - _GradientMin, 1e-4));
                    col.rgb *= lerp(_BottomColor.rgb, _TopColor.rgb, gy);
                #endif

                // ---- 틴트 (프리멀티플라이드)
                col.rgb *= i.color.rgb;
                col *= i.color.a;

                #ifdef UNITY_UI_CLIP_RECT
                    col *= UnityGet2DClipping(i.localPos.xy, _ClipRect);
                #endif

                #ifdef UNITY_UI_ALPHACLIP
                    clip(col.a - 0.001);
                #endif

                return col;
            }
            ENDCG
        }
    }
}
