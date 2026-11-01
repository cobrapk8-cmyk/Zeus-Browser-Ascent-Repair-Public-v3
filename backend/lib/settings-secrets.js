function plain(value) {
    if (value && typeof value.toObject === 'function') return value.toObject();
    return value || {};
}

function secretListForClient(items) {
    if (!Array.isArray(items)) return [];
    return items.map((value, index) => {
        const item = plain(value);
        return {
            id: String(item._id || item.id || index),
            key: '',
            hasKey: Boolean(item.key),
            status: item.status === 'inactive' ? 'inactive' : 'active'
        };
    });
}

function publicSettings(value) {
    if (!value) return value;
    const settings = plain(value);
    const result = { ...settings };
    result.geminiApiKeys = secretListForClient(settings.geminiApiKeys);
    result.openrouterApiKeys = secretListForClient(settings.openrouterApiKeys);
    result.customProviders = Array.isArray(settings.customProviders)
        ? settings.customProviders.map((value) => {
            const provider = plain(value);
            return { ...provider, apiKeys: secretListForClient(provider.apiKeys) };
        })
        : [];
    return result;
}

function normalizeStatus(status, fallback = 'active') {
    if (status === 'inactive' || status === 'active') return status;
    return fallback === 'inactive' ? 'inactive' : 'active';
}

function mergeSecretKeys(incoming, existing) {
    const current = Array.isArray(existing) ? existing.map(plain) : [];
    if (!Array.isArray(incoming)) return current;

    const byId = new Map();
    current.forEach((item) => {
        const id = item._id || item.id;
        if (id) byId.set(String(id), item);
    });

    return incoming.flatMap((value, index) => {
        const item = plain(value);
        const id = item.id || item._id;
        const matchedById = id ? byId.get(String(id)) : undefined;
        const old = id ? matchedById : current[index];
        const suppliedKey = typeof item.key === 'string' && item.key.length > 0 ? item.key : '';

        if (suppliedKey) {
            const entry = { key: suppliedKey, status: normalizeStatus(item.status, old?.status || 'active') };
            if (old?._id) entry._id = old._id;
            return [entry];
        }

        // Empty values from the redacted client representation mean keep an
        // existing secret. Removing an entry from the array removes the key.
        if (old?.key && (matchedById || (!id && item.hasKey === true))) {
            return [{ _id: old._id, key: old.key, status: normalizeStatus(item.status, old.status || 'active') }];
        }
        return [];
    });
}

function mergeCustomProviders(incoming, existing) {
    const current = Array.isArray(existing) ? existing.map(plain) : [];
    if (!Array.isArray(incoming)) return current;
    const byId = new Map(current.filter((provider) => provider.id).map((provider) => [String(provider.id), provider]));

    return incoming.map((value, index) => {
        const provider = plain(value);
        const old = (provider.id && byId.get(String(provider.id))) || current[index];
        return {
            id: provider.id,
            name: provider.name,
            baseUrl: provider.baseUrl,
            models: Array.isArray(provider.models) ? provider.models : [],
            apiKeys: mergeSecretKeys(provider.apiKeys, old?.apiKeys)
        };
    });
}

module.exports = { mergeCustomProviders, mergeSecretKeys, publicSettings, secretListForClient };
