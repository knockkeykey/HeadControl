import Foundation
import Combine

@MainActor final class ConfigurationStore: ObservableObject {
    @Published var configuration = Configuration() { didSet { save() } }
    @Published private(set) var error: String?
    var onChange: (() -> Void)?
    private var loading = true
    let directory: URL
    var file: URL { directory.appendingPathComponent("configuration.json") }
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("com.keyknock.HeadControl", isDirectory: true)
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                let data = try Data(contentsOf:file)
                configuration = try Configuration.decode(data)
                if let header = try JSONSerialization.jsonObject(with:data) as? [String:Any], header["version"] as? Int == 1 {
                    let backup = self.directory.appendingPathComponent("configuration-v1-backup-\(UUID().uuidString).json")
                    try FileManager.default.copyItem(at:file,to:backup)
                    try configuration.encoded().write(to:file,options:.atomic)
                }
            }
            catch { self.error = "配置无法读取，当前使用默认值；原文件未修改。恢复保存前请备份或重置配置。" }
        }
        loading = false
    }
    private func save() {
        guard !loading else { return }
        onChange?()
        guard error == nil else { return }
        do {
            let data = try configuration.encoded()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
        } catch { self.error = "配置保存失败：\(error.localizedDescription)" }
    }
    func recover() {
        do {
            if FileManager.default.fileExists(atPath: file.path) {
                let backup = directory.appendingPathComponent("configuration-backup-\(Int(Date().timeIntervalSince1970)).json")
                try FileManager.default.copyItem(at: file, to: backup)
            }
            error = nil; configuration = Configuration()
        } catch { self.error = "备份失败，未重置：\(error.localizedDescription)" }
    }
}
