#ifndef ATMOSPHERE_COMMON_INCLUDED
#define ATMOSPHERE_COMMON_INCLUDED

half _RayleighDensityExpScale;
half3 _RayleighScattering;

half _MieDensityExpScale;
half3 _MieScattering;
half3 _MieAbsorption;

half _MiePhaseG;

half3 _OzoneAbsorptionExtinction;

float _BottomRadius;
float _TopRadius;

half3 _GroundAlbedo;

float3 _CameraPosForAtmosphere;
half3 _SunRadianceForAtmosphere;
half3 _SunDirectionForAtmosphere;

uint _MultiScatteringLutRes;
uint _AmbientLutRes;
half4 _AtmosphereLutParams;

#define _TransmittanceLutResolution _AtmosphereLutParams.xy
#define _SkyViewLutResolution _AtmosphereLutParams.zw

half4 _SunDiskParams;

#define _SunSize _SunDiskParams.x
#define _SunDiskIntensity _SunDiskParams.y
#define _SunDiskMax _SunDiskParams.z
#define _LimbDarken _SunDiskParams.w

half4 _AtmosphereRaymarchParams;
#define _RayMarchMinMaxSPP _AtmosphereRaymarchParams.xy

half _DensityScale;

#define _DistanceUnitMeter 1000.0

#define _OzoneAbsorptionDensity0LayerWidth 25000.0 / _DistanceUnitMeter
#define _OzoneAbsorptionDensity0ConstantTerm -2.0 / 3.0
#define _OzoneAbsorptionDensity0LinearTerm 1.0 / (15000.0 / _DistanceUnitMeter)
#define _OzoneAbsorptionDensity1ConstantTerm 8.0 / 3.0
#define _OzoneAbsorptionDensity1LinearTerm -1.0 / (15000.0 / _DistanceUnitMeter)

#define _PLANET_RADIUS_OFFSET 10.0 / _DistanceUnitMeter

#ifndef PI
#define PI 3.14159265359
#endif

TEXTURE2D(_TransmittanceLut);
SAMPLER(sampler_TransmittanceLut);

TEXTURE2D(_SkyViewLut);
SAMPLER(sampler_SkyViewLut);

struct MediumSampleRGB
{
    half3 scattering;
    half3 absorption;
    half3 extinction;

    half3 scatteringMie;
    half3 absorptionMie;
    half3 extinctionMie;

    half3 scatteringRay;
    half3 absorptionRay;
    half3 extinctionRay;

    half3 scatteringOzo;
    half3 absorptionOzo;
    half3 extinctionOzo;

    half3 albedo;
};

// - r0: ray origin
// - rd: normalized ray direction
// - s0: sphere center
// - sR: sphere radius
// - Returns distance from r0 to first intersecion with sphere,
//   or -1.0 if no intersection.
float RaySphereIntersectNearest(float3 r0, float3 rd, float3 s0, float sR)
{
    float a = dot(rd, rd);
    float3 s0_r0 = r0 - s0;
    float b = 2.0 * dot(rd, s0_r0);
    float c = dot(s0_r0, s0_r0) - (sR * sR);
    float delta = b * b - 4.0 * a * c;
    if (delta < 0.0 || a == 0.0)
    {
        return -1.0;
    }
    float sol0 = (-b - sqrt(delta)) / (2.0 * a);
    float sol1 = (-b + sqrt(delta)) / (2.0 * a);
    if (sol0 < 0.0 && sol1 < 0.0)
    {
        return -1.0;
    }
    if (sol0 < 0.0)
    {
        return max(0.0, sol1);
    }
    else if (sol1 < 0.0)
    {
        return max(0.0, sol0);
    }
    return max(0.0, min(sol0, sol1));
}

bool MoveToTopAtmosphere(inout float3 viewPos, in half3 viewDir, in float atmosphereTopRadius)
{
    float viewHeight = length(viewPos);
    if (viewHeight > atmosphereTopRadius)
    {
        float tTop = RaySphereIntersectNearest(viewPos, viewDir, float3(0.0f, 0.0f, 0.0f), atmosphereTopRadius);
        if (tTop >= 0.0f)
        {
            float3 UpVector = viewPos / viewHeight;
            float3 UpOffset = UpVector * -_PLANET_RADIUS_OFFSET;
            viewPos = viewPos + viewDir * tTop + UpOffset;
        }
        else
        {
            // Ray is not intersecting the atmosphere
            return false;
        }
    }
    return true; // ok to start tracing
}

