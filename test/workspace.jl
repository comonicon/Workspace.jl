using Distributed
using Workspace
using Test
using Configurations
using StructTypes
using JSON

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


s = JSON.json(d)
ins = from_dict(WorkspaceInstance, JSON.parse(s))
table = WorkspaceTable()
current_nproc = nprocs()
add_workspace_process!(table, ins)
eval_in_workspace(table, ins, quote
    println("aaaaa")
end)

@test nprocs() == current_nproc + 1
rm_workspace!(table, ins)
@test nprocs() == current_nproc

f = Distributed.remotecall(2) do ch
end
fetch(f)
