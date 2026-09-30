// 하프톤 화면전환 (UI용) - 경량 버전
// _Progress 0→1 : 원이 커지며 덮음 / _Reverse 켜고 0→1 : 같은 방향으로 작아지며 열림
// 화면 위치에 선형인 계산은 모두 버텍스(4개)에서 처리하고, 프래그먼트는 최소 연산만 수행
Shader "UI/HalftoneTransition"
{
    Properties
    {
        _Color     ("Color", Color) = (0, 0, 0, 1)
        _Progress  ("Progress", Range(0, 1)) = 0
        _CellSize  ("Cell Size (px @ Ref Height)", Float) = 48
        _RefHeight ("Reference Height", Float) = 1080
        _Spread    ("Spread", Range(0.01, 1)) = 0.35
        _Angle     ("Grid Angle", Range(0, 90)) = 45
        _Direction ("Direction (XY)", Vector) = (1, 0, 0, 0)
        _Smooth    ("Edge Smooth (px)", Range(0.01, 4)) = 1
        [Toggle] _Reverse ("Reverse (Shrink)", Float) = 0
    }

    SubShader
    {
        Tags { "Queue" = "Transparent" "RenderType" = "Transparent" }
        Cull Off ZWrite Off ZTest [unity_GUIZTestMode]
        Blend SrcAlpha OneMinusSrcAlpha

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            fixed4 _Color;
            float _Progress, _CellSize, _RefHeight, _Spread, _Angle, _Smooth, _Reverse;
            float4 _Direction;

            struct v2f
            {
                float4 pos   : SV_POSITION;
                fixed4 color : COLOR;
                float4 data  : TEXCOORD0;   // xy: 그리드 좌표, z: 진행 값, w: 엣지 선명도
            };

            v2f vert (float4 vertex : POSITION, fixed4 color : COLOR)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(vertex);
                o.color = color * _Color;

                // 화면 중심 기준 px (UI 캔버스는 w가 일정 → 보간해도 정확)
                float4 sp = ComputeScreenPos(o.pos);
                float2 screen = _ScreenParams.xy;
                float2 p = (sp.xy / sp.w - 0.5) * screen;

                // 진행 값: 픽셀 위치에 선형 → 버텍스에서 계산 후 보간
                float2 dir = normalize(_Direction.xy + float2(1e-5, 0));
                float g = dot(p, dir) / dot(abs(dir), screen) + 0.5;
                float prog = (_Progress * (1 + _Spread) - g) / _Spread;

                // 회전된 그리드 좌표
                float cell = _CellSize * screen.y / _RefHeight;
                float s, c;
                sincos(radians(_Angle), s, c);
                float2 gp = float2(c * p.x - s * p.y, s * p.x + c * p.y) / cell;

                o.data = float4(gp, prog, cell / _Smooth);
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                half t = saturate(i.data.z);
                t = t * t * (3 - 2 * t);
                t = abs((half)_Reverse - t);

                half d = length(frac(i.data.xy) - 0.5);   // frac 입력은 float 유지 (half면 정밀도 부족)
                half cov = saturate((t * 0.75 - d) * i.data.w + 0.5) * step(0.001, t);

                return fixed4(i.color.rgb, i.color.a * cov);
            }
            ENDCG
        }
    }
}
