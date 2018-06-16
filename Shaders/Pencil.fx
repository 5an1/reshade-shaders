/*******************************************************
	ReShade Shader: Pencil
	https://github.com/Daodan317081/reshade-shaders
*******************************************************/

#include "ReShade.fxh"
#include "Tools.fxh"

#define UI_CATEGORY_OUTLINES "Outlines (needs depth buffer)"
#define UI_CATEGORY_EDGES "Edge Detection Weight"
#define UI_CATEGORY_DEBUG "Debug"
#define UI_CATEGORY_EFFECT "Effect"

/******************************************************************************
	Uniforms
******************************************************************************/
////////////////////////// Pencil Layer //////////////////////////

//Outlines
uniform int iUIOutlinesEnableThreshold <
	ui_type = "combo";
	ui_category = UI_CATEGORY_OUTLINES;
	ui_label = "Enable Threshold";
	ui_items = "Off\0On\0";
> = 0;

uniform float fUIOutlinesThreshold <
	ui_type = "drag";
	ui_category = UI_CATEGORY_OUTLINES;
	ui_label = "Threshold";
	ui_min = 0.0; ui_max = 1.0;
	ui_step = 0.001;
> = 0.5;

uniform int iUIOutlinesFadeWithDistance <
	ui_type = "combo";
	ui_category = UI_CATEGORY_OUTLINES;
	ui_label = "Distance Weight";
	ui_tooltip = "Outlines fade with increasing distance (or inverse)";
	ui_items = "No\0Decrease\0Increase\0";
> = 0;

uniform float fUIOutlinesStrength <
	ui_type = "drag";
	ui_category = UI_CATEGORY_OUTLINES;
	ui_label = "Strength";
	ui_min = 0.0; ui_max = 1.0;
> = 1.0;

//Edge Detection
uniform float fUIDiffEdgesStrength <
	ui_type = "drag";
	ui_category = UI_CATEGORY_EDGES;
	ui_label = "Luma";
	ui_min = 0.0; ui_max = 1.0;
> = 1.0;

uniform float fUIConvStrength <
	ui_type = "drag";
	ui_category = UI_CATEGORY_EDGES;
	ui_label = "Chroma";
	ui_min = 0.0; ui_max = 1.0;
> = 1.0;

uniform float fUIConvClip <
	ui_type = "drag";
	ui_category = UI_CATEGORY_EDGES;
	ui_label = "Clip";
	ui_min = 0.0; ui_max = 1.0;
> = 0.0;

uniform float3 fUIPencilColor <
	ui_type = "color";
	ui_category = UI_CATEGORY_EDGES;
	ui_label = "Color";
> = float3(0.0, 0.0, 0.0);

////////////////////////// Debug //////////////////////////

uniform int iUIDebugMaps <
	ui_type = "combo";
	ui_category = UI_CATEGORY_DEBUG;
	ui_label = "Show Debug Maps";
	ui_items = "Off\0Depth Buffer Outlines\0Luma Edges\0Chroma Edges\0Pencil Layer\0Show Depth Buffer\0";
> = 0;

////////////////////////// Effect //////////////////////////
uniform float fUIStrength <
	ui_type = "drag";
	ui_category = UI_CATEGORY_EFFECT;
	ui_label = "Strength";
	ui_min = 0.0; ui_max = 1.0;
> = 1.0;

/******************************************************************************
	Textures
******************************************************************************/

