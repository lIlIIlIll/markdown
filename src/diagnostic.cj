package markdown

/** `MarkdownException.code` 使用的稳定错误类别。 */
public enum MarkdownErrorCode {
    /** 输入不是合法的编码。 */
    | InvalidEncoding
    /** 读取输入流失败。 */
    | InputReadFailure
    /** 操作被取消。 */
    | Cancelled
    /** 结构或输出上限被超过。 */
    | LimitExceeded
    /** 操作预算耗尽。 */
    | BudgetExceeded
    /** 扩展之间或与内建规则冲突。 */
    | ExtensionConflict
    /** 扩展 callback 执行失败。 */
    | ExtensionFailure
    /** 输出 sink 写入失败。 */
    | SinkFailure
    /** 渲染失败。 */
    | RenderFailure
    /** 遇到不支持的节点类别。 */
    | UnsupportedNode
    /** artifact 无效或身份不匹配。 */
    | InvalidArtifact
    /** 显式输入采用了当前不支持的版本。 */
    | UnsupportedVersion
    /** 引用无法按显式的严格绑定策略解析。 */
    | InvalidReference
    /** 触发内部不变量违规。 */
    | InternalInvariantViolation
}

/**
 * 解析、渲染、扩展和资源限制失败的统一异常基类。
 *
 * `phase` 标识失败阶段，`span` 在有源码位置时提供半开 byte range。
 */
public open class MarkdownException <: Exception {
    /** 稳定错误类别。 */
    public let code: MarkdownErrorCode
    /** 失败发生的阶段名称。 */
    public let phase: String
    /** 失败位置的 source span；无位置信息时为 `None`。 */
    public let span: ?SourceSpan

    /**
     * 创建异常。
     * @param code 稳定错误类别。
     * @param message 人读错误消息。
     * @param phase 失败发生的阶段名称。
     * @param span 失败位置的 source span。
     */
    public init(code: MarkdownErrorCode, message: String, phase!: String = "", span!: ?SourceSpan = None) {
        super(message)
        this.code = code
        this.phase = phase
        this.span = span
    }

    /**
     * 返回异常类名。
     * @return 异常类名。
     */
    protected open override func getClassName(): String {
        "MarkdownException"
    }
}

/** 可恢复诊断的严重级别。 */
public enum DiagnosticSeverity {
    /** 提示信息。 */
    | Info
    /** 警告。 */
    | Warning
    /** 错误。 */
    | Error
}

/** 绑定到源码范围的可选诊断修复。 */
public class DiagnosticFix {
    /** 修复的展示标题。 */
    public let title: String
    /** 修复作用的 source span。 */
    public let span: SourceSpan
    /** 替换后的文本。 */
    public let replacement: String
    /**
     * 创建修复。
     * @param title 修复的展示标题。
     * @param span 修复作用的 source span。
     * @param replacement 替换后的文本。
     */
    public init(title: String, span: SourceSpan, replacement: String) {
        this.title = title
        this.span = span
        this.replacement = replacement
    }
}

/**
 * parser 或扩展产生的可恢复诊断。
 *
 * `relatedSpans`、扩展/rule 身份和 `fixes` 用于编辑器或宿主展示与修复。
 */
public class Diagnostic {
    /** 诊断代码。 */
    public let code: String
    /** 严重级别。 */
    public let severity: DiagnosticSeverity
    /** 人读消息。 */
    public let message: String
    /** 关联的 source span。 */
    public let span: SourceSpan
    /** 相关的其它 source span。 */
    public let relatedSpans: Array<SourceSpan>
    /** 产生诊断的扩展 id。 */
    public let extensionId: ?String
    /** 产生诊断的规则 id。 */
    public let ruleId: ?String
    /** 可选修复列表。 */
    public let fixes: ImmutableArray<DiagnosticFix>

