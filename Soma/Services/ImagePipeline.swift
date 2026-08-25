import Foundation
import ImageIO
import UIKit

actor ImagePipeline {
    static let shared = ImagePipeline()

    static let thumbnailCostLimit = 48 * 1024 * 1024

    private let cache = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private var aspectRatios: [String: CGFloat] = [:]

    init() {
        cache.totalCostLimit = Self.thumbnailCostLimit
    }

    func image(
        atStoredPath path: String?,
        maxPixelSize: Int = 1024
    ) async -> UIImage? {
        guard let url = MediaStore.url(at: path) else { return nil }
        return await image(
            at: url,
            cacheKey: "stored:\(fingerprint(for: url))",
            maxPixelSize: maxPixelSize
        )
    }

    func image(
        at url: URL,
        cacheKey: String,
        maxPixelSize: Int = 1024
    ) async -> UIImage? {
        let key = "\(cacheKey):\(maxPixelSize)"
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }
        if let existing = inFlight[key] {
            return await existing.value
        }

        let task = Task.detached(priority: .utility) {
            let interval = AppPerformance.begin(.imageLoad, detail: "source=file")
            defer { AppPerformance.end(interval, detail: "source=file") }
            return Self.downsample(url: url, maxPixelSize: maxPixelSize)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if let result {
            cache.setObject(
                result,
                forKey: key as NSString,
                cost: Self.cost(of: result)
            )
        }
        return result
    }

    func image(
        data: Data,
        cacheKey: String,
        maxPixelSize: Int = 256
    ) async -> UIImage? {
        let key = "data:\(cacheKey):\(maxPixelSize)"
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }
        if let existing = inFlight[key] {
            return await existing.value
        }

        let task = Task.detached(priority: .utility) {
            let interval = AppPerformance.begin(.imageLoad, detail: "source=data")
            defer { AppPerformance.end(interval, detail: "source=data") }
            return Self.downsample(data: data, maxPixelSize: maxPixelSize)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if let result {
            cache.setObject(
                result,
                forKey: key as NSString,
                cost: Self.cost(of: result)
            )
        }
        return result
    }

    func aspectRatio(atStoredPath path: String?) async -> CGFloat? {
        guard let url = MediaStore.url(at: path) else { return nil }
        let key = fingerprint(for: url)
        if let cached = aspectRatios[key] {
            return cached
        }
        let value = await Task.detached(priority: .utility) {
            Self.readAspectRatio(url: url)
        }.value
        if let value {
            aspectRatios[key] = value
        }
        return value
    }

    func removeAllCachedImages() {
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
        aspectRatios.removeAll()
        cache.removeAllObjects()
    }

    private func fingerprint(for url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [
            .contentModificationDateKey,
            .fileSizeKey
        ])
        return [
            url.standardizedFileURL.path,
            String(values?.fileSize ?? 0),
            String(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)
        ].joined(separator: ":")
    }

    private static func downsample(
        url: URL,
        maxPixelSize: Int
    ) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(
            url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else {
            return nil
        }
        return downsample(source: source, maxPixelSize: maxPixelSize)
    }

    private static func downsample(
        data: Data,
        maxPixelSize: Int
    ) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else {
            return nil
        }
        return downsample(source: source, maxPixelSize: maxPixelSize)
    }

    private static func downsample(
        source: CGImageSource,
        maxPixelSize: Int
    ) -> UIImage? {
        let options: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize)
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return nil
        }
        return UIImage(cgImage: image)
    }

    private static func readAspectRatio(url: URL) -> CGFloat? {
        guard let source = CGImageSourceCreateWithURL(
            url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ),
            let properties = CGImageSourceCopyPropertiesAtIndex(
                source,
                0,
                nil
            ) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
            let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
            width.doubleValue > 0,
            height.doubleValue > 0
        else {
            return nil
        }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let isRotated = (5 ... 8).contains(orientation)
        let resolvedWidth = isRotated ? height.doubleValue : width.doubleValue
        let resolvedHeight = isRotated ? width.doubleValue : height.doubleValue
        return resolvedWidth / resolvedHeight
    }

    private static func cost(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }
}
