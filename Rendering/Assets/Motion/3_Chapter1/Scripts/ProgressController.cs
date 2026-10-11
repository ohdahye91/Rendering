using System.Collections;
using UnityEngine;
using UnityEngine.UI;
using TMPro;
using System;

public class ProgressController : MonoBehaviour
{
    [SerializeField] private float startValue = 0f;
    [SerializeField] private float targetValue = 1f;
    [SerializeField] private float duration = 2f;
    
    [SerializeField] private Button button;
    [SerializeField] private Animator animator;
    [SerializeField] private TextMeshProUGUI startPercent;
    [SerializeField] private TextMeshProUGUI targetPercent;

    [SerializeField] private string floatParameterName = "";
    
    private Coroutine interpolationCoroutine;
    private float currentValue;

    private float initialStartValue;
    private float initialTargetValue;
    
    void Start()
    {
        initialStartValue = startValue;
        initialTargetValue = targetValue;

        if (button != null)
        {
            button.onClick.AddListener(StartInterpolation);
        }
        
        currentValue = startValue;
        UpdateAnimatorParameter();
    }

    public void ResetToInitialState()
    {
        StopInterpolation(); 

        startValue = initialStartValue;
        targetValue = initialTargetValue;
        currentValue = startValue;

        UpdateAnimatorParameter();
    }

    public void SetMinMax(float min, float max)
    {
        startValue = min;
        targetValue = max;
    }
    
    public void StartInterpolation()
    {
        if (interpolationCoroutine != null)
        {
            StopCoroutine(interpolationCoroutine);
        }
        
        interpolationCoroutine = StartCoroutine(InterpolateFloat());
    }
    

    private IEnumerator InterpolateFloat()
    {
        float elapsedTime = 0f;

        float distance = Mathf.Abs(targetValue - startValue);
        
        float actualDuration = distance * duration;

        if (actualDuration < 0.01f)
        {
            currentValue = targetValue;
        }
        else
        {
            while (elapsedTime < actualDuration)
            {
                elapsedTime += Time.deltaTime;
                
                float progress = elapsedTime / actualDuration;
                
                float exponentialProgress = ApplyExponentialCurve(progress, 1.5f);

                currentValue = Mathf.Lerp(startValue, targetValue, exponentialProgress);
                
                if (animator != null) animator.SetFloat(floatParameterName, currentValue);

                yield return null;
            }
        }

        currentValue = targetValue;
        
        UpdateAnimatorParameter();

        interpolationCoroutine = null;
    }
    

    private float ApplyExponentialCurve(float t, float strength)
    {
        bool isIncreasing = targetValue > startValue;
        if (isIncreasing) return Mathf.Pow(t, 1f / strength);
        else return 1f - Mathf.Pow(1f - t, 1f / strength);
    }

    
    private void UpdateAnimatorParameter()
    {
        if (animator != null) animator.SetFloat(floatParameterName, currentValue);
    }

    public void StopInterpolation()
    {
        if (interpolationCoroutine != null)
        {
            StopCoroutine(interpolationCoroutine);
            interpolationCoroutine = null;
        }
    }
    
    public void SetStartValue(float value)
    {
        startValue = Mathf.Clamp01(value);
        if (interpolationCoroutine == null)
        {
            currentValue = startValue;
            //UpdateAnimatorParameter();
        }
    }

    public void SetTargetValue(float value)
    {
        targetValue = Mathf.Clamp01(value);
    }
    
    void OnDestroy()
    {
        if (button != null) button.onClick.RemoveListener(StartInterpolation);
    }
}