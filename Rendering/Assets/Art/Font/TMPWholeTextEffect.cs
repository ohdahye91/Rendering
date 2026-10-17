using TMPro;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.UI;

/// <summary>
/// TMP 텍스트 전체를 RenderTexture 한 장으로 캡처한 뒤
/// 'UI/TMP Whole Text Glitch' 쉐이더로 다시 그려서, 글자 단위가 아니라 텍스트 전체에 효과를 적용한다.
/// - TextMeshProUGUI(UI) / TextMeshPro(3D) 모두 지원
/// - 폴백 폰트(서브메시, 한글 폴백 등)도 함께 캡처
/// - maxVisibleCharacters 를 이용한 타이핑 연출과 호환
/// - Control Offset 을 켜면 텍스트마다 개별 Offset 값으로 왜곡 위치를 제어 (Animator로 애니메이션 가능)
/// </summary>
[ExecuteAlways]
[DisallowMultipleComponent]
[RequireComponent(typeof(TMP_Text))]
public class TMPWholeTextEffect : MonoBehaviour
{
    [Tooltip("'UI/TMP Whole Text Glitch' 쉐이더를 사용하는 머티리얼")]
    public Material effectMaterial;

    [Header("Distortion Offset")]
    [Tooltip("켜면 이 텍스트 전용 머티리얼 복사본을 만들어 아래 Offset 값을 적용 (텍스트마다 따로 애니메이션 가능)")]
    public bool controlOffset = true;

    [Tooltip("왜곡 구간의 가로 위치 (0 = 왼쪽 끝, 1 = 오른쪽 끝, 범위 밖으로 보내면 효과 사라짐)")]
    public float offset = 0.5f;

    [Header("Capture")]
    [Tooltip("캡처 해상도 배율 (UI는 캔버스 픽셀 기준)")]
    [Range(0.25f, 10f)] public float resolutionScale = 1f;

    [Tooltip("3D TextMeshPro 전용: 1유닛당 픽셀 수")]
    public float worldPixelsPerUnit = 100f;

    [Tooltip("왜곡으로 밀려나갈 공간 확보용 좌우 여백 (텍스트 폭 대비 비율)")]
    [Range(0f, 0.5f)] public float horizontalPadding = 0.15f;

    [Tooltip("위아래 여백 (텍스트 높이 대비 비율)")]
    [Range(0f, 0.5f)] public float verticalPadding = 0.05f;

    [Tooltip("타이핑 중 아직 안 보이는 글자까지 영역에 포함 → 타이핑 도중 그라데이션/왜곡 영역이 흔들리지 않음")]
    public bool includeHiddenCharacters = true;

    [Tooltip("매 프레임 다시 캡처 (폰트 머티리얼 자체를 애니메이션할 때만 켜기)")]
    public bool captureEveryFrame = false;

    TMP_Text _tmp;
    bool _isUI;
    RenderTexture _rt;
    CommandBuffer _cmd;

    GameObject _display;
    RawImage _rawImage;
    MeshRenderer _meshRenderer;
    Mesh _quad;
    MaterialPropertyBlock _mpb;
    Material _instanceMat;
    float _lastOffset = float.NaN;

    Vector2 _min, _max;
    float _ppu = -1f;
    bool _dirty = true;

    static readonly int MainTexId = Shader.PropertyToID("_MainTex");
    static readonly int OffsetId = Shader.PropertyToID("_Offset");
    static readonly int ScreenParamsId = Shader.PropertyToID("_ScreenParams");

    // ------------------------------------------------------------------ lifecycle

    void OnEnable()
    {
        _tmp = GetComponent<TMP_Text>();
        _isUI = _tmp is TextMeshProUGUI;
        TMPro_EventManager.TEXT_CHANGED_EVENT.Add(OnTextChanged);
        _dirty = true;
    }

