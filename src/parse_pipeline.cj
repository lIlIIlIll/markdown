package markdown

import std.collection.*

/** Shared complete-document pipeline after either batch or append construction. */
internal func finishParsedDocument(arena: Document, source: SourceBuffer, diagnostics: ArrayList<Diagnostic>,
    profile: MarkdownProfile, dialect: CompiledMarkdownDialect, bindingOptions: BindingOptions, limits: ParseLimits,
    budget: OperationBudget, cancellation: CancellationToken, requiresBinding!: Bool): ParseResult {
    var document = arena
    if (dialect.parserHotPlan.hasDocumentProcessors) {
        for (index in 0..dialect.documentProcessors.size) {
            let processor = dialect.documentProcessors[index]
            cancellation.throwIfCancelled(phase: "extension_process")
            budget.consumeExtensionCallback()
            budget.consumeTransform()
            try {
                document = processor.process(document, budget, cancellation)
                document.requireSource(source)
            } catch (error: ExtensionFailureException) {
                throw error
            } catch (error: Exception) {
                let manifest = compiledExtensionManifest(dialect, processor.extensionId)
                throw ExtensionFailureException(processor.extensionId, manifest.semanticVersion,
                    manifest.implementationVersion, "extension_process", error, ruleId: Some(processor.processorId))
            }
            let root = document.root().asDocument().getOrThrow()
            if (!root.profile.sameIdentity(profile) || root.dialectFingerprint != dialect.fingerprint) {
                throw MarkdownException(MarkdownErrorCode.InternalInvariantViolation,
                    "document processor changed profile or dialect identity", phase: "extension_process")
            }
            AstInvariantValidator().validate(document, limits: limits)
        }
    }
    if (requiresBinding || dialect.parserHotPlan.hasDocumentProcessors || (dialect.parserOptions.extensionsEnabled &&
        dialect.parserHotPlan.headingIdRule.isSome())) {
        document = DocumentBinder.bind(document, bindingOptions, limits, budget, cancellation,
            headingsEnabled: dialect.parserOptions.extensionsEnabled && dialect.parserHotPlan.headingIdRule.isSome())
        diagnostics.add(all: document.bindings.diagnostics.toArray())
    }
    ParseResult(document, source, diagnostics.toArray())
}

private func compiledExtensionManifest(dialect: CompiledMarkdownDialect, extensionId: String): ExtensionManifest {
    for (index in 0..dialect.manifests.size) {
        let manifest = dialect.manifests[index]
        if (manifest.extensionId == extensionId) {
            return manifest
        }
    }
    throw IllegalStateException("compiled dialect is missing extension manifest")
}
