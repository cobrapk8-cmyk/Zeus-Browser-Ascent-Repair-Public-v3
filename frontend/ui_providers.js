
// تحديث المزودين المخصصين في كائن providers
function updateCustomProviders() {
    // إزالة المزودين المخصصين القدامى
    Object.keys(providers).forEach(key => {
        if (key.startsWith('custom_')) {
            delete providers[key];
        }
    });

    // إضافة المزودين المخصصين الجدد
    settings.customProviders.forEach(provider => {
        providers[provider.id] = {
            name: provider.name,
            models: provider.models || []
        };
    });
}

function initializeEventListeners() {
    const messageInput = document.getElementById('messageInput');
    const temperatureSlider = document.getElementById('temperatureSlider');
    const providerSelect = document.getElementById('providerSelect');
document.getElementById('fileInput').addEventListener('change', updateSendButton);

const chkEnableBrowsing = document.getElementById('enableWebBrowsing');
const selBrowsingMode   = document.getElementById('browsingMode');
const chkShowSources    = document.getElementById('showSources');
const dynThresholdSlider = document.getElementById('dynamicThresholdSlider');
const dynThresholdValue = document.getElementById('dynamicThresholdValue');

// تحميل الحالة الحالية في الواجهة
if (chkEnableBrowsing) chkEnableBrowsing.checked = settings.enableWebBrowsing || false;
if (selBrowsingMode) selBrowsingMode.value = settings.browsingMode || 'gemini';
if (chkShowSources) chkShowSources.checked = settings.showSources !== false; // افتراضي true
if (dynThresholdSlider) {
    dynThresholdSlider.value = settings.dynamicThreshold || 0.6;
    if (dynThresholdValue) dynThresholdValue.textContent = (settings.dynamicThreshold || 0.6).toFixed(1);
}

// استماع للتغييرات وتحديث settings
chkEnableBrowsing?.addEventListener('change', e => {
    settings.enableWebBrowsing = e.target.checked;
    console.log('Web browsing toggled:', e.target.checked);
});
selBrowsingMode?.addEventListener('change', e => settings.browsingMode = e.target.value);
chkShowSources?.addEventListener('change', e => settings.showSources = e.target.checked);
dynThresholdSlider?.addEventListener('input', e => {
    settings.dynamicThreshold = parseFloat(e.target.value);
    if (dynThresholdValue) dynThresholdValue.textContent = parseFloat(e.target.value).toFixed(1);
});

    if (messageInput) {
        messageInput.addEventListener('input', function() {
            updateSendButton();
            // Auto-resize textarea
            this.style.height = 'auto';
            this.style.height = Math.min(this.scrollHeight, 128) + 'px';
        });

        messageInput.addEventListener('keydown', function(e) {
            if (e.key === 'Enter' && !e.shiftKey) {
                e.preventDefault();
                sendMessage();
            }
        });
    }

    if (temperatureSlider) {
        temperatureSlider.addEventListener('input', function() {
            document.getElementById('temperatureValue').textContent = this.value;
        });
    }

    if (providerSelect) {
        providerSelect.addEventListener('change', function() {
            updateProviderUI();
            updateModelOptions();
        });
    }

    const fontSizeSlider = document.getElementById('fontSizeSlider');
    if (fontSizeSlider) {
        fontSizeSlider.addEventListener('input', function() {
            const size = this.value;
            document.getElementById('fontSizeValue').textContent = `${size}px`;
            updateFontSize(size);
        });
    }
}

// --- New Function ---
function updateFontSize(size) {
    document.documentElement.style.setProperty('--message-font-size', `${size}px`);
}

// Provider and model management
function updateProviderUI() {
    const provider = document.getElementById('providerSelect').value;
    const geminiSection = document.getElementById('geminiApiKeysSection');
    const openrouterSection = document.getElementById('openrouterApiKeysSection');
    const customSection = document.getElementById('customProviderApiKeysSection');

    // إخفاء جميع الأقسام أولاً
    geminiSection.classList.add('hidden');
    openrouterSection.classList.add('hidden');
    if (customSection) customSection.classList.add('hidden');

    // إظهار القسم المناسب
    if (provider === 'gemini') {
        geminiSection.classList.remove('hidden');
    } else if (provider === 'openrouter') {
        openrouterSection.classList.remove('hidden');
    } else if (provider.startsWith('custom_')) {
        // مزود مخصص - إظهار قسم مفاتيح API الخاص به
        if (customSection) {
            customSection.classList.remove('hidden');
            updateCustomProviderApiKeysUI(provider);
        }
    }

    updateModelOptions();
}

