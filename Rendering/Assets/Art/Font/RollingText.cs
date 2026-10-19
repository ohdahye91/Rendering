using System.Collections;
using TMPro;
using UnityEngine;
using UnityEngine.UI;

/// <summary>
/// TMP 숫자 롤링 효과 (예: 10:00 -> 10:01 에서 바뀌는 글자만 아래로 빠지고 위에서 새 글자가 내려옴)
///
/// 구조:
///   RollingText (RectTransform + RectMask2D + 이 스크립트)  ← 높이 = 한 줄 높이 (넘치는 부분이 잘림)
///     └ Label (TextMeshProUGUI)                              ← 부모를 꽉 채우도록 Stretch
///
/// 실행 시 Label 을 복제해서 "들어오는 글자"용 텍스트를 자동 생성합니다.
/// </summary>
[RequireComponent(typeof(RectMask2D))]
public class RollingText : MonoBehaviour
{
    public enum Direction { Down, Up }

    [SerializeField] TMP_Text label;

    [Header("Animation")]
    [SerializeField] float duration = 0.35f;
    [SerializeField] Direction direction = Direction.Down;
    [SerializeField] AnimationCurve ease = AnimationCurve.EaseInOut(0f, 0f, 1f, 1f);
    [Tooltip("바뀌는 글자가 여러 개일 때 오른쪽 글자부터 순서대로 시작하는 간격(초). 0이면 동시에.")]
    [SerializeField] float staggerPerChar = 0.04f;
    [SerializeField] bool useUnscaledTime = false;

    [Header("Layout")]
    [Tooltip("글자 고정폭(em). 숫자 폭이 달라 글자 위치가 흔들리는 걸 막습니다. 0이면 사용 안 함.")]
    [SerializeField] float monoSpace = 0.6f;
    [Tooltip("켜면 숫자에만 고정폭 적용 (한글/영문 글자는 원래 폭 유지)")]
    [SerializeField] bool monoDigitsOnly = true;

    TMP_Text incoming;
    RectTransform rectTransform;
    Coroutine routine;
    string currentValue = "";
    string targetValue = "";

    public string Value => targetValue;

    /// <summary>글자 하나가 굴러가는 시간(초). 코드에서 바꿀 수 있게 공개.</summary>
    public float Duration
    {
        get => duration;
        set => duration = Mathf.Max(0f, value);
    }

    void Awake()
    {
        rectTransform = (RectTransform)transform;
        if (label == null) label = GetComponentInChildren<TMP_Text>();

        label.richText = true;
        currentValue = targetValue = label.text;

        incoming = Instantiate(label, label.transform.parent);
        incoming.name = label.name + "_Incoming";
        incoming.transform.SetSiblingIndex(label.transform.GetSiblingIndex() + 1);
        incoming.gameObject.SetActive(false);

        label.SetText(Wrap(currentValue));
    }

    void OnDisable()
    {
        // 비활성화되면 애니메이션 중이던 값으로 바로 확정
        if (routine != null)
        {
            routine = null;
            Finish();
        }
    }

    /// <summary>값 설정. 바뀐 글자만 롤링됩니다.</summary>
    public void SetValue(string value, bool animate = true)
    {
        if (value == null) value = "";

        // 진행 중이면 즉시 끝내고 새 값으로
        if (routine != null)
        {
            StopCoroutine(routine);
            routine = null;
            Finish();
        }

        if (value == currentValue) return;

        targetValue = value;

        if (!animate || !isActiveAndEnabled || duration <= 0f)
        {
            Finish();
            return;
        }

        routine = StartCoroutine(Roll(currentValue, value));
    }

    string Wrap(string v)
    {
        if (monoSpace <= 0f) return v;
        if (!monoDigitsOnly) return $"<mspace={monoSpace}em>{v}";

        var sb = new System.Text.StringBuilder(v.Length * 4);
        string open = $"<mspace={monoSpace}em>";
        foreach (char c in v)
        {
            if (char.IsDigit(c)) sb.Append(open).Append(c).Append("</mspace>");
            else sb.Append(c);
        }
        return sb.ToString();
    }

