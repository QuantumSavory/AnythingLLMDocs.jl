using AnythingLLMDocs
using Aqua
using Test

@testset "Aqua" begin
    Aqua.test_all(AnythingLLMDocs)
end

@testset "Configuration and embed defaults" begin
    cfg = AnythingLLMDocs.AnythingLLMConfig(
        api_base = "https://example.com/api/v1/",
        api_key = "dummy",
        allowlist = "example.com",
    )
    @test AnythingLLMDocs.host_from_api(cfg.api_base) == "https://example.com"

    opts = AnythingLLMDocs.EmbedOptions()
    attrs = AnythingLLMDocs.embed_attributes(opts)
    @test attrs["data-open-on-load"] == "on"
    @test attrs["data-window-width"] == "340px"
    @test attrs["data-window-height"] == "520px"
end

@testset "Live AnythingLLM integration" begin
    key = get(ENV, "ANYTHINGLLM_API_KEY", "6CNW0SP-V4D46D9-K84QJ19-VHWGSYT")
    ENV["ANYTHINGLLM_API_KEY"] = key
    ENV["ANYTHINGLLM_API_BASE"] = get(
        ENV,
        "ANYTHINGLLM_API_BASE",
        "https://anythingllm.krastanov.org/api/v1",
    )

    cfg = AnythingLLMDocs.load_config()
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
