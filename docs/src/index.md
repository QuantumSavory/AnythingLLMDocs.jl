# AnythingLLMDocs.jl

AnythingLLMDocs.jl resets or creates an AnythingLLM workspace for your package docs, uploads Markdown sources and docstrings, and mounts the embed widget back into the generated HTML using a small sandboxed iframe.

## Usage

```julia
using AnythingLLMDocs

doc_modules = [MyPackage]
api_base="https://anythingllm.krastanov.org/api/v1"
assets = integrate_anythingllm(
    "MyPackage",
    doc_modules,
    @__DIR__,
    api_base;
    repo = "github.com/you/MyPackage.jl.git",
    options = EmbedOptions(; greeting = "Docs-aware helper", window_width = "320px"),
)
```

Pass `assets` to `Documenter.HTML(assets = assets)` in `makedocs`. All embed attributes listed in the upstream AnythingLLM embed README are represented as `String` fields in `EmbedOptions`.

## Environmental Variables

Set `ANYTHINGLLMDOC_FORCE_DEPLOY` to any non-empty value to bypass the deploy check when building docs locally. Configure the environmental variable `ANYTHINGLLM_API_KEY` if you want to avoid hardcoding API keys in the source code.
