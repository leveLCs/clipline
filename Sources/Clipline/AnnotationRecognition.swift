import AppKit
import Vision

struct AnnotationQRCode {
    let text: String
    // Vision coordinates: unit square, bottom-left origin, relative to rendered crop.
    let bounds: CGRect
}

enum AnnotationRecognition {
    static func qr(_ image: CGImage) throws -> [AnnotationQRCode] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let text = observation.payloadStringValue, !text.isEmpty else { return nil }
            return AnnotationQRCode(text: text, bounds: observation.boundingBox)
        }
    }
}
