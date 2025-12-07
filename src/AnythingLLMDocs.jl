module AnythingLLMDocs

export integrate_anythingllm, EmbedOptions

import Documenter
using Documenter: RawHTMLHeadContent
using Documenter.DocSystem
using HTTP
using JSON

default_api_key() = get(ENV, "ANYTHINGLLM_API_KEY", "")

"""
Configuration for connecting to an AnythingLLM instance.

`api_base` should point to the `/api/v1` root, `api_key` is the bearer token,
`allowlist` controls embed domain restrictions, and `embed_host` is the host
serving the embed script (derived from `api_base` when not provided).
"""
struct AnythingLLMConfig
    api_base
    api_key
    allowlist
    embed_host
    function AnythingLLMConfig(api_base, api_key, allowlist, embed_host)
        clean_api_base = strip_trailing_slash(api_base)
        clean_embed_host = strip_trailing_slash(embed_host)
        new(clean_api_base, api_key, allowlist, clean_embed_host)
    end
end

"""Remove a trailing slash from `s` if present."""
strip_trailing_slash(s::AbstractString) = endswith(s, "/") ? s[1:end-1] : s

"""Derive the host root from an API base, stripping `/api/v1` and trailing slashes."""
function host_from_api(api_base)
    stripped = replace(strip_trailing_slash(api_base), r"/api/v1$" => "")
    return strip_trailing_slash(stripped)
end

"""Create a configuration, normalizing defaults and derived host values."""
function AnythingLLMConfig(
    api_base,
    api_key,
    allowlist
)
    return AnythingLLMConfig(api_base, api_key, allowlist, host_from_api(strip_trailing_slash(api_base)))
end

"""Build a fully-qualified API URL for `path` relative to the configured base."""
api_url(cfg::AnythingLLMConfig, path::AbstractString) = string(cfg.api_base, path)

"""
Perform an HTTP request against AnythingLLM and parse JSON.

Throws if no API key is configured or if the status is non-2xx. Returns the
parsed JSON object or a `Dict` with `"raw"` when parsing fails.
"""
function request_json(cfg::AnythingLLMConfig, method, path; body=nothing)
    isempty(cfg.api_key) && error("ANYTHINGLLM_API_KEY must be provided")

    headers = ["Authorization" => "Bearer $(cfg.api_key)"]
    payload = body === nothing ? nothing : JSON.json(body)
    if payload !== nothing
        push!(headers, "Content-Type" => "application/json")
    end
    resp = HTTP.request(method, api_url(cfg, path), headers, payload === nothing ? "" : payload)
    if resp.status ÷ 100 == 2
        text = String(resp.body)
        if isempty(text)
            return Dict{String,Any}()
        end
        try
            return JSON.parse(text)
        catch
            return Dict{String,Any}("raw" => text)
        end
    end
    error("AnythingLLM $(method) $(path) failed with status $(resp.status): $(String(resp.body))")
end

"""Create a URL-friendly slug from an arbitrary package name."""
slugify(name::AbstractString) = replace(lowercase(strip(name)), r"[^a-z0-9]+" => "-")

"""List all workspaces from AnythingLLM."""
function current_workspaces(cfg)
    data = request_json(cfg, "GET", "/workspaces")
    get(data, "workspaces", Vector{Any}())
end

"""Delete a workspace by slug."""
function delete_workspace!(cfg, slug::AbstractString)
    request_json(cfg, "DELETE", "/workspace/$slug")
    return slug
end

"""Return all document entries (flattened) from the AnythingLLM file browser."""
function list_documents(cfg)
    data = request_json(cfg, "GET", "/documents")
    items = get(get(data, "localFiles", Dict{String,Any}()), "items", Vector{Any}())
    docs = Any[]
    stack = collect(items)
    while !isempty(stack)
        entry = pop!(stack)
        if get(entry, "type", "") == "file"
            push!(docs, entry)
        elseif get(entry, "type", "") == "folder"
            append!(stack, get(entry, "items", Any[]))
        end
    end
    return docs
