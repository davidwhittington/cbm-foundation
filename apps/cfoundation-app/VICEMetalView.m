/* VICEMetalView.m
 * MTKView subclass and Metal rendering pipeline for c=foundation.
 * Ported from EmulatorMetalView.m in fuji-foundation.
 *
 * Pixel format: VICE outputs ARGB8888; we load it as MTLPixelFormatBGRA8Unorm
 * (Metal's native BGRA). The byte order swap is handled automatically because
 * Metal interprets BGRA8Unorm as B=byte0,G=byte1,R=byte2,A=byte3 in memory,
 * which matches ARGB stored as A=byte0,R=byte1,G=byte2,B=byte3 on little-endian.
 * If colors appear wrong, add a channel-swap pass in the fragment shader.
 */

#import "VICEMetalView.h"
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <os/lock.h>

// Fragment params struct — must match Shaders.metal
typedef struct {
    float brightness;
    float saturation;
    float contrast;
    uint32_t scanlinesEnabled;
    float scanlineTransparency;
    uint32_t crtCurvatureEnabled;
    float pad;
} VICEFragParams;

// MARK: - Double-buffer state

typedef struct {
    uint32_t *pixels;
    NSInteger width;
    NSInteger height;
    NSInteger rowPitch;
    BOOL      dirty;
} VICEFrameBuffer;

@implementation VICEMetalView {
    id<MTLDevice>              _device;
    id<MTLCommandQueue>        _commandQueue;
    id<MTLRenderPipelineState> _pipelineState;
    id<MTLBuffer>              _fragmentParamsBuffer;
    id<MTLTexture>             _texture;

    // Double-buffer: VICE thread writes to _back, render thread reads from _front
    VICEFrameBuffer _front;
    VICEFrameBuffer _back;
    os_unfair_lock  _bufferLock;

    NSInteger _texWidth;
    NSInteger _texHeight;
}

// MARK: - Init

- (instancetype)initWithFrame:(CGRect)frame {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    self = [super initWithFrame:frame device:device];
    if (!self) return nil;
    [self _setup];
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (!self) return nil;
    self.device = MTLCreateSystemDefaultDevice();
    [self _setup];
    return self;
}

- (void)_setup {
    _device = self.device;
    NSAssert(_device, @"Metal is not supported on this device");

    _commandQueue = [_device newCommandQueue];
    _bufferLock   = OS_UNFAIR_LOCK_INIT;

    // Defaults
    _emulatorResolution      = CGSizeMake(384, 272);
    _scanlinesEnabled        = NO;
    _scanlineTransparency    = 0.72f;
    _crtCurvatureEnabled     = NO;
    _linearFilterEnabled     = NO;
    _brightness              = 1.0f;
    _saturation              = 1.0f;
    _contrast                = 1.0f;

    // MTKView settings
    self.framebufferOnly     = YES;
    self.colorPixelFormat    = MTLPixelFormatBGRA8Unorm;
    self.clearColor          = MTLClearColorMake(0, 0, 0, 1);
    self.enableSetNeedsDisplay = NO;  // driven by VICE frame delivery
    self.delegate            = self;

    [self _buildPipeline];
    [self _allocFragmentParamsBuffer];
}

// MARK: - Pipeline

- (void)_buildPipeline {
    NSError *error = nil;
    id<MTLLibrary> lib = [_device newDefaultLibrary];
    if (!lib) {
        NSLog(@"[VICEMetalView] Could not load default Metal library");
        return;
    }

    id<MTLFunction> vertFn = [lib newFunctionWithName:@"viceVertex"];
    id<MTLFunction> fragFn = [lib newFunctionWithName:@"viceFragment"];

    MTLRenderPipelineDescriptor *desc = [MTLRenderPipelineDescriptor new];
    desc.vertexFunction                              = vertFn;
    desc.fragmentFunction                            = fragFn;
    desc.colorAttachments[0].pixelFormat             = self.colorPixelFormat;

    _pipelineState = [_device newRenderPipelineStateWithDescriptor:desc error:&error];
    if (!_pipelineState) {
        NSLog(@"[VICEMetalView] Pipeline creation failed: %@", error);
    }
}

- (void)_allocFragmentParamsBuffer {
    _fragmentParamsBuffer = [_device newBufferWithLength:sizeof(VICEFragParams)
                                                 options:MTLResourceStorageModeShared];
}

- (void)_updateFragmentParams {
    VICEFragParams *p = (VICEFragParams *)_fragmentParamsBuffer.contents;
    p->brightness           = _brightness;
    p->saturation           = _saturation;
    p->contrast             = _contrast;
    p->scanlinesEnabled     = _scanlinesEnabled ? 1 : 0;
    p->scanlineTransparency = _scanlineTransparency;
    p->crtCurvatureEnabled  = _crtCurvatureEnabled ? 1 : 0;
    p->pad                  = 0;
}

