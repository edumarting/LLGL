/*
 * MTEncoderScheduler.mm
 * 
 * This file is part of the "LLGL" project (Copyright (c) 2015-2018 by Lukas Hermanns)
 * See "LICENSE.txt" for license information.
 */

#include "MTEncoderScheduler.h"
#include <LLGL/GraphicsPipelineFlags.h>
#include <algorithm>


namespace LLGL
{

    
void MTEncoderScheduler::Reset(id<MTLCommandBuffer> cmdBuffer)
{
    cmdBuffer_ = cmdBuffer;
    ResetRenderEncoderState();
}

void MTEncoderScheduler::Flush()
{
    if (renderEncoder_ != nil)
    {
        [renderEncoder_ endEncoding];
        renderEncoder_ = nil;
    }
    else if (computeEncoder_ != nil)
    {
        [computeEncoder_ endEncoding];
        computeEncoder_ = nil;
    }
    else if (blitEncoder_ != nil)
    {
        [blitEncoder_ endEncoding];
        blitEncoder_ = nil;
    }
}

id<MTLRenderCommandEncoder> MTEncoderScheduler::BindRenderEncoder(MTLRenderPassDescriptor* renderPassDesc, bool primaryRenderPass)
{
    Flush();
    renderEncoder_ = [cmdBuffer_ renderCommandEncoderWithDescriptor:renderPassDesc];

    if (primaryRenderPass)
    {
        /* Store descriptor for primary render pass */
        renderPassDesc_ = renderPassDesc;

        /* Reset pipeline states (must be reset within Begin/EndRenderPass) */
        renderEncoderState_.renderPipelineState = nil;
        renderEncoderState_.depthStencilState   = nil;
    }

    SubmitRenderEncoderState();
    return renderEncoder_;
}

id<MTLComputeCommandEncoder> MTEncoderScheduler::BindComputeEncoder()
{
    if (computeEncoder_ == nil)
    {
        Flush();
        computeEncoder_ = [cmdBuffer_ computeCommandEncoder];
    }
    return computeEncoder_;
}

id<MTLBlitCommandEncoder> MTEncoderScheduler::BindBlitEncoder()
{
    if (blitEncoder_ == nil)
    {
        Flush();
        blitEncoder_ = [cmdBuffer_ blitCommandEncoder];
    }
    return blitEncoder_;
}

MTLRenderPassDescriptor* MTEncoderScheduler::CopyRenderPassDesc()
{
    return (MTLRenderPassDescriptor*)[renderPassDesc_ copy];
}

static void Convert(MTLViewport& dst, const Viewport& src)
{
    const double scaling = 1.0;//2.0 for retina display
    dst.originX = static_cast<double>(src.x)*scaling;
    dst.originY = static_cast<double>(src.y)*scaling;
    dst.width   = static_cast<double>(src.width)*scaling;
    dst.height  = static_cast<double>(src.height)*scaling;
    dst.znear   = static_cast<double>(src.minDepth);
    dst.zfar    = static_cast<double>(src.maxDepth);
}

void MTEncoderScheduler::SetViewports(const Viewport* viewports, NSUInteger viewportCount)
{
    /* Convert and store viewports */
    renderEncoderState_.viewportCount = std::min(viewportCount, NSUInteger(LLGL_MAX_NUM_VIEWPORTS_AND_SCISSORS));
    for (std::uint32_t i = 0; i < renderEncoderState_.viewportCount; ++i)
        Convert(renderEncoderState_.viewports[i], viewports[i]);

    /* Submit viewports to encoder */
    if (renderEncoder_ != nil)
    {
        [renderEncoder_
            setViewports:   renderEncoderState_.viewports
            count:          renderEncoderState_.viewportCount
        ];
    }
}

static void Convert(MTLScissorRect& dst, const Scissor& scissor)
{
    dst.x       = static_cast<NSUInteger>(std::max(0, scissor.x));
    dst.y       = static_cast<NSUInteger>(std::max(0, scissor.y));
    dst.width   = static_cast<NSUInteger>(std::max(0, scissor.width));
    dst.height  = static_cast<NSUInteger>(std::max(0, scissor.height));
}

void MTEncoderScheduler::SetScissorRects(const Scissor* scissors, NSUInteger scissorCount)
{
    /* Convert and store scissor rects */
    renderEncoderState_.scissorRectCount = std::min(scissorCount, NSUInteger(LLGL_MAX_NUM_VIEWPORTS_AND_SCISSORS));
    for (std::uint32_t i = 0; i < renderEncoderState_.scissorRectCount; ++i)
        Convert(renderEncoderState_.scissorRects[i], scissors[i]);

    /* Submit scissor rects to encoder */
    if (renderEncoder_ != nil)
    {
        [renderEncoder_
            setScissorRects:    renderEncoderState_.scissorRects
            count:              renderEncoderState_.scissorRectCount
        ];
    }
}

void MTEncoderScheduler::SetVertexBuffer(id<MTLBuffer> buffer, NSUInteger offset)
{
    /* Store reference to buffer */
    renderEncoderState_.vertexBuffers[0]            = buffer;
    renderEncoderState_.vertexBufferOffsets[0]      = offset;
    renderEncoderState_.vertexBufferRange.location  = 0;
    renderEncoderState_.vertexBufferRange.length    = 1;

    /* Subtmit vertex buffer to encoder */
    if (renderEncoder_ != nil)
    {
        [renderEncoder_
            setVertexBuffer:    buffer
            offset:             offset
            atIndex:            0
        ];
    }
}

void MTEncoderScheduler::SetVertexBuffers(const id<MTLBuffer>* buffers, const NSUInteger* offsets, NSUInteger bufferCount)
{
    /* Store reference to buffers */
    std::copy(buffers, buffers + bufferCount, renderEncoderState_.vertexBuffers);
    std::copy(offsets, offsets + bufferCount, renderEncoderState_.vertexBufferOffsets);

    renderEncoderState_.vertexBufferRange.location  = 0;
    renderEncoderState_.vertexBufferRange.length    = bufferCount;

    /* Subtmit vertex buffers to encoder */
    if (renderEncoder_ != nil)
    {
        [renderEncoder_
            setVertexBuffers:   renderEncoderState_.vertexBuffers
            offsets:            renderEncoderState_.vertexBufferOffsets
            withRange:          renderEncoderState_.vertexBufferRange
        ];
    }
}

void MTEncoderScheduler::SetRenderPipelineState(id<MTLRenderPipelineState> renderPipelineState)
{
    /* Store render pipeline state */
    renderEncoderState_.renderPipelineState = renderPipelineState;

    /* Submit render pipeline state to encoder */
    if (renderEncoder_ != nil)
        [renderEncoder_ setRenderPipelineState:renderPipelineState];
}

void MTEncoderScheduler::SetDepthStencilState(id<MTLDepthStencilState> depthStencilState)
{
    /* Store depth-stencil state */
    renderEncoderState_.depthStencilState = depthStencilState;

    /* Submit depth-stencil state to encoder */
    if (renderEncoder_ != nil)
        [renderEncoder_ setDepthStencilState:depthStencilState];
}


/*
 * ======= Private: =======
 */

void MTEncoderScheduler::SubmitRenderEncoderState()
{
    if (renderEncoder_ != nil)
    {
        if (renderEncoderState_.viewportCount > 0)
        {
            [renderEncoder_
                setViewports:   renderEncoderState_.viewports
                count:          renderEncoderState_.viewportCount
            ];
        }
        if (renderEncoderState_.scissorRectCount > 0)
        {
            [renderEncoder_
                setScissorRects:    renderEncoderState_.scissorRects
                count:              renderEncoderState_.scissorRectCount
            ];
        }
        if (renderEncoderState_.vertexBufferRange.length > 0)
        {
            [renderEncoder_
                setVertexBuffers:   renderEncoderState_.vertexBuffers
                offsets:            renderEncoderState_.vertexBufferOffsets
                withRange:          renderEncoderState_.vertexBufferRange
            ];
        }
        if (renderEncoderState_.renderPipelineState != nil)
            [renderEncoder_ setRenderPipelineState:renderEncoderState_.renderPipelineState];
        if (renderEncoderState_.depthStencilState != nil)
            [renderEncoder_ setDepthStencilState:renderEncoderState_.depthStencilState];
    }
}

void MTEncoderScheduler::ResetRenderEncoderState()
{
    renderEncoderState_.viewportCount               = 0;
    renderEncoderState_.scissorRectCount            = 0;
    renderEncoderState_.vertexBufferRange.length    = 0;
    renderEncoderState_.renderPipelineState         = nil;
    renderEncoderState_.depthStencilState           = nil;
}


} // /namespace LLGL



// ================================================================================