"""JobeNode stores data about a job that is included in a given pipeline run"""
mutable struct JobNode{T}
    # hash of the job
    const id::UInt64
    # jobs that require this job as a dependency
    const parents::Vector{JobNode}
    # The job itself
    const job::T
    # is the job completed
    complete::Bool
    # the resulting object
    # todo: this should be replace with a MemPool.jl StorageDevice down the road for more flexibility
    # in shifting results in and out of memory
    result::Union{Nothing, Dagger.EagerThunk}
    # All dependency nodes for this job
    const dependencies::Vector{JobNode}
end

# JobNode field getters
get_id(n::JobNode) = n.id
get_parents(n::JobNode) = n.parents
"""
has_ancestor(n::JobNode, id)
Checks if a node has a parent with a given id hash (checks all the way up to the root of the job tree)
"""
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


"""JobTree represents the graph of all jobs that are required to generate the job requested by `run_pipeline`"""
struct JobTree
    nodes::Dict{UInt64, JobNode}
    root::JobNode
end
function JobTree(@nospecialize(job::AbstractJob))
    nodes = Dict{UInt64, JobNode}()
    id = hash(job)
    root = add_job_node!(nodes, job, id)
    return JobTree(nodes, root)
end

# jobtree field getters
get_node_lookup(jt::JobTree) = jt.nodes
get_root(jt::JobTree) = jt.root

"""
add_job_node!(nodes, job, id, parent = JobNode[])
Descends through dependencies recursively. Adds all required jobs to the `nodes` dict and then 
returns the root node of the dependency tree.
"""
function add_job_node!(nodes::Dict{UInt64, JobNode}, @nospecialize(job::AbstractJob), id::UInt64, parent = JobNode[])
    job_type = typeof(job)
    @debug "adding node for $job_type"

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
    node = JobNode{job_type}(id, parent, job, complete, result, dependency_nodes)
    nodes[id] = node

    for (i,dep) in pairs(dependencies)
        @debug "adding dep of type $(typeof(job))"
        dep_id = hash(dep)
        # If a dependency is already in the parent chain, then that means there is a cycle in the dependencies
        if dep_id == id || has_ancestor(node, dep_id)
            throw(InvalidStateException("The dependency tree contains cycles", :CyclicDep))
        end
        @inbounds node.dependencies[i] = add_job_node!(nodes, dep, dep_id, [node])
    end
    return node 
end


"""Run a jobs process and set the result. Mark jobnode as complete"""
function set_result!(@nospecialize(job_node::JobNode); ignore_target)
    job_node.result = Dagger.@spawn (get_job(job_node))(
        get_id(job_node), 
        ignore_target, 
        get_result.(get_dependencies(job_node))...
    )
    job_node.complete = true
end

"""Update a job result field with the given data"""
function set_result!(@nospecialize(job_node::JobNode), data, complete = true)
    job_node.result = data
    job_node.complete = complete
end


"""Given a ready node, run the job and do some clean up"""
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

    # Release result objects that are no longer required
    # TODO this should be reimplemented with MemPool.jl StorageDevice because it should be able
    # to handle swapping things dynamically
    for dep in dep_nodes
        if !is_required(dep)
            set_result!(dep, nothing)
        end
    end

    return nothing
end