// تحديث واجهة مفاتيح API للمزود المخصص المحدد
function updateCustomProviderApiKeysUI(providerId) {
    const customProvider = settings.customProviders.find(p => p.id === providerId);
    if (!customProvider) return;

    // تحديث عنوان القسم
    const label = document.getElementById('customProviderApiKeysLabel');
    if (label) {
        label.textContent = `مفاتيح ${customProvider.name} API`;
    }

    // عرض مفاتيح API
    renderCustomProviderApiKeys(providerId);
}

function updateModelOptions() {
    const provider = document.getElementById('providerSelect').value;
    const modelSelect = document.getElementById('modelSelect');

    modelSelect.innerHTML = '';

    if (providers[provider]) {
        // عرض النماذج للمزود المحدد
        providers[provider].models.forEach(model => {
            const option = document.createElement('option');
            option.value = model.id;
            option.textContent = model.name;
            modelSelect.appendChild(option);
        });
    }

    // تعيين النموذج الحالي إذا كان موجوداً
    const currentModel = settings.model;
    const modelExists = Array.from(modelSelect.options).some(option => option.value === currentModel);

    if (modelExists) {
        modelSelect.value = currentModel;
    } else {
        // إذا لم يكن النموذج الحالي موجوداً، اختر الأول
        if (modelSelect.options.length > 0) {
            modelSelect.value = modelSelect.options[0].value;
        }
    }
}

// إدارة مفاتيح API للمزودين المخصصين
function renderCustomProviderApiKeys(providerId) {
    const customProvider = settings.customProviders.find(p => p.id === providerId);
    if (!customProvider) return;

    const container = document.getElementById('customProviderApiKeysContainer');
    container.innerHTML = '';

    if (!customProvider.apiKeys || customProvider.apiKeys.length === 0) {
        container.innerHTML = `
            <div class="text-center text-gray-500 dark:text-gray-400 py-4">
                <i class="fas fa-key text-2xl mb-2"></i>
                <p>لا توجد مفاتيح API بعد</p>
                <p class="text-xs">اضغط على "أضف مفتاحاً جديداً" لإضافة مفتاح API</p>
            </div>
        `;
        return;
    }

    customProvider.apiKeys.forEach((apiKey, index) => {
        const keyDiv = document.createElement('div');
        keyDiv.className = 'flex items-center space-x-3 space-x-reverse';
        keyDiv.innerHTML = `
            <div class="relative flex-1">
                <input type="password" value="${escapeHtml(apiKey.key || '')}"
                    id="customProviderApiKeyInput-${escapeHtml(providerId)}-${index}"
                    class="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-lg bg-white/80 dark:bg-gray-700/80 text-gray-900 dark:text-white text-base pl-10 backdrop-blur-sm"
                    placeholder="${apiKey.hasKey ? 'مفتاح محفوظ؛ أدخل قيمة جديدة لتغييره' : 'أدخل مفتاح API'}">
                <button type="button" data-action="toggle"
                    class="absolute left-3 top-1/2 transform -translate-y-1/2 text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200">
                    <i id="customProviderApiKeyToggleIcon-${escapeHtml(providerId)}-${index}" class="fas fa-eye"></i>
                </button>
            </div>
            <div class="flex items-center space-x-2 space-x-reverse">
                <span class="status-indicator ${apiKey.status === 'active' ? 'bg-green-500' : 'bg-red-500'} w-3 h-3 rounded-full"></span>
                <span class="text-xs text-gray-500 dark:text-gray-400">${apiKey.status === 'active' ? 'نشط' : 'معطل'}</span>
            </div>
            <button type="button" data-action="remove"
                class="p-2 text-red-500 hover:text-red-700 dark:text-red-400 dark:hover:text-red-300 transition-colors">
                <i class="fas fa-trash text-sm"></i>
            </button>
        `;
        keyDiv.querySelector('input').addEventListener('change', (event) => {
            updateCustomProviderApiKeyValue(providerId, index, event.currentTarget.value);
        });
        keyDiv.querySelector('[data-action="toggle"]').addEventListener('click', () => {
            toggleCustomProviderApiKeyVisibility(providerId, index);
        });
        keyDiv.querySelector('[data-action="remove"]').addEventListener('click', () => {
            removeCustomProviderApiKey(providerId, index);
        });
        container.appendChild(keyDiv);
    });
}

