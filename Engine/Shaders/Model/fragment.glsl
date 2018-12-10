#version 330
#extension GL_ARB_texture_cube_map_array : enable

#define NR_POINT_LIGHTS 4

layout (std140) uniform PlayerTransformBlock {
    mat4 camera;
    mat4 projection;
    mat4 cameraProjection;
    mat4 inverseTransposeProjection;
    vec3 position;
    vec2 noiseScale;
} playerTransforms;

struct LightSource
{
    mat4 shadowMatrices[6];
    mat4 lightSpaceMatrix;
    vec3 position;
    float farPlanePoint;
    vec3 color;
    int type; //1 Directional, 2 point
};

layout (std140) uniform LightSourceBlock
{
    LightSource lights[NR_POINT_LIGHTS];
} LightSources;

layout (std140) uniform MaterialInformationBlock {
    vec3 ambient;
    float shininess;
    vec3 diffuse;
    int isMap; 	//using the last 4, ambient=8, diffuse=4, specular=2, opacity = 1
} material;

in VS_FS {
    vec3 boneColor;
    vec2 textureCoord;
    vec3 normal;
    vec3 fragPos;
    vec4 fragPosLightSpace[NR_POINT_LIGHTS];
} from_vs;

out vec4 finalColor;

uniform sampler2DArray shadowSamplerDirectional;
uniform samplerCubeArray shadowSamplerPoint;
uniform sampler2D ssaoSampler;
uniform sampler2D ssaoNoiseSampler;

uniform sampler2D ambientSampler;
uniform sampler2D diffuseSampler;
uniform sampler2D specularSampler;
uniform sampler2D opacitySampler;
uniform sampler2D normalSampler;

vec3 pointSampleOffsetDirections[20] = vec3[]
(
   vec3( 1,  1,  1), vec3( 1, -1,  1), vec3(-1, -1,  1), vec3(-1,  1,  1),
   vec3( 1,  1, -1), vec3( 1, -1, -1), vec3(-1, -1, -1), vec3(-1,  1, -1),
   vec3( 1,  1,  0), vec3( 1, -1,  0), vec3(-1, -1,  0), vec3(-1,  1,  0),
   vec3( 1,  0,  1), vec3(-1,  0,  1), vec3( 1,  0, -1), vec3(-1,  0, -1),
   vec3( 0,  1,  1), vec3( 0, -1,  1), vec3( 0, -1, -1), vec3( 0,  1, -1)
);

uniform vec3 ssaoKernel[128];
uniform int ssaoSampleCount;

float ShadowCalculationDirectional(vec4 fragPosLightSpace, float bias, float lightIndex){
    // perform perspective divide
    vec3 projectedCoordinates = fragPosLightSpace.xyz / fragPosLightSpace.w;
    // Transform to [0,1] range
    projectedCoordinates = projectedCoordinates * 0.5 + 0.5;
    // Get closest depth value from light's perspective (using [0,1] range fragPosLightSpace as coords)
    float closestDepth = texture(shadowSamplerDirectional, vec3(projectedCoordinates.xy, lightIndex)).r;
    // Get depth of current fragment from light's perspective
    float currentDepth = projectedCoordinates.z;
    float shadow = 0.0;
    if(currentDepth < 1.0){
        vec2 texelSize = 1.0 / textureSize(shadowSamplerDirectional, 0).xy;
        for(int x = -1; x <= 1; ++x){
            for(int y = -1; y <= 1; ++y){
                float pcfDepth = texture(shadowSamplerDirectional, vec3(projectedCoordinates.xy + vec2(x, y) * texelSize, lightIndex)).r;
                if(currentDepth + bias > pcfDepth) {
                    shadow += 1.0;
                }
            }
        }
        shadow /= 9.0;
    }

    return shadow;
}

float ShadowCalculationPoint(vec3 fragPos, float bias, float viewDistance, int lightIndex)
{
    // get vector between fragment position and light position
    vec3 fragToLight = fragPos - LightSources.lights[lightIndex].position;
    // use the light to fragment vector to sample from the depth map
    float closestDepth = texture(shadowSamplerPoint, vec4(fragToLight, lightIndex)).r;
    // it is currently in linear range between [0,1]. Re-transform back to original value
    closestDepth *= LightSources.lights[lightIndex].farPlanePoint;
    // now get current linear depth as the length between the fragment and light position
    float currentDepth = length(fragToLight);
    // now test for shadows
    float shadow = 0.0;
    int samples  = 20;
    float diskRadius = (1.0 + (viewDistance / LightSources.lights[lightIndex].farPlanePoint)) / 25.0;
    for(int i = 0; i < samples; ++i)
    {
        float closestDepth = texture(shadowSamplerPoint, vec4(fragToLight + pointSampleOffsetDirections[i] * diskRadius, lightIndex)).r;
        closestDepth *= LightSources.lights[lightIndex].farPlanePoint;   // Undo mapping [0;1]
        if(currentDepth + bias > closestDepth)
            shadow += 1.0;
    }
    shadow /= float(samples);

    return shadow;
}

