#ifndef ATMOSPHERE_RAYMARCH_HELPER_INCLUDED
#define ATMOSPHERE_RAYMARCH_HELPER_INCLUDED

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/UnityInput.hlsl"

#include "AtmosphereCommon.hlsl"

struct SingleScatteringResult
{
    half3 L; // Scattered light (luminance)
    half3 OpticalDepth; // Optical depth (1/m)
    half3 Transmittance; // Transmittance in [0,1] (unitless)
    half3 MultiScatAs1;
};

SingleScatteringResult IntegrateScatteredLuminance(in float3 viewPos, in half3 viewDir, in half3 sunDir,
                                                   in half3 sunRadiance, bool ground, half densityScale,
                                                   in half sampleCountIni, in float linearDepth,
                                                   bool variableSampleCount, bool useMieRayPhase)
{
    SingleScatteringResult result = (SingleScatteringResult)0;

    // Compute next intersection with atmosphere or ground 
    float3 earthO = float3(0.0f, 0.0f, 0.0f);
    float tBottom = RaySphereIntersectNearest(viewPos, viewDir, earthO, _BottomRadius);
    float tTop = RaySphereIntersectNearest(viewPos, viewDir, earthO, _TopRadius);

    // Compute the endpoint distance
    float tMax = 0.0f;
    if (tBottom < 0.0f)
    {
        if (tTop < 0.0f)
        {
            tMax = 0.0f; // No intersection with earth nor atmosphere: stop right away  
            return result;
        }
        else
        {
            tMax = tTop;
        }
    }
    else
    {
        if (tTop > 0.0f)
        {
            tMax = min(tTop, tBottom);
        }
    }

    if (linearDepth >= 0.0f)
    {
        tMax = min(tMax, linearDepth);
    }

    tMax = min(tMax, 9000000.0f);

    // Sample count 
    half SampleCount = sampleCountIni;
    half SampleCountFloor = sampleCountIni;
    float tMaxFloor = tMax;
    if (variableSampleCount)
    {
        SampleCount = lerp(_RayMarchMinMaxSPP.x, _RayMarchMinMaxSPP.y, saturate(tMax * 0.01));
        SampleCountFloor = floor(SampleCount);
        tMaxFloor = tMax * SampleCountFloor / SampleCount; // rescale tMax to map to the last entire step segment.
    }
    float dt = tMax / SampleCount;

    // Phase functions
    const half uniformPhase = 1.0 / (4.0 * PI);
    const half3 wi = sunDir;
    const half3 wo = viewDir;
    half cosTheta = dot(wi, wo);
    half MiePhaseValue = HgPhase(_MiePhaseG, -cosTheta);
    // mnegate cosTheta because due to viewDir being a "in" direction. 
    half RayleighPhaseValue = RayleighPhase(cosTheta);

    // Ray march the atmosphere to integrate optical depth
    half3 L = 0.0f;
    half3 transmittanceAccu = 1.0;
    half3 OpticalDepth = 0.0;
    half t = 0.0f;
    half tPrev = 0.0;
    const half SampleSegmentT = 0.3f;
    for (half s = 0.0f; s < SampleCount; s += 1.0f)
    {
        if (variableSampleCount)
        {
            // More expenssive but artefact free
            half t0 = (s) / SampleCountFloor;
            half t1 = (s + 1.0f) / SampleCountFloor;
            // Non linear distribution of sample within the range.
            t0 = t0 * t0;
            t1 = t1 * t1;
            // Make t0 and t1 world space distances.
            t0 = tMaxFloor * t0;
            if (t1 > 1.0)
            {
                t1 = tMax;
                //	t1 = tMaxFloor;	// this reveal depth slices
            }
            else
            {
                t1 = tMaxFloor * t1;
            }
            //t = t0 + (t1 - t0) * (whangHashNoise(pixPos.x, pixPos.y, gFrameId * 1920 * 1080)); // With dithering required to hide some sampling artefact relying on TAA later? This may even allow volumetric shadow?
            t = t0 + (t1 - t0) * SampleSegmentT;
            dt = t1 - t0;
        }
        else
        {
            //t = tMax * (s + SampleSegmentT) / SampleCount;
            // Exact difference, important for accuracy of multiple scattering
            half NewT = tMax * (s + SampleSegmentT) / SampleCount;
            dt = NewT - t;
            t = NewT;
        }
        float3 P = viewPos + t * viewDir;

        MediumSampleRGB medium = SampleMediumRGB(P);
        const half3 SampleOpticalDepth = medium.extinction * dt * densityScale;
        const half3 SampleTransmittance = exp(-SampleOpticalDepth);
        OpticalDepth += SampleOpticalDepth;

        float pHeight = length(P);
        const half3 UpVector = P / pHeight;
        half SunZenithCosAngle = dot(sunDir, UpVector);
        float2 uv;
        LutTransmittanceParamsToUv(pHeight, SunZenithCosAngle, uv);
        half3 TransmittanceToSun = SAMPLE_TEXTURE2D_LOD(_TransmittanceLut, sampler_TransmittanceLut, uv, 0).rgb;

        half3 PhaseTimesScattering;
        if (useMieRayPhase)
        {
            PhaseTimesScattering = medium.scatteringMie * MiePhaseValue + medium.scatteringRay * RayleighPhaseValue;
        }
        else
        {
            PhaseTimesScattering = medium.scattering * uniformPhase;
        }

        // Earth shadow 
        float tEarth = RaySphereIntersectNearest(P, sunDir, earthO + _PLANET_RADIUS_OFFSET * UpVector, _BottomRadius);
        half earthShadow = tEarth >= 0.0 ? 0.0 : 1.0;

        // Dual scattering for multi scattering 

        half3 multiScatteredLuminance = 0.0f;
        #if _MultiScattering_Enable
            multiScatteredLuminance = GetMultipleScattering(pHeight, SunZenithCosAngle);
        #endif

        half shadow = 1.0f;
        #if _ShadowMap_Enable
            //todo: how to calculate the unity's world space pos if the coordinate axis rotates.
            // now I just use shadowmap in ray march pass, and the axis doesn't rotate.
            float3 posWS = (P - float3(0, _BottomRadius, 0)) * _DistanceUnitMeter;
		    shadow = MainLightRealtimeShadow(TransformWorldToShadowCoord(posWS));
        #endif

        half3 MS = medium.scattering * 1;
        half3 MSint = (MS - MS * SampleTransmittance) / medium.extinction;
        result.MultiScatAs1 += transmittanceAccu * MSint;

        half3 S = (earthShadow * shadow * TransmittanceToSun * PhaseTimesScattering +
            multiScatteredLuminance * medium.scattering);
        half3 Sint = (S - S * SampleTransmittance) / medium.extinction;
        L += transmittanceAccu * Sint;

        transmittanceAccu *= SampleTransmittance;

        tPrev = t;
    }

    if (ground && tMax == tBottom && tBottom > 0.0)
    {
        // Account for bounced light off the earth
        float3 P = viewPos + tBottom * viewDir;
        float pHeight = length(P);

        const half3 UpVector = P / pHeight;
        half SunZenithCosAngle = dot(sunDir, UpVector);
        float2 uv;
        LutTransmittanceParamsToUv(pHeight, SunZenithCosAngle, uv);
        half3 TransmittanceToSun = SAMPLE_TEXTURE2D_LOD(_TransmittanceLut, sampler_TransmittanceLut, uv, 0).rgb;

        const half NdotL = saturate(dot(normalize(UpVector), normalize(sunDir)));
        L += TransmittanceToSun * transmittanceAccu * NdotL * _GroundAlbedo / PI;
    }

    result.L = L * sunRadiance;
    result.OpticalDepth = OpticalDepth;
    result.Transmittance = transmittanceAccu;
    return result;
}

