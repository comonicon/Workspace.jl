using Configurations
using JSON
using HTTP
using HTTP.Sockets
using Workspace
s = Workspace.Session()
router = Workspace.make_router(s)
HTTP.serve(router, Sockets.localhost, 8081)

d = Dict(
    "name" => "test_workspace",
    "uuid" => "94f78cb8-c85a-11eb-0dc6-f7f6bd9facf1",
    "compiler" => Dict(
        "project" => Dict(
            "deps" => Dict(
                "JSON" => "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
            ),
            "compat" => Dict(
                "JSON" => "0.20.0",
            )
        )
    )
)

HTTP.open("POST", "http://127.0.0.1:8081/api/v1/workspace") do io
    write(io, JSON.json(d))
end

HTTP.open("GET", "http://127.0.0.1:8081/api/v1/workspace") do io
    println(JSON.json(Dict("uuid" => "94f78cb8-c85a-11eb-0dc6-f7f6bd9facf1")))
    write(io, JSON.json(Dict("uuid" => "94f78cb8-c85a-11eb-0dc6-f7f6bd9facf1")))
end

response = HTTP.get("http://127.0.0.1:8081/api/v1/workspace"; body=JSON.json(Dict("uuid" => "94f78cb8-c85a-11eb-0dc6-f7f6bd9facf1")))
d = JSON.parse(IOBuffer(HTTP.payload(response)))
from_dict(WorkspaceInstance, )