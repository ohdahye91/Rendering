// UI용 종이 구김 셰이더 (UGUI, Built-in / URP 공용)
// 반드시 CrumpleImage 컴포넌트와 함께 사용 (그리드 메시 + 버텍스 채널로 크기/구김값 전달)
//   TEXCOORD1 = (rect width, rect height, crumple 0~1, seed)
//   TEXCOORD2 = (grid u, grid v)  0~1
Shader "UI/CrumplePaper"
{
    Properties
    {
        [PerRendererData] _MainTex ("Texture", 2D) = "white" {}
        _Color          ("Tint", Color) = (1,1,1,1)
        _BackColor      ("Back Side Color", Color) = (0.9,0.9,0.88,1)

        [Header(Wrinkle Phase)]
        _WrinkleScale   ("Wrinkle Scale", Float) = 3.5
        _WrinkleStrength("Wrinkle Strength", Float) = 0.12
        _Shrink         ("Wrinkle Shrink", Range(0,0.5)) = 0.12

        [Header(Ball Phase)]
        _BallRadius     ("Ball Radius", Float) = 0.2
        _BallFold       ("Ball Fold Frequency", Float) = 3.0
        _BallBump       ("Ball Bump", Float) = 0.7
        _BallChaos      ("Ball Chaos", Range(0,2)) = 0.9
        _Spin           ("Ball Spin (rad)", Float) = 2.5

        [Header(Fake 3D)]
        _Perspective    ("Perspective", Range(0,2)) = 0.6
        _LightDir       ("Light Direction", Vector) = (-0.4, 0.6, -0.7, 0)
        _Ambient        ("Ambient", Range(0,1)) = 0.55
        _Wrap           ("Wrap Lighting", Range(0,1)) = 0.35
        _CreaseShadow   ("Crease Darkening", Range(0,1)) = 0.3
        [Enum(Off,0,On,1)] _ZWrite ("ZWrite (접힘 겹침 정렬)", Float) = 1

        // ---- UGUI 기본 ----
        _StencilComp ("Stencil Comparison", Float) = 8
        _Stencil ("Stencil ID", Float) = 0
        _StencilOp ("Stencil Operation", Float) = 0
        _StencilWriteMask ("Stencil Write Mask", Float) = 255
        _StencilReadMask ("Stencil Read Mask", Float) = 255
        _ColorMask ("Color Mask", Float) = 15
        [Toggle(UNITY_UI_ALPHACLIP)] _UseUIAlphaClip ("Use Alpha Clip", Float) = 0
    }

    SubShader
    {
        Tags
        {
            "Queue"="Transparent" "IgnoreProjector"="True" "RenderType"="Transparent"
            "PreviewType"="Plane" "CanUseSpriteAtlas"="True"
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
        ZWrite [_ZWrite]
        ZTest [unity_GUIZTestMode]
        Blend SrcAlpha OneMinusSrcAlpha
        ColorMask [_ColorMask]

        Pass
        {
            Name "Default"
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0
            #include "UnityCG.cginc"
            #include "UnityUI.cginc"
            #pragma multi_compile_local _ UNITY_UI_CLIP_RECT
            #pragma multi_compile_local _ UNITY_UI_ALPHACLIP

            struct appdata_t
            {
                float4 vertex : POSITION;
                float4 color  : COLOR;
                float2 uv0    : TEXCOORD0;
                float4 uv1    : TEXCOORD1; // w, h, crumple, seed
                float2 uv2    : TEXCOORD2; // grid uv
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
                float4 vertex        : SV_POSITION;
                fixed4 color         : COLOR;
                float2 uv            : TEXCOORD0;
                float4 worldPosition : TEXCOORD1;
                float3 shapePos      : TEXCOORD2; // 조명용 3D 위치 (정규화 단위)
                float  crease        : TEXCOORD3;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;
            fixed4 _Color, _BackColor, _TextureSampleAdd;
            float4 _ClipRect;
            float  _WrinkleScale, _WrinkleStrength, _Shrink;
            float  _BallRadius, _BallFold, _BallBump, _BallChaos, _Spin;
            float  _Perspective, _Ambient, _Wrap, _CreaseShadow;
            float4 _LightDir;

            // ---------- noise ----------
            float hash31(float3 p)
            {
                p = frac(p * 0.1031);
                p += dot(p, p.zyx + 31.32);
                return frac((p.x + p.y) * p.z);
            }

            float noise3(float3 p)
            {
                float3 i = floor(p), f = frac(p);
                float3 u = f * f * (3.0 - 2.0 * f);
                return lerp(lerp(lerp(hash31(i),                  hash31(i + float3(1,0,0)), u.x),
                                 lerp(hash31(i + float3(0,1,0)),  hash31(i + float3(1,1,0)), u.x), u.y),
                            lerp(lerp(hash31(i + float3(0,0,1)),  hash31(i + float3(1,0,1)), u.x),
                                 lerp(hash31(i + float3(0,1,1)),  hash31(i + float3(1,1,1)), u.x), u.y), u.z);
            }

            float ridgedFbm(float3 p)
            {
                float sum = 0, amp = 0.55, norm = 0;
                [unroll] for (int k = 0; k < 4; k++)
                {
                    float r = 1.0 - abs(noise3(p) * 2.0 - 1.0);
                    sum += r * amp; norm += amp;
                    p = p * 2.03 + 17.1; amp *= 0.5;
                }
                return sum / norm;
            }

            float3 noiseVec(float3 p) { return float3(noise3(p), noise3(p + 31.7), noise3(p + 73.3)) - 0.5; }
            float3 rotateY(float3 p, float a) { float s = sin(a), c = cos(a); return float3(c*p.x + s*p.z, p.y, -s*p.x + c*p.z); }
            float3 rotateX(float3 p, float a) { float s = sin(a), c = cos(a); return float3(p.x, c*p.y - s*p.z, s*p.y + c*p.z); }

            // p0 : 정규화된 평면 좌표 (짧은 변 = 1), g : 그리드 uv
            float3 Crumple(float3 p0, float2 g, float2 halfN, float t, float seedF, out float crease)
            {
                float wrinkleW = saturate(t * 2.5);
                float ballW    = smoothstep(0.3, 1.0, t);
                float3 seed    = float3(seedF * 13.1, seedF * 7.7, seedF * 3.3);

                // 1) 주름
                float3 wp = float3(g * _WrinkleScale, 0) + seed;
                float  n  = ridgedFbm(wp);
                float  amp = _WrinkleStrength * wrinkleW * (1.0 + 1.5 * sin(ballW * UNITY_PI));
                float3 p = p0;
                p.xy += noiseVec(wp * 0.7).xy * amp * 0.8;
                p.xy *= 1.0 - _Shrink * wrinkleW;
                p.z  += (n - 0.5) * amp * 2.0;

                // 2) 공
                float  r   = length(p0.xy) / length(halfN);
                float  phi = atan2(p0.y, p0.x);
                float  th  = saturate(r) * UNITY_PI * 0.97;
                float3 sp  = float3(sin(th) * cos(phi), sin(th) * sin(phi), -cos(th));
                sp = normalize(sp + noiseVec(sp * 2.0 + seed) * _BallChaos);
                float  nb  = ridgedFbm(sp * _BallFold + seed + 5.0);
                float3 ball = sp * _BallRadius * (1.0 + (nb - 0.5) * _BallBump);
                ball = rotateX(rotateY(ball, _Spin * ballW), _Spin * 0.6 * ballW);

                crease = lerp(n, nb, ballW) * saturate(t * 4.0);
                return lerp(p, ball, ballW);
            }

            v2f vert(appdata_t v)
            {
                v2f o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

                float2 size  = max(v.uv1.xy, 1e-3);
                float  t     = v.uv1.z;
                float  s     = min(size.x, size.y);        // 정규화 기준 길이(px)
                float2 g     = v.uv2;
                float2 center = v.vertex.xy - (g - 0.5) * size;
                float2 halfN = 0.5 * size / s;

                float3 p0 = float3((g - 0.5) * size / s, 0);
                float crease;
                float3 p = Crumple(p0, g, halfN, t, v.uv1.w, crease);

                // 가짜 원근 : 카메라 쪽(-Z)으로 나온 부분을 키움
                float persp = 1.0 / max(0.2, 1.0 + p.z * _Perspective);

                float4 pos = v.vertex;
                pos.xy = center + p.xy * s * persp;
                pos.z  = v.vertex.z + p.z * s;

                o.worldPosition = pos;
                o.vertex   = UnityObjectToClipPos(pos);
                o.uv       = TRANSFORM_TEX(v.uv0, _MainTex);
                o.color    = v.color * _Color;
                o.shapePos = p;
                o.crease   = crease;
                return o;
            }

            fixed4 frag(v2f i, fixed facing : VFACE) : SV_Target
            {
                fixed4 tex = (tex2D(_MainTex, i.uv) + _TextureSampleAdd) * i.color;
                fixed4 col = facing > 0 ? tex : fixed4(_BackColor.rgb, tex.a);

                // 패싯 노멀 (보는 쪽 = -Z)
                float3 N = normalize(cross(ddx(i.shapePos), ddy(i.shapePos)));
                if (N.z > 0) N = -N;
                float3 L = normalize(_LightDir.xyz);
                float diff = saturate((dot(N, L) + _Wrap) / (1.0 + _Wrap));
                float light = lerp(_Ambient, 1.0, diff);

                float creaseAO = lerp(1.0, 1.0 - _CreaseShadow, smoothstep(0.55, 0.95, i.crease));
                col.rgb *= light * creaseAO;

                #ifdef UNITY_UI_CLIP_RECT
                col.a *= UnityGet2DClipping(i.worldPosition.xy, _ClipRect);
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