half3 RenderTransmittanceLut(float2 uv)
{
    // Compute camera position from LUT coords
    float viewHeight;
    half viewZenithCosAngle;
    UvToLutTransmittanceParams(viewHeight, viewZenithCosAngle, uv);

    //  A few extra needed constants
    float3 viewPos = float3(0.0, viewHeight, 0.0);
    half3 viewDir = half3(0.0, viewZenithCosAngle, sqrt(1.0 - viewZenithCosAngle * viewZenithCosAngle));

    const half sampleCountIni = 40.0f; // Can go a low as 10 sample but energy lost starts to be visible.
    half3 transmittance = exp(-IntegrateScatteredLuminance(viewPos, viewDir, 1, 1, false, 1,
                                                           sampleCountIni, -1, false,
                                                           false).OpticalDepth);

    return transmittance;
}

half3 AtmosphereAmbientLut(float2 uv)
{
    uv.x = DecodeUvToRange01(uv.x, _AmbientLutRes);
    half cosSunZenithAngle = uv.x * 1.1 - 0.1;
    half3 sunDir = half3(0.0, cosSunZenithAngle, sqrt(saturate(1.0 - cosSunZenithAngle * cosSunZenithAngle)));
    float3 viewPos = float3(0.0f, _BottomRadius + 0.01f, 0.0f);
    half3 viewDir = 0;
    half3 LSum = 0;
    #define _SampleCount 16.0
    half start;
    half end;
    half count;
    if (uv.y > 0.6)
    {
        // sky
        start = 0.5;
        end = _SampleCount / 4;
        count = _SampleCount * _SampleCount / 4;
    }
    else if(uv.y < 0.4)
    {
        // ground
        start = _SampleCount * 3 / 4 + 0.5;
        end = _SampleCount;
        count = _SampleCount * _SampleCount / 4;
    }
    else
    {
        // equator
        start = _SampleCount / 4 + 0.5;
        end = _SampleCount * 3 / 4;
        count = _SampleCount * _SampleCount / 2;
    }
    for (half i = 0.5; i < _SampleCount; i += 1.0)
    {
        for (half j = start; j < end; j += 1.0)
        {
            half randA = i / _SampleCount;
            half randB = j / _SampleCount;
            half theta = 2.0 * PI * randA;
            half phi = acos(1.0 - 2.0 * randB);
            // uniform distribution https://mathworld.wolfram.com/SpherePointPicking.html
            //phi = PI * randB;						// bad non uniform
            half cosPhi = cos(phi);
            half sinPhi = sin(phi);
            half cosTheta = cos(theta);
            half sinTheta = sin(theta);
            viewDir.x = cosTheta * sinPhi;
            viewDir.y = cosPhi;
            viewDir.z = sinTheta * sinPhi;
            SingleScatteringResult result = IntegrateScatteredLuminance(viewPos, viewDir, sunDir, 1.0, true, 1.0,
                                                                        20.0, -1.0,
                                                                        true, true);
            LSum += result.L;
        }
    }

    LSum /= count;

    return LSum;
}

