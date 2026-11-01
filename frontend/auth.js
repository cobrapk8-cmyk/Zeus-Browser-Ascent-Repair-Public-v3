async function checkUserStatus() {
    const token = localStorage.getItem('authToken');
    if (!token) {
        console.log("No auth token found. User is logged out.");
        currentUser = null;
        settings = { ...defaultSettings };
        updateUserDisplay();
        displayChatHistory();
        return;
    }

    try {
        // ✨ الخطوة 1: التحقق من هوية المستخدم
        const userResponse = await fetch(`${API_BASE_URL}/api/user`, {
            headers: { 'Authorization': `Bearer ${token}` }
        });
        if (!userResponse.ok) throw new Error('Invalid or expired token');
        const userData = await userResponse.json();

        // ✨ الخطوة 2: تحديث الواجهة فورًا بالمعلومات الأساسية للمستخدم
        currentUser = userData.user;
updateUserDisplay();
renderAccountInfo(); // 👈 تحديث تبويب "الحساب" // <--- هذا هو السحر! سيُظهر الصورة والاسم فورًا!

        // ✨ الخطوة 3: الآن، قم بجلب باقي البيانات (المحادثات والإعدادات)
        const dataResponse = await fetch(`${API_BASE_URL}/api/data`, {
            headers: { 'Authorization': `Bearer ${token}` }
        });
        if (!dataResponse.ok) {
            // حتى لو فشل هذا الطلب، سيبقى المستخدم مسجلاً دخوله
            showNotification('تم تسجيل الدخول، لكن فشل جلب البيانات.', 'error');
            throw new Error('Failed to fetch user data');
        }
        const data = await dataResponse.json();

        // ✨ الخطوة 4: دمج البيانات وتحديث باقي الواجهة
        chats = data.chats.reduce((acc, chat) => { acc[chat._id] = chat; return acc; }, {});
        settings = redactSettingsSecrets({ ...defaultSettings, ...data.settings });
// توحيد قيمة الثيم القادمة من الخادم (قديمة أو جديدة)
settings.theme = normalizeThemeValue(settings.theme);
// خزِّن الثيم الموحّد محلياً لتقليل الوميض بعد التحديث
localStorage.setItem('zeus-theme', settings.theme);

        // تحديث واجهة الإعدادات والمحادثات بالترتيب الصحيح
        updateCustomProviders();
        updateProviderSelect();
        displayChatHistory();
        loadSettingsUI();

        if (Object.keys(chats).length > 0) {
            currentChatId = Object.values(chats).sort((a, b) => (b.order || 0) - (a.order || 0))[0]._id;
            switchToChat(currentChatId);
        }

    } catch (error) {
        console.error("Check user status process failed:", error.message);
        // إذا فشلت أي خطوة بعد تعيين المستخدم، لا تسجل خروجه بالكامل
        // هذا يضمن بقاء الصورة والاسم ظاهرين حتى لو فشل جلب البيانات
        if (!currentUser) {
             localStorage.removeItem('authToken');
             chats = {};
             settings = { ...defaultSettings };
             updateUserDisplay();
             displayChatHistory();
        }
    }
}

function updateUserDisplay() {
    renderUserMenu(currentUser);
}

/**
 * تبدأ عملية تسجيل الدخول.
 */
function loginWithGoogle() {
    showNotification('جارٍ توجيهك لتسجيل الدخول...', 'info');
    window.location.href = 'https://chatzeus-production.up.railway.app/auth/google'; // <--- هذا هو السطر الصحيح
}

/**
 * تبدأ عملية تسجيل الخروج.
 */
