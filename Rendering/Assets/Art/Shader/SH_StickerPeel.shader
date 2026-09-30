// Sticker Peel (fold) effect - SpriteRenderer / UI Image
// Built-in & URP 둘 다 동작 (Unlit, Transparent)
Shader "Custom/StickerPeel"
{
    Properties
    {
        [PerRendererData] _MainTex ("Sprite Texture", 2D) = "white" {}
        _Color ("Tint", Color) = (1,1,1,1)

        _Angle ("Angle (Degrees)", Range(0, 360)) = 45
        _Slide ("Slide", Range(0, 1)) = 0

        _BackColor ("Back Color", Color) = (1, 0.97, 0.68, 1)
        _FoldShade ("Fold Shade (접힌 선 근처 어둡기)", Range(0, 1)) = 0.35
        _FoldShadeWidth ("Fold Shade Width", Range(0.001, 0.5)) = 0.12
        _EdgeHighlight ("Fold Edge Highlight", Range(0, 1)) = 0.25

        _ShadowColor ("Shadow Color", Color) = (0, 0, 0, 1)
        _ShadowStrength ("Shadow Strength", Range(0, 1)) = 0.35
        _ShadowOffset ("Shadow Offset (UV)", Vector) = (0.015, -0.02, 0, 0)
        _CreaseShadow ("Crease Shadow (접힌 선 아래 앞면)", Range(0, 1)) = 0.25

        _Expand ("Quad Expand", Range(1, 5)) = 3
    }

    SubShader
    {
        Tags
        {
            "Queue" = "Transparent"
            "RenderType" = "Transparent"
            "IgnoreProjector" = "True"
            "PreviewType" = "Plane"
            "CanUseSpriteAtlas" = "False"
        }

        Cull Off
        Lighting Off
        ZWrite Off
        Blend One OneMinusSrcAlpha   // premultiplied

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv     : TEXCOORD0;
                float4 color  : COLOR;
            };

            struct v2f
            {
                float4 pos   : SV_POSITION;
                float2 uv    : TEXCOORD0;
                float4 color : COLOR;
            };

            sampler2D _MainTex;
            float4 _Color;
            float  _Angle, _Slide;
            float4 _BackColor;
            float  _FoldShade, _FoldShadeWidth, _EdgeHighlight;
            float4 _ShadowColor;
            float  _ShadowStrength, _CreaseShadow;
            float4 _ShadowOffset;
            float  _Expand;

            v2f vert (appdata v)
            {
                v2f o;
                // 접힌 조각이 원래 사각형 밖으로 나가므로 쿼드를 키움 (피벗 = 중앙 기준)
                v.vertex.xy *= _Expand;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.uv = (v.uv - 0.5) * _Expand + 0.5;
                o.color = v.color * _Color;
                return o;
            }

            // 0~1 범위 밖은 투명 처리
            float4 SampleClamp (float2 uv)
            {
                float2 inside = step(0, uv) * step(uv, 1);
                float4 c = tex2D(_MainTex, saturate(uv));
                return c * (inside.x * inside.y);
            }

            // 접힌 조각(뒷면)의 알파 & 반사 좌표
            // p : 중앙 기준 좌표, dir : 접는 방향, L : 접힌 선 위치
            float FlapAlpha (float2 p, float2 dir, float L, out float dist)
            {
                float s = dot(p, dir);
                dist = L - s;                                // 접힌 선까지 거리 (+ = 남아있는 쪽)
                float2 pr = p + 2.0 * dist * dir;            // 접힌 선 기준 반사
                return SampleClamp(pr + 0.5).a * step(0, dist);
            }

            float4 frag (v2f i) : SV_Target
            {
                float rad = radians(_Angle);
                float2 dir = float2(cos(rad), sin(rad));

                // Slide 0 = 안 접힘, 1 = 완전히 넘어감
                const float R = 0.7072;                      // 중심~모서리 거리
                float L = lerp(R, -R, _Slide);

                float2 p = i.uv - 0.5;
                float s = dot(p, dir);
                float dist = L - s;

                // 접힌 선 경계 안티앨리어싱
                float aa = max(fwidth(s), 1e-5);
                float keep = saturate(dist / aa + 0.5);

                // ---------- 앞면 (남은 부분) ----------
                float4 front = SampleClamp(i.uv) * i.color;
                front.a *= keep;

                // 접힌 조각이 앞면에 드리우는 그림자
                float dummy;
                float shadowA = FlapAlpha(p - _ShadowOffset.xy, dir, L, dummy);
                // 접힌 선 바로 아래의 주름 그림자
                float crease = (1.0 - saturate(dist / _FoldShadeWidth)) * _CreaseShadow * step(0.0001, _Slide);
                float shade = saturate(shadowA * _ShadowStrength + crease);
                front.rgb = lerp(front.rgb, _ShadowColor.rgb, shade);
                front.rgb *= front.a;                        // premultiply

                // ---------- 뒷면 (접힌 조각) ----------
                float2 pr = p + 2.0 * dist * dir;
                float backA = SampleClamp(pr + 0.5).a * keep * step(0.0001, _Slide);

                // 접힌 선 근처는 어둡게, 가장자리엔 살짝 하이라이트 (말려 올라간 느낌)
                float t = saturate(dist / _FoldShadeWidth);
                float3 back = _BackColor.rgb * lerp(1.0 - _FoldShade, 1.0, smoothstep(0, 1, t));
                float edge = 1.0 - saturate(dist / (_FoldShadeWidth * 0.25));
                back += _EdgeHighlight * edge * (1.0 - edge) * 4.0;
                backA *= i.color.a;

                // ---------- 합성 (뒷면이 위) ----------
                float4 col;
                col.rgb = back * backA + front.rgb * (1.0 - backA);
                col.a   = backA + front.a * (1.0 - backA);
                return col;
            }
            ENDCG
        }
    }
}
