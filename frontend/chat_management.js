async function startNewChat() {
    const chatId = Date.now().toString();
    currentChatId = chatId;
    const now = Date.now();
    chats[chatId] = {
        _id: chatId,
        title: 'محادثة جديدة',
        messages: [],
        createdAt: now,
        updatedAt: now,
        order: now,
        isTemporary: true         // ✨ تمييزها كمحادثة غير محفوظة بعد
    };

    document.getElementById('welcomeScreen').classList.remove('hidden');
    document.getElementById('messagesContainer').classList.add('hidden');
    document.getElementById('messagesArea').innerHTML = '';

    displayChatHistory();
}

// Drag and drop state
let draggedChatId = null;

function displayChatHistory() {
    const chatHistory = document.getElementById('chatHistory');
    chatHistory.innerHTML = '';

    const sortedChats = Object.values(chats).sort((a, b) => (b.order || 0) - (a.order || 0));

    if (sortedChats.length === 0) {
        chatHistory.innerHTML = `
            <div class="text-center text-gray-500 dark:text-gray-400 py-8">
                <i class="fas fa-comments text-2xl mb-2"></i>
                <p>لا توجد محادثات بعد</p>
                <p class="text-xs">ابدأ محادثة جديدة لرؤيتها هنا</p>
            </div>
        `;
        return;
    }

    sortedChats.forEach(chat => {
        if (!chat._id) return; 

        const chatItem = document.createElement('div');
        chatItem.className = `p-3 rounded-lg cursor-pointer transition-colors ${chat._id === currentChatId ? 'bg-zeus-accent text-white' : 'hover:bg-white/10 text-gray-300'}`;

        chatItem.setAttribute('draggable', true);
        chatItem.setAttribute('data-chat-id', chat._id);

        const lastMessage = chat.messages[chat.messages.length - 1];
        const preview = lastMessage ? (lastMessage.content.substring(0, 50) + (lastMessage.content.length > 50 ? '...' : '')) : 'محادثة فارغة';

        // نسخة نظيفة تمامًا
        chatItem.innerHTML = `
            <div class="flex items-center justify-between">
                <div class="flex-1 min-w-0" id="chat-title-container-${chat._id}">
                    <h4 class="font-medium truncate">${escapeHtml(chat.title)}</h4>
                    <p class="text-sm opacity-70 truncate">${escapeHtml(preview)}</p>
                </div>
                <div class="flex items-center ml-2 space-x-1 space-x-reverse">
                    <button onclick="toggleEditChatTitle('${chat._id}', event)" class="p-1 rounded hover:bg-white/20 text-gray-300 hover:text-white transition-colors" title="تعديل الاسم">
                        <i class="fas fa-pen text-xs"></i>
                    </button>
                    <button onclick="deleteChat('${chat._id}', event)" class="p-1 rounded hover:bg-red-500/20 text-red-400 hover:text-red-300 transition-colors" title="حذف المحادثة">
                        <i class="fas fa-trash text-xs"></i>
                    </button>
                </div>
            </div>
        `;

        chatItem.onclick = (e) => {
            if (e.target.closest('button')) return;
            switchToChat(chat._id);
        };

        chatItem.addEventListener('dragstart', handleDragStart);
        chatItem.addEventListener('dragenter', handleDragEnter);
        chatItem.addEventListener('dragover', handleDragOver);
        chatItem.addEventListener('dragleave', handleDragLeave);
        chatItem.addEventListener('drop', handleDrop);
        chatItem.addEventListener('dragend', handleDragEnd);

        chatHistory.appendChild(chatItem);
    });
}

// --- Drag and Drop Handlers ---

function handleDragStart(e) {
    draggedChatId = this.getAttribute('data-chat-id');
    e.dataTransfer.effectAllowed = 'move';
    e.dataTransfer.setData('text/plain', draggedChatId);

    setTimeout(() => {
        this.classList.add('dragging');
    }, 0);
}

function handleDragEnter(e) {
    e.preventDefault();
    const dropTarget = this;
    if (dropTarget.getAttribute('data-chat-id') !== draggedChatId) {
        // Remove existing indicators before adding a new one
        document.querySelectorAll('.drop-indicator').forEach(ind => ind.remove());

        const indicator = document.createElement('div');
        indicator.className = 'drop-indicator';

        const rect = dropTarget.getBoundingClientRect();
        const isAfter = e.clientY > rect.top + rect.height / 2;

        if (isAfter) {
            dropTarget.insertAdjacentElement('afterend', indicator);
        } else {
            dropTarget.insertAdjacentElement('beforebegin', indicator);
        }
    }
}

