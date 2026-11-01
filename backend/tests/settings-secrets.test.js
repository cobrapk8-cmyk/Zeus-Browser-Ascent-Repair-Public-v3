const assert = require('node:assert/strict');
const test = require('node:test');
const { mergeCustomProviders, mergeSecretKeys, publicSettings } = require('../lib/settings-secrets');

test('public settings redact top-level and custom-provider API keys', () => {
    const privateSettings = {
        geminiApiKeys: [{ _id: 'g1', key: 'secret-gemini', status: 'active' }],
        openrouterApiKeys: [{ _id: 'o1', key: 'secret-router', status: 'inactive' }],
        customProviders: [{
            id: 'custom_1',
            name: 'Local provider',
            apiKeys: [{ _id: 'c1', key: 'secret-custom', status: 'active' }]
        }]
    };

    const output = publicSettings(privateSettings);
    assert.deepEqual(output.geminiApiKeys, [{ id: 'g1', key: '', hasKey: true, status: 'active' }]);
    assert.deepEqual(output.openrouterApiKeys, [{ id: 'o1', key: '', hasKey: true, status: 'inactive' }]);
    assert.deepEqual(output.customProviders[0].apiKeys, [{ id: 'c1', key: '', hasKey: true, status: 'active' }]);
    assert.equal(JSON.stringify(output).includes('secret-'), false);
});

test('redacted arrays preserve saved keys, allow rotation and status change, and honor removal', () => {
    const stored = [
        { _id: 'g1', key: 'old-key-1', status: 'active' },
        { _id: 'g2', key: 'old-key-2', status: 'active' }
    ];
    const incoming = [
        { id: 'g1', key: '', hasKey: true, status: 'inactive' },
        { id: 'g2', key: 'rotated-key-2', hasKey: true, status: 'active' },
        { key: '', status: 'active' }
    ];

    assert.deepEqual(mergeSecretKeys(incoming, stored), [
        { _id: 'g1', key: 'old-key-1', status: 'inactive' },
        { _id: 'g2', key: 'rotated-key-2', status: 'active' }
    ]);
    assert.deepEqual(mergeSecretKeys([{ id: 'g2', key: '', hasKey: true }], stored), [
        { _id: 'g2', key: 'old-key-2', status: 'active' }
    ]);
    assert.deepEqual(mergeSecretKeys([{ key: '', status: 'active' }], [stored[0]]), []);
    assert.deepEqual(mergeSecretKeys([], stored), []);
});

test('custom provider metadata updates preserve the matching provider secrets by provider id', () => {
    const existing = [
        { id: 'custom_a', name: 'A', apiKeys: [{ _id: 'secret-a', key: 'A-key', status: 'active' }] },
        { id: 'custom_b', name: 'B', apiKeys: [{ _id: 'secret-b', key: 'B-key', status: 'active' }] }
    ];
    const incoming = [
        { id: 'custom_b', name: 'B new', baseUrl: 'https://example.test', apiKeys: [{ id: 'secret-b', key: '', hasKey: true }] },
        { id: 'custom_a', name: 'A', apiKeys: [] }
    ];

    const merged = mergeCustomProviders(incoming, existing);
    assert.equal(merged[0].name, 'B new');
    assert.deepEqual(merged[0].apiKeys, [{ _id: 'secret-b', key: 'B-key', status: 'active' }]);
    assert.deepEqual(merged[1].apiKeys, []);
});