half RayleighPhase(half cosTheta)
{
    half factor = 3.0f / (16.0f * PI);
    return factor * (1.0f + cosTheta * cosTheta);
}

half CornetteShanksMiePhaseFunction(half g, half cosTheta)
{
    half k = 3.0 / (8.0 * PI) * (1.0 - g * g) / (2.0 + g * g);
    half denom = 1.0f + g * g + 2.0f * g * cosTheta;
    return k * (1.0 + cosTheta * cosTheta) / (denom * sqrt(denom));
}

#define _USE_CornetteShanks

half HgPhase(half g, half cosTheta)
{
    #ifdef _USE_CornetteShanks
    return CornetteShanksMiePhaseFunction(g, cosTheta);
    #else
        // Reference implementation (i.e. not schlick approximation). 
        // See http://www.pbr-book.org/3ed-2018/Volume_Scattering/Phase_Functions.html
        half numer = 1.0f - g * g;
        half denom = 1.0f + g * g + 2.0f * g * cosTheta;
        return numer / (4.0f * PI * denom * sqrt(denom));
    #endif
}

half GetAlbedo(half scattering, half extinction)
{
    return scattering / max(0.001, extinction);
}

half3 GetAlbedo(half3 scattering, half3 extinction)
{
    return scattering / max(0.001, extinction);
}

// EarthSpace is used to calculate, the original point is the center of the earth, and the unit is kilometer.
void TransformToEarthSpace(float3 cameraPos, float earthRadius, out float3 viewPos, out float viewHeight,
                           out half3 upVector)
{
    viewPos = cameraPos;
    viewPos.y = max(1, viewPos.y); // the position is relative to the earth, so should not under the earth.
    viewPos /= _DistanceUnitMeter; // change unit to kilometer
    viewPos.y += earthRadius; // based on the flat ground
    viewHeight = length(viewPos);

    // #if _FixedViewPosition
    //     viewPos *= viewPos.y / viewHeight;
    //     viewHeight = viewPos.y;
    // #endif

    // upVector = viewPos / viewHeight;
    upVector = normalize(viewPos);
}

MediumSampleRGB SampleMediumRGB(in float3 WorldPos)
{
    const float viewHeight = length(WorldPos) - _BottomRadius;

    const half densityMie = exp(_MieDensityExpScale * viewHeight);
    const half densityRay = exp(_RayleighDensityExpScale * viewHeight);
    const half densityOzo = saturate(viewHeight < _OzoneAbsorptionDensity0LayerWidth
                                          ? _OzoneAbsorptionDensity0LinearTerm * viewHeight +
                                          _OzoneAbsorptionDensity0ConstantTerm
                                          : _OzoneAbsorptionDensity1LinearTerm * viewHeight +
                                          _OzoneAbsorptionDensity1ConstantTerm);

    MediumSampleRGB s;

    s.scatteringMie = densityMie * _MieScattering;
    s.absorptionMie = densityMie * _MieAbsorption;
    s.extinctionMie = s.scatteringMie + s.absorptionMie;

    s.scatteringRay = densityRay * _RayleighScattering;
    s.absorptionRay = 0.0f;
    s.extinctionRay = s.scatteringRay + s.absorptionRay;

    s.scatteringOzo = 0.0;
    s.absorptionOzo = densityOzo * _OzoneAbsorptionExtinction;
    s.extinctionOzo = s.scatteringOzo + s.absorptionOzo;

    s.scattering = s.scatteringMie + s.scatteringRay + s.scatteringOzo;
    s.absorption = s.absorptionMie + s.absorptionRay + s.absorptionOzo;
    s.extinction = s.extinctionMie + s.extinctionRay + s.extinctionOzo;
    s.albedo = GetAlbedo(s.scattering, s.extinction);

    return s;
}

// https://ebruneton.github.io/precomputed_atmospheric_scattering/atmosphere/functions.glsl.html#transmittance_precomputation
// We should precompute those terms from resolutions (Or set resolution as #defined constants)
float EncodeRange01ToUv(float u, float resolution)
{
    return (u + 0.5f / resolution) * (resolution / (resolution + 1.0f));
}

float2 EncodeRange01ToUv(float2 uv, float2 resolution)
{
    return (uv + 0.5f / resolution) * (resolution / (resolution + 1.0f));
}

