//
// The Game Creators (www.thegamecreators.com)
// Particle Effects
//

struct VSParticleIn
{
    float3 Pos			  : POSITION;
    float3 Vel			  : VELOCITY;
    float Life			  : LIFE;
    float Size			  : SIZE;
};

struct GSParticleIn
{
    float3 Pos            : POSITION;
    float Life            : LIFE;	//stage of animation we're in [0..1] 0 is first frame, 1 is last
    float Size            : SIZE;
};

struct PSParticleIn
{
    float4 Pos			  : SV_POSITION;
    float3 Tex			  : TEXCOORD0;
    float2 ScreenTex	  	  : TEXCOORD1;
    float2 Depth		  : TEXCOORD2;
    float  Size			  : TEXCOORD3;
    float3 worldPos		  : TEXCOORD4;
    float3 particleOrig	  : TEXCOORD5;
    float3 particleColor  : TEXCOORD6;
};

cbuffer cbPerObject
{
    matrix g_mWorldViewProj;
    matrix g_mWorldView;
    matrix g_mWorld;
    matrix g_mInvView;
    matrix g_mInvProj;
    float3 g_vViewDir;
};

cbuffer cbUser
{
    float g_fFadeDistance;
    float g_fSizeZScale;
    float4 g_vEyePt;
    float4 g_ParticleDiffuse;
};

cbuffer cbImmutable
{
    float3 g_positions[4] =
    {
        float3( -1, 1, 0 ),
        float3( 1, 1, 0 ),
        float3( -1, -1, 0 ),
        float3( 1, -1, 0 ),
    };
    float2 g_texcoords[4] = 
    { 
        float2(0,0), 
        float2(1,0),
        float2(0,1),
        float2(1,1),
    };
    float4 g_directional1 = float4( 0.992, 1.0, 0.880, 0.0 );
    float4 g_directional2 = float4( 0.595, 0.6, 0.528, 0.0 );
    float4 g_ambient = float4(0.525,0.474,0.474,0.0);
};

Texture3D g_txVolumeDiff;
Texture2D g_txDepth;

SamplerState g_samPoint
{
    Filter = MIN_MAG_MIP_POINT;
    AddressU = Clamp;
    AddressV = Clamp;
};

SamplerState g_samVolume
{
    Filter = MIN_MAG_LINEAR_MIP_POINT;
    AddressU = Wrap;
    AddressV = Wrap;
    AddressW = Wrap;
};


BlendState AlphaBlending
{
    AlphaToCoverageEnable = FALSE;
    BlendEnable[0] = TRUE;
    SrcBlend = SRC_ALPHA;
    DestBlend = INV_SRC_ALPHA;
    BlendOp = ADD;
    SrcBlendAlpha = ZERO;
    DestBlendAlpha = ZERO;
    BlendOpAlpha = ADD;
    RenderTargetWriteMask[0] = 0x0F;
};

BlendState NoBlending
{
    AlphaToCoverageEnable = FALSE;
    BlendEnable[0] = FALSE;
};

DepthStencilState EnableDepth
{
    DepthEnable = TRUE;
    DepthWriteMask = ALL;
};

DepthStencilState DisableDepth
{
    DepthEnable = FALSE;
    DepthWriteMask = ZERO;
};

DepthStencilState DisableDepthWrite
{
    DepthEnable = TRUE;
    DepthWriteMask = ZERO;
};

DepthStencilState DisableDepthTest
{
    DepthEnable = TRUE;
    DepthWriteMask = ALL;
    DepthFunc = ALWAYS;
};

GSParticleIn VSParticlemain(VSParticleIn input)
{
    GSParticleIn output;
    
    output.Pos = input.Pos;
    output.Life = input.Life;
    output.Size = input.Size;
    
    return output;
}