// MARK: - Texture management

- (void)_ensureTextureWidth:(NSInteger)w height:(NSInteger)h {
    if (_texture && _texWidth == w && _texHeight == h) return;

    MTLTextureDescriptor *desc =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                           width:(NSUInteger)w
                                                          height:(NSUInteger)h
                                                       mipmapped:NO];
    desc.usage          = MTLTextureUsageShaderRead;
    desc.storageMode    = MTLStorageModeShared;
    _texture            = [_device newTextureWithDescriptor:desc];
    _texWidth           = w;
    _texHeight          = h;
}

// MARK: - Frame delivery (called from VICEDisplayManager, any thread)

- (void)presentFrame:(const uint32_t *)pixels
               width:(NSInteger)width
              height:(NSInteger)height
            rowPitch:(NSInteger)rowPitch {
    os_unfair_lock_lock(&_bufferLock);

    // Grow backing buffer if needed
    NSInteger neededBytes = rowPitch * height;
    if (!_back.pixels ||
        _back.width != width || _back.height != height) {
        free(_back.pixels);
        _back.pixels = malloc((size_t)neededBytes);
    }
    memcpy(_back.pixels, pixels, (size_t)neededBytes);
    _back.width    = width;
    _back.height   = height;
    _back.rowPitch = rowPitch;
    _back.dirty    = YES;

    os_unfair_lock_unlock(&_bufferLock);

    // Tell MTKView to render next frame
    dispatch_async(dispatch_get_main_queue(), ^{
        [self setNeedsDisplay:YES];
    });
}

// MARK: - MTKViewDelegate

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {}

- (void)drawInMTKView:(MTKView *)view {
    // Swap buffers
    os_unfair_lock_lock(&_bufferLock);
    VICEFrameBuffer tmp = _front;
    _front  = _back;
    _back   = tmp;
    _back.dirty = NO;
    os_unfair_lock_unlock(&_bufferLock);

    if (!_front.dirty || !_front.pixels) return;

    // Upload pixel data to texture
    [self _ensureTextureWidth:_front.width height:_front.height];
    MTLRegion region = MTLRegionMake2D(0, 0,
                                       (NSUInteger)_front.width,
                                       (NSUInteger)_front.height);
    [_texture replaceRegion:region
                mipmapLevel:0
                  withBytes:_front.pixels
                bytesPerRow:(NSUInteger)_front.rowPitch];

    // Render
    MTLRenderPassDescriptor *rpd = view.currentRenderPassDescriptor;
    if (!rpd) return;

    id<MTLCommandBuffer>        cmd     = [_commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [cmd renderCommandEncoderWithDescriptor:rpd];

    [encoder setRenderPipelineState:_pipelineState];
    [encoder setFragmentTexture:_texture atIndex:0];

    [self _updateFragmentParams];
    [encoder setFragmentBuffer:_fragmentParamsBuffer offset:0 atIndex:0];

    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip
                vertexStart:0
                vertexCount:4];

    [encoder endEncoding];
    [cmd presentDrawable:view.currentDrawable];
    [cmd commit];

    _front.dirty = NO;
}

@end

// MARK: - C bridge

static VICEMetalView *gMetalView = nil;

void Vice_MetalViewCreate(void *nsWindow, int width, int height) {
    dispatch_sync(dispatch_get_main_queue(), ^{
        NSWindow *window = (__bridge NSWindow *)nsWindow;
        CGRect frame = CGRectMake(0, 0, width, height);
        gMetalView = [[VICEMetalView alloc] initWithFrame:frame];
        gMetalView.emulatorResolution = CGSizeMake(width, height);
        window.contentView = gMetalView;
    });
}

void Vice_MetalPresent(const uint32_t *argbPixels,
                       int width, int height, int rowPitch) {
    [gMetalView presentFrame:argbPixels width:width height:height rowPitch:rowPitch];
}

void Vice_MetalSetScanlines(int enabled) {
    dispatch_async(dispatch_get_main_queue(), ^{
        gMetalView.scanlinesEnabled = (enabled != 0);
    });
}

void Vice_MetalSetScanlineTransparency(double transparency) {
    dispatch_async(dispatch_get_main_queue(), ^{
        gMetalView.scanlineTransparency = (float)transparency;
    });
}

void Vice_MetalSetLinearFilter(int enabled) {
    dispatch_async(dispatch_get_main_queue(), ^{
        gMetalView.linearFilterEnabled = (enabled != 0);
    });
}

void Vice_MetalViewDestroy(void) {
    dispatch_sync(dispatch_get_main_queue(), ^{
        gMetalView = nil;
    });
}
