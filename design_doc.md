# Vision
Waliugi should provide a seemless interface for constructing data pipelines. Users just need 
to define an task that has three parts:
* a list of tasks on which the current task depends 
* a target which holds the resulting data. Can be a local file, a database table, etc
* process function that providest the steps for creating the data

The workflow should be

Defining a list of tasks, calling `run()` on the final task, and then Waliuigi will
spawn all the dependent tasks required. If a task is already done, then it will read the target
and return that data. `run()` will return a Result object which contains references to the 
results of the depenencies, the target, and the data created by the task.

We will lean on Dagger.jl for the backend infrastructure which schedules tasks, mantains the
graph of dependencies, and provides visualizations of the processes. 

Some brainstroming code:

## Fundamental Types

```julia
# This is the internal Task structure
# TODO save the file and line number for the task definition so we can give clear debugging information
struct Task
    parameters::Tuple{Symbol}
    parameter_types::Tuple{Type}
    dependencies::Function
    target::Function
    process::Function
end

function make_anon_function_expr(f; args = (), kwargs = nothing)
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

function assure_result_is_array(func_block)
    return Expr(
        :block,
        Expr(Symbol("="), :t, Expr(:block, func_block)),
        :(if !(t isa AbstractArray)
            return [t]
        end
        ),
        Expr(:return, :t)
    )
end

function separate_type_annotations(args_expr)
    arg_part_generator = (
        arg isa Symbol ?
            (arg, Any) :
            (arg.args[1], eval(arg.args[2]))
        for arg in args_expr.args)
    return (Tuple(arg[1] for arg in arg_part_generator), Tuple(arg[2] for arg in arg_part_generator))
end

macro Task(task_description)
    task_features = Dict{Symbol, Union{Symbol, Expr}}()
    for element in task_description.args
        if element isa LineNumberNode
            continue
        end
        @assert element.head == Symbol("=") "No `=` operator found in task description for $element"
        task_features[element.args[1]] = element.args[2]
    end

    for feature in (:dependencies, :target, :process)
        if !(feature in keys(task_features))
            task_features[feature] = Expr(:block, :nothing)
        end
    end

    if !(:parameters in keys(task_features))
        task_features[:parameters] = :(())
    end
        
    (param_list, param_type_list) = separate_type_annotations(task_features[:parameters])
    dependency_func = assure_result_is_array(task_features[:dependencies])
    task_definition = Expr(
        :call, 
        :Task,
        :($param_list),
        :($param_type_list),
        make_anon_function_expr(dependency_func; kwargs = param_list),
        make_anon_function_expr(task_features[:target]; kwargs = param_list),
        make_anon_function_expr(task_features[:process]; args = (:dependencies, :target), kwargs = param_list)
    )
    return esc(task_definition)
end

# Struct for passing results of tasks through the graph
Base.@kwdef mutable struct Result
    parameters
    dependencies
    target
    promise
    collected = false
    data = missing
end

function Base.collect(r::Result)
    if !r.collected
        r.data = collect(r.promise)
        r.collected = true
    end
    return r.data
end
dependencies(r::Result) = r.dependencies

```

## Running a task
```julia
# Each instance of Task is collable. It will use unique paramters to make new data 
function (task::Task)(ignore_target = false, parameters...)
    needed_parameters = Dict(k => v for (k, v) in parameters if k in task.parameters)

    dep_tasks = task.dependencies(needed_parameters...)
    dependencies = if dep_tasks isa Nothing 
        nothing 
    else
        # TODO deps will be hard to find upstream if they're in a list like this
        # It would be helpful to names in a NamedTuple or Dict. But it's tough to imagine how to 
        # Create a name 
        dependencies = Vector{Dagger.EagerThunk}(undef, length(dep_tasks))
        for (i, dep_task) in enumerate(dep_tasks)
            dependencies[i] = dep_task(;ignore_target=ignore_target, needed_parameters...) 
        end
        dependencies
    end

    target = task.target(needed_parameters...)
    if iscomplete(target)
        data = read(target)
        return Result(dependencies, target, data)
    end

    promise = Dagger.@spawn task.process(dependencies, target; needed_parameters...)

    return Result(needed_parameters, dependencies, target, promise)
end
```

## Example Usage
```julia
@macroexpand1 GetRawSnfTable = @Task begin
    # Paramters are the input values for the task and it's dependencies
    parameters = (snf_path::String, month::Date)
    dependencies = nothing
    target = FileTarget(joinpath(snf_path, "raw_tables", "$month.csv"))
    # The process function
    process = begin
        tbl = request("www.snf_stuff.com/$month")
        write(target, table)
    end
end

# Macro transforms this into:
GetRawSnfTable = Task(
    (:snf_path, :month),
    (String, Date),
    (;snf_path, month) -> nothing,
    (;snf_path, month) -> FileTarget(joinpath(snf_path, "raw_tables", "$month.csv")),
    (dependencies, target; snf_path, month) -> begin
        tbl = request("www.snf_stuff.com/$month")
        write(target, table)
    end
)


# Another task example that depends on the last one
GetAllSnfTables = @Task begin
    parameters = (start_month::Date, end_month::Date, snf_path::String)
    # Notice that we can programatically specify multiple dependencies
    dependencies = [GetRawSnfTable(snf_path, month) for month in start_month:end_month]
    target = nothing
    process = nothing
end

StackSnfTables = @Task begin 
    parameters = (start_month::Date,)
    dependencies = GetAllSnfTables(start_month, end_month,)
    target = FileTarget(joinpath(snf_path, "stacked_table", "$(start_month)_through_$(end_month).csv"))
    process = begin
        vcat(
            # notice that we need to fetch the data of a dependency before it can be used.
            (collect(dep) for dep in dependencies)...
        )
    end
end


```


## Target Vision
A target needs three things to work.
* A place to store the result
* A way to write to that place
* a way to read from that place

The simplest way to do this is a local bin file that serializes the result to and from
Julia
```julia
struct LocalSerialFile 
    fp
end
write(t::LocalSerialFile, data) = write(t.fp, data)
read(t::LocalSerialFile) = read(t.fp)


target = LocalSerialFile("path/to/serialized.bin")

x = 5 # result of task

write(target, x)
y = read(target)
```

It would be great to have targets for Tables
```julia
using CSV
using DataFrames
struct CsvTableTarget{T}
    fp
    sink::T
end

write(t::CsvTableTarget{T}, df::T) where T = CSV.write(t.fp, df)
read(t::CsvTableTarget) = CSV.read(t.fp, t.sink)

target = CsvTableTarget("path/to/file.csv", DataFrame)
df = DataFrame(a=[1,2], b=[3,4])
write(target, df)
df2 = read(target)
```

Custom Target
```julia
struct Target
    location
    config
    write_function
    read_function
end
write(t::Target, data) = t.write_function(data)
read(t::Target) = t.read_function()

function LocalSerialFile(fp)
    Target(
        fp,
        nothing,
        (data) -> write(fp, data),
        () -> read(fp)
    )
end

function CsvTableTarget(fp, sink)
    Target(
        fp,
        nothing,
        (data) -> CSV.write(fp, data),
        () -> CSV.read(fp, sink)
    )
end



```
