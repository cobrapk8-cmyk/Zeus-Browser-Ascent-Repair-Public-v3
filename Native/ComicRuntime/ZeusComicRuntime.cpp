#include "ZeusComicRuntime.h"
#include "llama.h"
#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <string>
#include <vector>
struct ZeusComicModel { llama_model *model; llama_context *context; };
extern "C" void *zeus_comic_load(const char *path,int context,int threads) {
    llama_backend_init();auto mp=llama_model_default_params();mp.n_gpu_layers=0;
    auto *model=llama_model_load_from_file(path,mp);if(!model)return nullptr;
    auto cp=llama_context_default_params();cp.n_ctx=std::max(512,std::min(context,4096));cp.n_batch=512;cp.n_threads=std::max(1,threads);cp.n_threads_batch=cp.n_threads;
    auto *ctx=llama_init_from_model(model,cp);if(!ctx){llama_model_free(model);return nullptr;}
    return new ZeusComicModel{model,ctx};
}
extern "C" void zeus_comic_unload(void *handle){if(!handle)return;auto *h=static_cast<ZeusComicModel*>(handle);llama_free(h->context);llama_model_free(h->model);delete h;}
extern "C" void zeus_comic_free_text(char *text){std::free(text);}
extern "C" char *zeus_comic_generate(void *handle,const char *input,int maximum,int(*cancelled)(void*),void *context){
    if(!handle||!input)return nullptr;auto *h=static_cast<ZeusComicModel*>(handle);auto *vocab=llama_model_get_vocab(h->model);
    llama_chat_message message{"user",input};const char *tmpl=llama_model_chat_template(h->model,nullptr);
    int n=llama_chat_apply_template(tmpl,&message,1,true,nullptr,0);if(n<=0||n>262144)return nullptr;
    std::vector<char> formatted(n+1);llama_chat_apply_template(tmpl,&message,1,true,formatted.data(),formatted.size());
    int count=-llama_tokenize(vocab,formatted.data(),n,nullptr,0,true,true);if(count<=0)return nullptr;
    std::vector<llama_token> tokens(count);count=llama_tokenize(vocab,formatted.data(),n,tokens.data(),tokens.size(),true,true);
    if(count<=0||count+16>=static_cast<int>(llama_n_ctx(h->context)))return nullptr;
    llama_kv_cache_clear(h->context);
    for(int i=0;i<count;i+=512){if(cancelled&&cancelled(context))return nullptr;auto batch=llama_batch_get_one(tokens.data()+i,std::min(512,count-i));if(llama_decode(h->context,batch)!=0)return nullptr;}
    auto sampler=std::unique_ptr<llama_sampler,decltype(&llama_sampler_free)>(llama_sampler_init_greedy(),llama_sampler_free);
    std::string output;int available=std::min({maximum,2048,static_cast<int>(llama_n_ctx(h->context))-count-8});
    for(int i=0;i<available;i++){
        if(cancelled&&cancelled(context))return nullptr;
        auto token=llama_sampler_sample(sampler.get(),h->context,-1);if(llama_vocab_is_eog(vocab,token))return strdup(output.c_str());
        std::vector<char> piece(256);int size=llama_token_to_piece(vocab,token,piece.data(),piece.size(),0,true);if(size<0){piece.resize(-size);size=llama_token_to_piece(vocab,token,piece.data(),piece.size(),0,true);}if(size>0)output.append(piece.data(),size);
        if(output.size()>524288)return nullptr;
        auto batch=llama_batch_get_one(&token,1);if(llama_decode(h->context,batch)!=0)return nullptr;
    }
    // An incomplete JSON answer must never be accepted as a successful translation.
    return nullptr;
}
