import Foundation

struct ParsedDescription {
    var friendlyName: String = ""
    var manufacturer: String = ""
    var modelName: String = ""
    var udn: String = ""
    var deviceType: String = ""
    var services: [(type: String, controlURL: String)] = []
}

final class DeviceDescriptionParser: NSObject, XMLParserDelegate {
    private(set) var result = ParsedDescription()
    private var path: [String] = []
    private var text = ""
    private var pendingService: (type: String, controlURL: String) = ("", "")

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes: [String: String] = [:]) {
        path.append(elementName)
        text = ""
        if path == ["root", "device", "serviceList", "service"] {
            pendingService = ("", "")
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = Array(path.dropLast())

        if parent == ["root", "device"] {
            switch elementName {
            case "friendlyName": result.friendlyName = trimmed
            case "manufacturer": result.manufacturer = trimmed
            case "modelName":    result.modelName    = trimmed
            case "UDN":          result.udn          = trimmed
            case "deviceType":   result.deviceType   = trimmed
            default: break
            }
        } else if parent == ["root", "device", "serviceList", "service"] {
            switch elementName {
            case "serviceType": pendingService.type = trimmed
            case "controlURL":  pendingService.controlURL = trimmed
            default: break
            }
        }

        if elementName == "service",
           parent == ["root", "device", "serviceList"],
           !pendingService.type.isEmpty {
            result.services.append(pendingService)
            pendingService = ("", "")
        }

        path.removeLast()
        text = ""
    }
}
