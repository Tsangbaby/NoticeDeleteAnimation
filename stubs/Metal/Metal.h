#ifndef NL_STUB_METAL_H
#define NL_STUB_METAL_H
#include <Foundation/Foundation.h>
#include <UIKit/UIKit.h>

typedef enum { MTLPixelFormatRGBA8Unorm = 70, MTLPixelFormatBGRA8Unorm = 80 } MTLPixelFormat;
typedef enum { MTLStorageModeShared = 0, MTLStorageModeManaged = 1 } MTLStorageMode;
typedef enum { MTLTextureUsageShaderRead = 1, MTLTextureUsageShaderWrite = 2 } MTLTextureUsage;
typedef enum { MTLLoadActionDontCare = 0, MTLLoadActionLoad = 1, MTLLoadActionClear = 2 } MTLLoadAction;
typedef enum { MTLStoreActionDontCare = 0, MTLStoreActionStore = 1 } MTLStoreAction;
typedef enum { MTLPrimitiveTypePoint = 0, MTLPrimitiveTypeLine = 1, MTLPrimitiveTypeTriangle = 3 } MTLPrimitiveType;
typedef enum { MTLBlendFactorOne = 1, MTLBlendFactorOneMinusSourceAlpha = 5 } MTLBlendFactor;
typedef enum {
    MTLCommandBufferStatusNotEnqueued = 0,
    MTLCommandBufferStatusEnqueued = 1,
    MTLCommandBufferStatusCommitted = 2,
    MTLCommandBufferStatusScheduled = 3,
    MTLCommandBufferStatusCompleted = 4,
    MTLCommandBufferStatusError = 5,
} MTLCommandBufferStatus;
typedef enum { MTLLanguageVersion2_1 = 0x20001 } MTLLanguageVersion;

typedef struct { NSUInteger x, y, z; } MTLSize;
typedef struct { CGFloat red, green, blue, alpha; } MTLClearColor;
typedef struct { NSUInteger x, y, z; } MTLOrigin;
typedef struct { NSUInteger width, height, depth; } MTLSizeDims;
typedef struct { MTLOrigin origin; MTLSizeDims size; } MTLRegion;
MTLRegion MTLRegionMake2D(NSUInteger x, NSUInteger y, NSUInteger w, NSUInteger h);
MTLClearColor MTLClearColorMake(double r, double g, double b, double a);

@protocol MTLDevice;
@protocol MTLTexture;
@protocol MTLCommandBuffer;
@protocol MTLCommandQueue;
@protocol MTLRenderCommandEncoder;
@protocol MTLDrawable;
@protocol MTLCommandBuffer;
@protocol MTLLibrary;
@protocol MTLFunction;
@protocol MTLRenderPipelineState;

@interface MTLTextureDescriptor : NSObject
+ (instancetype)texture2DDescriptorWithPixelFormat:(MTLPixelFormat)fmt
                                             width:(NSUInteger)w
                                            height:(NSUInteger)h
                                         mipmapped:(BOOL)mip;
@property (nonatomic) MTLTextureUsage usage;
@property (nonatomic) MTLStorageMode storageMode;
@end

@protocol MTLTexture <NSObject>
- (void)replaceRegion:(MTLRegion)region mipmapLevel:(NSUInteger)level
            withBytes:(const void *)bytes bytesPerRow:(NSUInteger)bytesPerRow;
@end

@protocol MTLCommandBuffer <NSObject>
@property (nonatomic, readonly) MTLCommandBufferStatus status;
- (id<MTLRenderCommandEncoder>)renderCommandEncoderWithDescriptor:(id)desc;
- (void)presentDrawable:(id)drawable;
- (void)commit;
@end

@protocol MTLCommandQueue <NSObject>
- (id<MTLCommandBuffer>)commandBuffer;
@end



@interface MTLCompileOptions : NSObject
@property (nonatomic) MTLLanguageVersion languageVersion;
@end

@protocol MTLLibrary <NSObject>
- (id<MTLFunction>)newFunctionWithName:(NSString *)name;
@end

@interface MTLRenderPipelineColorAttachmentDescriptor : NSObject
@property (nonatomic) MTLPixelFormat pixelFormat;
@property (nonatomic, getter=isBlendingEnabled) BOOL blendingEnabled;
@property (nonatomic) MTLBlendFactor sourceRGBBlendFactor;
@property (nonatomic) MTLBlendFactor destinationRGBBlendFactor;
@property (nonatomic) MTLBlendFactor sourceAlphaBlendFactor;
@property (nonatomic) MTLBlendFactor destinationAlphaBlendFactor;
@end

@interface MTLRenderPipelineColorAttachmentDescriptorArray : NSObject
- (MTLRenderPipelineColorAttachmentDescriptor *)objectAtIndexedSubscript:(NSUInteger)idx;
@end

@interface MTLRenderPipelineDescriptor : NSObject
@property (nonatomic, strong) id<MTLFunction> vertexFunction;
@property (nonatomic, strong) id<MTLFunction> fragmentFunction;
@property (nonatomic, readonly) MTLRenderPipelineColorAttachmentDescriptorArray *colorAttachments;
@end

@interface MTLRenderPassColorAttachmentDescriptor : NSObject
@property (nonatomic, strong) id<MTLTexture> texture;
@property (nonatomic) MTLLoadAction loadAction;
@property (nonatomic) MTLStoreAction storeAction;
@property (nonatomic) MTLClearColor clearColor;
@end

@interface MTLRenderPassColorAttachmentDescriptorArray : NSObject
- (MTLRenderPassColorAttachmentDescriptor *)objectAtIndexedSubscript:(NSUInteger)idx;
@end

@interface MTLRenderPassDescriptor : NSObject
+ (instancetype)renderPassDescriptor;
@property (nonatomic, readonly) MTLRenderPassColorAttachmentDescriptorArray *colorAttachments;
@end

@protocol MTLRenderCommandEncoder <NSObject>
- (void)setRenderPipelineState:(id<MTLRenderPipelineState>)state;
- (void)setVertexBytes:(const void *)bytes length:(NSUInteger)len atIndex:(NSUInteger)idx;
- (void)setFragmentTexture:(id<MTLTexture>)tex atIndex:(NSUInteger)idx;
- (void)drawPrimitives:(MTLPrimitiveType)type vertexStart:(NSUInteger)start
           vertexCount:(NSUInteger)count instanceCount:(NSUInteger)instances;
- (void)endEncoding;
@end

@protocol MTLDevice <NSObject>
- (id<MTLLibrary>)newLibraryWithSource:(NSString *)src options:(MTLCompileOptions *)opt error:(NSError **)err;
- (id<MTLRenderPipelineState>)newRenderPipelineStateWithDescriptor:(MTLRenderPipelineDescriptor *)desc
                                                              error:(NSError **)err;
- (id<MTLCommandQueue>)newCommandQueue;
- (id<MTLTexture>)newTextureWithDescriptor:(MTLTextureDescriptor *)desc;
@end

id<MTLDevice> MTLCreateSystemDefaultDevice(void);
#endif
