function openSidebar() {
    document.getElementById('sidebar').classList.remove('translate-x-full');
}

function closeSidebar() {
    document.getElementById('sidebar').classList.add('translate-x-full');
}

function setTheme(theme) {
  const VALID = ['theme-black','theme-blue','theme-light'];
  if (!VALID.includes(theme)) theme = 'theme-black';

  document.body.classList.remove('theme-black','theme-blue','theme-light');
  document.body.classList.add(theme);

  // مزامنة القائمة إن كانت مفتوحة
  const sel = document.getElementById('themeSelect');
  if (sel && sel.value !== theme) sel.value = theme;
}

function normalizeThemeValue(v) {
  if (!v) return 'theme-black';
  // ترقية قيَم قديمة إلى القيَم الجديدة
  if (v === 'blue')  return 'theme-blue';
  if (v === 'black') return 'theme-black';
  if (v === 'light') return 'theme-light';
  // إن كانت بالفعل بصيغة theme-*
  return v;
}

function initializeTheme() {
  const KEY = 'zeus-theme';
  const VALID = ['theme-black','theme-blue','theme-light'];

  // 1) خذ من localStorage إن وُجد، وإلا من settings، وإلا الافتراضي الأسود
  let saved = localStorage.getItem(KEY) || (settings && settings.theme) || 'theme-black';

  // 2) ترقية قيم قديمة مثل "blue/black/light" إلى القيَم الجديدة
  saved = normalizeThemeValue(saved);
  if (!VALID.includes(saved)) saved = 'theme-black';

  // 3) طبّق وخزّن كي يبقى بعد التحديث
  localStorage.setItem(KEY, saved);
  setTheme(saved);

  // 4) مزامنة قائمة الثيم إن كانت مفتوحة
  const sel = document.getElementById('themeSelect');
  if (sel) sel.value = saved;
}

function toggleDarkMode() {
    const body = document.body;
    const themeIcon = document.getElementById('themeIcon'); // قد يكون غير موجود الآن

    body.classList.toggle('dark');

    const isDark = body.classList.contains('dark');
    localStorage.setItem('theme', isDark ? 'dark' : 'light');

    // تحمّل عدم وجود أيقونة في الرأس (لأننا نقلنا التحكم داخل منيو الحساب)
    if (themeIcon) {
        themeIcon.className = isDark ? 'fas fa-sun text-lg' : 'fas fa-moon text-lg';
    }
}

function initializeDarkMode() {
    const savedTheme = localStorage.getItem('theme');
    const themeIcon = document.getElementById('themeIcon'); // قد لا يوجد

    if (savedTheme === 'dark') {
        document.body.classList.add('dark');
        if (themeIcon) themeIcon.className = 'fas fa-sun text-lg';
    } else if (savedTheme === 'light') {
        document.body.classList.remove('dark');
        if (themeIcon) themeIcon.className = 'fas fa-moon text-lg';
    } else {
        // الوضع الافتراضي: دع المتصفح يقرر، ولا تلمس الأيقونة إن لم تكن موجودة
    }
}

function showNotification(message, type = 'info') {
    const container = document.getElementById('notificationContainer');
    const safeType = ['success', 'error', 'info'].includes(type) ? type : 'info';

    const notification = document.createElement('div');
    notification.className = `notification ${safeType} animate-fade-in pointer-events-auto`;
    notification.innerHTML = `
        <div class="flex items-center">
            <i class="fas ${safeType === 'success' ? 'fa-check-circle' : safeType === 'error' ? 'fa-exclamation-circle' : 'fa-info-circle'} ml-2"></i>
            <span></span>
        </div>
    `;
    notification.querySelector('span').textContent = String(message ?? '');

    container.appendChild(notification);

    setTimeout(() => {
        notification.remove();
    }, 5000);
}

// Legacy functions for backward compatibility (these may not be used with new file card system)
async function sendToCustomProvider(messages, attachments, providerId) {
    const customProvider = settings.customProviders.find(p => p.id === providerId);
    if (!customProvider) {
        throw new Error('المزود المخصص غير موجود');
    }

    const apiKeys = (customProvider.apiKeys || []).filter(key => key.status === 'active').map(key => key.key);
    if (apiKeys.length === 0) {
        throw new Error(`لا توجد مفاتيح API نشطة للمزود ${customProvider.name}`);
    }

    // This is a basic implementation - extend based on your custom provider's API
    const apiKey = apiKeys[0];
    const baseUrl = customProvider.baseUrl || 'https://api.openai.com/v1';

    // Prepare messages
    const formattedMessages = [];

    if (settings.customPrompt.trim()) {
        formattedMessages.push({
            role: 'system',
            content: settings.customPrompt
        });
    }

    messages.forEach(msg => {
        if (msg.role === 'user') {
            let content = msg.content;

            if (attachments && attachments.length > 0) {
                const fileContents = attachments
                    .filter(file => file.content)
                    .map(file => `\n\n--- محتوى الملف: ${file.name} ---\n${file.content}\n--- نهاية الملف ---`)
                    .join('');
                content += fileContents;
            }

            formattedMessages.push({
                role: 'user',
                content: content
            });
        } else if (msg.role === 'assistant') {
            formattedMessages.push({
                role: 'assistant',
                content: msg.content
            });
        }
    });

    const requestBody = {
        model: settings.model,
        messages: formattedMessages,
        temperature: settings.temperature,
        max_tokens: 4096
    };

    const response = await fetch(`${baseUrl}/chat/completions`, {
        method: 'POST',
        headers: {
            'Authorization': `Bearer ${apiKey}`,
            'Content-Type': 'application/json'
        },
        body: JSON.stringify(requestBody)
    });

    if (!response.ok) {
        throw new Error(`Custom provider API error: ${response.status}`);
    }

    const data = await response.json();
    return data.choices[0].message.content;
}


