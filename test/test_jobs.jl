module TestJobs
using Waluigi

@Job begin
    name = NothingJob
    parameters = nothing
    dependencies = nothing
    target = nothing
    process = nothing
end

@Job begin
    name = OopsAllOmited
end

@Job begin
    name = DepJob
    parameters = (a,b)
    dependencies = nothing
    target = nothing
    process = begin
        return a + b
    end
end

@Job begin
    name = MainJob
    parameters = nothing
    dependencies = [DepJob(2,4)]
    target = nothing
    process = begin
        sum_dep = get_result(dependencies[1])
        return sum_dep + 1
    end
end

@Job begin
    name = BadDeps
    parameters = nothing
    dependencies = (a = DepJob(2,4),)
    target = nothing
    process = nothing
end

@Job begin
    name = BadTarget
    parameters = nothing
    dependencies = nothing
    target = 42
    process = nothing
end

@Job begin
    name = CheckPointTester
    parameters = (a,)
    dependencies = nothing
    target = Waluigi.BinFileTarget{typeof(a)}(joinpath(Main.test_files, "checkpoint_tester.bin"))
    process = a
end

@Job begin
    name = UsingCustomTarget
    parameters = (tbl, parq_dir)
    dependencies = nothing
    target = Main.ParquetDirTarget(parq_dir; read_kwargs = (use_mmap=false,))
    process = tbl
end

@Job begin
    name = TypedParams
    parameters = (a::Int, b::String)
    dependencies = nothing
    target = nothing
    process = nothing
end

@Job begin
    name = UsingTypedParams
    parameters = (a::Int, b::String)
    dependencies = nothing
    target = Waluigi.BinFileTarget{Int}(joinpath(Main.test_files, "typed_checkpoint.bin"))
    process = begin
        s = a + 100
        return s
    end
end

end # TestJobs Module
