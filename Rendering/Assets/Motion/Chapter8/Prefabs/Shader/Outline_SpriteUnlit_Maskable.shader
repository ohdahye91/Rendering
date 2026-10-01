Shader "Shader Graphs/Outline_SpriteUnlit_Maskable"
{
    Properties
    {
        [NoScaleOffset]_MainTex("MainTex", 2D) = "white" {}
        _Speed("Speed", Float) = 1
        [HDR]_Emission("Emission", Color) = (1, 1, 1, 1)
        [ToggleUI]_TwoHeads("TwoHeads", Float) = 0
        [HideInInspector]White("Color", Color) = (1, 1, 1, 1)
        [HideInInspector][NoScaleOffset]unity_Lightmaps("unity_Lightmaps", 2DArray) = "" {}
        [HideInInspector][NoScaleOffset]unity_LightmapsInd("unity_LightmapsInd", 2DArray) = "" {}
        [HideInInspector][NoScaleOffset]unity_ShadowMasks("unity_ShadowMasks", 2DArray) = "" {}
        _StencilComp ("Stencil Comparison", Float) = 8
        _Stencil ("Stencil ID", Float) = 0
        _StencilOp ("Stencil Operation", Float) = 0
        _StencilWriteMask ("Stencil Write Mask", Float) = 255
        _StencilReadMask ("Stencil Read Mask", Float) = 255
        _ColorMask ("Color Mask", Float) = 15
    }
    SubShader
    {
        Tags
        {
            "RenderPipeline"="UniversalPipeline"
            "RenderType"="Transparent"
            "UniversalMaterialType" = "Unlit"
            "Queue"="Transparent"
            // DisableBatching: <None>
            "ShaderGraphShader"="true"
            "ShaderGraphTargetId"="UniversalSpriteUnlitSubTarget"
        }

        Stencil
        {
            Ref [_Stencil]
            Comp [_StencilComp]
            Pass [_StencilOp]
            ReadMask [_StencilReadMask]
            WriteMask [_StencilWriteMask]
        }
        ColorMask [_ColorMask]

        Pass
        {
            Name "Sprite Unlit"
            Tags
            {
                "LightMode" = "SRPDefaultUnlit"
            }
        
        // Render State
        Cull Off
        Blend SrcAlpha One, One One
        ZTest [unity_GUIZTestMode]
        ZWrite Off
        
        
        // Debug
        // <None>
        
        // --------------------------------------------------
        // Pass
        
        HLSLPROGRAM
        
        // Pragmas
        #pragma target 2.0
        #pragma exclude_renderers d3d11_9x
        #pragma multi_compile_instancing
        #pragma vertex vert
        #pragma fragment frag
        
        // Keywords
        #pragma multi_compile_fragment _ DEBUG_DISPLAY
        #pragma multi_compile_vertex _ SKINNED_SPRITE
        // GraphKeywords: <None>
        
        // Defines
        
        #define ATTRIBUTES_NEED_NORMAL
        #define ATTRIBUTES_NEED_TANGENT
        #define ATTRIBUTES_NEED_TEXCOORD0
        #define ATTRIBUTES_NEED_COLOR
        #define FEATURES_GRAPH_VERTEX_NORMAL_OUTPUT
        #define FEATURES_GRAPH_VERTEX_TANGENT_OUTPUT
        #define VARYINGS_NEED_POSITION_WS
        #define VARYINGS_NEED_NORMAL_WS
        #define VARYINGS_NEED_TEXCOORD0
        #define VARYINGS_NEED_COLOR
        #define FEATURES_GRAPH_VERTEX
        /* WARNING: $splice Could not find named fragment 'PassInstancing' */
        #define SHADERPASS SHADERPASS_SPRITEUNLIT
        
        
        // custom interpolator pre-include
        /* WARNING: $splice Could not find named fragment 'sgci_CustomInterpolatorPreInclude' */
        
        // Includes
        #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Fog.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Texture.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include_with_pragmas "Packages/com.unity.render-pipelines.core/ShaderLibrary/FoveatedRenderingKeywords.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/FoveatedRendering.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Input.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/TextureStack.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/DebugMipmapStreamingMacros.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/ShaderGraphFunctions.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/Shaders/2D/Include/Core2D.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/Editor/ShaderGraph/Includes/ShaderPass.hlsl"
        
        // --------------------------------------------------
        // Structs and Packing
        
        // custom interpolators pre packing
        /* WARNING: $splice Could not find named fragment 'CustomInterpolatorPrePacking' */
        
        struct Attributes
        {
             float3 positionOS : POSITION;
             float3 normalOS : NORMAL;
             float4 tangentOS : TANGENT;
             float4 uv0 : TEXCOORD0;
             float4 color : COLOR;
            #if UNITY_ANY_INSTANCING_ENABLED || defined(ATTRIBUTES_NEED_INSTANCEID)
             uint instanceID : INSTANCEID_SEMANTIC;
            #endif
        };
        struct Varyings
        {
             float4 positionCS : SV_POSITION;
             float3 positionWS;
             float3 normalWS;
             float4 texCoord0;
             float4 color;
            #if UNITY_ANY_INSTANCING_ENABLED || defined(VARYINGS_NEED_INSTANCEID)
             uint instanceID : CUSTOM_INSTANCE_ID;
            #endif
            #if (defined(UNITY_STEREO_MULTIVIEW_ENABLED)) || (defined(UNITY_STEREO_INSTANCING_ENABLED) && (defined(SHADER_API_GLES3) || defined(SHADER_API_GLCORE)))
             uint stereoTargetEyeIndexAsBlendIdx0 : BLENDINDICES0;
            #endif
            #if (defined(UNITY_STEREO_INSTANCING_ENABLED))
             uint stereoTargetEyeIndexAsRTArrayIdx : SV_RenderTargetArrayIndex;
            #endif
            #if defined(SHADER_STAGE_FRAGMENT) && defined(VARYINGS_NEED_CULLFACE)
             FRONT_FACE_TYPE cullFace : FRONT_FACE_SEMANTIC;
            #endif
        };
        struct SurfaceDescriptionInputs
        {
             float4 uv0;
             float3 TimeParameters;
        };
        struct VertexDescriptionInputs
        {
             float3 ObjectSpaceNormal;
             float3 ObjectSpaceTangent;
             float3 ObjectSpacePosition;
        };
        struct PackedVaryings
        {
             float4 positionCS : SV_POSITION;
             float4 texCoord0 : INTERP0;
             float4 color : INTERP1;
             float3 positionWS : INTERP2;
             float3 normalWS : INTERP3;
            #if UNITY_ANY_INSTANCING_ENABLED || defined(VARYINGS_NEED_INSTANCEID)
             uint instanceID : CUSTOM_INSTANCE_ID;
            #endif
            #if (defined(UNITY_STEREO_MULTIVIEW_ENABLED)) || (defined(UNITY_STEREO_INSTANCING_ENABLED) && (defined(SHADER_API_GLES3) || defined(SHADER_API_GLCORE)))
             uint stereoTargetEyeIndexAsBlendIdx0 : BLENDINDICES0;
            #endif
            #if (defined(UNITY_STEREO_INSTANCING_ENABLED))
             uint stereoTargetEyeIndexAsRTArrayIdx : SV_RenderTargetArrayIndex;
            #endif
            #if defined(SHADER_STAGE_FRAGMENT) && defined(VARYINGS_NEED_CULLFACE)
             FRONT_FACE_TYPE cullFace : FRONT_FACE_SEMANTIC;
            #endif
        };
        
        PackedVaryings PackVaryings (Varyings input)
        {
            PackedVaryings output;
            ZERO_INITIALIZE(PackedVaryings, output);
            output.positionCS = input.positionCS;
            output.texCoord0.xyzw = input.texCoord0;
            output.color.xyzw = input.color;
            output.positionWS.xyz = input.positionWS;
            output.normalWS.xyz = input.normalWS;
            #if UNITY_ANY_INSTANCING_ENABLED || defined(VARYINGS_NEED_INSTANCEID)
            output.instanceID = input.instanceID;
            #endif
            #if (defined(UNITY_STEREO_MULTIVIEW_ENABLED)) || (defined(UNITY_STEREO_INSTANCING_ENABLED) && (defined(SHADER_API_GLES3) || defined(SHADER_API_GLCORE)))
            output.stereoTargetEyeIndexAsBlendIdx0 = input.stereoTargetEyeIndexAsBlendIdx0;
            #endif
            #if (defined(UNITY_STEREO_INSTANCING_ENABLED))
            output.stereoTargetEyeIndexAsRTArrayIdx = input.stereoTargetEyeIndexAsRTArrayIdx;
            #endif
            #if defined(SHADER_STAGE_FRAGMENT) && defined(VARYINGS_NEED_CULLFACE)
            output.cullFace = input.cullFace;
            #endif
            return output;
        }
        
        Varyings UnpackVaryings (PackedVaryings input)
        {
            Varyings output;
            output.positionCS = input.positionCS;
            output.texCoord0 = input.texCoord0.xyzw;
            output.color = input.color.xyzw;
            output.positionWS = input.positionWS.xyz;
            output.normalWS = input.normalWS.xyz;
            #if UNITY_ANY_INSTANCING_ENABLED || defined(VARYINGS_NEED_INSTANCEID)
            output.instanceID = input.instanceID;
            #endif
            #if (defined(UNITY_STEREO_MULTIVIEW_ENABLED)) || (defined(UNITY_STEREO_INSTANCING_ENABLED) && (defined(SHADER_API_GLES3) || defined(SHADER_API_GLCORE)))
            output.stereoTargetEyeIndexAsBlendIdx0 = input.stereoTargetEyeIndexAsBlendIdx0;
            #endif
            #if (defined(UNITY_STEREO_INSTANCING_ENABLED))
            output.stereoTargetEyeIndexAsRTArrayIdx = input.stereoTargetEyeIndexAsRTArrayIdx;
            #endif
            #if defined(SHADER_STAGE_FRAGMENT) && defined(VARYINGS_NEED_CULLFACE)
            output.cullFace = input.cullFace;
            #endif
            return output;
        }
        
        
        // --------------------------------------------------
        // Graph
        
        // Graph Properties
        CBUFFER_START(UnityPerMaterial)
        float4 _MainTex_TexelSize;
        float _Speed;
        float4 _Emission;
        float _TwoHeads;
        UNITY_TEXTURE_STREAMING_DEBUG_VARS;
        CBUFFER_END
        
        
        // Object and Global properties
        SAMPLER(SamplerState_Linear_Repeat);
        TEXTURE2D(_MainTex);
        SAMPLER(sampler_MainTex);
        
        // Graph Includes
        // GraphIncludes: <None>
        
        // -- Property used by ScenePickingPass
        #ifdef SCENEPICKINGPASS
        float4 _SelectionID;
        #endif
        
        // -- Properties used by SceneSelectionPass
        #ifdef SCENESELECTIONPASS
        int _ObjectId;
        int _PassValue;
        #endif
        
        // Graph Functions
        
        void Unity_Multiply_float_float(float A, float B, out float Out)
        {
            Out = A * B;
        }
        
        void Unity_Rotate_Degrees_float(float2 UV, float2 Center, float Rotation, out float2 Out)
        {
            Rotation = Rotation * (3.1415926f/180.0f);
            UV -= Center;
            float s, c;
            sincos(Rotation, s, c);
            float3 r3 = float3(-s, c, s);
            float2 r1;
            r1.y = dot(UV, r3.xy);
            r1.x = dot(UV, r3.yz);
            Out = r1 + Center;
        }
        
        void Unity_Add_float(float A, float B, out float Out)
        {
            Out = A + B;
        }
        
        void Unity_Branch_float(float Predicate, float True, float False, out float Out)
        {
            Out = Predicate ? True : False;
        }
        
        void Unity_Multiply_float4_float4(float4 A, float4 B, out float4 Out)
        {
            Out = A * B;
        }
        
        // Custom interpolators pre vertex
        /* WARNING: $splice Could not find named fragment 'CustomInterpolatorPreVertex' */
        
        // Graph Vertex
        struct VertexDescription
        {
            float3 Position;
            float3 Normal;
            float3 Tangent;
        };
        
        VertexDescription VertexDescriptionFunction(VertexDescriptionInputs IN)
        {
            VertexDescription description = (VertexDescription)0;
            description.Position = IN.ObjectSpacePosition;
            description.Normal = IN.ObjectSpaceNormal;
            description.Tangent = IN.ObjectSpaceTangent;
            return description;
        }
        
        // Custom interpolators, pre surface
        #ifdef FEATURES_GRAPH_VERTEX
        Varyings CustomInterpolatorPassThroughFunc(inout Varyings output, VertexDescription input)
        {
        return output;
        }
        #define CUSTOMINTERPOLATOR_VARYPASSTHROUGH_FUNC
        #endif
        
        // Graph Pixel
        struct SurfaceDescription
        {
            float3 BaseColor;
            float Alpha;
        };
        
        SurfaceDescription SurfaceDescriptionFunction(SurfaceDescriptionInputs IN)
        {
            SurfaceDescription surface = (SurfaceDescription)0;
            float4 _Property_9b6ecbb070d64e8ab7eeb323fa004667_Out_0_Vector4 = IsGammaSpace() ? LinearToSRGB(_Emission) : _Emission;
            float _Property_557323b6aba54b6cacfb651998a00f45_Out_0_Boolean = _TwoHeads;
            UnityTexture2D _Property_71f49cde153c4ac8b1a6f5c8110fe5cd_Out_0_Texture2D = UnityBuildTexture2DStructInternal(_MainTex, sampler_MainTex, _MainTex_TexelSize, float4(1, 1, 0, 0), float4(0, 0, 0, 0));
            float _Property_b0bf1c94287742149070d59bd9ba6446_Out_0_Float = _Speed;
            float _Multiply_73dde7affb7a45869798cefa4210fa49_Out_2_Float;
            Unity_Multiply_float_float(IN.TimeParameters.x, _Property_b0bf1c94287742149070d59bd9ba6446_Out_0_Float, _Multiply_73dde7affb7a45869798cefa4210fa49_Out_2_Float);
            float2 _Rotate_2009c0bfd64d416c8e413d2aff7e0e54_Out_3_Vector2;
            Unity_Rotate_Degrees_float(IN.uv0.xy, float2 (0.5, 0.5), _Multiply_73dde7affb7a45869798cefa4210fa49_Out_2_Float, _Rotate_2009c0bfd64d416c8e413d2aff7e0e54_Out_3_Vector2);
            float4 _SampleTexture2D_9cc87d2cc5e54f4486bbdb9e8f857524_RGBA_0_Vector4 = SAMPLE_TEXTURE2D(_Property_71f49cde153c4ac8b1a6f5c8110fe5cd_Out_0_Texture2D.tex, _Property_71f49cde153c4ac8b1a6f5c8110fe5cd_Out_0_Texture2D.samplerstate, _Property_71f49cde153c4ac8b1a6f5c8110fe5cd_Out_0_Texture2D.GetTransformedUV(_Rotate_2009c0bfd64d416c8e413d2aff7e0e54_Out_3_Vector2) );
            if (_Property_71f49cde153c4ac8b1a6f5c8110fe5cd_Out_0_Texture2D.hdrDecode.x > 0)
                _SampleTexture2D_9cc87d2cc5e54f4486bbdb9e8f857524_RGBA_0_Vector4 = DecodeHDRSample(_SampleTexture2D_9cc87d2cc5e54f4486bbdb9e8f857524_RGBA_0_Vector4, _Property_71f49cde153c4ac8b1a6f5c8110fe5cd_Out_0_Texture2D.hdrDecode);
            float _SampleTexture2D_9cc87d2cc5e54f4486bbdb9e8f857524_R_4_Float = _SampleTexture2D_9cc87d2cc5e54f4486bbdb9e8f857524_RGBA_0_Vector4.r;
            float _SampleTexture2D_9cc87d2cc5e54f4486bbdb9e8f857524_G_5_Float = _SampleTexture2D_9cc87d2cc5e54f4486bbdb9e8f857524_RGBA_0_Vector4.g;
            float _SampleTexture2D_9cc87d2cc5e54f4486bbdb9e8f857524_B_6_Float = _SampleTexture2D_9cc87d2cc5e54f4486bbdb9e8f857524_RGBA_0_Vector4.b;
            float _SampleTexture2D_9cc87d2cc5e54f4486bbdb9e8f857524_A_7_Float = _SampleTexture2D_9cc87d2cc5e54f4486bbdb9e8f857524_RGBA_0_Vector4.a;
            float _Add_7ff372654a394c4d9fe67626f83366e5_Out_2_Float;
            Unity_Add_float(_Multiply_73dde7affb7a45869798cefa4210fa49_Out_2_Float, float(180), _Add_7ff372654a394c4d9fe67626f83366e5_Out_2_Float);
            float2 _Rotate_40958894e02c445eac6d0419c43e5fce_Out_3_Vector2;
            Unity_Rotate_Degrees_float(IN.uv0.xy, float2 (0.5, 0.5), _Add_7ff372654a394c4d9fe67626f83366e5_Out_2_Float, _Rotate_40958894e02c445eac6d0419c43e5fce_Out_3_Vector2);
            float4 _SampleTexture2D_ba3818c8c3614317871eab40942d7e82_RGBA_0_Vector4 = SAMPLE_TEXTURE2D(_Property_71f49cde153c4ac8b1a6f5c8110fe5cd_Out_0_Texture2D.tex, _Property_71f49cde153c4ac8b1a6f5c8110fe5cd_Out_0_Texture2D.samplerstate, _Property_71f49cde153c4ac8b1a6f5c8110fe5cd_Out_0_Texture2D.GetTransformedUV(_Rotate_40958894e02c445eac6d0419c43e5fce_Out_3_Vector2) );
            if (_Property_71f49cde153c4ac8b1a6f5c8110fe5cd_Out_0_Texture2D.hdrDecode.x > 0)
                _SampleTexture2D_ba3818c8c3614317871eab40942d7e82_RGBA_0_Vector4 = DecodeHDRSample(_SampleTexture2D_ba3818c8c3614317871eab40942d7e82_RGBA_0_Vector4, _Property_71f49cde153c4ac8b1a6f5c8110fe5cd_Out_0_Texture2D.hdrDecode);
            float _SampleTexture2D_ba3818c8c3614317871eab40942d7e82_R_4_Float = _SampleTexture2D_ba3818c8c3614317871eab40942d7e82_RGBA_0_Vector4.r;
            float _SampleTexture2D_ba3818c8c3614317871eab40942d7e82_G_5_Float = _SampleTexture2D_ba3818c8c3614317871eab40942d7e82_RGBA_0_Vector4.g;
            float _SampleTexture2D_ba3818c8c3614317871eab40942d7e82_B_6_Float = _SampleTexture2D_ba3818c8c3614317871eab40942d7e82_RGBA_0_Vector4.b;
            float _SampleTexture2D_ba3818c8c3614317871eab40942d7e82_A_7_Float = _SampleTexture2D_ba3818c8c3614317871eab40942d7e82_RGBA_0_Vector4.a;
            float _Add_a74269f5c19345c3a0c5acf3adfe9b75_Out_2_Float;
            Unity_Add_float(_SampleTexture2D_9cc87d2cc5e54f4486bbdb9e8f857524_R_4_Float, _SampleTexture2D_ba3818c8c3614317871eab40942d7e82_R_4_Float, _Add_a74269f5c19345c3a0c5acf3adfe9b75_Out_2_Float);
            float _Branch_9f7984e913334810945ce403ce3f3c08_Out_3_Float;
            Unity_Branch_float(_Property_557323b6aba54b6cacfb651998a00f45_Out_0_Boolean, _Add_a74269f5c19345c3a0c5acf3adfe9b75_Out_2_Float, _SampleTexture2D_9cc87d2cc5e54f4486bbdb9e8f857524_R_4_Float, _Branch_9f7984e913334810945ce403ce3f3c08_Out_3_Float);
            float4 _Multiply_853dc7f28962433dbffcd7f7e0041938_Out_2_Vector4;
            Unity_Multiply_float4_float4(_Property_9b6ecbb070d64e8ab7eeb323fa004667_Out_0_Vector4, (_Branch_9f7984e913334810945ce403ce3f3c08_Out_3_Float.xxxx), _Multiply_853dc7f28962433dbffcd7f7e0041938_Out_2_Vector4);
            float4 _SampleTexture2D_6e2c106edf914040adeca1626cb0bf5e_RGBA_0_Vector4 = SAMPLE_TEXTURE2D(_Property_71f49cde153c4ac8b1a6f5c8110fe5cd_Out_0_Texture2D.tex, _Property_71f49cde153c4ac8b1a6f5c8110fe5cd_Out_0_Texture2D.samplerstate, _Property_71f49cde153c4ac8b1a6f5c8110fe5cd_Out_0_Texture2D.GetTransformedUV(IN.uv0.xy) );
            if (_Property_71f49cde153c4ac8b1a6f5c8110fe5cd_Out_0_Texture2D.hdrDecode.x > 0)
                _SampleTexture2D_6e2c106edf914040adeca1626cb0bf5e_RGBA_0_Vector4 = DecodeHDRSample(_SampleTexture2D_6e2c106edf914040adeca1626cb0bf5e_RGBA_0_Vector4, _Property_71f49cde153c4ac8b1a6f5c8110fe5cd_Out_0_Texture2D.hdrDecode);
            float _SampleTexture2D_6e2c106edf914040adeca1626cb0bf5e_R_4_Float = _SampleTexture2D_6e2c106edf914040adeca1626cb0bf5e_RGBA_0_Vector4.r;
            float _SampleTexture2D_6e2c106edf914040adeca1626cb0bf5e_G_5_Float = _SampleTexture2D_6e2c106edf914040adeca1626cb0bf5e_RGBA_0_Vector4.g;
            float _SampleTexture2D_6e2c106edf914040adeca1626cb0bf5e_B_6_Float = _SampleTexture2D_6e2c106edf914040adeca1626cb0bf5e_RGBA_0_Vector4.b;
            float _SampleTexture2D_6e2c106edf914040adeca1626cb0bf5e_A_7_Float = _SampleTexture2D_6e2c106edf914040adeca1626cb0bf5e_RGBA_0_Vector4.a;
            float _Multiply_08ba48cd0776456e9987917d16c1ef41_Out_2_Float;
            Unity_Multiply_float_float(_Branch_9f7984e913334810945ce403ce3f3c08_Out_3_Float, _SampleTexture2D_6e2c106edf914040adeca1626cb0bf5e_G_5_Float, _Multiply_08ba48cd0776456e9987917d16c1ef41_Out_2_Float);
            surface.BaseColor = (_Multiply_853dc7f28962433dbffcd7f7e0041938_Out_2_Vector4.xyz);
            surface.Alpha = _Multiply_08ba48cd0776456e9987917d16c1ef41_Out_2_Float;
            return surface;
        }
        
        // --------------------------------------------------
        // Build Graph Inputs
        #ifdef HAVE_VFX_MODIFICATION
        #define VFX_SRP_ATTRIBUTES Attributes
        #define VFX_SRP_VARYINGS Varyings
        #define VFX_SRP_SURFACE_INPUTS SurfaceDescriptionInputs
        #endif
        VertexDescriptionInputs BuildVertexDescriptionInputs(Attributes input)
        {
            VertexDescriptionInputs output;
            ZERO_INITIALIZE(VertexDescriptionInputs, output);
        
            output.ObjectSpaceNormal =                          input.normalOS;
            output.ObjectSpaceTangent =                         input.tangentOS.xyz;
            output.ObjectSpacePosition =                        input.positionOS;
        #if UNITY_ANY_INSTANCING_ENABLED
        #else // TODO: XR support for procedural instancing because in this case UNITY_ANY_INSTANCING_ENABLED is not defined and instanceID is incorrect.
        #endif
        
            return output;
        }
        SurfaceDescriptionInputs BuildSurfaceDescriptionInputs(Varyings input)
        {
            SurfaceDescriptionInputs output;
            ZERO_INITIALIZE(SurfaceDescriptionInputs, output);
        
        #ifdef HAVE_VFX_MODIFICATION
        #if VFX_USE_GRAPH_VALUES
            uint instanceActiveIndex = asuint(UNITY_ACCESS_INSTANCED_PROP(PerInstance, _InstanceActiveIndex));
            /* WARNING: $splice Could not find named fragment 'VFXLoadGraphValues' */
        #endif
            /* WARNING: $splice Could not find named fragment 'VFXSetFragInputs' */
        
        #endif
        
            
        
        
        
        
        
        
            #if UNITY_UV_STARTS_AT_TOP
            #else
            #endif
        
        
            output.uv0 = input.texCoord0;
        #if UNITY_ANY_INSTANCING_ENABLED
        #else // TODO: XR support for procedural instancing because in this case UNITY_ANY_INSTANCING_ENABLED is not defined and instanceID is incorrect.
        #endif
            output.TimeParameters = _TimeParameters.xyz; // This is mainly for LW as HD overwrite this value
        #if defined(SHADER_STAGE_FRAGMENT) && defined(VARYINGS_NEED_CULLFACE)
        #define BUILD_SURFACE_DESCRIPTION_INPUTS_OUTPUT_FACESIGN output.FaceSign =                    IS_FRONT_VFACE(input.cullFace, true, false);
        #else
        #define BUILD_SURFACE_DESCRIPTION_INPUTS_OUTPUT_FACESIGN
        #endif
        #undef BUILD_SURFACE_DESCRIPTION_INPUTS_OUTPUT_FACESIGN
        
                return output;
        }
        
        // --------------------------------------------------
        // Main
        
        #include "Packages/com.unity.render-pipelines.universal/Editor/ShaderGraph/Includes/Varyings.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/Editor/2D/ShaderGraph/Includes/SpriteUnlitPass.hlsl"
        
        // --------------------------------------------------
        // Visual Effect Vertex Invocations
        #ifdef HAVE_VFX_MODIFICATION
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/VisualEffectVertex.hlsl"
        #endif
        
        ENDHLSL
        }
        
    }
    CustomEditor "UnityEditor.ShaderGraph.GenericShaderGraphMaterialGUI"
    CustomEditorForRenderPipeline "UnityEditor.ShaderGraphSpriteGUI" "UnityEngine.Rendering.Universal.UniversalRenderPipelineAsset"
    FallBack "Hidden/Shader Graph/FallbackError"
}