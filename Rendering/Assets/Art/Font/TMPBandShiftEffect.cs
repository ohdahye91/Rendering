using System.Collections.Generic;
using TMPro;
using UnityEngine;
using UnityEngine.Rendering;

/// <summary>
/// TMP 텍스트 전체를 가로 띠(Band)로 잘라서 띠마다 좌우로 밀어내는 계단식 효과.
/// - 렌더텍스처 / 커스텀 쉐이더 불필요 (기본 TMP SDF 쉐이더 그대로 사용 → 아웃라인/언더레이 유지)
/// - 띠는 글자 단위가 아니라 줄(또는 텍스트 전체) 기준으로 나뉘어서 모든 글자에 이어지게 적용됨
/// - offset 0 = 원본, 값이 커질수록 띠가 벌어짐 (Animator / DOTween 으로 offset 애니메이션)
/// - TextMeshProUGUI / TextMeshPro(3D), 폴백 폰트(서브메시), maxVisibleCharacters 타이핑과 호환
/// </summary>
[ExecuteAlways]
[DisallowMultipleComponent]
[RequireComponent(typeof(TMP_Text))]
public class TMPBandShiftEffect : MonoBehaviour
{
    public enum BandSpace { PerLine, WholeText }

    [Header("Offset")]
    [Tooltip("효과 진행값. 0 = 원본, 1 = 최대 (음수면 반대 방향)")]
    public float offset = 0f;

    [Tooltip("offset = 1 일 때 최대 밀림 거리 (줄 높이 대비 비율)")]
    public float maxShift = 0.12f;

    [Header("Bands")]
    [Tooltip("PerLine: 줄마다 띠를 나눔 / WholeText: 텍스트 전체 높이를 한 번에 나눔")]
    public BandSpace bandSpace = BandSpace.PerLine;

    [Tooltip("띠 개수 (줄 높이 또는 전체 높이 기준)")]
    [Min(1)] public int bandCount = 10;

    [Tooltip("띠 경계를 위아래로 이동 (1 = 띠 한 칸)")]
    public float bandPhase = 0f;

    [Header("Pattern Weights")]
    [Tooltip("홀/짝 띠가 서로 반대로 밀림 → 체크무늬 계단")]
    public float alternate = 1f;

    [Tooltip("아래에서 위로 갈수록 점점 더 밀림 → 대각선 계단")]
    public float staircase = 0f;

    [Tooltip("띠마다 랜덤하게 밀림")]
    public float random = 0f;

    [Tooltip("랜덤 패턴 시드")]
    public int seed = 0;

    [Tooltip("띠 내부 기울기. 이탤릭 폰트에 음수를 주면 띠 안에서 기울기가 펴져서 블록 계단처럼 보임")]
    public float bandSkew = 0f;

    // ------------------------------------------------------------------ state

    class Source
    {
        public Mesh tmpMesh;
        public Mesh output;
        public readonly List<Vector3> pos = new List<Vector3>();
        public readonly List<Vector4> uv0 = new List<Vector4>();
        public readonly List<Vector4> uv1 = new List<Vector4>();
        public readonly List<Color32> col = new List<Color32>();
        public readonly List<Vector3> nrm = new List<Vector3>();
        public readonly List<Vector4> tan = new List<Vector4>();
    }

    TMP_Text _tmp;
    bool _isUI;
    bool _needsForce = true;
    int _paramHash;

    readonly List<Source> _sources = new List<Source>();
    int _sourceCount;

    float[] _lineMin = new float[8];
    float[] _lineMax = new float[8];
    int _lineCount;

    // build buffers
    readonly List<Vector3> _p = new List<Vector3>();
    readonly List<Vector4> _u0 = new List<Vector4>();
    readonly List<Vector4> _u1 = new List<Vector4>();
    readonly List<Color32> _c = new List<Color32>();
    readonly List<Vector3> _n = new List<Vector3>();
    readonly List<Vector4> _t = new List<Vector4>();
    readonly List<int> _tri = new List<int>();