[maxvertexcount(4)]
void GSParticlemain(point GSParticleIn input[1], inout TriangleStream<PSParticleIn> SpriteStream)
{
    PSParticleIn output;
    
    float4 orig = mul( float4(input[0].Pos,1), g_mWorld );
    output.particleOrig = orig.xyz;
    
    if( input[0].Life > -1 )
    {
        // calculate color from a 1d gradient texture
        float3 particleColor = float3(input[0].Life,input[0].Life,input[0].Life);//g_txColorGradient.SampleLevel( g_samLinearClamp, float2(input[0].Life,0), 0 );
        output.particleColor = particleColor;
            
        //
        // Emit two new triangles
        //
        [unroll] for(int i=0; i<4; i++)
        {
            float3 position = g_positions[i]*input[0].Size;
            position = mul( position, (float3x3)g_mInvView ) + input[0].Pos;
            output.Pos = mul( float4(position,1.0), g_mWorldViewProj );
            
            // pass along the texcoords
            output.Tex = float3(g_texcoords[i],input[0].Life);
            
            // screenspace coordinates for the lookup into the depth buffer
            output.ScreenTex = output.Pos.xy/output.Pos.w;
            
            // output depth of this particle
            output.Depth = output.Pos.zw;
            
            // size
            output.Size = input[0].Size;
                                    
            // world position
            float4 posWorld = mul( float4(position,1.0), g_mWorld );
            output.worldPos = posWorld;							
            
            SpriteStream.Append(output);
        }
        SpriteStream.RestartStrip();
    }
}

//
// PS for the particles
//
float4 PSBillboardParticlemain(PSParticleIn input, uniform bool bSoftParticles ) : SV_TARGET
{     
    float2 screenTex = 0.5*( (input.ScreenTex) + float2(1,1));
    screenTex.y = 1 - screenTex.y;
    
    float4 particleSample = g_txVolumeDiff.Sample( g_samVolume, input.Tex );
    
    float particleDepth = input.Depth.x;
    particleDepth /= input.Depth.y;
        
    float depthFade = 1;
    if( bSoftParticles )
    {
        // We need to determine the distance between the value stored in the depth buffer
        // and the value that came in from the GS
        // Because the depth values aren't linear, we need to transform the depthsample back into view space
        // in order for the comparison to give us an accurate distance
        float depthSample = g_txDepth.Sample( g_samPoint, screenTex );
        
        float4 depthViewSample = mul( float4( input.ScreenTex, depthSample, 1 ), g_mInvProj );
        float4 depthViewParticle = mul( float4( input.ScreenTex, particleDepth, 1 ), g_mInvProj );
        
        float depthDiff = depthViewSample.z/depthViewSample.w - depthViewParticle.z/depthViewParticle.w;
        if( depthDiff < 0 )
            discard;
            
        depthFade = saturate( depthDiff / g_fFadeDistance );
    }
        
    float4 Light = g_directional1 + g_ambient;
    particleSample.rgb *= Light.xyz*input.particleColor * g_ParticleDiffuse;
    particleSample.a *= depthFade;
    
    return particleSample;
}

technique10 RenderBillboardParticles_Hard
{
    pass p0
    {
        SetVertexShader( CompileShader( vs_4_0, VSParticlemain() ) );
        SetGeometryShader( CompileShader( gs_4_0, GSParticlemain() ) );
        SetPixelShader( CompileShader( ps_4_0, PSBillboardParticlemain(false) ) );
        
        SetBlendState( AlphaBlending, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
        SetDepthStencilState( DisableDepthWrite, 0 );
    }  
}

technique10 RenderBillboardParticles_Soft
{
    pass p0
    {
        SetVertexShader( CompileShader( vs_4_0, VSParticlemain() ) );
        SetGeometryShader( CompileShader( gs_4_0, GSParticlemain() ) );
        SetPixelShader( CompileShader( ps_4_0, PSBillboardParticlemain(true) ) );
        
        SetBlendState( AlphaBlending, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
        SetDepthStencilState( DisableDepthWrite, 0 );
    }  
}

