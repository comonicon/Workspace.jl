# copied from Pluto, should split this out
# at some point?
@option mutable struct CompilerOptions
    compile::Union{Nothing,String} = nothing
    sysimage::Union{Nothing,String} = nothing
    banner::Union{Nothing,String} = nothing
    optimize::Union{Nothing,Int} = nothing
    math_mode::Union{Nothing,String} = nothing

    # notebook specified options
    # the followings are different from
    # the default julia compiler options

    # we use nothing to represent "@v#.#"
    # unlike Pluto, we use parsed content of the Project.toml here
    # so that we can transfer the TOML file through sockets.
    project::Dict{String, Any} = TOML.parsefile(Base.load_path_expand("@."))
    # we don't load startup file in notebook
    startup_file::Union{Nothing,String} = "no"
    # we don't load history file in notebook
    history_file::Union{Nothing,String} = "no"

    threads::Union{Nothing,String,Int} = get_nthreads()
end

function _convert_to_exeflags(options::CompilerOptions)::Vector{String}
    option_list = String[]

    workspace_deps = Dict{String, Any}(
        "Suppressor" => "fd094767-a336-5f1f-9728-57cf17d0bbfb"
    )

    for name in fieldnames(CompilerOptions)
        name === :project && continue # skip project
        flagname = string("--", replace(String(name), "_" => "-"))
        value = getfield(options, name)
        if value !== nothing
            if !(VERSION <= v"1.5.0-" && name === :threads)
                push!(option_list, string(flagname, "=", value))
            end
        end
    end

    # handle in memory project
    # only deps and compat matters for workspace
    temp_project_dir = mktempdir(;prefix="workspace_")
    temp_project = joinpath(temp_project_dir, "Project.toml")
    open(temp_project, "w+") do io
        deps = get(options.project, "deps", Dict{String, Any}())
        compat = get(options.project, "compat", Dict{String, Any}())

        merge!(deps, workspace_deps)
        TOML.print(io, Dict("deps"=>deps, "compat"=>compat);
        sorted=true, by=key -> (Pkg.Types.project_key_order(key), key))
    end

    push!(option_list, "--project=$temp_project")
    return option_list
end

@option struct DistributedOptions
    dir::String = pwd()
    enable_threaded_blas::Bool = false
    exename::String = joinpath(Sys.BINDIR, "julia")
    topology::Symbol = :all_to_all
    lazy::Bool = true
end

function addprocs_flags(options::DistributedOptions)
    kw_list = []
    for name in fieldnames(DistributedOptions)
        value = getfield(options, name)
        isnothing(value) && continue
        push!(kw_list, name => value)
    end
    return kw_list
end

@option struct WorkspaceInstance
    name::Symbol = gensym(:workspace)
    uuid::UUID = uuid1()
    compiler::CompilerOptions = CompilerOptions()
    distributed::DistributedOptions = DistributedOptions()
    # scripts that is evaluated in this workspace instance
    linked_scripts::Vector{String} = String[]
end

StructTypes.StructType(::Type{WorkspaceInstance}) = StructTypes.Struct()

function Configurations.convert_to_option(::Type{WorkspaceInstance}, ::Type{Symbol}, x::String)
    return Symbol(x)
end

function Configurations.convert_to_option(::Type{WorkspaceInstance}, ::Type{UUID}, x::String)
    return UUID(x)
end

struct WorkspaceTable
    workspaces::Dict{UUID, WorkspaceInstance}
    process::Dict{UUID, Int}
end

WorkspaceTable() = WorkspaceTable(Dict{UUID, WorkspaceInstance}(), Dict{UUID, Int}())

function get_nthreads()
    haskey(ENV, "JULIA_NUM_THREADS") || return
    isempty(ENV["JULIA_NUM_THREADS"]) && return
    return parse(Int, ENV["JULIA_NUM_THREADS"])
end

function add_workspace_process!(table::WorkspaceTable, ins::WorkspaceInstance)
    pid = addprocs(1;addprocs_flags(ins.distributed)..., exeflags=_convert_to_exeflags(ins.compiler))[]

    # init workspace project env
    Distributed.remotecall_eval(Main, [pid], quote
        using Pkg; Pkg.instantiate()
    end)
    # create the workspace module
    Distributed.remotecall_eval(Main, [pid], Expr(:toplevel, :(module $(ins.name) end)))
    Distributed.remotecall_eval(Main, [pid], Expr(:toplevel, :(using Suppressor)))
    table.workspaces[ins.uuid] = ins
    table.process[ins.uuid] = pid
    return table
end

rm_workspace!(table::WorkspaceTable, ins::WorkspaceInstance) = rm_workspace!(table, ins.uuid)

function rm_workspace!(table::WorkspaceTable, uuid::UUID)
    haskey(table.workspaces, uuid) || error("cannot find workspace: $uuid")
    wait(rmprocs(table.process[uuid]; waitfor=5))
    delete!(table.workspaces, uuid)
    delete!(table.process, uuid)
    return table
end

function eval_in_workspace(table::WorkspaceTable, ins::WorkspaceInstance, expr)
    haskey(table.process, ins.uuid) || error("workspace process is not spawned, call add_workspace_process")
    pid = table.process[ins.uuid]
    Distributed.remotecall_fetch(Core.eval, pid, Main, quote
        Suppressor.@capture_out begin
            Core.eval($(ins.name), $(QuoteNode(expr)))
        end
    end)
end
