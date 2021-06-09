module Workspace

using Pkg
using HTTP
using TOML
using JSON
using UUIDs
using Random
using MLStyle
using Distributed
using StructTypes
using Configurations

export WorkspaceTable, WorkspaceInstance,
    add_workspace_process!,
    eval_in_workspace,
    rm_workspace!

include("workspace.jl")
include("server.jl")

end
