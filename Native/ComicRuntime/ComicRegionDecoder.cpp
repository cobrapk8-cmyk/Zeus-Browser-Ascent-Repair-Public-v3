#include "ZeusComicRuntime.h"
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <csetjmp>
#include <cstdio>
#include <jpeglib.h>
#include <png.h>
#include <webp/decode.h>
static bool permitted(int fullw,int fullh,int x,int y,int w,int h){return fullw>0&&fullh>0&&fullw<=16384&&fullh<=1000000&&static_cast<int64_t>(fullw)*fullh<=256000000&&x==0&&w==fullw&&y>=0&&h>0&&y<=fullh-h&&static_cast<int64_t>(w)*h<=8000000;}
struct JPEGError{jpeg_error_mgr base;jmp_buf jump;};
static void jpegFailure(j_common_ptr c){longjmp(reinterpret_cast<JPEGError*>(c->err)->jump,1);}
static uint8_t *jpegRegion(const uint8_t *bytes,size_t size,int x,int y,int w,int h){
    jpeg_decompress_struct c{};JPEGError error{};uint8_t *volatile output=nullptr,*volatile row=nullptr;
    c.err=jpeg_std_error(&error.base);error.base.error_exit=jpegFailure;
    if(setjmp(error.jump)){std::free(output);std::free(row);jpeg_destroy_decompress(&c);return nullptr;}
    jpeg_create_decompress(&c);jpeg_mem_src(&c,bytes,size);
    jpeg_read_header(&c,TRUE);
    if(!permitted(c.image_width,c.image_height,x,y,w,h)){jpeg_destroy_decompress(&c);return nullptr;}
    c.out_color_space=JCS_RGB;jpeg_start_decompress(&c);
    output=static_cast<uint8_t*>(std::malloc(static_cast<size_t>(w)*h*4));row=static_cast<uint8_t*>(std::malloc(c.output_width*3));
    if(!output||!row){std::free(output);std::free(row);jpeg_destroy_decompress(&c);return nullptr;}
    jpeg_skip_scanlines(&c,y);
    for(int r=0;r<h;r++){JSAMPROW pointer=row;if(jpeg_read_scanlines(&c,&pointer,1)!=1){std::free(output);output=nullptr;break;}
        for(int col=0;col<w;col++){auto dst=output+(static_cast<size_t>(r)*w+col)*4;auto src=row+(col+x)*3;dst[0]=src[0];dst[1]=src[1];dst[2]=src[2];dst[3]=255;}}
    jpeg_abort_decompress(&c);jpeg_destroy_decompress(&c);std::free(row);return output;
}
struct PNGInput{const uint8_t *bytes;size_t size,offset;};
static void pngRead(png_structp p,png_bytep out,png_size_t count){auto *s=static_cast<PNGInput*>(png_get_io_ptr(p));if(count>s->size-s->offset)png_error(p,"truncated input");std::memcpy(out,s->bytes+s->offset,count);s->offset+=count;}
static uint8_t *pngRegion(const uint8_t *bytes,size_t size,int x,int y,int w,int h){
    auto *p=png_create_read_struct(PNG_LIBPNG_VER_STRING,nullptr,nullptr,nullptr);if(!p)return nullptr;
    auto *info=png_create_info_struct(p);if(!info){png_destroy_read_struct(&p,nullptr,nullptr);return nullptr;}
    uint8_t *volatile output=nullptr,*volatile row=nullptr;
    if(setjmp(png_jmpbuf(p))){std::free(output);std::free(row);png_destroy_read_struct(&p,&info,nullptr);return nullptr;}
    PNGInput input{bytes,size,0};png_set_read_fn(p,&input,pngRead);png_set_user_limits(p,16384,1000000);png_read_info(p,info);
    int width=png_get_image_width(p,info),height=png_get_image_height(p,info),depth=png_get_bit_depth(p,info),color=png_get_color_type(p,info);
    if(!permitted(width,height,x,y,w,h)){png_destroy_read_struct(&p,&info,nullptr);return nullptr;}
    if(depth==16)png_set_strip_16(p);if(color==PNG_COLOR_TYPE_PALETTE)png_set_palette_to_rgb(p);
    if(color==PNG_COLOR_TYPE_GRAY&&depth<8)png_set_expand_gray_1_2_4_to_8(p);
    bool transparency=png_get_valid(p,info,PNG_INFO_tRNS);if(transparency)png_set_tRNS_to_alpha(p);
    if(color==PNG_COLOR_TYPE_GRAY||color==PNG_COLOR_TYPE_GRAY_ALPHA)png_set_gray_to_rgb(p);
    if(!(color&PNG_COLOR_MASK_ALPHA)&&!transparency)png_set_add_alpha(p,255,PNG_FILLER_AFTER);
    int passes=png_set_interlace_handling(p);png_read_update_info(p,info);
    if(png_get_rowbytes(p,info)!=static_cast<size_t>(w)*4)png_error(p,"unexpected row size");
    output=static_cast<uint8_t*>(std::calloc(static_cast<size_t>(w)*h,4));row=static_cast<uint8_t*>(std::calloc(w,4));if(!output||!row)png_error(p,"out of memory");
    for(int pass=0;pass<passes;pass++)for(int r=0;r<(passes==1?y+h:height);r++){auto *destination=r>=y&&r<y+h?output+static_cast<size_t>(r-y)*w*4:row;png_read_row(p,destination,nullptr);}
    if(passes>1)png_read_end(p,info);png_destroy_read_struct(&p,&info,nullptr);std::free(row);return output;
}
extern "C" unsigned char *zeus_comic_decode_region(const unsigned char *bytes,unsigned long size,int x,int y,int w,int h){
    if(!bytes||size<12||size>33554432||w<=0||h<=0||static_cast<int64_t>(w)*h>8000000)return nullptr;
    if(bytes[0]==0xff&&bytes[1]==0xd8)return jpegRegion(bytes,size,x,y,w,h);
    if(png_sig_cmp(bytes,0,8)==0)return pngRegion(bytes,size,x,y,w,h);
    int width=0,height=0;
    if(WebPGetInfo(bytes,size,&width,&height)&&permitted(width,height,x,y,w,h)){
        WebPDecoderConfig config;if(!WebPInitDecoderConfig(&config))return nullptr;
        int aligned=y&~1,offset=y-aligned;size_t length=static_cast<size_t>(w)*(h+offset)*4;
        auto *buffer=static_cast<uint8_t*>(std::malloc(length));if(!buffer)return nullptr;
        config.options.use_cropping=1;config.options.crop_left=0;config.options.crop_top=aligned;config.options.crop_width=w;config.options.crop_height=h+offset;
        config.output.colorspace=MODE_RGBA;config.output.is_external_memory=1;config.output.u.RGBA.rgba=buffer;config.output.u.RGBA.stride=w*4;config.output.u.RGBA.size=length;
        auto status=WebPDecode(bytes,size,&config);WebPFreeDecBuffer(&config.output);if(status!=VP8_STATUS_OK){std::free(buffer);return nullptr;}
        if(offset)std::memmove(buffer,buffer+static_cast<size_t>(w)*4,static_cast<size_t>(w)*h*4);return buffer;
    }
    return nullptr;
}
extern "C" void zeus_comic_free_pixels(unsigned char *pixels){std::free(pixels);}
