# This is the internal Job structure
# TODO save the file and line number for the job definition so we can give clear debugging information
abstract type AbstractJob end

get_dependencies() = nothing
get_target() = nothing
run_process(job, dependencies, target) = nothing

Base.@kwdef mutable struct Result
    dependencies
    target
    data
end

get_dependencies(r::Result) = r.dependencies


"""
    @Job(job_description)

Constructs a new job based on a description. 

## Description Format
```juila
MyNewJob = @Job begin
    # Paramters are the input values for the job 
    parameters = (param1::String, param2::Int, param)
    
    # Dependencies list jobs that should be inputs to this job (Optional)
    # They can be created programmatically using parameters
    dependencies = [[SomeJob(i) for i in 1:param2]; AnotherJob("input")]
    
    # Target is an output location to cache the result. If the target exists, the job will
    # be skipped and the cached result will be returned (Optional).
    target = FileTarget(joinpath(snf_path, "raw_tables", "\$month.csv"))
    
    # The process function will be executed when the job is called.
    # All parameters, `dependencies`, and `target` are defined in this scope.
    process = begin
        dep1_data = dependencies[1]
        x = do_logic(dep1_data, param1)
        write(target, x)
        return x
    end
end
```
"""
macro Job(job_description)
    job_features = extract_job_features(job_description)
    
    job_name = job_features[:name]

    raw_parameters = job_features[:parameters]
    parameter_list = raw_parameters isa Symbol ? (raw_parameters,) : raw_parameters.args
    parameter_names = [arg isa Symbol ? arg : arg.args[1] for arg in parameter_list]

    dependency_func = add_get_dep_return_type_protection(job_features[:dependencies])

    dependency_ex = unpack_input_function(:get_dependencies, job_name, parameter_names, dependency_func)
    target_ex = unpack_input_function(:get_target, job_name, parameter_names, job_features[:target])
    process_ex = unpack_input_function(:run_process, job_name, parameter_names, job_features[:process], (:dependencies, :target))

    struct_def = :(struct $job_name <: AbstractJob end)
    push!(struct_def.args[3].args, parameter_list...)

    return quote
        $struct_def
        eval($(esc(dependency_ex)))
        eval($(esc(target_ex)))
        eval($(esc(process_ex)))
    end
end


function extract_job_features(job_description)
    job_features = Dict{Symbol,Union{Symbol,Expr}}()
    for element in job_description.args
        if element isa LineNumberNode
            continue
        end
        @assert element.head == Symbol("=") "No `=` operator found in job description for $element"
        job_features[element.args[1]] = element.args[2]
    end

    for feature in (:dependencies, :target, :process)
        if !(feature in keys(job_features))
            job_features[feature] = Expr(:block, :nothing)
        end
    end

    if !(:parameters in keys(job_features)) || job_features[:parameters] == :nothing
        job_features[:parameters] = :(())
    end

    return job_features
end


function make_anon_function_expr(f; args=(), kwargs=nothing)
    sym_args = Any[Symbol(p) for p in args]
    if !(kwargs isa Nothing)
        pushfirst!(sym_args, Expr(:parameters, (Symbol(k) for k in kwargs)...))
    end
    return Expr(
        Symbol("->"),
        Expr(
            :tuple,
            sym_args...
        ),
        f
    )
end

function unpack_input_function(function_name, job_name, parameter_names, function_body, additional_inputs=())
    quote
        function Waluigi.$function_name(job::$job_name, $(additional_inputs...))
            let $((:($name = job.$name) for name in parameter_names)...)
                $function_body
            end
        end
    end
end



function add_get_dep_return_type_protection(func_block)
    return quote
        t = begin
            $func_block
        end
        if t isa Nothing
            return []
        elseif !(t isa Union{Base.Generator,AbstractArray})
            return [t]
        end
        return t
    end
end


function execute(job::AbstractJob, ignore_target=false)
    dep_jobs = get_dependencies(job)
    
    # TODO deps will be hard to find upstream if they're in a list like this
    # It would be helpful to names in a NamedTuple or Dict. But it's tough to imagine how to 
    # Create a name 
    dependencies = Vector(undef, length(dep_jobs))
    for (i, dep_job) in enumerate(dep_jobs)
        dependencies[i] = execute(dep_job, ignore_target)
    end
    dependencies

    target = get_target(job)
    if !(target isa Nothing) && iscomplete(target)
        data = read(target)
        return Result(dependencies, target, data)
    end

    data = run_process(job, dependencies, target)

    return Result(dependencies, target, data)
end
