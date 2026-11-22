// A minimal lightmapped material for verifying the iOS shader pipeline.
cbuffer DrawConstants : register(b3)
{
    float4 transform; // translation x/y, aspect correction, rotation
    float4 tint;
};

Texture2D<float4> baseTexture : register(t0);
Texture2D<float4> lightTexture : register(t1);
SamplerState materialSampler : register(s2);

struct VertexInput
{
    float2 position : POSITION;
    float2 uv : TEXCOORD0;
    float2 lightUV : TEXCOORD1;
};

struct VertexOutput
{
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
    float2 lightUV : TEXCOORD1;
};

VertexOutput vertexMain(VertexInput input)
{
    float sine, cosine;
    sincos(transform.w, sine, cosine);
    float2 p = float2(cosine * input.position.x - sine * input.position.y,
                      sine * input.position.x + cosine * input.position.y);
    VertexOutput output;
    output.position = float4(p * float2(transform.z, 1.0) + transform.xy, 0.5, 1.0);
    output.uv = input.uv;
    output.lightUV = input.lightUV;
    return output;
}

float4 fragmentMain(VertexOutput input) : SV_Target0
{
    float4 base = baseTexture.Sample(materialSampler, input.uv);
    float3 lighting = lightTexture.Sample(materialSampler, input.lightUV).rgb;
    return float4(base.rgb * lighting * tint.rgb, base.a);
}

// UnlitGeneric's base-texture modulation, with no shader-side sRGB conversion.
float4 unlitMain(VertexOutput input) : SV_Target0
{
    return baseTexture.Sample(materialSampler, input.uv) * tint;
}
