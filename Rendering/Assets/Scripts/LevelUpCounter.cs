using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using TMPro;

public class LevelUpCounter : MonoBehaviour
{
    public TextMeshProUGUI levelText;
    private int level = 10;

    public void Upgrade()
    {
        level += 1;
        level = Mathf.Min(level, 99);
        levelText.text = level.ToString();
    }


    // Start is called before the first frame update
    void Start()
    {
        
    }

    // Update is called once per frame
    void Update()
    {
        
    }
}
