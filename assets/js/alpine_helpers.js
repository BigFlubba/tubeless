window.copyTextToClipboard = async (text) => {
  // Navigator clipboard api needs a secure context (https)
  if (navigator.clipboard && window.isSecureContext) {
    await navigator.clipboard.writeText(text)
  } else {
    const textArea = document.createElement('textarea')
    textArea.value = text
    // Move textarea out of the viewport so it's not visible
    textArea.style.position = 'absolute'
    textArea.style.left = '-999999px'

    document.body.prepend(textArea)
    textArea.select()

    try {
      document.execCommand('copy')
    } catch (error) {
      console.error(error)
    } finally {
      textArea.remove()
    }
  }
}

window.copyWithCallbacks = async (text, onCopy, onAfterDelay, delay = 4000) => {
  await window.copyTextToClipboard(text)
  onCopy()
  setTimeout(onAfterDelay, delay)
}

window.markVersionAsSeen = (versionString) => {
  localStorage.setItem('seenVersion', versionString)
}

window.isVersionSeen = (versionString) => {
  return localStorage.getItem('seenVersion') === versionString
}

window.dispatchFor = (elementOrId, eventName, detail = {}) => {
  const element =
    typeof elementOrId === 'string' ? document.getElementById(elementOrId) : elementOrId

  // This is needed to ensure the DOM has updated before dispatching the event.
  // Doing so ensures that the latest DOM state is what's sent to the server
  setTimeout(() => {
    element.dispatchEvent(new Event(eventName, { bubbles: true, detail }))
  }, 0)
}

// Client-side sanity checks for output-path templates (the free-text box on the
// media profile and source forms). This is warn-only: the Ecto changeset stays
// the source of truth. We mirror the backend grammar/regex so the messages match
// what actually happens at download time.
//
// The template mixes three syntaxes freely: liquid-style `{{ identifier }}`,
// yt-dlp-style `%( ... )s`, and bare literal path text. The liquid parser
// (lib/pinchflat/downloading/output_path/base.ex) is strict - an identifier is
// only `[a-zA-Z0-9_]` - so most user mistakes live in the `{{ }}` blocks.
//
// Returns an array of warning strings (empty means no issues found).
window.validateOutputTemplate = (rawValue) => {
  const value = rawValue == null ? '' : String(rawValue)
  const warnings = []

  if (value.trim() === '') {
    return ['Template can’t be blank.']
  }

  if (value !== value.trim()) {
    warnings.push('Remove leading/trailing spaces.')
  }

  // Walk the `{{ ... }}` blocks, checking that each one is closed and that its
  // contents are a single valid identifier. Anything outside the blocks is
  // treated as literal text (which may still contain yt-dlp `%( )s` syntax).
  let unbalanced = false
  let badIdentifier = false
  let index = 0

  while (index < value.length) {
    const open = value.indexOf('{{', index)
    if (open === -1) break

    const close = value.indexOf('}}', open + 2)
    if (close === -1) {
      unbalanced = true
      break
    }

    const identifier = value.slice(open + 2, close).trim()
    if (!/^[a-zA-Z0-9_]+$/.test(identifier)) {
      badIdentifier = true
    }

    index = close + 2
  }

  // Catch stray single braces (e.g. `{ title }` or a `}` with no `{{`) once the
  // well-formed `{{ ... }}` pairs are removed.
  const withoutBlocks = value.replace(/\{\{[^}]*\}\}/g, '')
  if (unbalanced || /[{}]/.test(withoutBlocks)) {
    warnings.push('Unbalanced or stray `{` or `}` — did you mean `{{ … }}`?')
  }

  if (badIdentifier) {
    warnings.push('`{{ … }}` must contain a single word (letters, numbers, underscores only).')
  }

  // Must end with an extension token - mirrors MediaProfile.ext_regex/0.
  if (!/\.(\{\{ ?ext ?\}\}|%\( ?ext ?\)[sS])$/.test(value.trim())) {
    warnings.push('Should end with `.{{ ext }}` (or `.%(ext)s`).')
  }

  // Filesystem-hostile characters, but only in the literal parts: strip the
  // `{{ }}` and `%( )s` segments first so yt-dlp date syntax like
  // `%(upload_date>%Y)S` (and its `:`/`>`) isn't flagged.
  const literalOnly = value.replace(/\{\{[^}]*\}\}/g, '').replace(/%\([^)]*\)[a-zA-Z]/g, '')
  const badChars = (literalOnly.match(/[\\*?"<>|\x00-\x1f]/g) || []).filter(
    (char, pos, all) => all.indexOf(char) === pos
  )
  if (badChars.length > 0) {
    warnings.push(`Avoid these characters in the path: ${badChars.join(' ')}`)
  }

  // Path traversal / home expansion. A leading `/` is normal here (the default
  // template starts with one) and is intentionally NOT flagged.
  if (/(^|\/)\.\.(\/|$)/.test(value) || /^\s*~/.test(value)) {
    warnings.push('`..` / `~` aren’t allowed — the path is relative to the library root.')
  }

  return warnings
}