float DecodeUvToRange01(float u, float resolution)
{
    return (u - 0.5f / resolution) * (resolution / (resolution - 1.0f));
}

float2 DecodeUvToRange01(float2 uv, float2 resolution)
{
    return (uv - 0.5f / resolution) * (resolution / (resolution - 1.0f));
}


void UvToLutTransmittanceParams(out float viewHeight, out half viewZenithCosAngle, in float2 uv)
{
    // uv.x = DecodeUvToRange01(uv.x, TransmittanceLutResolution.x);
    float mu = uv.x;
    float r = uv.y;

    float H = sqrt(_TopRadius * _TopRadius - _BottomRadius * _BottomRadius);
    float rho = H * r;
    viewHeight = sqrt(rho * rho + _BottomRadius * _BottomRadius);

    float dmin = _TopRadius - viewHeight;
    float dmax = rho + H;
    float d = dmin + mu * (dmax - dmin);
    viewZenithCosAngle = d == 0.0 ? 1.0 : (H * H - rho * rho - d * d) / (2.0 * viewHeight * d);
    viewZenithCosAngle = clamp(viewZenithCosAngle, -1.0, 1.0);
}

void LutTransmittanceParamsToUv(in float viewHeight, in float viewZenithCosAngle, out float2 uv)
{
    float H = sqrt(max(0.0f, _TopRadius * _TopRadius - _BottomRadius * _BottomRadius));
    float rho = sqrt(max(0.0f, viewHeight * viewHeight - _BottomRadius * _BottomRadius));

    float discriminant = viewHeight * viewHeight * (viewZenithCosAngle * viewZenithCosAngle - 1.0) +
        _TopRadius * _TopRadius;
    float d = max(0.0, (-viewHeight * viewZenithCosAngle + sqrt(discriminant))); // Distance to atmosphere boundary

    float dmin = _TopRadius - viewHeight;
    float dmax = rho + H;
    float mu = (d - dmin) / (dmax - dmin);
    float r = rho / H;

    uv = float2(mu, r);
    // uv.x = EncodeRange01ToUv(uv.x, TransmittanceLutResolution.x);
}

#define NONLINEARSKYVIEWLUT 1

void UvToSkyViewLutParams(out half viewZenithCosAngle, out half lightViewCosAngle, in float viewHeight, in float2 uv)
{
    // Constrain uvs to valid sub texel range (avoid zenith derivative issue making LUT usage visible)
    uv = DecodeUvToRange01(uv, _SkyViewLutResolution);

    float Vhorizon = sqrt(viewHeight * viewHeight - _BottomRadius * _BottomRadius);
    float CosBeta = Vhorizon / viewHeight; // GroundToHorizonCos
    float Beta = acos(CosBeta);
    float ZenithHorizonAngle = PI - Beta;

    if (uv.y < 0.5f)
    {
        float coord = 2.0 * uv.y;
        coord = 1.0 - coord;
        #if NONLINEARSKYVIEWLUT
        coord *= coord;
        #endif
        coord = 1.0 - coord;
        viewZenithCosAngle = cos(ZenithHorizonAngle * coord);
    }
    else
    {
        float coord = uv.y * 2.0 - 1.0;
        #if NONLINEARSKYVIEWLUT
        coord *= coord;
        #endif
        viewZenithCosAngle = cos(ZenithHorizonAngle + Beta * coord);
    }

    float coord = uv.x;
    coord *= coord;
    lightViewCosAngle = -(coord * 2.0 - 1.0);
}

void SkyViewLutParamsToUv(bool IntersectGround, in half viewZenithCosAngle, in half lightViewCosAngle,
                          in float viewHeight, out float2 uv)
{
    float Vhorizon = sqrt(viewHeight * viewHeight - _BottomRadius * _BottomRadius);
    float CosBeta = Vhorizon / viewHeight; // GroundToHorizonCos
    float Beta = acos(CosBeta);
    float ZenithHorizonAngle = PI - Beta;

    if (!IntersectGround)
    {
        float coord = acos(viewZenithCosAngle) / ZenithHorizonAngle;
        coord = 1.0 - coord;
        #if NONLINEARSKYVIEWLUT
        coord = sqrt(coord);
        #endif
        coord = 1.0 - coord;
        uv.y = coord * 0.5f;
    }
    else
    {
        float coord = (acos(viewZenithCosAngle) - ZenithHorizonAngle) / Beta;
        #if NONLINEARSKYVIEWLUT
        coord = sqrt(coord);
        #endif
        uv.y = coord * 0.5f + 0.5f;
    }

    {
        float coord = -lightViewCosAngle * 0.5f + 0.5f;
        coord = sqrt(coord);
        uv.x = coord;
    }

    // Constrain uvs to valid sub texel range (avoid zenith derivative issue making LUT usage visible)
    uv = EncodeRange01ToUv(uv, _SkyViewLutResolution);
}

