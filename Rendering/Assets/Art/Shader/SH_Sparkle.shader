// 반짝임(Sparkle) VFX - 텍스처 없는 절차적 셰이더
// 쿼드 하나에 적용 (MeshRenderer / Particle System / UI Image 모두 가능)
// 1루프 구성 (60fps 기준 60프레임)
//   0~27f  : 아크 4개(노랑→빨강→연두→진홍)가 회전하며 커지고 얇아짐
//   24~40f : 4방향 별이 통통하게 커짐, 38~40f 마름모 플래시
//   40~57f : 별이 가시형으로 가늘어지며 축소, 색 깜빡임
//   30f~   : 스파크 조각이 바깥으로 흩어지며 점으로 사라짐
Shader "VFX/Sparkle"
{
    Properties
    {
        _Progress ("Progress", Range(0, 1)) = 0
        [Toggle] _AutoPlay ("Auto Play (Loop)", Float) = 1
        _Speed ("Loops / sec", Float) = 1
        [Toggle] _UseCustomData ("Progress from Particle Custom Data (UV0.z)", Float) = 0

        [Header(Arcs)]
        _ArcColor0 ("Arc 1", Color) = (1.00, 0.95, 0.10, 1)
        _ArcColor1 ("Arc 2", Color) = (0.90, 0.02, 0.20, 1)
        _ArcColor2 ("Arc 3", Color) = (0.65, 0.88, 0.35, 1)
        _ArcColor3 ("Arc 4", Color) = (0.60, 0.00, 0.30, 1)

        [Header(Star)]
        _StarGrow  ("Star Grow", Color)     = (0.62, 0.30, 0.90, 1)
        _StarPeak  ("Star Peak", Color)     = (0.80, 0.30, 0.80, 1)
        _StarFlickA ("Star Flicker A", Color) = (0.88, 0.00, 0.85, 1)
        _StarFlickB ("Star Flicker B", Color) = (0.60, 0.00, 0.80, 1)
        _CoreA ("Core A", Color) = (0.20, 0.65, 0.95, 1)
        _CoreB ("Core B", Color) = (0.78, 0.58, 0.82, 1)
        _CoreC ("Core C", Color) = (0.10, 0.05, 0.95, 1)
        _DiamondColor ("Diamond Flash", Color) = (0.85, 0.00, 0.85, 1)
    }

    SubShader
    {
        Tags { "Queue" = "Transparent" "RenderType" = "Transparent" "IgnoreProjector" = "True" "PreviewType" = "Plane" }
        Cull Off ZWrite Off
        Blend One OneMinusSrcAlpha   // 프리멀티플라이드 알파

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            float _Progress, _AutoPlay, _Speed, _UseCustomData;
            fixed4 _ArcColor0, _ArcColor1, _ArcColor2, _ArcColor3;
            fixed4 _StarGrow, _StarPeak, _StarFlickA, _StarFlickB;
            fixed4 _CoreA, _CoreB, _CoreC, _DiamondColor;

            struct v2f
            {
                float4 pos   : SV_POSITION;
                fixed4 color : COLOR;
                float3 uv    : TEXCOORD0;   // xy: -1~1 쿼드 좌표, z: 진행도
            };

            v2f vert (float4 vertex : POSITION, fixed4 color : COLOR, float4 uv : TEXCOORD0)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(vertex);
                o.color = color;
                float t = lerp(_Progress, frac(_Time.y * _Speed), _AutoPlay);
                o.uv = float3(uv.xy * 2 - 1, lerp(t, frac(uv.z), _UseCustomData));
                return o;
            }

            // ---------- 헬퍼 ----------
            // SDF 커버리지 (d < 0 내부)
            float Cov(float d, float aa) { return saturate(0.5 - d / aa); }

            // 프리멀티플라이드 over 합성
            void Over(inout float4 acc, float3 c, float a) { acc = float4(c, 1) * a + acc * (1 - a); }

            // 초승달 아크
            // a0: 시작t, 끝t, 시작반지름, 끝반지름 / a1: 중심각, 회전량, 시작반폭, 끝반폭 / a2: 두께, 성장시간
            float Arc(float2 pol, float t, float4 a0, float4 a1, float2 a2, float aa)
            {
                float life = saturate((t - a0.x) / (a0.y - a0.x));
                float g = saturate((t - a0.x) / a2.y);
                float R = lerp(a0.z, a0.w, g * (1.5 - 0.5 * g));
                float h = lerp(a1.z, a1.w, life);
                float m = a1.x + a1.y * life;

                float da = abs(frac((pol.y - m) / UNITY_TWO_PI + 0.5) - 0.5) * UNITY_TWO_PI;
                float th = a2.x * pow(1 - life, 0.9) * sqrt(saturate(1 - da / h));   // 가운데 두껍고 끝이 뾰족
                float d = abs(pol.x - (R - th * 0.5)) - th * 0.5;

                float fade = saturate((t - a0.x) / 0.02) * saturate((a0.y - t) / 0.15);
                return Cov(d, aa) * saturate(th / aa) * fade;
            }

            // 4방향 별: |x|^e + |y|^e = s^e  (e=1 마름모, e<1 오목한 별)
            float Star(float2 p, float s, float e)
            {
                float2 q = abs(p) / max(s, 1e-4) + 1e-5;
                float k = pow(q.x, e) + pow(q.y, e);
                return saturate((1 - k) / (fwidth(k) + 1e-5) + 0.5) * step(0.002, s);
            }

            // 얇은 십자선 (픽셀보다 가는 가시 보완)
            float CrossLine(float2 p, float L, float w, float aa)
            {
                float2 a = abs(p);
                float tx = w * saturate(1 - a.x / max(L, 1e-4));
                float ty = w * saturate(1 - a.y / max(L, 1e-4));
                return max(Cov(a.y - tx, aa) * saturate(2 * tx / aa),
                           Cov(a.x - ty, aa) * saturate(2 * ty / aa));
            }

            // 스파크 조각: 바깥으로 날아가며 꼬리가 줄어 점이 됨 (다음 루프 초반까지 이어짐)
            float Spark(float2 p, float t, float ang, float t0, float aa)
            {
                float life = frac(t - t0) / 0.6;
                float lc = saturate(life);
                float2 dir;
                sincos(ang, dir.y, dir.x);

                float head = 0.15 + 0.75 * (1 - (1 - lc) * (1 - lc));
                float len = 0.16 * pow(1 - lc, 2.5) + 0.01;
                float wd = 0.018 * (1 - 0.5 * lc);

                float al = dot(p, dir);
                float pe = dot(p, float2(-dir.y, dir.x));
                float u = saturate((al - (head - len)) / len);
                float dist = length(float2(al - clamp(al, head - len, head), pe));

                return Cov(dist - wd * (0.25 + 0.75 * u), aa) * saturate((1 - life) / 0.15);
            }

            // ---------- 메인 ----------
            fixed4 frag (v2f i) : SV_Target
            {
                float2 p = i.uv.xy;
                float t = i.uv.z;
                float aa = length(fwidth(p)) * 0.8;
                float2 pol = float2(length(p), atan2(p.y, p.x));
                float4 acc = 0;

                // 1) 아크 4개
                Over(acc, _ArcColor0.rgb, Arc(pol, t, float4(0.05, 0.62, 0.10, 0.84), float4( 2.00,  0.6, 1.0, 2.2), float2(0.090, 0.40), aa));
                Over(acc, _ArcColor1.rgb, Arc(pol, t, float4(0.16, 0.80, 0.28, 0.84), float4( 0.70, -0.4, 1.0, 2.2), float2(0.080, 0.40), aa));
                Over(acc, _ArcColor2.rgb, Arc(pol, t, float4(0.26, 0.88, 0.20, 0.82), float4(-0.75, -1.0, 0.9, 2.2), float2(0.075, 0.40), aa));
                Over(acc, _ArcColor3.rgb, Arc(pol, t, float4(0.38, 0.82, 0.32, 0.64), float4( 3.70, -0.4, 1.0, 2.0), float2(0.065, 0.30), aa));

                // 2) 마름모 플래시
                float dia = smoothstep(0.625, 0.635, t) * (1 - smoothstep(0.685, 0.695, t));
                Over(acc, _DiamondColor.rgb, Cov(abs(p.x) + abs(p.y) - 0.52, aa) * dia);

                // 3) 스파크 (각도 rad, 시작t)
                Over(acc, float3(0.85, 0.85, 0.85), Spark(p, t, 1.658, 0.50, aa));   //  95°
                Over(acc, float3(0.45, 0.90, 0.40), Spark(p, t, 5.760, 0.50, aa));   // 330°
                Over(acc, float3(0.88, 0.60, 0.82), Spark(p, t, 3.752, 0.50, aa));   // 215°
                Over(acc, float3(0.35, 0.00, 0.25), Spark(p, t, 4.363, 0.53, aa));   // 250°
                Over(acc, float3(0.55, 0.10, 0.60), Spark(p, t, 2.618, 0.54, aa));   // 150°
                Over(acc, float3(0.55, 0.10, 0.60), Spark(p, t, 0.087, 0.56, aa));   //   5°

                // 4) 별 타임라인
                float s = 0.90 * pow(saturate((t - 0.40) / 0.22), 2.3) * (1 - 0.8 * smoothstep(0.78, 1.0, t));
                float e = lerp(0.80, 0.26, pow(saturate((t - 0.52) / 0.28), 0.6));

                // 색 깜빡임 (3프레임 단위)
                float idx = floor(t * 20);
                float3 outer = lerp(_StarGrow.rgb, _StarPeak.rgb, step(0.58, t));
                outer = lerp(outer, lerp(_StarFlickA.rgb, _StarFlickB.rgb, fmod(idx, 2)), step(0.66, t));
                float m3 = fmod(idx + 1, 3);
                float3 core = lerp(_CoreA.rgb, lerp(_CoreB.rgb, _CoreC.rgb, step(1.5, m3)), step(0.5, m3));
                core = lerp(_CoreB.rgb, core, step(0.68, t));

                float crossLine = CrossLine(p, s, 0.012, aa) * smoothstep(0.62, 0.64, t) * step(0.002, s);
                Over(acc, outer, max(Star(p, s, e), crossLine));

                float coreOn = smoothstep(0.655, 0.665, t) * (1 - smoothstep(0.90, 0.95, t));
                Over(acc, core, Star(p, s * 0.45, e * 1.3) * coreOn);

                return acc * i.color.a * float4(i.color.rgb, 1);
            }
            ENDCG
        }
    }
}
