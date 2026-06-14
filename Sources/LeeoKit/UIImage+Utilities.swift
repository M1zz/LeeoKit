//
//  UIImage+Utilities.swift
//  LeeoKit
//
//  이미지 인코딩/리사이즈/포맷 감지 유틸. UIKit 환경에서만 컴파일.
//

#if canImport(UIKit)
import UIKit

public extension UIImage {
    /// 이미지를 Base64 문자열로 변환
    func toBase64(compressionQuality: CGFloat = 0.8) -> String? {
        guard let imageData = self.jpegData(compressionQuality: compressionQuality) else {
            return nil
        }
        return imageData.base64EncodedString()
    }

    /// Base64 문자열에서 UIImage 생성
    static func from(base64: String) -> UIImage? {
        guard let imageData = Data(base64Encoded: base64) else {
            return nil
        }
        return UIImage(data: imageData)
    }

    /// 이미지를 특정 크기로 리사이즈 (썸네일 생성용)
    func resized(to size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext()
    }

    /// 이미지를 최대 너비/높이로 제한 (메모리 절약)
    func constrainedSize(maxDimension: CGFloat = 1024) -> UIImage? {
        let maxSize = max(size.width, size.height)
        if maxSize <= maxDimension {
            return self
        }

        let ratio = maxDimension / maxSize
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        return resized(to: newSize)
    }

    /// 이미지 포맷 감지 (첫 바이트 매직넘버 기반)
    var imageFormat: String {
        guard let data = self.pngData() ?? self.jpegData(compressionQuality: 1.0),
              let byte = data.first else {
            return "unknown"
        }

        switch byte {
        case 0xFF: return "jpeg"
        case 0x89: return "png"
        case 0x47: return "gif"
        case 0x49, 0x4D: return "tiff"
        default: return "unknown"
        }
    }
}
#endif
