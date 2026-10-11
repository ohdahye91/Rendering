using UnityEngine;
using UnityEngine.UI;
using UnityEngine.EventSystems;
using UnityEngine.Events;
using TMPro;

[RequireComponent(typeof(RectTransform))]
public class MinMaxSlider : MonoBehaviour, IPointerDownHandler, IDragHandler
{
    [Header("Slider Limits")]
    public float minLimit = 0f;
    public float maxLimit = 1f;

    [Header("Current Values")]
    public float minValue = 0f;
    public float maxValue = 0f;

    [Header("UI References")]
    [Tooltip("슬라이더의 전체 클릭 영역이자 바탕이 되는 RectTransform")]
    public RectTransform sliderBounds;
    public RectTransform minHandle;
    public RectTransform maxHandle;
    public RectTransform fillArea;

    // 인스펙터에 노출하기 위한 커스텀 이벤트 클래스
    [System.Serializable]
    public class MinMaxSliderEvent : UnityEvent<float, float> { }
    [System.Serializable]
    public class SliderEvent : UnityEvent<float> { }

    [Header("Events")]
    [Tooltip("Min과 Max 중 하나라도 변경되면 두 값을 동시에 보냅니다.")]
    public MinMaxSliderEvent onValueChanged;
    
    [Tooltip("Min(Start) 값이 변경될 때만 해당 값을 보냅니다.")]
    public SliderEvent onMinValueChanged;
    
    [Tooltip("Max(Target) 값이 변경될 때만 해당 값을 보냅니다.")]
    public SliderEvent onMaxValueChanged;

    public TextMeshProUGUI startPercent;
    public TextMeshProUGUI targetPercent;

    private bool _isDraggingMin = false;

    private void Start()
    {
        UpdateUI();
    }

    public void OnPointerDown(PointerEventData eventData)
    {
        if (sliderBounds == null) return;

        Vector2 localPoint;
        if (RectTransformUtility.ScreenPointToLocalPointInRectangle(sliderBounds, eventData.position, eventData.pressEventCamera, out localPoint))
        {
            float percentage = Mathf.InverseLerp(sliderBounds.rect.xMin, sliderBounds.rect.xMax, localPoint.x);
            float clickedValue = Mathf.Lerp(minLimit, maxLimit, percentage);

            float diffMin = Mathf.Abs(minValue - clickedValue);
            float diffMax = Mathf.Abs(maxValue - clickedValue);

            if (diffMin < diffMax)
            {
                _isDraggingMin = true;
                minHandle.SetAsLastSibling(); // 핸들을 시각적으로 맨 위로
            }
            else
            {
                _isDraggingMin = false;
                maxHandle.SetAsLastSibling();
            }

            CalculateAndSetValues(localPoint);
        }
    }

    public void OnDrag(PointerEventData eventData)
    {
        if (sliderBounds == null) return;

        Vector2 localPoint;
        if (RectTransformUtility.ScreenPointToLocalPointInRectangle(sliderBounds, eventData.position, eventData.pressEventCamera, out localPoint))
        {
            CalculateAndSetValues(localPoint);
        }
    }

    private void CalculateAndSetValues(Vector2 localPoint)
    {
        float percentage = Mathf.InverseLerp(sliderBounds.rect.xMin, sliderBounds.rect.xMax, localPoint.x);
        float value = Mathf.Lerp(minLimit, maxLimit, percentage);

        bool isChanged = false;

        if (_isDraggingMin)
        {
            float newMin = Mathf.Clamp(value, minLimit, maxValue);
            // 값이 실제로 변했을 때만 이벤트 발생 (최적화)
            if (!Mathf.Approximately(minValue, newMin))
            {
                minValue = newMin;
                onMinValueChanged?.Invoke(minValue); // StartValue 연결용
                isChanged = true;
            }
        }
        else
        {
            float newMax = Mathf.Clamp(value, minValue, maxLimit);
            if (!Mathf.Approximately(maxValue, newMax))
            {
                maxValue = newMax;
                onMaxValueChanged?.Invoke(maxValue); // TargetValue 연결용
                isChanged = true;
            }
        }

        if (isChanged)
        {
            UpdateUI();
            onValueChanged?.Invoke(minValue, maxValue); // 기존의 통합 이벤트
        }

            startPercent.text = $"{minValue * 100f:F1}%";
            targetPercent.text = $"{maxValue * 100f:F1}%";
    }

    public void UpdateUI()
    {
        if (sliderBounds == null || minHandle == null || maxHandle == null || fillArea == null) return;

        float minPercent = Mathf.InverseLerp(minLimit, maxLimit, minValue);
        float maxPercent = Mathf.InverseLerp(minLimit, maxLimit, maxValue);

        minHandle.anchorMin = new Vector2(minPercent, 0.5f);
        minHandle.anchorMax = new Vector2(minPercent, 0.5f);
        minHandle.anchoredPosition = Vector2.zero;

        maxHandle.anchorMin = new Vector2(maxPercent, 0.5f);
        maxHandle.anchorMax = new Vector2(maxPercent, 0.5f);
        maxHandle.anchoredPosition = Vector2.zero;

        fillArea.anchorMin = new Vector2(minPercent, 0f);
        fillArea.anchorMax = new Vector2(maxPercent, 1f);
        fillArea.offsetMin = Vector2.zero;
        fillArea.offsetMax = Vector2.zero;
    }
    
    public void SetValues(float newMin, float newMax)
    {
        bool changed = false;
        
        newMin = Mathf.Clamp(newMin, minLimit, maxLimit);
        newMax = Mathf.Clamp(newMax, minLimit, maxLimit);

        if (!Mathf.Approximately(minValue, newMin))
        {
            minValue = newMin;
            onMinValueChanged?.Invoke(minValue);
            changed = true;
        }

        if (!Mathf.Approximately(maxValue, newMax))
        {
            maxValue = newMax;
            onMaxValueChanged?.Invoke(maxValue);
            changed = true;
        }

        if (changed)
        {
            UpdateUI();
            onValueChanged?.Invoke(minValue, maxValue);
        }
    }
}