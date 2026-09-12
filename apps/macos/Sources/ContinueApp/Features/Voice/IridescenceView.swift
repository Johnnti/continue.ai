import MetalKit
import SwiftUI

struct IridescenceView: NSViewRepresentable {
    let level: Double
    let tint: SIMD3<Float>
    let isAnimated: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.wantsLayer = true
        view.layer?.isOpaque = false
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = !isAnimated
        view.isPaused = !isAnimated
        context.coordinator.configure(view: view)
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator.level = Float(min(max(level, 0.08), 1))
        context.coordinator.tint = tint
        view.enableSetNeedsDisplay = !isAnimated
        view.isPaused = !isAnimated
        if !isAnimated {
            view.setNeedsDisplay(view.bounds)
        }
    }

    @MainActor
    final class Coordinator: NSObject, MTKViewDelegate {
        private var commandQueue: MTLCommandQueue?
        private var pipeline: MTLRenderPipelineState?
        private var startTime = CACurrentMediaTime()
        var level: Float = 0.08
        var tint = SIMD3<Float>(0.30, 0.62, 1.0)

        func configure(view: MTKView) {
            guard let device = view.device,
                  let commandQueue = device.makeCommandQueue()
            else { return }

            do {
                let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.vertexFunction = library.makeFunction(name: "iridescenceVertex")
                descriptor.fragmentFunction = library.makeFunction(name: "iridescenceFragment")
                descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
                descriptor.colorAttachments[0].isBlendingEnabled = true
                descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
                descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
                pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
                self.commandQueue = commandQueue
                view.delegate = self
            } catch {
                pipeline = nil
            }
        }

        func draw(in view: MTKView) {
            guard let pipeline,
                  let commandBuffer = commandQueue?.makeCommandBuffer(),
                  let descriptor = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable,
                  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
            else { return }

            var uniforms = Uniforms(
                time: Float(CACurrentMediaTime() - startTime),
                amplitude: 0.10 + level * 1.2,
                speed: 0.75 + level * 0.5,
                color: SIMD4<Float>(tint.x, tint.y, tint.z, 1),
                resolution: SIMD4<Float>(Float(max(view.drawableSize.width, 1)), Float(max(view.drawableSize.height, 1)), 0, 0),
                mouse: SIMD2<Float>(0.5, 0.5)
            )

            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        private struct Uniforms {
            var time: Float
            var amplitude: Float
            var speed: Float
            var padding: Float = 0
            var color: SIMD4<Float>
            var resolution: SIMD4<Float>
            var mouse: SIMD2<Float>
            var mousePadding: SIMD2<Float> = .zero
        }

        private static let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct Uniforms {
            float time;
            float amplitude;
            float speed;
            float padding;
            float4 color;
            float4 resolution;
            float2 mouse;
            float2 mousePadding;
        };

        struct VertexOut {
            float4 position [[position]];
            float2 uv;
        };

        vertex VertexOut iridescenceVertex(uint vertexID [[vertex_id]]) {
            constexpr float2 positions[3] = {
                float2(-1.0, -1.0),
                float2( 3.0, -1.0),
                float2(-1.0,  3.0)
            };
            VertexOut output;
            output.position = float4(positions[vertexID], 0.0, 1.0);
            output.uv = positions[vertexID] * 0.5 + 0.5;
            return output;
        }

        fragment float4 iridescenceFragment(
            VertexOut input [[stage_in]],
            constant Uniforms& uniforms [[buffer(0)]]) {
            float2 spherePosition = input.uv * 2.0 - 1.0;
            float radiusSquared = dot(spherePosition, spherePosition);
            float circleMask = 1.0 - smoothstep(0.94, 1.0, radiusSquared);
            if (circleMask <= 0.0) discard_fragment();

            float sphereZ = sqrt(max(0.0, 1.0 - radiusSquared));
            float3 normal = normalize(float3(spherePosition, sphereZ));
            float3 viewDirection = float3(0.0, 0.0, 1.0);
            float lightPhase = uniforms.time * (0.22 + uniforms.speed * 0.08);
            float3 lightDirection = normalize(float3(
                cos(lightPhase) * 0.62,
                sin(lightPhase * 0.73) * 0.54,
                0.78
            ));
            float diffuse = smoothstep(-0.28, 0.92, dot(normal, lightDirection));
            float3 halfVector = normalize(lightDirection + viewDirection);
            float specular = pow(max(dot(normal, halfVector), 0.0), 18.0);
            float fresnel = pow(1.0 - max(dot(normal, viewDirection), 0.0), 2.2);

            float mr = min(uniforms.resolution.x, uniforms.resolution.y);
            float2 uv = spherePosition * uniforms.resolution.xy / mr;
            uv += (uniforms.mouse - float2(0.5)) * uniforms.amplitude;
            uv += normal.xy * (0.08 + uniforms.amplitude * 0.05);

            float d = -uniforms.time * 0.5 * uniforms.speed;
            float a = 0.0;
            for (float i = 0.0; i < 8.0; ++i) {
                a += cos(i - d - a * uv.x);
                d += sin(uv.y * i + a);
            }
            d += uniforms.time * 0.5 * uniforms.speed;
            float3 col = float3(
                cos(uv * float2(d, a)) * 0.6 + 0.4,
                cos(a + d) * 0.5 + 0.5
            );
            col = cos(col * cos(float3(d, a, 2.5)) * 0.5 + 0.5) * uniforms.color.rgb;

            float shadowSide = 0.42 + diffuse * 0.58;
            float3 shadedColor = col * shadowSide;
            shadedColor += uniforms.color.rgb * fresnel * (0.52 + uniforms.amplitude * 0.16);
            shadedColor += mix(uniforms.color.rgb, float3(1.0), 0.35) * specular * (0.32 + uniforms.amplitude * 0.12);
            shadedColor += uniforms.color.rgb * pow(max(diffuse, 0.0), 5.0) * 0.12;

            return float4(clamp(shadedColor, 0.0, 1.0), circleMask);
        }
        """
    }
}
