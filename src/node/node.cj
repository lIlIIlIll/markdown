package markdown.node

import markdown.core.{CancellationToken, ImmutableArray, MarkdownErrorCode, MarkdownException, OperationBudget, 
    SourceSpan}
import markdown.render.{CodeHighlightToken, MathMlAttribute, MathMlNode, RichContentBackend, RichContentFailure, 
    RichContentKind, RichContentLimits, RichContentOutcome, RichContentProduct, RichContentRequest, RichPngImage}
import std.collection.*
import std.env.getProcessId
import std.fs.{File, Path}
import std.io.*
import std.process.*
import std.sync.AtomicBool

/**
 * 显式可选的 Linux Node 适配器；基础解析与渲染不会自动使用或下载此后端。构造只读取固定 identity 文件，实际作业由显式 prepare 启动。它是可信宿主执行端口，不因本接口而成为沙箱安全边界。
 */
public class NodeRichContentBackend <: RichContentBackend {
    private let runtimeDirectory: String
    private let workDirectory: String
    private let pythonExecutable: String
    private let shikiTheme: String
    private let diagramTheme: String
    private let allowUnsandboxedChromium: Bool
    private let installed: Bool
    /** 固定运行时闭包的 SHA-256；缺失时为 missing，不包含本机路径。 */
    public let runtimeIdentity: String

    /**
     * 路径只能由可信宿主提供；工作目录应位于有足够空间的磁盘。
     *
     * runtimeDirectory、workDirectory 和 pythonExecutable 必须是无 NUL 的绝对路径。主题和 Chromium 沙箱选择来自宿主，不能由 Markdown 覆盖。构造时缓存运行时身份，运行时闭包更新后应创建新实例，避免沿用旧身份。
     * @param runtimeDirectory prepare_rich_runtime.py 生成的运行时目录。
     * @param workDirectory 已存在的私有工作目录。
     * @param pythonExecutable 显式的 Python 3 可执行文件。
     * @param shikiTheme github-light 或 github-dark。
     * @param diagramTheme default、dark、neutral 或 forest。
     * @param allowUnsandboxedChromium 是否显式允许 Chromium 的 no-sandbox 模式；默认不允许。
     * @throws IllegalArgumentException 路径不是显式绝对路径、含 NUL，或主题不受支持时。
     */
    public init(runtimeDirectory: String, workDirectory: String, pythonExecutable!: String = "/usr/bin/python3",
        shikiTheme!: String = "github-light", diagramTheme!: String = "default", allowUnsandboxedChromium!: Bool = false) {
        for (path in [runtimeDirectory, workDirectory, pythonExecutable]) {
            if (path.isEmpty() || !path.startsWith("/") || path.contains("\u{0}")) {
                throw IllegalArgumentException("Node backend paths must be explicit absolute host paths")
            }
        }
        if ((shikiTheme != "github-light" && shikiTheme != "github-dark") || (diagramTheme != "default" &&
            diagramTheme != "dark" && diagramTheme != "neutral" && diagramTheme != "forest")) {
            throw IllegalArgumentException("unsupported Node backend theme")
        }
        this.runtimeDirectory = runtimeDirectory
        this.workDirectory = workDirectory
        this.pythonExecutable = pythonExecutable
        this.shikiTheme = shikiTheme
        this.diagramTheme = diagramTheme
        this.allowUnsandboxedChromium = allowUnsandboxedChromium
        let bytes = try {
            File.readFrom("${runtimeDirectory}/identity")
        } catch (_: Exception) {
            Array<Byte>()
        }
        var valid = bytes.size == 65
        if (valid) {
            valid = bytes[64] == b'\n'
            for (index in 0..64) {
                if (!((bytes[index] >= b'0' && bytes[index] <= b'9') || (bytes[index] >= b'a' && bytes[index] <= b'f'))) {
                    valid = false
                }
            }
        }
        installed = valid
        runtimeIdentity = if (valid) {
            String.fromUtf8(bytes[..64])
        } else {
            "missing"
        }
    }

