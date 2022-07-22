using System;
#if UNITY_EDITOR
using UnityEditor;
using UnityEditor.ProjectWindowCallback;
#endif
using UnityEngine;
using UnityEngine.Rendering;

public class AtmosphereConfig : ScriptableObject
{
    public bool ForceUpdate;
    public GeneralParameters generalParameters;
    public SunDiskParameters sunDiskParameters;
    public AtmosphereParameters atmosphereParameters;
    public AtmosphereShaderResources shaders;

#if UNITY_EDITOR
    internal class CreateAtmosphereConfigAsset : EndNameEditAction
    {
        public override void Action(int instanceId, string pathName, string resourceFile)
        {
            var instance = CreateInstance<AtmosphereConfig>();
            AssetDatabase.CreateAsset(instance, pathName);
            ResourceReloader.ReloadAllNullIn(instance, "Assets");
            Selection.activeObject = instance;
        }
    }

    [MenuItem("Assets/Create/Atmosphere/Config")]
    static void CreatePostProcessData()
    {
        ProjectWindowUtil.StartNameEditingIfProjectWindowExists(0, CreateInstance<CreateAtmosphereConfigAsset>(),
            "AtmosphereConfig.asset", null, null);
    }
#endif

    public override int GetHashCode()
    {
        var hashCode = new HashCode();
        hashCode.Add(atmosphereParameters.BottomRadius);
        hashCode.Add(atmosphereParameters.TopRadius);
        hashCode.Add(atmosphereParameters.RayleighScaleHeight);
        hashCode.Add(atmosphereParameters.RayleighScatteringColor);
        hashCode.Add(atmosphereParameters.RayleighScatteringScale);
        hashCode.Add(atmosphereParameters.MieScaleHeight);
        hashCode.Add(atmosphereParameters.MieScatteringColor);
        hashCode.Add(atmosphereParameters.MieScatteringScale);
        hashCode.Add(atmosphereParameters.MieAbsorptionColor);
        hashCode.Add(atmosphereParameters.MieAbsorptionScale);
        hashCode.Add(atmosphereParameters.MiePhaseG);
        hashCode.Add(atmosphereParameters.OzoneAbsorptionExtinctionColor);
        hashCode.Add(atmosphereParameters.OzoneAbsorptionExtinctionScale);
        hashCode.Add(atmosphereParameters.GroundAlbedo);
        hashCode.Add(generalParameters.MultiScattering);
        return hashCode.ToHashCode();
    }
}

[Serializable]
public sealed class GeneralParameters
{
    public Color SunRadianceColor = Color.white;
    [Min(0)] public float SunRadianceIntensity = 5;
    public bool UpdateMainLightByAtmosphere = true;
    public bool UpdateAmbientByAtmosphere = true;
    public bool AtmosphereFog = true;
    [HideInInspector] public bool AerialPerspective = false;
    [Range(0f, 10f)] public float DensityScale = 1;
    public bool MultiScattering = true;
    public bool Shadowmap = false;

    [Tooltip("Min to Max Steps with the distance of raymarching from 0 to 100,000 meters")] [Range(1, 40)]
    public int MinSteps = 4;

    [Tooltip("Min to Max Steps with the distance of raymarching from 0 to 100,000 meters")] [Range(2, 41)]
    public int MaxSteps = 14;
}

[Serializable]
public sealed class SunDiskParameters
{
    public bool SunDisk = true;
    [Range(0.01f, 1f)] public float SunSize = 0.1f;
    [Range(0f, 1f)] public float SunDiskBrightness = 0.1f;
    [Min(0)] public float SunDiskBrightnessMax = 100f;
    public bool SunLimbDarken = true;
    [Range(1f, 10f)] public float SunLimbDarkenIntensity = 2f;
    public bool SunTransmittancedPerPixel = false;
}

[Serializable]
public sealed class AtmosphereParameters
{
    [Header("Rayleigh Scattering")] [Min(1)]
    public float RayleighScaleHeight = 8;

    public Color RayleighScatteringColor = new Color(41f / 255, 95f / 255, 233f / 255);
    [Range(0f, 1f)] public float RayleighScatteringScale = 0.03624f;

    [Header("Mie Scattering")] [Min(0)] public float MieScaleHeight = 1.2f;
    public Color MieScatteringColor = new Color(147f / 255, 147f / 255, 147f / 255);
    [Range(0f, 3f)] public float MieScatteringScale = 0.00692f;
    public Color MieAbsorptionColor = new Color(147f / 255, 147f / 255, 147f / 255);
    [Range(0f, 1f)] public float MieAbsorptionScale = 0.00077f;
    [Range(0f, 1f)] public float MiePhaseG = 0.8f;

    [Header("Ozone Absorption")]
    public Color OzoneAbsorptionExtinctionColor = new Color(83f / 255, 241f / 255, 11f / 255);

    [Range(0f, 0.3f)] public float OzoneAbsorptionExtinctionScale = 0.00199f;

    [Header("Ground")] public Color GroundAlbedo = Color.black;
    [Min(0)] public float BottomRadius = 6360;
    [Min(0)] public float TopRadius = 6460;
}

[Serializable, ReloadGroup]
public class AtmosphereShaderResources
{
    [Reload("Atmosphere/Shaders/TransmittanceLut.shader")]
    public Shader transmittanceLut;

    [Reload("Atmosphere/Shaders/AtmosphereMultiScatter.compute")]
    public ComputeShader multiScatterCS;

    [Reload("Atmosphere/Shaders/SkyViewLut.shader")]
    public Shader skyViewLut;

    [Reload("Atmosphere/Shaders/AtmosphereRaymarch.shader")]
    public Shader atmosphereRaymarch;
}

public class LutInfo
{
    public const string TransmittanceLutName = "_TransmittanceLut";
    public const int TransmittanceLutWidth = 256;
    public const int TransmittanceLutHeight = 64;
    public const RenderTextureFormat TransmittanceLutFormat = RenderTextureFormat.RGB111110Float; //check support?
    public static readonly int TransmittanceLutNameId = Shader.PropertyToID(TransmittanceLutName);

    public const string MultiScatterLuaName = "_MultiScatterLut";
    public const RenderTextureFormat MultiScatterLuaFormat = RenderTextureFormat.RGB111110Float; //check support?
    public const int MultiScatterRes = 32;
    public static readonly int MultiScatterLuaNameId = Shader.PropertyToID(MultiScatterLuaName);

    public const string SkyViewLutName = "_SkyViewLut";
    public const int SkyViewLutWidth = 192;
    public const int SkyViewLutHeight = 108;
    public const RenderTextureFormat SkyViewLutFormat = RenderTextureFormat.RGB111110Float; //check support?
    public static readonly int SkyViewLutNameId = Shader.PropertyToID(SkyViewLutName);

    public const string AmbientLutName = "_AmbientLut";
    public const int AmbientLutWidth = 128;
    public const RenderTextureFormat AmbientLutFormat = RenderTextureFormat.RGB111110Float; //check support?
}