    bool _hasUv0, _hasUv1, _hasCol, _hasNrm, _hasTan;

    // ------------------------------------------------------------------ lifecycle

    void OnEnable()
    {
        _tmp = GetComponent<TMP_Text>();
        _isUI = _tmp is TextMeshProUGUI;
        TMPro_EventManager.TEXT_CHANGED_EVENT.Add(OnTextChanged);
        _needsForce = true;
    }

    void OnDisable()
    {
        TMPro_EventManager.TEXT_CHANGED_EVENT.Remove(OnTextChanged);
        Restore();

        foreach (var s in _sources)
        {
            if (s.output == null) continue;
            if (Application.isPlaying) Destroy(s.output);
            else DestroyImmediate(s.output);
            s.output = null;
        }
        _sources.Clear();
        _sourceCount = 0;
    }

    void OnValidate()
    {
        _paramHash = 0;   // 다음 LateUpdate에서 다시 적용
    }

    /// <summary>강제로 다시 적용하고 싶을 때 호출</summary>
    public void Refresh()
    {
        if (_tmp != null) _tmp.ForceMeshUpdate();
    }

    void LateUpdate()
    {
        if (_tmp == null) return;

        if (_needsForce)
        {
            _needsForce = false;
            _tmp.ForceMeshUpdate();   // → OnTextChanged 에서 캡처 + 적용
            return;
        }

        if (_sourceCount > 0 && ParamHash() != _paramHash)
            Apply();
    }

    void OnTextChanged(Object obj)
    {
        if (obj != _tmp || !isActiveAndEnabled) return;
        CaptureSource();
        Apply();
    }

    // ------------------------------------------------------------------ capture

    void CaptureSource()
    {
        TMP_TextInfo ti = _tmp.textInfo;
        if (ti == null || ti.meshInfo == null) { _sourceCount = 0; return; }

        _sourceCount = ti.meshInfo.Length;
        while (_sources.Count < _sourceCount) _sources.Add(new Source());

        for (int i = 0; i < _sourceCount; i++)
        {
            Source s = _sources[i];
            Mesh m = ti.meshInfo[i].mesh;
            s.tmpMesh = m;
            s.pos.Clear(); s.uv0.Clear(); s.uv1.Clear(); s.col.Clear(); s.nrm.Clear(); s.tan.Clear();
            if (m == null) continue;

            m.GetVertices(s.pos);
            m.GetUVs(0, s.uv0);
            m.GetUVs(1, s.uv1);
            m.GetColors(s.col);
            m.GetNormals(s.nrm);
            m.GetTangents(s.tan);
        }

        _lineCount = Mathf.Max(0, ti.lineCount);
        if (_lineMin.Length < _lineCount)
        {
            _lineMin = new float[_lineCount * 2];
            _lineMax = new float[_lineCount * 2];
        }
        for (int l = 0; l < _lineCount; l++)
        {
            _lineMin[l] = ti.lineInfo[l].descender;
            _lineMax[l] = ti.lineInfo[l].ascender;
        }
    }

    // ------------------------------------------------------------------ build

