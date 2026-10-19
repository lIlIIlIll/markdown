package markdown

extend HtmlRenderer {
    /** 创建可恢复的实际 renderer 遍历。构造时不渲染、不调用 sink 或宿主端口。
     * @param document 完整且不可变的 Document。
     * @param chunkBytes 每次提供给 sink 的最大字节数，至少为 4，保证容纳任意 UTF-8 scalar。
     * @param cancellation 整个输出会话共用的取消 token。
     * @param budget 整个输出会话共用的累计操作预算。
     * @return 顺序使用的输出会话。
     */
    public func newOutputSession(document: Document, chunkBytes!: Int64 = 4096,
        cancellation!: CancellationToken = CancellationToken.none(), budget!: OperationBudget = OperationBudget.safe()): HtmlOutputSession {
        HtmlOutputSession(this, document, chunkBytes, cancellation, budget)
    }
}

/** 保存 renderer 遍历、转义进度和未确认输出的会话；不会预先生成完整 HTML。 */
public class HtmlOutputSession {
    private let cancellation: CancellationToken
    private let budget: OperationBudget
    private let initialOutputBytes: Int64
    private var cursor: ?HtmlOutputCursor
    private var pending = ""
    private var pendingOffset: Int64 = 0
    private var acknowledged: Int64 = 0
    private var active = false
    private var terminal = false

    internal init(renderer: HtmlRenderer, document: Document, chunkBytes: Int64, cancellation: CancellationToken,
        budget: OperationBudget) {
        this.cancellation = cancellation
        this.budget = budget
        initialOutputBytes = budget.usedOutputBytes()
        cursor = Some(HtmlOutputCursor(renderer, document, chunkBytes, cancellation, budget))
    }

    /** 写出直到暂停、完成或失败。Pause(n) 确认本次片段前 n 个字节，必须位于 UTF-8 边界。
     * Continue 确认全部片段。拒绝/部分接收的余下字节会原样重试，不重做渲染或重复收费。
     * @param sink 负责字节确认和 backpressure 的宿主 sink。
     * @return Complete、Paused 或包含原始 MarkdownException 的 Failed。
     * @throws IllegalStateException 终态后或重入调用时。
     */
    public func resume(sink: AsyncTextSink): AsyncRenderState {
        if (active || terminal) {
            throw IllegalStateException("HTML output session is active or terminal")
        }
        active = true
        try {
            while (true) {
                cancellation.throwIfCancelled(phase: "render")
                if (pendingOffset >= pending.size) {
                    match (cursor.getOrThrow().nextChunk()) {
                        case Some(chunk) =>
                            pending = chunk
                            pendingOffset = 0
                        case None =>
                            terminal = true
                            release()
                            return AsyncRenderState.Complete
                    }
                }
                let offered = pending[pendingOffset..]
                let outcome = try {
                    sink.write(offered)
                } catch (error: Exception) {
                    throw SinkFailureException(SinkError(error.message))
                }
                var pause = false
                let accepted = match (outcome) {
                    case AsyncSinkWriteResult.Continue => offered.size
                    case AsyncSinkWriteResult.Pause(count) =>
                        pause = true
                        count
                    case AsyncSinkWriteResult.Failed(error) => throw SinkFailureException(error)
                }
                if (accepted < 0 || accepted > offered.size || (accepted < offered.size && (offered[accepted] & 0xC0) ==
                    0x80)) {
                    throw SinkFailureException(SinkError("sink acknowledgement is outside the offered UTF-8 prefix"))
                }
                pendingOffset += accepted
                acknowledged += accepted
                if (pendingOffset == pending.size) {
                    pending = ""
                    pendingOffset = 0
                }
                cancellation.throwIfCancelled(phase: "render")
                if (pause) {
                    return AsyncRenderState.Paused
                }
            }
            throw IllegalStateException("HTML output loop ended without a state")
        } catch (error: MarkdownException) {
            terminal = true
            release()
            AsyncRenderState.Failed(error)
        } catch (error: Exception) {
            terminal = true
            release()
            AsyncRenderState.Failed(MarkdownException(MarkdownErrorCode.RenderFailure, error.message, phase: "render"))
        } finally {
            active = false
        }
    }

    /** sink 已确认接收的累计字节数。 */
    public func bytesWritten(): Int64 {
        acknowledged
    }
    /** 已生成并计入输出预算的累计字节数；未确认重试不会增加此值。 */
    public func bytesProduced(): Int64 {
        budget.usedOutputBytes() - initialOutputBytes
    }
    /** 当前未确认片段与小型编码缓冲的字节数；不包含原始 AST/来源或宿主端口返回值。 */
    public func bufferedBytes(): Int64 {
        let remaining = match (cursor) {
            case Some(value) => value.bufferedBytes();
            case None => 0
        }
        pending.size - pendingOffset + remaining
    }

    private func release(): Unit {
        cursor = None
        pending = ""
        pendingOffset = 0
    }
}