TEXTURE2D(_MultiScatterLut);
SAMPLER(sampler_MultiScatterLut);

half3 GetMultipleScattering(float viewHeight, float viewZenithCosAngle)
{
    float2 uv = saturate(float2(viewZenithCosAngle * 0.5f + 0.5f,
                                (viewHeight - _BottomRadius) / (_TopRadius - _BottomRadius)));
    uv = EncodeRange01ToUv(uv, _MultiScatteringLutRes);

    return SAMPLE_TEXTURE2D_LOD(_MultiScatterLut, sampler_MultiScatterLut, uv, 0).rgb;
}

#define MIE_G (-0.990)
#define MIE_G2 0.9801

half GetMiePhase(half eyeCos, half eyeCos2, half sunSize)
{
    half temp = 1.0 + MIE_G2 - 2.0 * MIE_G * eyeCos;
    temp = pow(temp, sunSize * 10);
    temp = max(temp, 1.0e-4); // prevent division by zero, esp. in half precision
    temp = 1.5 * ((1.0 - MIE_G2) / (2.0 + MIE_G2)) * (1.0 + eyeCos2) / temp;
    return temp;
}

// copy from unity skybox shader "Skybox/Procedural"
half CalcSunAttenuation(half3 lightDir, half3 viewDir, half sunSize, half sunSizeConvergence)
{
    half focusedEyeCos = pow(saturate(dot(lightDir, viewDir)), sunSizeConvergence);
    return GetMiePhase(-focusedEyeCos, focusedEyeCos * focusedEyeCos, sunSize);
}

// https://media.contentapi.ea.com/content/dam/eacom/frostbite/files/s2016-pbs-frostbite-sky-clouds-new.pdf
half3 SunDiskNec96(half centerToEdge, half darken)
{
    // Model from http://www.physics.hmc.edu/faculty/esin/a101/limbdarkening.pdf
    half3 u = half3(1.0, 1.0, 1.0); // some models have u!=1
    half3 a = half3(0.397, 0.503, 0.652) * darken; // coefficient for RGB wavelength (680 ,550 ,440)

    centerToEdge = 1.0 - centerToEdge;
    half mu = sqrt(1.0 - centerToEdge * centerToEdge);

    half3 factor = 1.0 - u * (1.0 - pow(mu, a));
    return factor;
}

half3 SunDiskHM98(half centerToEdge)
{
    // Model using P5 polynomial from http://articles.adsabs.harvard.edu/cgi-bin/nph-iarticle_query?1994SoPh..153...91N&defaultprint=YES&filetype=.pdf
    centerToEdge = 1.0 - centerToEdge;
    half mu = sqrt(1.0 - centerToEdge * centerToEdge);

    // coefficient for RGB wavelength (680 ,550 ,440)
    half3 a0 = half3(0.34685, 0.26073, 0.15248);
    half3 a1 = half3(1.37539, 1.27428, 1.38517);
    half3 a2 = half3(-2.04425, -1.30352, -1.49615);
    half3 a3 = half3(2.70493, 1.47085, 1.99886);
    half3 a4 = half3(-1.94290, -0.96618, -1.48155);
    half3 a5 = half3(0.55999, 0.26384, 0.44119);

    half mu2 = mu * mu;
    half mu3 = mu2 * mu;
    half mu4 = mu2 * mu2;
    half mu5 = mu4 * mu;

    half3 factor = a0 + a1 * mu + a2 * mu2 + a3 * mu3 + a4 * mu4 + a5 * mu5;
    return factor;
}

half SizeScaleIntensity(half size)
{
    // https://media.contentapi.ea.com/content/dam/eacom/frostbite/files/s2016-pbs-frostbite-sky-clouds-new.pdf
    // L = E / w
    // w = 2 * PI * (1 − eyeLightCos) = 2 * PI * sunSize
    return 1.0 / (2.0 * PI * size);
}

#endif
