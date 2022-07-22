using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class AtmospherePrecomputeManager
{
    public void ComputeLuts(CommandBuffer cmd, AtmosphereData data, AtmosphereConfig config)
    {
        ComputeTransmittanceLut(cmd, data, config);
        ComputeMultipleScatterLut(cmd, data, config);
        ComputeSkyViewLut(cmd, data, config);
        ComputeAmbientLut(cmd, data, config);
    }

    public void PrepareData(CommandBuffer cmd, AtmosphereData data, AtmosphereConfig config, Vector3 cameraPos,
        Vector4 mainLightPosition)
    {
        var mainLightColor = config.generalParameters.SunRadianceColor.linear *
                             config.generalParameters.SunRadianceIntensity;
        if (Mathf.Abs(data.cameraPos.y - cameraPos.y) > 10 ||
            mainLightPosition != data.sunDir ||
            mainLightColor != data.sunColor || config.ForceUpdate)
        {
            data.SetValid(ELutType.SkyViewLut, false);
            data.cameraPos = cameraPos;
            data.sunDir = mainLightPosition;
            data.sunColor = mainLightColor;
        }

        var hash = config.GetHashCode();
        if (hash != data.atmosHashCode || config.ForceUpdate)
        {
            data.SetValid(ELutType.All, false);
            data.atmosHashCode = hash;
        }

        cmd.SetGlobalVector(CameraPosForAtmosphere, cameraPos);
        cmd.SetGlobalVector(SunDirectionForAtmosphere, mainLightPosition.normalized);
        cmd.SetGlobalColor(SunRadianceForAtmosphere, mainLightColor);
        cmd.SetGlobalVector(AtmosphereLutParams,
            new Vector4(LutInfo.TransmittanceLutWidth, LutInfo.TransmittanceLutHeight, LutInfo.SkyViewLutWidth,
                LutInfo.SkyViewLutHeight));
        cmd.SetGlobalVector(AtmosphereRaymarchParams,
            new Vector4(config.generalParameters.MinSteps, config.generalParameters.MaxSteps));
        if (config.generalParameters.MultiScattering)
            Shader.EnableKeyword("_MultiScattering_Enable");
        else
            Shader.DisableKeyword("_MultiScattering_Enable");
        SetSunParams(cmd, config.sunDiskParameters);
        SetAtmosphereParams(cmd, config.atmosphereParameters);
    }

    public bool GetMainLightColor(CommandBuffer cmd, AtmosphereData data, AtmosphereConfig config,
        out Color mainLightColor)
    {
        mainLightColor = Color.white;
        if (!config.generalParameters.UpdateMainLightByAtmosphere) return false;
        if (data.directionalLightColors == null) return false;
        var viewHeight = AtmosphereTools.UvToLutTransmittanceParams(0.5f / LutInfo.TransmittanceLutHeight,
            config.atmosphereParameters.TopRadius, config.atmosphereParameters.BottomRadius);
        var viewZenithCosAngle = Vector3.Dot(data.sunDir, Vector3.up);
        var u = AtmosphereTools.LutTransmittanceParamsToUv(viewHeight, viewZenithCosAngle,
            config.atmosphereParameters.TopRadius, config.atmosphereParameters.BottomRadius);

        var colors = data.directionalLightColors;
        var sampleValue = Mathf.Clamp01(u) * (colors.Length - 1);
        var index = (int) sampleValue;
        mainLightColor = index + 1 < colors.Length
            ? Color.Lerp(colors[index], colors[index + 1], sampleValue - index)
            : colors[index];
        mainLightColor *= config.generalParameters.SunRadianceColor.linear *
                          config.generalParameters.SunRadianceIntensity;
        if (u > 1)
        {
            mainLightColor *= Mathf.Lerp(1, MinColorValue, u - 1);
        }

        var maxCom = mainLightColor.maxColorComponent;
        if (maxCom < MinColorValue)
        {
            if (maxCom > 0)
            {
                mainLightColor *= MinColorValue / maxCom;
            }
            else
            {
                mainLightColor = MinColor; //unity will stripe the black lights,
            }
            // Debug.LogWarning(
            // $"The main light color can not be black. sun dir {data.sunDir}, u {u}, sampleValue {sampleValue}");
        }

        return true;
    }

    public bool GetAmbientColor(CommandBuffer cmd, AtmosphereData data, AtmosphereConfig config, out Color groundColor,
        out Color equatorColor, out Color skyColor)
    {
        groundColor = equatorColor = skyColor = Color.white;
        if (!config.generalParameters.UpdateAmbientByAtmosphere) return false;
        if (data.ambientColors == null) return false;
        var viewZenithCosAngle = Vector3.Dot(data.sunDir, Vector3.up);
        var u = (viewZenithCosAngle + 0.1f) / 1.1f;
        var colors = data.ambientColors;
        var length = LutInfo.AmbientLutWidth;
        var sampleValue = Mathf.Clamp01(u) * (length - 1);
        var index = (int) sampleValue;
        var weight = sampleValue - index;
        var hasNext = index + 1 < length;
        groundColor = hasNext
            ? Color.Lerp(colors[index], colors[index + 1], weight)
            : colors[index];
        index += length;
        equatorColor = hasNext
            ? Color.Lerp(colors[index], colors[index + 1], weight)
            : colors[index];
        index += length;
        skyColor = hasNext
            ? Color.Lerp(colors[index], colors[index + 1], weight)
            : colors[index];
        var sunRadiance = config.generalParameters.SunRadianceColor.linear *
                          config.generalParameters.SunRadianceIntensity;
        groundColor *= sunRadiance;
        equatorColor *= sunRadiance;
        skyColor *= sunRadiance;
        return true;
    }

    public bool RaymarchPass(CommandBuffer cmd, AtmosphereData data, AtmosphereConfig config)
    {
        if (data.cameraPos.y > config.atmosphereParameters.TopRadius ||
            config.generalParameters.AtmosphereFog && !config.generalParameters.AerialPerspective)
        {
            data.CheckRaymarchResource(config);
            if (config.generalParameters.Shadowmap)
                data.raymarchMaterial.EnableKeyword("_ShadowMap_Enable");
            else
                data.raymarchMaterial.DisableKeyword("_ShadowMap_Enable");
            data.raymarchMaterial.SetFloat(DensityScale, config.generalParameters.DensityScale);
            cmd.SetViewProjectionMatrices(Matrix4x4.identity, Matrix4x4.identity);
            cmd.DrawMesh(RenderingUtils.fullscreenMesh, Matrix4x4.identity, data.raymarchMaterial);
            return true;
        }

        return false;
    }

    public bool NeedDepthTexture(AtmosphereConfig config)
    {
        return config.generalParameters.AtmosphereFog && !config.generalParameters.AerialPerspective;
    }

    private void SetSunParams(CommandBuffer cmd, SunDiskParameters sunDiskParams)
    {
        cmd.SetGlobalVector(SunDiskParams,
            new Vector4(sunDiskParams.SunSize, sunDiskParams.SunDiskBrightness, sunDiskParams.SunDiskBrightnessMax,
                sunDiskParams.SunLimbDarkenIntensity));
        if (sunDiskParams.SunDisk)
            Shader.EnableKeyword("_SunDisk_Enable");
        else
            Shader.DisableKeyword("_SunDisk_Enable");
        if (sunDiskParams.SunLimbDarken)
            Shader.EnableKeyword("_SunDisk_LimbDarken");
        else
            Shader.DisableKeyword("_SunDisk_LimbDarken");
        if (sunDiskParams.SunTransmittancedPerPixel)
            Shader.EnableKeyword("_SunDisk_Transmittanced");
        else
            Shader.DisableKeyword("_SunDisk_Transmittanced");
    }

    private void SetAtmosphereParams(CommandBuffer cmd, AtmosphereParameters atmParams)
    {
        cmd.SetGlobalFloat(BottomRadius, atmParams.BottomRadius);
        cmd.SetGlobalFloat(TopRadius, atmParams.TopRadius);
        cmd.SetGlobalFloat(RayleighDensityExpScale, -1f / atmParams.RayleighScaleHeight);
        cmd.SetGlobalColor(RayleighScattering,
            atmParams.RayleighScatteringColor * atmParams.RayleighScatteringScale);
        cmd.SetGlobalFloat(MieDensityExpScale, -1f / atmParams.MieScaleHeight);
        cmd.SetGlobalColor(MieScattering,
            atmParams.MieScatteringColor * atmParams.MieScatteringScale);
        cmd.SetGlobalColor(MieAbsorption,
            atmParams.MieAbsorptionColor * atmParams.MieAbsorptionScale);
        cmd.SetGlobalFloat(MiePhaseG, atmParams.MiePhaseG);

        cmd.SetGlobalColor(OzoneAbsorptionExtinction,
            atmParams.OzoneAbsorptionExtinctionColor * atmParams.OzoneAbsorptionExtinctionScale);
        cmd.SetGlobalColor(GroundAlbedo, atmParams.GroundAlbedo);
    }

    private void ComputeTransmittanceLut(CommandBuffer cmd, AtmosphereData data, AtmosphereConfig config)
    {
        if (data.transmittanceLutUpdating)
        {
            data.GetDirectionalColors(); // fetch transmittance from lut.
            data.transmittanceLutUpdating = false;
        }

        if (!data.IsValid(ELutType.TransmittanceLut) || config.ForceUpdate)
        {
            data.CheckTransmittanceResource(config);
            cmd.Blit(null, data.transmittanceLut, data.transmittanceMaterial, 0);
            data.SetValid(ELutType.TransmittanceLut, true);

            data.transmittanceLutUpdating = true; // fetch result in the NEXT frame
        }

        cmd.SetGlobalTexture(LutInfo.TransmittanceLutNameId, data.transmittanceLut);
    }

    private void ComputeAmbientLut(CommandBuffer cmd, AtmosphereData data, AtmosphereConfig config)
    {
        if (!config.generalParameters.UpdateAmbientByAtmosphere && !config.ForceUpdate) return;
        if (data.ambientLutUpdating)
        {
            data.GetAmbientColors(); // fetch ambient from lut.
            data.ambientLutUpdating = false;
        }

        if (!data.IsValid(ELutType.AmbientLut) || config.ForceUpdate)
        {
            data.transmittanceMaterial.SetInteger(AmbientLutRes, LutInfo.AmbientLutWidth);
            data.CheckAmbientResource(config);
            cmd.Blit(null, data.ambientLut, data.transmittanceMaterial, 1);
            data.SetValid(ELutType.AmbientLut, true);
            data.ambientLutUpdating = true; // fetch result in the NEXT frame
        }
    }

    private void ComputeMultipleScatterLut(CommandBuffer cmd, AtmosphereData data, AtmosphereConfig config)
    {
        if (!config.generalParameters.MultiScattering && !config.ForceUpdate) return;
        if (!data.IsValid(ELutType.MultiScatteringLut) || config.ForceUpdate)
        {
            data.CheckMultipleScatterResource();
            cmd.SetComputeIntParam(config.shaders.multiScatterCS, MultiScatteringLutRes, LutInfo.MultiScatterRes);
            cmd.SetComputeTextureParam(config.shaders.multiScatterCS, 0, OutputTexture,
                data.multiScatterLut);
            cmd.DispatchCompute(config.shaders.multiScatterCS, 0, LutInfo.MultiScatterRes, LutInfo.MultiScatterRes, 1);
            data.SetValid(ELutType.MultiScatteringLut, true);
        }

        cmd.SetGlobalTexture(LutInfo.MultiScatterLuaNameId, data.multiScatterLut);
        cmd.SetGlobalInteger(MultiScatteringLutRes, LutInfo.MultiScatterRes);
    }

    private void ComputeSkyViewLut(CommandBuffer cmd, AtmosphereData data, AtmosphereConfig config)
    {
        if (!data.IsValid(ELutType.SkyViewLut) || config.ForceUpdate)
        {
            data.CheckSkyViewResource(config);
            cmd.Blit(null, data.skyViewLut, data.skyViewMaterial);
            data.SetValid(ELutType.SkyViewLut, true);
        }

        cmd.SetGlobalTexture(LutInfo.SkyViewLutNameId, data.skyViewLut);
    }

    private class ELutType
    {
        public const uint TransmittanceLut = 1;
        public const uint MultiScatteringLut = 2;
        public const uint SkyViewLut = 4;
        public const uint AmbientLut = 8;
        public const uint All = TransmittanceLut | MultiScatteringLut | SkyViewLut | AmbientLut;
    }

    private static float MinColorValue = 1 / 255f;
    private static Color MinColor = new Color(MinColorValue, MinColorValue, MinColorValue);
    private static readonly int BottomRadius = Shader.PropertyToID("_BottomRadius");
    private static readonly int TopRadius = Shader.PropertyToID("_TopRadius");
    private static readonly int RayleighDensityExpScale = Shader.PropertyToID("_RayleighDensityExpScale");
    private static readonly int RayleighScattering = Shader.PropertyToID("_RayleighScattering");
    private static readonly int MieDensityExpScale = Shader.PropertyToID("_MieDensityExpScale");
    private static readonly int MieScattering = Shader.PropertyToID("_MieScattering");
    private static readonly int MieAbsorption = Shader.PropertyToID("_MieAbsorption");
    private static readonly int MiePhaseG = Shader.PropertyToID("_MiePhaseG");
    private static readonly int OzoneAbsorptionExtinction = Shader.PropertyToID("_OzoneAbsorptionExtinction");
    private static readonly int GroundAlbedo = Shader.PropertyToID("_GroundAlbedo");
    private static readonly int CameraPosForAtmosphere = Shader.PropertyToID("_CameraPosForAtmosphere");
    private static readonly int SunDirectionForAtmosphere = Shader.PropertyToID("_SunDirectionForAtmosphere");
    private static readonly int SunRadianceForAtmosphere = Shader.PropertyToID("_SunRadianceForAtmosphere");
    private static readonly int AtmosphereLutParams = Shader.PropertyToID("_AtmosphereLutParams");
    private static readonly int SunDiskParams = Shader.PropertyToID("_SunDiskParams");
    private static readonly int AtmosphereRaymarchParams = Shader.PropertyToID("_AtmosphereRaymarchParams");
    private static readonly int MultiScatteringLutRes = Shader.PropertyToID("_MultiScatteringLutRes");
    private static readonly int OutputTexture = Shader.PropertyToID("_OutputTexture");
    private static readonly int AmbientLutRes = Shader.PropertyToID("_AmbientLutRes");
    private static readonly int DensityScale = Shader.PropertyToID("_DensityScale");
}

