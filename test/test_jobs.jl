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
    name = CheckPointTester
    parameters = (a,)
    dependencies = nothing
    target = Waluigi.BinFileTarget(joinpath(Main.test_files, "checkpoint_tester.bin"))
    process = a
end

end # TestJobs Module
