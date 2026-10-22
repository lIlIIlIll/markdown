package markdown.core

import std.collection.*

/** 链接的绑定决策；派生展示目标不改写作者的语义 destination。 */
public class LinkBinding {
    /** 链接节点身份。 */
    public let link: NodeId
    /** 解析后的作者 destination。 */
    public let destination: String
    /** 输出使用的 destination，包含必要的文档 scope。 */
    public let renderedDestination: String
    /** 是否仅引用当前文档 fragment。 */
    public let isLocalFragment: Bool
    /** 已解析的本地目标；外部链接、页面顶部或未知 fragment 为 None。 */
    public let target: ?NodeId

    /** 保存链接语义、输出目标和本地 fragment 解析结果。
     * @param link 链接节点的 NodeId。
     * @param destination 作者链接经 Markdown 解码后的语义目标。
     * @param renderedDestination 输出时采用的目标，可包含绑定 scope。
     * @param target 已解析的当前文档节点；未知或外部目标为 None。
     */
    protected init(link: NodeId, destination: String, renderedDestination: String, target: ?NodeId) {
        this.link = link
        this.destination = destination
        this.renderedDestination = renderedDestination
        this.isLocalFragment = destination.startsWith("#")
        this.target = target
    }
}

/** 对 fragment 执行百分号解码并验证 UTF-8；不执行 URI 访问或网络请求。
 * @param value 不含起始 # 的 fragment 文本。
 * @param consume 计入扫描字节并检查取消的回调；长输入也以 0 调用作为检查点。
 * @return 解码后的 fragment；百分号编码或 UTF-8 非法时为 None。
 */
protected func decodeFragment(value: String, consume: (Int64) -> Unit): ?String {
    consume(value.size)
    let bytes = ArrayList<Byte>()
    var index: Int64 = 0
    var checkpoint: Int64 = 0
    while (index < value.size) {
        if (index - checkpoint >= 1024) {
            consume(0);
            checkpoint = index
        }
        if (value[index] == b'%') {
            if (index + 2 >= value.size) {
                return None
            }
            let high = fragmentHex(value[index + 1])
            let low = fragmentHex(value[index + 2])
            if (high < 0 || low < 0) {
                return None
            }
            bytes.add(UInt8(high * 16 + low))
            index += 3
        } else {
            bytes.add(value[index]);
            index++
        }
    }
    try {
        Some(String.fromUtf8(bytes.toArray()))
    } catch (_: Exception) {
        None
    }
}

private func fragmentHex(byte: Byte): Int64 {
    if (byte >= b'0' && byte <= b'9') {
        return Int64(byte - b'0')
    }
    if (byte >= b'a' && byte <= b'f') {
        return Int64(byte - b'a') + 10
    }
    if (byte >= b'A' && byte <= b'F') {
        return Int64(byte - b'A') + 10
    }
    -1
}
