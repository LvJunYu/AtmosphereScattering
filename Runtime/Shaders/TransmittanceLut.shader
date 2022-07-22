Shader "Hidden/Atmosphere/TransmittanceLut"
{
    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline"
        }
        LOD 100
        ZTest Always ZWrite Off Cull Off

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "AtmosphereCore.hlsl"

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

        half4 FragmentTransmittance(Varyings input) : SV_Target
        {
            half3 col = RenderTransmittanceLut(input.uv);
            return half4(col, 1);
        }

        half4 FragmentAmbient(Varyings input) : SV_Target
        {
            half3 col = AtmosphereAmbientLut(input.uv);
            return half4(col, 1);
        }
        ENDHLSL

        Pass
        {
            Name "TransmittanceLut"

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FragmentTransmittance
            ENDHLSL
        }

        Pass
        {
            Name "AmbientLut"

            HLSLPROGRAM
            
            #pragma multi_compile_fragment _ _MultiScattering_Enable

            #pragma vertex Vert
            #pragma fragment FragmentAmbient
            ENDHLSL
        }
    }
}