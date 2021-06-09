@option struct Session
    host::String = "127.0.0.1"
    port::Maybe{Int} = nothing
    secret::String = randstring(('a':'z') ∪ ('A':'Z') ∪ ('0':'9'), 8)
    workspace_table::WorkspaceTable = WorkspaceTable()
end

# REST
function make_router(s::Session)
    router = HTTP.Router()

    function create_workspace(req::HTTP.Request)
        d = JSON.parse(IOBuffer(HTTP.payload(req)))
        ins = from_dict(WorkspaceInstance, d)
        add_workspace_process!(s.workspace_table, ins)
        response = Dict(
            "uuid" => string(ins.uuid),
        )
        return HTTP.Response(200, JSON.json(response))
    end

    function get_workspace(req::HTTP.Request)
        println(HTTP.payload(req))
        d = JSON.parse(IOBuffer(HTTP.payload(req)))
        haskey(d, "uuid") || @error "cannot find field uuid"
        ins = s.workspace_table.workspaces[UUID(d["uuid"])]
        d = to_dict(ins; include_defaults=true, exclude_nothing=true)
        return HTTP.Response(200, JSON.json(d))
    end

    function eval_program(req::HTTP.Request)
        d = JSON.parse(IOBuffer(HTTP.payload(req)))
        haskey(d, "workspace") || @error "missing workspace"
        workspace = s.workspace_table.workspaces[UUID(d["workspace"])]
        if haskey(d, "args")
            eval_in_workspace(s.workspace_table, workspace, quote
                empty!(ARGS); append!(ARGS, $(d["args"]))
            end)
        end

        if haskey(d, "file") # local file
            eval_in_workspace(s.workspace_table, workspace, quote
                include($(d["file"]))
            end)
        elseif haskey(d, "script") # some remote script
            eval_in_workspace(s.workspace_table, workspace, Meta.parse(d["script"]))
        else
            @error "expect field 'file' or 'script'."
        end
        return HTTP.Response(200)
    end
    
    function delete_workspace(req::HTTP.Request)
        d = JSON.parse(IOBuffer(HTTP.payload(req)))
        haskey(d, "uuid") || @error "cannot find field uuid"
        rm_workspace!(s.workspace_table, UUID(d["uuid"]))
        return HTTP.Response(200)
    end

    HTTP.@register(router, "POST", "api/v1/workspace/", create_workspace)
    HTTP.@register(router, "GET", "api/v1/workspace/", get_workspace)
    HTTP.@register(router, "PUT", "api/v1/workspace/", eval_program)
    HTTP.@register(router, "DELETE", "api/v1/workspace/", delete_workspace)
    return router
end

function serve(sess::Session)
    host_ip, port, serversocket = listen(sess)
    shutdown_server = Ref{Function}(() -> ())

    servertask = @async HTTP.serve(host_ip, UInt16(port), stream=true, server=serversocket) do http::HTTP.Stream
        request::HTTP.Request = http.message
        request.body = read(http)
        HTTP.closeread(http)

        params = HTTP.queryparams(HTTP.URI(request.target))
        if haskey(params, "token") && session.binder_token === nothing 
            session.binder_token = params["token"]
        end

        response_body = HTTP.handle(pluto_router, request)

        request.response::HTTP.Response = response_body
        request.response.request = request

        try
            HTTP.setheader(http, "Referrer-Policy" => "origin-when-cross-origin")
            HTTP.startwrite(http)
            write(http, request.response.body)
            HTTP.closewrite(http)
        catch e
            if isa(e, Base.IOError) || isa(e, ArgumentError)
                # @warn "Attempted to write to a closed stream at $(request.target)"
            else
                rethrow(e)
            end
        end
    end
end

function listen(s::Session)
    host = s.host
    port = s.port
    host_ip = parse(Sockets.IPAddr, host)

    if port === nothing
        port, serversocket = Sockets.listenany(host_ip, UInt16(1234))
    else
        try
            serversocket = Sockets.listen(host_ip, UInt16(port))
        catch _
            @error "Port with number $port is already in use. Use serve() to automatically select an available port."
            return
        end
    end
    return host_ip, port, serversocket
end

"""
Return whether the `request` was authenticated in one of two ways:
1. the session's `secret` was included in the URL as a search parameter, or
2. the session's `secret` was included in a cookie.
"""
function is_authenticated(session::Session, request::HTTP.Request)
    try
        uri = HTTP.URI(request.target)
        query = HTTP.queryparams(uri)
        return get(query, "secret", "") == session.secret
    catch e
        @warn "Failed to authenticate request using URL" exception = (e, catch_backtrace())
        return false
    end || try
        cookies = HTTP.cookies(request)
        return any(cookies) do cookie
            cookie.name == "secret" && cookie.value == session.secret
        end
    catch e
        @warn "Failed to authenticate request using cookies" exception = (e, catch_backtrace())
        return false
    end
end