    void OnDisable()
    {
        TMPro_EventManager.TEXT_CHANGED_EVENT.Remove(OnTextChanged);
        SetOriginalVisible(true);

        SafeDestroy(_display);
        _display = null; _rawImage = null; _meshRenderer = null;
        SafeDestroy(_quad); _quad = null;
        SafeDestroy(_instanceMat); _instanceMat = null;
        _lastOffset = float.NaN;

        if (_rt != null) { _rt.Release(); SafeDestroy(_rt); _rt = null; }
        if (_cmd != null) { _cmd.Release(); _cmd = null; }
        _ppu = -1f;
    }

    void OnValidate() => _dirty = true;

    /// <summary>외부에서 강제로 다시 캡처하고 싶을 때 호출</summary>
    public void SetDirty() => _dirty = true;

    void OnTextChanged(Object obj)
    {
        if (obj != _tmp) return;
        // UGUI 리빌드 루프 안이므로 Graphic/RectTransform은 건드리지 않는다.
        // 영역이 그대로면 RT만 즉시 다시 그리고, 영역이 바뀌었으면 LateUpdate로 미룬다.
        if (!Capture(false)) _dirty = true;
    }

    void LateUpdate()
    {
        if (_tmp == null) return;

        if (effectMaterial == null)
        {
            SetOriginalVisible(true);
            if (_display != null && _display.activeSelf) _display.SetActive(false);
            return;
        }

        SyncMaterial();

        if (_dirty || captureEveryFrame || !Mathf.Approximately(CurrentPPU(), _ppu))
        {
            if (_tmp.havePropertiesChanged) _tmp.ForceMeshUpdate();
            _dirty = !Capture(true);
        }
    }

    // ------------------------------------------------------------------ material

    Material DisplayMaterial => controlOffset ? _instanceMat : effectMaterial;

    void SyncMaterial()
    {
        if (controlOffset)
        {
            if (_instanceMat == null || _instanceMat.shader != effectMaterial.shader)
            {
                SafeDestroy(_instanceMat);
                _instanceMat = new Material(effectMaterial)
                {
                    name = effectMaterial.name + " (Instance)",
                    hideFlags = HideFlags.HideAndDontSave
                };
                _lastOffset = float.NaN;
            }

            // 원본 머티리얼 수정사항 반영 + 개별 Offset 적용
            _instanceMat.CopyPropertiesFromMaterial(effectMaterial);
            _instanceMat.SetFloat(OffsetId, offset);
        }
        else if (_instanceMat != null)
        {
            SafeDestroy(_instanceMat);
            _instanceMat = null;
        }

        Material mat = DisplayMaterial;

        if (_rawImage != null)
        {
            if (_rawImage.material != mat) _rawImage.material = mat;
            else if (controlOffset && !Mathf.Approximately(_lastOffset, offset))
                _rawImage.SetMaterialDirty();   // 마스크용 스텐실 머티리얼 복사본까지 갱신
        }

        if (_meshRenderer != null && _meshRenderer.sharedMaterial != mat)
            _meshRenderer.sharedMaterial = mat;

        _lastOffset = offset;
    }

    // ------------------------------------------------------------------ capture

    /// <returns>캡처를 끝냈으면 true, 레이아웃 변경이 필요해서 미뤘으면 false</returns>
    bool Capture(bool allowLayout)
    {
        if (!isActiveAndEnabled || effectMaterial == null || !gameObject.scene.IsValid()) return true;

        if (!TryGetBounds(out Vector2 min, out Vector2 max))
        {
            // 보이는 글자가 없음 (타이핑 시작 전 등)
            if (!allowLayout) return false;
            if (_display != null && _display.activeSelf) _display.SetActive(false);
            return true;
        }

        float ppu = CurrentPPU();
        int pw = Mathf.Clamp(Mathf.CeilToInt((max.x - min.x) * ppu), 4, 4096);
        int ph = Mathf.Clamp(Mathf.CeilToInt((max.y - min.y) * ppu), 4, 4096);

        bool layoutChanged =
            _display == null || !_display.activeSelf ||
            _rt == null || _rt.width != pw || _rt.height != ph ||
            min != _min || max != _max;

        if (layoutChanged)
        {
            if (!allowLayout) return false;
            _min = min; _max = max; _ppu = ppu;
            EnsureRT(pw, ph);
            EnsureDisplay();
            ApplyDisplay();
        }

        Render(pw, ph);
        SetOriginalVisible(false);
        return true;
    }

