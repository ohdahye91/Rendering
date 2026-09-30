using UnityEngine;
using UnityEngine.UI;

// RawImage 대신 쓰는 구김용 UI 그래픽.
// 촘촘한 그리드 메시를 만들고, 크기/구김값/시드를 버텍스 채널로 셰이더에 넘김
// (Mask/RectMask2D와 함께 써도 애니메이션이 정상 동작하도록 머티리얼 대신 버텍스 사용)
[RequireComponent(typeof(CanvasRenderer))]
[ExecuteAlways]
public class CrumpleImage : MaskableGraphic
{
    [SerializeField] Texture m_Texture;
    [SerializeField] Rect m_UVRect = new Rect(0, 0, 1, 1);
    [SerializeField, Range(8, 128)] int m_Resolution = 64;   // 긴 변 기준 분할 수
    [SerializeField, Range(0, 1)] float m_Crumple = 0f;
    [SerializeField] float m_Seed = 0f;

    public Texture texture
    {
        get => m_Texture;
        set { if (m_Texture == value) return; m_Texture = value; SetMaterialDirty(); }
    }

    public Rect uvRect
    {
        get => m_UVRect;
        set { if (m_UVRect == value) return; m_UVRect = value; SetVerticesDirty(); }
    }

    public float crumple
    {
        get => m_Crumple;
        set { value = Mathf.Clamp01(value); if (Mathf.Approximately(m_Crumple, value)) return; m_Crumple = value; SetVerticesDirty(); }
    }

    public float seed
    {
        get => m_Seed;
        set { if (Mathf.Approximately(m_Seed, value)) return; m_Seed = value; SetVerticesDirty(); }
    }

    public override Texture mainTexture
    {
        get
        {
            if (m_Texture != null) return m_Texture;
            if (material != null && material.mainTexture != null) return material.mainTexture;
            return s_WhiteTexture;
        }
    }

    protected override void OnEnable()
    {
        base.OnEnable();
        EnableChannels();
    }

    protected override void OnCanvasHierarchyChanged()
    {
        base.OnCanvasHierarchyChanged();
        EnableChannels();
    }

    void EnableChannels()
    {
        if (canvas == null) return;
        canvas.additionalShaderChannels |= AdditionalCanvasShaderChannels.TexCoord1
                                         | AdditionalCanvasShaderChannels.TexCoord2;
    }

    protected override void OnPopulateMesh(VertexHelper vh)
    {
        vh.Clear();
        Rect r = GetPixelAdjustedRect();
        if (r.width <= 0 || r.height <= 0) return;

        float aspect = r.width / r.height;
        int nx = Mathf.Max(2, Mathf.RoundToInt(m_Resolution * Mathf.Min(1f, aspect)));
        int ny = Mathf.Max(2, Mathf.RoundToInt(m_Resolution * Mathf.Min(1f, 1f / aspect)));

        var data = new Vector4(r.width, r.height, m_Crumple, m_Seed);
        Color32 c = color;
        UIVertex vert = UIVertex.simpleVert;

        for (int y = 0; y <= ny; y++)
        for (int x = 0; x <= nx; x++)
        {
            float u = (float)x / nx, v = (float)y / ny;
            vert.position = new Vector3(r.xMin + u * r.width, r.yMin + v * r.height, 0);
            vert.color = c;
            vert.uv0 = new Vector4(m_UVRect.xMin + u * m_UVRect.width, m_UVRect.yMin + v * m_UVRect.height, 0, 0);
            vert.uv1 = data;
            vert.uv2 = new Vector4(u, v, 0, 0);
            vh.AddVert(vert);
        }

        for (int y = 0; y < ny; y++)
        for (int x = 0; x < nx; x++)
        {
            int i = y * (nx + 1) + x;
            vh.AddTriangle(i, i + nx + 1, i + 1);
            vh.AddTriangle(i + 1, i + nx + 1, i + nx + 2);
        }
    }

#if UNITY_EDITOR
    protected override void OnValidate()
    {
        base.OnValidate();
        SetVerticesDirty();
    }
#endif
}