function logout() {
    // حذف التوكن من التخزين المحلي
    localStorage.removeItem('authToken');

    // إعادة تعيين حالة المستخدم في الواجهة
    currentUser = null;
    
    // ✨ إعادة تعيين البيانات المحلية بالكامل
    chats = {};
    currentChatId = null;
    // يمكنك إعادة تعيين الإعدادات إلى الافتراضية هنا إذا أردت
    
    // تحديث الواجهة لعرض زر تسجيل الدخول
    updateUserDisplay();
    
    // عرض شاشة الترحيب وإخفاء المحادثات
    document.getElementById('welcomeScreen').classList.remove('hidden');
    document.getElementById('messagesContainer').classList.add('hidden');
    
    // تحديث قائمة المحادثات (ستكون فارغة)
    displayChatHistory();

    showNotification('تم تسجيل الخروج بنجاح', 'success');
}

function renderAccountInfo() {
  const n = document.getElementById('accName');
  const e = document.getElementById('accEmail');
  const c = document.getElementById('accCreatedAt');

  if (!n || !e || !c) return;

  if (!currentUser) {
    n.textContent = 'غير مسجّل';
    e.textContent = '—';
    c.textContent = '—';
    return;
  }
  n.textContent = currentUser.name || '—';
  e.textContent = currentUser.email || '—';
  const d = currentUser.createdAt ? new Date(currentUser.createdAt) : null;
  c.textContent = d ? d.toLocaleString() : '—';
}