    bool TryGetBounds(out Vector2 min, out Vector2 max)
    {
        min = new Vector2(float.MaxValue, float.MaxValue);
        max = new Vector2(float.MinValue, float.MinValue);

        TMP_TextInfo ti = _tmp.textInfo;
        if (ti == null || ti.characterInfo == null) return false;

        int count = ti.characterCount;
        int limit = includeHiddenCharacters ? count : Mathf.Min(count, _tmp.maxVisibleCharacters);
        bool found = false;

        for (int i = 0; i < limit; i++)
        {
            TMP_CharacterInfo c = ti.characterInfo[i];
            if (c.character < 32 || char.IsWhiteSpace(c.character)) continue;

            min.x = Mathf.Min(min.x, Mathf.Min(c.bottomLeft.x, c.topLeft.x));
            max.x = Mathf.Max(max.x, Mathf.Max(c.bottomRight.x, c.topRight.x));
            min.y = Mathf.Min(min.y, Mathf.Min(c.descender, c.bottomLeft.y));
            max.y = Mathf.Max(max.y, Mathf.Max(c.ascender, c.topLeft.y));
            found = true;
        }

        if (!found) return false;

        Vector2 size = max - min;
        Vector2 pad = new Vector2(size.x * horizontalPadding, size.y * verticalPadding);
        min -= pad;
        max += pad;
        return true;
    }

    void Render(int pw, int ph)
    {
        if (_cmd == null) _cmd = new CommandBuffer { name = "TMP Whole Text Capture" };

        _cmd.Clear();
        _cmd.SetRenderTarget(_rt);
        _cmd.ClearRenderTarget(false, true, Color.clear);
        _cmd.SetViewProjectionMatrices(Matrix4x4.identity,
            Matrix4x4.Ortho(_min.x, _max.x, _min.y, _max.y, -1000f, 1000f));
        // TMP SDF 쉐이더의 안티앨리어싱 계산이 RT 해상도 기준으로 되도록
        _cmd.SetGlobalVector(ScreenParamsId, new Vector4(pw, ph, 1f + 1f / pw, 1f + 1f / ph));

        DrawMesh(_tmp.mesh, _tmp.fontSharedMaterial);

        if (_isUI)
        {
            foreach (var sm in GetComponentsInChildren<TMP_SubMeshUI>())
                if (sm.isActiveAndEnabled) DrawMesh(sm.mesh, sm.sharedMaterial);
        }
        else
        {
            foreach (var sm in GetComponentsInChildren<TMP_SubMesh>())
                if (sm.isActiveAndEnabled) DrawMesh(sm.mesh, sm.sharedMaterial);
        }

        Graphics.ExecuteCommandBuffer(_cmd);
    }

    void DrawMesh(Mesh mesh, Material mat)
    {
        if (mesh != null && mat != null)
            _cmd.DrawMesh(mesh, Matrix4x4.identity, mat, 0, 0);
    }

    // ------------------------------------------------------------------ display

    void EnsureRT(int w, int h)
    {
        if (_rt != null && _rt.width == w && _rt.height == h) return;
        if (_rt != null) { _rt.Release(); SafeDestroy(_rt); }

        _rt = new RenderTexture(w, h, 0, RenderTextureFormat.ARGB32)
        {
            name = "TMPWholeText_RT",
            hideFlags = HideFlags.HideAndDontSave,
            wrapMode = TextureWrapMode.Clamp,
            filterMode = FilterMode.Bilinear,
            useMipMap = false
        };
        _rt.Create();
    }