    void Apply()
    {
        _paramHash = ParamHash();

        for (int i = 0; i < _sourceCount; i++)
        {
            Source s = _sources[i];
            if (s.tmpMesh == null) continue;

            int vc = s.pos.Count;
            _hasUv0 = s.uv0.Count == vc;
            _hasUv1 = s.uv1.Count == vc;
            _hasCol = s.col.Count == vc;
            _hasNrm = s.nrm.Count == vc;
            _hasTan = s.tan.Count == vc;

            _p.Clear(); _u0.Clear(); _u1.Clear(); _c.Clear(); _n.Clear(); _t.Clear(); _tri.Clear();

            int quadCount = vc / 4;
            for (int q = 0; q < quadCount; q++)
            {
                int b = q * 4;
                // TMP 정점 순서: 0 = BL, 1 = TL, 2 = TR, 3 = BR
                if ((s.pos[b + 2] - s.pos[b]).sqrMagnitude < 1e-12f) continue;   // 빈 쿼드 (숨겨진 글자 등)
                SliceQuad(s, b);
            }

            if (s.output == null)
            {
                s.output = new Mesh { name = "TMPBandShift", hideFlags = HideFlags.HideAndDontSave };
                s.output.MarkDynamic();
            }

            Mesh o = s.output;
            o.Clear();
            o.indexFormat = _p.Count > 65000 ? IndexFormat.UInt32 : IndexFormat.UInt16;
            o.SetVertices(_p);
            if (_hasUv0) o.SetUVs(0, _u0);
            if (_hasUv1) o.SetUVs(1, _u1);
            if (_hasCol) o.SetColors(_c);
            if (_hasNrm) o.SetNormals(_n);
            if (_hasTan) o.SetTangents(_t);
            o.SetTriangles(_tri, 0, false);
            o.RecalculateBounds();

            AssignMesh(i, s, o);
        }
    }

    void SliceQuad(Source s, int b)
    {
        float yB = s.pos[b].y;       // BL
        float yT = s.pos[b + 1].y;   // TL
        float dy = yT - yB;

        GetBandFrame((yB + yT) * 0.5f, out float origin, out float bandH, out float unitH, out int line);

        if (dy <= 1e-6f || bandH <= 1e-6f)
        {
            int kk = bandH > 1e-6f ? Mathf.FloorToInt((yB - origin) / bandH) : 0;
            EmitStrip(s, b, 0f, 1f, kk, line, origin, bandH, unitH);
            return;
        }

        int kStart = Mathf.FloorToInt((yB - origin) / bandH);
        int kEnd = Mathf.FloorToInt((yT - origin) / bandH);
        float ya = yB;

        for (int k = kStart; k <= kEnd; k++)
        {
            float yb = Mathf.Min(yT, origin + (k + 1) * bandH);
            if (yb - ya > 1e-6f)
                EmitStrip(s, b, (ya - yB) / dy, (yb - yB) / dy, k, line, origin, bandH, unitH);
            ya = yb;
        }
    }

    void EmitStrip(Source s, int b, float ta, float tb, int k, int line, float origin, float bandH, float unitH)
    {
        float shift = offset * maxShift * unitH * Pattern(k, line);
        float yc = origin + (k + 0.5f) * bandH;
        int baseIndex = _p.Count;

        AddVert(s, b,     b + 1, ta, shift, yc);   // BL
        AddVert(s, b,     b + 1, tb, shift, yc);   // TL
        AddVert(s, b + 3, b + 2, tb, shift, yc);   // TR
        AddVert(s, b + 3, b + 2, ta, shift, yc);   // BR

        _tri.Add(baseIndex);     _tri.Add(baseIndex + 1); _tri.Add(baseIndex + 2);
        _tri.Add(baseIndex + 2); _tri.Add(baseIndex + 3); _tri.Add(baseIndex);
    }

    void AddVert(Source s, int ia, int ib, float t, float shift, float yc)
    {
        Vector3 p = Vector3.LerpUnclamped(s.pos[ia], s.pos[ib], t);
        p.x += shift + offset * bandSkew * (p.y - yc);
        _p.Add(p);

        if (_hasUv0) _u0.Add(Vector4.LerpUnclamped(s.uv0[ia], s.uv0[ib], t));
        if (_hasUv1) _u1.Add(Vector4.LerpUnclamped(s.uv1[ia], s.uv1[ib], t));
        if (_hasCol) _c.Add(Color32.LerpUnclamped(s.col[ia], s.col[ib], t));
        if (_hasNrm) _n.Add(s.nrm[ia]);
        if (_hasTan) _t.Add(s.tan[ia]);
    }

    float Pattern(int k, int line)
    {
        float alt = (k & 1) == 0 ? -0.5f : 0.5f;
        float stair = (k + 0.5f) / bandCount - 0.5f;
        float rnd = Hash01(k, line, seed) - 0.5f;
        return alternate * alt + staircase * stair + random * rnd;
    }

