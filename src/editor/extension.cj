package markdown.editor

/** 为 `DocumentSnapshot` 提供扩展诊断的接口。 */
public interface ExtensionLintProvider {
    /** provider 所属的扩展 id。 */
    prop extensionId: String
    /** provider 的 rule id。 */
    prop ruleId: String
    /** provider 的版本。 */
    prop version: String
    /** 为 snapshot 产生扩展 lint 诊断。
     * @param snapshot 目标文档 snapshot。
     * @return 扩展产生的 lint 诊断数组。
     */
    func lint(snapshot: DocumentSnapshot): Array<LintDiagnostic>
}
