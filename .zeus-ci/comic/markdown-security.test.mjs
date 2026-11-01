import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import { JSDOM } from 'jsdom';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const purifierSource = readFileSync(path.join(repoRoot, 'frontend/vendor/dompurify-3.4.17.min.js'), 'utf8');
const securitySource = readFileSync(path.join(repoRoot, 'frontend/markdown_security.js'), 'utf8');

function createSanitizerWindow(withDOMPurify = true) {
    const dom = new JSDOM('<!doctype html><html><body></body></html>', {
        url: 'https://chatzeus.example/',
        runScripts: 'dangerously'
    });
    if (withDOMPurify) dom.window.eval(purifierSource);
    dom.window.marked = { parse: (value) => String(value) };
    dom.window.eval(securitySource);
    return dom;
}

test('Markdown sanitizer strips active markup, event handlers, and dangerous URLs', () => {
    const dom = createSanitizerWindow();
    const dirty = [
        '<p>safe text</p>',
        '<script>window.__xss = true</script>',
        '<img src="x" onerror="window.__xss = true">',
        '<svg onload="window.__xss = true"><circle></circle></svg>',
        '<a href="javascript:window.__xss=true" target="_blank" onclick="window.__xss=true">bad link</a>',
        '<a href="/help" target="_blank">safe link</a>',
        '<img src="data:image/svg+xml,<svg onload=alert(1)>" alt="bad data URL">'
    ].join('');

    const clean = dom.window.renderSafeMarkdown(dirty);
    const rendered = dom.window.document.createElement('div');
    rendered.innerHTML = clean;

    assert.equal(rendered.querySelector('p')?.textContent, 'safe text');
    assert.equal(rendered.querySelector('script'), null);
    assert.equal(rendered.querySelector('svg'), null);
    assert.equal(rendered.querySelector('[onerror], [onload], [onclick]'), null);
    assert.equal(rendered.querySelector('img[src^="data:"]'), null);
    assert.equal(rendered.querySelector('a[href^="javascript:"]'), null);
    assert.equal(dom.window.__xss, undefined);

    const safeLink = [...rendered.querySelectorAll('a')].find((link) => link.textContent === 'safe link');
    assert.equal(safeLink?.getAttribute('href'), '/help');
    assert.equal(safeLink?.getAttribute('rel'), 'noopener noreferrer');
    dom.window.close();
});

test('Markdown rendering fails closed to escaped text if sanitizer is unavailable', () => {
    const dom = createSanitizerWindow(false);
    const clean = dom.window.renderSafeMarkdown('<script>window.__xss = true</script>');
    assert.match(clean, /&lt;script&gt;/);
    assert.doesNotMatch(clean, /<script/i);
    assert.equal(dom.window.__xss, undefined);
    dom.window.close();
});

test('all conversation Markdown sinks use the centralized sanitizer', () => {
    const chatFiles = ['frontend/chat_stream.js', 'frontend/chat_management.js'];
    for (const relativePath of chatFiles) {
        const contents = readFileSync(path.join(repoRoot, relativePath), 'utf8');
        assert.doesNotMatch(contents, /marked\.parse\s*\(/, `${relativePath} has a direct Markdown sink`);
    }

    const html = readFileSync(path.join(repoRoot, 'frontend/index.html'), 'utf8');
    assert.match(html, /vendor\/dompurify-3\.4\.17\.min\.js/);
    assert.match(html, /markdown_security\.js/);
});

test('the page has valid inline scripts and loads its local modules in dependency order', () => {
    const html = readFileSync(path.join(repoRoot, 'frontend/index.html'), 'utf8');
    const dom = new JSDOM(html, { url: 'https://chatzeus.example/', runScripts: 'outside-only' });
    const sourcePaths = [...dom.window.document.querySelectorAll('script[src]')]
        .map((script) => script.getAttribute('src'));
    const localPaths = sourcePaths.filter((source) => source.startsWith('/'));

    assert.equal(sourcePaths.some((source) => source === 'script.js' || source === '/script.js'), false);
    for (const source of localPaths) {
        assert.equal(existsSync(path.join(repoRoot, 'frontend', source.replace(/^\//, ''))), true, `missing ${source}`);
    }

    for (const inlineScript of dom.window.document.querySelectorAll('script:not([src])')) {
        if (inlineScript.textContent.trim()) assert.doesNotThrow(() => new Function(inlineScript.textContent));
    }

    dom.window.marked = { parse: (value) => String(value) };
    dom.window.hljs = { highlightElement: () => {} };
    dom.window.tailwind = { config: {} };
    for (const source of localPaths) {
        const scriptPath = path.join(repoRoot, 'frontend', source.replace(/^\//, ''));
        assert.doesNotThrow(() => dom.window.eval(readFileSync(scriptPath, 'utf8')), `failed to load ${source}`);
    }
    dom.window.close();
});
