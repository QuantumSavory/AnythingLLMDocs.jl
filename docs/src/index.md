# AnythingLLMDocs.jl

AnythingLLMDocs.jl resets or creates an AnythingLLM workspace for your package docs, uploads Markdown sources and docstrings, and mounts the embed widget back into the generated HTML using a small sandboxed iframe.

## Usage

```julia
using AnythingLLMDocs

doc_modules = [MyPackage]
assets = integrate_anythingllm(
    "MyPackage",
    doc_modules,
    @__DIR__;
    repo = "github.com/you/MyPackage.jl.git",
    options = EmbedOptions(; greeting = "Docs-aware helper", window_width = "320px"),
)
```

Pass `assets` to `Documenter.HTML(assets = assets)` in `makedocs`. All embed attributes listed in the upstream AnythingLLM embed README are represented as `String` fields in `EmbedOptions` and may also be passed directly through `embed_attributes` without validation. The iframe wrapper is only slightly larger than the chat window and defaults to opening the chat immediately with a smaller footprint.

## Deployment toggles

Set `ANYTHINGLLMDOC_FORCE_DEPLOY` to any non-empty value to bypass the deploy check when building docs locally. Configure `ANYTHINGLLM_API_BASE` and `ANYTHINGLLM_API_KEY` to point to your instance; the defaults target `https://anythingllm.krastanov.org/api/v1`.
