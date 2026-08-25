package markdown

public enum MarkdownErrorCode {
    | InvalidEncoding
    | InputReadFailure
    | Cancelled
    | LimitExceeded
    | BudgetExceeded
    | ExtensionConflict
    | ExtensionFailure
    | SinkFailure
    | RenderFailure
    | UnsupportedNode
    | InvalidArtifact
    | InternalInvariantViolation
}

public open class MarkdownException <: Exception {
    public let code: MarkdownErrorCode
    public let phase: String
    public let span: ?SourceSpan

    public init(code: MarkdownErrorCode, message: String, phase!: String = "", span!: ?SourceSpan = None) {
        super(message)
        this.code = code
        this.phase = phase
        this.span = span
    }

    protected open override func getClassName(): String {
        "MarkdownException"
    }
}

public enum DiagnosticSeverity {
    | Info
    | Warning
    | Error
}

public class DiagnosticFix {
    public let title: String
    public let span: SourceSpan
    public let replacement: String
    public init(title: String, span: SourceSpan, replacement: String) {
        this.title = title
        this.span = span
        this.replacement = replacement
    }
}

public class Diagnostic {
    public let code: String
    public let severity: DiagnosticSeverity
    public let message: String
    public let span: SourceSpan
    public let relatedSpans: Array<SourceSpan>
    public let extensionId: ?String
    public let ruleId: ?String
    public let fixes: ImmutableArray<DiagnosticFix>

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

public class LimitExceededException <: MarkdownException {
    public let limitKind: String
    public let configuredLimit: Int64
    public let observedValue: Int64
    public let extensionId: ?String

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

    protected override func getClassName(): String {
        "LimitExceededException"
    }
}

public class InputReadFailureException <: MarkdownException {
    public let cause: Exception

    public init(cause: Exception) {
        super(MarkdownErrorCode.InputReadFailure, cause.message, phase: "input")
        this.cause = cause
    }

    protected override func getClassName(): String {
        "InputReadFailureException"
    }
}

public class ExtensionFailureException <: MarkdownException {
    public let extensionId: String
    public let semanticVersion: String
    public let implementationVersion: String
    public let ruleId: ?String
    public let cause: Exception

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

    protected override func getClassName(): String {
        "ExtensionFailureException"
    }
}