end

"""Delete the provided document `names` from AnythingLLM."""
function delete_documents!(cfg, names::Vector{String})
    isempty(names) && return
    request_json(cfg, "DELETE", "/system/remove-documents"; body=Dict("names" => names))
end

"""
Delete uploaded documentation artifacts associated with a workspace.

Matches on known doc and docstring `docSource` markers containing the workspace
name or slug.
"""
function delete_workspace_documents!(cfg, name, slug)
    docs = list_documents(cfg)
    targets = String[]
    for doc in docs
        docsource = get(doc, "docSource", "")
        docloc = lowercase(String(get(doc, "location", get(doc, "name", ""))))
        if isempty(docsource)
            continue
        end
        if startswith(docsource, "docs/") || startswith(docsource, "docstring:")
            if occursin(lowercase(slug), lowercase(docsource)) || occursin(lowercase(name), lowercase(docsource)) || occursin(lowercase(slug), docloc) || occursin(lowercase(name), docloc)
                push!(targets, String(get(doc, "location", get(doc, "name", ""))))
            end
        end
    end
    delete_documents!(cfg, targets)
end

"""Ensure a folder exists (best effort)."""
function ensure_folder!(cfg, folder)
    try
        request_json(cfg, "POST", "/document/create-folder"; body=Dict("name" => folder))
    catch err
        @debug "create-folder failed (possibly exists)" exception = (err, catch_backtrace())
    end
end

"""
Move uploaded documents into a target folder.

`locations` should be the `location` paths returned by AnythingLLM uploads.
"""
function move_files_to_folder!(cfg, folder, locations::Vector{String})
    isempty(locations) && return
    ensure_folder!(cfg, folder)
    files = [
        Dict("from" => loc, "to" => string(folder, "/", split(loc, "/")[end]))
        for loc in locations
    ]
    request_json(cfg, "POST", "/document/move-files"; body=Dict("files" => files))
end

function delete_embeds_for_workspace!(cfg, workspace_slugs::Set{String}, workspace_by_id::AbstractDict)
    embeds = get(request_json(cfg, "GET", "/embed"), "embeds", Vector{Any}())
    for embed in embeds
        ws_id = get(get(embed, "workspace", Dict{Any,Any}()), "id", nothing)
        ws_slug = ws_id === nothing ? nothing : get(workspace_by_id, ws_id, nothing)
        if ws_slug !== nothing && ws_slug in workspace_slugs
            uuid = get(embed, "uuid", nothing)
            uuid === nothing && continue
            request_json(cfg, "DELETE", "/embed/$uuid")
        end
    end
end

"""
Recreate the workspace named `name`, ensuring embeds and uploaded docs are removed first.

Returns the newly created workspace object.
"""
function recreate_workspace!(cfg, name)
    workspaces = current_workspaces(cfg)
    target_slug = slugify(name)
    workspace_by_id = Dict(ws["id"] => String(ws["slug"]) for ws in workspaces if haskey(ws, "id") && haskey(ws, "slug"))
    matches = Set{String}(
        String(ws["slug"]) for ws in workspaces if (
            get(ws, "name", "") == name || get(ws, "slug", "") == target_slug
        ) && haskey(ws, "slug")
    )
    if !isempty(matches)
        delete_embeds_for_workspace!(cfg, matches, workspace_by_id)
        for slug in matches
            delete_workspace_documents!(cfg, name, slug)
            delete_workspace!(cfg, slug)
        end
    end
    workspace = request_json(cfg, "POST", "/workspace/new"; body=Dict("name" => name))
    return get(workspace, "workspace", workspace)
end

