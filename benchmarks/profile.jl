# profile.jl -- host/device attribution for one solve, and the allocation share of
# the hottest line ("Profiling and allocation" in the manuscript).
#
# Replaces the one-off profiler sessions that previously backed those numbers, so
# they can be re-taken on whichever machine the rest of the suite runs on.
#
# Protocol: 128power chimera instance (4x4x8), Zipper/Dense, SquareSingleNode,
# bond 32, beta = 3, max_states = 128, one lattice transformation -- the same solve
# crossover.jl times, so the two are directly comparable.
#
# Phase 1 (needs a functional GPU): CUDA.@profile trace=true around the solve.
#   gpu_busy_s   union of device-activity intervals (kernels, memcpy, memset)
#   host_api_s   union of host-side CUDA API call intervals
#   These are interval unions, not sums, so concurrent activity is not
#   double-counted. batching_cap = wall / (wall - host_api_s) is the ceiling on
#   what removing ALL CUDA API time could buy.
# Phase 2 (host-side, device-independent): Profile.Allocs at 2% sampling over the
#   same solve; reports the share of sampled allocated bytes attributable to the
#   hottest single line. Allocated bytes do not depend on the host or device model,
#   the same argument the allocation figure rests on.
#
# ENV: SPINS=128|2048  BOND=Int  SPARSITY=dense|sparse  DEVICE=cpu|gpu
#      SEED=Int  RATE=Float (Allocs sample rate)  OUT=path  PKG=checkout
# Usage: julia --project=$PKG profile.jl
using SpinGlassPEPS
using SpinGlassPEPS.SpinGlassEngine: no_merge
import CUDA
using Random, Printf, Profile

const SPINS    = parse(Int, get(ENV, "SPINS", "128"))
const BOND     = parse(Int, get(ENV, "BOND", "32"))
const SPARSITY = get(ENV, "SPARSITY", "dense")
const DEVICE   = get(ENV, "DEVICE", "gpu")
const SEED     = parse(Int, get(ENV, "SEED", "1"))
const RATE     = parse(Float64, get(ENV, "RATE", "0.02"))
const OUT      = get(ENV, "OUT", "profile.csv")
const PKG      = get(ENV, "PKG", normpath(joinpath(@__DIR__, "..", "..", "SpinGlassPEPS.jl")))

const onGPU = DEVICE == "gpu"
onGPU && !CUDA.functional() && error("DEVICE=gpu but CUDA is not functional here")

const INSTS = Dict(
    128  => (joinpath(PKG, "test", "engine", "instances", "chimera_droplets", "128power", "001.txt"), (4, 4, 8)),
    2048 => (joinpath(PKG, "test", "engine", "instances", "chimera_droplets", "2048power", "001.txt"), (16, 16, 8)),
)
const inst, (m, n, t) = INSTS[SPINS]
const Sp = SPARSITY == "sparse" ? Sparse : Dense
const ph = potts_hamiltonian(ising_graph(inst); spectrum = full_spectrum,
    cluster_assignment_rule = super_square_lattice((m, n, t)))

function one_solve()
    net = PEPSNetwork{SquareSingleNode{GaugesEnergy},Sp,Float64}(m, n, ph, rotation(0))
    ctr = MpsContractor(Zipper, net,
        MpsParameters{Float64}(; bond_dim = BOND, var_tol = 1e-8, num_sweeps = 4, tol_SVD = 1e-16);
        onGPU = onGPU, beta = 3.0, graduate_truncation = true)
    res = low_energy_spectrum(ctr,
        SearchParameters(; max_states = 128, cutoff_prob = 0.0), no_merge; show_progress = false)
    e = first(first(res).energies)
    clear_memoize_cache()
    e
end

# Total length covered by a set of [start, stop) intervals, counting overlap once.
function union_span(starts, stops)
    isempty(starts) && return 0.0
    iv = sort!(collect(zip(starts, stops)); by = first)
    total = 0.0; cs, ce = iv[1]
    for (s, e) in iv[2:end]
        if s > ce
            total += ce - cs; cs, ce = s, e
        else
            ce = max(ce, e)
        end
    end
    total + (ce - cs)
end

