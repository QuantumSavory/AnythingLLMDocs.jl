using Documenter
using AnythingLLMDocs

doc_modules = [AnythingLLMDocs]

api_base="https://anythingllm.krastanov.org/api/v1"

assets = integrate_anythingllm(
    "AnythingLLMDocs",
    doc_modules,
    @__DIR__,
    api_base;
    repo = "github.com/QuantumSavory/AnythingLLMDocs.jl.git",
    options = EmbedOptions(),
)

makedocs(
    clean = true,
    doctest = false,
    modules = doc_modules,
    sitename = "AnythingLLMDocs.jl",
    format = Documenter.HTML(assets = assets),
    repo = "",
    remotes = nothing,
    warnonly = [:missing_docs],
    pages = [
        "index.md",
    ],
)

deploydocs(repo = "github.com/QuantumSavory/AnythingLLMDocs.jl.git")
