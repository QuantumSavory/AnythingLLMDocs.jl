using AnythingLLMDocs
using Aqua
using Test

@testset "Aqua" begin
    Aqua.test_all(AnythingLLMDocs)
end

@testset "Configuration and embed defaults" begin
    cfg = AnythingLLMDocs.AnythingLLMConfig(
        "https://example.com/api/v1/",
        "dummy",
        "example.com",
    )
    @test AnythingLLMDocs.host_from_api(cfg.api_base) == "https://example.com"

    opts = AnythingLLMDocs.EmbedOptions()
    attrs = AnythingLLMDocs.embed_attributes(opts)
    @test attrs["data-open-on-load"] == "on"
    @test attrs["data-window-width"] == "300px"
    @test attrs["data-window-height"] == "400px"
end

@testset "Live AnythingLLM integration" begin
    cfg = AnythingLLMDocs.AnythingLLMConfig(
        "https://anythingllm.krastanov.org/api/v1",
        AnythingLLMDocs.default_api_key(),
        ""
    )

    workspace_name = "AnythingLLMDocs test $(time_ns())"
    workspace = AnythingLLMDocs.recreate_workspace!(cfg, workspace_name)
    slug = String(get(workspace, "slug", AnythingLLMDocs.slugify(workspace_name)))

    try
        locs = AnythingLLMDocs.upload_raw!(
            cfg,
            slug;
            title = "Live check",
            text = "Hello from AnythingLLMDocs.",
            source = "docs/test.md",
        )
        AnythingLLMDocs.move_files_to_folder!(cfg, slug, locs)
        uuid = AnythingLLMDocs.create_embed!(cfg, slug)
        html = AnythingLLMDocs.embed_script(cfg, uuid)

        @test occursin(uuid, html)
        @test occursin("data-open-on-load", html)
        @test occursin("anythingllm-chat-widget.min.js", html)
    finally
        try
            AnythingLLMDocs.delete_workspace!(cfg, slug)
        catch err
            @warn "cleanup failed" exception = (err, catch_backtrace())
        end
    end
end