async function sendToGeminiStreaming(messages, attachments, apiKey, model) {
    // 1. إعداد هيكل المحادثة
    const conversation = [];

    // إضافة البرومبت المخصص إذا كان موجودًا
    if (settings.customPrompt.trim()) {
        conversation.push({ role: 'user', parts: [{ text: settings.customPrompt }] });
        conversation.push({ role: 'model', parts: [{ text: 'مفهوم، سأتبع هذه التعليمات.' }] });
    }

    // 2. إضافة الرسائل السابقة (كل الرسائل ما عدا الأخيرة)
    // هذا يحافظ على سياق المحادثة
    const previousMessages = messages.slice(0, -1);
    previousMessages.forEach(msg => {
        // نتجاهل المرفقات في الرسائل القديمة للتبسيط وإرسالها كنص فقط
        if (msg.role === 'user') {
            conversation.push({ role: 'user', parts: [{ text: msg.content }] });
        } else if (msg.role === 'assistant') {
            conversation.push({ role: 'model', parts: [{ text: msg.content }] });
        }
    });

    // 3. ✨ معالجة الرسالة الأخيرة مع مرفقاتها (هذا هو الجزء الرئيسي)
    const lastMessage = messages[messages.length - 1];
    if (lastMessage && lastMessage.role === 'user') {
        const userParts = [];

        // أضف نص الرسالة أولاً
        if (lastMessage.content) {
            userParts.push({ text: lastMessage.content });
        }

        // أضف المرفقات (نصوص وصور) كأجزاء منفصلة
        if (attachments && attachments.length > 0) {
            attachments.forEach(file => {
                if (file.dataType === 'image' && file.content) {
                    // هذا هو الجزء الخاص بالصور
                    userParts.push({
                        inline_data: {
                            mime_type: file.mimeType,
                            data: file.content // بيانات Base64
                        }
                    });
                } else if (file.dataType === 'text' && file.content) {
                    // هذا الجزء للملفات النصية (نضيفها كنص إضافي)
                    const fileText = `\n\n--- محتوى الملف: ${file.name} ---\n${file.content}\n--- نهاية الملف ---`;
                    userParts.push({ text: fileText });
                }
            });
        }

        // Gemini يتطلب وجود جزء نصي واحد على الأقل في الطلب
        // إذا كانت الرسالة تحتوي على صور فقط بدون نص، نضيف نصًا افتراضيًا
        if (userParts.length > 0 && userParts.every(p => !p.text)) {
            userParts.unshift({ text: "انظر إلى الصور المرفقة:" });
        }

        // أضف الرسالة الأخيرة المجمعة إلى المحادثة
        if (userParts.length > 0) {
            conversation.push({ role: 'user', parts: userParts });
        }
    }

    // 4. إعداد الطلب النهائي للـ API
    const requestBody = {
        contents: conversation,
        generationConfig: {
            temperature: settings.temperature,
            maxOutputTokens: 4096,
        }
    };

    // 5. إرسال الطلب وقراءة الاستجابة (هذا الجزء يبقى كما هو)
    const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:streamGenerateContent?key=${apiKey}&alt=sse`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(requestBody )
    });

    if (!response.ok) {
        const errorText = await response.text();
        console.error('Gemini API Error Response:', errorText); // طباعة الخطأ للمساعدة في التصحيح
        throw new Error(`Gemini API error: ${response.status} - ${errorText}`);
    }

    const reader = response.body.getReader();
    const decoder = new TextDecoder('utf-8');

    try {
        while (true) {
            const { done, value } = await reader.read();
            if (done) break;

            const chunk = decoder.decode(value);
            const lines = chunk.split('\n');

            for (const line of lines) {
                if (line.trim().startsWith('data: ')) {
                    try {
                        const jsonString = line.replace('data: ', '');
                        const json = JSON.parse(jsonString);
                        const text = json.candidates?.[0]?.content?.parts?.[0]?.text || '';
                        if (text) {
                            appendToStreamingMessage(text);
                        }
                    } catch (e) {
                        console.debug('Skipping invalid JSON chunk:', line);
                    }
                }
            }
        }
    } finally {
        reader.releaseLock();
    }

    appendToStreamingMessage('', true);
}

// ===============================================
// نظام تسجيل الدخول والخروج
// ===============================================

