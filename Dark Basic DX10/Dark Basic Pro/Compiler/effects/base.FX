//
// The Game Creators (www.thegamecreators.com)
// Base Effect Foundation
//

#include "basepool.fx"

// shader

struct VSIn
{
    float3 pos          : POSITION;
    float3 norm         : NORMAL;
    float2 tex0         : TEXTURE0;
};

struct VSOut
{
    float4 pos : SV_Position;
    float2 tex0 : TEXTURE0;
    float3 wPos : TEXTURE1; 
    float3 wNorm : TEXTURE2;
    float4 colorD : COLOR0;
    float4 colorS : COLOR1;
    float  fogDist : FOGDISTANCE;
    float3 planeDist : SV_ClipDistance0;
};

struct PSIn
{
    float4 pos : SV_Position;
    float2 tex0 : TEXTURE0;
    float3 wPos : TEXTURE1;
    float3 wNorm : TEXTURE2;
    float4 colorD : COLOR0;
    float4 colorS : COLOR1;
    float  fogDist : FOGDISTANCE;
};

cbuffer cbPerTechnique
{
    bool     g_bEnableLighting = true;
    bool     g_bEnableClipping = true;
    bool     g_bPointScaleEnable = false;
    float    g_pointScaleA;
    float    g_pointScaleB;
    float    g_pointScaleC;
    float    g_pointSize;
    float    g_fAlphaFactor;
    float    g_fAlphaTest;
    float4   g_fAmbientLight;
};
    
cbuffer cbPerViewChange
{
    //viewport params
    float    g_viewportHeight;
    float    g_viewportWidth;
    float    g_nearPlane;
};

cbuffer cbImmutable
{
    float3 g_positions[4] =
    {
        float3( -0.5, 0.5, 0 ),
        float3( 0.5, 0.5, 0 ),
        float3( -0.5, -0.5, 0 ),
        float3( 0.5, -0.5, 0 ),
    };
};

Texture2D g_tx2D0;
Texture2D g_tx2D1;
Texture2D g_tx2D2;
Texture2D g_tx2D3;
Texture2D g_tx2D4;
Texture2D g_tx2D5;
Texture2D g_tx2D6;
Texture2D g_tx2D7;

SamplerState g_samLinear
{
    Filter = ANISOTROPIC;
    AddressU = Wrap;
    AddressV = Wrap;
    AddressW = Wrap;
};

DepthStencilState DisableDepth
{
    DepthEnable = FALSE;
};

DepthStencilState EnableDepth
{
    DepthEnable = TRUE;
};

BlendState EnableFrameBuffer
{
    BlendEnable[0] = FALSE;
    RenderTargetWriteMask[0] = 0x0F;
};

BlendState EnableTransparency
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

struct ColorsOutput
{
    float4 Diffuse;
    float4 Specular;
};

ColorsOutput CalcLighting( float3 worldNormal, float3 worldPos, float3 cameraPos )
{
    ColorsOutput output = (ColorsOutput)0.0;
    
    for(int i=0; i<g_LightsUsed; i++)
    {
        float3 toLight = g_lights[i].Position.xyz - worldPos;
        float lightDist = max(length( toLight ),100);
        float fAtten = 1.0/dot( g_lights[i].Atten, float4(1,lightDist,lightDist*lightDist,0) );
        float3 lightDir = normalize( toLight );
        float3 halfAngle = normalize( normalize(-cameraPos) + lightDir );
        
        output.Diffuse += max(0,dot( lightDir, worldNormal ) * g_lights[i].Diffuse * fAtten) + g_lights[i].Ambient;
        output.Specular += max(0,pow( abs(dot(halfAngle,worldNormal)), 64 ) * g_lights[i].Specular * fAtten );
    }

    output.Diffuse += g_fAmbientLight;
    output.Diffuse.w = 1.0;
    output.Specular.w = 0.0f;
 
    return output;
}