half3 RenderSkyViewLut(float2 uv)
{
    float viewHeight;
    half3 upVector;
    float3 viewPosWS;
    TransformToEarthSpace(_CameraPosForAtmosphere, _BottomRadius, viewPosWS, viewHeight, upVector);

    half viewZenithCosAngle;
    half lightViewCosAngle;
    UvToSkyViewLutParams(viewZenithCosAngle, lightViewCosAngle, viewHeight, uv);

    // the Zenith space
    half sunZenithCosAngle = dot(upVector, _SunDirectionForAtmosphere.xyz);
    half3 sunDir = normalize(half3(0.0, sunZenithCosAngle, sqrt(1.0 - sunZenithCosAngle * sunZenithCosAngle)));
    float3 viewPos = float3(0.0, viewHeight, 0.0);
    half viewZenithSinAngle = sqrt(1 - viewZenithCosAngle * viewZenithCosAngle);
    half3 viewDir = half3(
        viewZenithSinAngle * sqrt(1.0 - lightViewCosAngle * lightViewCosAngle),
        viewZenithCosAngle,
        viewZenithSinAngle * lightViewCosAngle);

    // Move to top atmospehre
    if (!MoveToTopAtmosphere(viewPos, viewDir, _TopRadius))
    {
        // Ray is not intersecting the atmosphere
        return 0;
    }

    SingleScatteringResult ss = IntegrateScatteredLuminance(viewPos, viewDir, sunDir, _SunRadianceForAtmosphere,
                                                            false, 1.0, 30.0, -1.0,
                                                            true, true);

    return ss.L;
}

