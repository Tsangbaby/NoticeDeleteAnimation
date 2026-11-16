#include <metal_stdlib>
using namespace metal;
struct DustUniforms {
    float2 viewport;
    float2 origin;
    float2 cardSize;
    uint columns;
    uint rows;
    float time;
    float distance;
    float seed;
    float pad;
};
struct DustVertex {
    float4 position [[position]];
    float2 uv;
    float2 local;
    float fade;
    float breakage;
};
float dustHash(float2 v) {
    return fract(sin(dot(v, float2(127.1,311.7))) * 43758.5453);
}
float easeDust(float p) { return p*p*(3.0-2.0*p); }
vertex DustVertex nlDustVertex(uint vertexID [[vertex_id]], uint instanceID [[instance_id]],
                              constant DustUniforms& u [[buffer(0)]]) {
    const float2 corners[6] = {float2(0,0),float2(1,0),float2(0,1),
                              float2(1,0),float2(1,1),float2(0,1)};
    float2 cell = float2(instanceID % u.columns, instanceID / u.columns);
    float2 grid = float2(u.columns, u.rows);
    float2 unit = (cell+0.5)/grid;
    float2 corner = corners[vertexID];
    float2 noiseCell = cell + float2(u.seed, u.seed*0.371);
    float r = dustHash(noiseCell);
    float r2 = dustHash(noiseCell + 19.7);
    float r3 = dustHash(noiseCell + 72.3);
    // A noisy breakup front sweeps through the card. Until it reaches a tile,
    // the six vertices reproduce that exact tile of the original texture.
    float frontier = (1.0-unit.x)*0.25 + unit.y*0.075;
    float begin = frontier + r*0.095;
    float progress = clamp((u.time-begin)/(0.56 + 0.035*r2), 0.0, 1.0);
    float burst = smoothstep(0.0,0.18,progress);
    float motion = pow(progress,1.12);
    float dx = (0.62 + 1.05*r)*u.distance*motion;
    float dy = -(0.45 + 1.05*r2)*u.distance*motion
               + sin(progress*7.0+r3*6.283)*u.distance*0.13*motion;
    dx += (r2-0.5)*u.distance*0.40*motion;
    float2 tileSize = u.cardSize/grid;
    float shrink = mix(1.0, mix(0.24,0.56,r3), smoothstep(0.01,0.65,progress));
    float2 delta = (corner-0.5)*tileSize*shrink;
    float angle = (r3-0.5)*4.8*motion;
    float c=cos(angle),s=sin(angle);
    delta=float2(c*delta.x-s*delta.y,s*delta.x+c*delta.y);
    float2 p = u.origin + unit*u.cardSize + delta + float2(dx,dy);
    DustVertex out;
    out.position=float4(2.0*p.x/u.viewport.x-1.0,1.0-2.0*p.y/u.viewport.y,0,1);
    out.uv=(cell+corner)/grid;
    out.local=corner;
    out.fade=1.0-smoothstep(0.32+0.20*r2,1.0,progress);
    out.breakage=burst;
    return out;
}
fragment float4 nlDustFragment(DustVertex in [[stage_in]], texture2d<float> image [[texture(0)]]) {
    constexpr sampler sampleImage(coord::normalized,address::clamp_to_edge,filter::linear);
    float4 color=image.sample(sampleImage,in.uv);
    float roundDust=1.0-smoothstep(0.34,0.53,length(in.local-0.5));
    float shape=mix(1.0,roundDust,in.breakage);
    // CG bitmap pixels are premultiplied; opacity must scale RGB and alpha.
    return color*(in.fade*shape);
}

