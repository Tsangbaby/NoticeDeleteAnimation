#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <stdio.h>
#include <string.h>

extern const char *NLDustMetalSource;

static int fail(NSString *message) {
    fprintf(stderr, "FAIL: %s\n", message.UTF8String);
    return 1;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2 || !NLDustMetalSource) return fail(@"missing shader input");
        NSData *raw = [NSData dataWithContentsOfFile:
                       [NSString stringWithUTF8String:argv[1]]];
        NSData *embedded = [NSData dataWithBytes:NLDustMetalSource
                                         length:strlen(NLDustMetalSource)];
        if (!raw || ![raw isEqualToData:embedded]) return fail(@"shader bytes differ");
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device) {
            fprintf(stderr, "NOTAVAILABLE: no macOS Metal device; runtime untested\n");
            return 77;  // Never masquerade as a successful pipeline test.
        }
        MTLCompileOptions *options = [MTLCompileOptions new];
        options.languageVersion = MTLLanguageVersion2_1;
        NSError *error = nil;
        id<MTLLibrary> library = [device newLibraryWithSource:
            [NSString stringWithUTF8String:NLDustMetalSource] options:options error:&error];
        if (!library) return fail(error.description ?: @"Metal source compile failed");
        MTLRenderPipelineDescriptor *desc = [MTLRenderPipelineDescriptor new];
        desc.vertexFunction = [library newFunctionWithName:@"nlDustVertex"];
        desc.fragmentFunction = [library newFunctionWithName:@"nlDustFragment"];
        if (!desc.vertexFunction || !desc.fragmentFunction)
            return fail(@"missing nlDustVertex/nlDustFragment");
        MTLRenderPipelineColorAttachmentDescriptor *a = desc.colorAttachments[0];
        a.pixelFormat = MTLPixelFormatBGRA8Unorm;
        a.blendingEnabled = YES;
        a.sourceRGBBlendFactor = MTLBlendFactorOne;
        a.destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        a.sourceAlphaBlendFactor = MTLBlendFactorOne;
        a.destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        error = nil;
        if (![device newRenderPipelineStateWithDescriptor:desc error:&error])
            return fail(error.description ?: @"Metal pipeline failed");
        puts("PASS: embedded source, entries and BGRA8 pipeline (no draw/readback)");
        return 0;
    }
}
