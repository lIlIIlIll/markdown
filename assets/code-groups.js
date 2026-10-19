// Optional Code Groups 1.0 enhancement. It never evaluates code or loads assets.
let nextGroup = 0;
const maximumCopyBytes = 4 * 1024 * 1024;

function copyText(figure, limit) {
  const hex = figure.getAttribute("data-code-copy-hex");
  if (hex === null || hex.length % 2 || hex.length / 2 > limit || !/^[0-9a-f]*$/i.test(hex)) return null;
  const bytes = new Uint8Array(hex.length / 2);
  for (let index = 0; index < bytes.length; index++) bytes[index] = Number.parseInt(hex.slice(index * 2, index * 2 + 2), 16);
  try {
    return new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(bytes);
  } catch {
    return null;
  }
}

function groupPrefix(document, count) {
  while (true) {
    const prefix = `markdown-code-${++nextGroup}`;
    let collision = false;
    for (let index = 0; index < count; index++) {
      if (document.getElementById(`${prefix}-tab-${index}`) || document.getElementById(`${prefix}-panel-${index}`)) collision = true;
    }
    if (!collision) return prefix;
  }
}

/** Enhance explicitly marked groups. Invoke again after adding new rendered HTML. */
export function enhanceCodeGroups(root = document) {
  const groups = Array.from(root.querySelectorAll('[data-code-group="1"]'));
  if (root.matches?.('[data-code-group="1"]')) groups.unshift(root);
  let enhanced = 0;
  for (const group of groups) {
    if (group.dataset.codeGroupEnhanced === "1") continue;
    const figures = Array.from(group.children).filter(child => child.matches("figure.code-group-item"));
    if (!figures.length || figures.some(figure => !figure.querySelector(":scope > figcaption") || !figure.querySelector(":scope > pre > code"))) continue;
    const document = group.ownerDocument;
    const prefix = groupPrefix(document, figures.length);
    const label = name => group.getAttribute(`data-${name}`);
    const copyLabel = label("copy-label") || "Copy code";
    const copiedLabel = label("copied-label") || "Copied";
    const failedLabel = label("copy-failed-label") || "Copy failed";
    const unavailableLabel = label("copy-unavailable-label") || "Copy unavailable";
    const configuredLimit = Number(group.getAttribute("data-copy-limit"));
    const limit = Number.isSafeInteger(configuredLimit) && configuredLimit >= 0
      ? Math.min(configuredLimit, maximumCopyBytes) : 0;
    const tabs = document.createElement("div");
    tabs.className = "code-group-tabs";
    tabs.setAttribute("role", "tablist");
    tabs.setAttribute("aria-label", group.getAttribute("aria-label") || "Code examples");
    const status = document.createElement("span");
    status.className = "code-group-status";
    status.setAttribute("role", "status");
    status.setAttribute("aria-live", "polite");
    const buttons = [];
    function activate(index, focus) {
      for (let current = 0; current < buttons.length; current++) {
        const selected = current === index;
        buttons[current].setAttribute("aria-selected", String(selected));
        buttons[current].tabIndex = selected ? 0 : -1;
        figures[current].hidden = !selected;
      }
      status.textContent = "";
      if (focus) buttons[index].focus();
    }
    for (let index = 0; index < figures.length; index++) {
      const figure = figures[index];
      const button = document.createElement("button");
      button.type = "button";
      button.id = `${prefix}-tab-${index}`;
      button.setAttribute("role", "tab");
      button.textContent = figure.querySelector(":scope > figcaption").textContent || String(index + 1);
      figure.id = `${prefix}-panel-${index}`;
      figure.setAttribute("role", "tabpanel");
      figure.setAttribute("aria-labelledby", button.id);
      figure.tabIndex = 0;
      button.setAttribute("aria-controls", figure.id);
      button.addEventListener("click", () => activate(index, false));
      button.addEventListener("keydown", event => {
        let target;
        if (event.key === "ArrowRight") target = (index + 1) % figures.length;
        if (event.key === "ArrowLeft") target = (index + figures.length - 1) % figures.length;
        if (event.key === "Home") target = 0;
        if (event.key === "End") target = figures.length - 1;
        if (target !== undefined) {
          event.preventDefault();
          activate(target, true);
        }
      });
      tabs.append(button);
      buttons.push(button);
      const copy = document.createElement("button");
      copy.type = "button";
      copy.className = "code-copy";
      copy.textContent = copyLabel;
      const text = copyText(figure, limit);
      if (text === null || !globalThis.navigator?.clipboard?.writeText) {
        copy.disabled = true;
        copy.textContent = unavailableLabel;
        copy.title = unavailableLabel;
        copy.setAttribute("aria-label", `${copyLabel}: ${unavailableLabel}`);
      } else {
        copy.addEventListener("click", async () => {
          copy.disabled = true;
          try {
            await globalThis.navigator.clipboard.writeText(text);
            status.textContent = copiedLabel;
          } catch {
            status.textContent = failedLabel;
          } finally {
            copy.disabled = false;
          }
        });
      }
      figure.append(copy);
    }
    group.insertBefore(tabs, figures[0]);
    group.append(status);
    group.dataset.codeGroupEnhanced = "1";
    activate(0, false);
    enhanced++;
  }
  return enhanced;
}
