# تقرير استلام ZEUS وإصلاحه وتحسينه — فرع Ascent

> المستودع الجديد: **cobrapk8ggggggg-tech/Zeus-Browser-Ascent** — مكمل لفرع `feature/zeus-manhwa-translation-20261101` في Zeus-Browser، بعد قراءته كاملاً (15 commit، 14 ملف Swift، جسر JS، C++ decoder، 10 workflows، وسجل 25 تشغيل CI).

## 1) ما وجدناه: ما بناه المستخدم (ممتاز)

- وحدة `ComicTranslation` كاملة على iOS 18.1+: جسر WKContentWorld معزول، نوافذ طويلة متداخلة بسياق حدود الصور، OCR ثلاثي (Vision/ML Kit/Paddle-ONNX)، تجميع فقاعات بفحص داخل مُسرف، رسم CoreText عربي مع Bidi ونص عمودي، طبقات حفظ 4×32MiB+256MiR، أمان SSRF صارم.
- اختبارات حقيقية: جسر Node، مفكك C++، و18 اختبار XCTest على محاكي فعلي (آخر تشغيل comic: **نجاح**).

## 2) سبب فشل workflow التكامل و IPA — الجذر بالدليل

| الدليل | القيمة |
|---|---|
| خطأ CI المتكرر | `upstream/src/ios/ZeusCloudFiles.swift:136:30: cannot find type 'ZeusOutputKind' in scope` (25×) + `ZeusOutputIndex` + `ZeusConversationFiles` + مهلة type-check |
| سجل التشغيلات | IPA: **3/3 فشل** · Integration: **11 تشغيلاً، 0 نجاح** (البقية ألغاها concurrency) |
| السبب الجذري | ملف `.openminis/Host/ZeusConversationFiles.swift` **مقتطع عند السطر 39** أثناء استيراد المستودع — ينقصه إغلاق `}` والتعريفات كاملة |
| الإثبات المقارن | المستودع القديم `zeus@224f043a` يحمل النسخة الكاملة (258 سطراً) مع `enum ZeusOutputKind` (سطر 42) و`ZeusOutputIndex`؛ نسخة `ZeusCloudFiles.swift` متطابقة حرفياً (diff=0) بين المستودعين |
| النتيجة | `build_project.rb` يُجمّع كل `Host/*.swift` داخل هدف التطبيق → أي ملف ناقص يُسقط البناء كله، فبقيت IPA والتكامل أحمرين منذ أول تشغيل |
| الإصلاح هنا | استعادة الملف كاملاً (217 سطراً) — جعل `main` يظهر في مشغّلات الثلاثة workflows |

## 3) تحسينات هذا الفرع (نقل بأسلوب Ascent)

1. **تلوين الحروف من داخل الفقاعة** (`ComicPixels.swift`):
   - قبل: عيّنة من حلقة حدود المنطقة فقط → تتأثر بضوضاء الحدود.
   - بعد: عيّنة من **حزام داخل الفقاعة** (الثلث الأوسط، مستثنياً صناديق أسطر OCR) — لون الفقاعة نفسه؛ والحلقة احتياط للنص المفتوح فقط.
   - اختيار اللون التلقائي بمعيار **تباين WCAG** (أسود مطبوع 0.04 مقابل أبيض 0.99) بدل عتبة إضاءة واحدة — فقاعات رمادية/مملّة تأخذ الحبر الأوضح فعلاً.
2. **نظام الخطوط**:
   - الافتراضي للعربية صار **GeezaPro** (خط iOS العربي الأصلي) بدل ArialMT الذي يهزم تشكيل النسخ داخل الفقاعات الضيقة.
   - منتقي الخطوط أضاف **خطوط النظام العربية**: GeezaPro، Damascus، Baghdad، Al Bayan، Sana، Nadeem — تعمل فوراً دون استيراد، مع بقاء استيراد TTF/OTF/TTC وضبط الحجم.
3. **workflow التكافؤ** `zeus-ascent-parity.yml`: جسر + مفكك + بناء واختبار على محاكي فعلي + بوابة أدلة `sim_probe.py` (ترفض أن يجتاز اختبار جوهري دون ظهوره في السجل) + **تقرير درجة تكافؤ** مبني على قائمة قدرات Ascent من تحليل REA الموثق، مع فصل: مثبت/غير مثبت/موثق بلا اختبار/خارج النطاق — ولا تُحتسب غير المقاسة.
4. **`parity_selftest.py`**: يثبت أن الأداة تعطي 100% بالأدلة الكاملة و0.0% بلا أدلة ولا تخترع نتائج.

## 4) خريطة القدرات مقابل Ascent 1.0.25

آلية حية في كل تشغيل: `docs/comic-translation/ascent-parity.json` (20 قدرة بأدلة REA) → `.zeus-ci/comic/parity_report.py` → `PARITY-CI.ar.md` في artifacts الـ workflow.
الفجوات المعلنة بصدق: نص مائل/منظور وSFX مركبة، وعزل عملية فك الصور (هنا C++ داخل التطبيق مقابل SharedMemory بين عمليتين في Ascent). القارئ المستقل **مقصيات العمداً** — سيأتي في تطبيق Tachiyomi-منفصل كما قررت.

## 5) كيف تشغّل

```bash
# التكافؤ الكامل (جسر + مفكك + محاكي + تقرير):
Actions → "ZEUS-Ascent parity — tests, simulator and gap report" → Run workflow (main)

# بناء IPA للجهاز (الآن يكتمل بعد إصلاح الملف):
Actions → "ZEUS integrated IPA - build and publish (no tests)" → Run workflow (main)
```