//
// VS for emulating fixed function pipeline
//
VSOut VSScenemain(VSIn input)
{
    VSOut output = (VSOut)0.0;

    //output our final position in clipspace
    float4 worldPos = mul( float4( input.pos, 1 ), g_mWorld );
    float4 cameraPos = mul( worldPos, g_mView ); //Save cameraPos for fog calculations
    output.pos = mul( cameraPos, g_mProj );
    
    //save world pos for later
    output.wPos = worldPos;
    
    //save the fog distance for later
    output.fogDist = cameraPos.z;
    
    //find our clipping planes (fixed function clipping is done in world space)
    if( g_bEnableClipping )
    {        
        //calc the distance from the 3 clipping planes
        worldPos.w = 1;
        output.planeDist.x = dot( worldPos, g_clipplanes[0] );
        output.planeDist.y = 1;
        output.planeDist.z = 1;
    }
    else
    {
        output.planeDist.x = 1;
        output.planeDist.y = 1;
        output.planeDist.z = 1;
    }
    
    //do gouraud lighting
    if( g_bEnableLighting )
    {
        float3 worldNormal = normalize( mul( input.norm, (float3x3)g_mWorld ) );
        output.wNorm = worldNormal;
        ColorsOutput cOut = CalcLighting( worldNormal, worldPos, cameraPos );
        output.colorD = cOut.Diffuse;
        output.colorS = cOut.Specular;
    }
    else
    {
        output.colorD = float4(1,1,1,1);
    }
    
    //propogate texture coordinate
    output.tex0 = input.tex0;
    
    return output;
}

PSIn VSScreenSpacemain(VSIn input)
{
    PSIn output = (PSIn)0.0;

    //output our final position
    output.pos.x = (input.pos.x / (g_viewportWidth/2.0)) -1;
    output.pos.y = -(input.pos.y / (g_viewportHeight/2.0)) +1;
    output.pos.z = input.pos.z;
    output.pos.w = 1;
    
    //propogate texture coordinate
    output.tex0 = input.tex0;
    output.colorD = float4(1,1,1,1);
    
    return output;
}

//
// GS for flat shaded rendering
//

[maxvertexcount(3)]
void GSFlatmain( triangle VSOut input[3], inout TriangleStream<VSOut> FlatTriStream )
{
    VSOut output;
    
    //
    // Calculate the face normal
    //
    float3 faceEdgeA = input[1].wPos - input[0].wPos;
    float3 faceEdgeB = input[2].wPos - input[0].wPos;

    //
    // Cross product
    //
    float3 faceNormal = cross(faceEdgeA, faceEdgeB);
    
    //
    //calculate the face center
    //
    float3 faceCenter = (input[0].wPos + input[1].wPos + input[2].wPos)/3.0;
    
    //find world pos and camera pos
    float4 worldPos = float4( faceCenter, 1 );
    float4 cameraPos = mul( worldPos, g_mView );
    
    //do shading
    float3 worldNormal = normalize( faceNormal );
    ColorsOutput cOut = CalcLighting( worldNormal, worldPos, cameraPos );
    
    for(int i=0; i<3; i++)
    {
        output = input[i];
        output.colorD = cOut.Diffuse;
        output.colorS = cOut.Specular;
        
        FlatTriStream.Append( output );
    }
    FlatTriStream.RestartStrip();
}

//
// GS for point rendering
//
[maxvertexcount(12)]
void GSPointmain( triangle VSOut input[3], inout TriangleStream<VSOut> PointTriStream )
{
    VSOut output;
    
    //
    // Calculate the point size
    //
    //float fSizeX = (g_pointSize/g_viewportWidth)/4.0;
    float fSizeY = (g_pointSize/g_viewportHeight)/4.0;
    float fSizeX = fSizeY;
    
    for(int i=0; i<3; i++)
    {
        output = input[i];
    
        //find world pos and camera pos
        float4 worldPos = float4(input[i].wPos,1);
        float4 cameraPos = mul( worldPos, g_mView );
        
        //find our size
        if( g_bPointScaleEnable )
        {   
            float dEye = length( cameraPos.xyz );
            fSizeX = fSizeY = g_viewportHeight * g_pointSize * 
                    sqrt( 1.0f/( g_pointScaleA + g_pointScaleB*dEye + g_pointScaleC*(dEye*dEye) ) );
        }
        
        //do shading
        if(g_bEnableLighting)
        {
            float3 worldNormal = input[i].wNorm;
            ColorsOutput cOut = CalcLighting( worldNormal, worldPos, cameraPos );
        
            output.colorD = cOut.Diffuse;
            output.colorS = cOut.Specular;
        }
        else
        {
            output.colorD = float4(1,1,1,1);
            output.colorS = float4(0,0,0,0);
        }
        
        output.tex0 = input[i].tex0;
        
        //
        // Emit two new triangles
        //
        for(int i=0; i<4; i++)
        {
            float4 outPos = mul( worldPos, g_mView );
            output.pos = mul( outPos, g_mProj );
            float zoverNear = (outPos.z)/g_nearPlane;
            float4 posSize = float4( g_positions[i].x*fSizeX*zoverNear,
                                     g_positions[i].y*fSizeY*zoverNear,
                                     0,
                                     0 );
            output.pos += posSize;
            
            PointTriStream.Append(output);
        }
        PointTriStream.RestartStrip();
    }
}