    /**
     * 仅把真正影响该种产物的主题/浏览器配置加入 key。
     * @param kind 待标识的富内容类别。
     * @return 包含 node-rich 协议、固定运行时身份及该类别有效配置的稳定身份；更换运行时后应重新构造后端。
     */
    public func identity(kind: RichContentKind): String {
        let base = "node-rich/1/${runtimeIdentity}/${kind.id()}"
        match (kind) {
            case RichContentKind.Math => base
            case RichContentKind.Highlight => "${base}/${shikiTheme}"
            case RichContentKind.Diagram => "${base}/${diagramTheme}/${allowUnsandboxedChromium}"
        }
    }

    /**
     * 执行一次有界批量作业；不读取 Markdown 指定的命令、文件或配置。
     * @param requests 按顺序处理的请求，语言名与 source 长度受 limits 约束。
     * @param limits 后端批量作业的资源和整体时间上限；实现还施加固定协议容量上限。
     * @param budget 与收集及校验阶段共用的累计操作预算。
     * @param cancellation 本次准备的取消 token。
     * @return 与 requests 等长且同序的候选产物或不可用原因；运行时未安装返回 Missing，不会下载或自动安装。
     * @throws MarkdownException 取消或累计操作预算耗尽时。
     */
    public func prepare(requests: Array<RichContentRequest>, limits: RichContentLimits, budget: OperationBudget,
        cancellation: CancellationToken): Array<RichContentOutcome> {
        cancellation.throwIfCancelled(phase: "prepare")
        if (!installed) {
            return nodeUnavailable(requests.size, RichContentFailure.Missing)
        }
        if (requests.isEmpty()) {
            return []
        }
        let input = match (encodeNodeRequests(requests, limits, budget, cancellation)) {
            case Some(value) => value
            case None => return nodeUnavailable(requests.size, RichContentFailure.Limited)
        }
        cancellation.throwIfCancelled(phase: "prepare")
        let maximumOutput = min(limits.maximumTotalOutputBytes, 33554432) + requests.size * 2 + 128
        let arguments = ArrayList<String>()
        arguments.add(
            all: ["-I", "-S", "${runtimeDirectory}/supervisor.py", "--runtime-root", runtimeDirectory, "--identity",
                runtimeIdentity, "--work-directory", workDirectory, "--parent-pid", "${getProcessId()}", "--timeout-ms",
                "${limits.maximumTimeMilliseconds}", "--maximum-output-bytes", "${maximumOutput}", "--theme", shikiTheme,
                "--diagram-theme", diagramTheme])
        if (allowUnsandboxedChromium) {
            arguments.add("--allow-no-sandbox")
        }
        let environment = HashMap<String, String>()
        environment.add("PATH", "/usr/bin:/bin")
        environment.add("LANG", "C.UTF-8")
        environment.add("TZ", "UTC")
        let child = try {
            launch(pythonExecutable, arguments.toArray(), workingDirectory: Some(Path(workDirectory)),
                environment: Some(environment), stdIn: ProcessRedirect.Pipe, stdOut: ProcessRedirect.Pipe,
                stdErr: ProcessRedirect.Pipe)
        } catch (_: Exception) {
            return nodeUnavailable(requests.size, RichContentFailure.Missing)
        }
        let limited = AtomicBool(false)
        let failed = AtomicBool(false)
        let output = spawn {readNodePipe(child.stdOutPipe, maximumOutput + 20, child, limited, failed)}
        let errors = spawn {readNodePipe(child.stdErrPipe, 65536, child, limited, failed)}
        let writer = spawn {
            try {
                child.stdInPipe.write(input);
                child.stdInPipe.flush()
            } catch (_: Exception) {
                failed.store(true);
                stopNodeChild(child)
            }
        }
        let io = spawn {
            writer.get()
            let bytes = output.get()
            let stderr = errors.get()
            NodePipeResult(bytes, stderr.size)
        }
        var completed: ?NodePipeResult = None
        var stopped = false
        while (completed.isNone()) {
            try {
                completed = Some(io.get(Duration.millisecond * 50))
            } catch (_: TimeoutException) {
                if (cancellation.isCancelled() && !stopped) {
                    stopped = true
                    stopNodeChild(child)
                }
            }
        }
        // wait closes Cangjie pipe objects: drain all three futures first.
        let status = child.wait(timeout: Some(Duration.second * 2))
        cancellation.throwIfCancelled(phase: "prepare")
        let value = completed.getOrThrow()
        budget.consumeScan(steps: value.output.size + value.stderrBytes)
        if (status != 0) {
            let reason = match (status) {
                case 66 | 2 => RichContentFailure.Missing
                case 69 => RichContentFailure.Unsupported
                case 124 => RichContentFailure.TimedOut
                case 75 => RichContentFailure.Limited
                case _ => RichContentFailure.Failed
            }
            return nodeUnavailable(requests.size, reason)
        }
        if (limited.load()) {
            return nodeUnavailable(requests.size, RichContentFailure.Limited)
        }
        if (failed.load()) {
            return nodeUnavailable(requests.size, RichContentFailure.Failed)
        }
        try {
            decodeNodeResponse(value.output, requests, limits, budget, cancellation)
        } catch (error: MarkdownException) {
            match (error.code) {
                case MarkdownErrorCode.Cancelled | MarkdownErrorCode.BudgetExceeded => throw error
                case _ => nodeUnavailable(requests.size, RichContentFailure.Failed)
            }
        } catch (_: Exception) {
            nodeUnavailable(requests.size, RichContentFailure.Failed)
        }
    }
}

