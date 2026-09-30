// 하프톤 화면전환 (UI용) - 해상도 독립 버전
// _Progress 0→1 : 원이 커지며 덮음 / _Reverse 켜고 0→1 : 같은 방향으로 작아지며 열림
// 그리드 = 캔버스 로컬 좌표(Canvas Scaler 기준 유닛), 진행 = 이미지 UV → 해상도와 무관하게 동일
Shader "UI/HalftoneTransition"
{
    Properties
    {
        _Color     ("Color", Color) = (0, 0, 0, 1)
        _Progress  ("Progress", Range(0, 1)) = 0
        _CellSize  ("Cell Size (Canvas Units)", Float) = 48
        _Spread    ("Spread", Range(0.01, 1)) = 0.35
        _Angle     ("Grid Angle", Range(0, 90)) = 45
        _Direction ("Direction (XY)", Vector) = (1, 0, 0, 0)
        _Smooth    ("Edge Smooth (px)", Range(0.5, 4)) = 1
        [Toggle] _Reverse ("Reverse (Shrink)", Float) = 0
    }

    SubShader
    {
        Tags { "Queue" = "Transparent" "RenderType" = "Transparent" "IgnoreProjector" = "True" "CanUseSpriteAtlas" = "False" }
        Cull Off ZWrite Off ZTest [unity_GUIZTestMode]
        Blend SrcAlpha OneMinusSrcAlpha

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            fixed4 _Color;
            float _Progress, _CellSize, _Spread, _Angle, _Smooth, _Reverse;
            float4 _Direction;

            struct appdata
            {
                float4 vertex : POSITION;
                fixed4 color  : COLOR;
                float2 uv     : TEXCOORD0;
            };

            struct v2f
            {
                float4 pos   : SV_POSITION;
                fixed4 color : COLOR;
                float3 data  : TEXCOORD0;   // xy: 그리드 좌표, z: 진행 값
            };

            v2f vert (appdata v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.color = v.color * _Color;

                // 진행 값: UV 기준 (이미지 가장자리 → 반대편 가장자리)
                float2 dir = normalize(_Direction.xy + float2(1e-5, 0));
                float g = dot(v.uv - 0.5, dir) / dot(abs(dir), 1) + 0.5;
                o.data.z = (_Progress * (1 + _Spread) - g) / _Spread;

                // 그리드: 캔버스 로컬 좌표 (Canvas Scaler가 해상도 보정)
                float s, c;
                sincos(radians(_Angle), s, c);
                float2 p = v.vertex.xy;
                o.data.xy = float2(c * p.x - s * p.y, s * p.x + c * p.y) / _CellSize;
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                half t = saturate(i.data.z);
                t = t * t * (3 - 2 * t);
                t = abs((half)_Reverse - t);

                float2 gp = i.data.xy;
                half d = length(frac(gp) - 0.5);

                // 1px당 그리드 좌표 변화량 → 실제 픽셀 기준 AA
                float aa = 1.0 / (length(fwidth(gp)) * 0.7071 * _Smooth);
                half cov = saturate((t * 0.75 - d) * aa + 0.5) * step(0.001, t);

                return fixed4(i.color.rgb, i.color.a * cov);
            }
            ENDCG
        }
    }
}