half3 RenderSunDisk(half3 sunDir, half3 viewDir, half3 sunColor, half3 upVector, half viewHeight)
{
    #if _SunDisk_Enable

    half sunSize = _SunSize * _SunSize * 0.1;
    half eyeLightCos = dot(sunDir, viewDir);
    half sunZenithCosAngle = dot(sunDir, upVector);

    // The size of the sun is bigger at noon, is that right?
    // sunSize *= saturate(lerp(1, 0.4, saturate(sunZenithCosAngle)));

    half3 sun;
    #if _SunDisk_LimbDarken
        half range = 1 - saturate((1 - eyeLightCos) / sunSize);
        sun = SunDiskNec96(range, _LimbDarken);
        // half3 sun = SunDiskHM98(range) * (range > 0.01);
    #else
        sun = step(1 - eyeLightCos, sunSize);
    #endif

    #if _SunDisk_Transmittanced
    {
        float2 uv;
        LutTransmittanceParamsToUv(viewHeight, sunZenithCosAngle, uv);
        sun *= SAMPLE_TEXTURE2D_LOD(_TransmittanceLut, sampler_TransmittanceLut, uv, 0).rgb * _SunRadianceForAtmosphere;
    }
    #else
    sun *= sunColor;
    #endif
    sun *= _SunDiskIntensity * SizeScaleIntensity(sunSize);
    sun *= saturate(_SunDiskMax / max(max(sun.r, sun.g), sun.b));
    return sun;
    
    #else // _SunDisk_Enable
    return 0;
    #endif
}

half3 RenderSkyBox(half3 viewDirWS, half3 sunDirWS, half3 sunColor)
{
    float viewHeight;
    half3 upVector;
    float3 viewPosWS;
    TransformToEarthSpace(_CameraPosForAtmosphere, _BottomRadius, viewPosWS, viewHeight, upVector);

    half viewZenithCosAngle = dot(viewDirWS, upVector);

    half3 sideVector = normalize(cross(upVector, viewDirWS)); // assumes non parallel vectors
    half3 forwardVector = normalize(cross(sideVector, upVector));
    // aligns toward the sun light but perpendicular to up vector
    half2 lightOnPlane = half2(dot(sunDirWS, forwardVector), dot(sunDirWS, sideVector));
    lightOnPlane = normalize(lightOnPlane);
    half lightViewCosAngle = lightOnPlane.x;

    bool intersectGround = RaySphereIntersectNearest(viewPosWS, viewDirWS, 0, _BottomRadius) >= 0.0f;

    float2 uv;
    SkyViewLutParamsToUv(intersectGround, viewZenithCosAngle, lightViewCosAngle, viewHeight, uv);

    half3 col = SAMPLE_TEXTURE2D_LOD(_SkyViewLut, sampler_SkyViewLut, uv, 0).rgb;
    if (!intersectGround)
    {
        col += RenderSunDisk(sunDirWS, viewDirWS, sunColor, upVector, viewHeight);
    }
    return col;
}

#define _HasSkyBox 1

half4 AtmosphereRaymarch(float2 uv, float depth, half3 viewDirWS, half3 sunDirWS, half3 sunColor)
{
    float viewHeight;
    half3 upVector;
    float3 viewPosWS;
    TransformToEarthSpace(_CameraPosForAtmosphere, _BottomRadius, viewPosWS, viewHeight, upVector);

    bool farClip = depth == UNITY_RAW_FAR_CLIP_VALUE;
    if (farClip && viewHeight < _TopRadius)
    {
        #if _HasSkyBox
        return half4(0, 0, 0, 1);
        #else
        {
            half3 col = RenderSkyBox(viewDirWS, sunDirWS, sunColor);
            return half4(col, 0);
        }
        #endif
    }

    half3 col = 0;
    if (farClip)
    {
        col += RenderSunDisk(sunDirWS, viewDirWS, sunColor, upVector, viewHeight);
    }

    #if _Aerial_Perspective_Enable
        half3 res = half3(0, 0, 0);
        return half4(res, 1);
    #else
    {
        if (!MoveToTopAtmosphere(viewPosWS, viewDirWS, _TopRadius))
        {
            // Ray is not intersecting the atmosphere		
            return half4(col, 0);
        }

        float linearDepth = LinearEyeDepth(depth, _ZBufferParams) / _DistanceUnitMeter;
        SingleScatteringResult ss = IntegrateScatteredLuminance(viewPosWS, viewDirWS, sunDirWS,
                                                                _SunRadianceForAtmosphere, false, _DensityScale,
                                                                0.0, linearDepth, true,
                                                                true);

        half transmittance = dot(ss.Transmittance, half3(1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0));
        col = ss.L;
        return half4(col, transmittance);
    }
    #endif
}

#endif
