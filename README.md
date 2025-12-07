# AnythingLLMDocs.jl

AnythingLLMDocs.jl uploads your Documenter.jl pages and docstrings to an AnythingLLM instance and injects the public chat widget back into the rendered docs.

### Hacky iframe note

We currently mount the widget inside a small iframe shell because Documenter.jl still ships `require.js`, which collides with the AnythingLLM embed bundle. Once Documenter moves away from `require.js`, the sandbox can be removed.