public class AtmosphereData : IDisposable
{
    public uint validMask;
    public int atmosHashCode;
    public Vector3 cameraPos;
    public Vector4 sunDir;
    public Color sunColor;
    public Texture2D directionalLightTexture;
    public Texture2D ambientTexture;
    public Color[] directionalLightColors;
    public Color[] ambientColors;
    public bool transmittanceLutUpdating;
    public bool ambientLutUpdating;

    public RenderTexture transmittanceLut;
    public RenderTexture ambientLut;
    public RenderTexture multiScatterLut;
    public RenderTexture skyViewLut;
    public Material transmittanceMaterial;
    public Material skyViewMaterial;
    public Material raymarchMaterial;

    public void CheckTransmittanceResource(AtmosphereConfig config)
    {
        transmittanceLut = AtmosphereTools.GetRenderTexture(LutInfo.TransmittanceLutName,
            LutInfo.TransmittanceLutWidth,
            LutInfo.TransmittanceLutHeight, LutInfo.TransmittanceLutFormat, FilterMode.Bilinear, transmittanceLut,
            out _);
        if (transmittanceMaterial == null)
            transmittanceMaterial = new Material(config.shaders.transmittanceLut);
    }

    public void CheckAmbientResource(AtmosphereConfig config)
    {
        ambientLut = AtmosphereTools.GetRenderTexture(LutInfo.AmbientLutName, LutInfo.AmbientLutWidth,
            3, LutInfo.AmbientLutFormat, FilterMode.Bilinear, ambientLut, out _);
        if (transmittanceMaterial == null)
            transmittanceMaterial = new Material(config.shaders.transmittanceLut);
    }