texture2D texColorfulPosterChroma { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
sampler2D SamplerColorfulPosterChroma { Texture = texColorfulPosterChroma; };

/******************************************************************************
	Pixel Shader
******************************************************************************/

//Convolution gets currently done with samplers, so rendering chroma to a texture is necessary
void Chroma_PS(float4 vpos : SV_Position, float2 texcoord : TexCoord, out float3 chroma : SV_Target0) {
	float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
	chroma = color - dot(color, LumaCoeff);
}

float3 Pencil_PS(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target {
	
	/*******************************************************
		Get BackBuffer
	*******************************************************/
	float3 backbuffer = tex2D(ReShade::BackBuffer, texcoord).rgb;

	/*******************************************************
		Create PencilLayer
	*******************************************************/
	float depthC =  ReShade::GetLinearizedDepth(texcoord);
	float depthN =  ReShade::GetLinearizedDepth(texcoord + float2(0.0, -ReShade::PixelSize.y));
	float depthNE = ReShade::GetLinearizedDepth(texcoord + float2(ReShade::PixelSize.x, -ReShade::PixelSize.y));
	float depthE =  ReShade::GetLinearizedDepth(texcoord + float2(ReShade::PixelSize.x, 0.0));
	float depthSE = ReShade::GetLinearizedDepth(texcoord + float2(ReShade::PixelSize.x, ReShade::PixelSize.y));
	float depthS =  ReShade::GetLinearizedDepth(texcoord + float2(0.0, ReShade::PixelSize.y));
	float depthSW = ReShade::GetLinearizedDepth(texcoord + float2(-ReShade::PixelSize.x, ReShade::PixelSize.y));
	float depthW =  ReShade::GetLinearizedDepth(texcoord + float2(-ReShade::PixelSize.x, 0.0));
	float depthNW = ReShade::GetLinearizedDepth(texcoord + float2(-ReShade::PixelSize.x, -ReShade::PixelSize.y));
	float diffNS = abs(depthN - depthS);
	float diffWE = abs(depthW - depthE);
	float diffNWSE = abs(depthNW - depthSE);
	float diffSWNE = abs(depthSW - depthNE);
	float outlinesDepthBuffer = (diffNS + diffWE + diffNWSE + diffSWNE);

	if(iUIOutlinesEnableThreshold == 1)
		outlinesDepthBuffer = outlinesDepthBuffer < fUIOutlinesThreshold ? 0.0 : 1.0;

	if(iUIOutlinesFadeWithDistance == 1)
		outlinesDepthBuffer *= (1.0 - depthC);
	else if(iUIOutlinesFadeWithDistance == 2)
		outlinesDepthBuffer *= depthC;
		
	outlinesDepthBuffer *= fUIOutlinesStrength;

	float lumaEdges = Tools::Functions::DiffEdges(ReShade::BackBuffer, texcoord) * fUIDiffEdgesStrength;
	float chromaEdges = Tools::Convolution::Edges(SamplerColorfulPosterChroma, texcoord, CONV_SOBEL2, CONV_MAX).r * fUIConvStrength;

	//Finalize pencil layer
	float pencilLayer = saturate(outlinesDepthBuffer + lumaEdges + chromaEdges);
	pencilLayer = pencilLayer < fUIConvClip ? 0.0 : pencilLayer;

	/*******************************************************
		Show debug stuff
	*******************************************************/
	if(iUIDebugMaps == 1)
		return lerp(1.0.rrr, fUIPencilColor, outlinesDepthBuffer);
	else if(iUIDebugMaps == 2)
		return lerp(1.0.rrr, fUIPencilColor, lumaEdges);
	else if(iUIDebugMaps == 3)
		return lerp(1.0.rrr, fUIPencilColor, chromaEdges);
	else if(iUIDebugMaps == 4)
		return lerp(1.0.rrr, fUIPencilColor, pencilLayer);
	else if(iUIDebugMaps == 5)
		return ReShade::GetLinearizedDepth(texcoord).rrr;

	/*******************************************************
		Set overall strength and return
	*******************************************************/
	return lerp(backbuffer, fUIPencilColor, fUIStrength * pencilLayer);
}

technique Pencil
{
	pass {
		VertexShader = PostProcessVS;
		PixelShader = Chroma_PS;
		RenderTarget0 = texColorfulPosterChroma;
	}
	pass {
		VertexShader = PostProcessVS;
		PixelShader = Pencil_PS;
	}
}