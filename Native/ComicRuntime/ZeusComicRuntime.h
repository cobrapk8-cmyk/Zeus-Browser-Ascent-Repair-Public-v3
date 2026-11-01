#ifndef ZEUS_COMIC_RUNTIME_H
#define ZEUS_COMIC_RUNTIME_H
#ifdef __cplusplus
extern "C" {
#endif
unsigned char *zeus_comic_decode_region(const unsigned char *bytes, unsigned long size, int x, int y, int width, int height);
void zeus_comic_free_pixels(unsigned char *pixels);
void *zeus_comic_load(const char *path, int context, int threads);
char *zeus_comic_generate(void *handle, const char *prompt, int maximum_tokens, int (*cancelled)(void *), void *context);
void zeus_comic_free_text(char *text);
void zeus_comic_unload(void *handle);
#ifdef __cplusplus
}
#endif
#endif