//
// Calculates fog factor based upon distance
//
float CalcFogFactor( float d )
{
    float fogCoeff = 1.0;
    if( FOGMODE_LINEAR == g_fogMode )
    {
        fogCoeff = (g_fogEnd - d)/(g_fogEnd - g_fogStart);
    }
    return clamp( fogCoeff, 0, 1 );
}

//
// PS for rendering with clip planes
//
float4 PSScenemain(PSIn input) : SV_Target
{   
    float4 texColor = g_tx2D0.Sample( g_samLinear, input.tex0 );
    if ( texColor.a < g_fAlphaTest )
        discard;

    //calculate the color based off of the normal, textures, etc
    float4 normalColor = texColor * input.colorD + input.colorS;
    float4 color = normalColor;
    color.w = color.w * g_fAlphaFactor;

    //calculate the fog factor  
    float fog = CalcFogFactor( input.fogDist );
    color.xyz = color.xyz + ((1.0 - fog)*g_fogColor.xyz);

    return color;
}

float4 PSScenemainNOTEX(PSIn input) : SV_Target
{   
    //calculate the fog factor  
    float fog = CalcFogFactor( input.fogDist );
    
    //calculate the color based off of the normal, textures, etc
    float4 normalColor = float4(1,1,1,1) * input.colorD + input.colorS;
//    return fog * normalColor + (1.0 - fog)*g_fogColor;

    // not using NOTEX base for anything, so colour with purple debug hue
    return float4(1,0,1,1);
}

float4 PSAlphaTestmain(PSIn input) : SV_Target
{   
    float4 color =  g_tx2D0.Sample( g_samLinear, input.tex0 ) * input.colorD;
    if( color.a < 0.5 )
        discard;
    return color;
}

technique10 DefaultCOL
{
    pass p0
    {
        SetVertexShader( CompileShader( vs_4_0, VSScenemain() ) );
        SetGeometryShader( NULL );
        SetPixelShader( CompileShader( ps_4_0, PSScenemainNOTEX() ) );
        SetBlendState( EnableFrameBuffer, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
    }  
}
technique10 DefaultTEX
{
    pass p0
    {
        SetVertexShader( CompileShader( vs_4_0, VSScenemain() ) );
        SetGeometryShader( NULL );
        SetPixelShader( CompileShader( ps_4_0, PSScenemain() ) );        
        SetBlendState( EnableTransparency, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
    }  
}










// from FixedFunc Example - use to re-create old pipeline where needed
//
// RenderSceneFlat - renders flat-shaded primitives
//
technique10 RenderSceneFlat
{
    pass p0
    {
        SetVertexShader( CompileShader( vs_4_0, VSScenemain() ) );
        SetGeometryShader( CompileShader( gs_4_0, GSFlatmain() ) );
        SetPixelShader( CompileShader( ps_4_0, PSScenemain() ) );
        
        SetDepthStencilState( EnableDepth, 0 );
    }  
}

//
// RenderScenePoint - replaces d3dfill_point
//
technique10 RenderScenePoint
{
    pass p0
    {
        SetVertexShader( CompileShader( vs_4_0, VSScenemain() ) );
        SetGeometryShader( CompileShader( gs_4_0, GSPointmain() ) );
        SetPixelShader( CompileShader( ps_4_0, PSScenemain() ) );
        
        SetDepthStencilState( EnableDepth, 0 );
    }  
}

//
// RenderScreneSpace - shows how to render something in screenspace
//
technique10 RenderScreenSpaceAlphaTest
{
    pass p0
    {
        SetVertexShader( CompileShader( vs_4_0, VSScreenSpacemain() ) );
        SetGeometryShader( NULL );
        SetPixelShader( CompileShader( ps_4_0, PSAlphaTestmain() ) );
        
        SetDepthStencilState( DisableDepth, 0 );
    }  
}

//
// RenderScreneSpace - shows how to render something in screenspace
//
technique10 RenderTextureOnly
{
    pass p0
    {
        SetVertexShader( CompileShader( vs_4_0, VSScenemain() ) );
        SetGeometryShader( NULL );
        SetPixelShader( CompileShader( ps_4_0, PSScenemain() ) );
        
        SetDepthStencilState( EnableDepth, 0 );
    }  
}

