module TestJobs
using Waluigi

Waluigi.@Job begin
    name = NothingJob
    parameters = nothing
    dependencies = nothing
    target = nothing
    process = nothing
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
    target = Waluigi.BinFileTarget(joinpath(Main.test_files, "checkpoint_tester.bin"))
    process = a
end

Waluigi.@Job begin
    name = UsingCustomTarget
    parameters = (tbl, parq_dir)
    dependencies = nothing
    target = Main.ParquetDirTarget(parq_dir; read_kwargs = (use_mmap=false,))
    process = tbl
end

@macroexpand1 Waluigi.@Job begin
    name = TypedParams
    parameters = (a::Int, b::String)
    dependencies = nothing
    target = nothing
    process = nothing
end

end # TestJobs Module