"""
Upload a text blob as a document to AnythingLLM, attaching metadata.

Returns the locations of the created document artifacts.
"""
function upload_raw!(cfg, workspace_slug; title, text, source)
    body = Dict(
        "textContent" => text,
        "addToWorkspaces" => workspace_slug,
        "metadata" => Dict(
            "title" => title,
            "docSource" => source,
        ),
    )
    resp = request_json(cfg, "POST", "/document/raw-text"; body=body)
    docs = get(resp, "documents", Any[])
    return String[
        String(get(doc, "location", get(doc, "name", "")))
        for doc in docs if get(doc, "location", nothing) !== nothing || get(doc, "name", nothing) !== nothing
    ]
end

"""Extract the first Markdown heading text, if present."""
function first_heading(text::AbstractString)
    for line in split(text, '\n')
        m = match(r"^\\s*#\\s+(.*)$", line)
        m !== nothing && return strip(m.captures[1])
    end
    return ""
end

"""
Upload all Markdown sources under `docs_root` into the target workspace.

Returns the locations of uploaded artifacts.
"""
function upload_markdown_sources!(cfg, workspace_slug, docs_root)
    locations = String[]
    for (root, _, files) in walkdir(docs_root)
        for file in files
            endswith(file, ".md") || continue
            path = joinpath(root, file)
            text = read(path, String)
            title = first_heading(text)
            title = isempty(title) ? file : title
            rel = relpath(path, docs_root)
            append!(locations, upload_raw!(cfg, workspace_slug; title=title, text=text, source="docs/$rel"))
        end
    end
    return locations
end

"""Convert Markdown content to a plain text representation for upload."""
markdown_string(md) = sprint(io -> show(io, MIME"text/plain"(), md))

"""
Collect docstrings for the given module into a Dict keyed by fully-qualified name.
"""
function docstrings_for_module(mod::Module)
    entries = Dict()
    for name in names(mod; all=false, imported=false)
        binding = DocSystem.binding(mod, name)
        docs = DocSystem.getdocs(binding)
        isempty(docs) && continue
        key = string(mod, ".", name)
        texts = [markdown_string(DocSystem.parsedoc(d)) for d in docs]
        entries[key] = join(texts, "\n\n---\n\n")
    end
    return entries
end

"""
Upload collected docstrings for all provided modules to AnythingLLM.

Returns the locations of uploaded artifacts.
"""
function upload_docstrings!(cfg, workspace_slug, modules::Vector{Module})
    seen = Set{String}()
    locations = String[]
    for mod in modules
        for (key, text) in docstrings_for_module(mod)
            if key in seen || isempty(strip(text))
                continue
            end
            push!(seen, key)
            append!(
                locations,
                upload_raw!(cfg, workspace_slug; title=key, text=text, source="docstring:$key"),
            )
        end
    end
    return locations
end

"""Embed configuration options mirrored from AnythingLLM's embed README."""
Base.@kwdef mutable struct EmbedOptions
    prompt = ""
    model = ""
    temperature = ""
    language = ""
    chat_icon = "magic"
    button_color = ""
    user_bg_color = ""
    assistant_bg_color = ""
    brand_image_url = "false"
    greeting = "This is an LLM helper with access to the entirety of the docs. You can directly ask it your questions. As usual, take anything it says with a grain of salt -- LLMs are prone to confabulating."
    no_sponsor = "true"
    no_header = "true"
    sponsor_link = ""
    sponsor_text = ""
    position = "bottom-right"
    assistant_name = "AnythingLLM Chat Assistant"
    assistant_icon = ""
    window_height = "400px"
    window_width = "300px"
    text_size = ""
    username = ""
    default_messages = ""
    send_message_text = ""
    reset_chat_text = ""
    open_on_load = "on"
    show_thoughts = ""
    support_email = ""
end