    void EnsureDisplay()
    {
        if (_display != null)
        {
            if (!_display.activeSelf) _display.SetActive(true);
            return;
        }

        _display = new GameObject("[TMP Whole Text FX]");
        _display.hideFlags = HideFlags.HideAndDontSave;
        _display.layer = gameObject.layer;

        if (_isUI)
        {
            var rect = _display.AddComponent<RectTransform>();
            rect.SetParent(transform, false);
            _display.AddComponent<LayoutElement>().ignoreLayout = true;
            _rawImage = _display.AddComponent<RawImage>();
            _rawImage.raycastTarget = false;
        }
        else
        {
            _display.transform.SetParent(transform, false);
            _quad = BuildQuad();
            _display.AddComponent<MeshFilter>().sharedMesh = _quad;
            _meshRenderer = _display.AddComponent<MeshRenderer>();
            _meshRenderer.shadowCastingMode = ShadowCastingMode.Off;
            _meshRenderer.receiveShadows = false;

            var src = GetComponent<Renderer>();
            if (src != null)
            {
                _meshRenderer.sortingLayerID = src.sortingLayerID;
                _meshRenderer.sortingOrder = src.sortingOrder;
            }
        }
    }

    void ApplyDisplay()
    {
        Vector2 size = _max - _min;
        Vector2 center = (_min + _max) * 0.5f;

        if (_isUI)
        {
            var rect = (RectTransform)_display.transform;
            rect.anchorMin = rect.anchorMax = rect.pivot = new Vector2(0.5f, 0.5f);
            rect.sizeDelta = size;
            rect.localRotation = Quaternion.identity;
            rect.localScale = Vector3.one;
            rect.localPosition = new Vector3(center.x, center.y, 0f);
            _rawImage.texture = _rt;
        }
        else
        {
            Transform t = _display.transform;
            t.localPosition = new Vector3(center.x, center.y, 0f);
            t.localRotation = Quaternion.identity;
            t.localScale = new Vector3(size.x, size.y, 1f);

            if (_mpb == null) _mpb = new MaterialPropertyBlock();
            _meshRenderer.GetPropertyBlock(_mpb);
            _mpb.SetTexture(MainTexId, _rt);
            _meshRenderer.SetPropertyBlock(_mpb);
        }

        SyncMaterial();
    }

    void SetOriginalVisible(bool visible)
    {
        if (_tmp == null) return;

        if (_isUI)
        {
            float a = visible ? 1f : 0f;
            _tmp.canvasRenderer.SetAlpha(a);
            foreach (var sm in GetComponentsInChildren<TMP_SubMeshUI>(true))
                sm.canvasRenderer.SetAlpha(a);
        }
        else
        {
            var r = GetComponent<Renderer>();
            if (r != null) r.forceRenderingOff = !visible;
            foreach (var sm in GetComponentsInChildren<TMP_SubMesh>(true))
            {
                var sr = sm.GetComponent<Renderer>();
                if (sr != null) sr.forceRenderingOff = !visible;
            }
        }
    }

    // ------------------------------------------------------------------ utils

    float CurrentPPU()
    {
        if (_isUI)
        {
            Canvas canvas = ((Graphic)_tmp).canvas;
            float s = canvas != null ? canvas.scaleFactor : 1f;
            return Mathf.Max(0.01f, s * resolutionScale);
        }
        return Mathf.Max(0.01f, worldPixelsPerUnit * resolutionScale);
    }

    static Mesh BuildQuad()
    {
        var m = new Mesh { name = "TMPWholeText_Quad", hideFlags = HideFlags.HideAndDontSave };
        m.vertices = new[]
        {
            new Vector3(-0.5f, -0.5f, 0f), new Vector3(0.5f, -0.5f, 0f),
            new Vector3(-0.5f,  0.5f, 0f), new Vector3(0.5f,  0.5f, 0f)
        };
        m.uv = new[] { new Vector2(0, 0), new Vector2(1, 0), new Vector2(0, 1), new Vector2(1, 1) };
        m.colors = new[] { Color.white, Color.white, Color.white, Color.white };
        m.triangles = new[] { 0, 2, 1, 2, 3, 1 };
        m.RecalculateBounds();
        return m;
    }

    static void SafeDestroy(Object o)
    {
        if (o == null) return;
        if (Application.isPlaying) Destroy(o);
        else DestroyImmediate(o);
    }
}