function addCustomProviderApiKey() {
    const provider = document.getElementById('providerSelect').value;
    if (!provider.startsWith('custom_')) return;

    const customProvider = settings.customProviders.find(p => p.id === provider);
    if (!customProvider) return;

    if (!customProvider.apiKeys) {
        customProvider.apiKeys = [];
    }

    customProvider.apiKeys.push({
        key: '',
        status: 'active'
    });
    renderCustomProviderApiKeys(provider);
}

function removeCustomProviderApiKey(providerId, index) {
    const customProvider = settings.customProviders.find(p => p.id === providerId);
    if (!customProvider || !customProvider.apiKeys) return;

    customProvider.apiKeys.splice(index, 1);
    renderCustomProviderApiKeys(providerId);
}

function updateCustomProviderApiKeyValue(providerId, index, value) {
    const customProvider = settings.customProviders.find(p => p.id === providerId);
    if (!customProvider || !customProvider.apiKeys || !customProvider.apiKeys[index]) return;

    customProvider.apiKeys[index].key = value;
}

function toggleCustomProviderApiKeyVisibility(providerId, index) {
    const input = document.getElementById(`customProviderApiKeyInput-${providerId}-${index}`);
    const icon = document.getElementById(`customProviderApiKeyToggleIcon-${providerId}-${index}`);

    if (input.type === 'password') {
        input.type = 'text';
        icon.className = 'fas fa-eye-slash';
    } else {
        input.type = 'password';
        icon.className = 'fas fa-eye';
    }
}

// إدارة المزودين المخصصين
function openCustomProvidersManager() {
    document.getElementById('customProvidersModal').classList.remove('hidden');
    renderCustomProviders();
}

function closeCustomProvidersManager() {
    document.getElementById('customProvidersModal').classList.add('hidden');
}

function renderCustomProviders() {
    const container = document.getElementById('customProvidersContainer');
    container.innerHTML = '';

    if (settings.customProviders.length === 0) {
        container.innerHTML = `
            <div class="text-center text-gray-500 dark:text-gray-400 py-8">
                <i class="fas fa-server text-4xl mb-4"></i>
                <p>لا توجد مزودين مخصصين بعد</p>
                <p class="text-sm">اضغط على "إضافة مزود جديد" لإنشاء مزود مخصص</p>
            </div>
        `;
        return;
    }

    settings.customProviders.forEach((provider, index) => {
        const providerCard = document.createElement('div');
        providerCard.className = 'glass-effect p-4 rounded-lg border border-gray-300 dark:border-gray-600';
        providerCard.innerHTML = `
            <div class="flex items-start justify-between mb-3">
                <div class="flex-1">
                    <input type="text" value="${escapeHtml(provider.name || '')}"
                        onchange="updateCustomProviderName(${index}, this.value)"
                        class="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-lg bg-white/80 dark:bg-gray-700/80 text-gray-900 dark:text-white text-base backdrop-blur-sm"
                        placeholder="اسم المزود">
                </div>
                <button onclick="removeCustomProvider(${index})"
                    class="p-2 ml-2 text-red-500 hover:text-red-700 dark:text-red-400 dark:hover:text-red-300 transition-colors">
                    <i class="fas fa-trash"></i>
                </button>
            </div>
            <div class="mb-3">
                <input type="text" value="${escapeHtml(provider.baseUrl || '')}"
                    onchange="updateCustomProviderBaseUrl(${index}, this.value)"
                    class="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-lg bg-white/80 dark:bg-gray-700/80 text-gray-900 dark:text-white text-base backdrop-blur-sm"
                    placeholder="رابط API الأساسي">
            </div>
            <div class="space-y-2">
                <div class="flex items-center justify-between">
                    <span class="text-sm font-medium text-gray-700 dark:text-gray-300">النماذج:</span>
                    <button onclick="addCustomProviderModel(${index})"
                        class="text-xs text-zeus-accent hover:text-zeus-accent-hover transition-colors">
                        <i class="fas fa-plus ml-1"></i>إضافة نموذج
                    </button>
                </div>
                <div id="customProviderModels-${index}" class="space-y-2">
                    ${provider.models ? provider.models.map((model, modelIndex) => `
                        <div class="flex items-center space-x-2 space-x-reverse">
                            <input type="text" value="${escapeHtml(model.id || '')}"
                                onchange="updateCustomProviderModelId(${index}, ${modelIndex}, this.value)"
                                class="flex-1 px-2 py-1 border border-gray-300 dark:border-gray-600 rounded bg-white/80 dark:bg-gray-700/80 text-gray-900 dark:text-white text-sm"
                                placeholder="معرف النموذج">
                            <input type="text" value="${escapeHtml(model.name || '')}"
                                onchange="updateCustomProviderModelName(${index}, ${modelIndex}, this.value)"
                                class="flex-1 px-2 py-1 border border-gray-300 dark:border-gray-600 rounded bg-white/80 dark:bg-gray-700/80 text-gray-900 dark:text-white text-sm"
                                placeholder="اسم النموذج">
                            <button onclick="removeCustomProviderModel(${index}, ${modelIndex})"
                                class="p-1 text-red-500 hover:text-red-700 dark:text-red-400 dark:hover:text-red-300 transition-colors">
                                <i class="fas fa-times text-xs"></i>
                            </button>
                        </div>
                    `).join('') : ''}
                </div>
            </div>
        `;
        container.appendChild(providerCard);
    });
}

