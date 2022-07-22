Shader "Hidden/Atmosphere/AtmosphereRaymarch"
{
    SubShader
    {
        Tags
        {
            "RenderType"="Opaque" "RenderPipeline" = "UniversalPipeline"
        }
        LOD 100

        Pass
        {
            ZTest Always
            ZWrite Off
            Cull Off
            Blend One SrcAlpha, Zero SrcAlpha

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Fragment

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "AtmosphereCore.hlsl"
            
            #pragma multi_compile_fragment _ _SunDisk_Enable
            #pragma multi_compile_fragment _ _SunDisk_LimbDarken
            #pragma multi_compile_fragment _ _SunDisk_Transmittanced
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _MultiScattering_Enable
            #pragma multi_compile_fragment _ _ShadowMap_Enable

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            Varyings Vert(Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.uv = input.uv;
                return output;
            }

            half4 Fragment(Varyings input) : SV_Target
            {
                float depth = SampleSceneDepth(input.uv);
                #if UNITY_REVERSED_Z
                float deviceDepth = depth;
                #else
                    float deviceDepth = deviceDepth * 2.0 - 1.0;
                #endif

                float3 wpos = ComputeWorldSpacePosition(input.uv.xy, deviceDepth, unity_MatrixInvVP);
                half3 viewDirs = normalize(wpos - GetCameraPositionWS());
                Light light = GetMainLight();
                half4 res = AtmosphereRaymarch(input.uv, depth, viewDirs, light.direction, light.color);
                return res;
            }
            ENDHLSL
        }
    }
}