    public void CheckMultipleScatterResource()
    {
        multiScatterLut = AtmosphereTools.GetRenderTexture(LutInfo.MultiScatterLuaName, LutInfo.MultiScatterRes,
            LutInfo.MultiScatterRes, LutInfo.MultiScatterLuaFormat, FilterMode.Bilinear, multiScatterLut,
            out var createNew);
        if (createNew)
        {
            multiScatterLut.enableRandomWrite = true;
            multiScatterLut.Create();
        }
    }

    public void CheckSkyViewResource(AtmosphereConfig config)
    {
        skyViewLut = AtmosphereTools.GetRenderTexture(LutInfo.SkyViewLutName, LutInfo.SkyViewLutWidth,
            LutInfo.SkyViewLutHeight, LutInfo.SkyViewLutFormat, FilterMode.Bilinear, skyViewLut, out _);
        if (skyViewMaterial == null)
            skyViewMaterial = new Material(config.shaders.skyViewLut);
    }

    public void CheckRaymarchResource(AtmosphereConfig config)
    {
        if (raymarchMaterial == null)
            raymarchMaterial = new Material(config.shaders.atmosphereRaymarch);
    }

    public void Dispose()
    {
        validMask = 0;
        atmosHashCode = 0;
        transmittanceLutUpdating = false;
        ambientLutUpdating = false;

        if (transmittanceLut != null)
        {
            RenderTexture.ReleaseTemporary(transmittanceLut);
            transmittanceLut = null;
        }

        if (multiScatterLut != null)
        {
            RenderTexture.ReleaseTemporary(multiScatterLut);
            multiScatterLut = null;
        }

        if (skyViewLut != null)
        {
            RenderTexture.ReleaseTemporary(skyViewLut);
            skyViewLut = null;
        }

        if (transmittanceMaterial != null)
        {
            AtmosphereTools.SafeDestroy(transmittanceMaterial);
            transmittanceMaterial = null;
        }

        if (skyViewMaterial != null)
        {
            AtmosphereTools.SafeDestroy(skyViewMaterial);
            skyViewMaterial = null;
        }
    }