"""Convert options into data-attributes for the embed script tag."""
function embed_attributes(opts::EmbedOptions; custom=Dict()) # TODO implement without silly name repetition by extracting named tuple
    attrs = Dict(
        "data-prompt" => opts.prompt,
        "data-model" => opts.model,
        "data-temperature" => opts.temperature,
        "data-language" => opts.language,
        "data-chat-icon" => opts.chat_icon,
        "data-button-color" => opts.button_color,
        "data-user-bg-color" => opts.user_bg_color,
        "data-assistant-bg-color" => opts.assistant_bg_color,
        "data-brand-image-url" => opts.brand_image_url,
        "data-greeting" => opts.greeting,
        "data-no-sponsor" => opts.no_sponsor,
        "data-no-header" => opts.no_header,
        "data-sponsor-link" => opts.sponsor_link,
        "data-sponsor-text" => opts.sponsor_text,
        "data-position" => opts.position,
        "data-assistant-name" => opts.assistant_name,
        "data-assistant-icon" => opts.assistant_icon,
        "data-window-height" => opts.window_height,
        "data-window-width" => opts.window_width,
        "data-text-size" => opts.text_size,
        "data-username" => opts.username,
        "data-default-messages" => opts.default_messages,
        "data-send-message-text" => opts.send_message_text,
        "data-reset-chat-text" => opts.reset_chat_text,
        "data-open-on-load" => opts.open_on_load,
        "data-show-thoughts" => opts.show_thoughts,
        "data-support-email" => opts.support_email,
    )
    # Drop empties to keep markup lean.
    for key in collect(keys(attrs))
        isempty(strip(attrs[key])) && delete!(attrs, key)
    end
    merge!(attrs, Dict(string(k) => v for (k, v) in custom))
    return attrs
end

"""Default styling for the sandboxed iframe shell."""
function default_iframe_style()
    Dict(
        "position" => "fixed",
        "bottom" => "0",
        "right" => "0",
        "width" => "360px", # slightly larger than the chat window
        "height" => "560px",
        "maxWidth" => "min(95vw, 360px)",
        "maxHeight" => "min(95vh, 560px)",
        "border" => "none",
        "zIndex" => "2147483000",
        "background" => "transparent",
    )
end

escape_attr(s::AbstractString) = replace(s, '"' => "&quot;", '&' => "&amp;", '<' => "&lt;", '>' => "&gt;")
escape_js(s::AbstractString) = replace(s, "\\" => "\\\\", "\"" => "\\\"", "\n" => "\\n")

"""
Generate a script block that loads the AnythingLLM embed widget inside a sandboxed iframe.

We isolate the widget to avoid clashes with Documenter's bundled `require.js`.
"""
function embed_script(
    cfg::AnythingLLMConfig,
    embed_uuid;
    options::EmbedOptions=EmbedOptions(),
    iframe_style=Dict()
)
    api_base = string(cfg.embed_host, "/api/embed")
    script_src = string(cfg.embed_host, "/embed/anythingllm-chat-widget.min.js")
    attrs = embed_attributes(options)
    iframe_styles = merge(default_iframe_style(), iframe_style)

    style_str = join(["$(k): $(v);" for (k, v) in iframe_styles], " ")
    attr_lines = join([string(k, "=\"", escape_attr(v), "\"") for (k, v) in attrs], "\n      ")

    return """
<script>
// Bad workaround for Documenter + require.js clashing with AnythingLLM.
// Render the widget inside a sandboxed iframe overlay to isolate globals.
(function() {
  const embedId = "$(escape_js(embed_uuid))";
  const apiBase = "$(escape_js(api_base))";
  const src = "$(escape_js(script_src))";

  const injectEmbed = () => {
    if (document.getElementById("anythingllm-embed-frame")) return;

    const iframe = document.createElement("iframe");
    iframe.id = "anythingllm-embed-frame";
    iframe.title = "AnythingLLM chat";
    iframe.style.cssText = "$(escape_js(style_str))";
    iframe.sandbox = "allow-same-origin allow-scripts allow-popups allow-forms allow-modals";
    iframe.loading = "lazy";

    const html = `
<!doctype html>
<html>
  <head>
    <style>
      html, body { margin: 0; padding: 0; overflow: hidden; background: transparent; }
    </style>
  </head>
  <body>
    <script
      data-embed-id="\${embedId}"
      data-base-api-url="\${apiBase}"
      $(attr_lines)
      src="\${src}">
    <\\/script>
  </body>
</html>`;
    iframe.srcdoc = html;
    document.body.appendChild(iframe);
  };

  if (document.readyState === "complete" || document.readyState === "interactive") {
    injectEmbed();
  } else {
    window.addEventListener("DOMContentLoaded", injectEmbed);
  }
})();
</script>
"""
end

