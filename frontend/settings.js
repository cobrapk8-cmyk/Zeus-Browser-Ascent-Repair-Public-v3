function openSettings() {
    document.getElementById('settingsModal').classList.remove('hidden');
    onOpenSettingsModal();
    loadSettingsUI();
}

function closeSettings() {
    document.getElementById('settingsModal').classList.add('hidden');
}

function loadSettingsUI() {
    // Load provider
    document.getElementById('providerSelect').value = settings.provider;

    // Load temperature
document.getElementById('temperatureSlider').value = settings.temperature;
document.getElementById('temperatureValue').textContent = settings.temperature;

// Load theme (قيَم موحّدة theme-*)
const themeSel = document.getElementById('themeSelect');
if (themeSel) {
  const v = normalizeThemeValue(settings.theme || localStorage.getItem('zeus-theme') || 'theme-black');
  themeSel.value = v;
}

// Load custom prompt (قد لا يكون موجوداً في HTML)
const cpi = document.getElementById('customPromptInput');
if (cpi) cpi.value = settings.customPrompt || '';

    // Load API key retry strategy
    document.getElementById('apiKeyRetryStrategySelect').value = settings.apiKeyRetryStrategy;

    // ✨ تحميل إعدادات البحث الجديدة ✨
    const chkEnableBrowsing = document.getElementById('enableWebBrowsing');
    const selBrowsingMode = document.getElementById('browsingMode');
    const chkShowSources = document.getElementById('showSources');
    const dynThresholdSlider = document.getElementById('dynamicThresholdSlider');
    const dynThresholdValue = document.getElementById('dynamicThresholdValue');

    if (chkEnableBrowsing) chkEnableBrowsing.checked = settings.enableWebBrowsing || false;
    if (selBrowsingMode) selBrowsingMode.value = settings.browsingMode || 'gemini';
    if (chkShowSources) chkShowSources.checked = settings.showSources !== false; // افتراضي true
    if (dynThresholdSlider) {
        dynThresholdSlider.value = settings.dynamicThreshold || 0.6;
        if (dynThresholdValue) dynThresholdValue.textContent = (settings.dynamicThreshold || 0.6).toFixed(1);
    }

    // Load API keys
    renderGeminiApiKeys();
    renderOpenRouterApiKeys();

    // Load font size
    document.getElementById('fontSizeSlider').value = settings.fontSize;
    document.getElementById('fontSizeValue').textContent = `${settings.fontSize}px`;

    updateProviderUI();
    updateModelOptions();
}

// ✨✨✨ الدالة المفقودة التي تصلح زر الحفظ ✨✨✨
async function saveSettings() {
  settings.provider = document.getElementById('providerSelect').value;
  settings.model = document.getElementById('modelSelect').value;
  settings.temperature = parseFloat(document.getElementById('temperatureSlider').value);

  const cpi = document.getElementById('customPromptInput');
  settings.customPrompt = cpi ? cpi.value : (settings.customPrompt || '');

  settings.apiKeyRetryStrategy = document.getElementById('apiKeyRetryStrategySelect').value;
  settings.fontSize = parseInt(document.getElementById('fontSizeSlider').value, 10);

  // ✨ حفظ إعدادات البحث ✨
  const chkEnableBrowsing = document.getElementById('enableWebBrowsing');
  const selBrowsingMode = document.getElementById('browsingMode');
  const chkShowSources = document.getElementById('showSources');
  const dynThresholdSlider = document.getElementById('dynamicThresholdSlider');

  if (chkEnableBrowsing) settings.enableWebBrowsing = chkEnableBrowsing.checked;
  if (selBrowsingMode) settings.browsingMode = selBrowsingMode.value;
  if (chkShowSources) settings.showSources = chkShowSources.checked;
  if (dynThresholdSlider) settings.dynamicThreshold = parseFloat(dynThresholdSlider.value);

  // الثيم (قيَم موحَّدة theme-*)
  const THEME_KEY = 'zeus-theme';
  const VALID = ['theme-black','theme-blue','theme-light'];
  const themeSel = document.getElementById('themeSelect');
  let chosen = themeSel ? themeSel.value : 'theme-black';
  if (!VALID.includes(chosen)) chosen = 'theme-black';

  // خزّن في localStorage + في الإعدادات + طبِّق فوراً
  localStorage.setItem(THEME_KEY, chosen);
  settings.theme = chosen;
  setTheme(chosen);

  // خلفية زيوس (إن وُجدت)
  const bgSel = document.getElementById('bgStyleSelect');
  if (bgSel) {
    localStorage.setItem('bgStyle', bgSel.value);
    const bgCanvas = document.getElementById('bgCanvas');
    if (bgCanvas) {
      bgCanvas.classList.toggle('bg-storm', bgSel.value === 'storm');
      bgCanvas.classList.toggle('bg-calm',  bgSel.value !== 'storm');
    }
  }

  // حجم الخط (تخزين وتطبيق فوري)
  document.documentElement.style.setProperty('--chat-font-size', `${settings.fontSize}px`);
  localStorage.setItem('zeus-font-size', String(settings.fontSize));

  await saveSettingsToDB();
  closeSettings();
}

