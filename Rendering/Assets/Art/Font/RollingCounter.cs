using System;
using System.Collections;
using System.Globalization;
using UnityEngine;

/// <summary>
/// RollingText 를 이용한 빠른 카운트 연출 (숫자 / 분:초 / 날짜+요일 통합)
///
/// Mode
///   Number : 0 -> 9999 처럼 정수
///   MinSec : 초 단위 값을 mm:ss 로 (600 = 10:00)
///   Date   : 실제 달력 규칙(월말, 윤년)으로 날짜 + 요일
///
/// 사용:
///   counter.Play();                          // 인스펙터 설정대로 실행
///   counter.PlayTo(9999, 2f);                // 값/일수 목표까지 2초 동안
///   counter.Add(1);                          // 한 칸(하루/1초/1)만 넘김
///   counter.RollTo(new DateTime(2026,12,25), 2f);   // Date 모드 전용
/// </summary>
public class RollingCounter : MonoBehaviour
{
    public enum Mode { Number, MinSec, Date }
    public enum DateTarget { ByDays, ToTargetDate }

    [Header("Mode")]
    [SerializeField] Mode mode = Mode.Date;

    [Header("Targets")]
    [SerializeField] RollingText mainText;
    [Tooltip("Date 모드에서만 사용. 비워두면 요일 표시 안 함")]
    [SerializeField] RollingText weekdayText;

    [Header("Number / MinSec")]
    [SerializeField] int from = 0;
    [Tooltip("MinSec 이면 초 단위 (600 = 10:00)")]
    [SerializeField] int to = 600;

    [Header("Date - Format")]
    [Tooltip("C# 날짜 포맷. 예) M월 d일 / MM월 dd일 / yyyy.MM.dd")]
    [SerializeField] string dateFormat = "M월 d일";
    [Tooltip("일요일부터 순서대로 7개")]
    [SerializeField] string[] weekdayNames = { "SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT" };

    [Header("Date - Start")]
    [SerializeField] bool useToday = true;
    [SerializeField] int startYear = 2026;
    [SerializeField] int startMonth = 1;
    [SerializeField] int startDay = 1;

    [Header("Date - Target")]
    [SerializeField] DateTarget dateTarget = DateTarget.ByDays;
    [Tooltip("ByDays: 넘길 일수 (음수면 과거로)")]
    [SerializeField] int days = 30;
    [Tooltip("ToTargetDate: 목표 날짜")]
    [SerializeField] int targetYear = 2026;
    [SerializeField] int targetMonth = 12;
    [SerializeField] int targetDay = 25;

    [Header("Auto Play")]
    [SerializeField] bool playOnStart = true;
    [SerializeField] float autoPlayDelay = 0.5f;

    [Header("Speed")]
    [Tooltip("목표까지 걸리는 전체 시간(초)")]
    [SerializeField] float rollTime = 1.5f;
    [Tooltip("값 갱신 간격(초). 작을수록 빠르게 바뀜. 0.03~0.08 추천")]
    [SerializeField] float tickInterval = 0.05f;
    [Tooltip("롤링 시간 = tickInterval * 이 값")]
    [SerializeField, Range(0.3f, 1f)] float rollRatio = 0.85f;
    [Tooltip("기본값: 처음엔 빠르고 끝에서 느려짐")]
    [SerializeField] AnimationCurve progress = new AnimationCurve(
        new Keyframe(0f, 0f, 2f, 2f),
        new Keyframe(1f, 1f, 0f, 0f));
    [Tooltip("마지막 값은 이 시간 동안 천천히 안착")]
    [SerializeField] float finalRollDuration = 0.3f;
    [Tooltip("Add() 로 한 칸씩 넘길 때 롤링 시간")]
    [SerializeField] float normalRollDuration = 0.35f;

    // Number/MinSec: 실제 값, Date: baseDate 로부터의 일수
    int current;
    int startValue;
    DateTime baseDate;
    Coroutine routine;

    public int CurrentValue => current;
    public DateTime CurrentDate => baseDate.AddDays(current);
    public bool IsRolling => routine != null;

    void Start()
    {
        if (mode == Mode.Date)
        {
            baseDate = useToday
                ? DateTime.Today
                : new DateTime(startYear, Mathf.Clamp(startMonth, 1, 12), 1)
                    .AddDays(Mathf.Max(1, startDay) - 1);
            startValue = 0;
        }
        else
        {
            startValue = from;
        }

        SetValue(startValue, false);

        if (playOnStart)
            routine = StartCoroutine(DelayedPlay());
    }