"""Create an embed configuration for the workspace and return its UUID."""
function create_embed!(cfg, workspace_slug; allowlist=cfg.allowlist, chat_mode="query")
    body = Dict(
        "workspace_slug" => workspace_slug,
        "chat_mode" => chat_mode,
        "allowlist_domains" => allowlist,
    )
    data = request_json(cfg, "POST", "/embed/new"; body=body)
    embed = get(data, "embed", data)
    uuid = get(embed, "uuid", nothing)
    uuid === nothing && error("Embed creation did not return a UUID")
    return String(uuid)
end

function determine_workspace_title(name, docs_root; repo::Union{Nothing,String}=nothing)
    if repo === nothing
        return string(name, " docs")
    end
    root = realpath(docs_root)
    devbranch = Documenter.git_remote_head_branch("deploydocs(devbranch = ...)", root)
    decision = Documenter.deploy_folder(
        Documenter.auto_detect_deploy_system();
        branch = "gh-pages",
        branch_previews = "gh-pages",
        devbranch = devbranch,
        devurl = "dev",
        push_preview = false,
        repo = repo,
        repo_previews = nothing,
        deploy_repo = nothing,
        tag_prefix = "",
    )
    versions = Any["stable" => "v^", "v#.#", "dev" => "dev"]
    deploy_subfolder = Documenter.determine_deploy_subfolder(decision, versions)
    decision.all_ok || return nothing
    return string(name, " ", deploy_subfolder)
end

"""
Full AnythingLLM integration hook: reset workspace, upload docs and docstrings,
create an embed, and return the head asset to inject into Documenter.
"""
function integrate_anythingllm(
    name,
    modules::Vector{Module},
    docs_root,
    api_base;
    repo::Union{Nothing,String}=nothing,
    options::EmbedOptions=EmbedOptions(),
    iframe_style=Dict(),
    api_key=default_api_key(),
    allowlist="",
    chat_mode="query",
)
    cfg = AnythingLLMConfig(
        api_base,
        api_key,
        allowlist
    )

    force_workspace = get(ENV, "ANYTHINGLLMDOC_FORCE_DEPLOY", "")
    try
        workspace_title = ""
        if isempty(force_workspace)
            workspace_title = determine_workspace_title(name, docs_root; repo=repo)
            if workspace_title === nothing
                @info "Skipping AnythingLLM deployment; deploy conditions not met."
                return RawHTMLHeadContent[]
            end
        else
            workspace_title = force_workspace
        end

        workspace = recreate_workspace!(cfg, workspace_title)
        slug = String(get(workspace, "slug", slugify(workspace_title)))
        locations = String[]
        append!(locations, upload_markdown_sources!(cfg, slug, joinpath(docs_root, "src")))
        append!(locations, upload_docstrings!(cfg, slug, modules))
        move_files_to_folder!(cfg, slug, locations)
        uuid = create_embed!(cfg, slug; allowlist, chat_mode)
        return [RawHTMLHeadContent(embed_script(cfg, uuid; options, iframe_style))]
    catch err
        @warn "AnythingLLM integration failed; docs will build without chat" exception=(err, catch_backtrace())
        return RawHTMLHeadContent[]
    end
end

end # module
