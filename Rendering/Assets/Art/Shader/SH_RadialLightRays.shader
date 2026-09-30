// URP 방사형 빛줄기 셰이더 (클라우드/노이즈 텍스처 버전)
// 절차적 노이즈 대신 텍스처 샘플 2회로 처리 → 모바일에서 더 가벼움
// 텍스처: 흑백 클라우드 노이즈, U축 타일링 가능, Wrap = Repeat, 256~512px, R8 권장
Shader "Custom/URP/RadialLightRays_Tex"
{
    Properties
    {
        _NoiseTex ("Cloud Noise (Tileable)", 2D) = "gray" {}
        [HDR] _Color ("Color", Color) = (1, 0.85, 0.55, 1)
        _Intensity ("Intensity", Range(0, 10)) = 1.5

        [Header(Center)]
        _Center ("Center (UV)", Vector) = (0.5, 0.5, 0, 0)

        [Header(Rays)]
        _NoiseTiling ("Noise Tiling (X=Angle, Y=Radial)", Vector) = (6, 1.5, 0, 0)
        _DetailTiling ("Detail Tiling (X=Angle, Y=Radial)", Vector) = (13, 2.3, 0, 0)
        _DetailMix ("Detail Mix", Range(0, 1)) = 0.35
        _RayCoverage ("Ray Coverage", Range(0, 1)) = 0.55
        _RaySharpness ("Ray Sharpness", Range(0.5, 16)) = 3

        [Header(Motion)]
        _FlowSpeed ("Outward Flow Speed", Float) = 0.3
        _DetailFlowSpeed ("Detail Flow Speed", Float) = 0.45
        _RotateSpeed ("Rotate Speed", Float) = 0.02
        _Flicker ("Flicker", Range(0, 1)) = 0.15

        [Header(Radial Fade)]
        _InnerRadius ("Inner Radius", Range(0, 1)) = 0.05
        _InnerSoft ("Inner Softness", Range(0.001, 1)) = 0.15
        _OuterRadius ("Outer Radius", Range(0, 1.5)) = 1.0
        _OuterSoft ("Outer Softness", Range(0.001, 1)) = 0.6
        _Falloff ("Distance Falloff", Range(0, 8)) = 1.2

        [Header(Core Glow)]
        _CoreIntensity ("Core Intensity", Range(0, 10)) = 1.0
        _CoreSize ("Core Tightness", Range(1, 200)) = 40

        [Header(Blending)]
        [Enum(UnityEngine.Rendering.BlendMode)] _SrcBlend ("Src Blend", Float) = 1   // One
        [Enum(UnityEngine.Rendering.BlendMode)] _DstBlend ("Dst Blend", Float) = 1   // One (Additive)
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Transparent"
            "Queue" = "Transparent"
            "IgnoreProjector" = "True"
        }

        Pass
        {
            Name "RadialRaysTex"
            Blend [_SrcBlend] [_DstBlend]
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_NoiseTex);
            SAMPLER(sampler_NoiseTex);

            CBUFFER_START(UnityPerMaterial)
                float4 _NoiseTex_ST;
                half4  _Color;
                half   _Intensity;
                float4 _Center;
                float4 _NoiseTiling;
                float4 _DetailTiling;
                half   _DetailMix;
                half   _RayCoverage;
                half   _RaySharpness;
                float  _FlowSpeed;
                float  _DetailFlowSpeed;
                float  _RotateSpeed;
                half   _Flicker;
                half   _InnerRadius;
                half   _InnerSoft;
                half   _OuterRadius;
                half   _OuterSoft;
                half   _Falloff;
                half   _CoreIntensity;
                half   _CoreSize;
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
                o.uv = v.uv;
                o.color = v.color;
                return o;
            }

            half4 frag (Varyings i) : SV_Target
            {
                float t = _Time.y;

                // 극좌표
                float2 d = i.uv - _Center.xy;
                float r = length(d) * 2.0;
                float ang = atan2(d.y, d.x) / TWO_PI + 0.5;     // 0..1 (경계에서 불연속)

                // atan2 경계(0↔1) 밉맵 이음새 방지용 미분 보정
                float angAlt = frac(ang + 0.5);
                float dAngX = ddx(ang); float dAltX = ddx(angAlt);
                float dAngY = ddy(ang); float dAltY = ddy(angAlt);
                dAngX = abs(dAngX) < abs(dAltX) ? dAngX : dAltX;
                dAngY = abs(dAngY) < abs(dAltY) ? dAngY : dAltY;
                float dRX = ddx(r);
                float dRY = ddy(r);

                ang += t * _RotateSpeed;   // Repeat 래핑이라 frac 불필요

                // 메인 레이어: 각도=광선, (r - time)=바깥으로 흐름
                float2 uv1 = float2(ang * _NoiseTiling.x, r * _NoiseTiling.y - t * _FlowSpeed);
                float2 g1x = float2(dAngX * _NoiseTiling.x, dRX * _NoiseTiling.y);
                float2 g1y = float2(dAngY * _NoiseTiling.x, dRY * _NoiseTiling.y);
                half n1 = SAMPLE_TEXTURE2D_GRAD(_NoiseTex, sampler_NoiseTex, uv1, g1x, g1y).r;

                // 디테일 레이어: 다른 스케일/속도로 반복감 감소
                float2 uv2 = float2(ang * _DetailTiling.x + 0.37, r * _DetailTiling.y - t * _DetailFlowSpeed);
                float2 g2x = float2(dAngX * _DetailTiling.x, dRX * _DetailTiling.y);
                float2 g2y = float2(dAngY * _DetailTiling.x, dRY * _DetailTiling.y);
                half n2 = SAMPLE_TEXTURE2D_GRAD(_NoiseTex, sampler_NoiseTex, uv2, g2x, g2y).r;

                half n = lerp(n1, n2, _DetailMix);

                // 광선 폭/선명도
                half rays = saturate(n + _RayCoverage - 0.5);
                rays = pow(rays * 2.0, _RaySharpness) * 0.5;

                // 반경 페이드
                half inner = smoothstep(_InnerRadius, _InnerRadius + _InnerSoft, r);
                half outer = 1.0 - smoothstep(_OuterRadius - _OuterSoft, _OuterRadius, r);
                half falloff = pow(saturate(1.0 - r / max(_OuterRadius, 1e-3)), _Falloff);
                rays *= inner * outer * falloff;

                // 깜빡임
                half flicker = 1.0 - _Flicker * (0.5 + 0.5 * sin(t * 7.3) * sin(t * 3.1 + 1.7));
                rays *= flicker;

                // 코어 글로우
                half core = exp(-r * r * _CoreSize) * _CoreIntensity;

                half mask = (rays + core) * _Intensity * i.color.a * _Color.a;
                half3 col = _Color.rgb * i.color.rgb * mask;

                return half4(col, saturate(mask));
            }
            ENDHLSL
        }
    }

    FallBack Off
}