async function saveSettingsToDB() {
    if (!currentUser) return;
    const token = localStorage.getItem('authToken');
    if (!token) return;

    try {
        const response = await fetch(`${API_BASE_URL}/api/settings`, {
            method: 'PUT',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${token}`
            },
            body: JSON.stringify(settings)
        });

        if (!response.ok) {
            const errorData = await response.json();
            // استخدم رسالة الخطأ من الخادم إذا كانت موجودة
            throw new Error(errorData.message || `فشل الحفظ: ${response.statusText}`);
        }

        const savedSettings = await response.json();
        settings = redactSettingsSecrets(savedSettings);
        console.log('Settings saved successfully to DB.');
        showNotification('تم حفظ الإعدادات بنجاح', 'success'); // <-- انقل الإشعار إلى هنا

    } catch (error) {
        console.error('Error saving settings:', error);
        showNotification(`خطأ: ${error.message}`, 'error');
    }
}

// API Keys management
function renderGeminiApiKeys() {
    const container = document.getElementById('geminiApiKeysContainer');
    container.innerHTML = '';

    if (settings.geminiApiKeys.length === 0) {
        container.innerHTML = `
            <div class="text-center text-gray-500 dark:text-gray-400 py-4">
                <i class="fas fa-key text-2xl mb-2"></i>
                <p>لا توجد مفاتيح API بعد</p>
                <p class="text-xs">اضغط على "أضف مفتاحاً جديداً" لإضافة مفتاح API</p>
            </div>
        `;
        return;
    }

    settings.geminiApiKeys.forEach((apiKey, index) => {
        const keyDiv = document.createElement('div');
        keyDiv.className = 'flex items-center space-x-3 space-x-reverse';
        keyDiv.innerHTML = `
            <div class="relative flex-1">
                <input type="password" value="${escapeHtml(apiKey.key || '')}"
                    onchange="updateGeminiApiKey(${index}, this.value)"
                    id="geminiApiKeyInput-${index}"
                    class="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-lg bg-white/80 dark:bg-gray-700/80 text-gray-900 dark:text-white text-base pl-10 backdrop-blur-sm"
                    placeholder="${apiKey.hasKey ? 'مفتاح محفوظ؛ أدخل قيمة جديدة لتغييره' : 'أدخل مفتاح Gemini API'}">
                <button type="button" onclick="toggleGeminiApiKeyVisibility(${index})"
                    class="absolute left-3 top-1/2 transform -translate-y-1/2 text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200">
                    <i id="geminiApiKeyToggleIcon-${index}" class="fas fa-eye"></i>
                </button>
            </div>
            <div class="flex items-center space-x-2 space-x-reverse">
                <span class="status-indicator ${apiKey.status === 'active' ? 'bg-green-500' : 'bg-red-500'} w-3 h-3 rounded-full"></span>
                <span class="text-xs text-gray-500 dark:text-gray-400">${apiKey.status === 'active' ? 'نشط' : 'معطل'}</span>
            </div>
            <button onclick="removeGeminiApiKey(${index})"
                class="p-2 text-red-500 hover:text-red-700 dark:text-red-400 dark:hover:text-red-300 transition-colors">
                <i class="fas fa-trash text-sm"></i>
            </button>
        `;
        container.appendChild(keyDiv);
    });
}

function addGeminiApiKeyField() {
    settings.geminiApiKeys.push({
        key: '',
        status: 'active'
    });
    renderGeminiApiKeys();
}

function removeGeminiApiKey(index) {
    settings.geminiApiKeys.splice(index, 1);
    renderGeminiApiKeys();
}

function updateGeminiApiKey(index, value) {
    if (settings.geminiApiKeys[index]) {
        settings.geminiApiKeys[index].key = value;
    }
}

function toggleGeminiApiKeyVisibility(index) {
    const input = document.getElementById(`geminiApiKeyInput-${index}`);
    const icon = document.getElementById(`geminiApiKeyToggleIcon-${index}`);

    if (input.type === 'password') {
        input.type = 'text';
        icon.className = 'fas fa-eye-slash';
    } else {
        input.type = 'password';
        icon.className = 'fas fa-eye';
    }
}

function renderOpenRouterApiKeys() {
    const container = document.getElementById('openrouterApiKeysContainer');
    container.innerHTML = '';

    if (settings.openrouterApiKeys.length === 0) {
        container.innerHTML = `
            <div class="text-center text-gray-500 dark:text-gray-400 py-4">
                <i class="fas fa-key text-2xl mb-2"></i>
                <p>لا توجد مفاتيح API بعد</p>
                <p class="text-xs">اضغط على "أضف مفتاحاً جديداً" لإضافة مفتاح API</p>
            </div>
        `;
        return;
    }

    settings.openrouterApiKeys.forEach((apiKey, index) => {
        const keyDiv = document.createElement('div');
        keyDiv.className = 'flex items-center space-x-3 space-x-reverse';
        keyDiv.innerHTML = `
            <div class="relative flex-1">
                <input type="password" value="${escapeHtml(apiKey.key || '')}"
                    onchange="updateOpenRouterApiKey(${index}, this.value)"
                    id="openrouterApiKeyInput-${index}"
                    class="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-lg bg-white/80 dark:bg-gray-700/80 text-gray-900 dark:text-white text-base pl-10 backdrop-blur-sm"
                    placeholder="${apiKey.hasKey ? 'مفتاح محفوظ؛ أدخل قيمة جديدة لتغييره' : 'أدخل مفتاح OpenRouter API'}">
                <button type="button" onclick="toggleOpenRouterApiKeyVisibility(${index})"
                    class="absolute left-3 top-1/2 transform -translate-y-1/2 text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200">
                    <i id="openrouterApiKeyToggleIcon-${index}" class="fas fa-eye"></i>
                </button>
            </div>
            <div class="flex items-center space-x-2 space-x-reverse">
                <span class="status-indicator ${apiKey.status === 'active' ? 'bg-green-500' : 'bg-red-500'} w-3 h-3 rounded-full"></span>
                <span class="text-xs text-gray-500 dark:text-gray-400">${apiKey.status === 'active' ? 'نشط' : 'معطل'}</span>
            </div>
            <button onclick="removeOpenRouterApiKey(${index})"
                class="p-2 text-red-500 hover:text-red-700 dark:text-red-400 dark:hover:text-red-300 transition-colors">
                <i class="fas fa-trash text-sm"></i>
            </button>
        `;
        container.appendChild(keyDiv);
    });
}

function addOpenRouterApiKeyField() {
    settings.openrouterApiKeys.push({
        key: '',
        status: 'active'
    });
    renderOpenRouterApiKeys();
}

function removeOpenRouterApiKey(index) {
    settings.openrouterApiKeys.splice(index, 1);
    renderOpenRouterApiKeys();
}

function updateOpenRouterApiKey(index, value) {
    if (settings.openrouterApiKeys[index]) {
        settings.openrouterApiKeys[index].key = value;
    }
}

function toggleOpenRouterApiKeyVisibility(index) {
    const input = document.getElementById(`openrouterApiKeyInput-${index}`);
    const icon = document.getElementById(`openrouterApiKeyToggleIcon-${index}`);

    if (input.type === 'password') {
        input.type = 'text';
        icon.className = 'fas fa-eye-slash';
    } else {
        input.type = 'password';
        icon.className = 'fas fa-eye';
    }
}

// UI functions
