// Editor 폴더에 넣어서 사용
// 메뉴: Tools > Glitch > Generate Textures
// Assets/GlitchTextures 에 셰이더용 데이터 텍스처 6장을 생성하고,
// 선택된 머티리얼이 있으면 자동으로 할당한다.
#if UNITY_EDITOR
using System.IO;
using UnityEditor;
using UnityEngine;

public static class GlitchTextureGenerator
{
    const string Folder = "Assets/GlitchTextures";
    const int Seed = 1337;

    [MenuItem("Tools/Glitch/Generate Textures")]
    public static void Generate()
    {
        Directory.CreateDirectory(Folder);
        var rng = new System.Random(Seed);

        string timing   = Save("Glitch_Timing",   MakeTiming(rng));
        string block    = Save("Glitch_BlockNoise", MakeRandomRGBA(64, 64, rng));
        string jitter   = Save("Glitch_Jitter",   MakeJitter(256, 256, rng));
        string split    = Save("Glitch_RGBSplit", MakeSplitDir(32, 32, rng));
        string scanline = Save("Glitch_Scanline", MakeScanline(4, 256));
        string grain    = Save("Glitch_Grain",    MakeRandomRGBA(256, 256, rng));

        AssetDatabase.Refresh();

        Configure(timing,   FilterMode.Bilinear);
        Configure(block,    FilterMode.Point);
        Configure(jitter,   FilterMode.Bilinear);
        Configure(split,    FilterMode.Point);
        Configure(scanline, FilterMode.Bilinear);
        Configure(grain,    FilterMode.Point);

        AssetDatabase.Refresh();

        if (Selection.activeObject is Material mat)
        {
            Assign(mat, "_GlitchTimingTex", timing);
            Assign(mat, "_BlockNoiseTex",   block);
            Assign(mat, "_JitterTex",       jitter);
            Assign(mat, "_RGBSplitTex",     split);
            Assign(mat, "_ScanlineTex",     scanline);
            Assign(mat, "_GrainTex",        grain);
            EditorUtility.SetDirty(mat);
            Debug.Log($"[Glitch] 텍스처 생성 및 '{mat.name}'에 할당 완료");
        }
        else
        {
            Debug.Log($"[Glitch] 텍스처 생성 완료 → {Folder}");
        }
    }

    // R: 평소엔 낮은 값, 간헐적으로 높은 스파이크(= 글리치 발생 구간)
    static Texture2D MakeTiming(System.Random rng)
    {
        const int w = 256;
        var tex = NewTex(w, 1);
        var v = new float[w];

        for (int x = 0; x < w; x++)
            v[x] = (float)rng.NextDouble() * 0.35f;

        int bursts = 9;
        for (int b = 0; b < bursts; b++)
        {
            int start = rng.Next(w);
            int len = rng.Next(2, 8);
            float peak = 0.75f + (float)rng.NextDouble() * 0.25f;
            for (int k = 0; k < len; k++)
            {
                int x = (start + k) % w;
                // 버스트 내부도 들쭉날쭉하게
                v[x] = Mathf.Max(v[x], peak * (0.7f + (float)rng.NextDouble() * 0.3f));
            }
        }

        for (int x = 0; x < w; x++)
            tex.SetPixel(x, 0, new Color(v[x], v[x], v[x], 1));
        tex.Apply();
        return tex;
    }

    // RGBA 전부 독립 랜덤 (블록 노이즈 / 그레인)
    static Texture2D MakeRandomRGBA(int w, int h, System.Random rng)
    {
        var tex = NewTex(w, h);
        for (int y = 0; y < h; y++)
        for (int x = 0; x < w; x++)
        {
            tex.SetPixel(x, y, new Color(
                (float)rng.NextDouble(),
                (float)rng.NextDouble(),
                (float)rng.NextDouble(),
                1f));
        }
        tex.Apply();
        return tex;
    }

    // R: 라인마다 다른 수평 흔들림 (부드러운 노이즈 + 가끔 튀는 값)
    static Texture2D MakeJitter(int w, int h, System.Random rng)
    {
        var tex = NewTex(w, h);
        float ox = (float)rng.NextDouble() * 100f;
        float oy = (float)rng.NextDouble() * 100f;

        for (int y = 0; y < h; y++)
        for (int x = 0; x < w; x++)
        {
            float n = Mathf.PerlinNoise(ox + x * 0.08f, oy + y * 0.6f);
            n = Mathf.Lerp(0.5f, n, 0.8f);
            if (rng.NextDouble() < 0.04) n = (float)rng.NextDouble(); // 스파이크
            tex.SetPixel(x, y, new Color(n, n, n, 1));
        }
        tex.Apply();
        return tex;
    }

    // RG: 분리 방향(대부분 수평, 약간의 기울기), B: 강도
    static Texture2D MakeSplitDir(int w, int h, System.Random rng)
    {
        var tex = NewTex(w, h);
        for (int y = 0; y < h; y++)
        for (int x = 0; x < w; x++)
        {
            float sign = rng.NextDouble() < 0.5 ? 1f : -1f;
            float angle = ((float)rng.NextDouble() - 0.5f) * 0.6f; // ±17도 정도
            Vector2 d = new Vector2(Mathf.Cos(angle) * sign, Mathf.Sin(angle));
            tex.SetPixel(x, y, new Color(
                d.x * 0.5f + 0.5f,
                d.y * 0.5f + 0.5f,
                (float)rng.NextDouble(),
                1f));
        }
        tex.Apply();
        return tex;
    }

    // R: 한 주기의 스캔라인 (셰이더에서 _ScanlineCount 만큼 반복)
    // G: 화면을 천천히 지나가는 부드러운 롤 밴드
    static Texture2D MakeScanline(int w, int h)
    {
        var tex = NewTex(w, h);
        for (int y = 0; y < h; y++)
        {
            float v = (y + 0.5f) / h;
            float line = Mathf.Pow(Mathf.Sin(v * Mathf.PI), 0.6f);
            float band = Mathf.Exp(-Mathf.Pow((v - 0.5f) / 0.06f, 2f));
            for (int x = 0; x < w; x++)
                tex.SetPixel(x, y, new Color(line, band, 0, 1));
        }
        tex.Apply();
        return tex;
    }

    static Texture2D NewTex(int w, int h)
    {
        return new Texture2D(w, h, TextureFormat.RGBA32, false, true);
    }

    static string Save(string name, Texture2D tex)
    {
        string path = $"{Folder}/{name}.png";
        File.WriteAllBytes(path, tex.EncodeToPNG());
        Object.DestroyImmediate(tex);
        return path;
    }

    // 데이터 텍스처이므로 sRGB 끄고, 압축/밉맵 없이 Repeat
    static void Configure(string path, FilterMode filter)
    {
        var importer = AssetImporter.GetAtPath(path) as TextureImporter;
        if (importer == null) return;

        importer.textureType = TextureImporterType.Default;
        importer.sRGBTexture = false;
        importer.mipmapEnabled = false;
        importer.wrapMode = TextureWrapMode.Repeat;
        importer.filterMode = filter;
        importer.npotScale = TextureImporterNPOTScale.None;
        importer.textureCompression = TextureImporterCompression.Uncompressed;
        importer.alphaSource = TextureImporterAlphaSource.None;
        importer.SaveAndReimport();
    }

    static void Assign(Material mat, string prop, string path)
    {
        if (!mat.HasProperty(prop)) return;
        mat.SetTexture(prop, AssetDatabase.LoadAssetAtPath<Texture2D>(path));
    }
}
#endif
