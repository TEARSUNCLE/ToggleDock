/// 语义版本解析与比较，供更新检测使用（支持 "v1.2.3"、纯数字 "1.2" 等写法）。
public enum Version {

    /// 解析出 (major, minor, patch) 三元组；缺段补 0，解析失败返回 nil。
    /// - 兼容写法："1.0" / "v2.1.0" / "1.2.3.4"（多余段忽略）
    public static func triple(from raw: String) -> (major: Int, minor: Int, patch: Int)? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let body = trimmed.first == "v" || trimmed.first == "V" ? String(trimmed.dropFirst()) : trimmed
        let parsed = body.split(separator: ".", omittingEmptySubsequences: false).prefix(3).map { Int($0) }
        guard !parsed.isEmpty, parsed.allSatisfy({ $0 != nil }) else { return nil }
        let nums = parsed.compactMap { $0 }
        return (nums[0], nums.count > 1 ? nums[1] : 0, nums.count > 2 ? nums[2] : 0)
    }
}