private class NodePipeResult {
    protected let output: Array<Byte>
    let stderrBytes: Int64
    protected init(output: Array<Byte>, stderrBytes: Int64) {
        this.output = output
        this.stderrBytes = stderrBytes
    }
}

private func stopNodeChild(child: SubProcess): Unit {
    try {
        child.terminate()
    } catch (_: ProcessException) {}
}

private func readNodePipe(input: InputStream, maximum: Int64, child: SubProcess, limited: AtomicBool, failed: AtomicBool): Array<Byte> {
    let values = ArrayList<Byte>()
    let buffer = Array<Byte>(8192, repeat: 0)
    var discarding = false
    try {
        while (true) {
            let count = input.read(buffer)
            if (count == 0) {
                break
            }
            if (count < 0) {
                failed.store(true);
                stopNodeChild(child);
                break
            }
            if (!discarding && count > maximum - values.size) {
                discarding = true
                limited.store(true)
                stopNodeChild(child)
            }
            if (!discarding) {
                for (index in 0..count) {
                    values.add(buffer[index])
                }
            }
        }
    } catch (_: Exception) {
        failed.store(true);
        stopNodeChild(child)
    }
    values.toArray()
}

private func nodeUnavailable(count: Int64, reason: RichContentFailure): Array<RichContentOutcome> {
    Array<RichContentOutcome>(count, repeat: RichContentOutcome.Unavailable(reason))
}

private func nodeKindCode(kind: RichContentKind): Int64 {
    match (kind) {
        case RichContentKind.Math => 0;
        case RichContentKind.Diagram => 1;
        case RichContentKind.Highlight => 2
    }
}

private class NodeWireWriter {
    private let values = ArrayList<Byte>()
    func uint(value: Int64): Unit {
        for (shift in [24, 16, 8, 0]) {
            values.add(UInt8((value >> shift) & 255))
        }
    }
    protected func byte(value: Int64): Unit {
        values.add(UInt8(value))
    }
    protected func raw(value: String): Unit {
        values.add(all: value.toArray())
    }
    protected func string(value: String): Unit {
        uint(value.size);
        raw(value)
    }
    protected func frame(): Array<Byte> {
        let body = values.toArray()
        let framed = NodeWireWriter()
        framed.uint(body.size)
        framed.values.add(all: body)
        framed.values.toArray()
    }
}

