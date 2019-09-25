Shader "Custom/Lit_TEST"
{
    Properties
    {
        [MainColor] _BaseColor ("Color", Color) = (0.5, 0.5, 0.5, 1)
        [MainTexture] _BaseMap ("Albedo", 2D) = "white" { }
        
        _Cutoff ("Alpha Cutoff", Range(0.0, 1.0)) = 0.5
        
        _Smoothness ("Smoothness", Range(0.0, 1.0)) = 0.5
        
        _Metallic ("Metallic", Range(0.0, 1.0)) = 0.0
        
        [ToggleOff] _SpecularHighlights ("Specular Highlights", Float) = 1.0
        [ToggleOff] _EnvironmentReflections ("Environment Reflections", Float) = 1.0
        
        _BumpScale ("Scale", Float) = 1.0
        _BumpMap ("Normal Map", 2D) = "bump" { }
        
        // Blending state
        [HideInInspector] _Surface ("__surface", Float) = 0.0
        [HideInInspector] _Blend ("__blend", Float) = 0.0
        [HideInInspector] _AlphaClip ("__clip", Float) = 0.0
        [HideInInspector] _SrcBlend ("__src", Float) = 1.0
        [HideInInspector] _DstBlend ("__dst", Float) = 0.0
        [HideInInspector] _ZWrite ("__zw", Float) = 1.0
        [HideInInspector] _Cull ("__cull", Float) = 2.0
        
        // _ReceiveShadows ("Receive Shadows", Float) = 1.0
    }
    
    SubShader
    {
        // Universal Pipeline tag is required. If Universal render pipeline is not set in the graphics settings
        // this Subshader will fail. One can add a subshader below or fallback to Standard built-in to make this
        // material work with both Universal Render Pipeline and Builtin Unity Pipeline
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" "IgnoreProjector" = "True" }
        LOD 300
        
        // ------------------------------------------------------------------
        //  Forward pass. Shades all light in a single pass. GI + emission + Fog
        Pass
        {
            // Lightmode matches the ShaderPassName set in UniversalRenderPipeline.cs. SRPDefaultUnlit and passes with
            // no LightMode tag are also rendered by Universal Render Pipeline
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }
            
            Blend[_SrcBlend][_DstBlend]
            ZWrite[_ZWrite]
            Cull[_Cull]
            
            HLSLPROGRAM
            
            // Required to compile gles 2.0 with standard SRP library
            // All shaders must be compiled with HLSLcc and currently only gles is not using HLSLcc by default
            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x
            #pragma target 2.0
            
            // -------------------------------------
            // Material Keywords
            #pragma shader_feature _NORMALMAP
            #pragma shader_feature _ALPHATEST_ON
            // #pragma shader_feature _ALPHAPREMULTIPLY_ON
            // #pragma shader_feature _EMISSION
            // #pragma shader_feature _METALLICSPECGLOSSMAP
            // #pragma shader_feature _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
            // #pragma shader_feature _OCCLUSIONMAP
            
            // #pragma shader_feature _SPECULARHIGHLIGHTS_OFF
            // #pragma shader_feature _ENVIRONMENTREFLECTIONS_OFF
            // #pragma shader_feature _SPECULAR_SETUP
            // #pragma shader_feature _RECEIVE_SHADOWS_OFF
            
            // -------------------------------------
            // Universal Pipeline keywords
            // #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            // #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            // #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            // #pragma multi_compile _ _SHADOWS_SOFT
            // #pragma multi_compile _ _MIXED_LIGHTING_SUBTRACTIVE
            
            // -------------------------------------
            // Unity defined keywords
            #pragma multi_compile _ DIRLIGHTMAP_COMBINED
            #pragma multi_compile _ LIGHTMAP_ON
            #pragma multi_compile_fog
            
            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing
            
            #pragma vertex LitPassVertex
            #pragma fragment LitPassFragment
            
            // #include "LitInput.hlsl"
            // #include "LitForwardPass.hlsl"
            
            // #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            // #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/SurfaceInput.hlsl"
            // #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            
            CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4 _BaseColor;
            half _Cutoff;
            half _Smoothness;
            half _Metallic;
            half _BumpScale;
            CBUFFER_END
            
            
            struct Attributes
            {
                float4 positionOS: POSITION;
                float3 normalOS: NORMAL;
                float4 tangentOS: TANGENT;
                float2 texcoord: TEXCOORD0;
                float2 lightmapUV: TEXCOORD1;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            
            struct Varyings
            {
                float2 uv: TEXCOORD0;
                DECLARE_LIGHTMAP_OR_SH(lightmapUV, vertexSH, 1);
                
                #ifdef _ADDITIONAL_LIGHTS
                    float3 positionWS: TEXCOORD2;
                #endif
                
                #ifdef _NORMALMAP
                    float4 normalWS: TEXCOORD3;    // xyz: normal, w: viewDir.x
                    float4 tangentWS: TEXCOORD4;    // xyz: tangent, w: viewDir.y
                    float4 bitangentWS: TEXCOORD5;    // xyz: bitangent, w: viewDir.z
                #else
                    float3 normalWS: TEXCOORD3;
                    float3 viewDirWS: TEXCOORD4;
                #endif
                
                half4 fogFactorAndVertexLight: TEXCOORD6; // x: fogFactor, yzw: vertex light
                
                #ifdef _MAIN_LIGHT_SHADOWS
                    float4 shadowCoord: TEXCOORD7;
                #endif
                
                float4 positionCS: SV_POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            
            
            void InitializeStandardLitSurfaceData(float2 uv, out SurfaceData outSurfaceData)
            {
                half4 albedoAlpha = SampleAlbedoAlpha(uv, TEXTURE2D_ARGS(_BaseMap, sampler_BaseMap));
                outSurfaceData.alpha = Alpha(albedoAlpha.a, _BaseColor, _Cutoff);
                outSurfaceData.albedo = albedoAlpha.rgb * _BaseColor.rgb;
                outSurfaceData.metallic = _Metallic;
                outSurfaceData.smoothness = _Smoothness;
                outSurfaceData.normalTS = SampleNormal(uv, TEXTURE2D_ARGS(_BumpMap, sampler_BumpMap), _BumpScale);
                outSurfaceData.occlusion = 1;
                outSurfaceData.emission = 0;
            }
            
            
            void InitializeInputData(Varyings input, half3 normalTS, out InputData inputData)
            {
                inputData = (InputData)0;
                
                #ifdef _ADDITIONAL_LIGHTS
                    inputData.positionWS = input.positionWS;
                #endif
                
                #ifdef _NORMALMAP
                    half3 viewDirWS = half3(input.normalWS.w, input.tangentWS.w, input.bitangentWS.w);
                    inputData.normalWS = TransformTangentToWorld(normalTS,
                    half3x3(input.tangentWS.xyz, input.bitangentWS.xyz, input.normalWS.xyz));
                #else
                    half3 viewDirWS = input.viewDirWS;
                    inputData.normalWS = input.normalWS;
                #endif
                
                inputData.normalWS = NormalizeNormalPerPixel(inputData.normalWS);
                viewDirWS = SafeNormalize(viewDirWS);
                
                inputData.viewDirectionWS = viewDirWS;
                #if defined(_MAIN_LIGHT_SHADOWS) && !defined(_RECEIVE_SHADOWS_OFF)
                    inputData.shadowCoord = input.shadowCoord;
                #else
                    inputData.shadowCoord = float4(0, 0, 0, 0);
                #endif
                inputData.fogCoord = input.fogFactorAndVertexLight.x;
                inputData.vertexLighting = input.fogFactorAndVertexLight.yzw;
                inputData.bakedGI = SAMPLE_GI(input.lightmapUV, input.vertexSH, inputData.normalWS);
            }
            
            half OneMinusReflectivityMetallic(half metallic)
            {
                half oneMinusDielectricSpec = kDieletricSpec.a;
                return oneMinusDielectricSpec - metallic * oneMinusDielectricSpec;
            }
            
            inline void InitializeBRDFData(half3 albedo, half metallic, half3 specular, half smoothness, half alpha, out BRDFData outBRDFData)
            {
                half oneMinusReflectivity = OneMinusReflectivityMetallic(metallic);
                half reflectivity = 1.0 - oneMinusReflectivity;
                outBRDFData.diffuse = albedo * oneMinusReflectivity;
                outBRDFData.specular = lerp(kDieletricSpec.rgb, albedo, metallic);
                
                outBRDFData.grazingTerm = saturate(smoothness + reflectivity);
                outBRDFData.perceptualRoughness = PerceptualSmoothnessToPerceptualRoughness(smoothness);
                outBRDFData.roughness = max(PerceptualRoughnessToRoughness(outBRDFData.perceptualRoughness), HALF_MIN);
                outBRDFData.roughness2 = outBRDFData.roughness * outBRDFData.roughness;
                
                outBRDFData.normalizationTerm = outBRDFData.roughness * 4.0h + 2.0h;
                outBRDFData.roughness2MinusOne = outBRDFData.roughness2 - 1.0h;
                
                #ifdef _ALPHAPREMULTIPLY_ON
                    outBRDFData.diffuse *= alpha;
                    alpha = alpha * oneMinusReflectivity + reflectivity;
                #endif
            }
            
            Light GetMainLight()
            {
                Light light;
                light.direction = _MainLightPosition.xyz;
                light.distanceAttenuation = unity_LightData.z;
                #if defined(LIGHTMAP_ON) || defined(_MIXED_LIGHTING_SUBTRACTIVE)
                    light.distanceAttenuation *= unity_ProbesOcclusion.x;
                #endif
                light.shadowAttenuation = 1.0;
                light.color = _MainLightColor.rgb;
                return light;
            }
            
            Light GetMainLight(float4 shadowCoord)
            {
                Light light = GetMainLight();
                light.shadowAttenuation = MainLightRealtimeShadow(shadowCoord);
                return light;
            }
            
            half3 GlossyEnvironmentReflection(half3 reflectVector, half perceptualRoughness, half occlusion)
            {
                #if !defined(_ENVIRONMENTREFLECTIONS_OFF)
                    half mip = PerceptualRoughnessToMipmapLevel(perceptualRoughness);
                    half4 encodedIrradiance = SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, reflectVector, mip);
                    
                    #if !defined(UNITY_USE_NATIVE_HDR)
                        half3 irradiance = DecodeHDREnvironment(encodedIrradiance, unity_SpecCube0_HDR);
                    #else
                        half3 irradiance = encodedIrradiance.rbg;
                    #endif
                    
                    return irradiance * occlusion;
                #endif // GLOSSY_REFLECTIONS
                
                return _GlossyEnvironmentColor.rgb * occlusion;
            }
            
            half3 GlobalIllumination(BRDFData brdfData, half3 bakedGI, half occlusion, half3 normalWS, half3 viewDirectionWS)
            {
                half3 reflectVector = reflect(-viewDirectionWS, normalWS);
                half fresnelTerm = Pow4(1.0 - saturate(dot(normalWS, viewDirectionWS)));
                
                half3 indirectDiffuse = bakedGI * occlusion;
                half3 indirectSpecular = GlossyEnvironmentReflection(reflectVector, brdfData.perceptualRoughness, occlusion);
                
                return EnvironmentBRDF(brdfData, indirectDiffuse, indirectSpecular, fresnelTerm);
            }
            
            half3 EnvironmentBRDF(BRDFData brdfData, half3 indirectDiffuse, half3 indirectSpecular, half fresnelTerm)
            {
                half3 c = indirectDiffuse * brdfData.diffuse;
                float surfaceReduction = 1.0 / (brdfData.roughness2 + 1.0);
                c += surfaceReduction * indirectSpecular * lerp(brdfData.specular, brdfData.grazingTerm, fresnelTerm);
                return c;
            }
            
            half4 UniversalFragmentPBR(InputData inputData, half3 albedo, half metallic, half3 specular,
            half smoothness, half occlusion, half3 emission, half alpha)
            {
                BRDFData brdfData;
                InitializeBRDFData(albedo, metallic, specular, smoothness, alpha, brdfData);
                
                Light mainLight = GetMainLight(inputData.shadowCoord);
                
                half3 color = GlobalIllumination(brdfData, inputData.bakedGI, occlusion, inputData.normalWS, inputData.viewDirectionWS);
                color += LightingPhysicallyBased(brdfData, mainLight, inputData.normalWS, inputData.viewDirectionWS);
                
                #ifdef _ADDITIONAL_LIGHTS
                    uint pixelLightCount = GetAdditionalLightsCount();
                    for (uint lightIndex = 0u; lightIndex < pixelLightCount; ++ lightIndex)
                    {
                        Light light = GetAdditionalLight(lightIndex, inputData.positionWS);
                        color += LightingPhysicallyBased(brdfData, light, inputData.normalWS, inputData.viewDirectionWS);
                    }
                #endif
                
                #ifdef _ADDITIONAL_LIGHTS_VERTEX
                    color += inputData.vertexLighting * brdfData.diffuse;
                #endif
                
                color += emission;
                return half4(color, alpha);
            }
            
            ///////////////////////////////////////////////////////////////////////////////
            //                  Vertex and Fragment functions                            //
            ///////////////////////////////////////////////////////////////////////////////
            
            // Used in Standard (Physically Based) shader
            Varyings LitPassVertex(Attributes input)
            {
                Varyings output = (Varyings)0;
                
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
                
                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);
                half3 viewDirWS = GetCameraPositionWS() - vertexInput.positionWS;
                half3 vertexLight = VertexLighting(vertexInput.positionWS, normalInput.normalWS);
                half fogFactor = ComputeFogFactor(vertexInput.positionCS.z);
                
                output.uv = TRANSFORM_TEX(input.texcoord, _BaseMap);
                
                #ifdef _NORMALMAP
                    output.normalWS = half4(normalInput.normalWS, viewDirWS.x);
                    output.tangentWS = half4(normalInput.tangentWS, viewDirWS.y);
                    output.bitangentWS = half4(normalInput.bitangentWS, viewDirWS.z);
                #else
                    output.normalWS = NormalizeNormalPerVertex(normalInput.normalWS);
                    output.viewDirWS = viewDirWS;
                #endif
                
                OUTPUT_LIGHTMAP_UV(input.lightmapUV, unity_LightmapST, output.lightmapUV);
                OUTPUT_SH(output.normalWS.xyz, output.vertexSH);
                
                output.fogFactorAndVertexLight = half4(fogFactor, vertexLight);
                
                #ifdef _ADDITIONAL_LIGHTS
                    output.positionWS = vertexInput.positionWS;
                #endif
                
                #if defined(_MAIN_LIGHT_SHADOWS) && !defined(_RECEIVE_SHADOWS_OFF)
                    output.shadowCoord = GetShadowCoord(vertexInput);
                #endif
                
                output.positionCS = vertexInput.positionCS;
                
                return output;
            }
            
            // Used in Standard (Physically Based) shader
            half4 LitPassFragment(Varyings input): SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);
                
                SurfaceData surfaceData;
                InitializeStandardLitSurfaceData(input.uv, surfaceData);
                
                InputData inputData;
                InitializeInputData(input, surfaceData.normalTS, inputData);
                
                half4 color = UniversalFragmentPBR(inputData, surfaceData.albedo, surfaceData.metallic, surfaceData.specular, surfaceData.smoothness, surfaceData.occlusion, surfaceData.emission, surfaceData.alpha);
                
                color.rgb = MixFog(color.rgb, inputData.fogCoord);
                return color;
            }
            
            ENDHLSL
            
        }
    }
    FallBack "Hidden/InternalErrorShader"
    CustomEditor "UnityEditor.Rendering.Universal.ShaderGUI.LitShader"
}
