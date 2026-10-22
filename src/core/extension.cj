package markdown.core

import std.collection.*
import std.sort.sort

/** block 参数解析后的 typed value。 */
public enum SyntaxParameterValue {
    /** 字符串值。 */
    | StringValue(String)
    /** 整数值。 */
    | IntegerValue(Int64)
    /** 布尔值。 */
    | BooleanValue(Bool)
    /** 标识符值。 */
    | IdentifierValue(String)
}

/** 内建 DSL custom node 使用的 payload，保留 raw 参数、literal 和 typed values。 */
public class SyntaxPayload <: CustomPayload {
    /** block 名称。 */
    public let name: String
    /** 原始参数文本。 */
    public let parameters: String
    /** 原始 body 文本。 */
    public let literal: String
    private let typedValues: HashMap<String, SyntaxParameterValue>

    /**
     * 创建 payload。
     * @param name block 名称。
     * @param parameters 原始参数文本。
     * @param literal 原始 body 文本。
     * @param typedValues 已解析的 typed 参数表。
     */
    public init(name: String, parameters: String, literal: String,
        typedValues!: HashMap<String, SyntaxParameterValue> = HashMap<String, SyntaxParameterValue>()) {
        this.name = name
        this.parameters = parameters
        this.literal = literal
        this.typedValues = HashMap<String, SyntaxParameterValue>()
        for ((key, value) in typedValues) {
            this.typedValues.add(key, value)
        }
    }
    /**
     * 返回稳定 payload type identity。
     * @return 稳定的 payload type 标识。
     */
    public func payloadTypeId(): String {
        "markdown.syntax-payload.v1"
    }
    /** 按名称读取 typed parameter；不存在时返回 None。
     * @param name 参数名称。
     * @return 对应的 typed 参数值；不存在时为 `None`。
     */
    public func parameter(name: String): ?SyntaxParameterValue {
        typedValues.get(name)
    }
    /** 按参数名排序写入 typed 参数，保持 artifact 身份编码确定性。
     * @param out 用于累计参数名称、类型和值的 canonical 描述器。
     */
    protected func appendArtifactParameters(out: CanonicalDescriptor): Unit {
        let keys = ArrayList<String>()
        for ((key, _) in typedValues) {
            keys.add(key)
        }
        let ordered = keys.toArray()
        sort(ordered, lessThan: {left, right => left < right})
        out.append(ordered.size)
        for (key in ordered) {
            out.append(key)
            match (typedValues[key]) {
                case SyntaxParameterValue.StringValue(value) =>
                    out.append("string");
                    out.append(value)
                case SyntaxParameterValue.IdentifierValue(value) =>
                    out.append("identifier");
                    out.append(value)
                case SyntaxParameterValue.IntegerValue(value) =>
                    out.append("integer");
                    out.append(value)
                case SyntaxParameterValue.BooleanValue(value) =>
                    out.append("boolean");
                    out.append(value)
            }
        }
    }
}
