mutable struct JobNode{T} 
    const id::UInt64
    const parents::Vector{JobNode}
    const job::T
    complete::Bool
    result::Union{Nothing, Dagger.EagerThunk}
    const dependencies::Vector{JobNode}
end

get_id(n::JobNode) = n.id
get_parents(n::JobNode) = n.parents
function has_ancestor(n::JobNode, id)
    for parent in get_parents(n)
        if get_id(parent) == id || has_ancestor(parent, id)
            return true
        end
    end
    return false
end

get_job(n::JobNode) = n.job
is_complete(n::JobNode) = n.complete
get_result(n::JobNode) = n.result
get_dependencies(n::JobNode) = [dep for dep in n.dependencies]
is_ready(n::JobNode) = all(is_complete(dep) for dep in n.dependencies)
is_required(n::JobNode) = n |> get_parents .|> !is_complete |> any


struct JobTree
    nodes::Dict{UInt64, JobNode}
    root::JobNode
end
function JobTree(@nospecialize(job::AbstractJob))
    nodes = Dict{UInt64, JobNode}()
    root = add_job_node!(nodes, job)
    return JobTree(nodes, root)
end

get_node_lookup(jt::JobTree) = jt.nodes
get_root(jt::JobTree) = jt.root

function add_job_node!(@nospecialize(nodes), @nospecialize(job::J), id::T = 0, parent = JobNode[]) where {T, J<:AbstractJob}
    if !(T <: UInt64)
        id = hash(job)
    end
    @debug "adding node for $(typeof(job))"

    if id in keys(nodes)
        @debug "this job was already processed"
        node = nodes[id]
        append!(node.parents, parent)
        return node
    end

    complete = false
    result = nothing
    dependencies = get_dependencies(job)
    dependency_nodes = Vector{JobNode}(undef, length(dependencies))
    node = JobNode{J}(id, parent, job, complete, result, dependency_nodes)
    nodes[id] = node

    for (i,dep) in enumerate(dependencies)
        @debug "adding dep of type $(typeof(job))"
        dep_id = hash(dep)
        if dep_id == id || has_ancestor(node, dep_id)
            throw(InvalidStateException("The dependency tree contains cycles", :Cyclic))
        end
        @inbounds node.dependencies[i] = add_job_node!(nodes, dep, dep_id, [node])
    end

    return node 
end

function set_result!(@nospecialize(job_node::JobNode); ignore_target)
    job_node.result = Dagger.@spawn (get_job(job_node))(
        get_id(job_node), 
        ignore_target, 
        get_result.(get_dependencies(job_node))...
    )
    job_node.complete = true
end

function set_result!(@nospecialize(job_node::JobNode), data, complete = true)
    job_node.result = data
    job_node.complete = complete
end



function schedule_job(@nospecialize(job::JobNode); ignore_target)
    if is_complete(job)
        return nothing
    end

    dep_nodes = get_dependencies(job)
    incomplete_deps = Iterators.filter(!is_complete, dep_nodes)

    for dep in incomplete_deps
        schedule_job(dep; ignore_target)
    end

    set_result!(job; ignore_target)

    for dep in dep_nodes
        if !is_required(dep)
            set_result!(dep, nothing)
        end
    end

    return nothing
end

