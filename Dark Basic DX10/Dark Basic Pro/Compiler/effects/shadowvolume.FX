//
// The Game Creators (www.thegamecreators.com)
// Shadow Effect
//

#include "basepool.fx"

#define LIGHT_FALLOFF 1.2f
#define NOVERTEX 0xfffffffe

struct VSSceneIn
{
    float4 pos          : POSITION;    
    float3 norm         : NORMAL;  
    float2 tex          : TEXTURE0;
    float3 tan          : TANGENT;
};

struct VSSceneInInst
{
    float4 pos          : POSITION;    
    float3 norm         : NORMAL;  
    float2 tex          : TEXTURE0;
    float3 tan          : TANGENT;
    row_major float4x4 mTransform : mTransform;		// instance struct
    uint4 uExtraData : uExtraData;
};

struct VSSceneInInstNoneStreamed
{
    float3 pos          : POSITION;    
    float3 norm         : NORMAL;  
    float2 tex          : TEXTURE0;
    float3 tan          : TANGENT;
    row_major float4x4 mTransform : mTransform;		// instance struct
    uint4 uExtraData : uExtraData;
};

struct GSShadowIn
{
    float3 pos          : POS; 
    float3 norm         : TEXTURE0;
    float3 center       : TEXTURE1;
    uint   extrudelen   : TEXTURE2;
};

struct PSShadowIn
{
    float4 pos : SV_Position;
    float4 spos : TEXTURE0;
    float far : TEXTURE1;
};

struct PSSceneIn
{
    float4 pos : SV_Position;
    float4 color : COLOR0; 
    float2 tex : TEXTURE0;
};

cbuffer cb1
{
    float3 g_vShadowPos;
    float g_fExtrudeAmt;
    float g_fExtrudeBias;
    float g_fShadowFadeInDistance;
};

SamplerState g_samLinear
{
    Filter = MIN_MAG_MIP_LINEAR;
    AddressU = Wrap;
    AddressV = Wrap;
};

DepthStencilState DisableDepth
{
    DepthEnable = FALSE;
    DepthWriteMask = ZERO;
};

DepthStencilState EnableDepth
{
    DepthEnable = TRUE;
    DepthWriteMask = ALL;
};

DepthStencilState TwoSidedStencil
{
    DepthEnable = true;
    DepthWriteMask = ZERO;
    DepthFunc = Greater;	//CHANGE - invert the depth test, stencil is now changed on depth pass
    
    // Setup stencil states
    StencilEnable = true;
    StencilReadMask = 0xFF;
    StencilWriteMask = 0xFF;
    
    BackFaceStencilFunc = Always;
    BackFaceStencilDepthFail = Keep;
    BackFaceStencilPass = Incr;	//CHANGE - stencil will always pass, stencil only changes on depth pass
    BackFaceStencilFail = Keep;
    
    FrontFaceStencilFunc = Always;
    FrontFaceStencilDepthFail = Keep;
    FrontFaceStencilPass = Decr;	//CHANGE
    FrontFaceStencilFail = Keep;
};

DepthStencilState UseStencilToDraw
{
    DepthEnable = true;
    DepthWriteMask = ALL;
    DepthFunc = Less_Equal;
    
    StencilEnable = true;
    StencilReadMask = 0xFFFFFFFF;
    StencilWriteMask = 0x0;
    
    FrontFaceStencilFunc = Not_Equal;
    FrontFaceStencilPass = Keep;
    FrontFaceStencilFail = Zero;
    
    BackFaceStencilFunc = Never;
    BackFaceStencilPass = Zero;
    BackFaceStencilFail = Zero;
};

BlendState DisableFrameBuffer
{
    BlendEnable[0] = FALSE;
    RenderTargetWriteMask[0] = 0x0;
};

BlendState EnableFrameBuffer
{
    BlendEnable[0] = FALSE;
    RenderTargetWriteMask[0] = 0x0F;
};

BlendState NoBlending
{
    AlphaToCoverageEnable = FALSE;
    BlendEnable[0] = FALSE;
    RenderTargetWriteMask[0] = 0x0F;
};

RasterizerState DisableCulling
{
    CullMode = NONE;
};