    public bool IsValid(uint type)
    {
        return (validMask & type) != 0;
    }

    public void SetValid(uint type, bool valid)
    {
        if (valid)
        {
            validMask |= type;
        }
        else
        {
            validMask &= ~type;
        }
    }

    public void GetDirectionalColors()
    {
        var oldActive = RenderTexture.active;
        RenderTexture.active = transmittanceLut;
        if (directionalLightTexture == null)
            directionalLightTexture =
                new Texture2D(LutInfo.TransmittanceLutWidth, 1, TextureFormat.RGBAHalf, false, true);
        directionalLightTexture.ReadPixels(
            new Rect(0, LutInfo.TransmittanceLutHeight - 1, LutInfo.TransmittanceLutWidth, 1), 0, 0,
            false);
        directionalLightTexture.Apply(false);
        RenderTexture.active = oldActive;
        directionalLightColors = directionalLightTexture.GetPixels();
        // cmd.Blit(directionalLightTexture, AtmosphereTools.GetRenderTexture(LutInfo.TransmittanceLutName,
        //     LutInfo.TransmittanceLutWidth, 1, LutInfo.TransmittanceLutFormat, FilterMode.Bilinear, null, out _));
    }

    public void GetAmbientColors()
    {
        var oldActive = RenderTexture.active;
        RenderTexture.active = ambientLut;
        if (ambientTexture == null)
            ambientTexture = new Texture2D(LutInfo.AmbientLutWidth, 3, TextureFormat.RGBAHalf, false, true);
        ambientTexture.ReadPixels(new Rect(0, 0, LutInfo.AmbientLutWidth, 3), 0, 0, false);
        ambientTexture.Apply(false);
        RenderTexture.active = oldActive;
        ambientColors = ambientTexture.GetPixels();
    }
}

public enum EDirectionalColorState
{
    None,
    NeedUpdate,
    Updated
}