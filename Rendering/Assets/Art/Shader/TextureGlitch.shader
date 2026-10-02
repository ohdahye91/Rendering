// Unity URP - 텍스처 구동형 글리치 셰이더
// 글리치 타이밍 / 블록 변위 / 라인 지터 / RGB 분리 / 스캔라인 / 롤 밴드 / 그레인을 전부 텍스처로 제어
// 스프라이트, UI(Image), 메시 머티리얼에 사용 가능 (Premultiplied Alpha)
Shader "Custom/URP/TextureGlitch"
{
    Properties
    {
        [MainTexture] _MainTex ("Main Texture", 2D) = "white" {}
        [MainColor] _Color ("Tint", Color) = (1,1,1,1)

        [Header(Glitch Timing)]
        _GlitchTimingTex ("Timing Tex (R: 트리거 곡선)", 2D) = "black" {}
        _GlitchTimingSpeed ("Timing Speed", Float) = 0.15
        _GlitchThreshold ("Trigger Threshold", Range(0,1)) = 0.7
        _GlitchFPS ("Glitch Step FPS", Float) = 12

        [Header(Block Glitch)]
        _BlockNoiseTex ("Block Noise (R: 변위, G: 마스크, B: 반전)", 2D) = "black" {}
        _BlockScale ("Block Count (XY)", Vector) = (6, 24, 0, 0)
        _BlockDisplace ("Block Displacement", Range(0,0.5)) = 0.08
        _BlockAmount ("Block Coverage", Range(0,1)) = 0.35
        _InvertChance ("Color Invert Chance", Range(0,1)) = 0.1

        [Header(Line Jitter)]
        _JitterTex ("Jitter Noise (R)", 2D) = "gray" {}
        _JitterLines ("Jitter Line Count", Float) = 180
        _JitterAmount ("Jitter Amount", Range(0,0.1)) = 0.012
        _IdleJitter ("Idle Jitter Ratio", Range(0,1)) = 0.08

        [Header(RGB Split)]
        _RGBSplitTex ("RGB Split (RG: 방향, B: 강도)", 2D) = "gray" {}
        _RGBSplitDir ("Base Split Direction", Vector) = (1, 0, 0, 0)
        _RGBSplitTexInfluence ("Split Tex Influence", Range(0,2)) = 0.6
        _RGBSplitAmount ("RGB Split Amount (Glitch)", Range(0,0.1)) = 0.025
        _IdleRGBSplit ("RGB Split Amount (Idle)", Range(0,0.02)) = 0.0015

        [Header(Scanline)]
        _ScanlineTex ("Scanline (R: 라인 패턴, G: 롤 밴드)", 2D) = "white" {}
        _ScanlineCount ("Scanline Count", Float) = 240
        _ScanlineSpeed ("Scanline Scroll Speed", Float) = 0.5
        _ScanlineIntensity ("Scanline Intensity", Range(0,1)) = 0.35
        [ToggleUI] _ScanlineScreenSpace ("Screen Space Scanline", Float) = 1
        _RollSpeed ("Roll Band Speed", Float) = 0.12
        _RollIntensity ("Roll Band Intensity", Range(0,1)) = 0.12

        [Header(Manual Control)]
        _GlitchOverride ("Glitch Override (스크립트 제어)", Range(0,1)) = 0
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Transparent"
            "Queue" = "Transparent"
            "IgnoreProjector" = "True"
            "CanUseSpriteAtlas" = "True"
        }

        Blend One OneMinusSrcAlpha
        ZWrite Off
        Cull Off

        Pass
        {
            Name "TextureGlitch"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_MainTex);         SAMPLER(sampler_MainTex);
            TEXTURE2D(_GlitchTimingTex); SAMPLER(sampler_GlitchTimingTex);
            TEXTURE2D(_BlockNoiseTex);
            TEXTURE2D(_JitterTex);       SAMPLER(sampler_JitterTex);
            TEXTURE2D(_RGBSplitTex);
            TEXTURE2D(_ScanlineTex);     SAMPLER(sampler_ScanlineTex);
            TEXTURE2D(_GrainTex);        SAMPLER(sampler_GrainTex);

            // 블록 계열은 경계가 딱 끊겨야 하므로 포인트 샘플러 고정
            SAMPLER(sampler_point_repeat);

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                half4  _Color;

                float _GlitchTimingSpeed;
                float _GlitchThreshold;
                float _GlitchFPS;

                float4 _BlockScale;
                float _BlockDisplace;
                float _BlockAmount;
                float _InvertChance;

                float _JitterLines;
                float _JitterAmount;
                float _IdleJitter;

                float4 _RGBSplitDir;
                float _RGBSplitTexInfluence;
                float _RGBSplitAmount;
                float _IdleRGBSplit;

                float _ScanlineCount;
                float _ScanlineSpeed;
                float _ScanlineIntensity;
                float _ScanlineScreenSpace;
                float _RollSpeed;
                float _RollIntensity;

                float _GrainTiling;
                float _GrainFPS;
                float _GrainIntensity;
                float _GlitchGrainBoost;

                float _GlitchOverride;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv         : TEXCOORD0;
                half4  color      : COLOR;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
                half4  color       : COLOR;
            };

            Varyings vert (Attributes v)
            {
                Varyings o;
                o.positionHCS = TransformObjectToHClip(v.positionOS.xyz);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                o.color = v.color * _Color;
                return o;
            }

            half4 SampleMain(float2 uv)
            {
                return SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv);
            }

            half4 frag (Varyings i) : SV_Target
            {
                float t = _Time.y;

                // ── 1. 글리치 타이밍 (텍스처 곡선) ─────────────────────
                float trig = SAMPLE_TEXTURE2D(_GlitchTimingTex, sampler_GlitchTimingTex,
                                              float2(frac(t * _GlitchTimingSpeed), 0.5)).r;
                float glitch = saturate((trig - _GlitchThreshold) / max(1.0 - _GlitchThreshold, 1e-4));
                glitch = max(glitch, _GlitchOverride);

                // 계단식 시간 → 노이즈 텍스처 룩업 오프셋 (글리치가 "뚝뚝" 바뀌는 느낌)
                float stepTime = floor(t * _GlitchFPS);
                float2 seed = frac(stepTime * float2(0.6180339, 0.2639320));
                float2 grainSeed = frac(floor(t * _GrainFPS) * float2(0.7548776, 0.5698403));

                float2 uv = i.uv;

                // ── 2. 블록 변위 ──────────────────────────────────────
                float2 blockUV = floor(i.uv * _BlockScale.xy) / max(_BlockScale.xy, 1.0);
                half4 block = SAMPLE_TEXTURE2D(_BlockNoiseTex, sampler_point_repeat, blockUV + seed);
                float blockMask = step(1.0 - _BlockAmount, block.g) * step(1e-3, glitch);
                uv.x += (block.r * 2.0 - 1.0) * _BlockDisplace * blockMask * glitch;

                // ── 3. 라인 지터 ──────────────────────────────────────
                float lineV = floor(i.uv.y * _JitterLines) / max(_JitterLines, 1.0);
                float jitter = SAMPLE_TEXTURE2D(_JitterTex, sampler_JitterTex,
                                                float2(lineV, seed.y)).r * 2.0 - 1.0;
                uv.x += jitter * _JitterAmount * lerp(_IdleJitter, 1.0, glitch);

                // ── 4. RGB 분리 ───────────────────────────────────────
                half4 split = SAMPLE_TEXTURE2D(_RGBSplitTex, sampler_point_repeat, blockUV + seed.yx);
                float2 dir = _RGBSplitDir.xy + (split.rg * 2.0 - 1.0) * _RGBSplitTexInfluence;
                float splitAmt = lerp(_IdleRGBSplit, _RGBSplitAmount * (0.5 + split.b), glitch);
                float2 off = dir * splitAmt;

                half4 cR = SampleMain(uv + off);
                half4 cG = SampleMain(uv);
                half4 cB = SampleMain(uv - off);

                // 채널별 프리멀티플라이 → 투명 가장자리에서도 색이 깔끔하게 갈라짐
                half3 rgb = half3(cR.r * cR.a, cG.g * cG.a, cB.b * cB.a);
                half  a   = max(cR.a, max(cG.a, cB.a));

                // ── 5. 블록 색 반전 ───────────────────────────────────
                float inv = step(1.0 - _InvertChance, block.b) * blockMask;
                rgb = lerp(rgb, a - rgb, inv);

                // ── 6. 스캔라인 + 롤 밴드 ─────────────────────────────
                float2 screenUV = i.positionHCS.xy / _ScaledScreenParams.xy;
                float scanV = lerp(i.uv.y, screenUV.y, _ScanlineScreenSpace);

                half scan = SAMPLE_TEXTURE2D(_ScanlineTex, sampler_ScanlineTex,
                                             float2(0.25, scanV * _ScanlineCount + t * _ScanlineSpeed)).r;
                half roll = SAMPLE_TEXTURE2D(_ScanlineTex, sampler_ScanlineTex,
                                             float2(0.75, scanV + t * _RollSpeed)).g;

                rgb *= lerp(1.0, scan, _ScanlineIntensity);
                rgb += roll * _RollIntensity * a;

                // ── 8. 틴트 / 버텍스 컬러 (프리멀티플라이 유지) ───────
                rgb *= i.color.rgb;
                half4 col = half4(rgb, a) * i.color.a;

                col.rgb = clamp(col.rgb, 0.0, col.a);
                return col;
            }
            ENDHLSL
        }
    }

    FallBack Off
}