RasterizerState EnableCulling
{
    CullMode = BACK;
};

Texture2D g_txDepth;

SamplerState g_samPoint
{
    Filter = MIN_MAG_MIP_POINT;
    AddressU = Clamp;
    AddressV = Clamp;
};

// VS for sending information to the shadow GS
GSShadowIn VSShadowmain( VSSceneIn input )
{
    GSShadowIn output = (GSShadowIn)0.0;

    //output our position in world space (W must be 1)
    float4 pos = mul( float4(input.pos.xyz,1), g_mWorld );
    output.pos = pos.xyz;
    
    //world space normal
    output.norm = mul( input.norm, (float3x3)g_mWorld );

    // center of object used for didtance from light calc
    output.center = g_mWorld[3].xyz;

    // move extrude length to vertex data (for non-instancing shadow lengths only)
    output.extrudelen = g_fExtrudeAmt;
    
    return output;
}
GSShadowIn VSShadowmainInst( VSSceneInInst input )
{
    GSShadowIn output = (GSShadowIn)0.0;

    float4 InstancePosition = mul(float4(input.pos.xyz,1), input.mTransform);
    uint iTexID = input.uExtraData.x;
    uint iMask = input.uExtraData.y;
    uint iRes1 = input.uExtraData.z;
    uint iRes2 = input.uExtraData.w;

    // iMask used for shadow length (not needed as it is a redundant visibility flag)
    output.pos = InstancePosition.xyz;
    output.norm = mul(input.norm, (float3x3)input.mTransform);
    output.center = input.mTransform[3].xyz;

    // move extrude length to vertex data (for non-instancing shadow lengths only)
    output.extrudelen = iMask * 5.0;

    return output;
}

GSShadowIn VSShadowmainInstNoneStreamed( VSSceneInInstNoneStreamed input )
{
    GSShadowIn output = (GSShadowIn)0.0;

    float4 InstancePosition = mul(float4(input.pos,1), input.mTransform);
    uint iTexID = input.uExtraData.x;
    uint iMask = input.uExtraData.y;
    uint iRes1 = input.uExtraData.z;
    uint iRes2 = input.uExtraData.w;

    // iMask used for shadow length (not needed as it is a redundant visibility flag)
    output.pos = InstancePosition.xyz;
    output.norm = mul(input.norm, (float3x3)input.mTransform);
    output.center = input.mTransform[3].xyz;

    // move extrude length to vertex data (for non-instancing shadow lengths only)
    output.extrudelen = iMask * 5.0;

    return output;
}

void DetectAndProcessSilhouette( float3 N,                  // Un-normalized triangle normal
                                 GSShadowIn v1,    // Shared vertex
                                 GSShadowIn v2,    // Shared vertex
                                 GSShadowIn vAdj,  // Adjacent triangle vertex
                                 inout TriangleStream<PSShadowIn> ShadowTriangleStream // triangle stream
                                 )
{    
        float3 outpos[4];
        float3 extrude1 = normalize(v1.pos - g_vShadowPos);
        float3 extrude2 = normalize(v2.pos - g_vShadowPos);

        outpos[0] = v1.pos + g_fExtrudeBias*extrude1;
        outpos[1] = v1.pos + v1.extrudelen*extrude1;
        outpos[2] = v2.pos + g_fExtrudeBias*extrude2;
        outpos[3] = v2.pos + v1.extrudelen*extrude2;
        
        // Extrude silhouette to create two new triangles
        PSShadowIn Out;
        for(int v=0; v<4; v++)
        {
            Out.pos = mul( float4(outpos[v],1), g_mViewProj );
            Out.spos = Out.pos;
            Out.far = 1.0; // 150807 - does not fade based on distance - (abs(length(v1.center-g_vShadowPos)) / 800.0f);
            ShadowTriangleStream.Append( Out );
        }
        ShadowTriangleStream.RestartStrip();
}