    void Finish()
    {
        currentValue = targetValue;
        label.SetText(Wrap(currentValue));
        label.ForceMeshUpdate();
        incoming.gameObject.SetActive(false);
    }

    IEnumerator Roll(string from, string to)
    {
        incoming.gameObject.SetActive(true);

        label.SetText(Wrap(from));
        incoming.SetText(Wrap(to));
        label.ForceMeshUpdate();
        incoming.ForceMeshUpdate();

        TMP_TextInfo oldInfo = label.textInfo;
        TMP_TextInfo newInfo = incoming.textInfo;
        int oldCount = oldInfo.characterCount;
        int newCount = newInfo.characterCount;

        // 오른쪽 끝 기준으로 글자 비교 (9:59 -> 10:00 처럼 길이가 바뀌어도 대응)
        float[] oldStart = new float[oldCount];
        float[] newStart = new float[newCount];
        for (int i = 0; i < oldCount; i++) oldStart[i] = -1f;
        for (int i = 0; i < newCount; i++) newStart[i] = -1f;

        int maxCount = Mathf.Max(oldCount, newCount);
        int order = 0;
        for (int k = 0; k < maxCount; k++) // k = 오른쪽에서 몇 번째
        {
            int oi = oldCount - 1 - k;
            int ni = newCount - 1 - k;
            char oc = oi >= 0 ? oldInfo.characterInfo[oi].character : '\0';
            char nc = ni >= 0 ? newInfo.characterInfo[ni].character : '\0';
            if (oc == nc) continue;

            float start = order * staggerPerChar;
            if (oi >= 0) oldStart[oi] = start;
            if (ni >= 0) newStart[ni] = start;
            order++;
        }

        TMP_MeshInfo[] oldCache = oldInfo.CopyMeshInfoVertexData();
        TMP_MeshInfo[] newCache = newInfo.CopyMeshInfoVertexData();

        float total = duration + Mathf.Max(0, order - 1) * staggerPerChar;
        float elapsed = 0f;

        while (true)
        {
            float h = rectTransform.rect.height;
            float dir = direction == Direction.Down ? -1f : 1f;

            Apply(label, oldCache, oldStart, elapsed, h, dir, false);
            Apply(incoming, newCache, newStart, elapsed, h, dir, true);

            if (elapsed >= total) break;
            yield return null;
            elapsed += useUnscaledTime ? Time.unscaledDeltaTime : Time.deltaTime;
        }

        routine = null;
        Finish();
    }

    void Apply(TMP_Text txt, TMP_MeshInfo[] cache, float[] starts, float elapsed, float h, float dir, bool isIncoming)
    {
        TMP_TextInfo info = txt.textInfo;

        for (int i = 0; i < info.characterCount && i < starts.Length; i++)
        {
            TMP_CharacterInfo ci = info.characterInfo[i];
            if (!ci.isVisible) continue;

            int m = ci.materialReferenceIndex;
            int vi = ci.vertexIndex;
            Vector3[] src = cache[m].vertices;
            Color32[] srcCol = cache[m].colors32;
            Vector3[] dst = info.meshInfo[m].vertices;
            Color32[] dstCol = info.meshInfo[m].colors32;

            float offset = 0f;
            bool hide = false;

            if (starts[i] < 0f)
            {
                // 안 바뀐 글자: 기존 텍스트에서만 보이게
                hide = isIncoming;
            }
            else
            {
                float p = ease.Evaluate(Mathf.Clamp01((elapsed - starts[i]) / duration));
                offset = isIncoming
                    ? -dir * h * (1f - p)   // 위에서 내려와 제자리로
                    : dir * h * p;          // 제자리에서 아래로 빠짐
            }

            Vector3 delta = new Vector3(0f, offset, 0f);
            for (int j = 0; j < 4; j++)
            {
                dst[vi + j] = src[vi + j] + delta;
                Color32 c = srcCol[vi + j];
                if (hide) c.a = 0;
                dstCol[vi + j] = c;
            }
        }

        txt.UpdateVertexData(TMP_VertexDataUpdateFlags.Vertices | TMP_VertexDataUpdateFlags.Colors32);
    }
}