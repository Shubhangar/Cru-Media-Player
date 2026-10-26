// Generates a 20 s 1280x720 H.264 + AAC test clip with a frame counter and a tone.
import AVFoundation
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.removeItem(at: out)
let w = 1280, h = 720, fps: Int32 = 30, seconds = 20
let writer = try! AVAssetWriter(outputURL: out, fileType: .mp4)

let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
  AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: vIn, sourcePixelBufferAttributes: [
  kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: w,
  kCVPixelBufferHeightKey as String: h])
let sampleRate = 44100.0
let aIn = AVAssetWriterInput(mediaType: .audio, outputSettings: [
  AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 96000])
writer.add(vIn); writer.add(aIn)
writer.startWriting(); writer.startSession(atSourceTime: .zero)

// 440 Hz tone, 1024-sample chunks.
var fmtDesc: CMAudioFormatDescription?
var asbd = AudioStreamBasicDescription(mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
  mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked, mBytesPerPacket: 2,
  mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0,
  magicCookie: nil, extensions: nil, formatDescriptionOut: &fmtDesc)
let chunk = 1024
var n = 0
func appendAudio(upTo limit: Int) {
while n < limit {
  while !aIn.isReadyForMoreMediaData { usleep(1000) }
  var samples = [Int16](repeating: 0, count: chunk)
  for k in 0..<chunk { samples[k] = Int16(sin(2 * .pi * 440 * Double(n + k) / sampleRate) * 6000) }
  var block: CMBlockBuffer?
  CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: chunk * 2, blockAllocator: nil,
    customBlockSource: nil, offsetToData: 0, dataLength: chunk * 2, flags: 0, blockBufferOut: &block)
  samples.withUnsafeBytes { CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block!, offsetIntoDestination: 0, dataLength: chunk * 2) }
  var sb: CMSampleBuffer?
  CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block!, formatDescription: fmtDesc!,
    sampleCount: chunk, presentationTimeStamp: CMTime(value: CMTimeValue(n), timescale: CMTimeScale(sampleRate)),
    packetDescriptions: nil, sampleBufferOut: &sb)
  aIn.append(sb!)
  n += chunk
}
}
let total = Int(fps) * seconds
for i in 0..<total {
  while !vIn.isReadyForMoreMediaData { usleep(1000) }
  var pb: CVPixelBuffer?
  CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
  CVPixelBufferLockBaseAddress(pb!, [])
  let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb!), width: w, height: h, bitsPerComponent: 8,
    bytesPerRow: CVPixelBufferGetBytesPerRow(pb!), space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
  let hue = CGFloat(i % 300) / 300
  ctx.setFillColor(NSColor(hue: hue, saturation: 0.5, brightness: 0.35, alpha: 1).cgColor)
  ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
  ctx.setFillColor(NSColor.white.cgColor)
  ctx.fill(CGRect(x: CGFloat(i) / CGFloat(total) * CGFloat(w - 80), y: 330, width: 80, height: 60))
  NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
  let text = String(format: "%02d.%02d  frame %d", i / Int(fps), i % Int(fps), i) as NSString
  text.draw(at: NSPoint(x: 60, y: 560), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 64, weight: .bold), .foregroundColor: NSColor.white])
  CVPixelBufferUnlockBaseAddress(pb!, [])
  adaptor.append(pb!, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: fps))
  appendAudio(upTo: Int(sampleRate) * (i + 1) / Int(fps))
}
vIn.markAsFinished()
aIn.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
print(writer.status == .completed ? "ok \(out.path)" : "failed \(String(describing: writer.error))")
