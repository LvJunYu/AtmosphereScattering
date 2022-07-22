Shader "Atmosphere/SkyBox"
{
    Properties
    {
//        [Toggle(_SunDisk_Enable)] _SunDisk ("Sun", Int) = 1
//        _SunSize ("Sun Size", Range(0.01,1)) = 0.1
//        _SunDiskIntensity ("Sun Disk Brightness", Range(0,1)) = 0.1
//        _SunDiskMax ("Sun Brightness Max", Float) = 100
//        [Toggle(_SunDisk_LimbDarken)] _SunDisk_LimbDarken ("Sun Limb Darken", Int) = 1
//        _LimbDarken ("Sun Limb Darken Intensity", Range(1, 10)) = 2
//        [Toggle(_SunDisk_Transmittanced)] _SunDiskTransmittanced ("Sun Transmittanced Per Pixel", Int) = 0

        [HideInInspector] _AtmosphereThickness ("Atmosphere Thickness", Range(0,5)) = 1.0
        [HideInInspector] _Exposure("Exposure", Range(0, 8)) = 1.3
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline" "RenderType" = "Background"
        }
        LOD 100

        Pass
        {
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Fragment

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "AtmosphereCore.hlsl"

            #pragma multi_compile_fragment _ _SunDisk_Enable
            #pragma multi_compile_fragment _ _SunDisk_LimbDarken
            #pragma multi_compile_fragment _ _SunDisk_Transmittanced

            half _Exposure;
            half _AtmosphereThickness;

            struct Attributes
            {
                float4 positionOS : POSITION;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
            };

            Varyings Vert(Attributes input)
            {
                Varyings output;
                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
                output.positionCS = vertexInput.positionCS;
                output.positionWS = vertexInput.positionWS;
                return output;
            }

            half4 Fragment(Varyings input) : SV_Target
            {
                Light light = GetMainLight();
                half3 viewDir = normalize(input.positionWS);
                half3 col = RenderSkyBox(viewDir, light.direction, light.color);
                return half4(col, 1);
            }
            ENDHLSL
        }
    }
}