[maxvertexcount(18)]
void GSShadowmain( triangleadj GSShadowIn In[6], inout TriangleStream<PSShadowIn> ShadowTriangleStream )
{
    // Compute un-normalized triangle normal
    float3 N = cross( In[2].pos - In[0].pos, In[4].pos - In[0].pos );

    // Compute direction from this triangle to the light
    float3 lightDir = g_vShadowPos - In[0].pos;
    
    //if we're facing the light
    if( dot(N, lightDir) > 0.0f )
    {
        // For each edge of the triangle, determine if it is a silhouette edge
        DetectAndProcessSilhouette( lightDir, In[0], In[2], In[1], ShadowTriangleStream );
        DetectAndProcessSilhouette( lightDir, In[2], In[4], In[3], ShadowTriangleStream );
        DetectAndProcessSilhouette( lightDir, In[4], In[0], In[5], ShadowTriangleStream );
        
        //near cap
        PSShadowIn Out;
        for(int v=0; v<6; v+=2)
        {
            float3 extrude = normalize(In[v].pos - g_vShadowPos);
            float3 pos = In[v].pos + g_fExtrudeBias*extrude;
            Out.pos = mul( float4(pos,1), g_mViewProj );
            Out.spos = Out.pos;
            Out.far = 1;
            ShadowTriangleStream.Append( Out );
        }
        ShadowTriangleStream.RestartStrip();
        
        //far cap (reverse the order)
        for(int v=4; v>=0; v-=2)
        {
            float3 extrude = normalize(In[v].pos - g_vShadowPos);
            float3 pos = In[v].pos + In[v].extrudelen*extrude;
            Out.pos = mul( float4(pos,1), g_mViewProj );
            Out.spos = Out.pos;
            Out.far = 1;	//CHANGE - far=0 caused blurring artefacts
            ShadowTriangleStream.Append( Out );
        }
        ShadowTriangleStream.RestartStrip();
    }
}

float4 PSShadowmain(PSShadowIn input) : SV_Target
{   
    // screenspace coordinates for the lookup into the depth buffer and output depth
    float2 inputScreenTex = input.spos.xy/input.spos.w;
    float2 inputDepth = input.spos.zw;
    float2 screenTex = 0.5*( (inputScreenTex) + float2(1,1));
    screenTex.y = 1 - screenTex.y;

    // work out depth difference        
    float depthSample = g_txDepth.Sample( g_samPoint, screenTex );
    float4 depthViewSample = mul( float4( inputScreenTex, depthSample, 1 ), g_mInvProj );

    // return black if far, white if near
    float DepthDist = (1.0-((depthViewSample.z/depthViewSample.w)/g_fShadowFadeInDistance ));

    // carry information from volume renderer to shadow blur shader
    // red=distance from viewer / green=distance from light / blue=1 / alpha=1
    return float4(DepthDist,input.far,1,1);
}

technique10 RenderShadow
{
    pass p0
    {
        SetVertexShader( CompileShader( vs_4_0, VSShadowmain() ) );
        SetGeometryShader( CompileShader( gs_4_0, GSShadowmain() ) );
        SetPixelShader( CompileShader( ps_4_0, PSShadowmain() ) );
        SetBlendState( EnableFrameBuffer, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
        SetDepthStencilState( TwoSidedStencil, 1 ); //state, stencilref
        SetRasterizerState( DisableCulling );
    }
}

technique10 RenderShadowInst
{
    pass p0
    {
        SetVertexShader( CompileShader( vs_4_0, VSShadowmainInst() ) );
        SetGeometryShader( CompileShader( gs_4_0, GSShadowmain() ) );
        SetPixelShader( CompileShader( ps_4_0, PSShadowmain() ) );
        SetBlendState( EnableFrameBuffer, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
        SetDepthStencilState( TwoSidedStencil, 1 ); //state, stencilref
        SetRasterizerState( DisableCulling );
    }
}

technique10 RenderShadowInstNoneStreamed
{
    pass p0
    {
        SetVertexShader( CompileShader( vs_4_0, VSShadowmainInstNoneStreamed() ) );
        SetGeometryShader( CompileShader( gs_4_0, GSShadowmain() ) );
        SetPixelShader( CompileShader( ps_4_0, PSShadowmain() ) );
        SetBlendState( EnableFrameBuffer, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
        SetDepthStencilState( TwoSidedStencil, 1 ); //state, stencilref
        SetRasterizerState( DisableCulling );
    }
}
