using System;
using UnityEngine;

public class ConfigAutoUpdate : MonoBehaviour
{
    public AtmosphereConfig config;

    public ColorController rayleigh;
    public ColorController ozone;

    void OnEnable()
    {
        rayleigh.Init(config.atmosphereParameters.RayleighScatteringColor);
        ozone.Init(config.atmosphereParameters.OzoneAbsorptionExtinctionColor);
    }

    void OnDisable()
    {
        config.atmosphereParameters.RayleighScatteringColor = rayleigh.OriColor;
        config.atmosphereParameters.OzoneAbsorptionExtinctionColor = ozone.OriColor;
    }

    void Update()
    {
        config.atmosphereParameters.RayleighScatteringColor = rayleigh.Update();
        config.atmosphereParameters.OzoneAbsorptionExtinctionColor = ozone.Update();
    }
}

[Serializable]
public class ColorController
{
    [Header("Rayleigh")] [Range(0, 1f)] public float Hue;
    [Range(0, 1f)] public float Saturation;
    [Range(0, 1f)] public float Value;
    public Color Color;
    [Range(0, 1)] public float Speed;
    private Color _oriColor;

    public Color OriColor => _oriColor;

    public void Init(Color color)
    {
        _oriColor = Color = color;
        Color.RGBToHSV(color, out Hue, out Saturation, out Value);
    }

    public Color Update()
    {
        Hue += Time.deltaTime * Speed;
        while (Hue > 1)
        {
            Hue -= 1;
        }

        Color = Color.HSVToRGB(Hue, Saturation, Value);
        return Color;
    }
    
}