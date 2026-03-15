import Foundation

protocol DetectPIIUseCase {
    func execute(document: Document) async -> [DetectedPII]
}

final class DetectPIIUseCaseImpl: DetectPIIUseCase {
    private let detector: PIIDetectorPort

    init(detector: PIIDetectorPort) {
        self.detector = detector
    }

    func execute(document: Document) async -> [DetectedPII] {
        await detector.detect(in: document.content)
    }
}