// ====================== واجهة حساب المستخدم (مثل GPT) ======================
function renderUserMenu(user) {
  const root = document.getElementById('user-info-container');
  if (!root) return;

  // إن لم تكن مسجلاً: زر تسجيل الدخول (نفس سلوكك الحالي)
  if (!user) {
    root.innerHTML = `
      <button onclick="loginWithGoogle()"
              class="flex items-center space-x-2 space-x-reverse bg-white hover:bg-gray-200 text-gray-800 px-4 py-2 rounded-lg transition-colors duration-200 transform hover:scale-105 text-sm font-semibold shadow-md">
        <svg class="w-5 h-5" viewBox="0 0 18 18">
          <g fill-rule="evenodd">
            <path d="M17.64 9.2045c0-.6381-.0573-1.2518-.1636-1.8409H9.1818v3.4818h4.7909c-.2045 1.125-.8227 2.0782-1.7773 2.7218v2.2591h2.9091c1.7045-1.5682 2.6864-3.8727 2.6864-6.6218z" fill="#4285F4"></path>
            <path d="M9.1818 18c2.4455 0 4.4955-.8127 5.9955-2.1818l-2.9091-2.2591c-.8127.5455-1.8545.8727-3.0864.8727-2.3364 0-4.3182-1.5682-5.0364-3.6545H1.2727v2.3364C2.9636 16.2 5.7818 18 9.1818 18z" fill="#34A853"></path>
            <path d="M4.1455 10.8818c-.1136-.3273-.1818-.6818-.1818-1.0455s.0682-.7182.1818-1.0455V6.4545H1.2727C.9455 7.1455.7273 7.9091.7273 8.7273c0 .8182.2182 1.5818.5455 2.2727l2.8727-2.1182z" fill="#FBBC05"></path>
            <path d="M9.1818 3.6545c1.3273 0 2.5182.4545 3.4545 1.3636l2.5818-2.5818C13.6773.9818 11.6273 0 9.1818 0 5.7818 0 2.9636 1.8 1.2727 4.1182l2.8727 2.3364c.7182-2.0864 2.7-3.6545 5.0364-3.6545z" fill="#EA4335"></path>
          </g>
        </svg>
        <span>تسجيل الدخول بـ Google</span>
      </button>
    `;
    return;
  }

  // عند تسجيل الدخول: زر أفاتار + قائمة مثل GPT
  const name = user.name || 'حسابي';
  const email = user.email || '';
  const fallbackPicture = 'https://ui-avatars.com/api/?name=' + encodeURIComponent(name);
  let picture = fallbackPicture;
  try {
    const candidate = new URL(user.picture || fallbackPicture);
    if (candidate.protocol === 'https:') picture = candidate.href;
  } catch (_error) {}

  root.innerHTML = `
    <div class="relative" id="userMenu">
      <button id="userMenuBtn"
              class="user-menu-trigger flex items-center gap-2 px-2 py-1 rounded-lg hover:bg-gray-800/60 transition-colors">
        <img src="${escapeHtml(picture)}" alt="avatar" class="w-8 h-8 rounded-full object-cover" />
        <div class="hidden md:flex flex-col items-start leading-tight text-left">
          <span class="text-sm text-white font-semibold truncate max-w-[160px]">${escapeHtml(name)}</span>
          <span class="text-xs text-gray-400 truncate max-w-[160px]">${escapeHtml(email)}</span>
        </div>
        <i class="fas fa-chevron-down text-gray-400 text-sm md:ml-1"></i>
      </button>

      <div id="userMenuPanel"
           class="user-menu-panel absolute right-0 mt-2 w-64 rounded-xl overflow-hidden shadow-xl hidden">
        <div class="px-4 py-3 bg-gray-900/90 backdrop-blur">
          <div class="flex items-center gap-3">
            <img src="${escapeHtml(picture)}" alt="avatar" class="w-10 h-10 rounded-full object-cover" />
            <div class="min-w-0">
              <div class="text-white font-semibold truncate">${escapeHtml(name)}</div>
              <div class="text-gray-400 text-xs truncate">${escapeHtml(email)}</div>
            </div>
          </div>
        </div>

        <div class="bg-gray-950/90 backdrop-blur divide-y divide-white/5">
          <button class="menu-item w-full text-left px-4 py-3 hover:bg-white/5" onclick="openSettingsFromMenu()">
  <i class="fas fa-cog mr-2"></i> الإعدادات
</button>
          <button class="menu-item w-full text-left px-4 py-3 hover:bg-white/5" onclick="toggleDarkMode()">
            <i class="fas fa-moon mr-2"></i> تبديل المظهر
          </button>
          <button class="menu-item w-full text-left px-4 py-3 hover:bg-white/5 text-red-400" onclick="logout()">
            <i class="fas fa-sign-out-alt mr-2"></i> تسجيل الخروج
          </button>
        </div>
      </div>
    </div>
  `;

  // تفعيل/إغلاق القائمة
  const btn = document.getElementById('userMenuBtn');
  const panel = document.getElementById('userMenuPanel');

  function closePanel(e) {
    if (!panel || !btn) return;
    if (e && (btn.contains(e.target) || panel.contains(e.target))) return;
    panel.classList.add('hidden');
    document.removeEventListener('click', closePanel);
  }

  btn?.addEventListener('click', (e) => {
    e.stopPropagation();
    panel?.classList.toggle('hidden');
    if (!panel?.classList.contains('hidden')) {
      setTimeout(() => document.addEventListener('click', closePanel), 0);
    } else {
      document.removeEventListener('click', closePanel);
    }
  });
}

// إغلاق قائمة الحساب ثم فتح نافذة الإعدادات
function openSettingsFromMenu() {
  try {
    const panel = document.getElementById('userMenuPanel');
    if (panel) panel.classList.add('hidden'); // أخفِ القائمة فوراً
  } catch(e) {}
  openSettings(); // افتح نافذة الإعدادات
}

// ===== تبويبات نافذة الإعدادات =====
function activateSettingsTab(tab) {
  document.querySelectorAll('.settings-tab').forEach(b => {
    b.classList.toggle('active', b.dataset.tab === tab);
  });
  document.querySelectorAll('#settingsPanels .settings-panel').forEach(p => {
    p.classList.toggle('hidden', p.dataset.tab !== tab);
  });
}

// مستمع عام للنقر على تبويبات الإعدادات
document.addEventListener('click', (e) => {
  const btn = e.target.closest('.settings-tab');
  if (!btn) return;
  activateSettingsTab(btn.dataset.tab);
});

// (اختياري) استدعاء عند فتح النافذة لأول مرة
function onOpenSettingsModal() {
  // اجعل تبويب "الحساب" هو الافتراضي
  activateSettingsTab('account');
}
