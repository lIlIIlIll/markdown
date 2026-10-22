package markdown.core

/** 复制文档 literal 与已知 payload，解除对原始来源存储的持有。 */
extend Document {
    /**
     * 将 source-backed 的文本、代码块和 raw HTML literal 转为拥有独立存储的文本，
     * 并将可达节点复制到不保留原 arena/source 的新文档；节点身份和绑定保持不变。
     * @return 独立于 source buffer 的 `Document` 副本。
     * @throws MarkdownException 自定义 payload 的 ownership 无法验证时。
     */
    public func detach(): Document {
        detachDocument(this)
    }
}