    /**
     * 创建诊断；`code` 为空时抛出 `IllegalArgumentException`。
     * @param code 诊断代码。
     * @param severity 严重级别。
     * @param message 人读消息。
     * @param span 关联的 source span。
     * @param relatedSpans 相关的其它 source span。
     * @param extensionId 产生诊断的扩展 id。
     * @param ruleId 产生诊断的规则 id。
     * @param fixes 可选修复列表。
     */
    public init(
        code: String,
        severity: DiagnosticSeverity,
        message: String,
        span: SourceSpan,
        relatedSpans!: Array<SourceSpan> = [],
        extensionId!: ?String = None,
        ruleId!: ?String = None,
        fixes!: Array<DiagnosticFix> = []
    ) {
        if (code.isEmpty()) {
            throw IllegalArgumentException("diagnostic code must not be empty")
        }
        this.code = code
        this.severity = severity
        this.message = message
        this.span = span
        this.relatedSpans = relatedSpans
        this.extensionId = extensionId
        this.ruleId = ruleId
        this.fixes = ImmutableArray<DiagnosticFix>(fixes)
    }
}

/** 结构上限或输出上限被观测值超过时抛出的异常。 */
public class LimitExceededException <: MarkdownException {
    /** 被超过的 limit 类别。 */
    public let limitKind: String
    /** 配置的 limit 值。 */
    public let configuredLimit: Int64
    /** 实际观测到的值。 */
    public let observedValue: Int64
    /** 触发限制的扩展 id。 */
    public let extensionId: ?String

    /**
     * 创建限制超限异常。
     * @param limitKind 被超过的 limit 类别。
     * @param configuredLimit 配置的 limit 值。
     * @param observedValue 实际观测到的值。
     * @param phase 失败发生的阶段名称。
     * @param span 失败位置的 source span。
     * @param extensionId 触发限制的扩展 id。
     */
    public init(
        limitKind: String,
        configuredLimit: Int64,
        observedValue: Int64,
        phase: String,
        span!: ?SourceSpan = None,
        extensionId!: ?String = None
    ) {
        super(
            MarkdownErrorCode.LimitExceeded,
            "limit exceeded: ${limitKind} configured=${configuredLimit} observed=${observedValue}",
            phase: phase,
            span: span
        )
        this.limitKind = limitKind
        this.configuredLimit = configuredLimit
        this.observedValue = observedValue
        this.extensionId = extensionId
    }

    /**
     * 返回异常类名。
     * @return 异常类名。
     */
    protected override func getClassName(): String {
        "LimitExceededException"
    }
}

/** 从 `InputStream` 读取输入时发生非 Markdown 异常的包装。 */
public class InputReadFailureException <: MarkdownException {
    /** 底层读取异常。 */
    public let cause: Exception

    /**
     * 包装底层异常。
     * @param cause 底层读取异常。
     */
    public init(cause: Exception) {
        super(MarkdownErrorCode.InputReadFailure, cause.message, phase: "input")
        this.cause = cause
    }

    /**
     * 返回异常类名。
     * @return 异常类名。
     */
    protected override func getClassName(): String {
        "InputReadFailureException"
    }
}

/** 扩展 callback、processor 或 renderer fallback 失败时的上下文异常。 */
public class ExtensionFailureException <: MarkdownException {
    /** 失败的扩展 id。 */
    public let extensionId: String
    /** 扩展的语义版本。 */
    public let semanticVersion: String
    /** 扩展的实现版本。 */
    public let implementationVersion: String
    /** 失败的规则 id。 */
    public let ruleId: ?String
    /** 底层异常。 */
    public let cause: Exception

    /**
     * 创建扩展失败异常。
     * @param extensionId 失败的扩展 id。
     * @param semanticVersion 扩展的语义版本。
     * @param implementationVersion 扩展的实现版本。
     * @param phase 失败发生的阶段名称。
     * @param cause 底层异常。
     * @param ruleId 失败的规则 id。
     * @param span 失败位置的 source span。
     */
    public init(extensionId: String, semanticVersion: String, implementationVersion: String, phase: String,
        cause: Exception, ruleId!: ?String = None, span!: ?SourceSpan = None) {
        super(MarkdownErrorCode.ExtensionFailure,
            "extension ${extensionId}@${semanticVersion} failed during ${phase}: ${cause.message}", phase: phase,
            span: span)
        this.extensionId = extensionId
        this.semanticVersion = semanticVersion
        this.implementationVersion = implementationVersion
        this.ruleId = ruleId
        this.cause = cause
    }

    /**
     * 返回异常类名。
     * @return 异常类名。
     */
    protected override func getClassName(): String {
        "ExtensionFailureException"
    }
}
