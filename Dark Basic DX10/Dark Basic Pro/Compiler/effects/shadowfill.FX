//
// The Game Creators (www.thegamecreators.com)
// Shadow Effect
//

// Fill the screen with the colour of the shadow VS + PS
struct VSIn
{
	float3 pos	: POSITION;
	float3 norm 	: NORMAL;
	float2 tex	: TEXTURE0;
};

struct VSOut
{
	float4 pos 	: SV_Position;
};

DepthStencilState RenderWithStencilState
{
    DepthEnable = false;
    DepthWriteMask = ZERO;
    DepthFunc = Less;
    
    // Setup stencil states
    StencilEnable = true;
    StencilReadMask = 0xFFFFFFFF;
    StencilWriteMask = 0x00;
    
    FrontFaceStencilFunc = Not_Equal;
    FrontFaceStencilPass = Keep;
    FrontFaceStencilFail = Zero;
    
    BackFaceStencilFunc = Not_Equal;
    BackFaceStencilPass = Keep;
    BackFaceStencilFail = Zero;
};

DepthStencilState RenderWithStencilStateReversed
{
    DepthEnable = false;
    DepthWriteMask = ZERO;
    DepthFunc = Less;
    
    // Setup stencil states
    StencilEnable = true;
    StencilReadMask = 0xFFFFFFFF;
    StencilWriteMask = 0x00;
    
    FrontFaceStencilFunc = Equal;
    FrontFaceStencilPass = Keep;
    FrontFaceStencilFail = Zero;
    
    BackFaceStencilFunc = Equal;
    BackFaceStencilPass = Keep;
    BackFaceStencilFail = Zero;
};

BlendState BlendIntoScene
{
    AlphaToCoverageEnable = FALSE;
    BlendEnable[0] = FALSE; // SOLID SHADOW
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

VSOut VSFillmain( VSIn input )
{
	VSOut OUT;
	OUT.pos=float4(input.pos,1);
	return OUT;
}

float4 PSFillmain(VSOut input) : SV_Target
{   
//	return float4(1,1,1,1);
	return float4(0,0,0,0);//blank all except stencil if 'RenderWithStencilStateReversed'
}

// FillQuad - fills screen with shadow colour (through stencil)
technique10 FillQuad
{
    pass p0
    {
        SetVertexShader( CompileShader( vs_4_0, VSFillmain() ) );
        SetGeometryShader( NULL );
        SetPixelShader( CompileShader( ps_4_0, PSFillmain() ) );

	// show stencil buffer
	SetBlendState( BlendIntoScene, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
        SetDepthStencilState( RenderWithStencilStateReversed, 0 );
    }
}
