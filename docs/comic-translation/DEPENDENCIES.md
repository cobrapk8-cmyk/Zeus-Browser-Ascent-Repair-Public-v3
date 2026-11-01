# Image translation dependencies

Independent ZEUS implementation. No APK, decompiled proprietary source, private API credential, or proprietary native binary is distributed here.

| Component | Pinned version | Purpose | Upstream license |
|---|---|---|---|
| Google ML Kit Text Recognition | 9.0.0 (CocoaPods) | Device Latin/Japanese/Chinese/Korean OCR | Google SDK terms; review upstream redistribution terms |
| ONNX Runtime | 1.24.2, b7fb7f7dea8a2469e6335d95a61b8f36d0dc83b2 | Paddle inference | MIT |
| PaddlePaddle OCR model artifacts | individual immutable Hugging Face revisions in comic-models.json | Detector, 10 script recognizers, dictionaries | Review each upstream model card; PaddleOCR is Apache-2.0 |
| llama.cpp | b5046, 74d4f5b041ad837153b0e90fc864b8290e01d8d5 | Optional imported GGUF inference | MIT; imported weights have their own license |
| libjpeg-turbo | 3.1.0 | JPEG regional decode | BSD/IJG/zlib notices |
| libpng | v1.6.47 | PNG row decode | libpng license |
| libwebp | v1.5.0 | WebP cropped decode | BSD-3-Clause |
| Apple Vision/CoreText/ImageIO/WebKit | iOS SDK, minimum iOS 18.1 | Simulator OCR, text shaping, pixels, browser | Apple platform SDK terms |
| jsdom (test only) | 26.1.0 | DOM regression tests | MIT |
| Pillow (test only) | 11.3.0 | Decoder pixel reference | HPND |

Native build scripts fetch sources; retain their license/notice files with distribution. Public online translation endpoints retain their own terms, quotas and availability. Keyed services are disabled until the user supplies their account credentials.