function addCustomProvider() {
    const newId = `custom_${Date.now()}`;
    settings.customProviders.push({
        id: newId,
        name: 'مزود مخصص جديد',
        baseUrl: '',
        models: [],
        apiKeys: []
    });
    renderCustomProviders();
    updateCustomProviders();
    updateProviderSelect();
}

function removeCustomProvider(index) {
    settings.customProviders.splice(index, 1);
    renderCustomProviders();
    updateCustomProviders();
    updateProviderSelect();
}

function updateCustomProviderName(index, name) {
    if (settings.customProviders[index]) {
        settings.customProviders[index].name = name;
        updateCustomProviders();
        updateProviderSelect();
    }
}

function updateCustomProviderBaseUrl(index, baseUrl) {
    if (settings.customProviders[index]) {
        settings.customProviders[index].baseUrl = baseUrl;
    }
}

function addCustomProviderModel(providerIndex) {
    if (!settings.customProviders[providerIndex].models) {
        settings.customProviders[providerIndex].models = [];
    }
    settings.customProviders[providerIndex].models.push({
        id: '',
        name: ''
    });
    renderCustomProviders();
    updateCustomProviders();
}

function removeCustomProviderModel(providerIndex, modelIndex) {
    settings.customProviders[providerIndex].models.splice(modelIndex, 1);
    renderCustomProviders();
    updateCustomProviders();
}

function updateCustomProviderModelId(providerIndex, modelIndex, id) {
    if (settings.customProviders[providerIndex] && settings.customProviders[providerIndex].models[modelIndex]) {
        settings.customProviders[providerIndex].models[modelIndex].id = id;
        updateCustomProviders();
    }
}

function updateCustomProviderModelName(providerIndex, modelIndex, name) {
    if (settings.customProviders[providerIndex] && settings.customProviders[providerIndex].models[modelIndex]) {
        settings.customProviders[providerIndex].models[modelIndex].name = name;
        updateCustomProviders();
    }
}

function updateProviderSelect() {
    const providerSelect = document.getElementById('providerSelect');
    const currentValue = providerSelect.value;

    // إزالة المزودين المخصصين القدامى
    const options = Array.from(providerSelect.options);
    options.forEach(option => {
        if (option.value.startsWith('custom_')) {
            providerSelect.removeChild(option);
        }
    });

    // إضافة المزودين المخصصين الجدد
    settings.customProviders.forEach(provider => {
        const option = document.createElement('option');
        option.value = provider.id;
        option.textContent = provider.name;
        providerSelect.appendChild(option);
    });

    // استعادة القيمة المحددة إذا كانت لا تزال موجودة
    const stillExists = Array.from(providerSelect.options).some(option => option.value === currentValue);
    if (stillExists) {
        providerSelect.value = currentValue;
    }
}

// إدارة النماذج المخصصة
function openCustomModelsManager() {
    document.getElementById('customModelsModal').classList.remove('hidden');
    renderCustomModels();
}