    void GetBandFrame(float y, out float origin, out float bandH, out float unitH, out int line)
    {
        float y0, y1;
        line = 0;

        if (_lineCount == 0)
        {
            y0 = y - 0.5f; y1 = y + 0.5f;
            unitH = 1f;
        }
        else if (bandSpace == BandSpace.WholeText)
        {
            y0 = float.MaxValue; y1 = float.MinValue;
            for (int l = 0; l < _lineCount; l++)
            {
                y0 = Mathf.Min(y0, _lineMin[l]);
                y1 = Mathf.Max(y1, _lineMax[l]);
            }
            unitH = _lineMax[0] - _lineMin[0];
        }
        else
        {
            // 쿼드 중심이 속한 줄 (없으면 가장 가까운 줄)
            float best = float.MaxValue;
            for (int l = 0; l < _lineCount; l++)
            {
                float d = y < _lineMin[l] ? _lineMin[l] - y : (y > _lineMax[l] ? y - _lineMax[l] : 0f);
                if (d < best) { best = d; line = l; }
            }
            y0 = _lineMin[line];
            y1 = _lineMax[line];
            unitH = y1 - y0;
        }

        bandH = (y1 - y0) / Mathf.Max(1, bandCount);
        origin = y0 + bandPhase * bandH;
    }

    // ------------------------------------------------------------------ mesh assign / restore

    void AssignMesh(int index, Source s, Mesh m)
    {
        if (_isUI)
        {
            if (index == 0) { _tmp.canvasRenderer.SetMesh(m); return; }
            foreach (var sm in GetComponentsInChildren<TMP_SubMeshUI>(true))
                if (sm.mesh == s.tmpMesh) { sm.canvasRenderer.SetMesh(m); return; }
        }
        else
        {
            MeshFilter f = FindFilter(index, s.tmpMesh);
            if (f != null && f.sharedMesh != m) f.sharedMesh = m;
        }
    }

    MeshFilter FindFilter(int index, Mesh tmpMesh)
    {
        if (index == 0) return GetComponent<MeshFilter>();
        foreach (var sm in GetComponentsInChildren<TMP_SubMesh>(true))
            if (sm.mesh == tmpMesh) return sm.GetComponent<MeshFilter>();
        return null;
    }

    void Restore()
    {
        if (_tmp == null) return;

        if (!_isUI)
        {
            for (int i = 0; i < _sourceCount && i < _sources.Count; i++)
            {
                Source s = _sources[i];
                if (s.tmpMesh == null) continue;
                MeshFilter f = FindFilter(i, s.tmpMesh);
                if (f != null) f.sharedMesh = s.tmpMesh;
            }
        }

        if (_tmp.isActiveAndEnabled) _tmp.ForceMeshUpdate(true);
    }

    // ------------------------------------------------------------------ utils

    int ParamHash()
    {
        unchecked
        {
            int h = 17;
            h = h * 31 + offset.GetHashCode();
            h = h * 31 + maxShift.GetHashCode();
            h = h * 31 + (int)bandSpace;
            h = h * 31 + bandCount;
            h = h * 31 + bandPhase.GetHashCode();
            h = h * 31 + alternate.GetHashCode();
            h = h * 31 + staircase.GetHashCode();
            h = h * 31 + random.GetHashCode();
            h = h * 31 + seed;
            h = h * 31 + bandSkew.GetHashCode();
            return h == 0 ? 1 : h;
        }
    }

    static float Hash01(int a, int b, int c)
    {
        unchecked
        {
            uint h = (uint)a * 73856093u ^ (uint)b * 19349663u ^ (uint)c * 83492791u;
            h ^= h >> 13;
            h *= 0x5bd1e995u;
            h ^= h >> 15;
            return (h & 0xFFFFFF) / 16777216f;
        }
    }
}
