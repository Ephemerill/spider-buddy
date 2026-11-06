// Accelerate stand-in for Windows: only the vDSP calls Beat.swift makes, with vDSP's conventions kept
// (including the real FFT's factor of 2 and its packed DC/Nyquist in element 0).
import Foundation

public typealias vDSP_Length = UInt
public typealias vDSP_Stride = Int
public typealias FFTRadix = Int32
public typealias FFTDirection = Int32
public let kFFTRadix2: Int32 = 0
public let FFT_FORWARD: Int32 = 1
public let FFT_INVERSE: Int32 = -1

public struct DSPSplitComplex {
    public var realp: UnsafeMutablePointer<Float>
    public var imagp: UnsafeMutablePointer<Float>
    public init(realp: UnsafeMutablePointer<Float>, imagp: UnsafeMutablePointer<Float>) { self.realp = realp; self.imagp = imagp }
}
public struct DSPComplex { public var real: Float; public var imag: Float; public init(real: Float, imag: Float) { self.real = real; self.imag = imag } }

public final class FFTSetupBox {
    let n: Int
    let cosT: [Float], sinT: [Float]
    var re: [Float], im: [Float]
    init(log2n: Int) {
        n = 1 << log2n
        cosT = (0..<(n / 2)).map { Float(cos(-2 * Double.pi * Double($0) / Double(1 << log2n))) }
        sinT = (0..<(n / 2)).map { Float(sin(-2 * Double.pi * Double($0) / Double(1 << log2n))) }
        re = [Float](repeating: 0, count: n)
        im = [Float](repeating: 0, count: n)
    }
    func forward() {
        var j = 0
        for i in 1..<n {
            var bit = n >> 1
            while j & bit != 0 { j ^= bit; bit >>= 1 }
            j ^= bit
            if i < j { re.swapAt(i, j); im.swapAt(i, j) }
        }
        var len = 2
        while len <= n {
            let half = len / 2, step = n / len
            var i = 0
            while i < n {
                for k in 0..<half {
                    let c = cosT[k * step], s = sinT[k * step]
                    let a = i + k, b = a + half
                    let tr = re[b] * c - im[b] * s, ti = re[b] * s + im[b] * c
                    re[b] = re[a] - tr; im[b] = im[a] - ti
                    re[a] += tr; im[a] += ti
                }
                i += len
            }
            len <<= 1
        }
    }
}
public typealias FFTSetup = FFTSetupBox

public func vDSP_create_fftsetup(_ log2n: vDSP_Length, _ radix: FFTRadix) -> FFTSetup? { FFTSetupBox(log2n: Int(log2n)) }
public func vDSP_destroy_fftsetup(_ s: FFTSetup?) {}

public func vDSP_ctoz(_ c: UnsafePointer<DSPComplex>, _ ic: vDSP_Stride, _ z: UnsafePointer<DSPSplitComplex>, _ iz: vDSP_Stride, _ n: vDSP_Length) {
    let raw = UnsafeRawPointer(c).assumingMemoryBound(to: Float.self)
    for i in 0..<Int(n) {
        z.pointee.realp[i * iz] = raw[i * ic]
        z.pointee.imagp[i * iz] = raw[i * ic + 1]
    }
}

/// Packed real FFT. Input: n/2 complex holding n reals. Output as vDSP: element 0 is (2·X0, 2·X(n/2)), others 2·Xk.
public func vDSP_fft_zrip(_ s: FFTSetup, _ z: UnsafePointer<DSPSplitComplex>, _ stride: vDSP_Stride, _ log2n: vDSP_Length, _ dir: FFTDirection) {
    let n = 1 << Int(log2n), half = n / 2
    for i in 0..<half {
        s.re[i * 2] = z.pointee.realp[i * stride]
        s.re[i * 2 + 1] = z.pointee.imagp[i * stride]
    }
    for i in 0..<n { s.im[i] = 0 }
    s.forward()
    z.pointee.realp[0] = 2 * s.re[0]
    z.pointee.imagp[0] = 2 * s.re[half]
    for k in 1..<half {
        z.pointee.realp[k * stride] = 2 * s.re[k]
        z.pointee.imagp[k * stride] = 2 * s.im[k]
    }
}

public func vDSP_vmul(_ a: UnsafePointer<Float>, _ ia: vDSP_Stride, _ b: UnsafePointer<Float>, _ ib: vDSP_Stride, _ c: UnsafeMutablePointer<Float>, _ ic: vDSP_Stride, _ n: vDSP_Length) {
    for i in 0..<Int(n) { c[i * ic] = a[i * ia] * b[i * ib] }
}
public func vDSP_measqv(_ a: UnsafePointer<Float>, _ ia: vDSP_Stride, _ r: UnsafeMutablePointer<Float>, _ n: vDSP_Length) {
    var s: Float = 0
    for i in 0..<Int(n) { s += a[i * ia] * a[i * ia] }
    r.pointee = n > 0 ? s / Float(n) : 0
}
public func vDSP_zvmags(_ z: UnsafePointer<DSPSplitComplex>, _ iz: vDSP_Stride, _ c: UnsafeMutablePointer<Float>, _ ic: vDSP_Stride, _ n: vDSP_Length) {
    for i in 0..<Int(n) {
        let r = z.pointee.realp[i * iz], m = z.pointee.imagp[i * iz]
        c[i * ic] = r * r + m * m
    }
}
public func vDSP_sve(_ a: UnsafePointer<Float>, _ ia: vDSP_Stride, _ r: UnsafeMutablePointer<Float>, _ n: vDSP_Length) {
    var s: Float = 0
    for i in 0..<Int(n) { s += a[i * ia] }
    r.pointee = s
}
public func vDSP_dotpr(_ a: UnsafePointer<Float>, _ ia: vDSP_Stride, _ b: UnsafePointer<Float>, _ ib: vDSP_Stride, _ r: UnsafeMutablePointer<Float>, _ n: vDSP_Length) {
    var s: Float = 0
    for i in 0..<Int(n) { s += a[i * ia] * b[i * ib] }
    r.pointee = s
}

public enum vDSP {
    public enum WindowSequence { case hanningDenormalized, hanningNormalized, hamming, blackman }
    public static func window(ofType: Float.Type, usingSequence s: WindowSequence, count: Int, isHalfWindow: Bool) -> [Float] {
        (0..<count).map { i in
            let t = 2 * Double.pi * Double(i) / Double(count)
            switch s {
            case .hanningDenormalized: return Float(0.5 * (1 - cos(t)))
            case .hanningNormalized: return Float(0.5 * (1 - cos(t)) * 1.63)
            case .hamming: return Float(0.54 - 0.46 * cos(t))
            case .blackman: return Float(0.42 - 0.5 * cos(t) + 0.08 * cos(2 * t))
            }
        }
    }
    public static func mean(_ v: [Float]) -> Float { v.isEmpty ? 0 : v.reduce(0, +) / Float(v.count) }
    public static func add(_ scalar: Float, _ v: [Float], result: inout [Float]) {
        for i in 0..<v.count { result[i] = v[i] + scalar }
    }
}