function closeCustomModelsManager() {
    document.getElementById('customModelsModal').classList.add('hidden');
}

function renderCustomModels() {
    const container = document.getElementById('customModelsContainer');
    container.innerHTML = '';

    if (settings.customModels.length === 0) {
        container.innerHTML = `
            <div class="text-center text-gray-500 dark:text-gray-400 py-8">
                <i class="fas fa-brain text-4xl mb-4"></i>
                <p>لا توجد نماذج مخصصة بعد</p>
                <p class="text-sm">اضغط على "إضافة نموذج مخصص جديد" لإنشاء نموذج مخصص</p>
            </div>
        `;
        return;
    }

    settings.customModels.forEach((model, index) => {
        const modelCard = document.createElement('div');
        modelCard.className = 'custom-model-card glass-effect p-4 rounded-lg border border-gray-300 dark:border-gray-600';
        modelCard.innerHTML = `
            <div class="flex items-start justify-between mb-3">
                <div class="flex-1 grid grid-cols-2 gap-3">
                    <div>
                        <label class="form-label">اسم النموذج</label>
                        <input type="text" value="${escapeHtml(model.name || '')}"
                            onchange="updateCustomModelName(${index}, this.value)"
                            class="form-input"
                            placeholder="اسم النموذج">
                    </div>
                    <div>
                        <label class="form-label">معرف النموذج</label>
                        <input type="text" value="${escapeHtml(model.id || '')}"
                            onchange="updateCustomModelId(${index}, this.value)"
                            class="form-input"
                            placeholder="معرف النموذج">
                    </div>
                </div>
                <button onclick="removeCustomModel(${index})"
                    class="p-2 ml-2 text-red-500 hover:text-red-700 dark:text-red-400 dark:hover:text-red-300 transition-colors">
                    <i class="fas fa-trash"></i>
                </button>
            </div>
            <div class="grid grid-cols-2 gap-3 mb-3">
                <div>
                    <label class="form-label">المزود</label>
                    <select onchange="updateCustomModelProvider(${index}, this.value)" class="form-input">
                        <option value="gemini" ${model.provider === 'gemini' ? 'selected' : ''}>Google Gemini</option>
                        <option value="openrouter" ${model.provider === 'openrouter' ? 'selected' : ''}>OpenRouter</option>
                        ${settings.customProviders.map(p => `
                            <option value="${escapeHtml(p.id || '')}" ${model.provider === p.id ? 'selected' : ''}>${escapeHtml(p.name || '')}</option>
                        `).join('')}
                    </select>
                </div>
                <div>
                    <label class="form-label">درجة الحرارة الافتراضية</label>
                    <input type="number" min="0" max="1" step="0.1" value="${escapeHtml(String(model.defaultTemperature ?? 0.7))}"
                        onchange="updateCustomModelTemperature(${index}, this.value)"
                        class="form-input"
                        placeholder="0.7">
                </div>
            </div>
            <div>
                <label class="form-label">وصف النموذج</label>
                <textarea onchange="updateCustomModelDescription(${index}, this.value)"
                    class="form-input form-textarea"
                    placeholder="وصف مختصر للنموذج">${escapeHtml(model.description || '')}</textarea>
            </div>
        `;
        container.appendChild(modelCard);
    });
}

function addCustomModel() {
    settings.customModels.push({
        id: '',
        name: 'نموذج مخصص جديد',
        provider: 'gemini',
        defaultTemperature: 0.7,
        description: ''
    });
    renderCustomModels();
}

function removeCustomModel(index) {
    settings.customModels.splice(index, 1);
    renderCustomModels();
}

function updateCustomModelName(index, name) {
    if (settings.customModels[index]) {
        settings.customModels[index].name = name;
    }
}

function updateCustomModelId(index, id) {
    if (settings.customModels[index]) {
        settings.customModels[index].id = id;
    }
}

function updateCustomModelProvider(index, provider) {
    if (settings.customModels[index]) {
        settings.customModels[index].provider = provider;
    }
}

function updateCustomModelTemperature(index, temperature) {
    if (settings.customModels[index]) {
        settings.customModels[index].defaultTemperature = parseFloat(temperature);
    }
}

function updateCustomModelDescription(index, description) {
    if (settings.customModels[index]) {
        settings.customModels[index].description = description;
    }
}

// File handling functions - MODIFIED to stop displaying content
