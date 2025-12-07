push!(LOAD_PATH, "../src/")

using Documenter
using AnythingLLMDocs

ENV["ANYTHINGLLMDOC_FORCE_DEPLOY"] = get(
    ENV,
    "ANYTHINGLLMDOC_FORCE_DEPLOY",
    "AnythingLLMDocs docs build",
)

doc_modules = [AnythingLLMDocs]

assets = integrate_anythingllm(
    "AnythingLLMDocs",
    doc_modules,
    @__DIR__;
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

if !isempty(get(ENV, "DOCUMENTER_KEY", "")) || !isempty(get(ENV, "GITHUB_TOKEN", ""))
    deploydocs(repo = "github.com/QuantumSavory/AnythingLLMDocs.jl.git")
else
    @info "Skipping deploydocs because no credentials were provided."
end