function handleDragOver(e) {
    e.preventDefault(); // Necessary to allow dropping
}

function handleDragLeave(e) {
    // This is to prevent the indicator from disappearing when moving between child elements
    const chatHistory = document.getElementById('chatHistory');
    if (!chatHistory.contains(e.relatedTarget)) {
        document.querySelectorAll('.drop-indicator').forEach(ind => ind.remove());
    }
}

function handleDrop(e) {
    e.preventDefault();
    e.stopPropagation();

    const sourceChatId = e.dataTransfer.getData('text/plain');
    const dropIndicator = document.querySelector('.drop-indicator');

    if (!dropIndicator || !chats[sourceChatId]) {
        if(dropIndicator) dropIndicator.remove();
        return;
    }

    const nextSibling = dropIndicator.nextElementSibling;
    const prevSibling = dropIndicator.previousElementSibling;

    const orderBefore = nextSibling && nextSibling.hasAttribute('data-chat-id') ? chats[nextSibling.getAttribute('data-chat-id')].order : null;
    const orderAfter = prevSibling && prevSibling.hasAttribute('data-chat-id') ? chats[prevSibling.getAttribute('data-chat-id')].order : null;

    let newOrder;
    if (orderBefore === null && orderAfter !== null) {
        // Dropped at the end of the list
        newOrder = orderAfter - 1000;
    } else if (orderBefore !== null && orderAfter === null) {
        // Dropped at the beginning of the list
        newOrder = orderBefore + 1000;
    } else if (orderBefore !== null && orderAfter !== null) {
        // Dropped between two items
        newOrder = (orderBefore + orderAfter) / 2;
    } else {
        // List has only one item or is empty, no change needed
        dropIndicator.remove();
        return;
    }

    chats[sourceChatId].order = newOrder;

    // The dragend handler will remove the indicator and dragging class
    // Re-render to show the final correct order
    displayChatHistory();
}

function handleDragEnd(e) {
    document.querySelectorAll('.dragging').forEach(el => el.classList.remove('dragging'));
    document.querySelectorAll('.drop-indicator').forEach(ind => ind.remove());
}

function switchToChat(chatId) {
    if (!chats[chatId]) return;

    // 👈 لا نُلغي البث هنا، نسمح له بالعمل في الخلفية
    currentChatId = chatId;
    document.getElementById('welcomeScreen').classList.add('hidden');
    document.getElementById('messagesContainer').classList.remove('hidden');

    displayMessages();
    displayChatHistory();
    closeSidebar();
}

// مساعد بسيط للتحقق من ObjectId
function isValidObjectId(id) {
    return typeof id === 'string' && /^[a-f\d]{24}$/i.test(id);
}

// تنظيف المحادثة قبل الإرسال للخادم
function sanitizeChatForSave(chat) {
  const safeMessages = (chat.messages || []).map(m => ({
    role: m.role,
    content: typeof m.content === 'string' ? m.content : '',
    timestamp: m.timestamp || Date.now(),
    // نحفظ المراجع فقط (بدون content/base64)
    attachments: (m.attachments || []).map(a => ({
      name: a.name,
      type: a.type,
      size: a.size,
      fileId: a.fileId || null,
      fileUrl: a.fileUrl || null
    }))
  }));

  return {
    _id: chat._id,
    title: chat.title || 'محادثة',
    messages: safeMessages,
    createdAt: chat.createdAt || Date.now(),
    updatedAt: Date.now(),
    order: chat.order || Date.now()
  };
}

