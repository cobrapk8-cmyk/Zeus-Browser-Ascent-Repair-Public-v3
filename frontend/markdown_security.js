(function installMarkdownSecurity(global) {
    const allowedTags = [
        'a', 'blockquote', 'br', 'code', 'del', 'em', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
        'hr', 'img', 'input', 'li', 'ol', 'p', 'pre', 's', 'strong', 'sub', 'sup',
        'table', 'tbody', 'td', 'th', 'thead', 'tr', 'ul'
    ];
    const allowedAttributes = [
        'alt', 'checked', 'class', 'disabled', 'href', 'rel', 'src', 'start', 'target', 'title', 'type'
    ];

    function escapeHTML(value) {
        const element = global.document.createElement('div');
        element.textContent = String(value ?? '');
        return element.innerHTML;
    }

    const purifier = global.DOMPurify;
    if (purifier) {
        purifier.addHook('uponSanitizeAttribute', (_node, data) => {
            if (data.attrName === 'href' || data.attrName === 'src') {
                const rawValue = String(data.attrValue || '').trim();
                if (data.attrName === 'href' && rawValue.startsWith('#')) return;

                try {
                    const parsed = new URL(rawValue, global.document.baseURI);
                    const allowedProtocols = data.attrName === 'href'
                        ? ['http:', 'https:', 'mailto:', 'tel:']
                        : ['http:', 'https:'];
                    if (!allowedProtocols.includes(parsed.protocol)) data.keepAttr = false;
                } catch (_error) {
                    data.keepAttr = false;
                }
            }

            if (data.attrName === 'target' && !['_blank', '_self'].includes(data.attrValue)) {
                data.keepAttr = false;
            }
        });

        purifier.addHook('afterSanitizeAttributes', (node) => {
            if (node.nodeName === 'A' && node.getAttribute('target') === '_blank') {
                node.setAttribute('rel', 'noopener noreferrer');
            }
        });
    }

    global.renderSafeMarkdown = function renderSafeMarkdown(markdown) {
        const source = String(markdown ?? '');
        if (!global.marked || typeof global.marked.parse !== 'function' || !purifier) {
            return escapeHTML(source).replace(/\r?\n/g, '<br>');
        }

        const dirtyHTML = global.marked.parse(source);
        return purifier.sanitize(dirtyHTML, {
            ALLOWED_TAGS: allowedTags,
            ALLOWED_ATTR: allowedAttributes,
            ALLOW_DATA_ATTR: false,
            SANITIZE_NAMED_PROPS: true
        });
    };
})(window);