    IEnumerator DelayedPlay()
    {
        if (autoPlayDelay > 0f)
            yield return new WaitForSeconds(autoPlayDelay);

        routine = null;
        Play();
    }

    // ---------------- Public API ----------------

    /// <summary>인스펙터 설정대로 목표까지 실행</summary>
    [ContextMenu("Play")]
    public void Play() => PlayTo(InspectorTarget(), rollTime);

    /// <summary>시작 값으로 되돌림 (애니메이션 없음)</summary>
    [ContextMenu("Reset To Start")]
    public void ResetToStart()
    {
        StopRoutine();
        SetDurations(normalRollDuration);
        SetValue(startValue, false);
    }

    [ContextMenu("Next (+1)")]
    public void Next() => Add(1);

    [ContextMenu("Prev (-1)")]
    public void Prev() => Add(-1);

    /// <summary>한 칸씩 넘김 (Date: 일, MinSec: 초, Number: 1)</summary>
    public void Add(int amount)
    {
        StopRoutine();
        SetDurations(normalRollDuration);
        SetValue(current + amount, true);
    }

    /// <summary>목표 값까지 totalTime 동안 빠르게 (Date 모드면 baseDate 기준 일수)</summary>
    public void PlayTo(int target, float totalTime)
    {
        StopRoutine();
        if (target == current) return;
        routine = StartCoroutine(FastRoutine(current, target, totalTime));
    }

    /// <summary>Date 모드: 지정 날짜까지 빠르게</summary>
    public void RollTo(DateTime date, float totalTime)
    {
        PlayTo((int)(date.Date - baseDate).TotalDays, totalTime);
    }

    /// <summary>Date 모드: 날짜 바로 지정</summary>
    public void SetDate(DateTime date, bool animate)
    {
        StopRoutine();
        SetValue((int)(date.Date - baseDate).TotalDays, animate);
    }

    public void SetValue(int value, bool animate)
    {
        current = value;
        mainText.SetValue(MainString(value), animate);

        if (mode == Mode.Date && weekdayText != null)
            weekdayText.SetValue(WeekdayName(baseDate.AddDays(value)), animate);
    }

    // ---------------- Internal ----------------

    int InspectorTarget()
    {
        if (mode != Mode.Date) return to;

        if (dateTarget == DateTarget.ByDays) return startValue + days;

        int y = Mathf.Clamp(targetYear, 1, 9999);
        int m = Mathf.Clamp(targetMonth, 1, 12);
        int d = Mathf.Clamp(targetDay, 1, DateTime.DaysInMonth(y, m));
        return (int)(new DateTime(y, m, d) - baseDate).TotalDays;
    }

    IEnumerator FastRoutine(int start, int end, float totalTime)
    {
        int last = start;
        SetDurations(tickInterval * rollRatio);

        float elapsed = 0f;
        float nextTick = 0f;

        while (elapsed < totalTime)
        {
            elapsed += Time.deltaTime;

            if (elapsed >= nextTick)
            {
                nextTick += tickInterval;

                float p = progress.Evaluate(Mathf.Clamp01(elapsed / totalTime));
                int value = Mathf.RoundToInt(Mathf.Lerp(start, end, p));

                // 마지막 값은 아래에서 천천히
                if (value != last && value != end)
                {
                    SetValue(value, true);
                    last = value;
                }
            }

            yield return null;
        }

        SetDurations(finalRollDuration);
        SetValue(end, true);

        yield return new WaitForSeconds(finalRollDuration);
        SetDurations(normalRollDuration);
        routine = null;
    }

    void StopRoutine()
    {
        if (routine == null) return;
        StopCoroutine(routine);
        routine = null;
    }

    void SetDurations(float d)
    {
        mainText.Duration = d;
        if (weekdayText != null) weekdayText.Duration = d;
    }

    string MainString(int v)
    {
        switch (mode)
        {
            case Mode.MinSec:
                v = Mathf.Max(0, v);
                return $"{v / 60:00}:{v % 60:00}";
            case Mode.Date:
                return baseDate.AddDays(v).ToString(dateFormat, CultureInfo.InvariantCulture);
            default:
                return v.ToString();
        }
    }

    string WeekdayName(DateTime d)
    {
        int i = (int)d.DayOfWeek;
        return (weekdayNames != null && weekdayNames.Length == 7) ? weekdayNames[i] : d.DayOfWeek.ToString();
    }
}