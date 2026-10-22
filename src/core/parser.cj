package markdown.core

/** 将 byte 输入解码为文本时采用的 UTF-8 错误策略。 */
public enum Utf8Policy {
    /** 遇到无效 UTF-8 序列时解析失败。 */
    | Strict
    /** 将无效 UTF-8 序列替换为 U+FFFD 后继续。 */
    | ReplaceInvalid
}

/**
 * 一次完整解析的结果。
 *
 * `document` 为 arena AST，`source` 携带原始输入与位置映射，`diagnostics`
 * 保留可恢复诊断。
 */
public class ParseResult {
    /** 成功解析得到的完整、不可变 arena AST。 */
    public let document: Document
    /** 与结果对应的原始文本、byte range 和位置映射。 */
    public let source: SourceBuffer
    /** 解析过程中保留的可恢复诊断。 */
    public let diagnostics: ImmutableArray<Diagnostic>

    /**
     * 创建解析结果。
     * @param document 完整且不可变的 arena AST。
     * @param source 与结果对应的原始文本和位置映射。
     * @param diagnostics 解析过程中保留的可恢复诊断。
     * @throws IllegalArgumentException Document 与 source 不属于同一次不可变来源视图时。
     */
    public init(document: Document, source: SourceBuffer, diagnostics: Array<Diagnostic>) {
        document.requireSource(source)
        this.document = document
        this.source = source
        this.diagnostics = ImmutableArray<Diagnostic>(diagnostics)
    }
}

/** 完整解析的成功或致命失败；失败不携带空文档或 AST 前缀。 */
public enum ParseOutcome {
    /** 成功文档及其可恢复诊断。 */
    | Success(ParseResult)
    /** 致命错误，保留类别、阶段及可用的来源范围。 */
    | Failure(MarkdownException)
}
