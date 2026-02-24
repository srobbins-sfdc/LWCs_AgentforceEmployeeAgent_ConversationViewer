/**
 * Converts message text (HTML or Markdown) into an HTML string safe for
 * lightning-formatted-rich-text (which sanitizes the output before rendering).
 *
 * Detection heuristic: if the string contains common HTML closing/void tags,
 * treat it as HTML and pass through unchanged. Otherwise run the lightweight
 * markdown-to-HTML converter below.
 */

const HTML_PATTERN = /<\/?(p|br|strong|b|em|i|ul|ol|li|h[1-6]|a|div|span|blockquote|pre|code|table)[\s\/>]/i;

/**
 * Returns a renderable HTML string from raw message text.
 * Safe to pass directly to lightning-formatted-rich-text value.
 *
 * @param {string} text - Raw message text (HTML, Markdown, or plain text)
 * @returns {string} HTML string
 */
export function renderMessageContent(text) {
    if (!text) return '';
    if (HTML_PATTERN.test(text)) return text;
    return markdownToHtml(text);
}

// ---------------------------------------------------------------------------
// Inline formatting helpers
// ---------------------------------------------------------------------------

function inlineFormat(str) {
    // Bold: **text**
    str = str.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
    // Italic: *text* (single asterisk, after bold is already processed)
    str = str.replace(/\*([^*]+)\*/g, '<em>$1</em>');
    // Inline code: `code`
    str = str.replace(/`([^`]+)`/g, '<code>$1</code>');
    return str;
}

// ---------------------------------------------------------------------------
// Markdown-to-HTML converter
// Supports: paragraphs, blank-line breaks, # headers, - /* unordered lists,
//           1. ordered lists, **bold**, *italic*, `inline code`
// ---------------------------------------------------------------------------

const UL_RE = /^[ \t]*[-*+]\s+(.+)/;
const OL_RE = /^[ \t]*\d+[.)]\s+(.+)/;
const H_RE  = /^(#{1,6})\s+(.+)/;
// Inline " N. " or " N) " (N ≥ 2) after sentence end — break into new line so one <ol> gets correct numbering
const INLINE_OL_BREAK = /\.\s+(\d+)[.)]\s+/g;

function markdownToHtml(text) {
    // Normalize: "... compliance. 2. **Up-Sell:**" → "... compliance.\n2. **Up-Sell:**" so list stays one <ol>
    text = text.replace(INLINE_OL_BREAK, '.\n$1. ');
    const lines = text.split('\n');
    const out = [];
    let listType = null;
    const listItems = [];

    const flushList = () => {
        if (listItems.length) {
            out.push(`<${listType}>${listItems.join('')}</${listType}>`);
            listItems.length = 0;
            listType = null;
        }
    };

    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];

        // Unordered list
        const ulMatch = UL_RE.exec(line);
        if (ulMatch) {
            if (listType === 'ol') flushList();
            listType = 'ul';
            listItems.push(`<li>${inlineFormat(ulMatch[1])}</li>`);
            continue;
        }

        // Ordered list (including inline "1. A 2. B 3. C" on one line)
        const olMatch = OL_RE.exec(line);
        if (olMatch) {
            if (listType === 'ul') flushList();
            listType = 'ol';
            const content = olMatch[1];
            const inlineParts = content.split(/\s+(\d+)[.)]\s+/);
            if (inlineParts.length > 1) {
                // "First 2. Second 3. Third" → ["First", "2", "Second", "3", "Third"]; items at 0,2,4...
                for (let j = 0; j < inlineParts.length; j += 2) {
                    const itemText = inlineParts[j].trim();
                    if (itemText) listItems.push(`<li>${inlineFormat(itemText)}</li>`);
                }
            } else {
                listItems.push(`<li>${inlineFormat(content)}</li>`);
            }
            continue;
        }

        // Blank line — skip when inside a list so numbering stays 1,2,3; otherwise paragraph break
        if (line.trim() === '') {
            if (listType !== null) continue;
            flushList();
            out.push('<br>');
            continue;
        }

        flushList();

        // ATX headers
        const hMatch = H_RE.exec(line);
        if (hMatch) {
            const lvl = hMatch[1].length;
            out.push(`<h${lvl}>${inlineFormat(hMatch[2])}</h${lvl}>`);
            continue;
        }

        // Regular paragraph line
        out.push(`<p>${inlineFormat(line)}</p>`);
    }

    flushList();

    return out.join('');
}
