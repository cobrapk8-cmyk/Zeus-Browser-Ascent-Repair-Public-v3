function getFileTypeInfo(filename) {
    const extension = filename.split('.').pop()?.toLowerCase();
    return fileTypeConfig[extension] || {
        icon: 'fas fa-file',
        color: 'file-icon-default',
        type: 'ملف'
    };
}

function formatFileSize(bytes) {
    if (bytes === 0) return '0 بايت';
    const k = 1024;
    const sizes = ['بايت', 'ك.ب', 'م.ب', 'ج.ب'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
}

function createFileCard(file) {
    const fileInfo = getFileTypeInfo(file.name);
    const fileSize = formatFileSize(file.size);

    const cardHtml = `
        <div class="file-card-bubble">
            <div class="file-card">
                <div class="file-icon-container ${fileInfo.color}">
                    <i class="${fileInfo.icon}"></i>
                </div>
                <div class="file-info">
                    <div class="file-name">${escapeHtml(file.name)}</div>
                    <div class="file-meta">${fileInfo.type} • ${fileSize}</div>
                </div>
            </div>
        </div>
    `;

    return cardHtml;
}

// ✅ إصلاح جذري: جمع المرفقات بشكل صحيح + رفع مرة واحدة فقط + التعامل مع عدم وجود توكن
async function processAttachedFiles(files) {
  const token = localStorage.getItem('authToken');
  const fileData = [];

  // 1) اجمع معلومات كل ملف واقرأ محتواه (للاستخدام مع الذكاء حتى لو لم نحفظ على الخادم)
  const textExt = ['txt','js','html','css','json','xml','md','py','java','cpp','c','cs','php','rb','sql','yaml','yml','csv','log'];
  const imgExt  = ['jpg','jpeg','png','gif','webp','bmp'];

  for (const file of files) {
    const info = {
      name: file.name,
      size: file.size,
      type: file.type,
      lastModified: file.lastModified
    };

    const ext = (file.name.split('.').pop() || '').toLowerCase();
    try {
      if (textExt.includes(ext)) {
        info.dataType = 'text';
        info.content  = await readFileAsText(file);
      } else if (imgExt.includes(ext) || (file.type && file.type.startsWith('image/'))) {
        info.dataType = 'image';
        info.mimeType = file.type || 'image/*';
        info.content  = await readFileAsBase64(file);
      } else {
        info.dataType = 'binary';
        // لا حاجة لقراءة المحتوى الثنائي هنا
      }
    } catch (e) {
      console.error('Error reading file:', e);
    }

    // 👈 المهم: أضف المعلومات للمصفوفة
    fileData.push(info);
  }

  // 2) لو لا يوجد توكن، لا تحاول الرفع — اكتفِ بالمحتوى المحلي (ستظهر البطاقات وتُرسل للذكاء)
  if (!token) {
    showNotification('لا يمكنك حفظ الملفات على الخادم قبل تسجيل الدخول. سَأستخدم المرفقات مؤقتًا فقط داخل هذه الرسالة.', 'warning');
    return fileData;
  }

  // 3) ارفع جميع الملفات دفعة واحدة (طلب واحد فقط) ثم اربط نتائج الرفع بكل عنصر
  try {
    const form = new FormData();
    for (const f of files) {
      form.append('files', f, f.name); // الخادم يتوقع الحقل "files"
    }

    const uploadRes = await fetch(`${API_BASE_URL}/api/uploads`, {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${token}` },
      body: form
    });

    if (!uploadRes.ok) {
      const errText = await uploadRes.text();
      throw new Error(`فشل رفع الملفات: ${uploadRes.status} - ${errText}`);
    }

    const uploaded = await uploadRes.json();           // { files: [...] }
    const byName = Object.fromEntries(
      (uploaded.files || []).map(u => [u.originalName || u.filename, u])
    );

    for (const info of fileData) {
      const rec = byName[info.name];
      if (rec) {
        info.fileId  = rec.id || rec._id || rec.filename || null;
        info.fileUrl = rec.url || null;               // مثال: /uploads/xxxx
      }
    }
  } catch (e) {
    console.error('Upload error:', e);
    showNotification('تعذر رفع الملفات للحفظ الدائم', 'error');
    // نُرجع على أي حال الـ fileData حتى تظهر البطاقات ويُستخدم المحتوى مع الذكاء
  }

  return fileData;
}


function readFileAsText(file) {
    return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = e => resolve(e.target.result);
        reader.onerror = reject;
        reader.readAsText(file);
    });
}

// دالة جديدة لقراءة الملفات كـ Base64
function readFileAsBase64(file) {
    return new Promise((resolve, reject) => {
        // ✨✨✨ التحقق من حجم الملف (5 ميجابايت) ✨✨✨
        if (file.size > 5 * 1024 * 1024) {
            return reject(new Error('حجم الملف كبير جدًا. الحد الأقصى هو 5 ميجابايت.'));
        }
        const reader = new FileReader();
        reader.onloadend = () => {
            const base64String = reader.result.split(',')[1];
            resolve(base64String);
        };
        reader.onerror = reject;
        reader.readAsDataURL(file);
    });
}


// File preview functions for input area
function handleFileSelection(input) {
    const files = Array.from(input.files);
    if (files.length === 0) return;

    displayFilePreview(files);
}

function displayFilePreview(files) {
    const container = document.getElementById('filePreviewContainer');
    const list = document.getElementById('filePreviewList');

    list.innerHTML = '';

    files.forEach((file, index) => {
        const fileInfo = getFileTypeInfo(file.name);
        const fileSize = formatFileSize(file.size);

        const preview = document.createElement('div');
        preview.className = 'inline-flex items-center bg-gray-700 rounded-lg px-3 py-2 text-sm';
        preview.innerHTML = `
            <div class="file-icon-container ${fileInfo.color} w-6 h-6 text-xs mr-2">
                <i class="${fileInfo.icon}"></i>
            </div>
            <span class="text-gray-200 mr-2">${escapeHtml(file.name)}</span>
            <span class="text-gray-400 text-xs mr-2">(${fileSize})</span>
            <button onclick="removeFileFromPreview(${index})" class="text-gray-400 hover:text-gray-200 ml-1">
                <i class="fas fa-times text-xs"></i>
            </button>
        `;
        list.appendChild(preview);
    });

    container.classList.remove('hidden');
}

function removeFileFromPreview(index) {
    const fileInput = document.getElementById('fileInput');
    const files = Array.from(fileInput.files);

    files.splice(index, 1);

    // Create new FileList
    const dt = new DataTransfer();
    files.forEach(file => dt.items.add(file));
    fileInput.files = dt.files;

    if (files.length === 0) {
        clearFileInput();
    } else {
        displayFilePreview(files);
    }
}

function clearFileInput() {
    document.getElementById('fileInput').value = '';
    document.getElementById('filePreviewContainer').classList.add('hidden');
}

// Advanced streaming functions