Random.seed!(SEED); onGPU && CUDA.seed!(SEED)
one_solve()   # warm up JIT and the allocator; not recorded

rows = Tuple{String,Float64,String}[]
Random.seed!(SEED); onGPU && CUDA.seed!(SEED)
GC.gc(true); onGPU && CUDA.reclaim()
wall = @elapsed e = one_solve()
push!(rows, ("wall_s", wall, "s"))
push!(rows, ("energy", e, "-"))

if onGPU
    Random.seed!(SEED); CUDA.seed!(SEED)
    GC.gc(true); CUDA.reclaim()
    res = CUDA.@profile trace=true one_solve()
    dev, host = res.device, res.host
    gpu_busy = union_span(dev.start, dev.stop)
    host_api = union_span(host.start, host.stop)
    # Timestamps are absolute, so take the span across both traces; an init= on
    # minimum would clamp the start to zero and make the span meaningless.
    allstart = vcat(collect(host.start), collect(dev.start))
    allstop  = vcat(collect(host.stop),  collect(dev.stop))
    prof_wall = isempty(allstart) ? NaN : maximum(allstop) - minimum(allstart)
    push!(rows, ("profiled_wall_s", prof_wall, "s"))
    push!(rows, ("gpu_busy_s", gpu_busy, "s"))
    push!(rows, ("gpu_busy_frac", gpu_busy / prof_wall, "fraction"))
    push!(rows, ("host_cuda_api_s", host_api, "s"))
    push!(rows, ("host_cuda_api_frac", host_api / prof_wall, "fraction"))
    push!(rows, ("batching_cap_x", prof_wall / max(prof_wall - host_api, eps()), "speed-up"))
    push!(rows, ("device_activities", Float64(length(dev.start)), "count"))
    push!(rows, ("host_api_calls", Float64(length(host.start)), "count"))
end

# Allocation attribution: share of sampled bytes from the hottest single line.
Random.seed!(SEED); onGPU && CUDA.seed!(SEED)
GC.gc(true)
Profile.Allocs.clear()
Profile.Allocs.@profile sample_rate=RATE one_solve()
allocs = Profile.Allocs.fetch().allocs
bytes = Dict{String,Int}()
for a in allocs
    st = a.stacktrace
    isempty(st) && continue
    # Skip the profiler's own C frames, and attribute to the innermost line inside
    # the package where possible (that is the line a developer can act on).
    jl = [fr for fr in st if !fr.from_c]
    isempty(jl) && continue
    inpkg = findfirst(fr -> occursin("SpinGlassPEPS", string(fr.file)), jl)
    f = jl[inpkg === nothing ? 1 : inpkg]
    key = string(basename(string(f.file)), ":", f.line, " ", f.func)
    bytes[key] = get(bytes, key, 0) + a.size
end
tot = sum(values(bytes); init = 0)
push!(rows, ("sampled_alloc_bytes", Float64(tot), "bytes"))
push!(rows, ("alloc_sample_rate", RATE, "fraction"))
if tot > 0
    top = sort!(collect(bytes); by = last, rev = true)
    for (i, (k, v)) in enumerate(top[1:min(5, end)])
        @printf("  alloc #%d  %5.1f%%  %s\n", i, 100v / tot, k)
    end
    push!(rows, ("top_alloc_line_frac", first(top)[2] / tot, "fraction"))
end

open(OUT, "w") do io
    println(io, "# ", SPINS, " spins, bond ", BOND, ", ", SPARSITY, ", Zipper/SquareSingleNode, beta=3, ",
                DEVICE, ", seed ", SEED)
    # The top allocation sites, as comments: the value column stays numeric.
    if tot > 0
        for (k, v) in sort!(collect(bytes); by = last, rev = true)[1:min(5, length(bytes))]
            @printf(io, "# alloc %5.1f%% %s\n", 100v / tot, k)
        end
    end
    println(io, "metric,value,unit")
    for (k, v, u) in rows
        @printf(io, "%s,%.6g,%s\n", k, v, u)
    end
end
@printf("== wrote %s (%d metrics)\n", OUT, length(rows))
for (k, v, u) in rows
    @printf("   %-22s %12.6g %s\n", k, v, u)
end
