module TestJobs

import ..Waluigi

Waluigi.@Job begin
    name = NothingJob
    parameters = nothing
    dependencies = nothing
    target = nothing
    process = nothing
end

Waluigi.@Job begin
    name = OopsAllOmited
end

Waluigi.@Job begin
    name = DepJob
    parameters = (a,b)
    dependencies = nothing
    target = nothing
    process = begin
        return a + b
    end
end

Waluigi.@Job begin
    name = MainJob
    parameters = nothing
    dependencies = [DepJob(2,4)]
    target = nothing
    process = begin
        sum_dep = get_result(dependencies[1])
        return sum_dep + 1
    end
end

Waluigi.@Job begin
    name = BadDeps
    parameters = nothing
    dependencies = (a = DepJob(2,4),)
    target = nothing
    process = nothing
end

Waluigi.@Job begin
    name = BadTarget
    parameters = nothing
    dependencies = nothing
    target = 42
    process = nothing
end

Waluigi.@Job begin
    name = CheckPointTester
    parameters = (a,)
    dependencies = nothing
    target = Waluigi.BinFileTarget{typeof(a)}(joinpath(Main.test_files, "checkpoint_tester.bin"))
    process = a
end

Waluigi.@Job begin
    name = UsingCustomTarget
    parameters = (tbl, parq_dir)
    dependencies = nothing
    target = Main.ParquetDirTarget(parq_dir; read_kwargs = (use_mmap=false,))
    process = tbl
end

Waluigi.@Job begin
    name = TypedParams
    parameters = (a::Int, b::String)
    dependencies = nothing
    target = nothing
    process = nothing
end

Waluigi.@Job begin
    name = UsingTypedParams
    parameters = (a::Int, b::String)
    dependencies = nothing
    target = Waluigi.BinFileTarget{Int}(joinpath(Main.test_files, "typed_checkpoint.bin"))
    process = begin
        s = a + 100
        return s
    end
end

Waluigi.@Job begin
    name = CycleDepA
    dependencies = CycleDepB()
end

Waluigi.@Job begin
    name = CycleDepB
    dependencies = CycleDepA()
end

Waluigi.@Job begin
    name = ReturnDepTypeNotInstance
    dependencies = DepJob
end

end # TestJobs Module
