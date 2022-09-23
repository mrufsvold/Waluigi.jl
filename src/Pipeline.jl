mutable struct ProcessNode
    const process::AbstractProcess
    const graph_index::Int
    status::ProcessStatus
end

"""
The Pipeline holds all information about tasks and their relationships. It can also
hold arbitrary data in the params field that can be accessed in any process. The easiest
way to hold parameters is in a dictionary, but for performance, it is recommended that
you create a struct or NamedTuple to maintain type stability.
"""
struct Pipeline
    process_graph::SimpleDiGraph{AbstractProcess}
    processes::Dict{NamedTuple, ProcessNode}
    vertex_to_process::Dict{Int, ProcessNode}
    params::Any
end
Pipeline(params) = Pipeline(SimpleDiGraph(),Dict(), Dict(), params)

# Get access to process detail using either its key or its graph index
get_process(pipeline::Pipeline, vert::Int) = pipeline.vertex_to_process[vert]
get_process(pipeline::Pipeline, key::NamedTuple) = pipeline.processes[key]
# Check the status of all processes
get_statuses(pipeline) = [get_process(pipeline, i).status for i in 1:nv(pipeline.process_graph)]
get_statuses(pipeline, ids) = [get_process(pipeline, i).status for i in ids]

# Build a new process node and add it to the pipeline
function add_process!(pipeline, process)
    add_vertex!(pipeline.process_graph)
    status = is_complete(process) ? Complete : Blocked
    node = ProcessNode(process, length(pipeline.process_graph), status)
    process_key = get_process_name(process)
    pipeline.processes[process_key] = node
    pipeline.vertex_to_process[node.graph_index] = node
    return process_key
end

# TODO Need to find a way to pass params to requirements
function add_requirements!(pipeline::Pipeline, proc_node)
    proc_index = proc_node.graph_index
    proc = proc_node.process
    reqs = get_requirements(proc)
    if ! reqs isa NoRequirements
        for req in reqs
            req_proc = req()
            # TODO Check to see if this req is already in the graph
            req_key = add_process!(pipeline, req_proc)
            req_index = pipeline.processes[req_key].graph_index
            add_edge!(pipeline.process_graph, proc_index, req_index)
            if ! is_complete(req_proc)
                add_requirements!(pipeline, req_index)
            end
        end
    end
    if is_complete(reqs)
        pipeline.processes[proc_key].status = Ready
    end
    return nothing
end

function run_process!(proc_node)
    run(proc_node.process)
    proc_node.status = is_complete(get_output(proc_node.process)) ? Complete : Failed
    return proc_node.status
end


function run_process!(pipeline, process_index = 1)
    proc_node = get_process(pipeline, process_index)
    add_requirements!(pipeline, proc_node)

    if proc_node.status == Blocked
        req_indices = outneighbors(pipeline.process_graph, proc_node.graph_index)
        Threads.@threads for i in req_indices
            run_process!(pipeline, i)
        end
        req_status = get_statuses(pipeline, req_indices)
        if all(.==(Ref(Complete), req_status))
            proc_node.status = Ready
        elseif any(.==(Ref(Failed), req_status))
            proc_node.status = Failed
            proc_node.status_reason = "Prerequisit failed."
        end
    end

    if proc_node.status == Ready
        try
            proc_node.status = Running
            run(proc_node.process)
        catch e
            proc_node.status == Failed
            proc_node.status_reason = "We got an error of $e when handling the following process.\n$(get_process_name(proc_node.process))"
            println(proc_node.status_reason)
        end
    end
    return nothing
end