private func encodeNodeRequests(requests: Array<RichContentRequest>, limits: RichContentLimits, budget: OperationBudget,
    cancellation: CancellationToken): ?Array<Byte> {
    if (requests.size > limits.maximumRequests) {
        return None
    }
    var size: Int64 = 57
    var sourceBytes: Int64 = 0
    for (request in requests) {
        cancellation.throwIfCancelled(phase: "prepare")
        if (request.language.size > 128 || request.source.size > limits.maximumInputBytes || request.source.size >
            limits.maximumTotalInputBytes - sourceBytes) {
            return None
        }
        sourceBytes += request.source.size
        size += request.source.size + request.language.size + 10
        if (size > 33554432) {
            return None
        }
    }
    budget.consumeScan(steps: size)
    let writer = NodeWireWriter()
    writer.raw("MDRICH-REQUEST/1\n")
    for (value in [limits.maximumRequests, limits.maximumInputBytes, limits.maximumTotalInputBytes,
        limits.maximumOutputBytes, limits.maximumTotalOutputBytes, limits.maximumTreeNodes, limits.maximumTreeDepth,
        limits.maximumTokens, limits.maximumImagePixels, requests.size]) {
        writer.uint(value)
    }
    for (request in requests) {
        cancellation.throwIfCancelled(phase: "prepare")
        writer.byte(nodeKindCode(request.kind));
        writer.byte(if (request.display) {
            1
        } else {
            0
        })
        writer.string(request.language);
        writer.string(request.source)
    }
    Some(writer.frame())
}

private class NodeWireReader {
    protected let bytes: Array<Byte>
    protected var offset: Int64 = 0
    protected init(bytes: Array<Byte>) {
        this.bytes = bytes
    }
    protected func byte(): Int64 {
        if (offset >= bytes.size) {
            invalidNodeProtocol()
        }
        let value = Int64(bytes[offset]);
        offset++;
        value
    }
    func uint(): Int64 {
        var value: Int64 = 0
        for (_ in 0..4) {
            value = (value << 8) | byte()
        }
        value
    }
    protected func data(count: Int64): Array<Byte> {
        if (count < 0 || count > bytes.size - offset) {
            invalidNodeProtocol()
        }
        let start = offset;
        offset += count
        Array<Byte>(count, {i => bytes[start + i]})
    }
    protected func string(maximum: Int64): String {
        let count = uint()
        if (count > maximum) {
            invalidNodeProtocol()
        }
        String.fromUtf8(data(count))
    }
    protected func expect(value: String): Unit {
        for (expected in value.toArray()) {
            if (byte() != Int64(expected)) {
                invalidNodeProtocol()
            }
        }
    }
}

private class NodeMathFrame {
    protected let tag: String
    protected let text: String
    protected let attributes: Array<MathMlAttribute>
    protected let children = ArrayList<MathMlNode>()
    protected var remaining: Int64
    protected init(tag: String, text: String, attributes: Array<MathMlAttribute>, remaining: Int64) {
        this.tag = tag
        this.text = text
        this.attributes = attributes
        this.remaining = remaining
    }
}

