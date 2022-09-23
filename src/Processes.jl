"""
An AbstractProcess is the basic building block of the Waluigi Pipeline. A process has three
essential parts:
    1. Requirements: Processes on which the current process depends for input. If not included
    then the pipeline will assume there are no requirements.
    2. Output: The target(s) to be created by the process
    3. run(): A function that dispatches on the process type and executes the logic to create output

To construct your own process, use the @process macro in front of a struct definition like so:
```
@process struct ExampleProcess
    requires = PrereqProcess
    output = FileTarget("path/to/output.csv")
end
```
Then define a run function for this type.
```
function run(proc::ExampleProcess)
    open(proc.output.fp) do f
        write(f, "Output data to write to the file")
    end
end
```
"""
abstract type AbstractProcess end
@enum ProcessStatus Blocked Ready Complete Running Failed

macro process(base_struct) 
    @assert base_struct.head == :struct "Process definition must be a struct"
    component_name = base_struct.args[2]
    @assert typeof(component_name) == Symbol "Component definition should not be subtyped"
    base_struct.args[2] = Expr(Symbol("<:"), component_name, :AbstractProcess)

    # Get list of field names
    needed_fields = [
        (name = :params, default = nothing), 
        (name = :output, default = []), 
        (name = :requires, default = [])
        ]
    fields = [field.args[1] for field in base_struct.args[3].args if typeof(field) == Expr]

    for field in needed_fields
        if ! (field.name in fields)
            push!(base_struct.args[3].args, Expr(Symbol("="), field.name, field.default))
        end
    end

    finalexpr = Expr(
        :macrocall,
        Expr(Symbol("."), :Base, QuoteNode(Symbol("@kwdef"))),
        base_struct.args[1],
        base_struct
    )

    dump(finalexpr)
    return finalexpr
end

get_process_name(proc::AbstractProcess) = (name=typeof(proc), params=proc.params)
# Define functions for checking if a process, req, or output is complete
get_output(proc::AbstractProcess) = proc.output
struct NoRequirements end
function get_requirements(proc::AbstractProcess)
    if proc.requires == []
        return NoRequirements()
    end
    return proc.requires isa Array ? proc.requires : [proc.requires]
end
is_complete(::NoRequirements) = true
is_complete(target_arr::Array{AbstractTarget}) = all(is_complete.(target_arr))
is_complete(proc::AbstractProcess) = is_complete(get_output(proc))
is_complete(procs::Array{AbstractProcess}) = all(is_complete.(procs))
