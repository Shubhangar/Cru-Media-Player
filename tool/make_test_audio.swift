// Generates an 8 s AAC .m4a test track with title/artist/album tags and
// embedded cover art.   Usage: swift tool/make_test_audio.swift out.m4a
import AVFoundation
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.removeItem(at: out)
let writer = try! AVAssetWriter(outputURL: out, fileType: .m4a)

func item(_ id: AVMetadataIdentifier, _ value: NSCopying & NSObjectProtocol) -> AVMetadataItem {
  let m = AVMutableMetadataItem()
  m.identifier = id
  m.value = value
  return m
}

// Cover: orange square with a cone-ish triangle.
let size = 300
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor(red: 1, green: 0.4, blue: 0, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()
let tri = NSBezierPath()
tri.move(to: NSPoint(x: 150, y: 250)); tri.line(to: NSPoint(x: 240, y: 50)); tri.line(to: NSPoint(x: 60, y: 50)); tri.close()
NSColor.white.setFill(); tri.fill()
NSGraphicsContext.current = nil
let png = rep.representation(using: .png, properties: [:])!

writer.metadata = [
  item(.commonIdentifierTitle, "Cone Test Tone" as NSString),
  item(.commonIdentifierArtist, "The Cones" as NSString),
  item(.commonIdentifierAlbumName, "Traffic Sessions" as NSString),
  item(.commonIdentifierArtwork, png as NSData),
]

let sampleRate = 44100.0, seconds = 8
let aIn = AVAssetWriterInput(mediaType: .audio, outputSettings: [
  AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1,
  AVEncoderBitRateKey: 96000])
writer.add(aIn)
writer.startWriting(); writer.startSession(atSourceTime: .zero)

var fmt: CMAudioFormatDescription?
var asbd = AudioStreamBasicDescription(mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
  mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked, mBytesPerPacket: 2,
  mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0,
  magicCookie: nil, extensions: nil, formatDescriptionOut: &fmt)
let chunk = 1024
var n = 0
while n < Int(sampleRate) * seconds {
  while !aIn.isReadyForMoreMediaData { usleep(1000) }
  var s = [Int16](repeating: 0, count: chunk)
  for k in 0..<chunk {
    let t = Double(n + k) / sampleRate
    // Amplitude swells each second so the waveform has visible shape.
    let env = 0.25 + 0.75 * abs(sin(.pi * t))
    s[k] = Int16(sin(2 * .pi * 330 * t) * 9000 * env)
  }
  var block: CMBlockBuffer?
  CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: chunk * 2, blockAllocator: nil,
    customBlockSource: nil, offsetToData: 0, dataLength: chunk * 2, flags: 0, blockBufferOut: &block)
  s.withUnsafeBytes { CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block!, offsetIntoDestination: 0, dataLength: chunk * 2) }
  var sb: CMSampleBuffer?
  CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block!, formatDescription: fmt!,
    sampleCount: chunk, presentationTimeStamp: CMTime(value: CMTimeValue(n), timescale: CMTimeScale(sampleRate)),
    packetDescriptions: nil, sampleBufferOut: &sb)
  aIn.append(sb!)
  n += chunk
}
aIn.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
print(writer.status == .completed ? "ok \(out.path)" : "failed \(String(describing: writer.error))")
