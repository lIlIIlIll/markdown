package markdown.editor

/**
 * 为不可变 DocumentSnapshot 提供扩展诊断的接口。
 *
 * provider 由 `MarkdownLinter` 显式注册，对应 manifest 必须声明 lint capability。
 * 它不是 dialect builder 的解析规则，也不参与解析 fingerprint。
 * @see markdown.editor.MarkdownLinter
 */
public interface ExtensionLintProvider {
    /**
     * provider 所属的扩展 id。
     * @return engine 已注册且声明 lint capability 的 manifest extensionId。
     */
    prop extensionId: String
    /**
     * provider 在该扩展内唯一的规则 id。
     * @return 非空规则标识，与 extensionId 共同决定注册唯一性。
     */
    prop ruleId: String
    /**
     * provider 的实现版本。
     * @return 非空版本标识；不参与解析 fingerprint。
     */
    prop version: String
    /** 为 snapshot 产生扩展 lint 诊断。
     * @param snapshot 目标文档 snapshot。
     * @return 扩展产生的诊断数组；fix 必须绑定目标 snapshot 的 source digest 和 Document revision。
     */
    func lint(snapshot: DocumentSnapshot): Array<LintDiagnostic>
}
