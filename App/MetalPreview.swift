import MetalKit

final class MetalPreview {
    private struct Vertex {
        let position: SIMD2<Float>
        let uv: SIMD2<Float>
        let lightUV: SIMD2<Float>
    }

    private struct Constants {
        var transform: SIMD4<Float>
        var tint: SIMD4<Float>
    }

    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let depth: MTLDepthStencilState
    private let vertices: MTLBuffer
    private let indices: MTLBuffer
    private let baseTexture: MTLTexture
    private let lightTexture: MTLTexture
    private let sampler: MTLSamplerState
    private var position = SIMD2<Float>.zero
    private var rotation: Float = 0
    private var lastFrame: CFTimeInterval?

    init(view: MTKView) throws {
        guard let device = view.device,
              let queue = device.makeCommandQueue(),
              let libraryURL = Bundle.main.url(forResource: "LightmappedPreview",
                                               withExtension: "metallib") else {
            throw PreviewError.resources
        }
        self.queue = queue

        let library = try device.makeLibrary(URL: libraryURL)
        guard let vertex = library.makeFunction(name: "lightmappedVertex"),
              let fragment = library.makeFunction(name: "lightmappedFragment") else {
            throw PreviewError.resources
        }

        let layout = MTLVertexDescriptor()
        for attribute in 0..<3 {
            layout.attributes[attribute].format = .float2
            layout.attributes[attribute].offset = attribute * MemoryLayout<SIMD2<Float>>.stride
            layout.attributes[attribute].bufferIndex = 0
        }
        layout.layouts[0].stride = MemoryLayout<Vertex>.stride

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.vertexDescriptor = layout
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        descriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
        descriptor.rasterSampleCount = view.sampleCount
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)

        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .lessEqual
        depthDescriptor.isDepthWriteEnabled = true
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear

        let mesh = [
            Vertex(position: [-0.55, -0.55], uv: [0, 1], lightUV: [0, 1]),
            Vertex(position: [ 0.55, -0.55], uv: [1, 1], lightUV: [1, 1]),
            Vertex(position: [ 0.55,  0.55], uv: [1, 0], lightUV: [1, 0]),
            Vertex(position: [-0.55,  0.55], uv: [0, 0], lightUV: [0, 0]),
        ]
        let elements: [UInt16] = [0, 1, 2, 0, 2, 3]
        guard let vertices = mesh.withUnsafeBytes({ bytes in
            bytes.baseAddress.flatMap { device.makeBuffer(bytes: $0, length: bytes.count) }
        }), let indices = elements.withUnsafeBytes({ bytes in
            bytes.baseAddress.flatMap { device.makeBuffer(bytes: $0, length: bytes.count) }
        }), let depth = device.makeDepthStencilState(descriptor: depthDescriptor),
            let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
            throw PreviewError.resources
        }
        self.vertices = vertices
        self.indices = indices
        self.depth = depth
        self.sampler = sampler

        baseTexture = try Self.makeTexture(device, [
            242, 152, 58, 255, 196, 77, 35, 255,
            196, 77, 35, 255, 242, 152, 58, 255,
        ])
        lightTexture = try Self.makeTexture(device, [
            255, 255, 245, 255, 162, 172, 199, 255,
            91, 108, 156, 255, 219, 201, 173, 255,
        ])
    }

    func draw(in view: MTKView, input: SourceInput) {
        let now = CACurrentMediaTime()
        let delta = Float(min(now - (lastFrame ?? now), 0.05))
        lastFrame = now
        position.x = max(-0.85, min(0.85, position.x + input.moveRight * delta))
        position.y = max(-0.7, min(0.7, position.y + input.moveForward * delta))
        rotation = (rotation + input.lookRight * 3 + input.lookDown).truncatingRemainder(dividingBy: 2 * .pi)

        let size = view.drawableSize
        guard size.width > 0, size.height > 0,
              let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commands = queue.makeCommandBuffer(),
              let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }

        var constants = Constants(
            transform: [position.x, position.y, Float(size.height / size.width), rotation],
            tint: input.held.contains(.attack) || input.pressed.contains(.attack)
                ? [1.3, 1.1, 0.7, 1] : [1, 1, 1, 1]
        )
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depth)
        encoder.setVertexBuffer(vertices, offset: 0, index: 0)
        encoder.setVertexBytes(&constants, length: MemoryLayout<Constants>.stride, index: 3)
        encoder.setFragmentBytes(&constants, length: MemoryLayout<Constants>.stride, index: 3)
        encoder.setFragmentTexture(baseTexture, index: 0)
        encoder.setFragmentTexture(lightTexture, index: 1)
        encoder.setFragmentSamplerState(sampler, index: 2)
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: 6, indexType: .uint16,
                                      indexBuffer: indices, indexBufferOffset: 0)
        encoder.endEncoding()
        commands.present(drawable)
        commands.commit()
    }

    private static func makeTexture(_ device: MTLDevice, _ pixels: [UInt8]) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 2, height: 2, mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw PreviewError.resources }
        pixels.withUnsafeBytes { bytes in
            if let address = bytes.baseAddress {
                texture.replace(region: MTLRegionMake2D(0, 0, 2, 2), mipmapLevel: 0,
                                withBytes: address, bytesPerRow: 8)
            }
        }
        return texture
    }

    private enum PreviewError: LocalizedError {
        case resources

        var errorDescription: String? {
            "Не удалось загрузить ресурсы Metal. Проверьте сборку шейдеров для этого SDK."
        }
    }
}