private func decodeNodeMath(reader: NodeWireReader, limits: RichContentLimits, budget: OperationBudget,
    cancellation: CancellationToken): MathMlNode {
    let count = reader.uint()
    if (count == 0 || count > min(limits.maximumTreeNodes, 65536)) {
        invalidNodeProtocol()
    }
    let frames = ArrayList<NodeMathFrame>()
    var root: ?MathMlNode = None
    for (index in 0..count) {
        cancellation.throwIfCancelled(phase: "prepare")
        budget.consumeScan()
        if (root.isSome() || frames.size >= min(limits.maximumTreeDepth, 128)) {
            invalidNodeProtocol()
        }
        let tag = reader.string(32)
        let text = reader.string(limits.maximumOutputBytes)
        let attributeCount = reader.uint()
        if (attributeCount > 32) {
            invalidNodeProtocol()
        }
        let attributes = ArrayList<MathMlAttribute>()
        for (_ in 0..attributeCount) {
            attributes.add(MathMlAttribute(reader.string(32), reader.string(128)))
        }
        let children = reader.uint()
        if (children > count - index - 1) {
            invalidNodeProtocol()
        }
        frames.add(NodeMathFrame(tag, text, attributes.toArray(), children))
        while (!frames.isEmpty() && frames[frames.size - 1].remaining == 0) {
            let frame = frames.remove(at: frames.size - 1)
            let node = MathMlNode(frame.tag, text: frame.text, attributes: frame.attributes,
                children: frame.children.toArray())
            if (frames.isEmpty()) {
                root = Some(node)
            } else {
                frames[frames.size - 1].children.add(node)
                frames[frames.size - 1].remaining--
            }
        }
    }
    if (!frames.isEmpty()) {
        invalidNodeProtocol()
    }
    root.getOrThrow()
}

private func decodeNodeResponse(bytes: Array<Byte>, requests: Array<RichContentRequest>, limits: RichContentLimits,
    budget: OperationBudget, cancellation: CancellationToken): Array<RichContentOutcome> {
    let reader = NodeWireReader(bytes)
    reader.expect("MDRICH-SUPERVISOR/1\nMDRICH-RESPONSE/1\n")
    if (reader.uint() != requests.size) {
        invalidNodeProtocol()
    }
    let outcomes = ArrayList<RichContentOutcome>()
    for (request in requests) {
        cancellation.throwIfCancelled(phase: "prepare")
        let status = reader.byte()
        if (status != 0) {
            let reason = match (status) {
                case 1 => RichContentFailure.Disabled;
                case 2 => RichContentFailure.Missing
                case 3 => RichContentFailure.Unsupported;
                case 4 => RichContentFailure.TimedOut
                case 5 => RichContentFailure.Failed;
                case 6 => RichContentFailure.Limited
                case _ => invalidNodeProtocol()
            }
            outcomes.add(RichContentOutcome.Unavailable(reason));
            continue
        }
        if (reader.byte() != nodeKindCode(request.kind)) {
            invalidNodeProtocol()
        }
        let product = match (request.kind) {
            case RichContentKind.Math => RichContentProduct.MathMl(decodeNodeMath(reader, limits, budget, cancellation))
            case RichContentKind.Diagram =>
                let size = reader.uint()
                if (size > limits.maximumOutputBytes) {
                    invalidNodeProtocol()
                }
                RichContentProduct.Diagram(RichPngImage(reader.data(size)))
            case RichContentKind.Highlight =>
                let count = reader.uint()
                if (count > min(limits.maximumTokens, 131072)) {
                    invalidNodeProtocol()
                }
                let tokens = ArrayList<CodeHighlightToken>()
                for (_ in 0..count) {
                    cancellation.throwIfCancelled(phase: "prepare")
                    budget.consumeScan()
                    let start = reader.uint();
                    let end = reader.uint();
                    let color = reader.uint()
                    if (color > 16777215) {
                        invalidNodeProtocol()
                    }
                    let text = StringBuilder();
                    text.append("#")
                    let digits = "0123456789abcdef"
                    for (shift in [20, 16, 12, 8, 4, 0]) {
                        let value = (color >> shift) & 15;
                        text.append(digits[value..value + 1])
                    }
                    tokens.add(CodeHighlightToken(SourceSpan(start, end), text.toString(), fontStyle: reader.byte()))
                }
                RichContentProduct.Highlight(ImmutableArray<CodeHighlightToken>(tokens.toArray()))
        }
        outcomes.add(RichContentOutcome.Ready(product))
    }
    if (reader.offset != bytes.size) {
        invalidNodeProtocol()
    }
    outcomes.toArray()
}

private func invalidNodeProtocol(): Nothing {
    throw MarkdownException(MarkdownErrorCode.RenderFailure, "invalid Node rich content protocol", phase: "prepare")
}