async function saveCurrentChat(chatIdParam = currentChatId) {
    if (!chatIdParam || !chats[chatIdParam]) return;

    const token = localStorage.getItem('authToken');
    if (!token) return;

    try {
        // ✨ تنظيف قبل الحفظ
        const payload = sanitizeChatForSave(chats[chatIdParam]);

        const response = await fetch(`${API_BASE_URL}/api/chats`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${token}`
            },
            body: JSON.stringify(payload)
        });

        if (!response.ok) {
            // ✨ التقط رسالة الخادم الحقيقية (JSON أو نص)
            let serverMsg = 'Failed to save chat to the database.';
            try {
                const txt = await response.text();
                serverMsg = txt || serverMsg;
            } catch (_) {}
            throw new Error(serverMsg);
        }

        const savedChat = await response.json();

        // خزّن النسخة العائدة من الخادم تحت الـ _id الحقيقي
        chats[savedChat._id] = { ...savedChat, isTemporary: false };

        // إن كان الـ chatIdParam مؤقّتًا (ليس ObjectId) احذفه
        const wasTemp = !isValidObjectId(chatIdParam);
        if (wasTemp && chatIdParam !== savedChat._id) {
            delete chats[chatIdParam];
        }

        // تحديث المعرّفات إن كنا على نفس المحادثة/نبثّ فيها
        if (currentChatId === chatIdParam) currentChatId = savedChat._id;
        if (streamingState.chatId === chatIdParam) streamingState.chatId = savedChat._id;

        console.log('Chat saved successfully to DB:', savedChat._id);
        displayChatHistory();

    } catch (error) {
        console.error('Error saving chat:', error);
        // ✨ أظهر رسالة الخادم بدل النص العام
        showNotification(`حدث خطأ أثناء حفظ المحادثة: ${error.message}`, 'error');
    }
}

async function deleteChat(chatId, event) {
    if (event) event.stopPropagation();

    if (!chats[chatId]) return;

    if (confirm('هل أنت متأكد من حذف هذه المحادثة؟')) {
        const token = localStorage.getItem('authToken');

        // 1) إذا كانت المحادثة مؤقتة محليًا (أو المعرّف ليس ObjectId) نحذفها محليًا فقط
        const temp = chats[chatId].isTemporary === true || !isValidObjectId(chatId);
        if (temp || !token) {
            delete chats[chatId];
            if (currentChatId === chatId) {
                currentChatId = null;
                document.getElementById('welcomeScreen').classList.remove('hidden');
                document.getElementById('messagesContainer').classList.add('hidden');
            }
            displayChatHistory();
            showNotification('تم حذف المحادثة محليًا.', 'success');
            return;
        }

        // 2) محادثة محفوظة فعلًا → احذف من الخادم أولًا
        try {
            const response = await fetch(`${API_BASE_URL}/api/chats/${chatId}`, {
                method: 'DELETE',
                headers: { 'Authorization': `Bearer ${token}` }
            });

            if (!response.ok) throw new Error('فشل حذف المحادثة من الخادم.');

            delete chats[chatId];

            if (currentChatId === chatId) {
                currentChatId = null;
                document.getElementById('welcomeScreen').classList.remove('hidden');
                document.getElementById('messagesContainer').classList.add('hidden');
            }

            displayChatHistory();
            showNotification('تم حذف المحادثة بنجاح.', 'success');

        } catch (error) {
            console.error('Error deleting chat:', error);
            showNotification(error.message, 'error');
        }
    }
}

function toggleEditChatTitle(chatId, event) {
    event.stopPropagation();
    const titleContainer = document.getElementById(`chat-title-container-${chatId}`);
    const chatItem = titleContainer.closest('.p-3');
    if (!titleContainer || !chatItem) return;

    const currentTitle = chats[chatId].title;

    // Preserve the preview text
    const previewText = chatItem.querySelector('p').textContent;

    const input = document.createElement('input');
    input.type = 'text';
    input.value = currentTitle;
    input.className = 'w-full bg-transparent text-white border-b border-white/50 focus:outline-none text-base font-medium';
    input.style.direction = 'rtl';
    input.onclick = (e) => e.stopPropagation();

    const saveAndUpdate = () => {
        const newTitle = input.value.trim();
        if (newTitle && newTitle !== currentTitle) {
            updateChatTitle(chatId, newTitle);
        } else {
            displayChatHistory(); // Restore if title is empty or unchanged
        }
    };

    input.onblur = saveAndUpdate;
    input.onkeydown = (e) => {
        if (e.key === 'Enter') {
            e.preventDefault();
            saveAndUpdate();
        } else if (e.key === 'Escape') {
            displayChatHistory();
        }
    };

    titleContainer.innerHTML = '';
    titleContainer.appendChild(input);

    // Re-add the preview paragraph
    const p = document.createElement('p');
    p.className = 'text-sm opacity-70 truncate';
    p.textContent = previewText;
    titleContainer.appendChild(p);

    input.focus();
    input.select();
}

function updateChatTitle(chatId, newTitle) {
    if (newTitle && newTitle.trim() !== '') {
        const now = Date.now();
        chats[chatId].title = newTitle.trim();
        chats[chatId].updatedAt = now;
        chats[chatId].order = now; // Bring to top on edit
    }
    displayChatHistory();
}

function displayMessages() {
    const messagesArea = document.getElementById('messagesArea');
    messagesArea.innerHTML = '';

    if (!currentChatId || !chats[currentChatId]) return;

    chats[currentChatId].messages.forEach(message => {
        displayMessage(message);
    });

    scrollToBottom();

    // 👇 هنا نضع الكود الجديد من الخطوة 6
    if (streamingState.isStreaming && streamingState.chatId === currentChatId) {
        // اربط عنصر العرض مرة أخرى إن لم يكن موجودًا
        if (!document.getElementById(`message-${streamingState.currentMessageId}`)) {
            const messageId = streamingState.currentMessageId;
            const messagesArea = document.getElementById('messagesArea');

            const messageDiv = document.createElement('div');
            messageDiv.className = `chat-bubble message-assistant streaming-message`;
            messageDiv.id = `message-${messageId}`;
            messageDiv.innerHTML = `
              <div class="message-content" id="content-${messageId}">
                  <span class="streaming-cursor"></span>
              </div>
              <div class="streaming-indicator">
                  <i class="fas fa-robot text-xs"></i>
                  <span>يكتب زيوس</span>
                  <div class="streaming-dots">
                      <div class="streaming-dot"></div>
                      <div class="streaming-dot"></div>
                      <div class="streaming-dot"></div>
                  </div>
              </div>
            `;
            messagesArea.appendChild(messageDiv);
            streamingState.streamingElement = document.getElementById(`content-${messageId}`);

            // أعرض ما جمعناه حتى الآن
            const rendered = renderSafeMarkdown(streamingState.currentText || '');
            streamingState.streamingElement.innerHTML = rendered;
            const cursor = document.createElement('span');
            cursor.className = 'streaming-cursor';
            streamingState.streamingElement.appendChild(cursor);

            // تمييز الأكواد
            streamingState.streamingElement.querySelectorAll('pre code').forEach(block => {
                hljs.highlightElement(block);
                addCodeHeader(block.parentElement);
            });

            smoothScrollToBottom();
        }
    }
}

function displayMessage(message) {
    const messagesArea = document.getElementById('messagesArea');
    const messageDiv = document.createElement('div');
    messageDiv.className = `chat-bubble message-${message.role}`;

    if (message.role === 'user') {
        let content = `<div class="message-content">${escapeHtml(message.content)}</div>`;

        // Add file cards if there are attachments
        if (message.attachments && message.attachments.length > 0) {
            const fileCards = message.attachments.map(file => createFileCard(file)).join('');
            content += fileCards;
        }

        messageDiv.innerHTML = content;
    } else {
        const renderedContent = renderSafeMarkdown(message.content);
        messageDiv.innerHTML = `<div class="message-content">${renderedContent}</div>`;

        // Highlight code blocks
        messageDiv.querySelectorAll('pre code').forEach(block => {
            hljs.highlightElement(block);
            addCodeHeader(block.parentElement);
        });

        addMessageActions(messageDiv, message.content);
    }

    messagesArea.appendChild(messageDiv);
}

function addCodeHeader(preElement) {
    // Remove any existing header
    const existingHeader = preElement.querySelector('.code-header-new');
    if (existingHeader) {
        existingHeader.remove();
    }

    const codeElement = preElement.querySelector('code');
    if (!codeElement) return;

    // Detect language
    let language = 'نص';
    const className = codeElement.className;
    const languageMatch = className.match(/language-(\w+)/);
    if (languageMatch) {
        const lang = languageMatch[1].toLowerCase();
        const languageNames = {
            'javascript': 'JavaScript',
            'js': 'JavaScript',
            'python': 'Python',
            'html': 'HTML',
            'css': 'CSS',
            'json': 'JSON',
            'xml': 'XML',
            'sql': 'SQL',
            'bash': 'Bash',
            'shell': 'Shell'
        };
        language = languageNames[lang] || lang;
    }

    // Create header
    const header = document.createElement('div');
    header.className = 'code-header-new';
    header.innerHTML = `
        <span class="language-label">${language}</span>
        <button class="copy-button-new" onclick="copyCode(this)">
            <i class="fas fa-copy"></i>
            <span>نسخ</span>
        </button>
    `;

    // Insert header at the beginning of pre element
    preElement.insertBefore(header, preElement.firstChild);
}

function copyCode(button) {
    const pre = button.closest('pre');
    const code = pre.querySelector('code');
    const text = code.textContent;

    navigator.clipboard.writeText(text).then(() => {
        const span = button.querySelector('span');
        const icon = button.querySelector('i');
        const originalText = span.textContent;
        const originalIcon = icon.className;

        span.textContent = 'تم النسخ!';
        icon.className = 'fas fa-check';

        setTimeout(() => {
            span.textContent = originalText;
            icon.className = originalIcon;
        }, 2000);
    }).catch(err => {
        console.error('Failed to copy:', err);
        showNotification('فشل في نسخ الكود', 'error');
    });
}

function addMessageActions(messageElement, content) {
    const actions = document.createElement('div');
    actions.className = 'message-actions';
    
    // فحص إذا كان الرد يحتوي على مصادر
    const hasSources = content.includes('**🔍 المصادر:**') || content.includes('**المصادر:**');
    
    let actionsHTML = `
        <button onclick="copyMessage(this)" class="p-1 rounded text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200 hover:bg-white/10" data-tooltip="نسخ">
            <i class="fas fa-copy text-xs"></i>
        </button>
        <button onclick="regenerateMessage(this)" class="p-1 rounded text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200 hover:bg-white/10" data-tooltip="إعادة توليد">
            <i class="fas fa-redo text-xs"></i>
        </button>
    `;
    
    // إضافة زر المصادر إذا كانت موجودة
    if (hasSources) {
        actionsHTML += `
            <button onclick="showSources(this)" class="p-1 rounded text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200 hover:bg-white/10" data-tooltip="المصادر">
                <i class="fas fa-external-link-alt text-xs"></i>
            </button>
        `;
    }
    
    actions.innerHTML = actionsHTML;
    messageElement.appendChild(actions);
    messageElement.setAttribute('data-content', content);
}

// إضافة دالة جديدة لعرض المصادر بجانب دالة `regenerateMessage`
function showSources(button) {
    const messageElement = button.closest('.chat-bubble');
    const content = messageElement.getAttribute('data-content');
    
    // استخراج المصادر من المحتوى
    const sourcesMatch = content.match(/\*\*🔍 المصادر:\*\*\n(.*?)$/s) || content.match(/\*\*المصادر:\*\*\n(.*?)$/s);
    if (sourcesMatch) {
        const sourcesText = sourcesMatch[1].trim();
        
        // إنشاء نافذة منبثقة للمصادر
        const modal = document.createElement('div');
        modal.className = 'fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50';
        modal.innerHTML = `
            <div class="bg-white dark:bg-gray-800 rounded-lg p-6 max-w-2xl max-h-80 overflow-y-auto">
                <div class="flex justify-between items-center mb-4">
                    <h3 class="text-lg font-semibold text-gray-900 dark:text-white">مصادر البحث</h3>
                    <button onclick="this.closest('.fixed').remove()" class="text-gray-500 hover:text-gray-700">
                        <i class="fas fa-times"></i>
                    </button>
                </div>
                <div class="text-gray-700 dark:text-gray-300 space-y-2">
                    ${renderSafeMarkdown(sourcesText)}
                </div>
            </div>
        `;
        
        document.body.appendChild(modal);
        
        // إغلاق النافذة عند النقر خارجها
        modal.addEventListener('click', (e) => {
            if (e.target === modal) {
                modal.remove();
            }
        });
    } else {
        showNotification('لا توجد مصادر متاحة لهذه الرسالة', 'info');
    }
}

function copyMessage(button) {
    const messageElement = button.closest('.chat-bubble');
    const content = messageElement.getAttribute('data-content');

    navigator.clipboard.writeText(content).then(() => {
        showNotification('تم نسخ الرسالة', 'success');
    }).catch(err => {
        console.error('Failed to copy message:', err);
        showNotification('فشل في نسخ الرسالة', 'error');
    });
}

function regenerateMessage(button) {
    // This would require re-sending the last user message
    showNotification('ميزة إعادة التوليد ستكون متاحة قريباً', 'info');
}

// Settings and data management
