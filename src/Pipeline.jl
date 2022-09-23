mutable struct ProcessNode
    const process::AbstractProcess
    const graph_index::Int
    status::ProcessStatus
end
struct Pipeline
    process_graph::SimpleDiGraph
    processes::Dict{NamedTuple, ProcessNode}
    vertex_to_process::Dict{Int, ProcessNode}
    params
end
Pipeline(params) = Pipeline(SimpleDiGraph{AbstractProcess}(), [], params)

get_process(pipeline::Pipeline, vert::Int) = pipeline.vertex_to_process[vert]
get_process(pipeline::Pipeline, key::NamedTuple) = pipeline.processes[key]

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
function add_requirements!(pipeline::Pipeline, proc_key)
    proc_node = pipeline.processes[proc_key]
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

function run_processes!(pipeline, proc_i)
    proc_node = get_process(pipeline, proc_i)

    if proc_node.status == Ready
        run_process!(proc_node)
    elseif proc_node.status == Blocked
        req_results = [
            run_processes!(pipeline, req_i) for req_i in outneighbors(pipeline.process_graph, proc_node.graph_index)
        ]
        if all(.==(Ref(Complete), req_results))
            run_process!(proc_node)
        elseif any(.==(Ref(Failed), req_results))
            proc_node.status = Failed
        end
    end
    return proc_node.status
end