vec3 calcViewSpacePos(vec3 screen) {
    vec4 temp = vec4(screen.x, screen.y, screen.z, 1);
    temp *= playerTransforms.inverseTransposeProjection;
    vec3 camera_space = temp.xyz / temp.w;
    return camera_space;
}

void main(void) {
        vec4 objectColor;
        if((material.isMap & 0x0004)!=0) {
            if((material.isMap & 0x0001)!=0) { //if there is a opacity map, and it with diffuse
                vec4 opacity = texture(opacitySampler, from_vs.textureCoord);
                if(opacity.a < 0.05) {
                    discard;
                }
                objectColor = texture(diffuseSampler, from_vs.textureCoord);
                objectColor.w =  opacity.a;//FIXME some other textures used x
            } else {
                objectColor = texture(diffuseSampler, from_vs.textureCoord);
                if(objectColor.a < 0.05) {
                    discard;
                }
            }
        } else {
            objectColor = vec4(material.diffuse, 1.0);
        }

        vec3 normal = from_vs.normal;

        if((material.isMap & 0x0010) != 0) {
            normal = -1 * vec3(texture(normalSampler, from_vs.textureCoord));
        }

        float occlusion = 0.0;

        if(length(playerTransforms.position - from_vs.fragPos) < 100) {
            vec3 randomVec = texture(ssaoNoiseSampler, from_vs.fragPos.xy * playerTransforms.noiseScale).xyz;

            vec3 tangent   = normalize(randomVec - normal * dot(randomVec, normal));
            vec3 bitangent = cross(normal, tangent);
            mat3 TBN       = mat3(tangent, bitangent, normal);

            float uRadius = 0.5f;
            for(int i = 0; i < ssaoSampleCount; ++i){
                // get sample position
                vec3 samplePosition = TBN * ssaoKernel[i]; // From tangent to view-space
                samplePosition = samplePosition * uRadius;
                samplePosition  += vec3(from_vs.fragPos);

                vec4 offset = vec4(samplePosition, 1.0);
                offset = playerTransforms.cameraProjection * offset;    // from view to clip-space
                offset.xyz /= offset.w;               // perspective divide
                offset.xyz  = offset.xyz * 0.5 + 0.5; // transform to range 0.0 - 1.0

                float sampleDepth = texture(ssaoSampler, offset.xy).r;

                vec3 realElement = calcViewSpacePos(vec3(offset.xy, sampleDepth));
                vec3 kernelElement = calcViewSpacePos(offset.xyz);

                float rangeCheck= abs(realElement.z - kernelElement.z) < 1 ? 1.0 : 0.0;
                occlusion += (realElement.z >= kernelElement.z ? 1.0 : 0.0) * rangeCheck;
            }

            occlusion = occlusion / ssaoSampleCount;
        }
        occlusion = 1 - occlusion;

        vec3 lightingColorFactor = (material.ambient + vec3(0.35, 0.35, 0.35)) * occlusion;
        if((material.isMap & 0x0008)!=0) {
            lightingColorFactor = vec3(texture(ambientSampler, from_vs.textureCoord));
        }

        float shadow;
        for(int i=0; i < NR_POINT_LIGHTS; ++i){
            if(LightSources.lights[i].type != 0) {
                // Diffuse Lighting
                vec3 lightDirectory;
                if(LightSources.lights[i].type == 1) {
                    lightDirectory = normalize(LightSources.lights[i].position);
                } else if(LightSources.lights[i].type == 2) {
                    lightDirectory = normalize(LightSources.lights[i].position - from_vs.fragPos);
                }
                float diffuseRate = max(dot(normal, lightDirectory), 0.0);
                // Specular
                vec3 viewDirectory = normalize(playerTransforms.position - from_vs.fragPos);
                vec3 reflectDirectory = reflect(-lightDirectory, normal);
                float specularRate = max(dot(viewDirectory, reflectDirectory), 0.0);
                if(specularRate != 0 && material.shininess != 0) {
                    specularRate = pow(specularRate, material.shininess);
                    //specularRate = specularRate * materialSpecular;//we should get specularMap to here
                } else {
                    specularRate = 0;
                }
                float viewDistance = length(playerTransforms.position - from_vs.fragPos);
                float bias = 0.0;
                if(LightSources.lights[i].type == 1) {//directional light
                    shadow = ShadowCalculationDirectional(from_vs.fragPosLightSpace[i], bias, i);
                } else if (LightSources.lights[i].type == 2){//point light
                    shadow = ShadowCalculationPoint(from_vs.fragPos, bias, viewDistance, i);
                }
                lightingColorFactor += ((1.0 - shadow) * (diffuseRate + specularRate) * LightSources.lights[i].color);
            }
        }
        finalColor = vec4(
        min(lightingColorFactor.x, 1.0),
        min(lightingColorFactor.y, 1.0),
        min(lightingColorFactor.z, 1.0),
        1.0) * objectColor;

}
