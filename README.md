# AnythingLLMDocs.jl

AnythingLLMDocs.jl uploads your Documenter.jl pages and docstrings to an AnythingLLM instance and injects the public chat widget back into the rendered docs. The widget is placed inside a small, sandboxed iframe to avoid the long-standing `require.js` conflicts inside Documenter.

The current code was written primarily by OpenAI Codex and reviewed in full by Stefan Krastanov.

## Quick start

```julia
using AnythingLLMDocs

doc_modules = [MyPackage]
assets = integrate_anythingllm(
    "MyPackage",
    doc_modules,
    @__DIR__;
    repo = "github.com/you/MyPackage.jl.git",
    options = EmbedOptions(),
)
```

Then pass `assets` into `Documenter.HTML(assets = assets)` inside `makedocs`. All embed configuration options documented in the [AnythingLLM embed README](https://raw.githubusercontent.com/Mintplex-Labs/anythingllm-embed/refs/heads/main/README.md) are exposed as `String` fields on `EmbedOptions` (no validation is performed). The iframe is only slightly larger than the chat window and defaults to opening the chat on page load with a smaller window size; adjust with `EmbedOptions` or `embed_attributes` as needed.

### Hacky iframe note

We currently mount the widget inside a small iframe shell because Documenter.jl still ships `require.js`, which collides with the AnythingLLM embed bundle. Once Documenter moves away from `require.js`, the sandbox can be removed.
