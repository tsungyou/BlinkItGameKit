import Foundation
import UIKit

public enum BlinkItGameKitResources {
    public static let bundle: Bundle = .module

    public static func image(named name: String) -> UIImage? {
        if let url = bundle.url(forResource: name, withExtension: "png"),
           let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            return image
        }
        if let url = bundle.url(forResource: name, withExtension: "jpg"),
           let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            return image
        }
        if let url = bundle.url(forResource: name, withExtension: "jpeg"),
           let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            return image
        }
        return nil
    }
}
